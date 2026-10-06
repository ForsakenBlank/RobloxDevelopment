--[[
	StatFormulas

	All the maths for scaling stats, kept in one place so the same
	calculation is never written twice. Pure functions only, no state and
	no instances, which also makes it the easiest module to test.

	The functions it needs are the scaled enemy health from a base value,
	the scaled enemy damage, the money reward after the difficulty
	multiplier, the shop price after the difficulty multiplier, and the
	final damage after any Damage and Resistance effects on the target.

	The multiplayer scaling is the +0.5x per player rule. With the
	multiplier read from Game.Config.GameConfig that works out as
	1 + (playerCount - 1) * 0.5, so 1 player is 1x, 2 players is 1.5x,
	3 is 2x and 4 is 2.5x. One player on their own is never penalised.
]]

--[[
	What connects to this

	Reads:
	  Game.Config.GameConfig for the per player scaling value.
	  Game.Shared.RunConfig for the player count and difficulty entry of
	  the current run.

	Called by:
	  Server.Game.Enemies.EnemyBase when a spawned enemy has its health
	  and damage set. This is the only place enemy health should ever be
	  scaled, so no other module should multiply it again.
	  Server.Game.Combat.DamageService for the final damage number and
	  for the money reward on a kill.
	  Server.Game.Shop.ShopManager for prices when it rolls stock.

	Player count is locked in at the start of the run by RunSetup. Do not
	recount players here, otherwise enemies already alive would have
	health that no longer matches what a player joining or leaving mid
	run would produce, and the boss health bar would jump.
]]

-- Every function takes the run settings as an argument rather than
-- reaching for RunConfig itself, so they stay pure and can be tested
-- with a hand built table. Callers pass RunConfig.Get().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local Types = require(ReplicatedStorage.Modules.Game.Shared.Types)

local StatFormulas = {}

----------------------------------------------------------------------
-- TUNING
----------------------------------------------------------------------

