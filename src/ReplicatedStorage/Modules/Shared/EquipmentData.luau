-- EquipmentData
-- The Velocity Equipment System (Velocity/VelocityGameplan.md, "Velocity
-- Equipment System"): every armour piece and accessory, the rarities,
-- stars and stat lines gear rolls, armour sets, accessory types and map
-- bonuses, the accessory slots, and the numbers for dismantling and
-- rerolling. Only numbers and keys live here; the words are in
-- Shared.GameText.Items.
--
-- Gear is owned as items. Each one is its own record in the save's Gear
-- table, keyed by a short id ("g3f9a..."):
--   Id        which piece it is (a key in Items below)
--   Rarity    Common, Good, Rare, Epic or Legendary
--   Stars     1 to 5, rolled once and never changed
--   Lines     its stat lines, { { Stat = "CritChance", Roll = 1.04 } }.
--             A line's value is the stat's base value (Stats below,
--             armour or accessory) x the rarity's Multiplier x the
--             stars' multiplier x Roll (0.9 to 1.1). See LineValue.
--             An accessory's first line is always its own stat (Stat on
--             the item); the rest are rolled.
--   Rerolls   how many times it has been rerolled (rerolls cost more)
--   Got       os.time() it was found (SORT: NEWEST)
--   Dev       true on the copies the developer's UNLOCK ALL hands out;
--             they are taken back when it is switched off
-- Armor ({ Helmet, Chestplate, Boots }) and Accessories (one entry per
-- slot) in the save hold the ids of what is worn, "" for an empty slot.
--
-- Accessory slots: the first is always open, the second opens at level
-- 10, the third at level 25, and the +2 Accessory Slots gamepass opens
-- the last two (AccessorySlots). Any accessory goes in any open slot,
-- but only one of each Type can be worn at once (so only one charm),
-- and the same stat can only be on MaxSameStat worn accessories.
--
-- Everything that changes gear happens on the server
-- (Server.Services.EquipmentService): it rolls new items with NewItem,
-- checks every equip with CheckAccessories and rerolls with Reroll. The
-- client only shows it (Client.Modules.LoadoutUI). Shared.CharacterStats
-- adds up what is worn. The game place needs this module too (copy it,
-- with UIIcons and GameText) to drop gear and apply the stats in a run.

local UIIcons = require(script.Parent.UIIcons)
local GameText = require(script.Parent.GameText)

local EquipmentData = {}

----------------------------------------------------------------------
-- RARITIES AND STARS
----------------------------------------------------------------------

EquipmentData.RarityOrder = { "Common", "Good", "Rare", "Epic", "Legendary" }

-- Colour          card edges, bars and outlines
-- TextColour      the same colour, dark enough to read on white
-- Multiplier      on every stat value of the item
-- ArmourLines / AccessoryLines   how many stat lines it has
-- Scrap           what dismantling one gives (more with stars)
EquipmentData.Rarities = {
	Common = { Order = 1, Colour = Color3.fromRGB(150, 158, 172), TextColour = Color3.fromRGB(104, 112, 128), Multiplier = 1.00, ArmourLines = 1, AccessoryLines = 1, Scrap = 2 },
	Good = { Order = 2, Colour = Color3.fromRGB(56, 200, 96), TextColour = Color3.fromRGB(24, 148, 62), Multiplier = 1.15, ArmourLines = 2, AccessoryLines = 1, Scrap = 4 },
	Rare = { Order = 3, Colour = Color3.fromRGB(60, 140, 255), TextColour = Color3.fromRGB(32, 102, 224), Multiplier = 1.30, ArmourLines = 2, AccessoryLines = 1, Scrap = 8 },
	Epic = { Order = 4, Colour = Color3.fromRGB(165, 90, 245), TextColour = Color3.fromRGB(128, 58, 210), Multiplier = 1.50, ArmourLines = 3, AccessoryLines = 2, Scrap = 16 },
	Legendary = { Order = 5, Colour = Color3.fromRGB(255, 190, 30), TextColour = Color3.fromRGB(186, 122, 0), Multiplier = 1.75, ArmourLines = 3, AccessoryLines = 2, Scrap = 32 },
}

EquipmentData.Stars = {
	Max = 5,
	-- On top of the rarity multiplier, by star count.
	Multipliers = { 1.00, 1.10, 1.20, 1.35, 1.50 },
	-- Chance (out of 100) of each star count when an item drops or is
	-- bought.
	Odds = { 40, 30, 18, 9, 3 },
}

-- Every line rolls somewhere between Min and Max of its full value.
-- VALUES ONLY moves it by up to Spread either way, so it stays near
-- what it was.
EquipmentData.Roll = {
	Min = 0.9,
	Max = 1.1,
	Spread = 0.06,
}

----------------------------------------------------------------------
-- STATS
----------------------------------------------------------------------

