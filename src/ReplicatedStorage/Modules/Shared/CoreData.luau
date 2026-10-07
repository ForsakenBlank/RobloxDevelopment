-- CoreData
-- The four cores (Velocity gameplan: CORE SYSTEM OVERHAUL). A core is the
-- player's class: exactly one is active at a time, picked on the
-- character screen and swapped (ATTUNE) on the Core menu
-- (Client.Modules.CoreUI).
--
-- Every core has its own progress, called Enlightenment. Playing with a
-- core enlightens it, enough Enlightenment levels it up, which raises its
-- stat bonuses and unlocks its milestones. Only the active core counts,
-- but every core's Enlightenment is kept, so swapping away and back again
-- loses nothing. The save holds total Enlightenment per core (Cores =
-- { Ruby = 0, ... }) and the active one (Core); the level is always
-- worked out from the total (FromXP).
--
-- What each core has (the words are in Shared.GameText.Cores, added to
-- each core when this loads):
--   Colour, Light, Dark, Shape, Icon   how it looks (Shared.GemIcon)
--   FavouredKey  the weapon it is built around (Amethyst: Fists), or nil
--   Stats        { Key, Base, Per, Max, Unlock, Sign }: Base% at the
--                level it unlocks (Unlock, else level 1), Per% more each
--                level after, never over Max. Sign "-" for a reduction.
--   Milestones   { Key, Level, Kind }: unlocked at Level (0 = always).
--                Kind is CRITS, PASSIVE, ULTIMATE or STAT.
--   Penalties    the drawbacks as numbers, in %, for Shared.CharacterStats
--                (the words are Drawbacks in GameText). MaxHealth = -20
--                is 20% less max health; AbilityCooldown = 30 is 30%
--                longer ability cooldowns; DamageTaken = 15 is 15% more
--                damage taken.
-- and from GameText: DisplayName, Class, Focus, Tagline, Description,
-- Favoured, each stat's Label, each milestone's Name and Description,
-- Ultimate { Name, Description, Charge }, Aura { Name, Description } and
-- Drawbacks { string }.
-- Nothing here does anything in a run by itself: the game place reads it
-- (copy this module there) and makes it happen.
--
-- Read by Server.Services.CoreService (checks, levels, the overhead
-- tag), Shared.GemIcon, Shared.CoreTag and the client's CoreUI and
-- CharacterUI.

local UIIcons = require(script.Parent.UIIcons)
local GameText = require(script.Parent.GameText)

local CoreData = {}

