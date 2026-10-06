--[[
	StatusEffectService

	The one system for status effects, on players and on enemies alike.
	This is ApplyEffect from the function plan. It is given a target, an
	effect name, a duration and an amount, and it runs that effect on a
	loop until the timer runs out, then cleans it up.

	It also has to answer questions about what is active, since damage
	calculations need to know the current Damage and Resistance
	multipliers, and the enemy AI needs to know whether something is
	stunned.

	One loop for all active effects rather than a task.spawn per effect,
	so a room with thirty burning enemies does not create thirty threads.

	It holds Fire, Poison, Regeneration, Damage, Resistance and Stun. The
	numbers for all of them come from the data module, so this handles
	the mechanism and not the balance.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.StatusEffectData for the tick rate, amount and stacking
	  rule of each effect.

	Applies effects to:
	  Server.Game.Core.PlayerStats for players, going through its methods
	  so the HUD stays in step.
	  Server.Game.Enemies.EnemyBase for enemies, going through its
	  TakeDamage rather than writing health directly.

	Uses:
	  Server.Game.Combat.DamageService for every Fire and Poison tick, so
	  damage over time goes through the same path as a weapon hit and
	  gets the same multipliers and the same death handling. That means a
	  kill by Poison still pays out money correctly.

	Called by:
	  Server.Game.Combat.Abilities.StunSlam for Stun.
	  Server.Game.Combat.Abilities.Rage for Damage.
	  Server.Game.Combat.Abilities.HealBurst for Regeneration.
	  Server.Game.Shop.ShopItems for the Damage Potion, the Mushroom roll
	  and the Molotov's Fire.
	  Server.Game.Enemies.Types.Necromancer for the Stun on its melee.

	Read by:
	  Server.Game.Combat.DamageService, which needs the active Damage
	  multiplier on the attacker and the Resistance on the target before
	  it can work out final damage. So this needs a getter for the
	  current multiplier on a target, not just an applier.
	  Server.Game.Enemies.EnemyAI, which checks for an active Stun and
	  skips its update if there is one.

	Sends:
	  ReplicatedStorage.Remotes.Events.EffectChanged when an effect
	  starts, ends or is refreshed on a player, for
	  ClientGame.Controllers.HUDController to show the icons and timers.
	  Effects on enemies do not need sending unless there is a visual,
	  which goes out as a CombatFX broadcast instead.

	Cleanup:
	  Server.Game.Core.RunManager clears everything here when a run ends.
	  An effect on a target that has died or been destroyed has to stop
	  on its own too, or the loop keeps ticking on a nil target.

	Stun is different from the others. It does not change a number, it
	stops behaviour, which is why the enemy AI checks it rather than this
	module trying to freeze the humanoid. For a player it sets the
	Stunned attribute on the character, which the input controllers
	check.

	Targets are identified by a Player for players and by the Model for
	enemies. Anything else, an enemy object or a character model, is
	normalised to one of those two so callers do not have to care.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatusEffectData = require(ReplicatedStorage.Modules.Game.Data.StatusEffectData)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local EnemyBase = require(script.Parent.Parent.Enemies.EnemyBase)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local EffectChanged = Remotes.Events:WaitForChild("EffectChanged")

local StatusEffectService = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

StatusEffectService.Settings = {
	-- Attribute set on a stunned character, read by the input
	-- controllers and the enemy AI.
	StunnedAttribute = "Stunned",
	-- Stunned enemies have their walk speed held at this.
	StunnedWalkSpeed = 0,
}

-- Fired with (Key, EffectName, Active: boolean) on start and end.
StatusEffectService.Changed = Instance.new("BindableEvent")

-- Active effects, keyed by target key then effect name. Each entry is
-- { Name, Data, Amount, Multiplier, EndsAt, NextTickAt, Source }.
local Active: { [any]: { [string]: any } } = {}
-- Stun immunity end times per key.
local StunImmuneUntil: { [any]: number } = {}

local Connection: RBXScriptConnection? = nil
local Accumulator = 0

----------------------------------------------------------------------
-- TARGETS
----------------------------------------------------------------------

-- Normalises whatever the caller passed to the key the tables use:
-- a Player for players, a Model for enemies.
local function KeyFor(Target: any): any?
	if typeof(Target) == "Instance" then
		if Target:IsA("Player") then
			return Target
		end
		if Target:IsA("Model") then
			local Player = Players:GetPlayerFromCharacter(Target)
			if Player then
				return Player
			end
			local Enemy = EnemyBase.FromInstance(Target)
			return Enemy and Enemy.Model or nil
		end
		local Enemy = EnemyBase.FromInstance(Target)
		if Enemy then
			return Enemy.Model
		end
		return nil
	end
	if type(Target) == "table" and Target.Model then
		return Target.Model
	end
	return nil
end

local function IsPlayerKey(Key: any): boolean
	return typeof(Key) == "Instance" and Key:IsA("Player")
end

local function ModelFor(Key: any): Model?
	if IsPlayerKey(Key) then
		return Key.Character
	end
	return Key
end

-- Whether the target is still around and alive.
local function IsValid(Key: any): boolean
	if IsPlayerKey(Key) then
		local Stats = PlayerStats.Get(Key)
		return Stats ~= nil and Stats:IsAlive()
	end
	local Enemy = EnemyBase.FromInstance(Key)
	return Enemy ~= nil and not Enemy.IsDead
end

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function Notify(Key: any, EffectName: string, Duration: number?)
	if IsPlayerKey(Key) and Key.Parent == Players then
		EffectChanged:FireClient(Key, EffectName, Duration)
	end
	StatusEffectService.Changed:Fire(Key, EffectName, Duration ~= nil)
end

local function ApplyStunState(Key: any, Stunned: boolean)
	local Model = ModelFor(Key)
	if not Model then
		return
	end
	Model:SetAttribute(StatusEffectService.Settings.StunnedAttribute, Stunned or nil)

	local Enemy = EnemyBase.FromInstance(Model)
	if Enemy then
		Enemy.IsStunned = Stunned
		local Humanoid = Enemy.Humanoid
		if Stunned then
			Enemy.WalkSpeedBeforeStun = Humanoid.WalkSpeed
			Humanoid.WalkSpeed = StatusEffectService.Settings.StunnedWalkSpeed
			Humanoid:Move(Vector3.zero)
		else
			Humanoid.WalkSpeed = Enemy.WalkSpeedBeforeStun or Enemy.Data.WalkSpeed
		end
	end
end

local function EndEffect(Key: any, EffectName: string, Silent: boolean?)
	local Effects = Active[Key]
	local Entry = Effects and Effects[EffectName]
	if not Entry then
		return
	end
	Effects[EffectName] = nil
	if next(Effects) == nil then
		Active[Key] = nil
	end

	if Entry.Data.Kind == "Control" and EffectName == "Stun" then
		ApplyStunState(Key, false)
		StunImmuneUntil[Key] = os.clock() + (Entry.Data.ImmunityAfter or 0)
	end

	if Entry.Data.ParticleName then
		local Model = ModelFor(Key)
		if Model then
			CombatFX.Broadcast("StatusEffectEnd", Model, { Name = EffectName })
		end
	end

	if not Silent then
		Notify(Key, EffectName, nil)
	end
end

-- One tick of a damage or heal effect.
local function Tick(Key: any, Entry)
	local Model = ModelFor(Key)
	if not Model then
		return
	end
	-- DamageService is required lazily to avoid a require loop, since
	-- it reads the multipliers from here.
	local DamageService = require(script.Parent.Parent.Combat.DamageService)
	if Entry.Data.Kind == "Damage" then
		DamageService.ApplyDamage(Model, Entry.Amount, Entry.Source, {
			Source = Entry.Name,
			IgnoreMultipliers = true,
		})
	elseif Entry.Data.Kind == "Heal" then
		DamageService.ApplyHeal(Model, Entry.Amount)
	end
end

----------------------------------------------------------------------
-- APPLY
----------------------------------------------------------------------

-- Puts an effect on a target. Duration and Amount default to the data
-- table. Source is who caused it, for the damage credit. Returns
-- whether it was applied.
function StatusEffectService.Apply(Target: any, EffectName: string, Duration: number?, Amount: number?, Source: any?): boolean
	local Data = StatusEffectData.Get(EffectName)
	if not Data then
		return false
	end
	local Key = KeyFor(Target)
	if not Key or not IsValid(Key) then
		return false
	end

	local IsPlayer = IsPlayerKey(Key)
	if (IsPlayer and not Data.AffectsPlayers) or (not IsPlayer and not Data.AffectsEnemies) then
		warn("[StatusEffectService] " .. EffectName .. " cannot be applied to that side")
		return false
	end

	if EffectName == "Stun" then
		local Enemy = not IsPlayer and EnemyBase.FromInstance(Key) or nil
		if Enemy and Enemy.Data.IsBoss and not Data.AffectsBoss then
			return false
		end
		if (StunImmuneUntil[Key] or 0) > os.clock() then
			return false
		end
	end

	local Length = Duration or Data.DefaultDuration
	local Value = Amount or Data.AmountPerTick or 0
	local Multiplier = Amount or Data.Multiplier or 1

	local Effects = Active[Key]
	if not Effects then
		Effects = {}
		Active[Key] = Effects
	end

	local Existing = Effects[EffectName]
	if Existing then
		local Rule = Data.Stacking
		if Rule == "Ignore" then
			return false
		elseif Rule == "Extend" then
			Existing.EndsAt += Length
		elseif Rule == "Highest" then
			if Data.Kind == "Multiplier" then
				Existing.Multiplier = math.max(Existing.Multiplier, Multiplier)
			else
				Existing.Amount = math.max(Existing.Amount, Value)
			end
			Existing.EndsAt = os.clock() + Length
		else
			-- Refresh, and Stack which is treated as Refresh since the
			-- HUD shows one icon per effect.
			Existing.EndsAt = os.clock() + Length
			Existing.Amount = Value
			Existing.Multiplier = Multiplier
		end
		Existing.Source = Source or Existing.Source
		Notify(Key, EffectName, Existing.EndsAt - os.clock())
		return true
	end

	local Count = 0
	for _ in pairs(Effects) do
		Count += 1
	end
	if Count >= StatusEffectData.Shared.MaxEffectsPerTarget then
		return false
	end

	local Now = os.clock()
	Effects[EffectName] = {
		Name = EffectName,
		Data = Data,
		Amount = Value,
		Multiplier = Multiplier,
		EndsAt = Now + Length,
		NextTickAt = Now + math.max(Data.TickRate, StatusEffectData.Shared.LoopRate),
		Source = Source,
	}

	if EffectName == "Stun" then
		ApplyStunState(Key, true)
	end

	if Data.ParticleName then
		local Model = ModelFor(Key)
		if Model then
			CombatFX.Broadcast("StatusEffectStart", Model, { Name = EffectName, Duration = Length, Colour = Data.Colour })
		end
	end

	Notify(Key, EffectName, Length)
	return true
end

function StatusEffectService.Remove(Target: any, EffectName: string)
	local Key = KeyFor(Target)
	if Key then
		EndEffect(Key, EffectName)
	end
end

-- Clears every effect on a target, for death and for the run ending.
function StatusEffectService.ClearTarget(Target: any)
	local Key = KeyFor(Target) or Target
	local Effects = Active[Key]
	if not Effects then
		return
	end
	for EffectName in pairs(table.clone(Effects)) do
		EndEffect(Key, EffectName)
	end
end

function StatusEffectService.ClearAll()
	for Key in pairs(table.clone(Active)) do
		StatusEffectService.ClearTarget(Key)
	end
	StunImmuneUntil = {}
end

----------------------------------------------------------------------
-- QUERIES
----------------------------------------------------------------------

function StatusEffectService.Has(Target: any, EffectName: string): boolean
	local Key = KeyFor(Target)
	local Effects = Key and Active[Key]
	return Effects ~= nil and Effects[EffectName] ~= nil
end

function StatusEffectService.GetRemaining(Target: any, EffectName: string): number
	local Key = KeyFor(Target)
	local Effects = Key and Active[Key]
	local Entry = Effects and Effects[EffectName]
	return Entry and math.max(0, Entry.EndsAt - os.clock()) or 0
end

function StatusEffectService.IsStunned(Target: any): boolean
	return StatusEffectService.Has(Target, "Stun")
end

-- Names of the effects active on a target.
function StatusEffectService.GetActive(Target: any): { string }
	local Names = {}
	local Key = KeyFor(Target)
	local Effects = Key and Active[Key]
	if Effects then
		for Name in pairs(Effects) do
			table.insert(Names, Name)
		end
	end
	return Names
end

local function MultiplierFor(Target: any, Stat: string): number
	local Key = KeyFor(Target)
	local Effects = Key and Active[Key]
	if not Effects then
		return 1
	end
	local Product = 1
	for _, Entry in pairs(Effects) do
		if Entry.Data.Kind == "Multiplier" and Entry.Data.Stat == Stat then
			Product *= Entry.Multiplier
		end
	end
	return Product
end

-- The Damage multiplier on an attacker, 1 if none.
function StatusEffectService.GetOutgoingMultiplier(Attacker: any): number
	return MultiplierFor(Attacker, "OutgoingDamage")
end

-- The Resistance multiplier on a target, 1 if none.
function StatusEffectService.GetIncomingMultiplier(Target: any): number
	return MultiplierFor(Target, "IncomingDamage")
end

----------------------------------------------------------------------
-- LOOP
----------------------------------------------------------------------

local function Step()
	local Now = os.clock()
	for Key, Effects in pairs(Active) do
		if not IsValid(Key) then
			StatusEffectService.ClearTarget(Key)
			continue
		end
		for EffectName, Entry in pairs(Effects) do
			if Now >= Entry.EndsAt then
				EndEffect(Key, EffectName)
			elseif (Entry.Data.Kind == "Damage" or Entry.Data.Kind == "Heal") and Now >= Entry.NextTickAt then
				Entry.NextTickAt = Now + math.max(Entry.Data.TickRate, StatusEffectData.Shared.LoopRate)
				Tick(Key, Entry)
			end
		end
	end
end

function StatusEffectService.Init()
	if Connection then
		return
	end
	Connection = RunService.Heartbeat:Connect(function(DeltaTime)
		Accumulator += DeltaTime
		if Accumulator < StatusEffectData.Shared.LoopRate then
			return
		end
		Accumulator = 0
		Step()
	end)

	if StatusEffectData.Shared.ClearOnDeath then
		PlayerStats.Died.Event:Connect(function(Player)
			StatusEffectService.ClearTarget(Player)
		end)
		EnemyBase.Died.Event:Connect(function(Enemy)
			StatusEffectService.ClearTarget(Enemy.Model)
		end)
	end

	Players.PlayerRemoving:Connect(function(Player)
		Active[Player] = nil
		StunImmuneUntil[Player] = nil
	end)
end

return StatusEffectService
