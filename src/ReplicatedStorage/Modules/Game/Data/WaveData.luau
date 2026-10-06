--[[
	WaveData

	The wave layout for every combat area. One entry per area, and inside
	each area a numbered list of waves. Each wave is a list of enemy type
	names with a count for each, plus an optional delay before the wave
	starts so an area can stagger its spawns.

	The built map has 4 combat rooms, so the keys are Room1, Room2,
	Room3, Room4 and BossRoom. The normal rooms get waves that mix Noob,
	Bob and Necromancer, with the harder types kept rarer in the early
	rooms and more common later. BossRoom is a single wave holding just
	the Boss.

	Worth noting the design document says 5 combat rooms and the success
	criteria is written against that number. The map currently has 4, so
	either a fifth needs adding to the map or the document needs
	changing. Adding one here is a new key plus an entry in
	Game.Data.RoomData and one more gate.
]]

--[[
	What connects to this

	Server.Game.Rooms.WaveManager reads this to know how many waves an
	area has and what is in each one. It is the only module that should
	read the wave list directly.

	Server.Game.Enemies.EnemySpawner is handed one wave at a time by
	WaveManager and spawns what that wave asks for at the platforms in
	workspace.MainGameObj.EnemySpawns.<AreaName>.

	Server.Game.Rooms.RoomManager needs the wave count so it knows when
	the last wave of an area has been cleared and the gate out can open
	through Server.Game.Rooms.GateController.

	The current wave number and total wave count get sent to the client
	on the ReplicatedStorage.Remotes.Events.WaveStateChanged remote for
	ClientGame.Controllers.HUDController to display.

	The area names here must match the area names in Game.Data.RoomData
	and the folder names in workspace.MainGameObj.EnemySpawns. The enemy
	type names must match the keys in Game.Data.EnemyData and the classes
	registered in Server.Game.Enemies.EnemyRegistry.

	If an area asks for more enemies than it has spawn platforms, the
	spawner reuses platforms rather than erroring, so keep that in mind
	when filling this in. A wave of 20 on 3 platforms will be a crowd.
]]

-- Note on when changes take effect. An area's wave list is read when
-- the first player enters that area, so a change applies to the next
-- room entered without a restart.

local WaveData = {}

----------------------------------------------------------------------
-- DEFAULTS
----------------------------------------------------------------------

-- Used by any wave or area that does not set its own value.
WaveData.Defaults = {
	-- Seconds between the last enemy of a wave dying and the next wave
	-- starting. The difficulty's WaveDelay multiplier applies on top.
	DelayBetweenWaves = 1.5,
	-- Seconds between each individual enemy appearing within a wave,
	-- so a wave of 8 trickles in rather than popping in at once. 0
	-- spawns them all together.
	SpawnInterval = 0.2,
	-- The next wave starts when this fraction of the current wave is
	-- dead, so a room keeps its pace and does not stall on one runner.
	-- 1 waits for every enemy. 0.8 starts the next wave with a fifth
	-- still alive. The last wave of an area always waits for everyone.
	NextWaveAtRemaining = 0.8,
	-- Spawn platforms are picked "Random", "Sequence" (in name order)
	-- or "Furthest" (from the nearest player, so enemies never appear
	-- on top of someone).
	PlatformOrder = "Furthest",
	-- The countdown before the first wave comes from
	-- GameConfig.Rooms.EntryCountdown, not from here.
}

----------------------------------------------------------------------
-- AREAS
----------------------------------------------------------------------

-- Each area is an ordered list of waves. Each wave is:
--   Enemies   { EnemyName = count, ... } using keys from EnemyData
--   Delay     nil uses Defaults.DelayBetweenWaves. Ignored on wave 1,
--             which uses the room entry countdown instead
--   Interval  nil uses Defaults.SpawnInterval
--   Name      optional, shown on the HUD instead of "Wave 2"
--   SpawnPoints  optional, { EnemyName = "PlatformName" } to always
--             spawn that enemy on one platform in EnemySpawns
-- An area can also set:
--   Enabled   false skips the fight and opens the gate straight away,
--             handy for testing a later room
--   Banner    what the room banner shows on entry
--
-- Each room brings in something new: Dashers in Room 1, Bombers in
-- Room 2, Necromancers in Room 3, then everything at once in Room 4.

WaveData.Areas = {

	Room1 = {
		Enabled = true,
		Banner = "Room 1",
		Waves = {
			{ Enemies = { Noob = 6 } },
			{ Enemies = { Noob = 6, Dasher = 2 } },
			{ Enemies = { Noob = 7, Dasher = 2, Bob = 1 } },
		},
	},

	Room2 = {
		Enabled = true,
		Banner = "Room 2",
		Waves = {
			{ Enemies = { Noob = 7, Dasher = 2 } },
			{ Enemies = { Noob = 6, Bomber = 3, Bob = 1 } },
			{ Enemies = { Noob = 7, Dasher = 3, Bomber = 2, Bob = 1 } },
		},
	},

	Room3 = {
		Enabled = true,
		Banner = "Room 3",
		Waves = {
			{ Enemies = { Noob = 8, Necromancer = 1, Bomber = 2 } },
			{ Enemies = { Dasher = 4, Bob = 2, Necromancer = 1 } },
			{ Enemies = { Noob = 8, Bob = 2, Necromancer = 2, Bomber = 3 } },
		},
	},

	Room4 = {
		Enabled = true,
		Banner = "Room 4",
		Waves = {
			{ Enemies = { Noob = 10, Dasher = 4, Bob = 1 } },
			{ Enemies = { Bob = 3, Necromancer = 2, Bomber = 4, Noob = 4 } },
			{ Enemies = { Noob = 12, Bob = 3, Necromancer = 2, Dasher = 4, Bomber = 3 }, Name = "Final Wave" },
		},
	},

	BossRoom = {
		Enabled = true,
		Banner = "Boss",
		Waves = {
			{ Enemies = { Boss = 1, Noob = 4, Dasher = 2 }, Name = "Boss", Interval = 0, SpawnPoints = { Boss = "Spawn3" } },
		},
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks an area up by name and warns rather than erroring if the name
-- is wrong, so a mismatch with RoomData opens the gate instead of
-- hanging the run.
function WaveData.GetArea(AreaName: string)
	local Area = WaveData.Areas[AreaName]
	if not Area then
		warn("[WaveData] no area called " .. tostring(AreaName))
	end
	return Area
end

-- How many waves an area has. 0 for an unknown or disabled area.
function WaveData.GetWaveCount(AreaName: string): number
	local Area = WaveData.Areas[AreaName]
	if not Area or not Area.Enabled then
		return 0
	end
	return #Area.Waves
end

-- Total enemies in one wave, for the HUD's "enemies remaining".
function WaveData.CountEnemies(Wave): number
	local Total = 0
	for _, Count in pairs(Wave.Enemies) do
		Total += Count
	end
	return Total
end

return WaveData
