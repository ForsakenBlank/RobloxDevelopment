--[[
	WaveManager

	Owns the waves inside a single combat area. This is where SpawnWave
	from the design plan lives. It reads the wave list for the area out
	of Game.Data.WaveData, asks EnemySpawner to spawn what the current
	wave asks for, then keeps a count of how many of those enemies are
	still alive.

	Every time one of those enemies dies the count drops. When it hits
	zero (or the wave's NextWaveAtRemaining fraction) it either starts
	the next wave, or if that was the last wave for the area it tells
	RoomManager the area is clear so the gate out can open. The last
	wave always waits for every enemy.

	The count comes from the enemies actually dying, through each
	enemy's own Died signal, rather than from counting models in the
	workspace, because a model lingers for a moment while its death
	plays and that would make the count wrong.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.WaveData for the wave list of the area it was given, and
	  the number of waves so it knows which one is last.
	  Game.Config.GameConfig.Rooms for the out of area and stuck
	  timeouts.
	  Game.Shared.RunConfig for the difficulty's WaveDelay multiplier.

	Calls:
	  Server.Game.Enemies.EnemySpawner with one wave at a time, and the
	  area name so the spawner knows which folder under
	  workspace.MainGameObj.EnemySpawns to use. The spawner calls back
	  for each enemy the moment it exists, so one that dies before the
	  rest of its wave has appeared is still counted.

	Listens to:
	  Each spawned enemy's Died BindableEvent on
	  Server.Game.Enemies.EnemyBase, rather than Humanoid.Died.

	Reports to:
	  Server.Game.Rooms.RoomManager through the OnCleared callback it
	  passes to Start, once the area is clear.

	Sends:
	  ReplicatedStorage.Remotes.Events.WaveStateChanged with the current
	  wave number, the total wave count and the enemies remaining, for
	  ClientGame.Controllers.HUDController to display. Nil values clear
	  the display.

	Summons:
	  Enemies summoned by Server.Game.Enemies.Types.Necromancer are not
	  in the wave list and do not count. A Necromancer's summons die
	  with it, so they can never keep a room open, see Necromancer.

	Enemies that leave the map:
	  One big part in workspace.MainGameObj.KillPlanes, handled by
	  Server.Game.Rooms.KillPlanes, kills anything that falls under the
	  level through EnemyBase so the count still goes down. On top of
	  that, every wave enemy that stays outside its own area's zone for
	  GameConfig.Rooms.OutOfAreaKillTime (thrown through a gap, stuck in
	  a wall) is killed here, so a room can never be left open by one
	  enemy nobody can reach.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local WaveData = require(ReplicatedStorage.Modules.Game.Data.WaveData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local EnemySpawner = require(script.Parent.Parent.Enemies.EnemySpawner)
local RoomZones = require(script.Parent.RoomZones)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WaveStateChanged = Remotes.Events:WaitForChild("WaveStateChanged")

local WaveManager = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

WaveManager.Settings = {
	-- Seconds between the stray enemy checks.
	StrayCheckRate = 1,
}

-- The area currently running, or nil. Only one area runs at a time.
local Current = nil

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function Log(Text: string)
	if GameConfig.Debug.LogWaves then
		print("[WaveManager] " .. Text)
	end
end

local function Send(WaveNumber: number?, WaveTotal: number?, Remaining: number?)
	WaveStateChanged:FireAllClients(WaveNumber, WaveTotal, Remaining)
end

local function WaveDelayMultiplier(): number
	local Run = RunConfig.Get()
	return Run and Run.Difficulty and Run.Difficulty.WaveDelay or 1
end

-- Kills wave enemies that have spent too long outside their area.
local function CheckStrays(State)
	local Limit = GameConfig.Rooms.OutOfAreaKillTime or 0
	local StuckLimit = GameConfig.Rooms.StuckKillTime or 0
	local Now = os.clock()
	for Enemy in pairs(State.Alive) do
		if Enemy.IsDead or not Enemy.Root or not Enemy.Root.Parent then
			continue
		end
		local Position = Enemy.Root.Position

		if Limit > 0 then
			if RoomZones.IsPointInArea(Position, State.AreaName) then
				Enemy.OutOfAreaSince = nil
			else
				Enemy.OutOfAreaSince = Enemy.OutOfAreaSince or Now
				if Now - Enemy.OutOfAreaSince >= Limit then
					Log(Enemy.TypeName .. " left " .. State.AreaName .. ", killing it")
					Enemy:Die(nil)
					continue
				end
			end
		end

		-- Not moved and not hurt for a long time: it is wedged
		-- somewhere. The boss is never removed this way.
		if StuckLimit > 0 and not Enemy.Data.IsBoss then
			local Last = Enemy.LastStrayPosition
			if not Last or (Position - Last).Magnitude > 2 or Enemy.Health ~= Enemy.LastStrayHealth then
				Enemy.LastStrayPosition = Position
				Enemy.LastStrayHealth = Enemy.Health
				Enemy.StillSince = Now
			elseif Now - (Enemy.StillSince or Now) >= StuckLimit then
				Log(Enemy.TypeName .. " stuck in " .. State.AreaName .. ", killing it")
				Enemy:Die(nil)
			end
		end
	end
end

----------------------------------------------------------------------
-- RUN AN AREA
----------------------------------------------------------------------

-- Starts the waves for an area. OnCleared() runs once when the last
-- wave is dead. Returns false if another area is already running.
-- An area with no waves (or Enabled = false) is cleared straight away.
function WaveManager.Start(AreaName: string, OnCleared: () -> ()): boolean
	if Current then
		warn("[WaveManager] " .. Current.AreaName .. " is still running, cannot start " .. AreaName)
		return false
	end

	local Area = WaveData.GetArea(AreaName)
	local Total = WaveData.GetWaveCount(AreaName)
	if not Area or Total == 0 then
		Log(AreaName .. " has no waves, clearing it")
		task.defer(OnCleared)
		return true
	end

	local State = {
		AreaName = AreaName,
		Area = Area,
		Total = Total,
		Wave = 0,
		Alive = {},
		Remaining = 0,
		Stopped = false,
		OnCleared = OnCleared,
	}
	Current = State

	-- Stray check loop for the life of the area.
	task.spawn(function()
		while Current == State and not State.Stopped do
			pcall(CheckStrays, State)
			task.wait(WaveManager.Settings.StrayCheckRate)
		end
	end)

	task.spawn(function()
		for Index, Wave in ipairs(Area.Waves) do
			if State.Stopped then
				return
			end
			State.Wave = Index
			local IsLast = Index == Total

			-- Wave 1 follows the room entry countdown, the rest wait
			-- their delay.
			if Index > 1 then
				local Delay = (Wave.Delay or WaveData.Defaults.DelayBetweenWaves) * WaveDelayMultiplier()
				Send(Index, Total, nil)
				task.wait(Delay)
				if State.Stopped then
					return
				end
			end

			local Count = WaveData.CountEnemies(Wave)
			local Dead = 0
			local Threshold = IsLast and Count or math.ceil(Count * (WaveData.Defaults.NextWaveAtRemaining or 1))
			local Done = Instance.new("BindableEvent")
			State.Done = Done
			local Finished = false
			State.Remaining = Count
			Send(Index, Total, Count)
			Log(string.format("%s wave %d/%d, %d enemies", AreaName, Index, Total, Count))

			local function OnDeath()
				if State.Stopped then
					return
				end
				Dead += 1
				State.Remaining = math.max(0, State.Remaining - 1)
				Send(Index, Total, State.Remaining)
				if not Finished and Dead >= Threshold then
					Finished = true
					Done:Fire()
				end
			end

			local Spawned = 0
			EnemySpawner.SpawnWave(AreaName, Wave, function(Enemy)
				Spawned += 1
				State.Alive[Enemy] = true
				Enemy.Died.Event:Once(function()
					State.Alive[Enemy] = nil
					OnDeath()
				end)
			end, function()
				return State.Stopped
			end)

			if State.Stopped then
				return
			end

			-- Anything the spawner could not create (a missing model, a
			-- disabled type) counts as already dead so the wave can end.
			for _ = 1, Count - Spawned do
				OnDeath()
			end

			if not Finished then
				Done.Event:Wait()
			end
			Done:Destroy()
			if State.Stopped then
				return
			end
		end

		-- The last wave used the full count, but an earlier wave that
		-- moved on early can still have stragglers. Wait for them.
		while not State.Stopped and next(State.Alive) ~= nil do
			Send(State.Total, State.Total, (function()
				local N = 0
				for _ in pairs(State.Alive) do
					N += 1
				end
				return N
			end)())
			task.wait(0.5)
		end
		if State.Stopped then
			return
		end

		Log(AreaName .. " cleared")
		Current = nil
		Send(nil, nil, nil)
		State.OnCleared()
	end)

	return true
end

-- Stops the current area without clearing it, for a run ending. The
-- enemies themselves are removed by RunManager.
function WaveManager.Stop()
	if Current then
		Current.Stopped = true
		-- Wake the wave thread if it is waiting on deaths, so it can
		-- see it was stopped and end.
		if Current.Done and Current.Done.Parent == nil then
			pcall(function()
				Current.Done:Fire()
			end)
		end
		Current = nil
	end
	Send(nil, nil, nil)
end

function WaveManager.IsRunning(): boolean
	return Current ~= nil
end

function WaveManager.GetCurrentArea(): string?
	return Current and Current.AreaName or nil
end

return WaveManager
