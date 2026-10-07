--[[
	GameConfig

	Every fixed number for a run lives here so nothing is hardcoded in
	the middle of a system. Holds the player starting values (100 max
	health, 100 max energy, energy regen per second), the multiplayer
	scaling value (+0.5x enemy health for each player past the first),
	the default money reward settings, the loadout size (2 weapons and 2
	abilities, 1 of each equipped), and the timing values for the room
	progression, mainly the countdown before an area starts once the
	first player has entered it.

	The area order and the gates are not here, those are in
	Game.Data.RoomData, because that describes the shape of the map
	rather than being a tuning value.

	This module is only a table of values. It never touches players,
	instances or remotes, which is why it can safely live in
	ReplicatedStorage and be read by both sides.
]]

--[[
	What connects to this

	Server reads:
	  Server.Game.Core.RunSetup takes the starting health, energy and the
	  per player scaling value when the run is built.
	  Server.Game.Core.PlayerStats takes the base max health and max
	  energy when a stat object is created.
	  Server.Game.Core.Loadout takes the loadout size.
	  Server.Game.Combat.EnergyService takes the regen per second and the
	  regen tick rate.
	  Server.Game.Rooms.RoomManager takes the entry countdown length.
	  Server.Game.Rooms.RoomZones takes how often to run its checks.
	  Server.Game.Combat.DamageService takes the money reward defaults.

	Shared reads:
	  Game.Shared.StatFormulas uses the per player scaling value in its
	  enemy health calculation.

	Client reads:
	  ClientGame.Controllers.HUDController uses max health and max energy
	  to work out bar fill sizes before the first StatsUpdated remote
	  arrives.
	  ClientGame.Controllers.RoomBannerController uses the countdown
	  length as a fallback if the server does not send it.

	Keep the scaling value in one place only. If it also gets written
	into StatFormulas the two will drift apart later.
]]

-- Note on when changes take effect. Everything in here is read when
-- the module that needs it first loads, so a change needs a restart of
-- the playtest. The Debug flags are the exception, they are read live.

local GameConfig = {}

----------------------------------------------------------------------
-- PLAYER
----------------------------------------------------------------------

GameConfig.Player = {
	-- The values a fresh PlayerStats starts with. Artifacts from the
	-- shop add on top of these during the run.
	MaxHealth = 100,
	MaxEnergy = 100,
	StartingMoney = 0,
	StartingLevel = 1,

	-- Energy comes back on its own, slowly. RegenPerSecond is the total
	-- gained each second, RegenTickRate is how often that is paid out,
	-- so 1 per second at 0.1 ticks is 0.1 energy ten times a second,
	-- which makes the bar move smoothly instead of jumping. With the
	-- ability costs in AbilityData (20 to 45) that is roughly one cast
	-- every half minute from regen alone, so kills and potions matter.
	EnergyRegenPerSecond = 1,
	EnergyRegenTickRate = 0.1,
	-- Seconds after an ability fires before regen starts again, so
	-- chaining abilities back to back drains the bar properly. 0 means
	-- it never pauses.
	EnergyRegenDelayAfterUse = 3,

	-- Health comes back on its own too, at this many points a second,
	-- paid out on the same tick as energy. The difficulty's PlayerRegen
	-- multiplier applies. 0 turns it off.
	HealthRegenPerSecond = 1,

	-- Energy given to the player who lands a kill, so aggressive play
	-- fuels the abilities. Scaled by the enemy's reward multiplier, so
	-- a Necromancer's summons give half. 0 turns it off.
	EnergyPerKill = 2,

	-- How long the body stays before the character is cleaned up.
	DeathCleanupTime = 3,
}

----------------------------------------------------------------------
-- MULTIPLAYER
----------------------------------------------------------------------

GameConfig.Multiplayer = {
	-- Enemy health is multiplied by 1 + (players - 1) * this, so with
	-- 0.5 one player is 1x, two is 1.5x, three is 2x, four is 2.5x.
	EnemyHealthPerExtraPlayer = 0.5,
	-- Same rule for enemy damage. 0 means enemies hit just as hard no
	-- matter how many players there are, which is the design.
	EnemyDamagePerExtraPlayer = 0,

	MaxPlayers = 4,

	-- true means the run only ends when every player is dead. false
	-- ends it the moment anyone dies.
	RunEndsWhenAllDead = true,
	-- true brings dead players back when the area they died in is
	-- cleared. false means dead players spectate until the run ends.
	ReviveOnAreaClear = true,
	-- Health a revived player comes back with, as a fraction of max.
	ReviveHealthPercent = 0.5,
}

