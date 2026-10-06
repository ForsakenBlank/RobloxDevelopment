--[[
	RunConfig

	Holds the settings this particular run is using, once they have been
	worked out. That is the difficulty name, the difficulty entry that
	was looked up, the number of players the run started with, and the
	enemy health multiplier that came out of the player count.

	This is deliberately separate from Game.Config.GameConfig.
	GameConfig is the fixed numbers that never change. RunConfig is the
	values that are only known once the server has started and the
	players have arrived from the lobby.

	It is a plain module with a get and a set, not a class, because there
	is only ever one run per server.
]]

--[[
	What connects to this

	Server.Game.Core.RunSetup is the only thing allowed to write to this.
	It builds the table from what Server.Game.Core.TeleportDataReader
	found and the entry it looked up in Game.Config.DifficultyConfig,
	then calls the setter once.

	Server reads:
	  Game.Shared.StatFormulas needs the player count and the difficulty
	  multipliers for every calculation it does.
	  Server.Game.Enemies.EnemyBase reads it when scaling a spawned
	  enemy.
	  Server.Game.Shop.ShopManager reads the price multiplier.

	Client reads:
	  The server sends a copy down on
	  ReplicatedStorage.Remotes.Events.RunStateChanged, and a late
	  joining client can ask for it with
	  ReplicatedStorage.Remotes.Functions.GetRunState.
	  ClientGame.Controllers.HUDController shows the difficulty name.

	The client copy is read only. This module is in ReplicatedStorage so
	the type is shared, but the client setter should refuse to run, since
	a client writing to it would only change its own view and make the
	two sides disagree.

	Until the lobby is passing teleport data, the player count should
	come from counting Players and the difficulty should default to
	"Normal".
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local DifficultyConfig = require(ReplicatedStorage.Modules.Game.Config.DifficultyConfig)
local Types = require(ReplicatedStorage.Modules.Game.Shared.Types)

local RunConfig = {}

-- Fired on the server whenever Set runs, so anything that cached a
-- value can refresh. The client gets RunStateChanged instead.
RunConfig.Changed = Instance.new("BindableEvent")

local Current: Types.RunSettings? = nil

-- Works out the multiplier from a player count using the GameConfig
-- rule, so RunSetup and StatFormulas never disagree about it.
local function PlayerMultiplier(PlayerCount: number, PerExtraPlayer: number): number
	return 1 + math.max(PlayerCount - 1, 0) * PerExtraPlayer
end

-- Builds a full settings table from a difficulty name and a player
-- count. Does not store it, so the server can build one and inspect
-- it before committing, and the client can build a local one from
-- what the server sent.
function RunConfig.Build(DifficultyName: string?, PlayerCount: number): Types.RunSettings
	local Name = DifficultyName or GameConfig.Run.DefaultDifficulty
	local Difficulty = DifficultyConfig.Get(Name)
	local Multiplayer = GameConfig.Multiplayer

	return {
		DifficultyName = Difficulty.DisplayName,
		Difficulty = Difficulty,
		PlayerCount = math.max(PlayerCount, 1),
		EnemyHealthMultiplier = PlayerMultiplier(PlayerCount, Multiplayer.EnemyHealthPerExtraPlayer),
		EnemyDamageMultiplier = PlayerMultiplier(PlayerCount, Multiplayer.EnemyDamagePerExtraPlayer),
		StartedAt = os.time(),
	}
end

-- Stores the settings for this run. Server only, called once by
-- RunSetup. A second call replaces the first and fires Changed, which
-- is intended for a restart in the same server.
function RunConfig.Set(Settings: Types.RunSettings)
	if RunService:IsClient() then
		warn("[RunConfig] the client cannot set run settings, use RunConfig.SetFromServer with the remote copy")
		return
	end
	Current = Settings
	RunConfig.Changed:Fire(Settings)
end

-- The client's way in. Takes the copy the server sent over
-- RunStateChanged or GetRunState and keeps it for reads.
function RunConfig.SetFromServer(Settings: Types.RunSettings)
	if RunService:IsServer() then
		warn("[RunConfig] SetFromServer is for the client, the server should call Set")
		return
	end
	Current = Settings
	RunConfig.Changed:Fire(Settings)
end

-- The current settings. On the server, before RunSetup has run, this
-- falls back to a build from the default difficulty and the current
-- player count with a warning, so nothing errors on a direct join in
-- Studio. On the client it is nil until the server copy arrives.
function RunConfig.Get(): Types.RunSettings?
	if Current then
		return Current
	end
	if RunService:IsServer() then
		warn("[RunConfig] Get called before RunSetup, using defaults")
		Current = RunConfig.Build(nil, #game:GetService("Players"):GetPlayers())
		return Current
	end
	return nil
end

-- true once a run has been set up on this side.
function RunConfig.IsSet(): boolean
	return Current ~= nil
end

-- Clears the stored settings. RunManager calls this when a run ends.
function RunConfig.Clear()
	Current = nil
end

return RunConfig
