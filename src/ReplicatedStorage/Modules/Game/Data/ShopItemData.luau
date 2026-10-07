--[[
	ShopItemData

	The 9 things that can appear in a shop. Each entry holds an id,
	display name, description shown on the billboard, base price, an
	icon, a rarity, and whether the item takes effect the moment it is
	bought or goes into the player's inventory to be used later.

	The items are the Health Potion (heals to full health), Energy
	Potion (refills energy fully, one use), Damage Potion (1.5x damage
	for 45 seconds), Mushroom (random status effect for 30 seconds with a
	25% chance of a bad one), Molotov (held and thrown along a shown
	arc, bursts on landing and burns a wide area for 7 seconds), and the
	four artifacts which apply straight
	away: +25 max health, +25 max energy, +2 walk speed and +1 max jump.

	The rarity is what the CarpetRarity part on each podium is coloured
	by, so this also needs a rarity list with a colour and a roll weight
	for each. Rarer items should be worth more and come up less often.

	Each entry also names the status effect it applies where relevant,
	and the Mushroom entry holds the list of effects it can roll from
	split into good and bad.
]]

--[[
	What connects to this

	Server.Game.Shop.ShopManager reads this list to roll the 4 items for
	a shop, uses the rarity weights for the roll, sets the CarpetRarity
	colour from the rarity, and multiplies the base price by the
	difficulty price multiplier from Game.Config.DifficultyConfig.

	Server.Game.Shop.ShopItems holds one function per item id, so every
	id in this table needs a matching function there or a purchase will
	go through and then do nothing.

	Server.Game.Effects.StatusEffectService is called by ShopItems for
	the Damage Potion, Mushroom and Molotov. The effect names used here
	must exist in Game.Data.StatusEffectData.

	Server.Game.Core.PlayerStats is what the artifacts change, since they
	edit max health, max energy, walk speed and max jumps directly rather
	than going through the effect system.

	ServerStorage.Assets.ShopItems needs a model named to match each id,
	which is what gets placed on the podium.

	Client side, ClientGame.UI.ShopUI and ClientGame.Controllers.
	ShopController read the display name, description, price, icon and
	rarity colour to build the billboard above each podium. The stock
	itself comes from the server over
	ReplicatedStorage.Remotes.Functions.GetShopStock, not from this
	table, because the roll happens server side.

	With only 4 podiums per shop and 9 items, most of the list will not
	appear in any given shop, so the roll weights matter more than they
	would with a bigger shop. An item that is never useful will feel like
	a wasted podium.
]]

-- Note on when changes take effect. The item list and rarities are
-- read when a shop is rolled, which happens when players first enter
-- it, so a change applies to the next shop without a restart.

local ShopItemData = {}

----------------------------------------------------------------------
-- SHOP
----------------------------------------------------------------------

ShopItemData.Shop = {
	-- Podiums stocked per shop. RoomData can override per area.
	PodiumCount = 4,
	-- The same item cannot appear on two podiums in one shop.
	AllowDuplicates = false,
	-- Items bought in Shop1 can still roll in Shop2.
	AllowRepeatAcrossShops = true,
	-- Text and hold time on the buy prompt.
	PromptText = "Buy",
	PromptHoldTime = 0.5,
	-- Seconds a "Not enough money" message shows on the billboard.
	DeniedMessageTime = 1.5,
	-- Rounds prices to the nearest this after multipliers, so a 1.25x
	-- difficulty does not produce 62.5.
	PriceRounding = 5,
	-- Inventory items are Tools in the Roblox Backpack, so the number
	-- keys (or clicking the slot) use them. Picking one uses it straight
	-- away. How many a player can hold at once, buying with a full
	-- inventory is refused.
	InventorySize = 4,
	-- The names of the parts on each podium model that ShopManager
	-- recolours and places the item model on.
	CarpetPartName = "CarpetRarity",
	ItemAttachmentName = "ItemPoint",
}

----------------------------------------------------------------------
-- RARITIES
----------------------------------------------------------------------

