--[[
	Loadout

	A class, one per player, holding what that player brought into the
	run and what they currently have out. A loadout is 4 things: 2
	weapons and 2 abilities, all chosen on the character creation screen
	in the lobby place. Only one weapon and one ability are
	equipped at a time, and the player swaps between their two of each
	during the run (R for weapons, G for abilities).

	So this owns the two weapon slots, the two ability slots, which slot
	of each is active, and the swap. It builds a weapon object for each
	of the two weapons up front rather than rebuilding on every swap, so
	swapping is instant and each weapon keeps its own cooldowns while it
	is put away.

	It also owns the player's shop items as Tools in the Roblox Backpack.
	PlayerStats keeps the list of items carried, and this keeps one Tool
	per item in the Backpack to match, so the normal Roblox hotbar is
	the item inventory. Picking a Tool uses that item, see
	ClientGame.Controllers.InventoryController.

	Keeping this separate from PlayerStats means the health and energy
	side does not need to know anything about weapons, and the swap rules
	live in one place instead of being spread across the input handlers
	and the combat service.

	The two weapons have to be different from each other, and so do the
	two abilities. That is checked in the lobby, but it gets checked here
	too, because the loadout arrives from saved data and saved data can
	be out of date if a weapon is ever renamed.
]]

--[[
	What connects to this

	Built from:
	  The player's saved data, read through
	  ServerScriptService.Server.Modules.DataManager. Character creation
	  happens in the lobby place and writes the chosen weapons and
	  abilities into the save, so this place reads them back out rather
	  than being sent them. The keys it reads must exist in
	  ReplicatedStorage.Modules.Shared.PlayerDataTemplate.

	Created by:
	  Server.Game.Core.RunSetup, one per player, after DataManager has
	  finished loading that player's data.

	Reads:
	  Game.Data.WeaponData and Game.Data.AbilityData to check the names
	  in the save are real, and to build the objects.
	  Game.Data.ShopItemData and Server.Game.Core.PlayerStats for the
	  items carried. A dead player (a spectator) carries no item Tools,
	  and gets them back when they are revived.

	Creates:
	  Server.Game.Combat.Weapons.WeaponBase objects, one per weapon slot,
	  which route to Sword, Pistol, RPG or Shotgun. Only the equipped
	  weapon's model is on the character.
	  Server.Game.Combat.Abilities.AbilityBase objects for the two
	  ability slots.
	  One Tool per carried item in the player's Backpack, marked with
	  the LoadoutKind and LoadoutId attributes.

	Asked by:
	  Server.Game.Combat.CombatService, which needs the currently
	  equipped weapon or ability to route an attack to it. CombatService
	  asks this rather than keeping its own idea of what is equipped.

	Swapping:
	  The request comes from the client (ClientGame.Controllers.
	  CombatInput and AbilityInput) through the LoadoutSwap remote, which
	  CombatService validates and passes here. The swap cooldown from
	  GameConfig.Loadout stops a player firing one weapon then instantly
	  firing the other to dodge both cooldowns. Swapping cancels any
	  attack that is in progress, and swaps the weapon model on the
	  character.

	Sends:
	  ReplicatedStorage.Remotes.Events.LoadoutChanged to the player
	  whenever a slot changes, with the four names, which of each is
	  active and the cooldown left on each weapon attack and ability, so
	  the input controllers and the HUD show the right thing.

	Fallback: if a saved weapon name is not in WeaponData, warn and use
	the fallback from GameConfig.Loadout rather than erroring. A player
	should never be stuck in a run with no weapon.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local WeaponData = require(ReplicatedStorage.Modules.Game.Data.WeaponData)
local AbilityData = require(ReplicatedStorage.Modules.Game.Data.AbilityData)
local ShopItemData = require(ReplicatedStorage.Modules.Game.Data.ShopItemData)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)
local PlayerStats = require(script.Parent.PlayerStats)
local WeaponBase = require(ServerScriptService.Server.Game.Combat.Weapons.WeaponBase)
local AbilityBase = require(ServerScriptService.Server.Game.Combat.Abilities.AbilityBase)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LoadoutChanged = Remotes.Events:FindFirstChild("LoadoutChanged")
if not LoadoutChanged then
	LoadoutChanged = Instance.new("RemoteEvent")
	LoadoutChanged.Name = "LoadoutChanged"
	LoadoutChanged.Parent = Remotes.Events
end

local Loadout = {}
Loadout.__index = Loadout

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

Loadout.Settings = {
	-- Attributes written on every item Tool this module makes, which
	-- the client reads to know what a Tool is for.
	KindAttribute = "LoadoutKind", -- always "Item"
	IdAttribute = "LoadoutId", -- the ShopItemData id
	-- Seconds to wait for a new character's Backpack before giving up.
	BackpackTimeout = 10,
}

-- Fired with (Player, Kind, NewIndex) after a swap. Kind is "Weapon"
-- or "Ability".
Loadout.Swapped = Instance.new("BindableEvent")

local ByPlayer: { [Player]: any } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Reads the saved names for a slot pair and makes sure they are
-- real, enabled and different from each other. Returns the two names.
local function ResolvePair(Player: Player, Key1: string, Key2: string, Lookup, Fallback: string, Label: string): (string, string)
	local Names = { DataManager.Get(Player, Key1), DataManager.Get(Player, Key2) }
	local EnabledNames = Lookup.GetEnabledNames()

	for Index, Name in ipairs(Names) do
		if type(Name) ~= "string" or not Lookup.Get(Name) then
			warn(string.format("[Loadout] %s has an unknown %s '%s' in slot %d, using %s", Player.Name, Label, tostring(Name), Index, Fallback))
			Names[Index] = Fallback
		end
	end

	local RequireUnique = Label == "weapon" and GameConfig.Loadout.RequireUniqueWeapons or GameConfig.Loadout.RequireUniqueAbilities
	if RequireUnique and Names[1] == Names[2] then
		-- Pick the first enabled name that is not the duplicate.
		for _, Candidate in ipairs(EnabledNames) do
			if Candidate ~= Names[1] then
				warn(string.format("[Loadout] %s had %s '%s' twice, second slot is now %s", Player.Name, Label, Names[1], Candidate))
				Names[2] = Candidate
				break
			end
		end
	end

	return Names[1], Names[2]
end

-- A Tool for one shop item. It has no handle: picking it uses the
-- item straight away, it is never held.
local function MakeItemTool(ItemId: string, Item): Tool
	local Settings = Loadout.Settings
	local Tool = Instance.new("Tool")
	Tool.Name = Item.DisplayName
	Tool.RequiresHandle = false
	Tool.CanBeDropped = false
	Tool.ManualActivationOnly = true
	Tool.ToolTip = Item.Description or Item.DisplayName
	if Item.Icon and Item.Icon ~= "" and Item.Icon ~= "rbxassetid://0" then
		Tool.TextureId = Item.Icon
	end
	Tool:SetAttribute(Settings.KindAttribute, "Item")
	Tool:SetAttribute(Settings.IdAttribute, ItemId)
	return Tool
end

----------------------------------------------------------------------
-- CONSTRUCTION
----------------------------------------------------------------------

function Loadout.new(Player: Player)
	local Existing = ByPlayer[Player]
	if Existing then
		Existing:Destroy()
	end

	local self = setmetatable({}, Loadout)
	self.Player = Player
	self.Destroyed = false
	self.Connections = {}

	local Config = GameConfig.Loadout
	local Weapon1, Weapon2 = ResolvePair(Player, "Weapon1", "Weapon2", WeaponData, Config.FallbackWeapon, "weapon")
	local Ability1, Ability2 = ResolvePair(Player, "Ability1", "Ability2", AbilityData, Config.FallbackAbility, "ability")

	self.WeaponNames = { Weapon1, Weapon2 }
	self.AbilityNames = { Ability1, Ability2 }
	self.ActiveWeapon = 1
	self.ActiveAbility = 1
	self.LastWeaponSwapAt = 0
	self.LastAbilitySwapAt = 0

	-- One weapon object per slot, built up front so a swap is instant
	-- and each keeps its own cooldowns while put away.
	self.Weapons = {}
	for Index, Name in ipairs(self.WeaponNames) do
		self.Weapons[Index] = WeaponBase.new(Player, Name)
	end

	-- One ability object per slot, same reasoning as the weapons.
	self.Abilities = {}
	for Index, Name in ipairs(self.AbilityNames) do
		self.Abilities[Index] = AbilityBase.new(Player, Name)
	end

	-- The item Tools currently in the Backpack.
	self.ItemTools = {}

	ByPlayer[Player] = self

	table.insert(self.Connections, Player.CharacterAdded:Connect(function(Character)
		self:_OnCharacterAdded(Character)
	end))
	-- The item Tools follow PlayerStats' inventory.
	table.insert(self.Connections, PlayerStats.Changed.Event:Connect(function(Who, Key)
		if Who == Player and Key == "Inventory" then
			self:_SyncItems()
		end
	end))
	-- A spectator carries nothing, and gets their items back on revive.
	table.insert(self.Connections, PlayerStats.Died.Event:Connect(function(Who)
		if Who == Player then
			self:_ClearItems()
		end
	end))
	table.insert(self.Connections, PlayerStats.Revived.Event:Connect(function(Who)
		if Who == Player then
			task.defer(function()
				self:_SyncItems()
			end)
		end
	end))

	if Player.Character then
		task.spawn(function()
			self:_OnCharacterAdded(Player.Character)
		end)
	end

	self:Send()
	return self
end

function Loadout:_OnCharacterAdded(Character: Model)
	-- Weapons attach their model to the new character, only the
	-- equipped one shown.
	Character:WaitForChild("Right Arm", Loadout.Settings.BackpackTimeout)
	if self.Destroyed or self.Player.Character ~= Character then
		return
	end
	for Index, Weapon in ipairs(self.Weapons) do
		Weapon:Attach(Character, Index == self.ActiveWeapon)
	end
	-- The Backpack is emptied on every respawn, so the item Tools are
	-- made again. PlayerStats decides on the same event whether this
	-- character is a spectator, so give it a frame first.
	task.defer(function()
		if not self.Destroyed and self.Player.Character == Character then
			self:_ClearItems()
			self:_SyncItems()
		end
	end)
end

function Loadout:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, Connection in ipairs(self.Connections) do
		Connection:Disconnect()
	end
	self.Connections = {}
	self:_ClearItems()
	for _, Weapon in ipairs(self.Weapons) do
		Weapon:Destroy()
	end
	for _, Ability in ipairs(self.Abilities) do
		Ability:Destroy()
	end
	if ByPlayer[self.Player] == self then
		ByPlayer[self.Player] = nil
	end
end

function Loadout.Get(Player: Player)
	return ByPlayer[Player]
end

function Loadout.GetAll(): { [Player]: any }
	return ByPlayer
end

function Loadout.Remove(Player: Player)
	local Existing = ByPlayer[Player]
	if Existing then
		Existing:Destroy()
	end
end

----------------------------------------------------------------------
-- ITEM TOOLS
----------------------------------------------------------------------

function Loadout:_ClearItems()
	for _, Tool in ipairs(self.ItemTools) do
		Tool:Destroy()
	end
	self.ItemTools = {}
end

-- Makes the item Tools match PlayerStats' inventory: one Tool per item
-- carried, in the order bought. Nothing for a dead player.
function Loadout:_SyncItems()
	if self.Destroyed then
		return
	end
	local Player = self.Player
	local Stats = PlayerStats.Get(Player)
	local Backpack = Player:FindFirstChildOfClass("Backpack")
	local Wanted = (Stats and Stats:IsAlive() and not Stats:IsSpectating()) and Stats:GetInventory() or {}

	-- Keep one existing Tool per wanted item, remove the rest.
	local Spare: { [string]: { Tool } } = {}
	for _, Tool in ipairs(self.ItemTools) do
		if Tool.Parent then
			local Id = Tool:GetAttribute(Loadout.Settings.IdAttribute)
			Spare[Id] = Spare[Id] or {}
			table.insert(Spare[Id], Tool)
		end
	end
	local Kept = {}
	local Missing = {}
	for _, ItemId in ipairs(Wanted) do
		local Pool = Spare[ItemId]
		if Pool and #Pool > 0 then
			table.insert(Kept, table.remove(Pool, 1))
		else
			table.insert(Missing, ItemId)
		end
	end
	for _, Pool in pairs(Spare) do
		for _, Tool in ipairs(Pool) do
			Tool:Destroy()
		end
	end

	if Backpack and Player.Character then
		for _, ItemId in ipairs(Missing) do
			local Item = ShopItemData.Items[ItemId]
			if Item then
				local Tool = MakeItemTool(ItemId, Item)
				Tool.Parent = Backpack
				table.insert(Kept, Tool)
			end
		end
	end
	self.ItemTools = Kept
end

----------------------------------------------------------------------
-- QUERIES
----------------------------------------------------------------------

-- The weapon object the player currently has out.
function Loadout:GetEquippedWeapon()
	return self.Weapons[self.ActiveWeapon]
end

function Loadout:GetEquippedWeaponName(): string
	return self.WeaponNames[self.ActiveWeapon]
end

function Loadout:GetEquippedAbilityName(): string
	return self.AbilityNames[self.ActiveAbility]
end

-- The ability object the player currently has out.
function Loadout:GetEquippedAbility()
	return self.Abilities[self.ActiveAbility]
end

-- Which slot a weapon name is in, or nil if the player does not have
-- it. CombatService uses this to reject attacks for a weapon the
-- player is not holding.
function Loadout:GetWeaponSlot(WeaponName: string): number?
	return table.find(self.WeaponNames, WeaponName)
end

function Loadout:GetAbilitySlot(AbilityName: string): number?
	return table.find(self.AbilityNames, AbilityName)
end

----------------------------------------------------------------------
-- SWAPPING
----------------------------------------------------------------------

-- Swaps to a weapon slot, or to the other one if Index is nil.
-- Returns whether it happened and a reason if not.
function Loadout:SwapWeapon(Index: number?): (boolean, string?)
	local Target = Index or (self.ActiveWeapon == 1 and 2 or 1)
	if Target ~= 1 and Target ~= 2 then
		return false, "bad slot"
	end
	if Target == self.ActiveWeapon then
		return false, "already equipped"
	end

	local Config = GameConfig.Loadout
	if os.clock() - self.LastWeaponSwapAt < Config.WeaponSwapCooldown then
		return false, "swap cooldown"
	end
	self.LastWeaponSwapAt = os.clock()

	local Old = self.Weapons[self.ActiveWeapon]
	if Old and Config.SwapCancelsAttack then
		Old:CancelAttack()
	end
	-- Swapping never skips a cooldown: part of what the old weapon
	-- still has left carries over to the new one.
	local Carry = Old and Old:GetLongestCooldown() * (Config.SwapCooldownShare or 0) or 0
	if Old then
		Old:SetShown(false)
	end

	self.ActiveWeapon = Target
	local New = self.Weapons[Target]
	if New then
		New:SetShown(true)
		if Carry > 0 then
			New:LockFor(Carry)
		end
	end

	-- Opens the quick swap bonus window, see DamageService.
	local QuickSwap = Config.QuickSwap
	local Stats = PlayerStats.Get(self.Player)
	if Stats and QuickSwap then
		Stats.QuickSwapUntil = os.clock() + (QuickSwap.Window or 0)
	end

	Loadout.Swapped:Fire(self.Player, "Weapon", Target)
	self:Send()
	return true, nil
end

function Loadout:SwapAbility(Index: number?): (boolean, string?)
	local Target = Index or (self.ActiveAbility == 1 and 2 or 1)
	if Target ~= 1 and Target ~= 2 then
		return false, "bad slot"
	end
	if Target == self.ActiveAbility then
		return false, "already equipped"
	end

	if os.clock() - self.LastAbilitySwapAt < GameConfig.Loadout.AbilitySwapCooldown then
		return false, "swap cooldown"
	end
	self.LastAbilitySwapAt = os.clock()

	self.ActiveAbility = Target
	Loadout.Swapped:Fire(self.Player, "Ability", Target)
	self:Send()
	return true, nil
end

----------------------------------------------------------------------
-- SYNC
----------------------------------------------------------------------

-- What the client needs to draw the slots: names, which is active,
-- and how long each weapon attack and ability has left on cooldown so
-- a swap shows the right sweep.
function Loadout:GetSnapshot()
	local Cooldowns = {}
	for Index, Weapon in ipairs(self.Weapons) do
		Cooldowns[Index] = {
			MB1 = Weapon:GetCooldownRemaining("MB1"),
			MB2 = Weapon:GetCooldownRemaining("MB2"),
		}
	end
	local AbilityCooldowns = {}
	for Index, Ability in ipairs(self.Abilities) do
		AbilityCooldowns[Index] = Ability:GetCooldownRemaining()
	end
	return {
		Weapons = table.clone(self.WeaponNames),
		Abilities = table.clone(self.AbilityNames),
		ActiveWeapon = self.ActiveWeapon,
		ActiveAbility = self.ActiveAbility,
		WeaponCooldowns = Cooldowns,
		AbilityCooldowns = AbilityCooldowns,
	}
end

function Loadout:Send()
	if self.Destroyed or self.Player.Parent ~= Players then
		return
	end
	LoadoutChanged:FireClient(self.Player, self:GetSnapshot())
end

Players.PlayerRemoving:Connect(function(Player)
	Loadout.Remove(Player)
end)

return Loadout
