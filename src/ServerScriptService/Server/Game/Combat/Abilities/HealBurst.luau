--[[
	HealBurst

	The support ability, and the 4th one added on top of the 3 in the
	original design. It costs energy like the others. On use it instantly
	heals the player and any teammate within a radius by a flat amount,
	then leaves a Regeneration effect on each of them for a few seconds.
	Any teammate inside the radius who is down (spectating) is revived
	on the spot, which is the only way to bring someone back before the
	room is cleared.

	It fills the gap the other three leave. Stun Slam is damage and
	control, Teleport is movement, Rage is a buff at a health cost, and
	nothing gives health back apart from shop potions. In multiplayer the
	radius makes it a reason to stay near your teammate, which is the
	kind of decision the co-op design wants.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Abilities.AbilityBase, which handles the energy
	  cost and cooldown. This module only does the heal and the effect.

	Reads:
	  The HealBurst entry in Game.Data.AbilityData for the instant heal
	  amount, the teammate radius, and the Regeneration duration.

	Uses:
	  Server.Game.Core.PlayerStats to add the health, going through its
	  method so the value gets clamped to max health and the HUD update
	  fires. The clamp lives in PlayerStats since every heal needs it,
	  unlike Rage's minimum of 1 which is that ability's own rule.
	  Server.Game.Effects.StatusEffectService to apply the Regeneration
	  effect for the duration, rather than this module holding its own
	  timer. That way it shows on the HUD with the other effects and gets
	  cleared properly if the run ends early.
	  Server.Game.Core.RunManager, or whatever holds the list of players
	  in the run, to find the teammates in range. Use the HumanoidRoot
	  Part distance rather than a Region or overlap check, since there
	  are at most a handful of players and it avoids catching enemies.

	Only players are ever healed. Enemies in the radius are not touched,
	so this never needs to go through Server.Game.Combat.DamageService.

	Healing is not damage, so the Damage and Resistance multipliers in
	StatusEffectService do not apply to it. If a healing multiplier is
	ever wanted it is a new effect, not a reuse of Damage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local AbilityBase = require(script.Parent.AbilityBase)
local PlayerStats = require(script.Parent.Parent.Parent.Core.PlayerStats)
local StatusEffectService = require(script.Parent.Parent.Parent.Effects.StatusEffectService)
local RunStats = require(script.Parent.Parent.Parent.Core.RunStats)

local HealBurst = setmetatable({}, { __index = AbilityBase })
HealBurst.__index = HealBurst

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Every living player the burst reaches, the user first if
-- IncludeSelf.
function HealBurst:GetTargets(Character: Model): { Player }
	local Data = self.Data
	local Root = Character:FindFirstChild("HumanoidRootPart")
	local List = {}
	if not Root then
		return List
	end
	for _, Other in ipairs(Players:GetPlayers()) do
		local Stats = PlayerStats.Get(Other)
		local OtherRoot = Other.Character and Other.Character:FindFirstChild("HumanoidRootPart")
		if Stats and Stats:IsAlive() and OtherRoot then
			local IsSelf = Other == self.Player
			if IsSelf and Data.IncludeSelf then
				table.insert(List, Other)
			elseif not IsSelf and Data.Radius > 0 and (OtherRoot.Position - Root.Position).Magnitude <= Data.Radius then
				table.insert(List, Other)
			end
		end
	end
	return List
end

----------------------------------------------------------------------
-- USE
----------------------------------------------------------------------

-- With AllowAtFullHealth off it refuses when nobody it would reach is
-- hurt, so the energy is not wasted.
function HealBurst:CanUseExtra(Character: Model): (boolean, string?)
	if self.Data.AllowAtFullHealth then
		return true
	end
	for _, Player in ipairs(self:GetTargets(Character)) do
		local Stats = PlayerStats.Get(Player)
		if Stats and Stats:GetHealth() < Stats:GetMaxHealth() then
			return true
		end
	end
	return false, "everyone is at full health"
end

function HealBurst:OnUse(Context)
	local Data = self.Data
	local DamageService = require(script.Parent.Parent.DamageService)
	local Healed = 0
	-- the healer's gear makes every heal bigger
	local Boost = RunStats.Value(Context.Player, "HealingMultiplier") or 1
	for _, Player in ipairs(self:GetTargets(Context.Character)) do
		if Player.Character then
			DamageService.ApplyHeal(Player.Character, Data.HealAmount * Boost)
			if Data.Regen and Data.Regen.Enabled then
				StatusEffectService.Apply(Player, "Regeneration", Data.Regen.Duration, Data.Regen.AmountPerTick * Boost, Context.Player)
			end
			Healed += 1
		end
	end
	-- Teammates who are down and close enough come back.
	local Revived = 0
	if (Data.ReviveHealthPercent or 0) > 0 and Data.Radius > 0 then
		for _, Other in ipairs(Players:GetPlayers()) do
			local Stats = PlayerStats.Get(Other)
			local OtherRoot = Other.Character and Other.Character:FindFirstChild("HumanoidRootPart")
			if Other ~= self.Player and Stats and not Stats:IsAlive() and Stats:IsSpectating() and OtherRoot
				and (OtherRoot.Position - Context.Root.Position).Magnitude <= Data.Radius then
				Stats:Revive(Data.ReviveHealthPercent)
				Revived += 1
				local Notify = game:GetService("ReplicatedStorage").Remotes.Events:FindFirstChild("Notify")
				if Notify then
					Notify:FireAllClients(string.format("%s revived %s!", self.Player.DisplayName, Other.DisplayName))
				end
			end
		end
	end

	CombatFX.Broadcast("HealBurst", Context.Character, { Position = Context.Root.Position, Radius = Data.Radius })
	return { Healed = Healed, Revived = Revived }
end

return HealBurst
