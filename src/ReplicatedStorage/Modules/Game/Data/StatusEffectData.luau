--[[
	StatusEffectData

	The 6 status effects that can be put on a player or an enemy. Each
	entry holds how often it ticks, its default duration, the amount it
	applies per tick, whether that amount is damage, healing or a
	multiplier, and whether a second application of the same effect
	stacks, refreshes the timer or is ignored.

	Fire and Poison both deal damage over time, with Fire hitting harder
	and Poison lasting longer. Regeneration heals a small amount each
	tick. Damage is a multiplier on all outgoing attacks. Resistance cuts
	incoming damage by 25%. Stun stops a target moving or attacking for
	its duration.

	Also holds an icon and colour for each so the HUD does not have to
	keep its own copy of that list.
]]

--[[
	What connects to this

	Server.Game.Effects.StatusEffectService is the only module that
	should apply these. It reads the tick rate and amount from here and
	runs the loop. Everything else asks StatusEffectService rather than
	editing health or multipliers itself.

	Callers that ask for an effect:
	  Server.Game.Combat.Abilities.StunSlam applies Stun.
	  Server.Game.Combat.Abilities.Rage applies Damage.
	  Server.Game.Combat.Abilities.HealBurst applies Regeneration.
	  Server.Game.Shop.ShopItems applies Damage, Regeneration, Fire and
	  whatever the Mushroom rolls.
	  Server.Game.Enemies.Types.Necromancer applies Stun with its melee.

	Server.Game.Combat.DamageService has to read the active Damage and
	Resistance multipliers off the target before working out final
	damage, so StatusEffectService needs a getter for the current
	multiplier on a target.

	Stun has to be respected by Server.Game.Enemies.EnemyAI, which should
	skip its behaviour update while a stun is active rather than the
	effect system trying to freeze the humanoid itself.

	Every change gets sent to the client on
	ReplicatedStorage.Remotes.Events.EffectChanged so
	ClientGame.Controllers.HUDController can show the icon and timer.
]]

-- Note on when changes take effect. Everything here is read when an
-- effect is applied, so changing a number affects the next application
-- straight away, even mid playtest. An effect already running keeps
-- the numbers it started with.

local StatusEffectData = {}

----------------------------------------------------------------------
-- SHARED
----------------------------------------------------------------------

StatusEffectData.Shared = {
	-- How often the one loop in StatusEffectService runs. Every effect
	-- ticks on a multiple of this, so a TickRate below it is rounded
	-- up to it.
	LoopRate = 0.1,
	-- Effects on enemies are removed when the enemy dies. Effects on
	-- players are removed on death and at the end of the run.
	ClearOnDeath = true,
	-- Max number of different effects one target can have at once.
	-- Applying another when full is ignored.
	MaxEffectsPerTarget = 8,
}

----------------------------------------------------------------------
-- STACKING RULES
----------------------------------------------------------------------

-- What happens when an effect is applied to a target that already has
-- that effect. Each entry below picks one of these by name.
--   "Refresh"  restart the timer with the new duration, keep one copy
--   "Extend"   add the new duration onto the remaining time
--   "Highest"  keep whichever has the bigger amount, restart timer
--   "Stack"    run a second independent copy alongside the first
--   "Ignore"   leave the existing one alone, the new one does nothing
StatusEffectData.StackingRules = { "Refresh", "Extend", "Highest", "Stack", "Ignore" }

----------------------------------------------------------------------
-- EFFECTS
----------------------------------------------------------------------

-- Every effect has these:
--   Enabled          false makes Apply do nothing and warn
--   DisplayName      shown on the HUD
--   Kind             "Damage"      takes AmountPerTick health each tick
--                    "Heal"        gives AmountPerTick health each tick
--                    "Multiplier"  sets a multiplier on Stat for the
--                                  duration, no ticking
--                    "Control"     no numbers, just a flag the AI and
--                                  input check for the duration
--   TickRate         seconds between ticks. Ignored by Multiplier and
--                    Control
--   DefaultDuration  used when the caller does not give one
--   AmountPerTick    health per tick for Damage and Heal
--   Multiplier       the value for Multiplier effects
--   Stat             which multiplier it is, "OutgoingDamage" or
--                    "IncomingDamage"
--   Stacking         one of the rules above
--   IsHarmful        true shows it red on the HUD and counts as a bad
--                    roll for the Mushroom
--   AffectsPlayers / AffectsEnemies
--                    who it can be put on. Applying to the wrong side
--                    does nothing and warns
--   ShowOnHUD        false hides it from the player's effect bar
--   Colour           HUD icon tint
--   Icon             HUD icon image
--   ParticleName     nil, or an effect in ReplicatedStorage.Assets.
--                    Effects to attach to the target while active