----------------------------------------------------------------------
-- LOADOUT
----------------------------------------------------------------------

GameConfig.Loadout = {
	-- How many of each the player brings into a run. Only one of each
	-- is out at a time, the rest are swapped to.
	WeaponSlots = 2,
	AbilitySlots = 2,

	-- The two weapons have to be different, same for abilities. Turn
	-- off to allow bringing two of the same.
	RequireUniqueWeapons = true,
	RequireUniqueAbilities = true,

	-- Seconds after a swap before the player can swap again. 0 means
	-- swapping is free. Each weapon and ability keeps its own cooldown
	-- either way, so a swap never skips one.
	WeaponSwapCooldown = 0,
	AbilitySwapCooldown = 0,
	-- true cancels an attack that is still winding up when the player
	-- swaps away from that weapon. false lets an attack that was
	-- already fired finish (the Pistol's fan, the Sword's crescent), so
	-- quick swapping between shots never throws one away.
	SwapCancelsAttack = false,
	-- Quick swapping: for Window seconds after swapping weapons, the
	-- player's hits do DamageMultiplier more damage, so firing one
	-- weapon then swapping and firing the other is rewarded. 1 turns
	-- it off.
	QuickSwap = {
		Window = 0.8,
		DamageMultiplier = 1.25,
	},

	-- Swapping never skips a cooldown: the weapon swapped to can not
	-- fire until this fraction of the longest cooldown still running on
	-- the weapon swapped from has passed. 0.5 is half, 0 turns it off.
	SwapCooldownShare = 0.5,

	-- What a player gets if their saved loadout has a name that no
	-- longer exists. These must be keys in WeaponData and AbilityData.
	FallbackWeapon = "Sword",
	FallbackAbility = "StunSlam",
}

----------------------------------------------------------------------
-- REWARDS
----------------------------------------------------------------------

GameConfig.Rewards = {
	-- Every kill reward from EnemyData is multiplied by this before the
	-- difficulty multiplier. A quick global knob for the economy.
	MoneyMultiplier = 1,

	-- "Killer" gives it only to whoever got the last hit, which is
	-- the design. "Everyone" gives the full reward to every player in
	-- the run. "Split" divides it evenly between everyone alive.
	MoneySplit = "Killer",

	-- Money handed to every player when an area is cleared, on top of
	-- the kills. It keeps the whole team able to shop in multiplayer,
	-- where kills only pay whoever lands them. 0 turns it off.
	AreaClearBonus = 25,
	BossKillBonus = 0,
}

----------------------------------------------------------------------
-- ROOMS
----------------------------------------------------------------------

GameConfig.Rooms = {
	-- Seconds between the first player entering a combat area and the
	-- first wave spawning. Shown as a countdown on the banner.
	EntryCountdown = 3,

	-- true pulls every player forward to the area's PlayerSpawns when
	-- the countdown starts, so nobody is left in the previous room.
	PullPlayersForwardOnEntry = true,

	-- How often RoomZones checks which area each player is in.
	ZoneCheckRate = 0.25,

	-- Seconds between the last enemy of an area dying and the gate out
	-- starting to open. A little pause so the clear registers.
	GateOpenDelay = 0.8,

	-- Seconds a banner such as "Room 2" or "Shop" stays on screen.
	BannerDuration = 3,

	-- true closes the gate behind the players once they are all in the
	-- next area so nobody can run back.
	CloseGateBehind = true,

	-- A wave enemy that has been outside its area's zone for this
	-- many seconds is killed, so a Noob stuck in a wall or thrown out
	-- of the room cannot stop the gate ever opening. 0 turns it off.
	OutOfAreaKillTime = 6,
	-- A wave enemy that has not taken damage or moved for this many
	-- seconds while no player can reach it is also removed. 0 is off.
	StuckKillTime = 25,
}

----------------------------------------------------------------------
-- KILL PLANE
----------------------------------------------------------------------

GameConfig.KillPlane = {
	-- One big block under the whole map in workspace.MainGameObj.
	-- KillPlanes. Anything whose position drops below the top of any
	-- part in that folder, while above its footprint, is caught.
	Enabled = true,
	-- Seconds between checks. A falling character moves about 20
	-- studs in a quarter second, and the plane sits well under the
	-- floors, so this never misses.
	CheckRate = 0.25,
	-- What happens to a player that falls. "Return" puts them back at
	-- their current area's player spawn and takes ReturnDamage off.
	-- "Kill" kills them outright.
	PlayerAction = "Return",
	ReturnDamage = 15,
	-- Enemies are always killed through EnemyBase so the wave count
	-- goes down. Projectiles are removed.
}

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------

