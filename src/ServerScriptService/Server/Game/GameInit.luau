--[[
	GameInit

	The single entry point for every game system, so Main only has to
	know about one module instead of twenty. It requires each game
	module and calls their Init in the right order, then starts the run.

	Order matters here. The data and config layer has nothing to start.
	Then RunSetup has to run first so RunConfig is filled in before
	anything reads it. Then the services that only set up listeners can
	go in any order: EnergyService, StatusEffectService, CombatService,
	DamageService, ShopManager, RoomZones. RoomManager goes last, because
	it is what actually starts the run once everything else is listening.
]]

--[[
	What connects to this

	Called from ServerScriptService.Server.Core.Main. Add
	require(ServerScriptService.Server.Game.GameInit) alongside the
	existing requires there, and GameInit.Init() after the existing
	Init calls, so the framework modules (DataManager, PlayerManager,
	LeaderstatsManager, AntiCheat, GameManager) are all up first.

	Requires and initialises:
	  Game.Core.RunSetup
	  Game.Combat.EnergyService
	  Game.Effects.StatusEffectService
	  Game.Combat.ProjectileService
	  Game.Enemies.EnemyRegistry
	  Game.Enemies.EnemySpawner
	  Game.Enemies.EnemyAI
	  Game.Combat.CombatService
	  Game.Shop.ShopManager
	  Game.Rooms.RoomZones
	  Game.Rooms.GateController
	  Game.Rooms.KillPlanes
	  Game.Rooms.RoomManager
	  Game.Core.LobbyLink
	  Game.Core.RunManager

	Game.Core.PlayerStats and Game.Core.Loadout are classes rather than
	services, so they are created per player by RunSetup and do not get
	an Init call from here.

	It depends on DataManager already being initialised, because
	Game.Core.Loadout reads each player's chosen weapons and abilities
	out of their saved data. That is why this goes after the existing
	Init calls in Main and not before them.

	GateController should close and lock every gate as part of its Init,
	before RoomManager starts, so there is never a moment at server start
	where the gates are open.

	Nothing else should require the game modules to start them. If a
	module needs another one it requires it directly for its functions,
	but only GameInit calls Init.
]]

local Game = script.Parent

local GameInit = {}

-- Every service, in start order. A module that is still a planning
-- stub with no Init is skipped with a note rather than erroring, so
-- the systems that do exist can be played before the rest are built.
-- Uncomment each line as that module gets written.
local Services = {
	-- answers the client asking for its save, before MapLoader since that waits for a player
	{ Name = "PlayerDataSync", Module = Game.Core.PlayerDataSync },
	-- waits for the first player and puts their map in workspace
	{ Name = "MapLoader", Module = Game.Core.MapLoader },
	{ Name = "RunSetup", Module = Game.Core.RunSetup },
	-- PlayTime and Timebux for time spent here
	{ Name = "PlayTimeService", Module = Game.Core.PlayTimeService },
	{ Name = "EnergyService", Module = Game.Combat.EnergyService },
	{ Name = "StatusEffectService", Module = Game.Effects.StatusEffectService },
	{ Name = "ProjectileService", Module = Game.Combat.ProjectileService },
	{ Name = "EnemyRegistry", Module = Game.Enemies.EnemyRegistry },
	{ Name = "EnemySpawner", Module = Game.Enemies.EnemySpawner },
	{ Name = "EnemyAI", Module = Game.Enemies.EnemyAI },
	{ Name = "CombatService", Module = Game.Combat.CombatService },
	{ Name = "ShopManager", Module = Game.Shop.ShopManager },
	{ Name = "RoomZones", Module = Game.Rooms.RoomZones },
	{ Name = "GateController", Module = Game.Rooms.GateController },
	{ Name = "KillPlanes", Module = Game.Rooms.KillPlanes },
	{ Name = "RoomManager", Module = Game.Rooms.RoomManager },
	-- the core tag over each player's head
	{ Name = "CoreTagService", Module = Game.Core.CoreTagService },
	-- gear drops from enemies and the boss
	{ Name = "GearService", Module = Game.Core.GearService },
	-- The way back to the lobby, before RunManager which uses it.
	{ Name = "LobbyLink", Module = Game.Core.LobbyLink },
	-- RunManager goes last. RunSetup starts it once the players are in,
	-- and by then everything above is listening.
	{ Name = "RunManager", Module = Game.Core.RunManager },
}
-- DamageService and HitDetection are libraries with no Init, they
-- are required by the weapons directly.

function GameInit.Init()
	for _, Entry in ipairs(Services) do
		local Ok, Result = pcall(require, Entry.Module)
		if not Ok then
			warn("[GameInit] " .. Entry.Name .. " failed to load: " .. tostring(Result))
			continue
		end

		if type(Result) ~= "table" or type(Result.Init) ~= "function" then
			warn("[GameInit] " .. Entry.Name .. " has no Init yet, skipped")
			continue
		end

		local InitOk, InitError = pcall(Result.Init)
		if not InitOk then
			warn("[GameInit] " .. Entry.Name .. ".Init errored: " .. tostring(InitError))
		end
	end

	print("[GameInit] game systems started")
end

return GameInit
