--[[
	RunSetup

	Works out the settings for this run and writes them once into
	Game.Shared.RunConfig. It falls back to "Normal" difficulty and a
	live count of players, looks the difficulty up in DifficultyConfig,
	works out the enemy health multiplier from the player count, and
	stores the finished table.

	It also creates the per player objects: a Server.Game.Core.
	PlayerStats for the health, energy and money, and a
	Server.Game.Core.Loadout built from the 2 weapons and 2 abilities in
	that player's saved data.

	It also decides when the run is allowed to start. In a multiplayer
	session everyone arriving does not happen at the same instant, so it
	should wait for the expected party size or for a short timeout,
	whichever comes first, before telling RunManager to begin. Otherwise
	the first player in gets a run scaled for one player.
]]

--[[
	What connects to this

	Reads:
	  Server.Game.Core.TeleportDataReader for the difficulty, the party
	  size and each player's loadout, when the players came from the
	  lobby. Opened straight from Studio there is none, and the fallback
	  (Normal, a live count of players, the saved loadout) runs.
	  Game.Config.DifficultyConfig to turn the difficulty name into its
	  multipliers. Until the lobby has a difficulty picker this is always
	  "Normal".
	  Game.Config.GameConfig for the +0.5x per player value.
	  ServerScriptService.Server.Modules.DataManager for each player's
	  saved loadout, which is what Game.Core.Loadout is built from. It
	  has to wait for DataManager.IsLoaded rather than reading straight
	  away, or a slow load gives the player a default loadout instead of
	  the one they picked.

	Writes:
	  Game.Shared.RunConfig, once, and it is the only module that writes
	  there.

	Creates:
	  Server.Game.Core.PlayerStats and Server.Game.Core.Loadout, one of
	  each per player.

	Calls:
	  Server.Game.Core.RunManager to start the run once the players are
	  in and the config is set.

	Sends:
	  ReplicatedStorage.Remotes.Events.RunStateChanged with a copy of the
	  finished RunConfig, so the client knows the difficulty and player
	  count. It also needs to answer
	  ReplicatedStorage.Remotes.Functions.GetRunState for a client that
	  asks late.

	Once the player count is written to RunConfig it must not change,
	even if someone leaves. StatFormulas reads it for every calculation
	and enemies already alive were scaled with the old value.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)
local WeaponData = require(ReplicatedStorage.Modules.Game.Data.WeaponData)
local AbilityData = require(ReplicatedStorage.Modules.Game.Data.AbilityData)
local PlayerStats = require(script.Parent.PlayerStats)
local Loadout = require(script.Parent.Loadout)
local TeleportDataReader = require(script.Parent.TeleportDataReader)
local RunStats = require(script.Parent.RunStats)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RunStateChanged = Remotes.Events:WaitForChild("RunStateChanged")
local GetRunState = Remotes.Functions:WaitForChild("GetRunState")

local RunSetup = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

RunSetup.Settings = {
	-- Seconds to wait for the rest of a party to arrive before the
	-- player count is locked in, when there is no teleport data saying
	-- how big the party is. With teleport data the wait is
	-- GameConfig.Lobby.PartyWaitTimeout, and ends early once everyone
	-- the lobby sent is here.
	PartyWaitTimeout = 5,
	-- The same wait when playtesting in Studio, where there is no
	-- party to wait for and a 5 second blank HUD is just annoying.
	StudioPartyWaitTimeout = 0.5,
	-- Seconds to wait for a player's save to load before giving up
	-- and building their stats from the defaults.
	DataLoadTimeout = 20,
}

local Started = false
local SetupPlayers: { [Player]: boolean } = {}
-- the difficulty the run was locked in with, for recounting players
local LockedDifficulty: string? = nil
local LockedFromLobby = false

----------------------------------------------------------------------
-- PER PLAYER
----------------------------------------------------------------------

-- Waits for the save, then builds the run objects for one player.
-- Safe to call twice, the second call does nothing.
function RunSetup.SetupPlayer(Player: Player)
	if SetupPlayers[Player] then
		return
	end
	SetupPlayers[Player] = true

	local Deadline = os.clock() + RunSetup.Settings.DataLoadTimeout
	while not DataManager.IsLoaded(Player) and os.clock() < Deadline do
		if Player.Parent ~= Players then
			SetupPlayers[Player] = nil
			return
		end
		task.wait(0.1)
	end

	if not DataManager.IsLoaded(Player) then
		warn("[RunSetup] " .. Player.Name .. "'s data did not load in time, using default stats")
	else
		RunSetup.ApplyTeleportLoadout(Player)
	end

	-- gear, core and passes from the save, through the lobby's CharacterStats
	RunStats.Compute(Player)
	RunStats.Apply(Player, PlayerStats.new(Player, RunStats.Overrides(Player)))

	-- The two weapons and two abilities from the player's save.
	Loadout.new(Player)

	local RunManager = require(script.Parent.RunManager)
	RunStateChanged:FireClient(Player, RunManager.GetPayload())
end

-- Builds fresh run objects for a player whose save is already loaded,
-- for RunManager restarting the run in place. The old PlayerStats and
-- Loadout are destroyed by their constructors.
function RunSetup.ResetPlayer(Player: Player)
	if Player.Parent ~= Players then
		return
	end
	RunStats.Apply(Player, PlayerStats.new(Player, RunStats.Overrides(Player)))
	Loadout.new(Player)
end

-- The lobby can send each player's loadout in the teleport data, in
-- case their save has not caught up yet. A valid one is written into
-- the save, so Loadout reads it like any other.
function RunSetup.ApplyTeleportLoadout(Player: Player)
	local Chosen = TeleportDataReader.GetLoadout(Player)
	if not Chosen then
		return
	end
	local W1, W2 = Chosen.Weapons[1], Chosen.Weapons[2]
	local A1, A2 = Chosen.Abilities[1], Chosen.Abilities[2]
	local Valid = WeaponData.Weapons[W1] and WeaponData.Weapons[W2] and AbilityData.Abilities[A1] and AbilityData.Abilities[A2]
		and W1 ~= W2 and A1 ~= A2
	if not Valid then
		warn("[RunSetup] " .. Player.Name .. " arrived with a loadout that is not valid, using their save instead")
		return
	end
	DataManager.Set(Player, "Weapon1", W1)
	DataManager.Set(Player, "Weapon2", W2)
	DataManager.Set(Player, "Ability1", A1)
	DataManager.Set(Player, "Ability2", A2)
end

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------

-- Locks in the difficulty and player count, tells every client, and
-- sets up everyone who is already here.
local function LockIn()
	if Started then
		return
	end
	Started = true

	-- The lobby's settings if the players came from it, otherwise the
	-- fallback. The player count is always who actually arrived.
	local LobbyData = TeleportDataReader.GetRunData()
	local DifficultyName = LobbyData and LobbyData.Difficulty or GameConfig.Run.DefaultDifficulty
	local PlayerCount = #Players:GetPlayers()

	local Settings = RunConfig.Build(DifficultyName, PlayerCount)
	Settings.FromLobby = LobbyData ~= nil
	LockedDifficulty = DifficultyName
	LockedFromLobby = Settings.FromLobby
	RunConfig.Set(Settings)

	local Run = RunConfig.Get()
	print(string.format("[RunSetup] run locked in: %s, %d player(s), enemy health x%.2f", Run.DifficultyName, Run.PlayerCount, Run.EnemyHealthMultiplier))

	for _, Player in ipairs(Players:GetPlayers()) do
		task.spawn(RunSetup.SetupPlayer, Player)
	end

	-- Required here rather than at the top, because RunManager
	-- requires this module for ResetPlayer.
	require(script.Parent.RunManager).Start()
end

-- Counts the players again while it is safe to: in Spawn, before any
-- enemy has been scaled, or when a run restarts (AllowLower). A friend
-- who loads in a few seconds late then still gets a run scaled for
-- them.
function RunSetup.Recount(AllowLower: boolean?)
	if not Started or not RunConfig.IsSet() then
		return
	end
	local RoomManager = require(script.Parent.Parent.Rooms.RoomManager)
	if not AllowLower and RoomManager.GetCurrentIndex() > 1 then
		return
	end
	local Count = math.max(1, #Players:GetPlayers())
	local Old = RunConfig.Get()
	if Count == Old.PlayerCount or (Count < Old.PlayerCount and not AllowLower) then
		return
	end
	local Settings = RunConfig.Build(LockedDifficulty, Count)
	Settings.FromLobby = LockedFromLobby
	RunConfig.Set(Settings)
	print(string.format("[RunSetup] player count is now %d, enemy health x%.2f", Settings.PlayerCount, Settings.EnemyHealthMultiplier))
	local RunManager = require(script.Parent.RunManager)
	RunStateChanged:FireAllClients(RunManager.GetPayload())
end

function RunSetup.Init()
	-- RunManager replaces this with the full run state when it starts.
	GetRunState.OnServerInvoke = function()
		return RunConfig.IsSet() and RunConfig.Get() or nil
	end

	Players.PlayerAdded:Connect(function(Player)
		if Started then
			-- A late joiner still gets stats. The player count is only
			-- recounted while the run is still in Spawn.
			task.spawn(RunSetup.SetupPlayer, Player)
			RunSetup.Recount(false)
		end
	end)

	Players.PlayerRemoving:Connect(function(Player)
		SetupPlayers[Player] = nil
	end)

	-- Wait for the first player, then give the rest of the party time
	-- to arrive, then lock in. With lobby data the wait ends as soon as
	-- everyone the lobby sent is here.
	task.spawn(function()
		while #Players:GetPlayers() == 0 do
			task.wait(0.25)
		end

		local LobbyData = TeleportDataReader.GetRunData()
		local Expected = LobbyData and LobbyData.PartySize or nil
		local Timeout = RunSetup.Settings.PartyWaitTimeout
		if Expected then
			Timeout = GameConfig.Lobby.PartyWaitTimeout
		elseif RunService:IsStudio() then
			Timeout = RunSetup.Settings.StudioPartyWaitTimeout
		end

		local Deadline = os.clock() + Timeout
		while os.clock() < Deadline do
			if Expected and #Players:GetPlayers() >= Expected then
				break
			end
			task.wait(0.25)
		end
		LockIn()
	end)
end

-- Whether the run has been locked in yet.
function RunSetup.IsStarted(): boolean
	return Started
end

return RunSetup
