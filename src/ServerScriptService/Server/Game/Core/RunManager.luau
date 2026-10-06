--[[
	RunManager

	The state machine for a whole run. It owns which state the run is in
	(waiting for players, playing, won, lost, resetting) and it is the
	only module allowed to change that state. Everything else asks it
	what state the run is in rather than keeping its own copy. Which
	area the run is in, and whether that is a room, a shop or the boss,
	is RoomManager's, and is sent along with the state.

	It handles starting the run once RunSetup says the players are ready,
	ending the run in a win when the boss dies, and ending it in a loss
	when every player is dead. On either ending it works out what each
	player earned (EXP and Cash), saves it with the lifetime stats, and
	sends the result to the clients. Then it waits: nothing restarts
	until half the players (rounded up, so one in a solo run and two out
	of four) vote to play again with the Replay button, and any player
	can leave with the Back to Lobby button.

	Multiplayer rule from the design: the run only ends when every player
	is dead, not the first one. A single dead player comes back as a
	spectator (see PlayerStats) and waits for the others, and is revived
	when the area is cleared if GameConfig.Multiplayer.ReviveOnAreaClear
	is on.
]]

--[[
	What connects to this

	Started by:
	  Server.Game.Core.RunSetup, after RunConfig is filled in, through
	  RunManager.Start.

	Talks to:
	  Server.Game.Rooms.RoomManager, which runs the walk through the
	  areas. RunManager starts and resets it, and listens to its
	  AreaStarted, AreaCleared and RunWon signals. RunManager does not
	  read RoomData itself.
	  Server.Game.Core.PlayerStats, whose Died signal is how it notices
	  deaths, and whose IsAlive is checked to see whether every player is
	  dead.
	  Server.Game.Rooms.RoomZones, through RoomManager.PlacePlayer, to put
	  a respawned spectator or a late joiner in the area the run is in.

	Sends:
	  ReplicatedStorage.Remotes.Events.RunStateChanged on every state
	  change, with a copy of RunConfig plus State, Area, AreaKind, Result
	  and Summary. HUDController reads the RunConfig half,
	  RoomBannerController the rest. It also answers
	  ReplicatedStorage.Remotes.Functions.GetRunState for a client that
	  joins or reloads late.
	  ReplicatedStorage.Remotes.Events.Notify for "X has fallen" and
	  revive messages.

	At the end of a run:
	  Writes the lifetime stats back through
	  ServerScriptService.Server.Modules.DataManager with Set and
	  Increment, using TotalRuns, RunsWon, TotalKills, BestRoom and Cash
	  from ReplicatedStorage.Modules.Shared.PlayerDataTemplate.
	  Clears every PlayerStats and Loadout object (by building fresh
	  ones), every active effect in StatusEffectService, and everything
	  still in workspace.Runtime.Enemies and workspace.Runtime.Projectiles.
	  Tells RoomManager to reset, which closes and locks every gate.

	Sending players back to the lobby place is Server.Game.Core.LobbyLink.
	GameConfig.Run.AfterRun "Vote" is the vote above. "Restart" and
	"Lobby" skip the vote and restart in place, or send everyone to the
	lobby, after GameConfig.Run.EndDelay. A player can also leave in the
	middle of a run with the "Back to lobby" button; their stats are
	saved first.

	Listens on:
	  ReplicatedStorage.Remotes.Events.RunVote with "Replay" or "Lobby",
	  from ClientGame.Controllers.RoomBannerController's end screen.

	A player leaving mid run is handled: their stats and loadout are
	removed on PlayerRemoving, and the all dead check only looks at
	players still in the game, so the run never hangs waiting on someone
	who is not there.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)
local PlayerStats = require(script.Parent.PlayerStats)
local Loadout = require(script.Parent.Loadout)
local LobbyLink = require(script.Parent.LobbyLink)
local RoomManager = require(script.Parent.Parent.Rooms.RoomManager)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RunStateChanged = Remotes.Events:WaitForChild("RunStateChanged")
local GetRunState = Remotes.Functions:WaitForChild("GetRunState")
local Notify = Remotes.Events:WaitForChild("Notify")

local RunManager = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

RunManager.Settings = {
	-- Seconds after the reset before the new run starts, so every
	-- character has respawned first.
	RestartDelay = 1.5,
	-- Fraction of the money a player ends a run with that becomes Cash,
	-- the carry over currency for the lobby. 0 turns it off.
	CashFromRunMoney = 0.25,
	-- Seconds after a spectator's character spawns before it is moved
	-- to the area the run is in, so the character has finished loading.
	SpectatorPlaceDelay = 0.2,
	-- Seconds to wait for a lobby teleport to take everyone before
	-- restarting the run for whoever is still here.
	LobbyTeleportTimeout = 20,
	-- EXP a player earns from a run: per kill, per area reached (Spawn
	-- is area 1), and on top for winning. A lost run only pays
	-- ExpLossMultiplier of that, so finishing is always worth far more.
	ExpPerKill = 1,
	ExpPerArea = 6,
	ExpForWin = 50,
	ExpLossMultiplier = 0.5,
	-- Fraction of the players still here who have to vote Replay, rounded
	-- up. 0.5 means 1 of 1, 1 of 2, 2 of 3, 2 of 4.
	ReplayVoteFraction = 0.5,
}

-- Fired with (NewState, OldState) on every change.
RunManager.StateChanged = Instance.new("BindableEvent")

local State = "Waiting"
local Result: string? = nil
local Kills: { [Player]: number } = {}
local BestIndex: { [Player]: number } = {}
local Summary = nil
local Generation = 0

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

-- The table the clients get: RunConfig plus where the run is.
function RunManager.GetPayload()
	local Payload = {}
	local Run = RunConfig.IsSet() and RunConfig.Get() or nil
	if Run then
		for Key, Value in pairs(Run) do
			Payload[Key] = Value
		end
	end
	local Room = RoomManager.GetState()
	Payload.State = State
	Payload.Area = Room.Area
	Payload.AreaKind = Room.Kind
	Payload.AreaPhase = Room.Phase
	Payload.Result = Result
	Payload.Summary = Summary
	Payload.HasLobby = LobbyLink.HasLobby()
	Payload.Votes, Payload.VotesNeeded = RunManager.GetVotes()
	Payload.AfterRun = GameConfig.Run.AfterRun
	return Payload
end

local function Broadcast()
	RunStateChanged:FireAllClients(RunManager.GetPayload())
end

local function SetState(NewState: string)
	local Old = State
	State = NewState
	RunManager.StateChanged:Fire(NewState, Old)
	Broadcast()
end

function RunManager.GetState(): string
	return State
end

function RunManager.IsPlaying(): boolean
	return State == "Playing"
end

----------------------------------------------------------------------
-- PLAYERS
----------------------------------------------------------------------

local function LivingPlayers(): { Player }
	local List = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		local Stats = PlayerStats.Get(Player)
		if Stats and Stats:IsAlive() then
			table.insert(List, Player)
		end
	end
	return List
end

-- Puts a player's new character in the area the run is in, if the
-- run has moved past the first area.
local function OnCharacterAdded(Player: Player, Character: Model)
	if State ~= "Playing" then
		return
	end
	local Area = RoomManager.GetCurrentArea()
	if not Area or RoomManager.GetCurrentIndex() <= 1 then
		return
	end
	local Root = Character:WaitForChild("HumanoidRootPart", 10)
	if not Root then
		return
	end
	task.wait(RunManager.Settings.SpectatorPlaceDelay)
	if Player.Character == Character and State == "Playing" then
		RoomManager.PlacePlayer(Player, Area, 1)
	end
end

local function WatchPlayer(Player: Player)
	Player.CharacterAdded:Connect(function(Character)
		OnCharacterAdded(Player, Character)
	end)
end

local function CheckAllDead()
	if State ~= "Playing" then
		return
	end
	if #Players:GetPlayers() == 0 then
		return
	end
	if #LivingPlayers() == 0 then
		RunManager.End("Lost")
	end
end

local function OnPlayerDied(Player: Player, Source)
	if State ~= "Playing" then
		return
	end
	Notify:FireAllClients(Player.DisplayName .. " has fallen!")
	if GameConfig.Multiplayer.RunEndsWhenAllDead then
		CheckAllDead()
	else
		RunManager.End("Lost")
	end
end

local function ReviveDead()
	for _, Player in ipairs(Players:GetPlayers()) do
		local Stats = PlayerStats.Get(Player)
		if Stats and not Stats:IsAlive() then
			Stats:Revive(GameConfig.Multiplayer.ReviveHealthPercent)
			Notify:FireClient(Player, "You have been revived!")
		end
	end
end

----------------------------------------------------------------------
-- AREAS
----------------------------------------------------------------------

local function OnAreaStarted(AreaName: string, Area)
	local Index = RoomData.GetIndex(AreaName) or 0
	for _, Player in ipairs(LivingPlayers()) do
		BestIndex[Player] = math.max(BestIndex[Player] or 0, Index)
	end
	Broadcast()
end

local function OnAreaCleared(AreaName: string, Area)
	if State ~= "Playing" then
		return
	end
	local Bonus = GameConfig.Rewards.AreaClearBonus or 0
	if Area.Kind == "Boss" then
		Bonus += GameConfig.Rewards.BossKillBonus or 0
	end
	if Bonus > 0 then
		for _, Stats in pairs(PlayerStats.GetAll()) do
			Stats:AddMoney(Bonus)
		end
	end
	if GameConfig.Multiplayer.ReviveOnAreaClear then
		ReviveDead()
	end
end

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------

-- Starts the first run. RunSetup calls this once the difficulty and
-- player count are locked in.
function RunManager.Start()
	if State ~= "Waiting" then
		return
	end
	-- From here death is handled by the run, a dead player waits as
	-- a spectator instead of popping back to full health.
	PlayerStats.Settings.ReviveOnRespawn = false
	Result = nil
	Summary = nil
	Kills = {}
	BestIndex = {}
	RoomManager.Start()
	SetState("Playing")
end

-- Players whose stats for this run are already saved, so leaving
-- early and the run ending never both pay out.
local Saved: { [Player]: boolean } = {}
local CashEarned: { [Player]: number } = {}
local ExpEarned: { [Player]: number } = {}
-- Players who have pressed Replay on the end screen.
local Votes: { [Player]: boolean } = {}

-- Works out what a player earned this run. Saved once, the numbers are
-- kept for the end screen.
local function SavePlayer(Player: Player, Won: boolean)
	if Saved[Player] then
		return
	end
	Saved[Player] = true
	local Settings = RunManager.Settings
	local Stats = PlayerStats.Get(Player)
	local Best = BestIndex[Player] or 0
	local Cash = Stats and math.floor(Stats:GetMoney() * Settings.CashFromRunMoney) or 0
	local Exp = (Kills[Player] or 0) * Settings.ExpPerKill + Best * Settings.ExpPerArea + (Won and Settings.ExpForWin or 0)
	if not Won then
		Exp = math.floor(Exp * Settings.ExpLossMultiplier)
	end
	CashEarned[Player] = Cash
	ExpEarned[Player] = Exp

	if not DataManager.IsLoaded(Player) then
		return
	end
	DataManager.Increment(Player, "TotalRuns", 1)
	if Won then
		DataManager.Increment(Player, "RunsWon", 1)
	end
	DataManager.Increment(Player, "TotalKills", Kills[Player] or 0)
	if Best > (DataManager.Get(Player, "BestRoom") or 0) then
		DataManager.Set(Player, "BestRoom", Best)
	end
	if Cash > 0 then
		DataManager.Increment(Player, "Cash", Cash)
	end
	if Exp > 0 then
		DataManager.Increment(Player, "XP", Exp)
	end
end

local function SaveLifetimeStats(Won: boolean)
	local Lines = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		SavePlayer(Player, Won)
		local Stats = PlayerStats.Get(Player)
		table.insert(Lines, {
			Name = Player.DisplayName,
			UserId = Player.UserId,
			Kills = Kills[Player] or 0,
			Money = Stats and Stats:GetMoney() or 0,
			Exp = ExpEarned[Player] or 0,
			Cash = CashEarned[Player] or 0,
		})
	end
	return Lines
end

-- What a player takes back to the lobby.
local function LobbyPayload(Player: Player, RunResult: string?)
	local Stats = PlayerStats.Get(Player)
	return {
		Result = RunResult,
		ReachedArea = Summary and Summary.ReachedArea or RoomManager.GetState().Area,
		Kills = Kills[Player] or 0,
		Money = Stats and Stats:GetMoney() or 0,
		CashEarned = CashEarned[Player] or 0,
		ExpEarned = ExpEarned[Player] or 0,
	}
end

----------------------------------------------------------------------
-- VOTING
----------------------------------------------------------------------

-- How many have voted Replay, and how many it takes.
function RunManager.GetVotes(): (number, number)
	local Count = 0
	for Player in pairs(Votes) do
		if Player.Parent == Players then
			Count += 1
		end
	end
	local Needed = math.max(1, math.ceil(#Players:GetPlayers() * RunManager.Settings.ReplayVoteFraction))
	return Count, Needed
end

local function CheckVotes()
	if State ~= "Won" and State ~= "Lost" then
		return
	end
	local Count, Needed = RunManager.GetVotes()
	if Count >= Needed and #Players:GetPlayers() > 0 then
		RunManager.Reset()
	end
end

local function OnVote(Player: Player, Choice: any)
	if State ~= "Won" and State ~= "Lost" then
		return
	end
	if Choice == "Replay" then
		if Votes[Player] then
			return
		end
		Votes[Player] = true
		local Count, Needed = RunManager.GetVotes()
		Notify:FireAllClients(string.format("%s wants to play again (%d/%d)", Player.DisplayName, Count, Needed))
		Broadcast()
		CheckVotes()
	elseif Choice == "Lobby" then
		if not LobbyLink.HasLobby() then
			Notify:FireClient(Player, "The lobby isn't connected yet")
			return
		end
		task.spawn(function()
			local Sent = LobbyLink.SendToLobby({ Player }, function(Who)
				return LobbyPayload(Who, Result)
			end)
			if not Sent and Player.Parent == Players then
				Notify:FireClient(Player, "Couldn't reach the lobby, try again")
			end
		end)
	end
end

-- Ends the run. Result is "Won" or "Lost".
function RunManager.End(NewResult: string)
	if State ~= "Playing" then
		return
	end
	Result = NewResult
	Generation += 1
	local MyGeneration = Generation
	Votes = {}

	local Room = RoomManager.GetState()
	Summary = {
		Players = SaveLifetimeStats(NewResult == "Won"),
		ReachedArea = Room.Banner or Room.Area,
		EndDelay = GameConfig.Run.EndDelay,
		ToLobby = RunManager.WillReturnToLobby(),
	}
	SetState(NewResult)

	-- With voting, nothing happens until the votes are in.
	local Mode = GameConfig.Run.AfterRun
	if Mode ~= "Restart" and Mode ~= "Lobby" then
		return
	end

	task.delay(GameConfig.Run.EndDelay, function()
		if Generation ~= MyGeneration then
			return
		end
		if RunManager.WillReturnToLobby() then
			local Sent = LobbyLink.SendToLobby(Players:GetPlayers(), function(Player)
				return LobbyPayload(Player, NewResult)
			end)
			if Sent then
				-- Anyone the teleport did not take still gets a new run.
				task.wait(RunManager.Settings.LobbyTeleportTimeout)
				if Generation ~= MyGeneration or #Players:GetPlayers() == 0 then
					return
				end
			end
		end
		RunManager.Reset()
	end)
end

-- Whether the end of this run sends everyone to the lobby, from
-- GameConfig.Run.AfterRun.
function RunManager.WillReturnToLobby(): boolean
	return GameConfig.Run.AfterRun == "Lobby" and LobbyLink.HasLobby()
end

-- Clears the whole run and starts a new one in place.
function RunManager.Reset()
	Generation += 1
	local MyGeneration = Generation
	SetState("Resetting")

	RoomManager.Reset()

	local Game = script.Parent.Parent
	local EnemyBase = require(Game.Enemies.EnemyBase)
	local ProjectileService = require(Game.Combat.ProjectileService)
	local StatusEffectService = require(Game.Effects.StatusEffectService)
	EnemyBase.ClearAll()
	ProjectileService.ClearAll()
	StatusEffectService.ClearAll()
	local Runtime = workspace:FindFirstChild("Runtime")
	if Runtime then
		for _, FolderName in ipairs({ "Enemies", "Projectiles" }) do
			local Folder = Runtime:FindFirstChild(FolderName)
			if Folder then
				Folder:ClearAllChildren()
			end
		end
	end

	-- Fresh stats and loadout, then a fresh character at Spawn.
	local RunSetup = require(script.Parent.RunSetup)
	for _, Player in ipairs(Players:GetPlayers()) do
		RunSetup.ResetPlayer(Player)
		-- A player who died moments ago is about to be respawned by
		-- Roblox anyway, and loading one now as well spawns them twice.
		local Humanoid = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
		local RespawnPending = Players.CharacterAutoLoads and Humanoid ~= nil and Humanoid.Health <= 0
		if not RespawnPending then
			task.spawn(function()
				pcall(Player.LoadCharacter, Player)
			end)
		end
	end

	Result = nil
	Summary = nil
	Kills = {}
	BestIndex = {}
	Saved = {}
	CashEarned = {}
	ExpEarned = {}
	Votes = {}

	task.delay(RunManager.Settings.RestartDelay, function()
		if Generation ~= MyGeneration then
			return
		end
		RoomManager.Start()
		SetState("Playing")
	end)
end

function RunManager.Init()
	GetRunState.OnServerInvoke = function()
		return RunManager.GetPayload()
	end

	PlayerStats.Died.Event:Connect(OnPlayerDied)
	RoomManager.AreaStarted.Event:Connect(OnAreaStarted)
	RoomManager.AreaCleared.Event:Connect(OnAreaCleared)
	RoomManager.RunWon.Event:Connect(function()
		RunManager.End("Won")
	end)

	local DamageService = require(script.Parent.Parent.Combat.DamageService)
	DamageService.EnemyKilled.Event:Connect(function(Enemy, Killer)
		if Killer then
			Kills[Killer] = (Kills[Killer] or 0) + 1
			-- Kills refuel abilities a little, so fighting keeps them
			-- coming. A summon gives less, the same as its money.
			local Stats = PlayerStats.Get(Killer)
			local Energy = (GameConfig.Player.EnergyPerKill or 0) * (Enemy.RewardMultiplier or 1)
			if Stats and Stats:IsAlive() and Energy > 0 then
				Stats:AddEnergy(Energy)
			end
		end
	end)

	Players.PlayerAdded:Connect(WatchPlayer)
	for _, Player in ipairs(Players:GetPlayers()) do
		WatchPlayer(Player)
	end
	-- "Back to lobby" in the middle of a run: save what they earned,
	-- then send them.
	LobbyLink.PlayerLeaving.Event:Connect(function(Player)
		if State == "Playing" then
			SavePlayer(Player, false)
		end
		task.spawn(function()
			LobbyLink.SendToLobby({ Player }, function()
				return LobbyPayload(Player, "Left")
			end)
		end)
	end)

	-- The end screen's Replay and Back to Lobby buttons.
	local RunVote = Remotes.Events:FindFirstChild("RunVote")
	if not RunVote then
		RunVote = Instance.new("RemoteEvent")
		RunVote.Name = "RunVote"
		RunVote.Parent = Remotes.Events
	end
	local RemoteGuard = require(ServerScriptService.Server.Modules.AntiCheat.RemoteGuard)
	RemoteGuard.BindEvent(RunVote, { Rate = 3, Burst = 3 }, OnVote)

	Players.PlayerRemoving:Connect(function(Player)
		Saved[Player] = nil
		CashEarned[Player] = nil
		ExpEarned[Player] = nil
		Votes[Player] = nil
		-- One fewer player can mean enough votes now.
		task.defer(CheckVotes)
		PlayerStats.Remove(Player)
		Loadout.Remove(Player)
		Kills[Player] = nil
		BestIndex[Player] = nil
		-- The leaver may have been the last one alive, or the last one
		-- keeping the others waiting.
		task.defer(CheckAllDead)
	end)
end

return RunManager
