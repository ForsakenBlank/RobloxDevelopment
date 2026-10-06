--[[
	Shotgun

	The burst damage weapon. MB1 is the close range blast, a cone of
	pellets that can hit several enemies at once but only works when
	they are close. MB2 is a slug: one hard hit on the first enemy along
	the aim out to a medium range, and its recoil throws the shooter
	backwards, which doubles as a movement tool.

	These are ShotgunMB1 and ShotgunMB2 from the function plan. The split
	between them is deliberate, MB1 for when a group of Noobs gets on top
	of you and MB2 for picking off a Bob from across the room, or for
	blasting yourself out of trouble.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Weapons.WeaponBase.

	Reads:
	  The Shotgun entry in Game.Data.WeaponData for both damage values,
	  the slug range, the pellet count, spread and lifetime on MB1, the
	  recoil launch on MB2 and the cooldowns.

	Uses:
	  Server.Game.Combat.ProjectileService for the MB1 pellets. Each
	  pellet can only hit once, so the damage on a crowd is shared out
	  across it rather than every enemy taking the full blast, which is
	  the per target falloff the design asked for.
	  Server.Game.Combat.HitDetection with a ray for the MB2 slug, since
	  it is meant to be instant.
	  Server.Game.Combat.DamageService for the damage.
	  ServerScriptService.Server.Modules.AntiCheat, told to expect the
	  recoil launch. The launch itself is applied by the shooter's own
	  client in ClientGame.Controllers.CombatInput, since the client owns
	  its character's physics.

	Called by:
	  Server.Game.Combat.CombatService, through WeaponBase.

	The slug is the highest single target damage in the game, so its
	range is strict. The ray stops at Range, so the shotgun cannot turn
	into a sniper and trivialise the Bob and boss fights.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local WeaponBase = require(script.Parent.WeaponBase)
local HitDetection = require(script.Parent.Parent.HitDetection)
local DamageService = require(script.Parent.Parent.DamageService)
local ProjectileService = require(script.Parent.Parent.ProjectileService)

local Shotgun = setmetatable({}, { __index = WeaponBase })
Shotgun.__index = Shotgun

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

Shotgun.Settings = {
	-- Where the shot leaves, relative to the root.
	MuzzleOffset = Vector3.new(1, 0.5, -2),
	-- Seconds the anti cheat allows for the recoil launch.
	LaunchGrace = 1.2,
}

local function Muzzle(Context): Vector3
	return Context.Root.CFrame:PointToWorldSpace(Shotgun.Settings.MuzzleOffset)
end

----------------------------------------------------------------------
-- ATTACKS
----------------------------------------------------------------------

-- The blast: a cone of short lived pellets. Their short lifetime is
-- what keeps it close range, and each pellet can only hit once, so a
-- point blank blast on one enemy lands most of them and the same blast
-- on a group spreads out.
function Shotgun:OnMB1(Context, Attack)
	local P = Attack.Projectile
	local Origin = Muzzle(Context)
	local Direction = Context.AimPosition - Origin
	if Direction.Magnitude < 0.01 then
		Direction = Context.AimDirection
	end
	ProjectileService.FireSpread({
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
	}, P.Count, P.Spread)
end

-- The slug: an instant ray out to Range and no further, so it cannot
-- become a sniper. The shooter's own client throws them backwards for
-- the recoil, the anti cheat is told here.
function Shotgun:OnMB2(Context, Attack)
	local Origin = Muzzle(Context)
	local Direction = Context.AimPosition - Origin
	if Direction.Magnitude < 0.01 then
		Direction = Context.AimDirection
	end
	if (Attack.SelfLaunch or 0) > 0 then
		AntiCheat.GrantException(Context.Player, Shotgun.Settings.LaunchGrace)
	end

	local Hit, EndPoint = HitDetection.Ray(Origin, Direction, Attack.Range, {
		Side = "Enemies",
		Exclude = { Context.Character },
		Radius = Attack.Radius,
	})
	CombatFX.Broadcast("Tracer", nil, { From = Origin, To = EndPoint })
	if Hit then
		-- A slug to the head hits harder.
		local Crit = Attack.CritMultiplier ~= nil and Hit.Part ~= nil and Hit.Part.Name == "Head"
		DamageService.ApplyDamage(Hit.Model, Attack.Damage * (Crit and Attack.CritMultiplier or 1), Context.Player, {
			Source = self.Name .. " " .. Attack.Name,
			Knockback = Attack.Knockback,
			From = Origin,
			StatusEffect = Attack.StatusEffect,
			HitSound = Attack.HitSound,
			Crit = Crit,
		})
		CombatFX.Broadcast("Hit", nil, { Position = Hit.Position })
	else
		CombatFX.Broadcast("Hit", nil, { Position = EndPoint, Colour = Color3.fromRGB(200, 200, 200) })
	end
end

return Shotgun