-- Weight is the share of the roll. With these numbers roughly 6 in 10
-- podiums are Common, 3 in 10 Rare, 1 in 10 Epic. PriceMultiplier is
-- applied on top of the item's own price.
ShopItemData.Rarities = {
	Common = {
		DisplayName = "Common",
		Weight = 60,
		Colour = Color3.fromRGB(200, 200, 200),
		PriceMultiplier = 1,
	},
	Rare = {
		DisplayName = "Rare",
		Weight = 30,
		Colour = Color3.fromRGB(80, 140, 255),
		PriceMultiplier = 1,
	},
	Epic = {
		DisplayName = "Epic",
		Weight = 10,
		Colour = Color3.fromRGB(190, 80, 255),
		PriceMultiplier = 1,
	},
}

----------------------------------------------------------------------
-- ITEMS
----------------------------------------------------------------------

-- Every item has these:
--   Enabled       false keeps it out of the roll
--   DisplayName   on the billboard and in the inventory
--   Description   one line on the billboard
--   Price         base price before rarity and difficulty multipliers
--   Rarity        key from Rarities above
--   UseType       "Instant"    takes effect the moment it is bought
--                 "Inventory"  goes into the Backpack as a Tool, used
--                              the moment it is picked
--   ModelName     model in ServerStorage.Assets.ShopItems for the
--                 podium
--   Icon          image for the billboard and inventory slot
--   Weight        nil uses the rarity weight. Set a number to make one
--                 item within a rarity more or less common
--   MaxPerRun     how many times one player can buy it in a run. nil
--                 is unlimited
--   Sound         played on use, through Modules.Shared.Sound
--
-- The rest of each entry is that item's own numbers.

