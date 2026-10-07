-- PlayerDataTemplate
-- This is the default data every player starts with.
-- To add a new saved variable, just add a line below.
-- DataManager fills it in for every player automatically and
-- it will not overwrite anyone's existing save.
--
-- The game place ("VeloCITY Map") shares this save, so both places
-- need the same keys: its own PlayerDataTemplate
-- (ReplicatedStorage.Modules.Shared) has the same ones. Keys only one
-- place uses are still kept safe by the other, because DataManager
-- saves the whole table and only fills in what is missing.

local PlayerDataTemplate = {

	-- Loadout, picked on the character creation screen here and used
	-- by the game. The names are keys in Shared.LoadoutData (and in the
	-- game's WeaponData and AbilityData).
	Weapon1 = "Sword",
	Weapon2 = "Pistol",
	Ability1 = "StunSlam",
	Ability2 = "Teleport",

	-- Whether the player has been through the character creation screen
	-- (Client.Modules.CharacterCreationUI). It opens on every join until
	-- this is true, and that includes players whose save is from before
	-- the screen existed, since they have never picked a core.
	CharacterCreated = false,
	-- "Starter" for the game's own character, "Roblox" for the player's
	-- Roblox avatar. Server.Services.CharacterService applies it.
	AvatarMode = "Starter",

	-- The Custom Character's skin (a key in Shared.SkinData; Cape and
	-- Plain are free) and the skins owned beyond the free and level ones,
	-- as { [Key] = true }: bought with Cash, or granted by the game place
	-- for beating a boss. Face and BodyColours ({ Torso = "#RRGGBB" })
	-- only show while the player owns the Customise gamepass; "" and {}
	-- leave the skin as it is.
	Skin = "Cape",
	OwnedSkins = {},
	Face = "",
	BodyColours = {},
	-- The USE CUSTOMISATION tick box: false wears the skin as it is
	-- without losing the face and colours.
	CustomiseOn = true,

	-- Timebux: earned by time in game, spent on gamepasses (1 = 1 Robux).
	-- Passes holds gamepasses bought with Timebux as { [Key] = true }; ones
	-- bought with Robux are checked with Roblox instead
	-- (Server.Services.SkinService).
	Timebux = 0,
	Passes = {},

	-- The developer's unlock-everything switch (Shared.SkinData.DevUserIds
	-- only; the server ignores it for anyone else).
	DevUnlockAll = false,

	-- The active core (a key in Shared.CoreData, "" until one is picked)
	-- and every core's total Enlightenment. The level of each is worked
	-- out from its total, see Server.Services.CoreService.
	Core = "",
	Cores = {
		Ruby = 0,
		Sapphire = 0,
		Amethyst = 0,
		Diamond = 0,
	},

	-- Gear (Shared.EquipmentData): every armour piece and accessory the
	-- player owns, as { [ItemId] = { Id, Rarity, Stars, Lines, Rerolls,
	-- Got, Dev } }. Everyone starts with none; it drops in runs (the game
	-- place adds it with EquipmentData.NewItem). Armor and Accessories
	-- hold the ids of what is worn ("" for an empty slot); Accessories has
	-- one entry per slot. Scrap comes from dismantling gear and pays for
	-- rerolls. Server.Services.EquipmentService checks all of it on join.
	Gear = {},
	Armor = {
		Boots = "",
		Chestplate = "",
		Helmet = "",
	},
	Accessories = { "", "", "", "", "" },
	Scrap = 0,
	-- Weapons, abilities and equipment unlocked by something other than
	-- level (a shop, a boss drop), as { [Key] = true }.
	Unlocks = {},

	Cash = 0,
	Level = 1,
	-- Total XP. Earned in the game at the end of every run; Level is
	-- worked out from it (Shared.Leveling).
	XP = 0,

	-- Lifetime stats, written by the game at the end of a run and shown
	-- on the Stats panel here.
	TotalKills = 0,
	TotalRuns = 0,
	RunsWon = 0,
	BestRoom = 0,

	-- More lifetime stats for the Stats menu. PlayTime (seconds) is
	-- counted in the lobby (Server.Services.SkinService); the rest are for
	-- the game place to add to at the end of a run:
	--   Deaths, Parries, PerfectParries   numbers
	--   MapBest      { [MapKey] = { [Difficulty] = best area reached } }
	--   MapRuns      { [MapKey] = runs played }
	--   CoreTime     { [CoreKey] = seconds played with it active }
	--   CoreRuns     { [CoreKey] = runs played with it active }
	--   WeaponKills  { [WeaponKey] = kills }
	--   AbilityUses  { [AbilityKey] = uses }
	PlayTime = 0,
	Deaths = 0,
	Parries = 0,
	PerfectParries = 0,
	MapBest = {},
	MapRuns = {},
	CoreTime = {},
	CoreRuns = {},
	WeaponKills = {},
	AbilityUses = {},

	-- The difficulty last picked on the Play menu.
	Difficulty = "Normal",

	-- Permanent upgrades bought with Cash. Empty until there is a shop
	-- for them.
	Upgrades = {},

	-- The Settings screen's choices (Shared.SettingsData has the list and
	-- defaults; older saves without some of these get the defaults).
	-- MusicEnabled and SFXEnabled are the game place's older switches.
	Settings = {
		MusicEnabled = true,
		SFXEnabled = true,
		MasterVolume = 100,
		MusicVolume = 70,
		EffectsVolume = 80,
		MenuSounds = true,
		CameraShake = true,
		MovingBackgrounds = true,
		HoverInfo = true,
		CoreTags = true,
	},

	-- The player's own keys (Settings > CONTROLS), only the ones they
	-- changed: { [Action] = "KeyName" }. Shared.Keybinds has the list and
	-- the defaults; Server.Services.SettingsService checks every change.
	-- The game place reads it for the combat and movement keys.
	Keybinds = {},

	Inventory = {},

	-- One higher every time the save is written (Server.Modules.
	-- DataManager). A place sending a player on puts the number it just
	-- saved in the teleport data, and the place they arrive in waits for
	-- a copy at least that new, so nobody plays on an old save.
	SaveVersion = 0,

}

return PlayerDataTemplate
