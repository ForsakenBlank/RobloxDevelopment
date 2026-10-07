-- CharacterStats
-- A player's full stat sheet, worked out from their save: max health
-- and regen, energy, stamina, damage, defence, resistances, speed,
-- cooldowns, crits and the rest. It comes from three things:
--   1. the base values (Base below, the game place's GameConfig.Player)
--   2. the active core and its level (Shared.CoreData: the core's stat
--      bonuses, and its drawbacks as Penalties)
--   3. the gear being worn (Shared.EquipmentData: every stat line, the
--      armour set and map bonuses, and a core charm's bonus while its
--      core is active)
-- Gear bonuses are added together into one pool first, and that pool is
-- then multiplied with the core's bonuses and drawbacks (the gameplan's
-- power budget), with the gameplan's caps (Caps below).
--
-- The lobby shows it on the Stats screen (Client.Modules.StatsUI) and
-- the server reads it through EquipmentService.Sheet. The game place
-- must use this same module (copy it, with CoreData, EquipmentData,
-- UIIcons and GameText) so a run plays with exactly the numbers the
-- lobby shows: Compute the sheet from the player's save when they
-- arrive, then ForRun turns it into plain numbers and multipliers for
-- its PlayerStats.
--
--   local Sheet = CharacterStats.Compute(SaveData, { Passes = { VIP = true } })
--   Sheet.Values.MaxHealth      -> 112
--   Sheet.Values.WeaponDamage   -> 12.5 (%)
--   CharacterStats.ForRun(Sheet).WeaponDamageMultiplier -> 1.125
--
-- Only numbers here; the stat names are in Shared.GameText.Items.GearStats.

local CoreData = require(script.Parent.CoreData)
local EquipmentData = require(script.Parent.EquipmentData)

local CharacterStats = {}

-- A player's stats before core and gear. Keep these the same as the
-- game place's GameConfig.Player.
CharacterStats.Base = {
	MaxHealth = 100,
	-- Per second.
	HealthRegen = 1,
	MaxEnergy = 100,
	-- Per second.
	EnergyRegen = 1,
	-- Stamina (melee, parries, Frenzy Surge) isn't in the game place
	-- yet; these are its starting numbers.
	MaxStamina = 100,
	StaminaRegen = 10,
	-- % chance once the core can land crits, and % extra damage a crit
	-- does.
	CritChance = 5,
	CritDamage = 50,
}

-- The gameplan's power budget.
CharacterStats.Caps = {
	-- Cooldown reduction from gear, %.
	GearCooldownReduction = 5,
	-- Total cooldown reduction from everything: past SoftCap, only
	-- OverCapRate of the rest counts.
	CooldownSoftCap = 30,
	OverCapRate = 0.5,
	-- Crit chance from gear, %.
	GearCritChance = 8,
	-- Damage reduction from gear, %, and each resistance.
	GearDamageReduction = 20,
	Resist = 50,
	-- Gear can win back at most this share of a core's max health
	-- drawback, so it never cancels Ruby's -20% out.
	DrawbackRecovery = 0.5,
}

-- The stats on the Stats screen, in groups and in order. Hidden ones
-- only show while they aren't 0.
CharacterStats.Groups = {
	{ Key = "Vitals", Stats = { "MaxHealth", "HealthRegen", "MaxEnergy", "EnergyRegen", "MaxStamina", "StaminaRegen" } },
	{ Key = "Defence", Stats = { "DamageReduction", "MeleeResist", "FireResist", "MagicResist", "KnockbackResist", "IgnoreKnockback" } },
	{ Key = "Offence", Stats = { "WeaponDamage", "AbilityDamage", "CritChance", "CritDamage", "WeaponCooldown", "AbilityCooldown", "Lifesteal" } },
	{ Key = "Utility", Stats = { "MoveSpeed", "Healing", "ParryDamage", "ParryWindow", "ReviveSpeed", "CoreCharge", "BloodlustGain", "PickupRange", "CoinGain", "ExpGain", "CashGain" } },
}

