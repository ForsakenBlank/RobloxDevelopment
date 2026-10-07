--[[
	PlayerStats

	A class, one instance per player, holding everything about that
	player's current run. Health and max health, energy and max energy,
	money, level, their inventory of bought items, and their current walk
	speed and max jumps after any artifacts.

	The weapons and abilities are not here. Those live on
	Server.Game.Core.Loadout, so this module stays about the numbers and
	does not need to know what a weapon is.

	Every change to a player value goes through a method on here rather
	than being written directly, so there is one place that clamps values
	to their maximum, one place that stops health going below zero, and
	one place that fires the update to the client. That is what keeps the
	HUD and the real value in step, which is a success criteria for the
	project.

	Created fresh at the start of a run and thrown away at the end. It is
	not saved. Anything that has to survive between sessions goes to
	DataManager instead.
]]

--[[
	What connects to this

	Created by:
	  Server.Game.Core.RunSetup, one per player, using the base values
	  from Game.Config.GameConfig. Its matching
	  Server.Game.Core.Loadout object is created at the same time.

	Read and written by:
	  Server.Game.Combat.DamageService when a player takes damage or
	  earns money from a kill.
	  Server.Game.Combat.EnergyService for the regen tick and for the
	  subtract when an ability fires.
	  Server.Game.Combat.Abilities.Rage, which takes 25% of current
	  health and must never drop the player below 1.
	  Server.Game.Combat.Abilities.HealBurst, which adds health and must
	  never push the player above their max.
	  Server.Game.Shop.ShopManager to check and take money on a purchase,
	  and Server.Game.Shop.ShopItems for the potions and artifacts, since
	  the artifacts change max health, max energy, walk speed and max
	  jumps directly.
	  Server.Game.Effects.StatusEffectService for damage and healing
	  ticks.
	  Server.Game.Core.RunManager, which checks whether every player is
	  dead to end the run.
	  Server.Game.Rooms.RoomManager, which checks a player is alive
	  before counting them for a room entry trigger.

	Sends:
	  ReplicatedStorage.Remotes.Events.StatsUpdated to that player
	  whenever a value changes, which is what
	  ClientGame.Controllers.HUDController listens to.
	  Answers ReplicatedStorage.Remotes.Functions.GetStats for a client
	  that asks on startup, so the HUD is right before the first update.

	Also has to talk to the character. Max jumps and walk speed are
	written as attributes on the character, which the movement framework
	reads through MovementSettings.GameModifiers, so the run module and
	this never fight over Humanoid.WalkSpeed. The anti cheat is told the
	new allowance through AntiCheat.SetSpeedAllowance at the same time.
	Both Rage and the speed artifact go through SetSpeedMultiplier and
	AddSpeedBonus here rather than each solving the problem separately.

	Keep the lookup keyed by player rather than character, since the
	character is replaced on respawn but the run stats are not.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)
local Types = require(ReplicatedStorage.Modules.Game.Shared.Types)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StatsUpdated = Remotes.Events:WaitForChild("StatsUpdated")
local GetStats = Remotes.Functions:FindFirstChild("GetStats")
if not GetStats then
	GetStats = Instance.new("RemoteFunction")
	GetStats.Name = "GetStats"
	GetStats.Parent = Remotes.Functions
end

local PlayerStats = {}
PlayerStats.__index = PlayerStats

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

PlayerStats.Settings = {
	-- Seconds to batch rapid changes into one StatsUpdated send. A
	-- burst of Poison ticks and a heal in the same frame becomes one
	-- remote rather than three. 0 sends every change straight away.
	SendRate = 0.05,

	-- Keep Humanoid.Health and MaxHealth equal to the run health, so
	-- the character dies and plays its death when run health hits 0,
	-- and anything that damages the humanoid directly (a kill plane,
	-- Roblox fall damage) is picked up as run damage too.
	MirrorToHumanoid = true,

	-- Delete the Health script Roblox adds to each character, which
	-- would otherwise regenerate the humanoid on its own.
	RemoveDefaultRegen = true,

	-- Also write the values as attributes on the Player, for other
	-- scripts and for reading in the Explorer while playtesting.
	MirrorToPlayerAttributes = true,

	-- The ground speed the anti cheat is told to allow, before any
	-- multiplier. The fast run speed is the quickest the movement
	-- framework moves on foot, so buffs are worked out from that.
	AntiCheatBaseSpeed = MovementSettings.Abilities.Run.FastSpeed,

	-- When the character respawns and the player is dead, bring them
	-- back with full health. RunManager sets this false once it owns
	-- death handling, so a dead player waits for the run to end.
	ReviveOnRespawn = true,

	-- A dead player who respawns without being revived comes back as a
	-- spectator: the character can walk around and watch, but it is
	-- see through, enemies ignore it and it cannot attack. Without
	-- this the new character would be synced to 0 health and die
	-- again straight away, forever.
	SpectatorAttribute = "Spectating",
	SpectatorTransparency = 0.7,
}

-- Fired on every change, with (Player, Key, NewValue, OldValue).
PlayerStats.Changed = Instance.new("BindableEvent")
-- Fired when run health reaches 0, with (Player, Source).
PlayerStats.Died = Instance.new("BindableEvent")
-- Fired when a dead player is brought back, with (Player).
PlayerStats.Revived = Instance.new("BindableEvent")

local ByPlayer: { [Player]: any } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function Clamp(Value: number, Min: number, Max: number): number
	return math.max(Min, math.min(Max, Value))
end

-- Writes a value, fires Changed if it actually changed, and queues a
-- send to the client.
function PlayerStats:_Set(Key: string, Value: any)
	local Old = self.Values[Key]
	if Old == Value then
		return false
	end
	self.Values[Key] = Value
	PlayerStats.Changed:Fire(self.Player, Key, Value, Old)
	if PlayerStats.Settings.MirrorToPlayerAttributes and type(Value) ~= "table" then
		self.Player:SetAttribute(Key, Value)
	end
	self:_QueueSend()
	return true
end

function PlayerStats:_QueueSend()
	if self.SendQueued then
		return
	end
	self.SendQueued = true
	local Rate = PlayerStats.Settings.SendRate
	if Rate <= 0 then
		self:Send()
		return
	end
	task.delay(Rate, function()
		if self.Destroyed then
			return
		end
		self:Send()
	end)
end

-- Pushes the humanoid to match, guarded so the HealthChanged listener
-- does not treat our own write as external damage.
function PlayerStats:_SyncHumanoid()
	if not PlayerStats.Settings.MirrorToHumanoid then
		return
	end
	local Humanoid = self.Humanoid
	if not Humanoid or Humanoid.Parent == nil then
		return
	end
	-- A spectator's body is not their run health, leave it alone.
	if self.Spectating then
		return
	end
	self.SyncingHumanoid = true
	Humanoid.MaxHealth = self.Values.MaxHealth
	Humanoid.Health = self.Values.Health
	self.SyncingHumanoid = false
end

-- Writes the movement modifiers onto the character and tells the anti
-- cheat the new allowance.
function PlayerStats:_ApplyMovement()
	local Modifiers = MovementSettings.GameModifiers
	local Character = self.Character
	if Character then
		Character:SetAttribute(Modifiers.SpeedMultiplierAttribute, self:GetSpeedMultiplier())
		Character:SetAttribute(Modifiers.SpeedBonusAttribute, self.Values.SpeedBonus)
		Character:SetAttribute(Modifiers.ExtraJumpsAttribute, self.Values.ExtraJumps)
	end

	local Allowance = PlayerStats.Settings.AntiCheatBaseSpeed * self:GetSpeedMultiplier() + self.Values.SpeedBonus
	AntiCheat.SetSpeedAllowance(self.Player, Allowance)
end

function PlayerStats:_OnCharacterAdded(Character: Model)
	self.Character = Character
	self.Humanoid = Character:WaitForChild("Humanoid", 10)
	if not self.Humanoid then
		return
	end

	if self.HealthConnection then
		self.HealthConnection:Disconnect()
	end

	self.Spectating = false
	if not self.Values.IsAlive then
		if PlayerStats.Settings.ReviveOnRespawn then
			self:Revive(1)
		else
			self:_SetSpectating(true)
		end
	end

	-- The anti cheat resets its speed limit from its own CharacterAdded
	-- handler, so this waits a frame to be sure it runs after that.
	task.defer(function()
		if not self.Destroyed and self.Character == Character then
			self:_ApplyMovement()
		end
	end)
	self:_SyncHumanoid()

	-- Roblox puts a Health script in every character that regenerates
	-- 1% a second. Run health only comes back through healing, so it
	-- goes.
	if PlayerStats.Settings.RemoveDefaultRegen then
		local Regen = Character:FindFirstChild("Health")
		if Regen and Regen:IsA("BaseScript") then
			Regen:Destroy()
		end
	end

	-- Anything that damages the humanoid directly, such as a kill
	-- plane or the default fall damage, is turned into run damage so
	-- the two never drift apart. An outside increase is not healing,
	-- it is something else writing to the humanoid, so it is undone.
	self.HealthConnection = self.Humanoid.HealthChanged:Connect(function(NewHealth)
		if self.SyncingHumanoid or not PlayerStats.Settings.MirrorToHumanoid then
			return
		end
		local Diff = self.Values.Health - NewHealth
		if Diff > 0.01 then
			local Dealt = self:TakeDamage(Diff, "Humanoid")
			-- Blocked (invulnerable, or already dead), so put the
			-- humanoid back to the real value.
			if Dealt <= 0 then
				self:_SyncHumanoid()
			end
		elseif Diff < -0.01 then
			self:_SyncHumanoid()
		end
	end)
end

----------------------------------------------------------------------
-- CONSTRUCTION
----------------------------------------------------------------------

-- Overrides is an optional table of starting values, used by RunSetup
-- for permanent upgrades from the lobby. Anything not given comes from
-- GameConfig.Player.
function PlayerStats.new(Player: Player, Overrides: { [string]: any }?)
	local Existing = ByPlayer[Player]
	if Existing then
		Existing:Destroy()
	end

	local Config = GameConfig.Player
	Overrides = Overrides or {}

	local self = setmetatable({}, PlayerStats)
	self.Player = Player
	self.Destroyed = false
	self.SendQueued = false
	self.SyncingHumanoid = false
	self.LastEnergyUseAt = 0
	self.SpeedMultipliers = {}

	self.Values = {
		Health = Overrides.MaxHealth or Config.MaxHealth,
		MaxHealth = Overrides.MaxHealth or Config.MaxHealth,
		Energy = Overrides.MaxEnergy or Config.MaxEnergy,
		MaxEnergy = Overrides.MaxEnergy or Config.MaxEnergy,
		Money = Overrides.Money or Config.StartingMoney,
		Level = Overrides.Level or Config.StartingLevel,
		Inventory = {},
		IsAlive = true,
		SpeedBonus = 0,
		SpeedMultiplier = 1,
		ExtraJumps = 0,
	}

	ByPlayer[Player] = self

	if PlayerStats.Settings.MirrorToPlayerAttributes then
		for Key, Value in pairs(self.Values) do
			if type(Value) ~= "table" then
				Player:SetAttribute(Key, Value)
			end
		end
	end

	self.CharacterConnection = Player.CharacterAdded:Connect(function(Character)
		self:_OnCharacterAdded(Character)
	end)
	if Player.Character then
		task.spawn(function()
			self:_OnCharacterAdded(Player.Character)
		end)
	end

	self:Send()
	return self
end

function PlayerStats:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self.CharacterConnection then
		self.CharacterConnection:Disconnect()
	end
	if self.HealthConnection then
		self.HealthConnection:Disconnect()
	end
	if ByPlayer[self.Player] == self then
		ByPlayer[self.Player] = nil
	end
end

-- The stats object for a player, or nil if the run has not made one.
function PlayerStats.Get(Player: Player)
	return ByPlayer[Player]
end

-- Every live stats object, keyed by player.
function PlayerStats.GetAll(): { [Player]: any }
	return ByPlayer
end

function PlayerStats.Remove(Player: Player)
	local Stats = ByPlayer[Player]
	if Stats then
		Stats:Destroy()
	end
end

----------------------------------------------------------------------
-- SYNC
----------------------------------------------------------------------

-- A copy of the values, safe to hand to a remote.
function PlayerStats:GetSnapshot(): Types.PlayerStatTable
	local Snapshot = table.clone(self.Values)
	Snapshot.Inventory = table.clone(self.Values.Inventory)
	Snapshot.SpeedMultiplier = self:GetSpeedMultiplier()
	return Snapshot
end

-- Sends the current values to this player's client now.
function PlayerStats:Send()
	self.SendQueued = false
	if self.Destroyed or self.Player.Parent ~= Players then
		return
	end
	StatsUpdated:FireClient(self.Player, self:GetSnapshot())
end

----------------------------------------------------------------------
-- HEALTH
----------------------------------------------------------------------

function PlayerStats:GetHealth(): number
	return self.Values.Health
end

function PlayerStats:GetMaxHealth(): number
	return self.Values.MaxHealth
end

function PlayerStats:IsAlive(): boolean
	return self.Values.IsAlive
end

-- Sets health directly, clamped between 0 and max. Going to 0 counts
-- as dying. Prefer TakeDamage and Heal so the source is known.
function PlayerStats:SetHealth(Value: number, Source: any?)
	Value = Clamp(Value, 0, self.Values.MaxHealth)
	self:_Set("Health", Value)
	self:_SyncHumanoid()
	if Value <= 0 and self.Values.IsAlive then
		self:_Set("IsAlive", false)
		PlayerStats.Died:Fire(self.Player, Source)
	end
end

-- Takes health off. Returns the amount actually removed and whether
-- this killed the player. Source is whatever caused it, for the death
-- message and for RunManager.
function PlayerStats:TakeDamage(Amount: number, Source: any?): (number, boolean)
	if Amount <= 0 or not self.Values.IsAlive then
		return 0, false
	end
	if GameConfig.Debug.Invincible then
		return 0, false
	end
	-- A short window where nothing hurts, such as arriving from a
	-- Teleport. Kill planes still go through Kill.
	if os.clock() < (self.InvulnerableUntil or 0) then
		return 0, false
	end

	local Before = self.Values.Health
	self:SetHealth(Before - Amount, Source)
	local Dealt = Before - self.Values.Health

	if GameConfig.Debug.LogDamage then
		print(string.format("[PlayerStats] %s took %.1f from %s, %.1f left", self.Player.Name, Dealt, tostring(Source), self.Values.Health))
	end

	return Dealt, not self.Values.IsAlive
end

-- Adds health, clamped to max. Returns the amount actually added. Does
-- nothing on a dead player, use Revive for that.
function PlayerStats:Heal(Amount: number): number
	if Amount <= 0 or not self.Values.IsAlive then
		return 0
	end
	local Before = self.Values.Health
	self:SetHealth(Before + Amount)
	return self.Values.Health - Before
end

-- Makes the player immune to damage for Seconds from now. A longer
-- window already running is kept.
function PlayerStats:SetInvulnerable(Seconds: number)
	self.InvulnerableUntil = math.max(self.InvulnerableUntil or 0, os.clock() + Seconds)
	self:_ShowInvulnerable()
end

-- Sets the end of the invulnerability to exactly Seconds from now,
-- shorter or longer than before. Stun Slam uses it to swap "until I
-- land" for the short window after landing.
function PlayerStats:SetInvulnerableExactly(Seconds: number)
	self.InvulnerableUntil = os.clock() + Seconds
	self:_ShowInvulnerable()
end

function PlayerStats:IsInvulnerable(): boolean
	return os.clock() < (self.InvulnerableUntil or 0)
end

-- Tells the clients, as a server time on the character, so the player
-- can see it (ClientGame.Controllers.ScreenEffects).
function PlayerStats:_ShowInvulnerable()
	local Character = self.Character
	if Character then
		local Left = math.max(0, (self.InvulnerableUntil or 0) - os.clock())
		Character:SetAttribute("IFramesUntil", workspace:GetServerTimeNow() + Left)
	end
end

----------------------------------------------------------------------
-- COOLDOWNS
----------------------------------------------------------------------

-- Sets or clears a named multiplier on the cooldowns this player
-- starts. Rage uses the key "Rage". The lowest one applies.
function PlayerStats:SetCooldownMultiplier(Key: string, Multiplier: number?)
	self.CooldownMultipliers = self.CooldownMultipliers or {}
	self.CooldownMultipliers[Key] = Multiplier
end

-- sets the gear's cooldown multipliers, kept apart for weapons and abilities and stacked on top of the buffs above
function PlayerStats:SetGearCooldownMultipliers(Weapon: number?, Ability: number?)
	self.GearCooldownMultipliers = { Weapon = Weapon or 1, Ability = Ability or 1 }
end

-- The multiplier on new cooldowns, 1 if none. Kind is "Weapon" or
-- "Ability" and adds the gear's multiplier for that kind.
function PlayerStats:GetCooldownMultiplier(Kind: string?): number
	local Best = 1
	for _, Multiplier in pairs(self.CooldownMultipliers or {}) do
		Best = math.min(Best, Multiplier)
	end
	local Gear = self.GearCooldownMultipliers
	if Gear and Kind and Gear[Kind] then
		Best *= Gear[Kind]
	end
	return Best
end

----------------------------------------------------------------------
-- LIFESTEAL
----------------------------------------------------------------------

-- Sets or clears a named lifesteal fraction, like the speed
-- multipliers. Rage uses the key "Rage". The highest one applies.
function PlayerStats:SetLifesteal(Key: string, Fraction: number?)
	self.Lifesteals = self.Lifesteals or {}
	self.Lifesteals[Key] = Fraction
end

-- The fraction of damage dealt that comes back as health, 0 if none.
function PlayerStats:GetLifesteal(): number
	local Best = 0
	for _, Fraction in pairs(self.Lifesteals or {}) do
		Best = math.max(Best, Fraction)
	end
	return Best
end

-- Kills the player outright, for kill planes and the like.
function PlayerStats:Kill(Source: any?)
	if not self.Values.IsAlive then
		return
	end
	self:SetHealth(0, Source)
end

-- Turns the current character into a see through spectator or back.
function PlayerStats:_SetSpectating(On: boolean)
	self.Spectating = On
	local Character = self.Character
	if not Character then
		return
	end
	local Settings = PlayerStats.Settings
	Character:SetAttribute(Settings.SpectatorAttribute, On or nil)
	for _, Part in ipairs(Character:GetDescendants()) do
		if Part:IsA("BasePart") and Part.Name ~= "HumanoidRootPart" then
			if On then
				if Part:GetAttribute("SpectatorOldTransparency") == nil then
					Part:SetAttribute("SpectatorOldTransparency", Part.Transparency)
				end
				Part.Transparency = math.max(Part.Transparency, Settings.SpectatorTransparency)
			else
				local Old = Part:GetAttribute("SpectatorOldTransparency")
				if Old ~= nil then
					Part.Transparency = Old
					Part:SetAttribute("SpectatorOldTransparency", nil)
				end
			end
		end
	end
	if not On then
		self:_SyncHumanoid()
	end
end

function PlayerStats:IsSpectating(): boolean
	return self.Spectating == true
end

-- Brings a dead player back with a fraction of max health.
function PlayerStats:Revive(HealthPercent: number?)
	local Percent = HealthPercent or GameConfig.Multiplayer.ReviveHealthPercent
	-- Revive only touches a live body. A player whose body is lying
	-- dead gets revived when their next character arrives instead.
	if self.Humanoid and self.Humanoid.Health <= 0 and not self.Spectating then
		self:_Set("IsAlive", true)
		self:_Set("Health", Clamp(math.floor(self.Values.MaxHealth * Percent + 0.5), 1, self.Values.MaxHealth))
		PlayerStats.Revived:Fire(self.Player)
		return
	end
	if self.Spectating then
		self.Spectating = false
		self:_Set("IsAlive", true)
		self:_Set("Health", Clamp(math.floor(self.Values.MaxHealth * Percent + 0.5), 1, self.Values.MaxHealth))
		self:_SetSpectating(false)
		PlayerStats.Revived:Fire(self.Player)
		return
	end
	self:_Set("IsAlive", true)
	self:_Set("Health", Clamp(math.floor(self.Values.MaxHealth * Percent + 0.5), 1, self.Values.MaxHealth))
	self:_SyncHumanoid()
	PlayerStats.Revived:Fire(self.Player)
end

-- Changes max health. AdjustCurrent true keeps the same fraction, so
-- 50/100 becomes 62.5/125. false leaves the current value alone and
-- only clamps it if the new max is lower.
function PlayerStats:SetMaxHealth(Value: number, AdjustCurrent: boolean?)
	Value = math.max(1, Value)
	local Fraction = self.Values.Health / self.Values.MaxHealth
	self:_Set("MaxHealth", Value)
	if AdjustCurrent then
		self:_Set("Health", Clamp(Value * Fraction, 0, Value))
	else
		self:_Set("Health", Clamp(self.Values.Health, 0, Value))
	end
	self:_SyncHumanoid()
end

-- Adds to max health. HealBy is how much of the increase is also
-- given as current health, so the health artifact can fill its own
-- bonus. nil heals by the full delta.
function PlayerStats:AddMaxHealth(Delta: number, HealBy: number?)
	self:SetMaxHealth(self.Values.MaxHealth + Delta, false)
	local Bonus = HealBy
	if Bonus == nil then
		Bonus = Delta
	end
	if Bonus > 0 then
		self:Heal(Bonus)
	end
end

----------------------------------------------------------------------
-- ENERGY
----------------------------------------------------------------------

function PlayerStats:GetEnergy(): number
	return self.Values.Energy
end

function PlayerStats:GetMaxEnergy(): number
	return self.Values.MaxEnergy
end

function PlayerStats:SetEnergy(Value: number)
	self:_Set("Energy", Clamp(Value, 0, self.Values.MaxEnergy))
end

-- Adds energy, clamped to max. Returns the amount actually added.
function PlayerStats:AddEnergy(Amount: number): number
	local Before = self.Values.Energy
	self:SetEnergy(Before + Amount)
	return self.Values.Energy - Before
end

function PlayerStats:CanAfford(Cost: number): boolean
	if GameConfig.Debug.FreeAbilities then
		return true
	end
	return self.Values.Energy >= Cost
end

-- Takes the cost if it can be afforded. Returns whether it was taken.
-- This is the only way energy should be spent, so an ability can never
-- fire without paying.
function PlayerStats:UseEnergy(Cost: number): boolean
	if not self:CanAfford(Cost) then
		return false
	end
	if not GameConfig.Debug.FreeAbilities then
		self:SetEnergy(self.Values.Energy - Cost)
	end
	self.LastEnergyUseAt = os.clock()
	return true
end

-- Seconds since energy was last spent, for the regen delay.
function PlayerStats:TimeSinceEnergyUse(): number
	return os.clock() - self.LastEnergyUseAt
end

function PlayerStats:SetMaxEnergy(Value: number, AdjustCurrent: boolean?)
	Value = math.max(1, Value)
	local Fraction = self.Values.Energy / self.Values.MaxEnergy
	self:_Set("MaxEnergy", Value)
	if AdjustCurrent then
		self:_Set("Energy", Clamp(Value * Fraction, 0, Value))
	else
		self:_Set("Energy", Clamp(self.Values.Energy, 0, Value))
	end
end

-- Adds to max energy. RefillBy nil also gives the full delta as
-- current energy.
function PlayerStats:AddMaxEnergy(Delta: number, RefillBy: number?)
	self:SetMaxEnergy(self.Values.MaxEnergy + Delta, false)
	local Bonus = RefillBy
	if Bonus == nil then
		Bonus = Delta
	end
	if Bonus > 0 then
		self:AddEnergy(Bonus)
	end
end

----------------------------------------------------------------------
-- MONEY AND LEVEL
----------------------------------------------------------------------

function PlayerStats:GetMoney(): number
	return self.Values.Money
end

function PlayerStats:AddMoney(Amount: number)
	if Amount == 0 then
		return
	end
	self:_Set("Money", math.max(0, self.Values.Money + Amount))
end

function PlayerStats:CanAffordMoney(Cost: number): boolean
	return self.Values.Money >= Cost
end

-- Takes the cost if it can be afforded. Returns whether it was taken.
function PlayerStats:SpendMoney(Cost: number): boolean
	if Cost < 0 or not self:CanAffordMoney(Cost) then
		return false
	end
	self:_Set("Money", self.Values.Money - Cost)
	return true
end

function PlayerStats:GetLevel(): number
	return self.Values.Level
end

function PlayerStats:SetLevel(Value: number)
	self:_Set("Level", math.max(1, math.floor(Value)))
end

function PlayerStats:AddLevel(Delta: number)
	self:SetLevel(self.Values.Level + Delta)
end

----------------------------------------------------------------------
-- INVENTORY
----------------------------------------------------------------------

-- A copy of the item ids the player is carrying, in the order bought.
function PlayerStats:GetInventory(): { string }
	return table.clone(self.Values.Inventory)
end

function PlayerStats:CountItems(): number
	return #self.Values.Inventory
end

function PlayerStats:HasItem(ItemId: string): boolean
	return table.find(self.Values.Inventory, ItemId) ~= nil
end

-- Adds an item if there is room. MaxItems nil means no limit, the
-- shop passes ShopItemData.Shop.InventorySize.
function PlayerStats:AddItem(ItemId: string, MaxItems: number?): boolean
	if MaxItems and #self.Values.Inventory >= MaxItems then
		return false
	end
	table.insert(self.Values.Inventory, ItemId)
	PlayerStats.Changed:Fire(self.Player, "Inventory", self:GetInventory(), nil)
	self:_QueueSend()
	return true
end

-- Removes one copy of an item. Returns whether one was there.
function PlayerStats:RemoveItem(ItemId: string): boolean
	local Index = table.find(self.Values.Inventory, ItemId)
	if not Index then
		return false
	end
	table.remove(self.Values.Inventory, Index)
	PlayerStats.Changed:Fire(self.Player, "Inventory", self:GetInventory(), nil)
	self:_QueueSend()
	return true
end

----------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------

-- The product of every named multiplier, so Rage at 1.25 and some
-- future buff at 1.1 give 1.375 rather than one overwriting the other.
function PlayerStats:GetSpeedMultiplier(): number
	local Product = 1
	for _, Multiplier in pairs(self.SpeedMultipliers) do
		Product *= Multiplier
	end
	return Product
end

-- Sets or clears a named speed multiplier. Key is who owns it, such
-- as "Rage". Pass nil to remove it when the buff ends.
function PlayerStats:SetSpeedMultiplier(Key: string, Multiplier: number?)
	self.SpeedMultipliers[Key] = Multiplier
	self:_Set("SpeedMultiplier", self:GetSpeedMultiplier())
	self:_ApplyMovement()
end

function PlayerStats:GetSpeedBonus(): number
	return self.Values.SpeedBonus
end

-- Adds a flat amount to walk speed for the rest of the run. The speed
-- artifact uses this.
function PlayerStats:AddSpeedBonus(Delta: number)
	self:_Set("SpeedBonus", self.Values.SpeedBonus + Delta)
	self:_ApplyMovement()
end

function PlayerStats:GetExtraJumps(): number
	return self.Values.ExtraJumps
end

-- Adds to the double jump's MaxAirUses for the rest of the run. The
-- jump artifact uses this.
function PlayerStats:AddExtraJumps(Delta: number)
	self:_Set("ExtraJumps", math.max(0, self.Values.ExtraJumps + Delta))
	self:_ApplyMovement()
end

----------------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------------

-- Wrapped so requiring this module from the Studio command bar, for
-- a quick test, does not error on a server only call.
pcall(function()
	GetStats.OnServerInvoke = function(Player: Player)
		local Stats = ByPlayer[Player]
		if not Stats then
			return nil
		end
		return Stats:GetSnapshot()
	end
end)

Players.PlayerRemoving:Connect(function(Player)
	PlayerStats.Remove(Player)
end)

return PlayerStats