-- Knobs for the formulas themselves. The per system multipliers live
-- in GameConfig, DifficultyConfig and the data tables, these are only
-- the shape of the maths.
StatFormulas.Settings = {
	-- Every damage number is rounded to this before being applied, so
	-- health bars show whole numbers. 1 rounds to whole, 0.5 to halves,
	-- 0 leaves it unrounded.
	DamageRounding = 1,
	-- Damage can never go below this after multipliers, so a heavily
	-- resisted hit still does something.
	MinDamage = 1,
	-- Money is rounded to this. 1 is whole coins.
	MoneyRounding = 1,
	-- Hits at or beyond MaxRange for falloff attacks are multiplied by
	-- the attack's own Falloff. Between 0 and MaxRange it is linear.
	FalloffCurve = "Linear",
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function RoundTo(Value: number, Step: number): number
	if Step <= 0 then
		return Value
	end
	return math.floor(Value / Step + 0.5) * Step
end

----------------------------------------------------------------------
-- ENEMY SCALING
----------------------------------------------------------------------

-- The multiplier for a player count on its own, using the GameConfig
-- rule. Exposed so the HUD can show "x1.5" without a run table.
function StatFormulas.PlayerMultiplier(PlayerCount: number): number
	local PerExtra = GameConfig.Multiplayer.EnemyHealthPerExtraPlayer
	return 1 + math.max(PlayerCount - 1, 0) * PerExtra
end

-- Max health for a spawned enemy from its EnemyData base.
function StatFormulas.EnemyHealth(BaseHealth: number, Run: Types.RunSettings): number
	local Scaled = BaseHealth * Run.EnemyHealthMultiplier * Run.Difficulty.EnemyHealth
	return math.max(RoundTo(Scaled, 1), 1)
end

-- Damage for one enemy attack from its EnemyData base.
function StatFormulas.EnemyDamage(BaseDamage: number, Run: Types.RunSettings): number
	local Scaled = BaseDamage * Run.EnemyDamageMultiplier * Run.Difficulty.EnemyDamage
	return RoundTo(Scaled, StatFormulas.Settings.DamageRounding)
end

----------------------------------------------------------------------
-- COMBAT
----------------------------------------------------------------------

-- Final damage after the attacker's outgoing multiplier and the
-- target's incoming multiplier. Both come from StatusEffectService's
-- getters and are 1 when nothing is active. Rage's DamageMultiplier
-- arrives here as part of AttackerMultiplier because it is applied
-- as a Damage effect.
function StatFormulas.FinalDamage(BaseDamage: number, AttackerMultiplier: number?, TargetMultiplier: number?): number
	local Damage = BaseDamage * (AttackerMultiplier or 1) * (TargetMultiplier or 1)
	Damage = RoundTo(Damage, StatFormulas.Settings.DamageRounding)
	if BaseDamage > 0 then
		Damage = math.max(Damage, StatFormulas.Settings.MinDamage)
	end
	return Damage
end

-- Damage at a distance from the centre of an explosion or slam.
-- Falloff is the fraction left at the edge, 1 meaning no falloff.
function StatFormulas.FalloffDamage(BaseDamage: number, Distance: number, Radius: number, Falloff: number?): number
	local Edge = Falloff or 1
	if Radius <= 0 or Distance <= 0 then
		return BaseDamage
	end
	local T = math.clamp(Distance / Radius, 0, 1)
	local Fraction = 1 - T * (1 - Edge)
	return RoundTo(BaseDamage * Fraction, StatFormulas.Settings.DamageRounding)
end

----------------------------------------------------------------------
-- ECONOMY
----------------------------------------------------------------------

-- Money paid for a kill from the EnemyData base.
function StatFormulas.MoneyReward(BaseReward: number, Run: Types.RunSettings, Extra: number?): number
	local Scaled = BaseReward * GameConfig.Rewards.MoneyMultiplier * Run.Difficulty.Money * (Extra or 1)
	return math.max(RoundTo(Scaled, StatFormulas.Settings.MoneyRounding), 0)
end

-- Shop price for an item, after its rarity and the difficulty. The
-- rounding step comes from ShopItemData.Shop.PriceRounding so the
-- shop owns how its prices look.
function StatFormulas.ShopPrice(BasePrice: number, RarityMultiplier: number, Run: Types.RunSettings, Rounding: number?): number
	local Scaled = BasePrice * RarityMultiplier * Run.Difficulty.ShopPrice
	return math.max(RoundTo(Scaled, Rounding or 1), 0)
end

----------------------------------------------------------------------
-- PLAYER
----------------------------------------------------------------------

-- Energy regained per second for this run, after the difficulty's
-- PlayerRegen multiplier.
function StatFormulas.EnergyRegenPerSecond(Run: Types.RunSettings): number
	return GameConfig.Player.EnergyRegenPerSecond * Run.Difficulty.PlayerRegen
end

-- Health regained per second for this run, after the same PlayerRegen
-- multiplier as energy.
function StatFormulas.HealthRegenPerSecond(Run: Types.RunSettings): number
	return (GameConfig.Player.HealthRegenPerSecond or 0) * Run.Difficulty.PlayerRegen
end

-- The health Rage takes, clamped so the player is left with at least
-- the minimum. Returns the amount to subtract, not the new health.
function StatFormulas.RageHealthCost(CurrentHealth: number, CostPercent: number, MinHealthAfter: number): number
	local Cost = CurrentHealth * CostPercent
	local Floor = math.max(CurrentHealth - MinHealthAfter, 0)
	return RoundTo(math.min(Cost, Floor), StatFormulas.Settings.DamageRounding)
end

-- Delay between waves for this run.
function StatFormulas.WaveDelay(BaseDelay: number, Run: Types.RunSettings): number
	return BaseDelay * Run.Difficulty.WaveDelay
end

return StatFormulas