GameConfig.Run = {
	-- Seconds after the run is won or lost before the server resets
	-- everything, so the result screen has time to show.
	EndDelay = 7,

	-- What happens when the run ends:
	--   "Vote"     the end screen shows what everyone earned and waits.
	--              The run restarts once half the players (rounded up)
	--              press Replay, and anyone can press Back to Lobby
	--   "Lobby"    after EndDelay, everyone is sent to the lobby
	--   "Restart"  after EndDelay, the run resets in place
	AfterRun = "Vote",

	-- Difficulty used when no teleport data arrived, for example when
	-- someone joins this place directly in Studio.
	DefaultDifficulty = "Normal",

	-- the map name the end of run stats are saved under (MapBest, MapRuns) when the lobby did not send one
	DefaultMap = "VeloCITY",
}

----------------------------------------------------------------------
-- LOBBY (THE WAY IN AND OUT)
----------------------------------------------------------------------

-- This place is the run itself, a separate "dimension" players are
-- teleported into from a lobby place in the same experience, and sent
-- back out of when the run ends. The data the lobby sends is written
-- down in Server.Game.Core.TeleportDataReader, and the way back out is
-- Server.Game.Core.LobbyLink.
GameConfig.Lobby = {
	-- The lobby place's id. 0 means there is no lobby yet, so nothing
	-- ever teleports and runs restart in place. The lobby can also send
	-- its own id in the teleport data, which wins over this.
	-- 132125671517738 is the "NEA" lobby place.
	PlaceId = 132125671517738,
	-- Seconds to wait for everyone the lobby said was coming before
	-- the run starts without them.
	PartyWaitTimeout = 20,
	-- Teleport attempts before giving up and restarting in place.
	TeleportRetries = 3,
	TeleportRetryDelay = 2,
	-- true lets a player leave in the middle of a run with the "Back to
	-- lobby" button, which only shows when there is a lobby to go back
	-- to. The end screen's own Back to Lobby button always shows.
	AllowEarlyLeave = true,
}

----------------------------------------------------------------------
-- DEBUG
----------------------------------------------------------------------

-- These are read live, so they can be flipped during a playtest.
-- Invincibility frames: moments where the player takes no damage at
-- all, so a big move can be used to get out of danger. Seconds each.
GameConfig.IFrames = {
	-- false turns every one of them off.
	Enabled = true,
	-- Given when the ability is used, by ability name.
	Abilities = {
		-- Stun Slam is covered the whole time the player is in the air
		-- (While = true), then for After seconds once they land.
		StunSlam = { While = true, After = 1 },
		-- On arrival, while the strike lands.
		Teleport = 0.6,
		Rage = 0.5,
		HealBurst = 0.75,
	},
	-- A dash or slide. Short, so dodging through an attack takes timing.
	Dash = 0.2,
}

GameConfig.Debug = {
	-- Print every damage event with the multipliers that applied.
	LogDamage = false,
	-- Print wave starts, spawns and area clears.
	LogWaves = false,
	-- Print every ability and weapon attack request the server gets.
	LogCombat = false,
	-- Print every shop roll and purchase.
	LogShop = false,
	-- Draw hitboxes and ability radii as parts for a moment.
	ShowHitboxes = false,
	-- Skip the entry countdown so rooms start instantly.
	SkipCountdown = false,
	-- Players cannot take damage. Useful for walking the map.
	Invincible = false,
	-- Abilities cost no energy and weapons have no cooldown.
	FreeAbilities = false,
	-- Stationary Noobs spawned near the SpawnLocation at server start
	-- to hit, so combat can be tested before the rooms exist. 0 is
	-- none. They come back a few seconds after dying.
	TrainingDummies = 0,
	-- Float a damage number over anything that gets hit.
	ShowDamageNumbers = true,
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks a section up by name and warns rather than erroring if the
-- name is wrong, so a typo at a call site does not take the server
-- down.
function GameConfig.Get(SectionName: string)
	local Section = GameConfig[SectionName]
	if type(Section) ~= "table" then
		warn("[GameConfig] no section called " .. tostring(SectionName))
	end
	return Section
end

return GameConfig