CoreData.Settings = {
	-- Enlightenment from level 1 to 2, and how much more each level
	-- after needs than the one before.
	FirstLevel = 200,
	PerLevel = 100,
	MaxLevel = 30,
	-- The core level its ultimate unlocks at (it then cycles in with the
	-- player's abilities).
	UltimateLevel = 5,
}

-- The order the cores are shown in.
CoreData.Order = { "Ruby", "Sapphire", "Amethyst", "Diamond" }

CoreData.Cores = {
	Ruby = {
		Shape = "Rhombus",
		Icon = UIIcons.Get("core_ruby", "rbxassetid://118845705367178"),
		Colour = Color3.fromRGB(230, 45, 75),
		Light = Color3.fromRGB(255, 130, 150),
		Dark = Color3.fromRGB(120, 10, 35),
		Stats = {
			{ Key = "Speed", Base = 5, Per = 1, Max = 15 },
			{ Key = "WeaponDamage", Base = 10, Per = 1.5 },
			{ Key = "OverallDamage", Base = 5, Per = 0.5 },
			{ Key = "WeaponCooldown", Base = 10, Sign = "-", Unlock = 20 },
		},
		Milestones = {
			{ Key = "Crits", Level = 0, Kind = "CRITS" },
			{ Key = "LowHealth", Level = 0, Kind = "PASSIVE" },
			{ Key = "Ultimate", Level = 5, Kind = "ULTIMATE" },
			{ Key = "Bloodlust", Level = 10, Kind = "PASSIVE" },
			{ Key = "Executioner", Level = 15, Kind = "PASSIVE" },
			{ Key = "Cooldown", Level = 20, Kind = "STAT" },
		},
		-- "Ability/Magic cooldowns are increased a lot" (30 is a first
		-- guess). No health regen in combat is the game place's to do.
		Penalties = { MaxHealth = -20, AbilityCooldown = 30 },
	},
	Sapphire = {
		Shape = "Round",
		Icon = UIIcons.Get("core_sapphire", "rbxassetid://115032839419008"),
		Colour = Color3.fromRGB(45, 105, 235),
		Light = Color3.fromRGB(140, 195, 255),
		Dark = Color3.fromRGB(15, 35, 125),
		Stats = {
			{ Key = "Energy", Base = 5, Per = 0.25 },
			{ Key = "MagicDamage", Base = 25, Per = 2 },
			{ Key = "AbilityCooldown", Base = 10, Sign = "-", Unlock = 20 },
		},
		Milestones = {
			{ Key = "CastOverflow", Level = 0, Kind = "PASSIVE" },
			{ Key = "Ultimate", Level = 5, Kind = "ULTIMATE" },
			{ Key = "Crits", Level = 8, Kind = "CRITS" },
			{ Key = "SpellWeaving", Level = 10, Kind = "PASSIVE" },
			{ Key = "ShatterFreeze", Level = 15, Kind = "PASSIVE" },
			{ Key = "Cooldown", Level = 20, Kind = "STAT" },
		},
		Penalties = { WeaponCooldown = 50, DamageTaken = 15, MoveSpeed = -10 },
	},
	Amethyst = {
		Shape = "Crystal",
		Icon = UIIcons.Get("core_amethyst", "rbxassetid://122080891712932"),
		Colour = Color3.fromRGB(155, 75, 225),
		Light = Color3.fromRGB(220, 165, 255),
		Dark = Color3.fromRGB(70, 25, 130),
		-- The weapon key it's built around (its name is in GameText).
		FavouredKey = "Fists",
		Stats = {
			{ Key = "Health", Base = 5, Per = 1, Max = 50 },
			{ Key = "WeaponDamage", Base = 25, Per = 2 },
			{ Key = "ParryDamage", Base = 25, Unlock = 12 },
			{ Key = "WeaponCooldown", Base = 15, Sign = "-", Unlock = 20 },
		},
		Milestones = {
			{ Key = "ComboMeter", Level = 0, Kind = "PASSIVE" },
			{ Key = "Ultimate", Level = 5, Kind = "ULTIMATE" },
			{ Key = "Crits", Level = 8, Kind = "CRITS" },
			{ Key = "ParryFlow", Level = 10, Kind = "PASSIVE" },
			{ Key = "ParryDamage", Level = 12, Kind = "STAT" },
			{ Key = "ArmorShredder", Level = 15, Kind = "PASSIVE" },
			{ Key = "Cooldown", Level = 20, Kind = "STAT" },
		},
		-- "Natural Regen is Halved" is taken as health regen.
		Penalties = { MaxStamina = -25, AbilityDamage = -20, AbilityCooldown = 10, HealthRegen = -50 },
	},
	Diamond = {
		Shape = "Brilliant",
		Icon = UIIcons.Get("core_diamond", "rbxassetid://743807896"),
		Colour = Color3.fromRGB(175, 225, 245),
		Light = Color3.fromRGB(255, 255, 255),
		Dark = Color3.fromRGB(85, 145, 185),
		Stats = {
			{ Key = "Health", Base = 25, Per = 2 },
			{ Key = "Healing", Base = 10, Per = 1 },
			{ Key = "DamageTaken", Base = 10, Per = 0.25, Sign = "-", Unlock = 20 },
		},
		Milestones = {
			{ Key = "Taunt", Level = 0, Kind = "PASSIVE" },
			{ Key = "Ultimate", Level = 5, Kind = "ULTIMATE" },
			{ Key = "Lifeline", Level = 10, Kind = "PASSIVE" },
			{ Key = "Reflective", Level = 15, Kind = "PASSIVE" },
			{ Key = "DamageTaken", Level = 20, Kind = "STAT" },
		},
		Penalties = { WeaponDamage = -25, AbilityDamage = -25, WeaponCooldown = 10, AbilityCooldown = 10 },
	},
}

-- The words, from GameText.Cores: DisplayName, Class, Focus, Tagline,
-- Description, Favoured, each stat's Label, each milestone's Name,
-- Description and KindText, Ultimate, Aura and Drawbacks.
for Key, Core in pairs(CoreData.Cores) do
	local Text = GameText.Table("Cores." .. Key) or {}
	Core.DisplayName = Text.Name or Key
	Core.Class = Text.Class or ""
	Core.Focus = Text.Focus or ""
	Core.Tagline = Text.Tagline or ""
	Core.Description = Text.Description or ""
	Core.Favoured = Core.FavouredKey and (Text.Favoured or Core.FavouredKey) or nil
	local StatNames = Text.Stats or {}
	for _, Stat in ipairs(Core.Stats) do
		Stat.Label = StatNames[Stat.Key] or Stat.Key
	end
	local Steps = Text.Milestones or {}
	for _, Step in ipairs(Core.Milestones) do
		local StepText = Steps[Step.Key] or {}
		Step.Name = StepText.Name or Step.Key
		Step.Description = StepText.Description or ""
		Step.KindText = GameText.Get("Cores.Kinds." .. Step.Kind)
	end
	Core.Ultimate = Text.Ultimate or { Name = "", Description = "", Charge = "" }
	Core.Aura = Text.Aura or { Name = "", Description = "" }
	Core.Drawbacks = Text.Drawbacks or {}
end

-- Old menus read Path; the milestones replaced it.
for _, Core in pairs(CoreData.Cores) do
	Core.Path = {}
end

function CoreData.Get(Key: any)
	return type(Key) == "string" and CoreData.Cores[Key] or nil
end

-- Enlightenment needed to go from Level to Level + 1.
function CoreData.XPForLevel(Level: number): number
	local S = CoreData.Settings
	return S.FirstLevel + (Level - 1) * S.PerLevel
end

-- Returns the level for a total Enlightenment, the amount into that
-- level, and what that level needs (0 at max level).
function CoreData.FromXP(TotalXP: number?): (number, number, number)
	local Level = 1
	local Left = math.max(0, math.floor(TotalXP or 0))
	while Level < CoreData.Settings.MaxLevel and Left >= CoreData.XPForLevel(Level) do
		Left -= CoreData.XPForLevel(Level)
		Level += 1
	end
	if Level >= CoreData.Settings.MaxLevel then
		return Level, 0, 0
	end
	return Level, Left, CoreData.XPForLevel(Level)
end

-- A stat's value (in %) at a core level, or nil while it is locked.
function CoreData.StatValue(Stat: any, Level: number): number?
	if Stat.Unlock and Level < Stat.Unlock then
		return nil
	end
	local From = Stat.Unlock or 1
	local Value = Stat.Base + (Stat.Per or 0) * (Level - From)
	if Stat.Max then
		Value = math.min(Value, Stat.Max)
	end
	return math.floor(Value * 100 + 0.5) / 100
end

-- The core level a core can land critical hits from (its CRITS
-- milestone), or nil if it never can.
function CoreData.CritsAt(Key: any): number?
	local Core = CoreData.Get(Key)
	for _, Step in ipairs(Core and Core.Milestones or {}) do
		if Step.Kind == "CRITS" then
			return Step.Level
		end
	end
	return nil
end

-- "+12%", "-10%", or nil while locked.
function CoreData.StatText(Stat: any, Level: number): string?
	local Value = CoreData.StatValue(Stat, Level)
	if not Value then
		return nil
	end
	return (Stat.Sign or "+") .. tostring(Value) .. "%"
end

-- The headline bonus for a core at a level, like "+12% weapon damage"
-- (its first stats, joined).
function CoreData.BonusText(Key: string, Level: number): string
	local Core = CoreData.Get(Key)
	if not Core then
		return ""
	end
	local Parts = {}
	for _, Stat in ipairs(Core.Stats or {}) do
		local Text = CoreData.StatText(Stat, Level)
		if Text and #Parts < 2 then
			table.insert(Parts, Text .. " " .. string.lower(Stat.Label))
		end
	end
	return table.concat(Parts, ", ")
end

return CoreData
