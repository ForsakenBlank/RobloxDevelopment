--[[
	DamageService

	The one place damage is applied. Everything that hurts anything in
	this game goes through here: player weapons, player abilities, enemy
	attacks, damage over time from Fire and Poison, and the Molotov.

	It takes who is doing the damage, who is taking it and the base
	amount, then applies the multipliers in a fixed order. The attacker's
	Damage effect and Rage buff multiply it up, the target's Resistance
	effect takes 25% off, and the difficulty multiplier applies to enemy
	damage against players. Then it takes the health off and checks for
	death.

	On a kill it also pays out the money to the player who got the kill
	and tells the wave system the enemy is gone.

	Having one order of operations here is what stops damage numbers
	being inconsistent between weapons, which would be very hard to track
	down once four weapons and three abilities are all doing their own
	maths.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Combat.Weapons.Sword, Pistol, RPG and Shotgun.
	  Server.Game.Combat.Abilities.StunSlam and Rage.
	  Server.Game.Combat.ProjectileService when a projectile lands.
	  Server.Game.Effects.StatusEffectService for each Fire and Poison
	  tick.
	  Server.Game.Enemies.EnemyBase and every enemy type for their
	  attacks.
	  Server.Game.Shop.ShopItems for the Molotov.

	Reads:
	  Server.Game.Effects.StatusEffectService for the active Damage and
	  Resistance multipliers on both sides. Until that module exists
	  both multipliers are 1.
	  Game.Shared.StatFormulas for the final damage calculation and for
	  the money reward after the difficulty multiplier.
	  Game.Config.GameConfig for the base money settings.

	Writes:
	  Server.Game.Core.PlayerStats when a player takes damage or earns
	  money, and it goes through the PlayerStats methods so the HUD
	  update fires.
	  Server.Game.Enemies.EnemyBase TakeDamage for enemies, rather than
	  writing to their humanoid directly.

	Tells:
	  Server.Game.Core.RunManager when a player dies, since it is
	  RunManager that decides whether the run is over. PlayerStats.Died
	  is the signal it listens to.

	Feedback:
	  The attacker gets a DamageNumber effect (the floating number, and
	  the hit sound) through Game.Shared.CombatFX, drawn only on their
	  own client, and the HitConfirmed remote for their hit marker. A
	  player who gets hurt gets a DamageIndicator pointing at whatever
	  hit them. Rage's lifesteal is paid back here too.

	Two things worth getting right. Money in multiplayer goes to the
	player who got the kill only, not everyone, which matches the design
	and is GameConfig.Rewards.MoneySplit. And a target already at zero
	health must not take damage again, or two players hitting the same
	enemy in one frame both get paid for it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local StatFormulas = require(ReplicatedStorage.Modules.Game.Shared.StatFormulas)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local Signal = require(ReplicatedStorage.Modules.Game.Shared.Signal)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local EnemyBase = require(script.Parent.Parent.Enemies.EnemyBase)

local DamageService = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

DamageService.Settings = {
	-- The floating number drawn on the attacker's screen when
	-- GameConfig.Debug.ShowDamageNumbers is on. The look is the
	-- ReplicatedStorage.Assets.UI.DamageNumber template, drawn by
	-- CombatFX's DamageNumber effect on the client.
	DamageNumbers = true,
	-- Sounds the attacker hears on a headshot and on a kill, on top of
	-- the attack's own HitSound.
	CritSound = "HeadshotDing",
	KillSound = "KillPing",
	-- Knockback on an enemy is applied as an instant change in
	-- velocity. On a player it goes through the anti cheat as an
	-- exception so the shove is not flagged.
	KnockbackUpward = 0.35,
	PlayerKnockbackGrace = 1,
	-- Shortest gap between two hit markers sent to one player.
	HitMarkerRate = 0.05,
	-- Shortest gap between two damage direction arrows for one player.
	IndicatorRate = 0.15,
}

-- Tells a player their hit landed, for the hit marker on their HUD.
local HitConfirmed = ReplicatedStorage:WaitForChild("Remotes").Events:WaitForChild("HitConfirmed")
local LastHitSent: { [Player]: number } = {}
local LastIndicator: { [Player]: number } = {}
Players.PlayerRemoving:Connect(function(Player)
	LastHitSent[Player] = nil
	LastIndicator[Player] = nil
end)

-- Fired with (Target, Amount, Attacker, Info, Killed) after every
-- damage event, for anything that wants to react without being in
-- the chain, such as a hit marker or the kill feed.
DamageService.Damaged = Signal.new()
-- Fired with (Enemy, Killer, Reward, Source) when an enemy dies to damage.
-- Source is the hit's label, such as "Sword MB1".
DamageService.EnemyKilled = Signal.new()

----------------------------------------------------------------------
-- MULTIPLIERS
----------------------------------------------------------------------

-- StatusEffectService is still being written, so this looks it up
-- lazily and falls back to 1 until it has the getters.
local StatusEffectService = nil
local CheckedEffects = false

local function GetEffects()
	if CheckedEffects then
		return StatusEffectService
	end
	CheckedEffects = true
	local Module = script.Parent.Parent.Effects:FindFirstChild("StatusEffectService")
	if Module then
		local Ok, Result = pcall(require, Module)
		if Ok and type(Result) == "table" and type(Result.GetOutgoingMultiplier) == "function" then
			StatusEffectService = Result
		end
	end
	return StatusEffectService
end

local function OutgoingMultiplier(Attacker: any): number
	local Effects = GetEffects()
	if Effects and Attacker then
		local Ok, Value = pcall(Effects.GetOutgoingMultiplier, Attacker)
		if Ok and type(Value) == "number" then
			return Value
		end
	end
	return 1
end

local function IncomingMultiplier(Target: any): number
	local Effects = GetEffects()
	if Effects and Target then
		local Ok, Value = pcall(Effects.GetIncomingMultiplier, Target)
		if Ok and type(Value) == "number" then
			return Value
		end
	end
	return 1
end

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function RootOf(Model: Model?): BasePart?
	if not Model then
		return nil
	end
	return Model:FindFirstChild("HumanoidRootPart") or Model.PrimaryPart
end

-- Draws a number over a hit on one player's screen. Kind is "Hit",
-- "Crit", "Kill" or "Heal". Sound plays for them at the same time.
local function ShowNumber(Player: Player?, Target: Model, At: Vector3, Amount: number, Kind: string, Sound: string?)
	if not Player or Player.Parent ~= Players then
		return
	end
	if not (GameConfig.Debug.ShowDamageNumbers and DamageService.Settings.DamageNumbers) then
		Amount = 0
	end
	CombatFX.SendTo(Player, "DamageNumber", nil, {
		Target = Target,
		Position = At,
		Amount = Amount,
		Kind = Kind,
		Sound = Sound,
	})
end

-- A negative Amount pulls the target toward From instead.
local function ApplyKnockback(Target: Model, Amount: number, From: Vector3?, IsPlayer: boolean)
	if Amount == 0 then
		return
	end
	local Root = RootOf(Target)
	if not Root or not From then
		return
	end
	local Flat = Root.Position - From
	Flat = Vector3.new(Flat.X, 0, Flat.Z)
	if Flat.Magnitude < 0.01 then
		Flat = Vector3.new(0, 0, -1)
	end
	local Direction
	if Amount < 0 then
		-- A pull stays flat, straight towards From.
		Direction = -Flat.Unit
		Amount = -Amount
	else
		Direction = (Flat.Unit + Vector3.new(0, DamageService.Settings.KnockbackUpward, 0)).Unit
	end

	if IsPlayer then
		-- The player's client owns its character's physics, so a
		-- velocity set here gets overwritten. Its client applies the
		-- shove instead, and the anti cheat is told to expect it.
		local Player = Players:GetPlayerFromCharacter(Target)
		if Player then
			AntiCheat.GrantException(Player, DamageService.Settings.PlayerKnockbackGrace)
			CombatFX.SendTo(Player, "Knockback", nil, { Velocity = Direction * Amount })
		end
		return
	end
	-- Enemies are server owned, but a humanoid walking fights a plain
	-- velocity change, so the push also briefly stops them walking.
	local Humanoid = Target:FindFirstChildOfClass("Humanoid")
	if Humanoid then
		Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	Root.AssemblyLinearVelocity = Direction * Amount
end

-- Pays the kill reward according to GameConfig.Rewards.MoneySplit.
local function PayReward(Enemy, Killer: Player?)
	local Run = RunConfig.Get()
	if not Run then
		return 0
	end
	local Reward = StatFormulas.MoneyReward(Enemy.Data.MoneyReward, Run, Enemy.RewardMultiplier)
	if Reward <= 0 then
		return 0
	end

	local Split = GameConfig.Rewards.MoneySplit
	if Split == "Killer" then
		local Stats = Killer and PlayerStats.Get(Killer)
		if Stats then
			Stats:AddMoney(Reward)
		end
	else
		local Alive = {}
		for _, Stats in pairs(PlayerStats.GetAll()) do
			if Stats:IsAlive() then
				table.insert(Alive, Stats)
			end
		end
		local Each = Split == "Split" and Reward / math.max(#Alive, 1) or Reward
		for _, Stats in ipairs(Alive) do
			Stats:AddMoney(Each)
		end
	end
	return Reward
end

----------------------------------------------------------------------
-- DAMAGE
----------------------------------------------------------------------

-- Applies damage to a target model. Returns the amount dealt and
-- whether it killed.
--   Target     the enemy or player character model
--   BaseDamage the unmodified number from the data table
--   Attacker   the Player, or the enemy object, doing it. nil for
--              environmental damage
--   Info       optional table:
--     Source       a label for the log, such as "Sword MB1"
--     Knockback    studs per second to shove the target
--     From         where the shove comes from, defaults to the
--                  attacker's position
--     IgnoreMultipliers  true skips the effect multipliers, for
--                  damage over time that was already calculated
function DamageService.ApplyDamage(Target: Model, BaseDamage: number, Attacker: any, Info: { [string]: any }?): (number, boolean)
	Info = Info or {}
	if BaseDamage <= 0 or not Target then
		return 0, false
	end

	local Enemy = EnemyBase.FromInstance(Target)
	local TargetPlayer = not Enemy and Players:GetPlayerFromCharacter(Target) or nil
	local TargetStats = TargetPlayer and PlayerStats.Get(TargetPlayer) or nil

	if not Enemy and not TargetStats then
		return 0, false
	end
	if (Enemy and Enemy.IsDead) or (TargetStats and not TargetStats:IsAlive()) then
		return 0, false
	end

	-- Friendly fire between players is off.
	if TargetStats and typeof(Attacker) == "Instance" and Attacker:IsA("Player") then
		return 0, false
	end

	local Amount = BaseDamage
	if not Info.IgnoreMultipliers then
		local AttackerKey = Attacker
		local TargetKey = TargetPlayer or Target
		local Outgoing = OutgoingMultiplier(AttackerKey)
		-- The quick swap bonus: a player who has just swapped weapons
		-- hits harder for a moment (GameConfig.Loadout.QuickSwap).
		if Enemy and typeof(Attacker) == "Instance" and Attacker:IsA("Player") then
			local AttackerStats = PlayerStats.Get(Attacker)
			local QuickSwap = GameConfig.Loadout.QuickSwap
			if AttackerStats and QuickSwap and os.clock() < (AttackerStats.QuickSwapUntil or 0) then
				Outgoing *= QuickSwap.DamageMultiplier or 1
				Info.QuickSwap = true
			end
		end
		Amount = StatFormulas.FinalDamage(BaseDamage, Outgoing, IncomingMultiplier(TargetKey))
	end

	local Dealt, Killed
	if Enemy then
		Dealt, Killed = Enemy:TakeDamage(Amount, Attacker, Info)
	else
		Dealt, Killed = TargetStats:TakeDamage(Amount, Info.Source or Attacker)
	end

	if Dealt <= 0 then
		return 0, false
	end

	-- Where the shove comes from: the attacker's root if it has one.
	local From = Info.From
	if not From then
		if typeof(Attacker) == "Instance" and Attacker:IsA("Player") then
			local Root = RootOf(Attacker.Character)
			From = Root and Root.Position
		elseif type(Attacker) == "table" and Attacker.Root then
			From = Attacker.Root.Position
		end
	end
	if Info.Knockback and Info.Knockback ~= 0 then
		ApplyKnockback(Target, Info.Knockback, From, TargetStats ~= nil)
	end

	local AttackerPlayer = typeof(Attacker) == "Instance" and Attacker:IsA("Player") and Attacker or nil

	-- The number and hit sound, for the player who landed it.
	if Enemy and AttackerPlayer then
		local Root = RootOf(Target)
		local Settings = DamageService.Settings
		local Kind = Killed and "Kill" or (Info.Crit and "Crit" or (Info.QuickSwap and "Swap" or "Hit"))
		local Sound = Killed and Settings.KillSound or (Info.Crit and Settings.CritSound or Info.HitSound)
		ShowNumber(AttackerPlayer, Target, Root and Root.Position or Target:GetPivot().Position, Dealt, Kind, Sound)

		-- Rage's lifesteal.
		local AttackerStats = PlayerStats.Get(AttackerPlayer)
		if AttackerStats and AttackerStats:IsAlive() then
			local Lifesteal = AttackerStats:GetLifesteal()
			if Lifesteal > 0 then
				AttackerStats:Heal(Dealt * Lifesteal)
			end
		end
	end

	-- The arrow on a hurt player's screen pointing at what hit them.
	if TargetPlayer and From then
		local Now = os.clock()
		if Now - (LastIndicator[TargetPlayer] or 0) > DamageService.Settings.IndicatorRate then
			LastIndicator[TargetPlayer] = Now
			CombatFX.SendTo(TargetPlayer, "DamageIndicator", nil, { From = From, Amount = Dealt })
		end
	end

	if GameConfig.Debug.LogDamage then
		local Who = Enemy and Enemy.TypeName or (TargetPlayer and TargetPlayer.Name) or "?"
		local By = typeof(Attacker) == "Instance" and Attacker.Name or (type(Attacker) == "table" and Attacker.TypeName) or "world"
		print(string.format("[DamageService] %s hit %s for %.1f (%s)%s", By, Who, Dealt, tostring(Info.Source), Killed and " KILL" or ""))
	end

	DamageService.Damaged:Fire(Target, Dealt, Attacker, Info, Killed)

	-- The hit marker on the attacker's screen. Throttled so a shotgun
	-- blast is one marker, but a kill always shows.
	if Enemy and AttackerPlayer then
		local Now = os.clock()
		if Killed or Info.Crit or Now - (LastHitSent[AttackerPlayer] or 0) > DamageService.Settings.HitMarkerRate then
			LastHitSent[AttackerPlayer] = Now
			HitConfirmed:FireClient(AttackerPlayer, Killed == true, Info.Crit == true)
		end
	end

	-- A hit can carry an effect, the Molotov's Fire for instance.
	if Info.StatusEffect and not Killed then
		local Effects = GetEffects()
		if Effects and type(Effects.Apply) == "function" then
			Effects.Apply(Target, Info.StatusEffect.Name, Info.StatusEffect.Duration, Info.StatusEffect.Amount, Attacker)
		end
	end

	if Killed and Enemy then
		local Killer = AttackerPlayer
		local Reward = PayReward(Enemy, Killer)
		DamageService.EnemyKilled:Fire(Enemy, Killer, Reward, Info.Source)
	end

	return Dealt, Killed
end

-- Applies the same base damage to every hit record from HitDetection.
-- Returns the total dealt and how many died.
function DamageService.ApplyToHits(Hits: { any }, BaseDamage: number, Attacker: any, Info: { [string]: any }?): (number, number)
	local Total, Kills = 0, 0
	for _, Hit in ipairs(Hits) do
		local Dealt, Killed = DamageService.ApplyDamage(Hit.Model, BaseDamage, Attacker, Info)
		Total += Dealt
		if Killed then
			Kills += 1
		end
	end
	return Total, Kills
end

-- Healing goes through here too so the number shows and the same
-- target rules apply. Returns the amount healed.
function DamageService.ApplyHeal(Target: Model, Amount: number): number
	local Enemy = EnemyBase.FromInstance(Target)
	local Player = not Enemy and Players:GetPlayerFromCharacter(Target) or nil
	local Stats = Player and PlayerStats.Get(Player) or nil

	local Healed = 0
	if Enemy then
		Healed = Enemy:Heal(Amount)
	elseif Stats then
		Healed = Stats:Heal(Amount)
	end

	if Healed > 0 and Player then
		local Root = RootOf(Target)
		if Root then
			ShowNumber(Player, Target, Root.Position, Healed, "Heal", nil)
		end
	end
	return Healed
end

return DamageService
