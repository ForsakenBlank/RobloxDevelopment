--[[
	PlayerDataTemplate

	The default saved data for a player who has never played before.
	This is what gets written to a fresh save, and any key added here
	later gets filled in automatically for players who already have an
	older save.

	Only things that should survive between sessions go in here, so the
	chosen loadout, permanent unlocks, total kills, best room reached and
	any currency meant to carry over. Run values like current health,
	energy and the money earned this run do not belong here, because a
	run resets when it ends. Those live on Server.Game.Core.PlayerStats.

	The loadout is the important one for this place. Character creation
	happens in the lobby, and the lobby writes the player's 2 chosen
	weapons and 2 chosen abilities into this save. This place reads them
	back out instead of being handed them. So the template needs keys for
	both weapon slots and both ability slots, with sensible defaults for
	a player who somehow arrives without having picked.
]]

--[[
	What connects to this

	ServerScriptService.Server.Modules.DataManager requires this on load
	and uses it in two places. It deep copies it for a brand new player,
	and its fillMissing function walks it to add any key a returning
	player's save does not have yet. That means adding a new saved
	variable only needs a line in here and nothing else.

	Server.Game.Core.Loadout reads the four loadout keys through
	DataManager.Get to build the player's weapons and abilities for the
	run. The values stored are the key names from
	Game.Data.WeaponData and Game.Data.AbilityData, so those two tables
	and the defaults in here have to agree.

	ServerScriptService.Server.Modules.LeaderstatsManager reads whichever
	keys it puts on the leaderboard, so those key names have to match.
	It currently lists Cash and Level.

	Server.Game.Core.RunManager writes back through DataManager.Set and
	DataManager.Increment at the end of a run for anything that
	persists, like a best room reached.

	The lobby place needs the exact same template, since it is the one
	writing the loadout. If the two places disagree, whichever saves last
	will overwrite keys the other added, and it will look like data is
	being lost. This is the single most important thing to keep in step
	between the two places.
]]

return {
	-- Loadout, written by the lobby's character creation. The names
	-- are keys in WeaponData.Weapons and AbilityData.Abilities. These
	-- defaults are what a player gets if they arrive without picking.
	Weapon1 = "Sword",
	Weapon2 = "Pistol",
	Ability1 = "StunSlam",
	Ability2 = "Teleport",

	-- Shown on the Roblox leaderboard by LeaderstatsManager. Cash is
	-- the carry over currency for the lobby, separate from the money
	-- earned inside a run.
	Cash = 0,
	Level = 1,
	-- Total experience, earned at the end of every run from kills, how
	-- far the run got and whether it was won. Called XP to match the
	-- lobby, which shares this save and works Level out from it.
	XP = 0,

	-- Lifetime stats, written at the end of a run.
	TotalKills = 0,
	TotalRuns = 0,
	RunsWon = 0,
	BestRoom = 0,

	-- The difficulty picked in the lobby. Read by TeleportDataReader
	-- as a fallback when no teleport data arrived.
	Difficulty = "Normal",

	-- Permanent upgrades bought in the lobby with Cash. Empty until the
	-- lobby has a shop for them.
	Upgrades = {},

	-- goes up by 1 on every save, the lobby and this place use it to spot an old copy of the save
	SaveVersion = 0,
}