-- Every stat gear can have, all in %. Group is the stat's own rarity:
-- rarer stats are stronger and roll less often. Armour and Accessory
-- are its base value on each (accessories are about a third of
-- armour). Group "Bonus" stats never roll on a line; they only come
-- from set bonuses and core charms.
EquipmentData.Stats = {
	MaxHealth = { Group = "Common", Armour = 3, Accessory = 1 },
	HealthRegen = { Group = "Common", Armour = 2, Accessory = 0.75 },
	StaminaRegen = { Group = "Common", Armour = 2, Accessory = 1 },
	CoinGain = { Group = "Common", Armour = 5, Accessory = 2 },
	PickupRange = { Group = "Common", Armour = 12, Accessory = 5 },

	EnergyRegen = { Group = "Good", Armour = 3, Accessory = 1 },
	MeleeResist = { Group = "Good", Armour = 3, Accessory = 1 },
	FireResist = { Group = "Good", Armour = 3, Accessory = 1 },
	MagicResist = { Group = "Good", Armour = 3, Accessory = 1 },
	KnockbackResist = { Group = "Good", Armour = 4, Accessory = 1.5 },

	DamageReduction = { Group = "Rare", Armour = 1.5, Accessory = 0.5 },
	MoveSpeed = { Group = "Rare", Armour = 1, Accessory = 0.5 },
	WeaponDamage = { Group = "Rare", Armour = 1.5, Accessory = 0.5 },
	AbilityDamage = { Group = "Rare", Armour = 1.5, Accessory = 0.5 },
	CooldownReduction = { Group = "Rare", Armour = 0.75, Accessory = 0.25 },

	CritChance = { Group = "Epic", Armour = 1, Accessory = 0.5 },
	CritDamage = { Group = "Epic", Armour = 3, Accessory = 1 },
	ParryWindow = { Group = "Epic", Armour = 4, Accessory = 1.5 },

	Lifesteal = { Group = "Legendary", Armour = 0.5, Accessory = 0.25 },
	ReviveSpeed = { Group = "Legendary", Armour = 6, Accessory = 2 },
	CoreCharge = { Group = "Legendary", Armour = 3, Accessory = 1 },

	-- Set bonuses and charms only.
	IgnoreKnockback = { Group = "Bonus" },
	BloodlustGain = { Group = "Bonus" },
	ParryDamage = { Group = "Bonus" },
	Healing = { Group = "Bonus" },
}

-- The stats in each stat rarity, in the order they're listed.
EquipmentData.StatGroups = {
	Common = { "MaxHealth", "HealthRegen", "StaminaRegen", "CoinGain", "PickupRange" },
	Good = { "EnergyRegen", "MeleeResist", "FireResist", "MagicResist", "KnockbackResist" },
	Rare = { "DamageReduction", "MoveSpeed", "WeaponDamage", "AbilityDamage", "CooldownReduction" },
	Epic = { "CritChance", "CritDamage", "ParryWindow" },
	Legendary = { "Lifesteal", "ReviveSpeed", "CoreCharge" },
}

-- Each rolled line picks a stat rarity with these chances (out of 100)
-- by the item's rarity, then a stat from that rarity. A Legendary
-- stat can only be the last line of a Legendary item.
EquipmentData.StatOdds = {
	Common = { Common = 80, Good = 20 },
	Good = { Common = 60, Good = 33, Rare = 7 },
	Rare = { Common = 40, Good = 38, Rare = 20, Epic = 2 },
	Epic = { Common = 25, Good = 35, Rare = 30, Epic = 10 },
	Legendary = { Common = 10, Good = 30, Rare = 40, Epic = 18, Legendary = 2 },
}

----------------------------------------------------------------------
-- SLOTS AND RULES
----------------------------------------------------------------------

-- Armour slots, in the order shown (top to bottom).
EquipmentData.ArmourSlots = { "Helmet", "Chestplate", "Boots" }

-- An empty slot's picture.
EquipmentData.SlotIcons = {
	Helmet = UIIcons.Get("armour_helmet"),
	Chestplate = UIIcons.Get("armour_chest"),
	Boots = UIIcons.Get("armour_boots"),
	Accessory = UIIcons.Get("eq_acc"),
}

-- The accessory slots, in order, and what opens each: a player level,
-- or a gamepass (a key in Shared.SkinData.Passes).
EquipmentData.AccessorySlots = {
	{ Level = 1 },
	{ Level = 10 },
	{ Level = 25 },
	{ Pass = "AccessorySlots" },
	{ Pass = "AccessorySlots" },
}

-- Accessory types, in the order they're listed. Only one of each can
-- be worn at a time.
EquipmentData.AccessoryTypes = { "Face", "Head", "Neck", "Back", "Hand", "Pin", "Charm" }

EquipmentData.Rules = {
	-- Only one accessory of each Type worn at once.
	OnePerType = true,
	-- The same stat can only be on this many worn accessories (stops
	-- five copies of the best one).
	MaxSameStat = 2,
	-- The most gear one player can hold. Anything found past it goes
	-- straight to Scrap (EquipmentService.Grant).
	MaxItems = 150,
}

----------------------------------------------------------------------
-- SETS
----------------------------------------------------------------------

-- Armour sets: a bonus for wearing 2 pieces, and more for all 3 (the 3
-- piece bonus is on top of the 2 piece one). Positive bonuses scale with
-- the lowest rarity piece worn (its Multiplier); penalties don't.
EquipmentData.Sets = {
	City = {
		Pieces = { "CourierCap", "CourierJacket", "CourierSneakers" },
		Bonuses = {
			[2] = { { "StaminaRegen", 2 } },
			[3] = { { "MoveSpeed", 3 }, { "PickupRange", 5 } },
		},
	},
	Street = {
		Pieces = { "HoodieHood", "StreetHoodie", "HeavyBoots" },
		Bonuses = {
			[2] = { { "MeleeResist", 3 } },
			[3] = { { "KnockbackResist", 4 }, { "MoveSpeed", -2 } },
		},
	},
	Retro = {
		Pieces = { "BrickHelmet", "ClassicTorso", "PlankBoots" },
		Bonuses = {
			[2] = { { "MaxHealth", 3 } },
			[3] = { { "DamageReduction", 3 }, { "KnockbackResist", 5 }, { "MoveSpeed", -2 } },
		},
	},
	Noob = {
		Pieces = { "NoobCap", "NoobShirt", "NoobShoes" },
		Bonuses = {
			[2] = { { "CoinGain", 2 } },
			[3] = { { "WeaponDamage", 1 }, { "HealthRegen", 2 } },
		},
	},
	Guest = {
		Pieces = { "GuestMask", "GuestJacket", "GuestBoots" },
		Bonuses = {
			[2] = { { "CritChance", 2 } },
			[3] = { { "DamageReduction", 3 }, { "WeaponDamage", 2 }, { "IgnoreKnockback", 10 } },
		},
	},
}
EquipmentData.SetOrder = { "City", "Street", "Retro", "Noob", "Guest" }

