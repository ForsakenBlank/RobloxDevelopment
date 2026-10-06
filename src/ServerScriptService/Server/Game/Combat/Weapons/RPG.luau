--[[
	RPG

	The explosive weapon. MB1 fires a rocket that explodes where it
	lands and damages everything in the blast radius, with a long
	cooldown to balance it. MB2 is a barrage: three of those same
	rockets fired at once in a fan, on a slightly longer cooldown.

	These are RPGMB1 and RPGMB2 from the function plan. The barrage is
	the biggest burst of damage in the game, so its cooldown is the
	thing that keeps it fair. OnMB2 fires whatever the MB2 data table
	describes as an even fan, so the barrage is set up entirely in
	WeaponData.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Weapons.WeaponBase.

	Reads:
	  The RPG entry in Game.Data.WeaponData for the rocket damage, blast
	  radius, the three projectile damage and spread, and the two
	  cooldowns.

	Uses:
	  Server.Game.Combat.ProjectileService for the rocket and the three
	  bolts.
	  Server.Game.Combat.HitDetection for the blast radius when the
	  rocket lands, which ProjectileService calls on its behalf.
	  Server.Game.Combat.DamageService for the damage, again through
	  ProjectileService.
	  ServerStorage.Assets.Projectiles for the rocket and bolt models.

	Called by:
	  Server.Game.Combat.CombatService, through WeaponBase.

	The explosion must not damage the player who fired it, or the player
	can rocket jump themselves to death, but it should still damage
	enemies right next to them. Pass the owner through to
	ProjectileService so the blast filter excludes the firer.

	If the rocket ends up applying knockback, that fights with the
	movement framework's velocity handling. Look at
	ReplicatedStorage.Modules.Shared.HelperFunctions clearVelocity and
	dashVelocity before adding a second system that pushes characters
	around, otherwise a rocket landing mid dash will do something
	unpredictable.
]]

local WeaponBase = require(script.Parent.WeaponBase)
local ProjectileService = require(script.Parent.Parent.ProjectileService)

local RPG = setmetatable({}, { __index = WeaponBase })
RPG.__index = RPG

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

RPG.Settings = {
	-- Where the rocket leaves, relative to the root: from the tube on
	-- the right shoulder.
	MuzzleOffset = Vector3.new(1, 1, -2),
}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function SpecFor(self, Context, Attack)
	local Origin = Context.Root.CFrame:PointToWorldSpace(RPG.Settings.MuzzleOffset)
	local Direction = Context.AimPosition - Origin
	if Direction.Magnitude < 0.01 then
		Direction = Context.AimDirection
	end
	local P = Attack.Projectile
	return {
		Owner = Context.Player,
		Side = "Enemies",
		Origin = Origin,
		Direction = Direction.Unit,
		Speed = P.Speed,
		Gravity = P.Gravity,
		Lifetime = P.Lifetime,
		ModelName = P.ModelName,
		Damage = Attack.Damage,
		Pierce = P.Pierce,
		Radius = P.Radius,
		Explosion = P.Explosion,
		Knockback = Attack.Knockback,
		SelfDamage = Attack.SelfDamage,
		RocketJump = Attack.RocketJump,
		Source = self.Name .. " " .. Attack.Name,
		StatusEffect = Attack.StatusEffect,
		CritMultiplier = Attack.CritMultiplier,
		HitSound = Attack.HitSound,
	}
end

----------------------------------------------------------------------
-- ATTACKS
----------------------------------------------------------------------

-- The rocket. The owner is passed through so the blast never damages
-- them unless SelfDamage says so, and so a rocket at your feet throws
-- you when RocketJump is on.
function RPG:OnMB1(Context, Attack)
	ProjectileService.Fire(SpecFor(self, Context, Attack))
end

-- The barrage: Projectile.Count rockets in an even fan over
-- Projectile.Spread degrees, each exploding like the MB1 rocket.
function RPG:OnMB2(Context, Attack)
	local P = Attack.Projectile
	local Base = SpecFor(self, Context, Attack)
	local Count = P.Count or 1
	local Spread = P.Spread or 0
	for Index = 1, Count do
		local Spec = table.clone(Base)
		if Count > 1 then
			local Yaw = math.rad(-Spread / 2 + Spread * (Index - 1) / (Count - 1))
			Spec.Direction = (CFrame.lookAt(Vector3.zero, Base.Direction) * CFrame.Angles(0, Yaw, 0)).LookVector
		end
		ProjectileService.Fire(Spec)
	end
end

return RPG
