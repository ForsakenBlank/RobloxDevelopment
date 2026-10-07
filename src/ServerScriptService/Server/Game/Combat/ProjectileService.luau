--[[
	ProjectileService

	Handles everything that flies. Pistol bullets, the RPG rockets, the
	Shotgun pellets, Bob's rock, the Necromancer's bolts and the boss's
	long range pattern all come through here.

	A projectile is created with an owner, a start position, a direction,
	a speed, a lifetime, a damage value and whether it explodes on
	impact. This module moves it, checks what it hits, and cleans it up
	when it hits something or runs out of lifetime.

	Movement is done by raycasting forward each step rather than by
	giving a part velocity and waiting for a Touched event, because a
	fast part will tunnel straight through a wall and Touched misses it.

	Projectiles are simulated on the server so damage cannot be faked,
	and drawn on every client (CombatFX's Projectile effect) so they move
	smoothly.

	Three extras on top of that:
	  Headshots: a projectile with a CritMultiplier that hits an enemy's
	  Head part does that much more damage.
	  Deflecting: the Sword's parry calls Deflect, which turns every
	  enemy projectile in an area round, makes it the player's, and
	  sends it back at whoever fired it.
	  Homing: a projectile with a Homing table curves after its target
	  for a while. The clients curve it the same way, and are sent its
	  true path every HomingSyncRate seconds so they never drift.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Combat.Weapons.Pistol for both its attacks, RPG for its
	  rockets, and Shotgun for its pellets.
	  Server.Game.Combat.Weapons.Sword for Deflect.
	  Server.Game.Enemies.EnemyAI for every enemy's ranged attack.
	  Server.Game.Enemies.Types.Bomber for Explode.
	  Server.Game.Shop.ShopItems for the thrown Molotov.

	Uses:
	  Server.Game.Combat.HitDetection for anything with a blast radius,
	  so the RPG explosion and the Molotov use the same area check as a
	  sword area attack.
	  Server.Game.Combat.DamageService to apply the damage on impact.
	  Server.Game.Effects.StatusEffectService for the rocket's stagger.

	Tells the clients:
	  Game.Shared.CombatFX Projectile, ProjectileRedirect and
	  ProjectileEnd, so every client draws the same projectile moving
	  smoothly, and Explosion for a blast.

	The owner matters. A projectile must not hit whoever fired it, and an
	enemy projectile must not hit other enemies, or Bob will kill the
	Noobs standing in front of him. The Side option decides who it can
	hit and the owner is always excluded.

	Gates are solid, so a projectile has to stop on a closed gate rather
	than passing through it into the next room. Since gates are in
	workspace.MainGameObj.Gates and are collidable when locked, a normal
	raycast against the map handles this on its own.

	Cleanup has to be guaranteed. A projectile that somehow never hits
	anything still has to be removed on its lifetime.
]]

local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local StatFormulas = require(ReplicatedStorage.Modules.Game.Shared.StatFormulas)
local HitDetection = require(script.Parent.HitDetection)
local DamageService = require(script.Parent.DamageService)
local Signal = require(ReplicatedStorage.Modules.Game.Shared.Signal)

local ProjectileService = {}

-- fired with (Owner, Count) when a deflect catches at least one projectile, RunManager counts these as Parries
ProjectileService.Deflected = Signal.new()

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

ProjectileService.Settings = {
	RuntimeFolder = "Runtime",
	ProjectilesFolder = "Projectiles",
	-- Hard cap on live projectiles. Past this the oldest is removed.
	MaxAlive = 250,
	-- Show a spark where a projectile lands.
	HitSparks = true,
	-- A fallback model when the named one is missing.
	FallbackModel = "Bullet",
	-- true draws projectiles on each client (smooth, with trails, see
	-- CombatFX.Settings.ProjectileVisuals) and the server only
	-- simulates the hits. false clones the model from
	-- ServerStorage.Assets.Projectiles and moves it on the server, which
	-- replicates in steps and looks choppy.
	ClientVisuals = true,
	-- Hit radius used when a spec gives none. Bigger than 0 means near
	-- misses still land.
	DefaultRadius = 0.5,
	-- A deflected projectile flies for at least this long, so one
	-- caught right at the end of its life still gets back.
	DeflectMinLifetime = 1.5,
	-- Part name that counts as a headshot.
	HeadPart = "Head",
	-- Seconds between the true path of a homing projectile being sent
	-- to the clients.
	HomingSyncRate = 0.25,
}

local NextId = 0

local Alive: { any } = {}
local Folder: Folder? = nil
local Connection: RBXScriptConnection? = nil

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function GetFolder(): Folder
	if Folder and Folder.Parent then
		return Folder
	end
	local Settings = ProjectileService.Settings
	local Runtime = workspace:FindFirstChild(Settings.RuntimeFolder)
	if not Runtime then
		Runtime = Instance.new("Folder")
		Runtime.Name = Settings.RuntimeFolder
		Runtime.Parent = workspace
	end
	local Found = Runtime:FindFirstChild(Settings.ProjectilesFolder)
	if not Found then
		Found = Instance.new("Folder")
		Found.Name = Settings.ProjectilesFolder
		Found.Parent = Runtime
	end
	Folder = Found
	return Found
end

local function OwnerModel(Owner: any): Model?
	if typeof(Owner) == "Instance" then
		if Owner:IsA("Player") then
			return Owner.Character
		elseif Owner:IsA("Model") then
			return Owner
		end
	elseif type(Owner) == "table" and Owner.Model then
		return Owner.Model
	end
	return nil
end

local function Remove(Projectile)
	local Index = table.find(Alive, Projectile)
	if Index then
		table.remove(Alive, Index)
	end
	if Projectile.Model then
		Projectile.Model:Destroy()
		Projectile.Model = nil
	end
	-- Tell the clients to stop drawing it, where it actually ended.
	if Projectile.Id then
		CombatFX.Broadcast("ProjectileEnd", nil, { Id = Projectile.Id, Position = Projectile.Position })
		Projectile.Id = nil
	end
end

-- The damage for a direct hit, with the headshot bonus if it hit the
-- head. Returns the damage and whether it was a headshot.
local function DirectDamage(Spec, HitPart: Instance?): (number, boolean)
	local Crit = Spec.CritMultiplier ~= nil
		and HitPart ~= nil
		and HitPart.Name == ProjectileService.Settings.HeadPart
	return Spec.Damage * (Crit and Spec.CritMultiplier or 1), Crit
end

----------------------------------------------------------------------
-- EXPLOSIONS
----------------------------------------------------------------------

-- Blows up at Position with the spec's Explosion table: falloff damage
-- to everything on Spec.Side in the radius, the stagger if it has one,
-- the blast on every client, and the rocket jump for the owner. Public
-- so the Bomber can use the same blast.
--   Spec needs: Explosion { Radius, Falloff, Stun }, Damage, Side,
--   Owner, Knockback, Source. Optional: SelfDamage, RocketJump,
--   StatusEffect, HitSound, Exclude (models to leave out).
function ProjectileService.Explode(Spec, Position: Vector3, OwnerModelOverride: Model?)
	local Explosion = Spec.Explosion
	local Owner = OwnerModelOverride or OwnerModel(Spec.Owner)
	local Exclude = { Owner }
	for _, Model in ipairs(Spec.Exclude or {}) do
		table.insert(Exclude, Model)
	end
	local Hits = HitDetection.Sphere(Position, Explosion.Radius, {
		Side = Spec.Side,
		Exclude = Exclude,
		Origin = Position,
	})
	local StatusEffectService = nil
	for _, Hit in ipairs(Hits) do
		local Damage = StatFormulas.FalloffDamage(Spec.Damage, Hit.Distance, Explosion.Radius, Explosion.Falloff)
		local _, Killed = DamageService.ApplyDamage(Hit.Model, Damage, Spec.Owner, {
			Source = Spec.Source,
			DamageType = Spec.DamageType,
			Knockback = Spec.Knockback,
			From = Position,
			StatusEffect = Spec.StatusEffect,
			HitSound = Spec.HitSound,
		})
		-- The stagger, which is what makes rockets crowd control.
		if not Killed and (Explosion.Stun or 0) > 0 and Spec.Side ~= "Players" then
			StatusEffectService = StatusEffectService or require(script.Parent.Parent.Effects.StatusEffectService)
			StatusEffectService.Apply(Hit.Model, "Stun", Explosion.Stun, nil, Spec.Owner)
		end
	end

	-- The player can be caught in their own explosion.
	local OwnerRoot = Owner and Owner:FindFirstChild("HumanoidRootPart")
	local OwnerInside = OwnerRoot ~= nil and (OwnerRoot.Position - Position).Magnitude <= Explosion.Radius
	if Spec.SelfDamage and Spec.SelfDamage > 0 and OwnerInside then
		DamageService.ApplyDamage(Owner, Spec.Damage * Spec.SelfDamage, nil, {
			Source = tostring(Spec.Source) .. " (self)",
			Knockback = Spec.Knockback,
			From = Position,
		})
	end

	-- Rocket jumping: the owner's own client throws them, the anti
	-- cheat is told to expect it.
	local LaunchOwner = nil
	if Spec.RocketJump and OwnerInside and typeof(Spec.Owner) == "Instance" and Spec.Owner:IsA("Player") then
		LaunchOwner = Spec.Owner.UserId
		local AntiCheat = require(game:GetService("ServerScriptService").Server.Modules.AntiCheat)
		AntiCheat.GrantException(Spec.Owner, 1.5)
	end
	CombatFX.Broadcast("Explosion", nil, {
		Position = Position,
		Radius = Explosion.Radius,
		LaunchOwner = LaunchOwner,
		Hostile = Spec.Side == "Players",
	})
end

-- What a projectile does when it lands on something, or runs out.
local function Impact(Projectile, Position: Vector3, HitModel: Model?, HitPart: Instance?)
	local Spec = Projectile.Spec

	if Spec.Explosion then
		ProjectileService.Explode(Spec, Position, Projectile.OwnerModel)
	elseif HitModel then
		local Damage, Crit = DirectDamage(Spec, HitPart)
		DamageService.ApplyDamage(HitModel, Damage, Spec.Owner, {
			Source = Spec.Source,
			DamageType = Spec.DamageType,
			Knockback = Spec.Knockback,
			From = Projectile.Position,
			StatusEffect = Spec.StatusEffect,
			HitSound = Spec.HitSound,
			Crit = Crit,
		})
		if ProjectileService.Settings.HitSparks then
			CombatFX.Broadcast("Hit", nil, { Position = Position, Crit = Crit })
		end
	elseif ProjectileService.Settings.HitSparks then
		CombatFX.Broadcast("Hit", nil, { Position = Position, Colour = Color3.fromRGB(200, 200, 200), Small = true })
	end

	if Spec.OnImpact then
		Spec.OnImpact(Position, HitModel)
	end
end

----------------------------------------------------------------------
-- FIRE
----------------------------------------------------------------------

-- Launches one projectile. Spec:
--   Owner        the Player or enemy object firing it
--   Side         "Enemies" or "Players", who it can hit
--   Origin       start position
--   Direction    unit vector
--   Speed        studs per second
--   Gravity      studs per second squared pulling down, 0 for none
--   Lifetime     seconds before it is removed
--   ModelName    look from CombatFX.Settings.ProjectileVisuals
--   Damage       base damage on a direct hit, or at the explosion
--                centre
--   Radius       hit radius in studs against targets. The map is
--                always checked with a thin ray
--   Pierce       enemies it passes through before stopping
--   Explosion    nil or { Radius, Falloff, Stun }
--   Knockback    studs per second on hit
--   CritMultiplier  damage multiplier for a headshot, nil for none
--   SelfDamage   fraction of Damage the owner takes inside their own
--                explosion
--   RocketJump   true throws the owner away from their own explosion
--   Source       label for the damage log
--   HitSound     sound the attacker hears on a hit
--   StatusEffect nil or { Name, Duration } applied on hit
--   OnImpact     optional function(Position, HitModel)
--   Homing       optional { Target (a BasePart), TurnRate (radians a
--                second), Duration (seconds it keeps turning) }
function ProjectileService.Fire(Spec: { [string]: any })
	if #Alive >= ProjectileService.Settings.MaxAlive then
		Remove(Alive[1])
	end

	local Model = nil
	local Id = nil
	if ProjectileService.Settings.ClientVisuals then
		NextId += 1
		Id = NextId
		CombatFX.Broadcast("Projectile", nil, {
			Id = Id,
			Origin = Spec.Origin,
			Velocity = Spec.Direction.Unit * Spec.Speed,
			Gravity = Spec.Gravity or 0,
			Lifetime = Spec.Lifetime or 3,
			Visual = Spec.ModelName,
			Homing = Spec.Homing and {
				Target = Spec.Homing.Target,
				TurnRate = Spec.Homing.TurnRate,
				Duration = Spec.Homing.Duration,
			} or nil,
		})
	else
		local Template = ServerStorage.Assets.Projectiles:FindFirstChild(Spec.ModelName or "")
			or ServerStorage.Assets.Projectiles:FindFirstChild(ProjectileService.Settings.FallbackModel)
		Model = Template and Template:Clone() or nil
	end
	if Model then
		for _, Part in ipairs(Model:GetDescendants()) do
			if Part:IsA("BasePart") then
				Part.Anchored = true
				Part.CanCollide = false
				Part.CanQuery = false
				Part.CanTouch = false
			end
		end
		Model:PivotTo(CFrame.lookAt(Spec.Origin, Spec.Origin + Spec.Direction))
		Model.Parent = GetFolder()
	end

	local Projectile = {
		Spec = Spec,
		Model = Model,
		Id = Id,
		Radius = Spec.Radius or ProjectileService.Settings.DefaultRadius,
		FirstStep = true,
		Position = Spec.Origin,
		Velocity = Spec.Direction.Unit * Spec.Speed,
		Gravity = Spec.Gravity or 0,
		DiesAt = os.clock() + (Spec.Lifetime or 3),
		PierceLeft = Spec.Pierce or 0,
		OwnerModel = OwnerModel(Spec.Owner),
		Hit = {},
		Born = os.clock(),
		NextSync = os.clock() + ProjectileService.Settings.HomingSyncRate,
	}
	table.insert(Alive, Projectile)
	return Projectile
end

-- Turns a homing projectile's velocity towards its target by at most
-- TurnRate radians a second. Shared maths with the client copy.
function ProjectileService.SteerTowards(Velocity: Vector3, Position: Vector3, TargetPosition: Vector3, TurnRate: number, DeltaTime: number): Vector3
	local Speed = Velocity.Magnitude
	local Wanted = TargetPosition - Position
	if Speed < 0.01 or Wanted.Magnitude < 0.01 then
		return Velocity
	end
	local Current = Velocity.Unit
	Wanted = Wanted.Unit
	local Angle = math.acos(math.clamp(Current:Dot(Wanted), -1, 1))
	local MaxTurn = TurnRate * DeltaTime
	if Angle <= MaxTurn then
		return Wanted * Speed
	end
	-- Rotate part of the way, around the axis between the two.
	local Axis = Current:Cross(Wanted)
	if Axis.Magnitude < 1e-4 then
		return Velocity
	end
	return (CFrame.fromAxisAngle(Axis.Unit, MaxTurn) * Current) * Speed
end

-- Fires Count projectiles spread over a cone of Spread degrees, all
-- sharing the same Spec. Direction is the centre of the cone.
function ProjectileService.FireSpread(Spec: { [string]: any }, Count: number, Spread: number)
	local Base = Spec.Direction.Unit
	local Fired = {}
	for Index = 1, Count do
		local Direction = Base
		if Spread > 0 and Count > 1 then
			-- Random point inside the cone.
			local Yaw = (math.random() - 0.5) * math.rad(Spread)
			local Pitch = (math.random() - 0.5) * math.rad(Spread)
			Direction = (CFrame.lookAt(Vector3.zero, Base) * CFrame.Angles(Pitch, Yaw, 0)).LookVector
		end
		local Copy = table.clone(Spec)
		Copy.Direction = Direction
		table.insert(Fired, ProjectileService.Fire(Copy))
	end
	return Fired
end

----------------------------------------------------------------------
-- DEFLECT
----------------------------------------------------------------------

-- Turns enemy projectiles round and makes them the player's. Options:
--   Owner             the Player doing the deflecting
--   Origin            centre of the area
--   Radius            studs out from Origin a projectile is caught
--   Direction, Arc    optional: only projectiles inside a cone of Arc
--                     degrees round the flat Direction are caught
--   DamageMultiplier  on the projectile's damage
--   SpeedMultiplier   on its speed
-- Each one flies back at the enemy that fired it if that enemy is still
-- alive, otherwise along Direction (or straight back). Returns how many
-- were deflected.
function ProjectileService.Deflect(Options): number
	local Owner = Options.Owner
	local Origin: Vector3 = Options.Origin
	local Radius = Options.Radius or 10
	local Direction: Vector3? = Options.Direction
	local MinDot = Options.Arc and math.cos(math.rad(Options.Arc / 2)) or -1
	local Count = 0

	for _, Projectile in ipairs(Alive) do
		local Spec = Projectile.Spec
		-- Only enemy projectiles, the ones aimed at players.
		if Spec.Side ~= "Players" then
			continue
		end
		local Offset = Projectile.Position - Origin
		if Offset.Magnitude > Radius then
			continue
		end
		if Direction then
			local Flat = Offset * Vector3.new(1, 0, 1)
			if Flat.Magnitude > 2 and Flat.Unit:Dot(Direction) < MinDot then
				continue
			end
		end

		-- Where it goes: back at the enemy that fired it if it is alive.
		local Shooter = Spec.Owner
		local Target: Vector3? = nil
		if type(Shooter) == "table" and Shooter.Root and not Shooter.IsDead and Shooter.Root.Parent then
			Target = Shooter.Root.Position
		end
		local Speed = Projectile.Velocity.Magnitude * (Options.SpeedMultiplier or 1)
		local NewDirection
		if Target then
			NewDirection = (Target - Projectile.Position)
		elseif Direction then
			NewDirection = Direction
		else
			NewDirection = -Projectile.Velocity
		end
		if NewDirection.Magnitude < 0.01 then
			NewDirection = -Projectile.Velocity
		end
		NewDirection = NewDirection.Unit

		-- It is the player's now.
		local NewSpec = table.clone(Spec)
		NewSpec.Owner = Owner
		NewSpec.Side = "Enemies"
		NewSpec.Damage = Spec.Damage * (Options.DamageMultiplier or 1)
		NewSpec.Source = "Parry"
		NewSpec.HitSound = "SwordHit"
		NewSpec.StatusEffect = nil
		NewSpec.Homing = nil
		-- Straight and flat out, so it reliably gets back.
		NewSpec.Gravity = 0
		Projectile.Spec = NewSpec
		Projectile.OwnerModel = OwnerModel(Owner)
		Projectile.Velocity = NewDirection * Speed
		Projectile.Gravity = 0
		Projectile.Hit = {}
		Projectile.FirstStep = true
		Projectile.PierceLeft = 0
		Projectile.DiesAt = math.max(Projectile.DiesAt, os.clock() + ProjectileService.Settings.DeflectMinLifetime)
		Count += 1

		if Projectile.Id then
			CombatFX.Broadcast("ProjectileRedirect", nil, {
				Id = Projectile.Id,
				Origin = Projectile.Position,
				Velocity = Projectile.Velocity,
				Gravity = 0,
				Lifetime = Projectile.DiesAt - os.clock(),
			})
		end
	end
	if Count > 0 then
		ProjectileService.Deflected:Fire(Owner, Count)
	end
	return Count
end

----------------------------------------------------------------------
-- STEP
----------------------------------------------------------------------

-- Advances every projectile by DeltaTime. Public so it can be driven
-- by hand in a test, Init connects it to Heartbeat.
function ProjectileService.Step(DeltaTime: number)
	local Now = os.clock()
	if #Alive == 0 then
		return
	end

	-- Built once per step and shared by every projectile. The map ray
	-- ignores every character, enemy and effect folder, so it only
	-- stops on walls and floors. The target sweep only looks at the
	-- side's targets.
	local MapParams = HitDetection.MapRaycastParams()
	local TargetParams = {}
	for _, Side in ipairs({ "Enemies", "Players" }) do
		local Params = RaycastParams.new()
		Params.FilterType = Enum.RaycastFilterType.Include
		local Targets = HitDetection.GetTargets(Side)
		Params.FilterDescendantsInstances = Targets
		TargetParams[Side] = { Params = Params, Targets = Targets }
	end

	for Index = #Alive, 1, -1 do
		local Projectile = Alive[Index]
		if not Projectile then
			continue
		end
		local Spec = Projectile.Spec

		if Now >= Projectile.DiesAt then
			Impact(Projectile, Projectile.Position, nil, nil)
			Remove(Projectile)
			continue
		end

		if Projectile.Gravity > 0 then
			Projectile.Velocity -= Vector3.new(0, Projectile.Gravity * DeltaTime, 0)
		end
		-- Homing: curve after the target while it lasts and still
		-- exists, and keep every client's copy on the same path.
		local Homing = Spec.Homing
		if Homing and Now - Projectile.Born < (Homing.Duration or 3) then
			local Target = Homing.Target
			if typeof(Target) == "Instance" and Target.Parent then
				Projectile.Velocity = ProjectileService.SteerTowards(Projectile.Velocity, Projectile.Position, Target.Position, Homing.TurnRate or 2, DeltaTime)
			end
			if Now >= Projectile.NextSync and Projectile.Id then
				Projectile.NextSync = Now + ProjectileService.Settings.HomingSyncRate
				CombatFX.Broadcast("ProjectileRedirect", nil, {
					Id = Projectile.Id,
					Origin = Projectile.Position,
					Velocity = Projectile.Velocity,
					Gravity = Projectile.Gravity,
					Lifetime = Projectile.DiesAt - Now,
					KeepColour = true,
				})
			end
		end
		local Move = Projectile.Velocity * DeltaTime

		-- Two checks. A thin ray against the map, so a bullet only stops
		-- on a wall it really touches, and a sphere of the projectile's
		-- Radius swept against the targets, so a near miss still lands.
		-- Whichever is closer wins.
		local Side = TargetParams[Spec.Side or "Enemies"]
		-- A piercing projectile leaves out what it already went
		-- through, and a deflected one leaves out the player who sent
		-- it back. A sweep only reports the first thing it touches.
		if next(Projectile.Hit) ~= nil or (Projectile.OwnerModel and table.find(Side.Targets, Projectile.OwnerModel)) then
			local Remaining = {}
			for _, Model in ipairs(Side.Targets) do
				if not Projectile.Hit[Model] and Model ~= Projectile.OwnerModel then
					table.insert(Remaining, Model)
				end
			end
			local Params = RaycastParams.new()
			Params.FilterType = Enum.RaycastFilterType.Include
			Params.FilterDescendantsInstances = Remaining
			Side = { Params = Params, Targets = Remaining }
		end
		local MapResult = workspace:Raycast(Projectile.Position, Move, MapParams)
		local TargetResult = nil
		if #Side.Targets > 0 then
			if Projectile.FirstStep and Projectile.Radius > 0 then
				-- A sweep cannot see a target it starts inside, which is
				-- what a point blank shot is, so check the start too.
				local Overlap = OverlapParams.new()
				Overlap.FilterType = Enum.RaycastFilterType.Include
				Overlap.FilterDescendantsInstances = Side.Targets
				local Parts = workspace:GetPartBoundsInRadius(Projectile.Position, Projectile.Radius, Overlap)
				if #Parts > 0 then
					TargetResult = { Instance = Parts[1], Position = Projectile.Position, Distance = 0 }
				end
			end
			if not TargetResult then
				if Projectile.Radius > 0 then
					TargetResult = workspace:Spherecast(Projectile.Position, Projectile.Radius, Move, Side.Params)
				else
					TargetResult = workspace:Raycast(Projectile.Position, Move, Side.Params)
				end
				-- A thin ray through the middle as well, so a shot that
				-- passes through a head counts as a headshot even when
				-- the wide sweep touched the shoulder first.
				if TargetResult and Spec.CritMultiplier and TargetResult.Instance.Name ~= ProjectileService.Settings.HeadPart then
					local Thin = workspace:Raycast(Projectile.Position, Move, Side.Params)
					if Thin and Thin.Instance.Name == ProjectileService.Settings.HeadPart then
						TargetResult = Thin
					end
				end
			end
		end
		Projectile.FirstStep = false

		local HitModel = nil
		if TargetResult then
			for _, Target in ipairs(Side.Targets) do
				if TargetResult.Instance == Target or TargetResult.Instance:IsDescendantOf(Target) then
					HitModel = Target
					break
				end
			end
			if HitModel and (HitModel == Projectile.OwnerModel or Projectile.Hit[HitModel]) then
				HitModel = nil
			end
			if HitModel and MapResult and MapResult.Distance < TargetResult.Distance then
				HitModel = nil
			end
		end

		local Result = HitModel and TargetResult or MapResult
		if Result then
			if HitModel and not Spec.Explosion and Projectile.PierceLeft > 0 then
				-- Pass through: damage it and keep going.
				Projectile.PierceLeft -= 1
				Projectile.Hit[HitModel] = true
				local Damage, Crit = DirectDamage(Spec, Result.Instance)
				DamageService.ApplyDamage(HitModel, Damage, Spec.Owner, {
					Source = Spec.Source,
					DamageType = Spec.DamageType,
					Knockback = Spec.Knockback,
					From = Projectile.Position,
					StatusEffect = Spec.StatusEffect,
					HitSound = Spec.HitSound,
					Crit = Crit,
				})
				if ProjectileService.Settings.HitSparks then
					CombatFX.Broadcast("Hit", nil, { Position = Result.Position, Crit = Crit })
				end
				-- Carry on along its own line. With a wide Radius the
				-- contact point can be off to one side, and restarting
				-- from there would make the projectile drift.
				Projectile.Position += Move.Unit * math.min(Move.Magnitude, (Result.Distance or 0) + 0.5)
			else
				Projectile.Position = Result.Position
				Impact(Projectile, Result.Position, HitModel, HitModel and Result.Instance or nil)
				Remove(Projectile)
				continue
			end
		else
			Projectile.Position += Move
		end

		if Projectile.Model then
			Projectile.Model:PivotTo(CFrame.lookAt(Projectile.Position, Projectile.Position + Projectile.Velocity))
		end
	end
end

function ProjectileService.ClearAll()
	for _, Projectile in ipairs(table.clone(Alive)) do
		Remove(Projectile)
	end
end

function ProjectileService.CountAlive(): number
	return #Alive
end

function ProjectileService.Init()
	if Connection then
		return
	end
	GetFolder()
	Connection = RunService.Heartbeat:Connect(ProjectileService.Step)
end

return ProjectileService
