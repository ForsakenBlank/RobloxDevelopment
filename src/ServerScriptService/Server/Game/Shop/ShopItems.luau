--[[
	ShopItems

	One function per shop item, holding what that item actually does when
	it is used. Keyed by the item id so ShopManager can look one up
	rather than running a chain of if statements.

	The artifacts run the moment they are bought, since a max health,
	max energy, walk speed or extra jump increase has no reason to sit in
	an inventory. The potions, the Mushroom and the Molotov go into the
	player's inventory, which Server.Game.Core.Loadout shows as Tools in
	the Roblox Backpack, and run when the player picks one, so those
	functions get called later rather than at the point of purchase.

	The Mushroom is the odd one. It rolls a random status effect for 30
	seconds with a 25% chance of rolling a bad one, so its function does
	the roll and then asks for whichever effect came up.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.ShopItemData for the amounts and durations. Every id in
	  that table needs a function in here, or a purchase would succeed
	  and then silently do nothing, so Init warns about any mismatch.

	Called by:
	  Server.Game.Shop.ShopManager through ShopItems.Give once a purchase
	  has been paid for. ShopManager owns the money and the podium, this
	  module only runs the effect or files the item.

	Listens on:
	  ReplicatedStorage.Remotes.Events.ItemUse with (ItemId,
	  AimPosition) from ClientGame.Controllers.InventoryController when
	  an item's Tool is picked, rate limited through RemoteGuard. The
	  item has to be in the server's own copy of the inventory, the
	  client only says which kind it wants to use.

	Uses:
	  Server.Game.Core.PlayerStats for the Health Potion, the Energy
	  Potion and all four artifacts. The speed and jump artifacts go
	  through AddSpeedBonus and AddExtraJumps, which write the
	  MovementSettings.GameModifiers attributes the movement framework
	  reads and tell the anti cheat the new speed allowance, so there is
	  only ever one jump counter and one speed rule.
	  Server.Game.Effects.StatusEffectService for the Damage Potion, the
	  Mushroom roll and the Molotov's Fire, so those show up on the HUD
	  with everything else and get cleared when the run ends.
	  Server.Game.Combat.ProjectileService for throwing the Molotov, and
	  Server.Game.Combat.DamageService for the burning area it leaves.

	Artifacts raising max health heal by the same amount when
	HealOnPickup is on, so the new health is usable straight away. That
	is a data choice in ShopItemData, not a rule here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopItemData = require(ReplicatedStorage.Modules.Game.Data.ShopItemData)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local ThrowArc = require(ReplicatedStorage.Modules.Game.Shared.ThrowArc)
local RemoteGuard = require(ServerScriptService.Server.Modules.AntiCheat.RemoteGuard)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local StatusEffectService = require(script.Parent.Parent.Effects.StatusEffectService)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ItemUse = Remotes.Events:WaitForChild("ItemUse")
local Notify = Remotes.Events:WaitForChild("Notify")

local ShopItems = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

ShopItems.Settings = {
	-- Uses per second a player can send.
	UseRate = 4,
	UseBurst = 2,
	-- Sound played where a Molotov bursts.
	MolotovSound = "Explosion",
}

-- Each returns (true) or (false, Reason). Reason is shown to the
-- player. AimPosition is only given for items used from the inventory.
local Effects: { [string]: (Player, any, any, Vector3?) -> (boolean, string?) } = {}

----------------------------------------------------------------------
-- POTIONS
----------------------------------------------------------------------

Effects.HealthPotion = function(Player, Stats, Item)
	if Item.BlockAtFullHealth and Stats:GetHealth() >= Stats:GetMaxHealth() then
		return false, "Already at full health"
	end
	local DamageService = require(script.Parent.Parent.Combat.DamageService)
	if Player.Character then
		DamageService.ApplyHeal(Player.Character, Stats:GetMaxHealth() * Item.HealPercentOfMax)
	else
		Stats:Heal(Stats:GetMaxHealth() * Item.HealPercentOfMax)
	end
	return true
end

Effects.EnergyPotion = function(Player, Stats, Item)
	if Item.BlockAtFullEnergy and Stats:GetEnergy() >= Stats:GetMaxEnergy() then
		return false, "Already at full energy"
	end
	Stats:AddEnergy(Stats:GetMaxEnergy() * Item.RefillPercentOfMax)
	return true
end

Effects.DamagePotion = function(Player, Stats, Item)
	StatusEffectService.Apply(Player, Item.Effect or "Damage", Item.Duration, Item.Multiplier, Player)
	return true
end

Effects.Mushroom = function(Player, Stats, Item)
	local Bad = math.random() < (Item.BadChance or 0)
	local List = Bad and Item.BadEffects or Item.GoodEffects
	if not List or #List == 0 then
		return false, "The mushroom did nothing"
	end
	local EffectName = List[math.random(#List)]
	local Amount = Item.AmountOverrides and Item.AmountOverrides[EffectName] or nil
	StatusEffectService.Apply(Player, EffectName, Item.Duration, Amount, nil)
	Notify:FireClient(Player, Bad and ("Bad mushroom: " .. EffectName) or ("Mushroom: " .. EffectName .. "!"))
	return true
end

-- A patch of fire at Position that burns enemies inside it. The look
-- (shattered glass, the burst, the flames, the scorch) is drawn by
-- every client from CombatFX "MolotovBurn".
local function BurnArea(Player: Player, Item, Position: Vector3)
	local DamageService = require(script.Parent.Parent.Combat.DamageService)
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)

	CombatFX.Broadcast("MolotovBurn", nil, {
		Position = Position,
		Radius = Item.Radius,
		Duration = Item.Duration,
		Sound = ShopItems.Settings.MolotovSound,
	})

	-- The burst.
	if (Item.ImpactDamage or 0) > 0 then
		local Hits = HitDetection.Sphere(Position + Vector3.new(0, 2, 0), Item.Radius, { Side = "Enemies", Origin = Position })
		for _, Hit in ipairs(Hits) do
			DamageService.ApplyDamage(Hit.Model, Item.ImpactDamage, Player, {
				Source = "Molotov",
				StatusEffect = Item.LingerEffect,
			})
		end
	end

	local Ticks = math.max(1, math.floor(Item.Duration / Item.TickRate))
	local PerTick = Item.DamagePerSecond * Item.TickRate
	task.spawn(function()
		for _ = 1, Ticks do
			local Hits = HitDetection.Sphere(Position + Vector3.new(0, 2, 0), Item.Radius, { Side = "Enemies", Origin = Position })
			for _, Hit in ipairs(Hits) do
				DamageService.ApplyDamage(Hit.Model, PerTick, Player, {
					Source = "Molotov",
					StatusEffect = Item.LingerEffect,
				})
			end
			if (Item.FriendlyFire or 0) > 0 then
				local PlayerHits = HitDetection.Sphere(Position + Vector3.new(0, 2, 0), Item.Radius, { Side = "Players", Origin = Position })
				for _, Hit in ipairs(PlayerHits) do
					DamageService.ApplyDamage(Hit.Model, PerTick * Item.FriendlyFire, nil, { Source = "Molotov" })
				end
			end
			task.wait(Item.TickRate)
		end
	end)
end

Effects.Molotov = function(Player, Stats, Item, AimPosition)
	local ProjectileService = require(script.Parent.Parent.Combat.ProjectileService)
	local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
	if not Root then
		return false, "No character"
	end
	local Aim = AimPosition
	if typeof(Aim) ~= "Vector3" then
		Aim = Root.Position + Root.CFrame.LookVector * 30
	end
	-- The same arc the client drew while aiming.
	local Throw = Item.Throw
	Aim = ThrowArc.ClampAim(Root.Position, Aim, Throw.MaxRange)
	local Origin = ThrowArc.Origin(Root.Position, Aim)
	local Velocity = ThrowArc.Velocity(Origin, Aim, Throw.Speed, Throw.Gravity)

	ProjectileService.Fire({
		Owner = Player,
		Side = "Enemies",
		Origin = Origin,
		Direction = Velocity.Unit,
		Speed = Throw.Speed,
		Gravity = Throw.Gravity,
		Lifetime = 4,
		ModelName = Item.ProjectileModel,
		Damage = 0,
		Pierce = 0,
		Knockback = 0,
		Source = "Molotov",
		OnImpact = function(Position)
			BurnArea(Player, Item, Position)
		end,
	})
	CombatFX.Broadcast("Enemy_Swing", Player.Character, { Kind = "Ranged" })
	return true
end

----------------------------------------------------------------------
-- ARTIFACTS
----------------------------------------------------------------------

Effects.HealthArtifact = function(Player, Stats, Item)
	Stats:AddMaxHealth(Item.MaxHealthBonus, Item.HealOnPickup and Item.MaxHealthBonus or 0)
	return true
end

Effects.EnergyArtifact = function(Player, Stats, Item)
	Stats:AddMaxEnergy(Item.MaxEnergyBonus, Item.RefillOnPickup and Item.MaxEnergyBonus or 0)
	return true
end

Effects.SpeedArtifact = function(Player, Stats, Item)
	Stats:AddSpeedBonus(Item.WalkSpeedBonus)
	return true
end

Effects.JumpArtifact = function(Player, Stats, Item)
	Stats:AddExtraJumps(Item.ExtraJumps)
	return true
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

-- Runs an item's effect now. Returns (Ok, Reason).
function ShopItems.Run(Player: Player, ItemId: string, AimPosition: Vector3?): (boolean, string?)
	local Item = ShopItemData.Get(ItemId)
	local Effect = Effects[ItemId]
	local Stats = PlayerStats.Get(Player)
	if not Item or not Effect then
		return false, "Unknown item"
	end
	if not Stats or not Stats:IsAlive() then
		return false, "You are dead"
	end
	local Ok, Result, Reason = pcall(Effect, Player, Stats, Item, AimPosition)
	if not Ok then
		warn("[ShopItems] " .. ItemId .. " errored: " .. tostring(Result))
		return false, "That item failed"
	end
	return Result == true, Reason
end

-- Whether a player has room for an item. Instant items always fit.
function ShopItems.CanReceive(Player: Player, ItemId: string): (boolean, string?)
	local Item = ShopItemData.Get(ItemId)
	local Stats = PlayerStats.Get(Player)
	if not Item or not Stats then
		return false, "Unknown item"
	end
	if Item.UseType == "Inventory" and Stats:CountItems() >= ShopItemData.Shop.InventorySize then
		return false, "Inventory full"
	end
	return true
end

-- Gives a paid for item: instant items run now, the rest go into the
-- inventory.
function ShopItems.Give(Player: Player, ItemId: string): boolean
	local Item = ShopItemData.Get(ItemId)
	local Stats = PlayerStats.Get(Player)
	if not Item or not Stats then
		return false
	end
	if Item.UseType == "Instant" then
		local Ok, Reason = ShopItems.Run(Player, ItemId, nil)
		if not Ok and Reason then
			Notify:FireClient(Player, Reason)
		end
		return Ok
	end
	return Stats:AddItem(ItemId, ShopItemData.Shop.InventorySize)
end

-- Uses one of an item the player is carrying.
function ShopItems.UseItem(Player: Player, ItemId: string, AimPosition: Vector3?)
	local Stats = PlayerStats.Get(Player)
	if not Stats or not Stats:IsAlive() then
		return
	end
	if not Stats:HasItem(ItemId) then
		return
	end
	local Ok, Reason = ShopItems.Run(Player, ItemId, AimPosition)
	if Ok then
		Stats:RemoveItem(ItemId)
		local Item = ShopItemData.Items[ItemId]
		if Item and ItemId ~= "Mushroom" then
			Notify:FireClient(Player, "Used " .. Item.DisplayName)
		end
		if Item and Item.Sound and Player.Character then
			CombatFX.Broadcast("PlaySound", Player.Character, { Name = Item.Sound })
		end
	elseif Reason then
		Notify:FireClient(Player, Reason)
	end
end

function ShopItems.Init()
	for ItemId in pairs(ShopItemData.Items) do
		if not Effects[ItemId] then
			warn("[ShopItems] ShopItemData has " .. ItemId .. " but there is no effect for it")
		end
	end

	RemoteGuard.BindEvent(ItemUse, { Rate = ShopItems.Settings.UseRate, Burst = ShopItems.Settings.UseBurst }, function(Player, ItemId, AimPosition)
		if type(ItemId) ~= "string" or not ShopItemData.Items[ItemId] then
			return
		end
		if AimPosition ~= nil and typeof(AimPosition) ~= "Vector3" then
			return
		end
		ShopItems.UseItem(Player, ItemId, AimPosition)
	end)
end

return ShopItems
