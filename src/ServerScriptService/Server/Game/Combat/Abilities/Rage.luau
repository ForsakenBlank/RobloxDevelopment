--[[
	Rage

	The buff ability. It costs energy like the others, and on top of that
	it takes a slice of the player's current health (AbilityData,
	HealthCostPercent), which can never leave them below 1 health. In
	return it raises their damage and their speed for a set time, and
	every hit they land while raging heals them for a share of the
	damage (the lifesteal), so a player who fights wins the cost back.

	This is Rage from the function plan. The health cost is what makes it
	a real decision rather than a free buff, and taking a percentage of
	current health rather than max health means it gets cheaper the lower
	you are, but also less worth using.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Abilities.AbilityBase, which handles the energy
	  cost and cooldown. The health cost is this module's own job,
	  because only this ability has one.

	Reads:
	  The Rage entry in Game.Data.AbilityData for the damage multiplier,
	  the speed bonus, the duration and the health cost percentage.

	Uses:
	  Server.Game.Core.PlayerStats to take the health, going through its
	  method so the HUD update fires and the value gets clamped. The
	  clamp to a minimum of 1 health belongs here, not in PlayerStats,
	  since it is a rule of this ability.
	  Server.Game.Effects.StatusEffectService to apply the Damage effect
	  for the duration, rather than this module holding its own timer.
	  That way the buff shows up on the HUD with the other effects and
	  gets cleared properly if the run ends early.

	The speed part:
	  Raising walk speed means writing to the Humanoid, which
	  ServerScriptService.Server.Modules.AntiCheat.Detectors.Movement
	  watches. The anti cheat has to be told the new expected speed for
	  the duration, or using Rage will flag the player. This is the same
	  problem the speed artifact in Server.Game.Shop.ShopItems has, so
	  solve it once in PlayerStats and have both go through it.
	  Also check ReplicatedStorage.Modules.Shared.MovementConfig, because
	  the movement framework may be setting walk speed itself for
	  sprinting and sliding, in which case a flat multiplier there is
	  better than writing to the Humanoid directly.

	Taking health must not be able to kill the player. If the clamp is
	missed, using Rage at low health kills you, which would look like a
	bug rather than a cost.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local AbilityBase = require(script.Parent.AbilityBase)
local PlayerStats = require(script.Parent.Parent.Parent.Core.PlayerStats)
local StatusEffectService = require(script.Parent.Parent.Parent.Effects.StatusEffectService)

local Rage = setmetatable({}, { __index = AbilityBase })
Rage.__index = Rage

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

Rage.Settings = {
	-- The key PlayerStats keeps Rage's speed multiplier under, so it
	-- can be removed without touching any other speed buff.
	SpeedKey = "Rage",
	-- The red glow on the character while Rage lasts.
	GlowColour = Color3.fromRGB(255, 50, 40),
}

----------------------------------------------------------------------
-- USE
----------------------------------------------------------------------

-- Refuses a second use while it is still running, unless AllowRefresh.
function Rage:CanUseExtra(Character: Model): (boolean, string?)
	if not self.Data.AllowRefresh and os.clock() < (self.ActiveUntil or 0) then
		return false, "already raging"
	end
	return true
end

function Rage:OnUse(Context)
	local Data = self.Data
	local Stats = PlayerStats.Get(Context.Player)
	if not Stats then
		return nil
	end

	-- The health cost, taken from current health and never below the
	-- minimum, so Rage can never kill.
	local Health = Stats:GetHealth()
	local Cost = Health * Data.HealthCostPercent
	local After = math.max(Data.MinHealthAfterCost, Health - Cost)
	if After < Health then
		Stats:SetHealth(After, "Rage")
	end

	-- Damage through the status effect so it shows on the HUD and is
	-- cleared with everything else when the run ends.
	StatusEffectService.Apply(Context.Player, "Damage", Data.Duration, Data.DamageMultiplier, Context.Player)

	-- Speed through PlayerStats, which tells the movement framework
	-- and the anti cheat.
	Stats:SetSpeedMultiplier(Rage.Settings.SpeedKey, Data.SpeedMultiplier)
	-- Hits heal while it lasts, which is how the health cost is won
	-- back. DamageService pays it out.
	Stats:SetLifesteal(Rage.Settings.SpeedKey, Data.Lifesteal)
	-- Faster cooldowns, see WeaponBase and AbilityBase StartCooldown.
	Stats:SetCooldownMultiplier(Rage.Settings.SpeedKey, Data.CooldownMultiplier)
	local Token = os.clock()
	self.ActiveUntil = Token + Data.Duration
	task.delay(Data.Duration, function()
		if self.ActiveUntil == Token + Data.Duration then
			local Current = PlayerStats.Get(Context.Player)
			if Current then
				Current:SetSpeedMultiplier(Rage.Settings.SpeedKey, nil)
				Current:SetLifesteal(Rage.Settings.SpeedKey, nil)
				Current:SetCooldownMultiplier(Rage.Settings.SpeedKey, nil)
			end
		end
	end)

	CombatFX.Broadcast("Rage", Context.Character, nil)
	CombatFX.Broadcast("StatusEffectStart", Context.Character, {
		Name = "Rage",
		Duration = Data.Duration,
		Colour = Rage.Settings.GlowColour,
	})
	return { Duration = Data.Duration }
end

return Rage