-- How each stat is shown.
--   Unit      "" (a number), "/s", "%" or "x"
--   Signed    shows + or - (a change rather than an amount)
--   Lower     lower is better (cooldowns)
--   Hidden    only shown while it isn't 0
CharacterStats.Info = {
	MaxHealth = { Unit = "" },
	HealthRegen = { Unit = "/s" },
	MaxEnergy = { Unit = "" },
	EnergyRegen = { Unit = "/s" },
	MaxStamina = { Unit = "" },
	StaminaRegen = { Unit = "/s" },
	DamageReduction = { Unit = "%", Signed = true },
	MeleeResist = { Unit = "%", Signed = true },
	FireResist = { Unit = "%", Signed = true },
	MagicResist = { Unit = "%", Signed = true },
	KnockbackResist = { Unit = "%", Signed = true },
	IgnoreKnockback = { Unit = "%", Hidden = true },
	WeaponDamage = { Unit = "%", Signed = true },
	AbilityDamage = { Unit = "%", Signed = true },
	CritChance = { Unit = "%" },
	CritDamage = { Unit = "%", Signed = true },
	WeaponCooldown = { Unit = "%", Signed = true, Lower = true },
	AbilityCooldown = { Unit = "%", Signed = true, Lower = true },
	Lifesteal = { Unit = "%" },
	MoveSpeed = { Unit = "%", Signed = true },
	Healing = { Unit = "%", Signed = true },
	ParryDamage = { Unit = "%", Signed = true },
	ParryWindow = { Unit = "%", Signed = true },
	ReviveSpeed = { Unit = "%", Signed = true },
	CoreCharge = { Unit = "%", Signed = true },
	BloodlustGain = { Unit = "%", Signed = true, Hidden = true },
	PickupRange = { Unit = "%", Signed = true },
	CoinGain = { Unit = "%", Signed = true },
	ExpGain = { Unit = "x" },
	CashGain = { Unit = "x" },
}