ShopItemData.Items = {

	HealthPotion = {
		Enabled = true,
		DisplayName = "Health Potion",
		Description = "Heals you to full health.",
		Price = 90,
		Rarity = "Common",
		UseType = "Inventory",
		ModelName = "HealthPotion",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "PotionDrink",

		HealPercentOfMax = 1,
		-- Refuse to use it at full health so it is not wasted.
		BlockAtFullHealth = true,
	},

	EnergyPotion = {
		Enabled = true,
		DisplayName = "Energy Potion",
		Description = "Refills your energy completely.",
		Price = 70,
		Rarity = "Common",
		UseType = "Inventory",
		ModelName = "EnergyPotion",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "PotionDrink",

		-- Fraction of max energy restored. 1 is a full refill.
		RefillPercentOfMax = 1,
		BlockAtFullEnergy = true,
	},

	DamagePotion = {
		Enabled = true,
		DisplayName = "Damage Potion",
		Description = "2x damage for 75 seconds.",
		Price = 190,
		Rarity = "Rare",
		UseType = "Inventory",
		ModelName = "DamagePotion",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "PotionDrink",

		Effect = "Damage",
		Multiplier = 2,
		Duration = 75,
	},

	Mushroom = {
		Enabled = true,
		DisplayName = "Mushroom",
		Description = "A random effect for 60 seconds. Almost always good, and strong.",
		Price = 110,
		Rarity = "Common",
		UseType = "Inventory",
		ModelName = "Mushroom",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "PotionDrink",

		Duration = 60,
		-- Chance the roll comes from BadEffects instead of GoodEffects.
		BadChance = 0.12,
		-- Names from StatusEffectData. Each is equally likely within
		-- its list.
		GoodEffects = { "Regeneration", "Damage", "Resistance" },
		BadEffects = { "Fire", "Poison" },
		-- Amount overrides so a bad roll is a nuisance rather than a
		-- run ender. nil uses the effect's own default.
		AmountOverrides = {
			Fire = 4,
			Poison = 2,
			-- the good ones are stronger than the same effect from anywhere else
			Regeneration = 4,
			Damage = 1.75,
			Resistance = 0.6,
		},
	},

	Molotov = {
		Enabled = true,
		DisplayName = "Molotov",
		Description = "Hold to aim, click to throw it a long way. Bursts into a huge patch of fire that burns everything in it for 15 seconds.",
		Price = 170,
		Rarity = "Rare",
		UseType = "Inventory",
		ModelName = "Molotov",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "EnemyThrow",

		-- Damage to everything in Radius the moment it bursts.
		ImpactDamage = 70,
		-- Damage per second to every enemy stood in the fire.
		DamagePerSecond = 75,
		TickRate = 0.25,
		Radius = 21,
		Duration = 15,
		-- Held ready when picked: the arm goes back and the arc is
		-- drawn to where it will land (ClientGame.Controllers.
		-- InventoryController), then a click throws it. Speed and
		-- Gravity shape the arc, MaxRange caps how far it can be aimed.
		-- The server throws with the same maths (Game.Shared.ThrowArc).
		Throw = { Speed = 110, Gravity = 45, MaxRange = 260 },
		ProjectileModel = "Molotov",
		-- Players stood in it take this fraction of the damage. 0 is
		-- none.
		FriendlyFire = 0,
		-- Enemies that leave the area keep burning with this effect.
		-- nil applies nothing on leaving.
		LingerEffect = { Name = "Fire", Duration = 5 },
	},

	HealthArtifact = {
		Enabled = true,
		DisplayName = "Heart Artifact",
		Description = "+40 max health, for the rest of the run.",
		Price = 280,
		Rarity = "Epic",
		UseType = "Instant",
		ModelName = "HealthArtifact",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "HealBurst",

		MaxHealthBonus = 40,
		-- true also heals by the same amount so the new max is full.
		HealOnPickup = true,
	},

	EnergyArtifact = {
		Enabled = true,
		DisplayName = "Spark Artifact",
		Description = "+40 max energy, for the rest of the run.",
		Price = 240,
		Rarity = "Epic",
		UseType = "Instant",
		ModelName = "EnergyArtifact",
		Icon = "",
		Weight = nil,
		MaxPerRun = nil,
		Sound = "HealBurst",

		MaxEnergyBonus = 40,
		RefillOnPickup = true,
	},

	SpeedArtifact = {
		Enabled = true,
		DisplayName = "Wind Artifact",
		Description = "+6 walk speed, for the rest of the run.",
		Price = 230,
		Rarity = "Rare",
		UseType = "Instant",
		ModelName = "SpeedArtifact",
		Icon = "",
		Weight = nil,
		MaxPerRun = 2,
		Sound = "HealBurst",

		-- Added to the walk speed. Goes through PlayerStats so the anti
		-- cheat and the movement framework both know about it.
		WalkSpeedBonus = 6,
	},

	JumpArtifact = {
		Enabled = true,
		DisplayName = "Feather Artifact",
		Description = "+1 jump in the air, for the rest of the run.",
		Price = 210,
		Rarity = "Rare",
		UseType = "Instant",
		ModelName = "JumpArtifact",
		Icon = "",
		Weight = nil,
		MaxPerRun = 2,
		Sound = "HealBurst",

		-- Added to MovementSettings.Abilities.DoubleJump.MaxAirUses for
		-- this player, through PlayerStats.
		ExtraJumps = 1,
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks an item up by id and warns rather than erroring if the id is
-- wrong or the item is switched off.
function ShopItemData.Get(ItemId: string)
	local Item = ShopItemData.Items[ItemId]
	if not Item then
		warn("[ShopItemData] no item called " .. tostring(ItemId))
		return nil
	end
	if not Item.Enabled then
		warn("[ShopItemData] item " .. ItemId .. " is disabled")
		return nil
	end
	return Item
end

-- Rarity entry for an item, falling back to Common with a warning if
-- the item names a rarity that does not exist.
function ShopItemData.GetRarity(ItemId: string)
	local Item = ShopItemData.Items[ItemId]
	local Rarity = Item and ShopItemData.Rarities[Item.Rarity]
	if not Rarity then
		warn("[ShopItemData] item " .. tostring(ItemId) .. " has an unknown rarity")
		Rarity = ShopItemData.Rarities.Common
	end
	return Rarity
end

-- The roll weight for an item, which is its own Weight if set or its
-- rarity's Weight otherwise.
function ShopItemData.GetWeight(ItemId: string): number
	local Item = ShopItemData.Items[ItemId]
	if not Item or not Item.Enabled then
		return 0
	end
	return Item.Weight or ShopItemData.GetRarity(ItemId).Weight
end

-- Ids of every enabled item, sorted so the order is stable.
function ShopItemData.GetEnabledIds(): { string }
	local Ids = {}
	for Id, Item in pairs(ShopItemData.Items) do
		if Item.Enabled then
			table.insert(Ids, Id)
		end
	end
	table.sort(Ids)
	return Ids
end

return ShopItemData
