--[[
	Pistol

	The ranged single target weapon. MB1 fires one fast bullet towards
	the player's cursor and damages the first enemy it hits, and can be
	held down. MB2 fans the hammer: six bullets in quick succession, each
	with a little random spread, for a burst of damage on one target at
	mid range.

	These are PistolMB1 and PistolMB2 from the function plan. Both use
	the cursor position, which the client has to send since the server
	does not know where the mouse is.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Weapons.WeaponBase.

	Reads:
	  The Pistol entry in Game.Data.WeaponData for damage, range, bullet
	  count, spread and the cooldowns.

	Uses:
	  Server.Game.Combat.ProjectileService for both attacks, since both
	  fire bullets. MB2 asks it for several at once with the spread
	  applied.
	  Server.Game.Combat.DamageService, but through ProjectileService
	  when a bullet lands rather than directly.

	Called by:
	  Server.Game.Combat.CombatService, which has already range checked
	  the cursor position that came up from
	  ClientGame.Controllers.CombatInput.

	The cursor position is client supplied so it cannot be trusted. By
	the time it gets here CombatService has clamped it, and this module
	fires from the character towards that point rather than from the
	point itself, so a bad position can only ever change the direction
	and never the origin.

	The spread on MB2 is worked out on the server in ProjectileService,
	not sent up by the client, or a client could send zero spread and
	turn it into a burst of perfectly accurate shots.
]]

local WeaponBase = require(script.Parent.WeaponBase)
local ProjectileService = require(script.Parent.Parent.ProjectileService)

local Pistol = setmetatable({}, { __index = WeaponBase })
Pistol.__index = Pistol

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

Pistol.Settings = {
	-- Where the bullet starts, relative to the root: a little forward
	-- and to the right so it leaves from around the gun rather than
	-- the chest.
	MuzzleOffset = Vector3.new(1, 0.5, -1.5),
}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Builds the projectile spec both attacks share.
local function SpecFor(self, Context, Attack)
	local Origin = Context.Root.CFrame:PointToWorldSpace(Pistol.Settings.MuzzleOffset)
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
		Source = self.Name .. " " .. Attack.Name,
		StatusEffect = Attack.StatusEffect,
		CritMultiplier = Attack.CritMultiplier,
		HitSound = Attack.HitSound,
	}
end

----------------------------------------------------------------------
-- ATTACKS
----------------------------------------------------------------------

-- One accurate bullet at the cursor.
function Pistol:OnMB1(Context, Attack)
	ProjectileService.Fire(SpecFor(self, Context, Attack))
end

-- Fan the hammer: Shots bullets one after another, each aimed at the
-- cursor from wherever the player is at that moment, with random
-- spread. With no Shots it falls back to one spread volley.
function Pistol:OnMB2(Context, Attack)
	local P = Attack.Projectile
	local Shots = Attack.Shots or 1
	if Shots <= 1 then
		ProjectileService.FireSpread(SpecFor(self, Context, Attack), P.Count, P.Spread)
		return
	end
	self.FanThreads = {}
	for Index = 1, Shots do
		local function Shoot()
			if self.Destroyed or not Context.Root.Parent then
				return
			end
			local Spec = SpecFor(self, Context, Attack)
			local Spread = math.rad(P.Spread or 0)
			local Yaw = (math.random() - 0.5) * Spread
			local Pitch = (math.random() - 0.5) * Spread * 0.5
			Spec.Direction = (CFrame.lookAt(Vector3.zero, Spec.Direction) * CFrame.Angles(Pitch, Yaw, 0)).LookVector
			ProjectileService.Fire(Spec)
		end
		if Index == 1 then
			Shoot()
		else
			table.insert(self.FanThreads, task.delay((Index - 1) * (Attack.ShotInterval or 0.07), Shoot))
		end
	end
end

-- A swap part way through the fan stops the rest of the shots.
function Pistol:CancelAttack()
	WeaponBase.CancelAttack(self)
	if self.FanThreads then
		for _, Thread in ipairs(self.FanThreads) do
			pcall(task.cancel, Thread)
		end
		self.FanThreads = nil
	end
end

return Pistol