-- What a sheet is worked out from, besides the save:
--   Passes   { [PassKey] = true } the gamepasses owned (EXP and cash
--            multipliers, the extra accessory slots)
--   DevAll   the developer's UNLOCK ALL (every accessory slot open)
export type Context = {
	Passes: { [string]: any }?,
	DevAll: boolean?,
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function Mult(Percent: number?): number
	return 1 + (Percent or 0) / 100
end

-- To the nearest Step (1, 0.1, 0.01), divided so 1.4 stays 1.4.
local function Round(Value: number, Step: number): number
	local Scale = math.floor(1 / Step + 0.5)
	return math.floor(Value * Scale + 0.5) / Scale
end

local function Trim(Number: number, Decimals: number): string
	local Text = string.format("%." .. Decimals .. "f", Number)
	if string.find(Text, "%.") then
		Text = string.gsub(Text, "0+$", "")
		Text = string.gsub(Text, "%.$", "")
	end
	return Text
end

----------------------------------------------------------------------
-- WHAT IS WORN
----------------------------------------------------------------------

-- The items being worn: armour in its own slots, and accessories in open
-- slots (one of each type; the first one wins, like the server). Returns
-- the items, the armour ids by slot, and the accessory ids by slot ("" in
-- a closed or empty slot).
function CharacterStats.Worn(Data: any, Context: Context?): ({ any }, { [string]: string }, { string })
	local Gear = type(Data.Gear) == "table" and Data.Gear or {}
	local Armour = type(Data.Armor) == "table" and Data.Armor or {}
	local Accessories = type(Data.Accessories) == "table" and Data.Accessories or {}
	local Slots = { Level = tonumber(Data.Level) or 1, Passes = Context and Context.Passes, DevAll = Context and Context.DevAll }

	local Items = {}
	local ArmourIds = {}
	for _, Slot in ipairs(EquipmentData.ArmourSlots) do
		local Id = Armour[Slot]
		local Item = type(Id) == "string" and Gear[Id]
		local Def = Item and EquipmentData.Get(Item.Id)
		if Def and Def.Slot == Slot then
			table.insert(Items, Item)
			ArmourIds[Slot] = Id
		else
			ArmourIds[Slot] = ""
		end
	end

	local AccessoryIds = {}
	local Types = {}
	for Index = 1, #EquipmentData.AccessorySlots do
		local Id = Accessories[Index]
		local Item = type(Id) == "string" and Id ~= "" and Gear[Id]
		local Def = Item and EquipmentData.Get(Item.Id)
		if Def and Def.Kind == "Accessory" and not Types[Def.Type] and EquipmentData.SlotOpen(Index, Slots) then
			Types[Def.Type] = true
			table.insert(Items, Item)
			AccessoryIds[Index] = Id
		else
			AccessoryIds[Index] = ""
		end
	end
	return Items, ArmourIds, AccessoryIds
end

-- The gear pool: every worn line and charm bonus added together (Lines),
-- the set and map bonuses (Sets), and the sets themselves.
function CharacterStats.GearPool(Data: any, Context: Context?): ({ [string]: number }, { [string]: number }, { any })
	local Gear = type(Data.Gear) == "table" and Data.Gear or {}
	local Items, ArmourIds, AccessoryIds = CharacterStats.Worn(Data, Context)
	local Lines, SetLines = {}, {}
	for _, Item in ipairs(Items) do
		for _, Line in ipairs(EquipmentData.Lines(Item)) do
			Lines[Line.Stat] = (Lines[Line.Stat] or 0) + Line.Value
		end
		local Def = EquipmentData.Get(Item.Id)
		if Def and Def.CoreBonus and Def.Core == Data.Core then
			local Stat, Value = Def.CoreBonus[1], Def.CoreBonus[2]
			Lines[Stat] = (Lines[Stat] or 0) + Value
		end
	end
	local Sets = EquipmentData.ActiveSets(Gear, ArmourIds, AccessoryIds)
	for _, Set in ipairs(Sets) do
		for _, Line in ipairs(Set.Lines) do
			SetLines[Line.Stat] = (SetLines[Line.Stat] or 0) + Line.Value
		end
	end
	return Lines, SetLines, Sets
end

-- The active core's bonuses (in %, a reduction negative) at its level,
-- its drawbacks, its key and its level.
function CharacterStats.CoreBonuses(Data: any): ({ [string]: number }, { [string]: number }, string?, number)
	local Key = Data.Core
	local Core = CoreData.Get(Key)
	if not Core then
		return {}, {}, nil, 0
	end
	local Saved = type(Data.Cores) == "table" and Data.Cores or {}
	local Level = CoreData.FromXP(tonumber(Saved[Key]) or 0)
	local Bonus = {}
	for _, Stat in ipairs(Core.Stats or {}) do
		local Value = CoreData.StatValue(Stat, Level)
		if Value then
			Bonus[Stat.Key] = (Bonus[Stat.Key] or 0) + (Stat.Sign == "-" and -Value or Value)
		end
	end
	return Bonus, Core.Penalties or {}, Key, Level
end

----------------------------------------------------------------------
-- THE SHEET
----------------------------------------------------------------------

-- Works out every stat. Data is the save (Core, Cores, Gear, Armor,
-- Accessories, Level). Returns
--   Values     { [Stat] = number } the final numbers
--   Parts      { [Stat] = { { Source, Value } } } what made each one, for
--              hover cards (Source is Base, Core, Gear, Sets, Drawback,
--              Pass; Value is in the stat's unit, % for most)
--   Capped     { [Stat] = true } where a cap was hit
--   Core, CoreLevel, CritsUnlocked, CritsAt, Sets
function CharacterStats.Compute(Data: any, Context: Context?)
	Data = type(Data) == "table" and Data or {}
	Context = Context or {}
	local Base = CharacterStats.Base
	local Caps = CharacterStats.Caps
	local Passes = Context.Passes or {}

	local Lines, SetLines, Sets = CharacterStats.GearPool(Data, Context)
	local Bonus, Penalty, CoreKey, CoreLevel = CharacterStats.CoreBonuses(Data)
	local function Gear(Stat: string): number
		return (Lines[Stat] or 0) + (SetLines[Stat] or 0)
	end

	local Values, Parts, Capped = {}, {}, {}
	local function Part(Stat: string, Source: string, Value: number?)
		if Value and math.abs(Value) > 1e-9 then
			Parts[Stat] = Parts[Stat] or {}
			table.insert(Parts[Stat], { Source = Source, Value = Value })
		end
	end
	local function GearParts(Stat: string)
		Part(Stat, "Gear", Lines[Stat])
		Part(Stat, "Sets", SetLines[Stat])
	end

	-- Vitals.
	do
		local CoreMult = Mult(Bonus.Health)
		local Drawback = Penalty.MaxHealth or 0
		local Multiplier = CoreMult * Mult(Gear("MaxHealth")) * Mult(Drawback)
		if Drawback < 0 then
			local Ceiling = CoreMult * (1 + Drawback / 100 * (1 - Caps.DrawbackRecovery))
			if Multiplier > Ceiling then
				Multiplier = Ceiling
				Capped.MaxHealth = true
			end
		end
		Values.MaxHealth = Round(Base.MaxHealth * Multiplier, 1)
		Part("MaxHealth", "Base", Base.MaxHealth)
		Part("MaxHealth", "Core", Bonus.Health)
		GearParts("MaxHealth")
		Part("MaxHealth", "Drawback", Drawback)
	end
	Values.HealthRegen = Round(Base.HealthRegen * Mult(Gear("HealthRegen")) * Mult(Penalty.HealthRegen), 0.01)
	Part("HealthRegen", "Base", Base.HealthRegen)
	GearParts("HealthRegen")
	Part("HealthRegen", "Drawback", Penalty.HealthRegen)

	Values.MaxEnergy = Round(Base.MaxEnergy * Mult(Bonus.Energy) * Mult(Gear("MaxEnergy")), 1)
	Part("MaxEnergy", "Base", Base.MaxEnergy)
	Part("MaxEnergy", "Core", Bonus.Energy)
	Values.EnergyRegen = Round(Base.EnergyRegen * Mult(Gear("EnergyRegen")), 0.01)
	Part("EnergyRegen", "Base", Base.EnergyRegen)
	GearParts("EnergyRegen")

	Values.MaxStamina = Round(Base.MaxStamina * Mult(Penalty.MaxStamina), 1)
	Part("MaxStamina", "Base", Base.MaxStamina)
	Part("MaxStamina", "Drawback", Penalty.MaxStamina)
	Values.StaminaRegen = Round(Base.StaminaRegen * Mult(Gear("StaminaRegen")), 0.01)
	Part("StaminaRegen", "Base", Base.StaminaRegen)
	GearParts("StaminaRegen")

	-- Defence. Damage reduction is 1 - the share of damage still taken.
	do
		local FromGear = Gear("DamageReduction")
		if FromGear > Caps.GearDamageReduction then
			FromGear = Caps.GearDamageReduction
			Capped.DamageReduction = true
		end
		local Taken = (1 - FromGear / 100) * Mult(Bonus.DamageTaken) * Mult(Penalty.DamageTaken)
		Values.DamageReduction = Round((1 - Taken) * 100, 0.1)
		Part("DamageReduction", "Core", Bonus.DamageTaken and -Bonus.DamageTaken)
		GearParts("DamageReduction")
		Part("DamageReduction", "Drawback", Penalty.DamageTaken and -Penalty.DamageTaken)
	end
	for _, Stat in ipairs({ "MeleeResist", "FireResist", "MagicResist", "KnockbackResist" }) do
		local Value = Gear(Stat)
		if Value > Caps.Resist then
			Value = Caps.Resist
			Capped[Stat] = true
		end
		Values[Stat] = Round(Value, 0.1)
		GearParts(Stat)
	end
	Values.IgnoreKnockback = Round(Gear("IgnoreKnockback"), 0.1)
	GearParts("IgnoreKnockback")

	-- Offence.
	do
		local CoreWeapon = (Bonus.WeaponDamage or 0) + (Bonus.OverallDamage or 0)
		local Weapon = Mult(CoreWeapon) * Mult(Gear("WeaponDamage")) * Mult(Penalty.WeaponDamage)
		Values.WeaponDamage = Round((Weapon - 1) * 100, 0.1)
		Part("WeaponDamage", "Core", CoreWeapon)
		GearParts("WeaponDamage")
		Part("WeaponDamage", "Drawback", Penalty.WeaponDamage)

		local CoreAbility = (Bonus.MagicDamage or 0) + (Bonus.OverallDamage or 0)
		local Ability = Mult(CoreAbility) * Mult(Gear("AbilityDamage")) * Mult(Penalty.AbilityDamage)
		Values.AbilityDamage = Round((Ability - 1) * 100, 0.1)
		Part("AbilityDamage", "Core", CoreAbility)
		GearParts("AbilityDamage")
		Part("AbilityDamage", "Drawback", Penalty.AbilityDamage)
	end
	local CritsAt = CoreData.CritsAt(CoreKey)
	local CritsUnlocked = CritsAt ~= nil and CoreLevel >= CritsAt
	do
		local FromGear = Gear("CritChance")
		if FromGear > Caps.GearCritChance then
			FromGear = Caps.GearCritChance
			Capped.CritChance = true
		end
		Values.CritChance = CritsUnlocked and Round(Base.CritChance + FromGear, 0.1) or 0
		if CritsUnlocked then
			Part("CritChance", "Base", Base.CritChance)
			GearParts("CritChance")
		end
		Values.CritDamage = Round(Base.CritDamage + Gear("CritDamage"), 0.1)
		Part("CritDamage", "Base", Base.CritDamage)
		GearParts("CritDamage")
	end
	-- Cooldowns: the core's and gear's reductions together (soft capped),
	-- then the drawback on top. Negative is faster.
	local function Cooldown(Stat: string, CoreReduction: number, Drawback: number?)
		local FromGear = Gear("CooldownReduction")
		if FromGear > Caps.GearCooldownReduction then
			FromGear = Caps.GearCooldownReduction
			Capped[Stat] = true
		end
		local Reduction = (1 - (1 - CoreReduction / 100) * (1 - FromGear / 100)) * 100
		if Reduction > Caps.CooldownSoftCap then
			Reduction = Caps.CooldownSoftCap + (Reduction - Caps.CooldownSoftCap) * Caps.OverCapRate
			Capped[Stat] = true
		end
		local Multiplier = (1 - Reduction / 100) * Mult(Drawback)
		Values[Stat] = Round((Multiplier - 1) * 100, 0.1)
		Part(Stat, "Core", -CoreReduction)
		Part(Stat, "Gear", -FromGear)
		Part(Stat, "Drawback", Drawback)
	end
	Cooldown("WeaponCooldown", -(Bonus.WeaponCooldown or 0), Penalty.WeaponCooldown)
	Cooldown("AbilityCooldown", -(Bonus.AbilityCooldown or 0), Penalty.AbilityCooldown)
	Values.Lifesteal = Round(Gear("Lifesteal"), 0.01)
	GearParts("Lifesteal")

	-- Utility.
	do
		local Speed = Mult(Bonus.Speed) * Mult(Gear("MoveSpeed")) * Mult(Penalty.MoveSpeed)
		Values.MoveSpeed = Round((Speed - 1) * 100, 0.1)
		Part("MoveSpeed", "Core", Bonus.Speed)
		GearParts("MoveSpeed")
		Part("MoveSpeed", "Drawback", Penalty.MoveSpeed)

		local Healing = Mult(Bonus.Healing) * Mult(Gear("Healing"))
		Values.Healing = Round((Healing - 1) * 100, 0.1)
		Part("Healing", "Core", Bonus.Healing)
		GearParts("Healing")

		Values.ParryDamage = Round((Bonus.ParryDamage or 0) + Gear("ParryDamage"), 0.1)
		Part("ParryDamage", "Core", Bonus.ParryDamage)
		GearParts("ParryDamage")
	end
	for _, Stat in ipairs({ "ParryWindow", "ReviveSpeed", "CoreCharge", "BloodlustGain", "PickupRange", "CoinGain" }) do
		Values[Stat] = Round(Gear(Stat), 0.1)
		GearParts(Stat)
	end
	Values.ExpGain = (Passes.DoubleExp and 2 or 1) * (Passes.VIP and 1.25 or 1)
	Values.CashGain = Passes.VIP and 1.25 or 1
	if Passes.DoubleExp then
		Part("ExpGain", "Pass", 2)
	end
	if Passes.VIP then
		Part("ExpGain", "Pass", 1.25)
		Part("CashGain", "Pass", 1.25)
	end

	return {
		Values = Values,
		Parts = Parts,
		Capped = Capped,
		Core = CoreKey,
		CoreLevel = CoreLevel,
		CritsUnlocked = CritsUnlocked,
		CritsAt = CritsAt,
		Sets = Sets,
		GearLines = Lines,
		SetLines = SetLines,
	}
end

----------------------------------------------------------------------
-- SHOWING IT
----------------------------------------------------------------------

-- A stat's value as shown: "112", "1.25/s", "+12.5%", "-10%", "x2.5".
function CharacterStats.Format(Stat: string, Value: number): string
	local Info = CharacterStats.Info[Stat] or { Unit = "%" }
	if Info.Unit == "" then
		return tostring(math.floor(Value + 0.5))
	elseif Info.Unit == "/s" then
		return Trim(Value, 2) .. "/s"
	elseif Info.Unit == "x" then
		return "x" .. Trim(Value, 2)
	end
	local Text = Trim(math.abs(Value), 2) .. "%"
	if math.abs(Value) < 0.005 then
		return "0%"
	end
	if Info.Signed then
		return (Value < 0 and "-" or "+") .. Text
	end
	return (Value < 0 and "-" or "") .. Text
end

-- Whether a value is better than having nothing (1), worse (-1) or the
-- same (0), for colouring it.
function CharacterStats.Tone(Stat: string, Value: number): number
	local Info = CharacterStats.Info[Stat] or {}
	local Start = CharacterStats.Base[Stat]
	if Info.Unit == "x" then
		Start = 1
	elseif Info.Unit == "%" then
		Start = 0
	end
	if Stat == "CritChance" then
		return 0
	end
	local Diff = Value - (Start or 0)
	if math.abs(Diff) < 1e-6 then
		return 0
	end
	if Info.Lower then
		Diff = -Diff
	end
	return Diff > 0 and 1 or -1
end

-- Whether a stat shows on the Stats screen.
function CharacterStats.Shown(Stat: string, Value: number): boolean
	local Info = CharacterStats.Info[Stat] or {}
	return not Info.Hidden or math.abs(Value) > 1e-6
end

----------------------------------------------------------------------
-- FOR A RUN
----------------------------------------------------------------------

-- Plain numbers for the game place: what to start a player's run stats
-- with and the multipliers to put on damage, cooldowns, speed and the
-- rest. Multipliers are 1 for no change; chances and Lifesteal are 0 to
-- 1.
function CharacterStats.ForRun(Sheet: any): { [string]: any }
	local V = Sheet.Values
	return {
		MaxHealth = V.MaxHealth,
		MaxEnergy = V.MaxEnergy,
		HealthRegenPerSecond = V.HealthRegen,
		EnergyRegenPerSecond = V.EnergyRegen,
		MaxStamina = V.MaxStamina,
		StaminaRegenPerSecond = V.StaminaRegen,
		-- Ruby: no health regen while in combat.
		NoHealthRegenInCombat = Sheet.Core == "Ruby",

		DamageTakenMultiplier = 1 - V.DamageReduction / 100,
		MeleeDamageTakenMultiplier = 1 - V.MeleeResist / 100,
		FireDamageTakenMultiplier = 1 - V.FireResist / 100,
		MagicDamageTakenMultiplier = 1 - V.MagicResist / 100,
		KnockbackMultiplier = 1 - V.KnockbackResist / 100,
		IgnoreKnockbackChance = V.IgnoreKnockback / 100,

		WeaponDamageMultiplier = 1 + V.WeaponDamage / 100,
		AbilityDamageMultiplier = 1 + V.AbilityDamage / 100,
		CritsEnabled = Sheet.CritsUnlocked == true,
		CritChance = V.CritChance / 100,
		CritDamageMultiplier = 1 + V.CritDamage / 100,
		WeaponCooldownMultiplier = 1 + V.WeaponCooldown / 100,
		AbilityCooldownMultiplier = 1 + V.AbilityCooldown / 100,
		Lifesteal = V.Lifesteal / 100,

		SpeedMultiplier = 1 + V.MoveSpeed / 100,
		HealingMultiplier = 1 + V.Healing / 100,
		ParryDamageMultiplier = 1 + V.ParryDamage / 100,
		ParryWindowMultiplier = 1 + V.ParryWindow / 100,
		ReviveSpeedMultiplier = 1 + V.ReviveSpeed / 100,
		CoreChargeMultiplier = 1 + V.CoreCharge / 100,
		BloodlustGainMultiplier = 1 + V.BloodlustGain / 100,
		PickupRangeMultiplier = 1 + V.PickupRange / 100,
		CoinMultiplier = 1 + V.CoinGain / 100,
		ExpMultiplier = V.ExpGain,
		CashMultiplier = V.CashGain,
	}
end

return CharacterStats