-- Accessories from the same map: 2 and 3 worn (3 is on top of 2).
EquipmentData.MapSets = {
	City = {
		[2] = { { "MoveSpeed", 1 } },
		[3] = { { "CoinGain", 2 } },
	},
	Retro = {
		[2] = { { "MaxHealth", 1 } },
		[3] = { { "CritChance", 1 } },
	},
}
EquipmentData.MapSetOrder = { "City", "Retro" }

----------------------------------------------------------------------
-- ITEMS
----------------------------------------------------------------------

-- Armour has a Slot (and a Set); everything else is an accessory with a
-- Type. Icon is a name in Shared.UIIcons.
--   Stat       an accessory's own stat (always its first line)
--   Map        the map an accessory is from (for MapSets)
--   Core       a core charm's core; CoreBonus { Stat, Value } is added
--              on top while that core is active
--   Cosmetic   looks only: always Common, 1 star, one Common stat at
--              its lowest value, and it can't be rerolled
--   Rarities   the only rarities it comes in (the Guest Pin's Core
--              Charge is a Legendary stat)
EquipmentData.Items = {
	-- City set (map 1, balanced and light).
	CourierCap = { Slot = "Helmet", Set = "City", Icon = "city_cap" },
	CourierJacket = { Slot = "Chestplate", Set = "City", Icon = "city_jacket" },
	CourierSneakers = { Slot = "Boots", Set = "City", Icon = "city_sneakers" },
	-- Street set (map 1 rare drop, tougher).
	HoodieHood = { Slot = "Helmet", Set = "Street", Icon = "street_hood" },
	StreetHoodie = { Slot = "Chestplate", Set = "Street", Icon = "street_hoodie" },
	HeavyBoots = { Slot = "Boots", Set = "Street", Icon = "street_boots" },
	-- Retro set (map 2, classic bricks).
	BrickHelmet = { Slot = "Helmet", Set = "Retro", Icon = "retro_helmet" },
	ClassicTorso = { Slot = "Chestplate", Set = "Retro", Icon = "retro_torso" },
	PlankBoots = { Slot = "Boots", Set = "Retro", Icon = "retro_boots" },
	-- Noob set (map 2 early drops).
	NoobCap = { Slot = "Helmet", Set = "Noob", Icon = "noob_cap" },
	NoobShirt = { Slot = "Chestplate", Set = "Noob", Icon = "noob_shirt" },
	NoobShoes = { Slot = "Boots", Set = "Noob", Icon = "noob_shoes" },
	-- Guest set (Retroscity Impossible only).
	GuestMask = { Slot = "Helmet", Set = "Guest", Icon = "guest_mask" },
	GuestJacket = { Slot = "Chestplate", Set = "Guest", Icon = "guest_jacket" },
	GuestBoots = { Slot = "Boots", Set = "Guest", Icon = "guest_boots" },

	-- City accessories.
	DeliveryBag = { Type = "Back", Map = "City", Stat = "PickupRange", Icon = "city_delivery_bag" },
	CourierWatch = { Type = "Hand", Map = "City", Stat = "StaminaRegen", Icon = "city_courier_watch" },
	Sunglasses = { Type = "Face", Map = "City", Stat = "CritChance", Icon = "city_sunglasses" },
	IdLanyard = { Type = "Neck", Map = "City", Stat = "CoinGain", Icon = "city_lanyard" },
	Wristband = { Type = "Hand", Map = "City", Stat = "EnergyRegen", Icon = "city_wristband" },
	MetroCard = { Type = "Pin", Map = "City", Stat = "MoveSpeed", Icon = "city_metro_card" },
	-- Retro accessories.
	ClassicCola = { Type = "Pin", Map = "Retro", Stat = "HealthRegen", Icon = "retro_cola" },
	BrickBadge = { Type = "Pin", Map = "Retro", Stat = "MaxHealth", Icon = "retro_brick_badge" },
	TixCoin = { Type = "Neck", Map = "Retro", Stat = "CoinGain", Icon = "retro_tix_coin" },
	OldSchoolVisor = { Type = "Face", Map = "Retro", Stat = "CritChance", Icon = "retro_visor" },
	BuilderToolBelt = { Type = "Back", Map = "Retro", Stat = "PickupRange", Icon = "retro_tool_belt" },
	ObbyMedal = { Type = "Neck", Map = "Retro", Stat = "StaminaRegen", Icon = "retro_obby_medal" },
	CursorPin = { Type = "Pin", Map = "Retro", Stat = "MoveSpeed", Icon = "retro_cursor_pin" },
	OrangeShades = { Type = "Face", Map = "Retro", Stat = "EnergyRegen", Icon = "retro_orange_shades" },
	StudsChain = { Type = "Neck", Map = "Retro", Stat = "WeaponDamage", Icon = "retro_studs_chain" },
	GuestPin = { Type = "Pin", Map = "Retro", Stat = "CoreCharge", Icon = "retro_guest_pin", Rarities = { "Legendary" } },

	-- Core charms.
	RubyCharm = { Type = "Charm", Stat = "WeaponDamage", Core = "Ruby", CoreBonus = { "BloodlustGain", 1 }, Icon = "charm_ruby" },
	SapphireCharm = { Type = "Charm", Stat = "EnergyRegen", Core = "Sapphire", CoreBonus = { "AbilityDamage", 1 }, Icon = "charm_sapphire" },
	AmethystCharm = { Type = "Charm", Stat = "StaminaRegen", Core = "Amethyst", CoreBonus = { "ParryDamage", 1 }, Icon = "charm_amethyst" },
	DiamondCharm = { Type = "Charm", Stat = "MaxHealth", Core = "Diamond", CoreBonus = { "Healing", 1 }, Icon = "charm_diamond" },

	-- Cosmetics.
	PartyHat = { Type = "Head", Cosmetic = true, Icon = "cos_party_hat" },
	TrafficCone = { Type = "Head", Cosmetic = true, Icon = "cos_traffic_cone" },
	BunnyEars = { Type = "Head", Cosmetic = true, Icon = "cos_bunny_ears" },
	PizzaPin = { Type = "Pin", Cosmetic = true, Icon = "cos_pizza_pin" },
	PaperCrown = { Type = "Head", Cosmetic = true, Icon = "cos_paper_crown" },
}

