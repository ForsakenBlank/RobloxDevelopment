--[[
	Sword

	The close range crowd control weapon. It never moves the player, so
	it can be used in the middle of any movement without surprises.

	MB1 is Cleave, a wide arc in front of the player towards the cursor.
	It hits everything in the arc, shoves it back so a crowd cannot
	swarm, and parries: any enemy projectile inside the arc is knocked
	back at whoever threw it, as the player's own, hitting twice as
	hard. Held down it keeps swinging.

	MB2 is Crescent Cannon, a high powered blade of energy fired from a
	big swing. It is huge, fast, passes through every enemy in its path,
	hits each one hard, throws them back and stuns them for a moment, so
	it clears a corridor or a line of enemies in one go.

	These are SwordMB1 and SwordMB2 from the function plan.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Weapons.WeaponBase, which has already done the
	  cooldown check, started the cooldown and told the other clients to
	  show the swing before either attack function runs.

	Reads:
	  The Sword entry in Game.Data.WeaponData for the damage, reach, arc,
	  knockback, the Parry table and the crescent's Projectile table.

	Uses:
	  Server.Game.Combat.HitDetection with a sphere around the player,
	  then an angle check for the arc.
	  Server.Game.Combat.ProjectileService.Deflect for the parry, and
	  ProjectileService.Fire for the crescent (its Pierce and wide
	  Radius let it pass through a whole line, and its StatusEffect is
	  the stun).
	  Server.Game.Combat.DamageService for all the damage and the shove.

	Called by:
	  Server.Game.Combat.CombatService, through WeaponBase.

	The aim direction comes from the client's cursor and is only used
	flat (no up or down), so a modified client can at most pick which
	way the arc faces, never how far it reaches.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local WeaponBase = require(script.Parent.WeaponBase)
local HitDetection = require(script.Parent.Parent.HitDetection)
local DamageService = require(script.Parent.Parent.DamageService)
local ProjectileService = require(script.Parent.Parent.ProjectileService)

local Sword = setmetatable({}, { __index = WeaponBase })
Sword.Settings = {
	-- Targets closer than this are hit whatever the angle, so an enemy
	-- stood inside the player is never missed.
	PointBlank = 3.5,
	-- The arc is checked from this far behind the root, so enemies right
	-- at the player's sides are still inside it.
	ArcBackOffset = 1.5,
	-- Studs above and in front of the root the crescent leaves from.
	CrescentHeight = 0.5,
	CrescentForward = 2,
}
Sword.__index = Sword

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- The flat direction the slash faces: the cursor if it is anywhere
-- sensible, otherwise the way the character is facing.
local function FlatAim(Context): Vector3
	local Flat = Context.AimDirection * Vector3.new(1, 0, 1)
	if Flat.Magnitude < 0.1 then
		Flat = Context.Facing.LookVector * Vector3.new(1, 0, 1)
	end
	return Flat.Unit
end

----------------------------------------------------------------------
-- MB1: CLEAVE
----------------------------------------------------------------------

function Sword:OnMB1(Context, Attack)
	local Settings = Sword.Settings
	local Root = Context.Root
	if not Root.Parent then
		return
	end
	local Origin = Root.Position
	local Forward = FlatAim(Context)
	local HalfArc = math.cos(math.rad((Attack.Arc or 160) / 2))
	local ArcFrom = Origin - Forward * Settings.ArcBackOffset

	local Hits = HitDetection.Sphere(Origin, Attack.Range, {
		Side = "Enemies",
		MaxTargets = Attack.MaxTargets,
		Origin = Origin,
	})

	local Landed = 0
	for _, Record in ipairs(Hits) do
		local Offset = (Record.Position - ArcFrom) * Vector3.new(1, 0, 1)
		local InArc = Record.Distance <= Settings.PointBlank
			or (Offset.Magnitude > 0.01 and Offset.Unit:Dot(Forward) >= HalfArc)
		if InArc then
			Landed += 1
			DamageService.ApplyDamage(Record.Model, Attack.Damage, Context.Player, {
				Source = self.Name .. " " .. Attack.Name,
				Knockback = Attack.Knockback,
				From = Origin,
				HitSound = Attack.HitSound,
			})
		end
	end

	-- The parry: projectiles in the same arc go back where they came
	-- from.
	local Parry = Attack.Parry
	if Parry and Parry.Enabled then
		local Count = ProjectileService.Deflect({
			Owner = Context.Player,
			Origin = Origin,
			Radius = Parry.Range,
			Direction = Forward,
			Arc = Attack.Arc,
			DamageMultiplier = Parry.DamageMultiplier,
			SpeedMultiplier = Parry.SpeedMultiplier,
		})
		if Count > 0 then
			CombatFX.Broadcast("Parry", Context.Character, { Position = Origin + Forward * 3, Count = Count })
		end
	end
end

----------------------------------------------------------------------
-- MB2: CRESCENT CANNON
----------------------------------------------------------------------

function Sword:OnMB2(Context, Attack)
	local Root = Context.Root
	if not Root.Parent then
		return
	end
	-- Fired from chest height just in front, towards the cursor.
	local Origin = Root.Position + Vector3.new(0, Sword.Settings.CrescentHeight, 0) + Root.CFrame.LookVector * Sword.Settings.CrescentForward
	local Direction = Context.AimPosition - Origin
	if Direction.Magnitude < 0.01 then
		Direction = Context.AimDirection
	end
	local P = Attack.Projectile
	ProjectileService.Fire({
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
		Knockback = Attack.Knockback,
		Source = self.Name .. " " .. Attack.Name,
		StatusEffect = Attack.StatusEffect,
		HitSound = Attack.HitSound,
	})
end

return Sword