StatusEffectData.Effects = {

	Fire = {
		Enabled = true,
		DisplayName = "Burning",
		Kind = "Damage",
		TickRate = 1,
		DefaultDuration = 4,
		AmountPerTick = 8,
		Stacking = "Refresh",
		IsHarmful = true,
		AffectsPlayers = true,
		AffectsEnemies = true,
		ShowOnHUD = true,
		Colour = Color3.fromRGB(255, 120, 40),
		Icon = "rbxassetid://0",
		ParticleName = "FireEffect",
	},

	Poison = {
		Enabled = true,
		DisplayName = "Poisoned",
		Kind = "Damage",
		TickRate = 1,
		DefaultDuration = 10,
		AmountPerTick = 3,
		Stacking = "Refresh",
		IsHarmful = true,
		AffectsPlayers = true,
		AffectsEnemies = true,
		ShowOnHUD = true,
		Colour = Color3.fromRGB(120, 220, 60),
		Icon = "rbxassetid://0",
		ParticleName = "PoisonEffect",
	},

	Regeneration = {
		Enabled = true,
		DisplayName = "Regenerating",
		Kind = "Heal",
		TickRate = 1,
		DefaultDuration = 10,
		AmountPerTick = 2,
		Stacking = "Refresh",
		IsHarmful = false,
		AffectsPlayers = true,
		AffectsEnemies = false,
		ShowOnHUD = true,
		Colour = Color3.fromRGB(80, 255, 140),
		Icon = "rbxassetid://0",
		ParticleName = "RegenEffect",
	},

	-- Multiplies outgoing damage. Rage and the Damage Potion both use
	-- this with their own multiplier, so "Highest" means a weaker one
	-- never overwrites a stronger one that is already running.
	Damage = {
		Enabled = true,
		DisplayName = "Damage Up",
		Kind = "Multiplier",
		Stat = "OutgoingDamage",
		TickRate = 0,
		DefaultDuration = 45,
		Multiplier = 1.5,
		Stacking = "Highest",
		IsHarmful = false,
		AffectsPlayers = true,
		AffectsEnemies = true,
		ShowOnHUD = true,
		Colour = Color3.fromRGB(255, 80, 80),
		Icon = "rbxassetid://0",
		ParticleName = nil,
	},

	-- Multiplies incoming damage. 0.75 is the 25% reduction from the
	-- design.
	Resistance = {
		Enabled = true,
		DisplayName = "Resistance",
		Kind = "Multiplier",
		Stat = "IncomingDamage",
		TickRate = 0,
		DefaultDuration = 30,
		Multiplier = 0.75,
		Stacking = "Highest",
		IsHarmful = false,
		AffectsPlayers = true,
		AffectsEnemies = true,
		ShowOnHUD = true,
		Colour = Color3.fromRGB(90, 160, 255),
		Icon = "rbxassetid://0",
		ParticleName = nil,
	},

	-- The AI skips its update and the player's input is blocked while
	-- this is active.
	Stun = {
		Enabled = true,
		DisplayName = "Stunned",
		Kind = "Control",
		TickRate = 0,
		DefaultDuration = 2,
		Stacking = "Refresh",
		IsHarmful = true,
		AffectsPlayers = true,
		AffectsEnemies = true,
		ShowOnHUD = true,
		Colour = Color3.fromRGB(255, 230, 80),
		Icon = "rbxassetid://0",
		ParticleName = "StunEffect",
		-- Stun specific. The boss cannot be stunned by default, so a
		-- Stun Slam does not trivialise the fight.
		AffectsBoss = false,
		-- Seconds after a stun ends before the same target can be
		-- stunned again. Stops permanent stun locking.
		ImmunityAfter = 1,
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks an effect up by name and warns rather than erroring if the
-- name is wrong or the effect is switched off.
function StatusEffectData.Get(EffectName: string)
	local Effect = StatusEffectData.Effects[EffectName]
	if not Effect then
		warn("[StatusEffectData] no effect called " .. tostring(EffectName))
		return nil
	end
	if not Effect.Enabled then
		warn("[StatusEffectData] effect " .. EffectName .. " is disabled")
		return nil
	end
	return Effect
end

-- Names of every enabled effect that is good or bad, for the Mushroom
-- roll and for anything else that wants a random one.
function StatusEffectData.GetNames(Harmful: boolean?): { string }
	local Names = {}
	for Name, Effect in pairs(StatusEffectData.Effects) do
		if Effect.Enabled and (Harmful == nil or Effect.IsHarmful == Harmful) then
			table.insert(Names, Name)
		end
	end
	table.sort(Names)
	return Names
end

return StatusEffectData