-- Every item, in the order they're listed (armour by set, then
-- accessories). UNLOCK ALL hands out one of each.
EquipmentData.Order = {
	"CourierCap", "CourierJacket", "CourierSneakers",
	"HoodieHood", "StreetHoodie", "HeavyBoots",
	"BrickHelmet", "ClassicTorso", "PlankBoots",
	"NoobCap", "NoobShirt", "NoobShoes",
	"GuestMask", "GuestJacket", "GuestBoots",
	"DeliveryBag", "CourierWatch", "Sunglasses", "IdLanyard", "Wristband", "MetroCard",
	"ClassicCola", "BrickBadge", "TixCoin", "OldSchoolVisor", "BuilderToolBelt",
	"ObbyMedal", "CursorPin", "OrangeShades", "StudsChain", "GuestPin",
	"RubyCharm", "SapphireCharm", "AmethystCharm", "DiamondCharm",
	"PartyHat", "TrafficCone", "BunnyEars", "PizzaPin", "PaperCrown",
}

----------------------------------------------------------------------
-- DROPS, DISMANTLING AND REROLLS
----------------------------------------------------------------------

-- Rarity chances (out of 100) for NewItem by where an item comes from
-- (the gameplan's "How Gear Is Obtained"). The game place picks the
-- source; MaxRarity caps it (Easy mode: no Epic or Legendary).
EquipmentData.DropOdds = {
	Enemy = { Common = 70, Good = 25, Rare = 5 },
	Chest = { Good = 55, Rare = 33, Epic = 12 },
	Boss = { Rare = 60, Epic = 32, Legendary = 8 },
	Shop = { Common = 65, Good = 35 },
	-- UNLOCK ALL's copies: every rarity equally, to test with.
	Dev = { Common = 20, Good = 20, Rare = 20, Epic = 20, Legendary = 20 },
}
-- Every star count equally, for UNLOCK ALL's copies.
EquipmentData.DevStarOdds = { 20, 20, 20, 20, 20 }

EquipmentData.Dismantle = {
	-- Each star past the first adds this share of the rarity's Scrap.
	StarBonus = 0.25,
	-- Scrap for a cosmetic.
	Cosmetic = 1,
}

-- Rerolls cost Scrap and Cash (never Timebux or Robux).
EquipmentData.Reroll = {
	-- Base costs for each mode.
	Modes = {
		One = { Scrap = 4, Cash = 150 },
		All = { Scrap = 10, Cash = 400 },
		Values = { Scrap = 2, Cash = 75 },
	},
	ModeOrder = { "One", "All", "Values" },
	-- Costs multiply by this for the item's rarity.
	RarityCost = { Common = 1, Good = 1.5, Rare = 2, Epic = 3, Legendary = 4 },
	-- Each reroll on the same item adds this much to its cost, up to
	-- MaxEscalation times the base. Every item keeps its own count.
	Escalation = 0.25,
	MaxEscalation = 3,
	-- Extra Scrap per locked line (ALL STATS only), and how many lines
	-- each rarity can lock.
	LockScrap = 5,
	MaxLocks = { Common = 1, Good = 1, Rare = 1, Epic = 1, Legendary = 2 },
}

----------------------------------------------------------------------
-- WORDS AND PICTURES
----------------------------------------------------------------------

for Key, Item in pairs(EquipmentData.Items) do
	Item.Key = Key
	Item.Kind = Item.Slot and "Armour" or "Accessory"
	Item.IconName = Item.Icon
	local Fallback = Item.Slot and EquipmentData.SlotIcons[Item.Slot] or EquipmentData.SlotIcons.Accessory
	Item.Icon = UIIcons.Get(Item.IconName or "", Fallback)
	local Text = GameText.Table("Items." .. (Item.Kind == "Armour" and "Armour" or "Accessories") .. "." .. Key) or {}
	Item.DisplayName = Text.Name or Key
	Item.Description = Text.Description or ""
end

-- The display name of a stat ("Crit Chance").
function EquipmentData.StatName(Stat: string): string
	local Names = GameText.Table("Items.GearStats") or {}
	return Names[Stat] or Stat
end

function EquipmentData.RarityName(Rarity: string?): string
	return GameText.Get("Items.Rarities." .. (Rarity or "Common"))
end

function EquipmentData.RarityColour(Rarity: string?): Color3
	local Info = EquipmentData.Rarities[Rarity or "Common"] or EquipmentData.Rarities.Common
	return Info.Colour
end

function EquipmentData.RarityTextColour(Rarity: string?): Color3
	local Info = EquipmentData.Rarities[Rarity or "Common"] or EquipmentData.Rarities.Common
	return Info.TextColour
end

function EquipmentData.TypeName(Type: string?): string
	return GameText.Get("Items.Types." .. tostring(Type))
end

function EquipmentData.SlotName(Slot: string?): string
	return GameText.Get("Items.Slots." .. tostring(Slot))
end

function EquipmentData.SetName(Set: string?): string
	return GameText.Get("Items.Sets." .. tostring(Set))
end

function EquipmentData.MapName(Map: string?): string
	return GameText.Get("Items.MapSets." .. tostring(Map))
end

-- "★★★☆☆"
function EquipmentData.StarsText(Stars: number?): string
	local Count = math.clamp(math.floor(Stars or 1), 0, EquipmentData.Stars.Max)
	return string.rep("★", Count) .. string.rep("☆", EquipmentData.Stars.Max - Count)
end

-- A value rounded the way it's shown: 2 decimals under 1, 1 decimal
-- under 10, whole numbers above.
function EquipmentData.Round(Value: number): number
	local Size = math.abs(Value)
	-- Divided rather than multiplied by the step, so 1.4 stays 1.4 and
	-- not 1.4000000000000001.
	local Scale = Size < 1 and 100 or (Size < 10 and 10 or 1)
	return math.floor(Value * Scale + 0.5) / Scale
end

-- "+1.2%", "-2%"
function EquipmentData.FormatValue(Value: number): string
	local Rounded = EquipmentData.Round(Value)
	local Text = string.format("%.2f", math.abs(Rounded)):gsub("%.?0+$", "")
	return (Rounded < 0 and "-" or "+") .. Text .. "%"
end

----------------------------------------------------------------------
-- READING ITEMS
----------------------------------------------------------------------

function EquipmentData.Get(Id: any)
	return type(Id) == "string" and EquipmentData.Items[Id] or nil
end

-- How many stat lines an item of this rarity has.
function EquipmentData.LineCount(Def: any, Rarity: string): number
	if Def.Cosmetic then
		return 1
	end
	local Info = EquipmentData.Rarities[Rarity] or EquipmentData.Rarities.Common
	return Def.Kind == "Armour" and Info.ArmourLines or Info.AccessoryLines
end

-- Whether a piece comes in a rarity.
function EquipmentData.AllowsRarity(Def: any, Rarity: string): boolean
	if not EquipmentData.Rarities[Rarity] then
		return false
	end
	if Def.Cosmetic then
		return Rarity == "Common"
	end
	if Def.Rarities then
		return table.find(Def.Rarities, Rarity) ~= nil
	end
	return true
end

-- The nearest rarity a piece comes in (for a save that has one it
-- doesn't any more).
local function NearestRarity(Def: any, Rarity: string): string
	if EquipmentData.AllowsRarity(Def, Rarity) then
		return Rarity
	end
	if Def.Cosmetic then
		return "Common"
	end
	return Def.Rarities and Def.Rarities[1] or "Common"
end

-- Whether Stat can be on a line of this piece at all.
function EquipmentData.CanHaveStat(Def: any, Stat: any): boolean
	local Info = type(Stat) == "string" and EquipmentData.Stats[Stat]
	if not Info or Info.Group == "Bonus" then
		return false
	end
	return (Def.Kind == "Armour" and Info.Armour or Info.Accessory) ~= nil
end

-- A line's value in %, as shown.
function EquipmentData.LineValue(Item: any, Line: any): number
	local Def = EquipmentData.Get(Item.Id)
	local Info = EquipmentData.Stats[Line.Stat]
	if not Def or not Info then
		return 0
	end
	local Base = (Def.Kind == "Armour" and Info.Armour or Info.Accessory) or 0
	local Rarity = EquipmentData.Rarities[Item.Rarity] or EquipmentData.Rarities.Common
	local Star = EquipmentData.Stars.Multipliers[Item.Stars or 1] or 1
	return EquipmentData.Round(Base * Rarity.Multiplier * Star * (Line.Roll or 1))
end

-- An item's lines ready to show: { Stat, Value, Group, Fixed, Index }.
-- Fixed is an accessory's own stat (its first line).
function EquipmentData.Lines(Item: any): { any }
	local Def = EquipmentData.Get(Item.Id)
	local Out = {}
	for Index, Line in ipairs(Item.Lines or {}) do
		local Info = EquipmentData.Stats[Line.Stat]
		table.insert(Out, {
			Index = Index,
			Stat = Line.Stat,
			Value = EquipmentData.LineValue(Item, Line),
			Group = Info and Info.Group or "Common",
			Fixed = Def ~= nil and Def.Stat ~= nil and Index == 1 and Line.Stat == Def.Stat,
		})
	end
	return Out
end

-- Whether a line is the accessory's own stat (it can't be rerolled
-- away, only its value).
function EquipmentData.IsFixedLine(Item: any, Index: number): boolean
	local Def = EquipmentData.Get(Item.Id)
	local Line = Item.Lines and Item.Lines[Index]
	return Def ~= nil and Line ~= nil and Def.Stat ~= nil and Index == 1 and Line.Stat == Def.Stat
end

-- Every stat on an item, as a set.
function EquipmentData.StatSet(Item: any): { [string]: boolean }
	local Set = {}
	for _, Line in ipairs(Item and Item.Lines or {}) do
		Set[Line.Stat] = true
	end
	return Set
end

-- Scrap for dismantling an item.
function EquipmentData.ScrapValue(Item: any): number
	local Def = EquipmentData.Get(Item.Id)
	if Def and Def.Cosmetic then
		return EquipmentData.Dismantle.Cosmetic
	end
	local Info = EquipmentData.Rarities[Item.Rarity] or EquipmentData.Rarities.Common
	local Stars = math.clamp(Item.Stars or 1, 1, EquipmentData.Stars.Max)
	return math.floor(Info.Scrap * (1 + EquipmentData.Dismantle.StarBonus * (Stars - 1)) + 0.5)
end

----------------------------------------------------------------------
-- SLOTS
----------------------------------------------------------------------

-- What a player's slots depend on:
--   Level    player level
--   Passes   { [PassKey] = true } owned gamepasses
--   DevAll   the developer's UNLOCK ALL (every slot open)
export type SlotContext = {
	Level: number?,
	Passes: { [string]: any }?,
	DevAll: boolean?,
}

-- Whether accessory slot Index is open, and if not, what opens it
-- ({ Level = 10 } or { Pass = "AccessorySlots" }).
function EquipmentData.SlotOpen(Index: number, Context: SlotContext): (boolean, any)
	local Slot = EquipmentData.AccessorySlots[Index]
	if not Slot then
		return false, nil
	end
	if Context.DevAll then
		return true, Slot
	end
	if Slot.Pass then
		return Context.Passes ~= nil and Context.Passes[Slot.Pass] == true, Slot
	end
	return (Context.Level or 1) >= (Slot.Level or 1), Slot
end

function EquipmentData.OpenSlotCount(Context: SlotContext): number
	local Count = 0
	for Index = 1, #EquipmentData.AccessorySlots do
		if EquipmentData.SlotOpen(Index, Context) then
			Count += 1
		end
	end
	return Count
end

-- "LV 10" or "PASS" for a locked slot's box.
function EquipmentData.SlotLockText(Index: number): string
	local Slot = EquipmentData.AccessorySlots[Index]
	if Slot and Slot.Pass then
		return GameText.Get("Loadout.Gear.SlotPass")
	end
	return GameText.Get("Common.Level", { Level = Slot and Slot.Level or 1 })
end

-- Whether a set of worn accessories follows the rules: one of each Type
-- and no stat on more than MaxSameStat of them. Gear is the save's Gear
-- table, Accessories the list of worn ids ("" for empty). Returns false,
-- the reason (GameText.Messages key) and its blanks when not.
function EquipmentData.CheckAccessories(Gear: { [string]: any }, Accessories: { any }): (boolean, string?, { [string]: any }?)
	local Types = {}
	local StatCount = {}
	for _, Id in ipairs(Accessories) do
		local Item = Id ~= "" and Gear[Id]
		local Def = Item and EquipmentData.Get(Item.Id)
		if Def then
			if EquipmentData.Rules.OnePerType then
				if Types[Def.Type] then
					return false, "Messages.OnePerType", { Type = EquipmentData.TypeName(Def.Type) }
				end
				Types[Def.Type] = true
			end
			for Stat in pairs(EquipmentData.StatSet(Item)) do
				StatCount[Stat] = (StatCount[Stat] or 0) + 1
				if StatCount[Stat] > EquipmentData.Rules.MaxSameStat then
					return false, "Messages.SameStatLimit", { Max = EquipmentData.Rules.MaxSameStat, Stat = EquipmentData.StatName(Stat) }
				end
			end
		end
	end
	return true, nil, nil
end

----------------------------------------------------------------------
-- SET BONUSES
----------------------------------------------------------------------

local function AddBonuses(Out: { any }, Bonuses: { any }?, Multiplier: number)
	for _, Bonus in ipairs(Bonuses or {}) do
		local Value = Bonus[2]
		if Value > 0 then
			Value = EquipmentData.Round(Value * Multiplier)
		end
		table.insert(Out, { Stat = Bonus[1], Value = Value })
	end
end

-- The set and map bonuses a player has on: a list of
-- { Kind = "Set" or "Map", Key, Count, Lines = { { Stat, Value } } }.
-- Armour holds the worn armour ids by slot, Accessories the worn
-- accessory ids (only the ones in open slots should be passed).
function EquipmentData.ActiveSets(Gear: { [string]: any }, Armour: { [string]: any }, Accessories: { any }): { any }
	local Out = {}
	local SetCount, SetLowest = {}, {}
	for _, Slot in ipairs(EquipmentData.ArmourSlots) do
		local Item = Gear[Armour[Slot] or ""]
		local Def = Item and EquipmentData.Get(Item.Id)
		if Def and Def.Set then
			SetCount[Def.Set] = (SetCount[Def.Set] or 0) + 1
			local Order = (EquipmentData.Rarities[Item.Rarity] or EquipmentData.Rarities.Common).Order
			if not SetLowest[Def.Set] or Order < SetLowest[Def.Set] then
				SetLowest[Def.Set] = Order
			end
		end
	end
	for _, Key in ipairs(EquipmentData.SetOrder) do
		local Count = SetCount[Key] or 0
		if Count >= 2 then
			local Lowest = EquipmentData.RarityOrder[SetLowest[Key] or 1]
			local Multiplier = EquipmentData.Rarities[Lowest].Multiplier
			local Lines = {}
			AddBonuses(Lines, EquipmentData.Sets[Key].Bonuses[2], Multiplier)
			if Count >= 3 then
				AddBonuses(Lines, EquipmentData.Sets[Key].Bonuses[3], Multiplier)
			end
			table.insert(Out, { Kind = "Set", Key = Key, Count = Count, Rarity = Lowest, Lines = Lines })
		end
	end

	local MapCount = {}
	for _, Id in ipairs(Accessories) do
		local Item = Id ~= "" and Gear[Id]
		local Def = Item and EquipmentData.Get(Item.Id)
		if Def and Def.Map then
			MapCount[Def.Map] = (MapCount[Def.Map] or 0) + 1
		end
	end
	for _, Key in ipairs(EquipmentData.MapSetOrder) do
		local Count = MapCount[Key] or 0
		if Count >= 2 then
			local Lines = {}
			AddBonuses(Lines, EquipmentData.MapSets[Key][2], 1)
			if Count >= 3 then
				AddBonuses(Lines, EquipmentData.MapSets[Key][3], 1)
			end
			table.insert(Out, { Kind = "Map", Key = Key, Count = Count, Lines = Lines })
		end
	end
	return Out
end

----------------------------------------------------------------------
-- CHECKING SAVED ITEMS
----------------------------------------------------------------------

local function CleanRoll(Value: any): number
	local Roll = EquipmentData.Roll
	if type(Value) ~= "number" or Value ~= Value then
		return 1
	end
	return math.clamp(Value, Roll.Min, Roll.Max)
end

-- A saved item made safe: a known piece, a rarity it comes in, 1 to 5
-- stars, lines with real stats (no repeats, its own stat first), rolls
-- in range. nil if it isn't a known piece at all.
function EquipmentData.CleanItem(Raw: any)
	if type(Raw) ~= "table" then
		return nil
	end
	local Def = EquipmentData.Get(Raw.Id)
	if not Def then
		return nil
	end
	local Rarity = type(Raw.Rarity) == "string" and EquipmentData.Rarities[Raw.Rarity] and Raw.Rarity or "Common"
	Rarity = NearestRarity(Def, Rarity)
	local Stars = math.clamp(math.floor(tonumber(Raw.Stars) or 1), 1, EquipmentData.Stars.Max)
	if Def.Cosmetic then
		Stars = 1
	end
	local Lines, Seen = {}, {}
	if Def.Stat then
		local Roll = 1
		for _, Line in ipairs(type(Raw.Lines) == "table" and Raw.Lines or {}) do
			if type(Line) == "table" and Line.Stat == Def.Stat then
				Roll = CleanRoll(Line.Roll)
			end
		end
		table.insert(Lines, { Stat = Def.Stat, Roll = Roll })
		Seen[Def.Stat] = true
	end
	for _, Line in ipairs(type(Raw.Lines) == "table" and Raw.Lines or {}) do
		if type(Line) == "table" and not Seen[Line.Stat] and EquipmentData.CanHaveStat(Def, Line.Stat) then
			local Info = EquipmentData.Stats[Line.Stat]
			if Info.Group ~= "Legendary" or Rarity == "Legendary" then
				Seen[Line.Stat] = true
				table.insert(Lines, { Stat = Line.Stat, Roll = CleanRoll(Line.Roll) })
			end
		end
	end
	local Max = EquipmentData.LineCount(Def, Rarity)
	while #Lines > Max do
		table.remove(Lines)
	end
	return {
		Id = Def.Key,
		Rarity = Rarity,
		Stars = Stars,
		Lines = Lines,
		Rerolls = math.max(0, math.floor(tonumber(Raw.Rerolls) or 0)),
		Got = tonumber(Raw.Got) or 0,
		Dev = Raw.Dev == true or nil,
	}
end

----------------------------------------------------------------------
-- ROLLING (server)
----------------------------------------------------------------------

-- A key from a { [Key] = weight } table.
local function Weighted(Rng: Random, Weights: { [string]: number }, Order: { string }): string?
	local Total = 0
	for _, Key in ipairs(Order) do
		Total += math.max(0, Weights[Key] or 0)
	end
	if Total <= 0 then
		return nil
	end
	local Pick = Rng:NextNumber() * Total
	for _, Key in ipairs(Order) do
		local Weight = math.max(0, Weights[Key] or 0)
		if Pick < Weight then
			return Key
		end
		Pick -= Weight
	end
	return Order[#Order]
end

local GroupOrder = { "Common", "Good", "Rare", "Epic", "Legendary" }

function EquipmentData.NewRoll(Rng: Random): number
	local Roll = EquipmentData.Roll
	return math.floor((Roll.Min + Rng:NextNumber() * (Roll.Max - Roll.Min)) * 1000 + 0.5) / 1000
end

-- A stat for line Index of an item (Count lines in all), not one of
-- Exclude. nil if every stat is taken.
function EquipmentData.RollStat(Rng: Random, Def: any, Rarity: string, Index: number, Count: number, Exclude: { [string]: boolean }): string?
	local Odds = EquipmentData.StatOdds[Rarity] or EquipmentData.StatOdds.Common
	local Weights = {}
	for _, Group in ipairs(GroupOrder) do
		local Allowed = Group ~= "Legendary" or (Rarity == "Legendary" and Index == Count)
		if Allowed and (Odds[Group] or 0) > 0 then
			for _, Stat in ipairs(EquipmentData.StatGroups[Group]) do
				if not Exclude[Stat] and EquipmentData.CanHaveStat(Def, Stat) then
					Weights[Group] = Odds[Group]
					break
				end
			end
		end
	end
	local Group = Weighted(Rng, Weights, GroupOrder)
	if not Group then
		return nil
	end
	local Choices = {}
	for _, Stat in ipairs(EquipmentData.StatGroups[Group]) do
		if not Exclude[Stat] and EquipmentData.CanHaveStat(Def, Stat) then
			table.insert(Choices, Stat)
		end
	end
	return Choices[Rng:NextInteger(1, #Choices)]
end

-- Options for NewItem:
--   Rarity      force a rarity (if the piece comes in it)
--   Source      a DropOdds key for the rarity chances (default Enemy)
--   RarityOdds  or the chances themselves, { Common = 70, ... }
--   MaxRarity   never above this rarity
--   Stars       force a star count
--   StarOdds    star chances, default Stars.Odds
export type NewItemOptions = {
	Rarity: string?,
	Source: string?,
	RarityOdds: { [string]: number }?,
	MaxRarity: string?,
	Stars: number?,
	StarOdds: { number }?,
}

-- Rolls any lines an item is missing for its rarity (a save from before
-- a rarity got more lines). Changes Item; returns whether it added any.
function EquipmentData.FillLines(Item: any, Rng: Random): boolean
	local Def = EquipmentData.Get(Item.Id)
	if not Def or Def.Cosmetic then
		return false
	end
	local Count = EquipmentData.LineCount(Def, Item.Rarity)
	local Used = EquipmentData.StatSet(Item)
	local Added = false
	while #Item.Lines < Count do
		local Stat = EquipmentData.RollStat(Rng, Def, Item.Rarity, #Item.Lines + 1, Count, Used)
		if not Stat then
			break
		end
		Used[Stat] = true
		table.insert(Item.Lines, { Stat = Stat, Roll = EquipmentData.NewRoll(Rng) })
		Added = true
	end
	return Added
end

-- A brand new item of piece Id (a key in Items), rolled with Rng.
function EquipmentData.NewItem(Id: string, Rng: Random, Options: NewItemOptions?)
	local Def = EquipmentData.Get(Id)
	assert(Def, "[EquipmentData] no item called " .. tostring(Id))
	local Opts = Options or {}

	local Rarity = Opts.Rarity
	if not Rarity or not EquipmentData.AllowsRarity(Def, Rarity) then
		local Odds = Opts.RarityOdds or EquipmentData.DropOdds[Opts.Source or "Enemy"] or EquipmentData.DropOdds.Enemy
		local Weights = {}
		local Max = Opts.MaxRarity and EquipmentData.Rarities[Opts.MaxRarity] and EquipmentData.Rarities[Opts.MaxRarity].Order or math.huge
		for _, Key in ipairs(EquipmentData.RarityOrder) do
			if EquipmentData.Rarities[Key].Order <= Max and EquipmentData.AllowsRarity(Def, Key) then
				Weights[Key] = Odds[Key] or 0
			end
		end
		Rarity = Weighted(Rng, Weights, EquipmentData.RarityOrder) or NearestRarity(Def, "Common")
	end

	local Stars = Opts.Stars and math.clamp(math.floor(Opts.Stars), 1, EquipmentData.Stars.Max) or nil
	if not Stars then
		local Odds = Opts.StarOdds or EquipmentData.Stars.Odds
		local Total, Pick = 0, 0
		for _, Weight in ipairs(Odds) do
			Total += Weight
		end
		Pick = Rng:NextNumber() * Total
		Stars = #Odds
		for Count, Weight in ipairs(Odds) do
			if Pick < Weight then
				Stars = Count
				break
			end
			Pick -= Weight
		end
	end

	local Lines = {}
	if Def.Cosmetic then
		Rarity, Stars = "Common", 1
		local Common = EquipmentData.StatGroups.Common
		table.insert(Lines, { Stat = Common[Rng:NextInteger(1, #Common)], Roll = EquipmentData.Roll.Min })
	else
		local Count = EquipmentData.LineCount(Def, Rarity)
		local Used = {}
		if Def.Stat then
			table.insert(Lines, { Stat = Def.Stat, Roll = EquipmentData.NewRoll(Rng) })
			Used[Def.Stat] = true
		end
		while #Lines < Count do
			local Stat = EquipmentData.RollStat(Rng, Def, Rarity, #Lines + 1, Count, Used)
			if not Stat then
				break
			end
			Used[Stat] = true
			table.insert(Lines, { Stat = Stat, Roll = EquipmentData.NewRoll(Rng) })
		end
	end

	return {
		Id = Def.Key,
		Rarity = Rarity,
		Stars = Stars,
		Lines = Lines,
		Rerolls = 0,
		Got = os.time(),
	}
end

----------------------------------------------------------------------
-- REROLLS (server)
----------------------------------------------------------------------

-- How many lines an item can lock on ALL STATS.
function EquipmentData.MaxLocks(Item: any): number
	return EquipmentData.Reroll.MaxLocks[Item.Rarity] or 1
end

-- Whether an item can be rerolled at all (cosmetics can't).
function EquipmentData.CanReroll(Item: any): boolean
	local Def = EquipmentData.Get(Item.Id)
	return Def ~= nil and not Def.Cosmetic
end

-- What a reroll costs: Scrap, Cash. Locks is how many lines are locked.
function EquipmentData.RerollCost(Item: any, Mode: string, Locks: number?): (number, number)
	local Settings = EquipmentData.Reroll
	local Base = Settings.Modes[Mode] or Settings.Modes.One
	local Rarity = Settings.RarityCost[Item.Rarity] or 1
	local Escalation = math.min(1 + Settings.Escalation * (Item.Rerolls or 0), Settings.MaxEscalation)
	local Scrap = math.ceil(Base.Scrap * Rarity * Escalation)
	if Mode == "All" then
		Scrap += (Locks or 0) * Settings.LockScrap
	end
	local Cash = math.ceil(Base.Cash * Rarity * Escalation / 5) * 5
	return Scrap, Cash
end

local function CopyItem(Item: any)
	local Copy = table.clone(Item)
	Copy.Lines = {}
	for Index, Line in ipairs(Item.Lines or {}) do
		Copy.Lines[Index] = table.clone(Line)
	end
	return Copy
end

-- The item after a reroll, or nil and the reason (a GameText path).
--   One      Line is the line to reroll: a new stat, never the one it had
--   All      every line but the fixed one and those in Locks
--            ({ [LineNumber] = true }) gets a new stat
--   Values   every line keeps its stat; its roll moves a little
-- Rarity and stars never change.
function EquipmentData.RerollItem(Item: any, Mode: string, Rng: Random, Line: number?, Locks: { [number]: boolean }?)
	local Def = EquipmentData.Get(Item.Id)
	if not Def or Def.Cosmetic then
		return nil, "Messages.CantReroll"
	end
	local New = CopyItem(Item)
	New.Rerolls = (Item.Rerolls or 0) + 1
	local Count = #New.Lines
	local Settings = EquipmentData.Roll

	if Mode == "Values" then
		for _, Each in ipairs(New.Lines) do
			local Moved = (Each.Roll or 1) + (Rng:NextNumber() * 2 - 1) * Settings.Spread
			Each.Roll = math.floor(math.clamp(Moved, Settings.Min, Settings.Max) * 1000 + 0.5) / 1000
		end
		return New, nil
	end

	local Used = {}
	for _, Each in ipairs(New.Lines) do
		Used[Each.Stat] = true
	end

	if Mode == "One" then
		if type(Line) ~= "number" or not New.Lines[Line] then
			return nil, "Messages.PickLine"
		end
		if EquipmentData.IsFixedLine(Item, Line) then
			return nil, "Messages.FixedLine"
		end
		-- Used still holds this line's old stat, so it never comes back.
		local Stat = EquipmentData.RollStat(Rng, Def, New.Rarity, Line, Count, Used)
		if not Stat then
			return nil, "Messages.CantReroll"
		end
		New.Lines[Line] = { Stat = Stat, Roll = EquipmentData.NewRoll(Rng) }
		return New, nil
	elseif Mode == "All" then
		Locks = Locks or {}
		local Rerolled = 0
		for Index = 1, Count do
			if not Locks[Index] and not EquipmentData.IsFixedLine(Item, Index) then
				local Old = New.Lines[Index].Stat
				-- Keeps every other line's stat (old and new) out, and this
				-- line's old one.
				local Stat = EquipmentData.RollStat(Rng, Def, New.Rarity, Index, Count, Used)
				if Stat then
					Used[Stat] = true
					New.Lines[Index] = { Stat = Stat, Roll = EquipmentData.NewRoll(Rng) }
					Rerolled += 1
				end
				Used[Old] = true
			end
		end
		if Rerolled == 0 then
			return nil, "Messages.NothingToReroll"
		end
		return New, nil
	end
	return nil, "Messages.BadRequest"
end

return EquipmentData
