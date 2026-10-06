--[[
	EnemyAI

	The shared thinking part of an enemy, kept out of EnemyBase so the
	behaviour can be changed without touching health and damage handling.
	It finds the best player to go for, works out the distance to them,
	and gives the enemy back a decision based on that distance and what
	cooldowns are ready.

	The decision logic from the design is: if the player is close enough
	do a melee attack, else if a ranged attack is off cooldown use that,
	else move towards them. That falls out of picking the highest
	priority attack whose range the target is inside, and moving when
	there is none. Each subclass can run its own version of an attack by
	defining Attack(AttackName, Target), and anything it does not
	override uses the generic attacks here: melee (with an optional lunge
	forward), area slams, projectiles, and charges.

	The players in this game are fast, so the enemies are built not to
	be easy to walk away from:
	  They sprint when their target is far away.
	  Melee attacks can lunge forward the last few studs as they swing.
	  Ranged attacks lead a moving target.
	  Charges dash in a straight line through the target, with a red
	  line on the floor as the tell.
	  Meteor rain drops meteors on and around every player, each shown
	  by a red circle first.
	  Shockwaves spread across the floor in rings that have to be jumped.
	  Homing projectiles curve after their target.
	  Enemies that keep their distance also circle their target, so
	  they are not a stationary turret to line up on.
	In multiplayer each enemy counts how many others are already on a
	player and prefers someone less crowded, so a room spreads over the
	whole team.

	It also owns the update loop timing. Running every enemy on
	RunService.Heartbeat would be wasteful with a room full of them, so
	one loop ticks every enemy on EnemyData.Shared.ThinkRate, and the
	expensive pathfinding only runs on RepathRate and only when the
	target cannot simply be walked at in a straight line.
]]

--[[
	What connects to this

	Drives:
	  Every living enemy in Server.Game.Enemies.EnemyBase.GetAlive(),
	  except ones made with Stationary = true. Nothing has to register
	  with it, an enemy is picked up the tick after it spawns.

	Subclass hooks, all optional, looked up on the enemy object:
	  PickTarget()                 its own target rule, the Boss uses it
	  Attack(AttackName, Target)   its own version of an attack
	  CanUseAttackNow(Name, Dist)  extra rules, the Necromancer's summon
	                               cap for instance
	  DesiredRange(Target, Dist)   studs it wants to keep from the
	                               target
	  OnThink(Target, Dist)        runs every tick before the decision

	Reads:
	  Game.Data.EnemyData for detection range, lose range, speeds, attack
	  ranges and cooldowns of the enemy it is thinking for.
	  Server.Game.Core.PlayerStats to check a player is actually alive
	  before targeting them, since a dead player waiting for the others
	  should not be chased.
	  Server.Game.Rooms.RoomZones so an enemy prefers players in its own
	  area over one who is closer through a wall in the next room.

	Tells the clients (Game.Shared.CombatFX):
	  Enemy_WindUp and Enemy_Swing for every attack, Telegraph_Circle
	  and Telegraph_Line for the area and charge tells, MeteorRain and
	  Shockwave for the boss patterns.

	Must respect:
	  Server.Game.Effects.StatusEffectService. A stunned enemy has
	  IsStunned set by that module, and this skips its update entirely,
	  which is how Stun Slam, rockets and the whirlwind stop an enemy
	  moving.

	Movement note: the players in this game have wall runs, ziplines and
	double jumps from the movement framework, so an enemy will regularly
	end up with a target it cannot reach on foot. When no path can be
	found, or the enemy has been stuck for a while, the target is marked
	unreachable for a few seconds. The enemy then uses a ranged attack
	if it has one, otherwise picks another player, otherwise stands
	under the target and waits for them to come down, rather than
	walking into a wall forever.
]]

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyData = require(ReplicatedStorage.Modules.Game.Data.EnemyData)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local EnemyBase = require(script.Parent.EnemyBase)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)

local EnemyAI = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

EnemyAI.Settings = {
	-- Within this many studs, with nothing in the way and not much
	-- height difference, an enemy walks straight at its target instead
	-- of pathfinding. Straight lines are free, paths are not.
	DirectChaseDistance = 70,
	-- Height difference above which a straight walk is not trusted.
	DirectChaseMaxHeight = 6,
	-- A path waypoint counts as reached within this many studs.
	WaypointReachedDistance = 4,
	-- An enemy that has moved less than StuckDistance in StuckTime
	-- while trying to move jumps. Doing that StuckStrikes times in a
	-- row marks the target unreachable.
	StuckTime = 1,
	StuckDistance = 1.5,
	StuckStrikes = 3,
	-- Seconds a target stays marked unreachable before trying again.
	UnreachableTime = 4,
	-- Enemies spread around their target instead of stacking on the
	-- same point, since they do not collide with each other. This is
	-- how far out from the target each one aims for, as a fraction of
	-- its melee range.
	SurroundFraction = 0.55,
	-- Extra studs added to an attack's range when the hit is checked
	-- after the wind up, so a target that stepped back a little is
	-- still hit. Dodging needs a real dodge, not a half step.
	MeleeHitTolerance = 2.5,
	-- Width and height of the box a melee swing checks in front of the
	-- enemy, multiplied by the model's size relative to a normal R6.
	MeleeBoxWidth = 6,
	MeleeBoxHeight = 7,
	-- Seconds the enemy stays planted after an attack lands. An enemy's
	-- AttackRecovery in EnemyData overrides it (the boss).
	AttackRecovery = 0.25,
	-- Projectile lifetime is the time to cover the attack range, times
	-- this, plus a second.
	ProjectileLifetimeScale = 1.5,
	-- Fraction of the target's velocity added to a ranged aim point,
	-- so projectiles lead a running player.
	ProjectileLead = 0.85,
	-- Studs in front of and above the root that projectiles start at.
	ProjectileMuzzle = Vector3.new(0, 1.5, -2),
	-- Players further than this from the enemy in its own area are
	-- still preferred over a closer player in another area, by treating
	-- the other area's players as this many studs further away.
	OtherAreaPenalty = 1000,
	-- Hard cap on living enemies. Summons are refused past this.
	MaxEnemiesAlive = 70,
	-- During a charge wind up the enemy keeps turning to follow its
	-- target until this many seconds before it goes, then commits.
	ChargeLockTime = 0.2,
	-- How often a charge checks what it has run into.
	ChargeStep = 1 / 30,
	-- The pathfinding agent. Scaled by the model's height against a
	-- normal 5 stud R6.
	Agent = {
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 6,
	},
}

local Running = false
-- How many enemies are going for each player, rebuilt every tick, for
-- spreading a crowd over the team.
local TargetCounts: { [Player]: number } = {}

----------------------------------------------------------------------
-- TARGETS
----------------------------------------------------------------------

-- The root of a living, targetable player, or nil.
function EnemyAI.GetPlayerRoot(Player: Player): BasePart?
	if typeof(Player) ~= "Instance" or not Player:IsA("Player") or Player.Parent ~= Players then
		return nil
	end
	local Stats = PlayerStats.Get(Player)
	if not Stats or not Stats:IsAlive() then
		return nil
	end
	local Character = Player.Character
	if not Character or Character:GetAttribute("Spectating") then
		return nil
	end
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local Root = Character:FindFirstChild("HumanoidRootPart")
	if not Humanoid or Humanoid.Health <= 0 or not Root then
		return nil
	end
	return Root
end

-- Every player an enemy could go for.
function EnemyAI.GetTargetablePlayers(): { Player }
	local List = {}
	for _, Player in ipairs(Players:GetPlayers()) do
		if EnemyAI.GetPlayerRoot(Player) then
			table.insert(List, Player)
		end
	end
	return List
end

local RoomZones = nil
local function GetRoomZones()
	if RoomZones == nil then
		local Module = script.Parent.Parent:FindFirstChild("Rooms") and script.Parent.Parent.Rooms:FindFirstChild("RoomZones")
		local Ok, Result = pcall(require, Module)
		RoomZones = Ok and type(Result) == "table" and Result.GetArea and Result or false
	end
	return RoomZones or nil
end

-- Distance used to rank targets, with the other area penalty and the
-- crowd penalty.
local function RankDistance(Enemy, Player: Player, Root: BasePart): number
	local Distance = (Root.Position - Enemy.Root.Position).Magnitude
	local Zones = GetRoomZones()
	if Zones and Enemy.AreaName and Zones.GetArea(Player) ~= Enemy.AreaName then
		Distance += EnemyAI.Settings.OtherAreaPenalty
	end
	-- Others already on this player, not counting this enemy.
	local Crowd = (TargetCounts[Player] or 0) - (Enemy.Target == Player and 1 or 0)
	Distance += math.max(0, Crowd) * (EnemyData.Shared.CrowdPenalty or 0)
	return Distance
end

local function IsUnreachable(Enemy, Player: Player): boolean
	local Until = Enemy.AI.Unreachable[Player]
	return Until ~= nil and os.clock() < Until
end

-- The default rule: whoever hit it recently, otherwise the best player
-- in range, otherwise (with NoTargetBehaviour "Hunt") the best player
-- anywhere. Players marked unreachable are skipped if anyone else is
-- available.
function EnemyAI.PickTarget(Enemy): Player?
	local Data = Enemy.Data
	local Shared = EnemyData.Shared

	local Aggro = Enemy.Target
	if Aggro and os.clock() < (Enemy.AggroUntil or 0) and EnemyAI.GetPlayerRoot(Aggro) and not IsUnreachable(Enemy, Aggro) then
		return Aggro
	end

	local Best, BestDistance = nil, math.huge
	local Fallback, FallbackDistance = nil, math.huge
	for _, Player in ipairs(EnemyAI.GetTargetablePlayers()) do
		local Root = EnemyAI.GetPlayerRoot(Player)
		local Distance = RankDistance(Enemy, Player, Root)
		local Real = (Root.Position - Enemy.Root.Position).Magnitude
		local InRange = Real <= Data.DetectRange or Shared.NoTargetBehaviour == "Hunt"
		-- Keep chasing the current target out to LoseRange, and a
		-- little stickiness so it does not flip between two players.
		if Player == Enemy.Target then
			if Real <= Data.LoseRange then
				InRange = true
			end
			Distance -= 6
		end
		if InRange then
			if IsUnreachable(Enemy, Player) then
				if Distance < FallbackDistance then
					Fallback, FallbackDistance = Player, Distance
				end
			elseif Distance < BestDistance then
				Best, BestDistance = Player, Distance
			end
		end
	end
	return Best or Fallback
end

----------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------

local function Stop(Enemy)
	local AI = Enemy.AI
	if AI then
		AI.Path = nil
		AI.Moving = false
	end
	if Enemy.Humanoid.Parent then
		Enemy.Humanoid:Move(Vector3.zero)
		Enemy.Humanoid:MoveTo(Enemy.Root.Position)
	end
end
EnemyAI.Stop = Stop

-- Turns the enemy to face a point without tilting it.
function EnemyAI.Face(Enemy, Position: Vector3)
	local Root = Enemy.Root
	local Flat = Vector3.new(Position.X, Root.Position.Y, Position.Z)
	if (Flat - Root.Position).Magnitude > 0.1 then
		Root.CFrame = CFrame.lookAt(Root.Position, Flat)
	end
end

local function HasClearLine(Enemy, To: Vector3): boolean
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)
	local From = Enemy.Root.Position
	local Result = workspace:Raycast(From, To - From, HitDetection.MapRaycastParams({ Enemy.Model }))
	return Result == nil
end

-- Size of this model relative to a normal 5 stud R6, for the agent
-- and the melee box.
local function ScaleOf(Enemy): number
	if Enemy.AI and Enemy.AI.Scale then
		return Enemy.AI.Scale
	end
	local _, Size = Enemy.Model:GetBoundingBox()
	local Scale = math.max(1, Size.Y / 5)
	if Enemy.AI then
		Enemy.AI.Scale = Scale
	end
	return Scale
end
EnemyAI.ScaleOf = ScaleOf

-- The walk speed the enemy should have right now: its base (or the
-- enraged speed), plus the sprint when its target is far away.
local function UpdateSpeed(Enemy, Distance: number?)
	if Enemy.IsStunned or Enemy.IsDead then
		return
	end
	local Base = Enemy.BaseWalkSpeed or Enemy.Data.WalkSpeed
	local Sprint = Enemy.Data.SprintMultiplier or EnemyData.Shared.SprintMultiplier or 1
	local Speed = Base
	if Distance and Distance > (EnemyData.Shared.SprintDistance or math.huge) then
		Speed = Base * Sprint
	end
	if math.abs(Enemy.Humanoid.WalkSpeed - Speed) > 0.05 then
		Enemy.Humanoid.WalkSpeed = Speed
	end
end
EnemyAI.UpdateSpeed = UpdateSpeed

local function ComputePath(Enemy, Goal: Vector3)
	local AI = Enemy.AI
	if AI.Computing then
		return
	end
	AI.Computing = true
	local Scale = ScaleOf(Enemy)
	local Agent = table.clone(EnemyAI.Settings.Agent)
	Agent.AgentRadius *= Scale
	Agent.AgentHeight *= Scale

	task.spawn(function()
		local Path = PathfindingService:CreatePath(Agent)
		local Ok = pcall(function()
			Path:ComputeAsync(Enemy.Root.Position, Goal)
		end)
		AI.Computing = false
		if Enemy.IsDead then
			return
		end
		if Ok and Path.Status == Enum.PathStatus.Success then
			AI.Path = Path:GetWaypoints()
			AI.WaypointIndex = 2
			AI.PathFails = 0
		else
			AI.Path = nil
			AI.PathFails = (AI.PathFails or 0) + 1
		end
	end)
end

-- Walks toward Goal, straight if it can, along a path if not.
local function MoveTowards(Enemy, Goal: Vector3, Target: Player?)
	local Settings = EnemyAI.Settings
	local AI = Enemy.AI
	local Humanoid = Enemy.Humanoid
	local Root = Enemy.Root
	local Now = os.clock()
	AI.Moving = true

	local Offset = Goal - Root.Position
	local Direct = Offset.Magnitude <= Settings.DirectChaseDistance
		and math.abs(Offset.Y) <= Settings.DirectChaseMaxHeight
		and HasClearLine(Enemy, Goal)

	if Direct or Enemy.Data.DirectChaseOnly or not EnemyData.Shared.UsePathfinding then
		AI.Path = nil
		Humanoid:MoveTo(Goal)
	else
		if Now >= (AI.NextRepathAt or 0) then
			AI.NextRepathAt = Now + EnemyData.Shared.RepathRate
			ComputePath(Enemy, Goal)
		end
		local Path = AI.Path
		if Path and AI.WaypointIndex <= #Path then
			local Waypoint = Path[AI.WaypointIndex]
			local Flat = (Waypoint.Position - Root.Position) * Vector3.new(1, 0, 1)
			if Flat.Magnitude < Settings.WaypointReachedDistance then
				AI.WaypointIndex += 1
				Waypoint = Path[AI.WaypointIndex]
			end
			if Waypoint then
				if Waypoint.Action == Enum.PathWaypointAction.Jump then
					Humanoid.Jump = true
				end
				Humanoid:MoveTo(Waypoint.Position)
			end
		elseif (AI.PathFails or 0) >= 2 and Target then
			-- No path at all: the target is somewhere feet cannot go.
			AI.Unreachable[Target] = Now + Settings.UnreachableTime
			AI.PathFails = 0
			Humanoid:MoveTo(Goal)
		else
			Humanoid:MoveTo(Goal)
		end
	end

	-- Stuck check.
	if not AI.StuckFrom or (Root.Position - AI.StuckFrom).Magnitude > Settings.StuckDistance then
		AI.StuckFrom = Root.Position
		AI.StuckSince = Now
		AI.StuckStrikes = 0
	elseif Now - AI.StuckSince > Settings.StuckTime then
		Humanoid.Jump = true
		AI.StuckSince = Now
		AI.StuckStrikes += 1
		AI.NextRepathAt = 0
		if AI.StuckStrikes >= Settings.StuckStrikes and Target then
			AI.Unreachable[Target] = Now + Settings.UnreachableTime
			AI.StuckStrikes = 0
		end
	end
end
EnemyAI.MoveTowards = MoveTowards

----------------------------------------------------------------------
-- ATTACKS
----------------------------------------------------------------------

local function KindOf(Attack): string
	if Attack.Projectile then
		return "Ranged"
	elseif Attack.Charge then
		return "Charge"
	elseif Attack.Explode then
		return "Explode"
	elseif Attack.Rain then
		return "Rain"
	elseif Attack.Shockwave then
		return "Shockwave"
	elseif Attack.Radius then
		return "Slam"
	elseif Attack.SummonType then
		return "Summon"
	end
	return "Melee"
end
EnemyAI.KindOf = KindOf

-- The highest priority attack the target is in range of that is off
-- cooldown. Unreachable limits it to attacks that do not need feet.
function EnemyAI.ChooseAttack(Enemy, Distance: number, Unreachable: boolean): string?
	local BestName, BestPriority = nil, -math.huge
	for Name, Attack in pairs(Enemy.Attacks) do
		local Kind = KindOf(Attack)
		local Usable = Distance <= Attack.Range and Distance >= (Attack.MinRange or 0) and Enemy:CanUseAttack(Name)
		-- A target out of reach can still be shot at from any
		-- distance inside range, the minimum range is ignored so Bob
		-- does not stand under a wall runner doing nothing.
		if Unreachable and Kind == "Ranged" and Distance <= Attack.Range and Enemy:CanUseAttack(Name) then
			Usable = true
		end
		-- A charge at someone up a wall would just run into it.
		if Unreachable and Kind == "Charge" then
			Usable = false
		end
		if Usable and type(Enemy.CanUseAttackNow) == "function" then
			Usable = Enemy:CanUseAttackNow(Name, Distance)
		end
		if Usable and (Attack.Priority or 0) > BestPriority then
			BestName, BestPriority = Name, Attack.Priority or 0
		end
	end
	return BestName
end

-- Damage for an attack after the enemy's own multiplier, the boss
-- enrage for instance. Scaling was already done by EnemyBase.
local function DamageOf(Enemy, Attack): number
	return Attack.Damage * (Enemy.DamageMultiplier or 1)
end
EnemyAI.DamageOf = DamageOf

local function HitPlayer(Enemy, AttackName: string, Attack, Character: Model, From: Vector3)
	local DamageService = require(script.Parent.Parent.Combat.DamageService)
	DamageService.ApplyDamage(Character, DamageOf(Enemy, Attack), Enemy, {
		Source = Enemy.TypeName .. " " .. AttackName,
		Knockback = Attack.Knockback,
		From = From,
		StatusEffect = Attack.StatusEffect,
	})
end
EnemyAI.HitPlayer = HitPlayer

-- The floor under a point, for area attacks and telegraphs.
function EnemyAI.FloorBelow(Enemy, Position: Vector3): Vector3
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)
	local Result = workspace:Raycast(Position, Vector3.new(0, -30, 0), HitDetection.MapRaycastParams({ Enemy.Model }))
	return Result and Result.Position or (Position - Vector3.new(0, 3 * ScaleOf(Enemy), 0))
end

-- Fires one or more projectiles at a player. Count and Spread in the
-- attack's Projectile table make an even fan.
function EnemyAI.FireAt(Enemy, AttackName: string, Attack, Target: Player)
	local ProjectileService = require(script.Parent.Parent.Combat.ProjectileService)
	local Settings = EnemyAI.Settings
	local TargetRoot = EnemyAI.GetPlayerRoot(Target)
	if not TargetRoot then
		return
	end
	local P = Attack.Projectile
	local Origin = Enemy.Root.CFrame:PointToWorldSpace(Settings.ProjectileMuzzle * ScaleOf(Enemy))
	local Distance = (TargetRoot.Position - Origin).Magnitude
	local Time = Distance / P.Speed
	-- Lead the target, then lift the aim to cancel the drop.
	local Aim = TargetRoot.Position + TargetRoot.AssemblyLinearVelocity * Vector3.new(1, 0.3, 1) * Time * Settings.ProjectileLead
	Aim += Vector3.new(0, 0.5 * (P.Gravity or 0) * Time * Time, 0)
	local Centre = (Aim - Origin).Unit

	local Count = P.Count or 1
	local Spread = P.Spread or 0
	for Index = 1, Count do
		local Yaw = 0
		if Count > 1 then
			Yaw = math.rad(-Spread / 2 + Spread * (Index - 1) / (Count - 1))
		end
		local Direction = (CFrame.lookAt(Vector3.zero, Centre) * CFrame.Angles(0, Yaw, 0)).LookVector
		ProjectileService.Fire({
			Owner = Enemy,
			Side = "Players",
			Origin = Origin,
			Direction = Direction,
			Speed = P.Speed,
			Gravity = P.Gravity or 0,
			Lifetime = Attack.Range / P.Speed * Settings.ProjectileLifetimeScale + 1,
			ModelName = P.ModelName,
			Damage = DamageOf(Enemy, Attack),
			Pierce = 0,
			Knockback = Attack.Knockback,
			Source = Enemy.TypeName .. " " .. AttackName,
			StatusEffect = Attack.StatusEffect,
			Explosion = P.Explosion,
			Radius = P.Radius,
			-- Curves after the target, see ProjectileService.
			Homing = P.Homing and {
				Target = TargetRoot,
				TurnRate = P.Homing.TurnRate,
				Duration = P.Homing.Duration,
			} or nil,
		})
	end
end

-- The players an area attack goes for: everyone targetable in the
-- enemy's own area, or everyone if it has no area.
local function PlayersInArea(Enemy): { Player }
	local List = {}
	local Zones = GetRoomZones()
	for _, Player in ipairs(EnemyAI.GetTargetablePlayers()) do
		if not Zones or not Enemy.AreaName or Zones.GetArea(Player) == Enemy.AreaName then
			table.insert(List, Player)
		end
	end
	if #List == 0 then
		List = EnemyAI.GetTargetablePlayers()
	end
	return List
end

-- Meteors on and around every player. The circles and the falling
-- meteors are drawn by the clients from one MeteorRain message, the
-- hits are done here as each one lands.
function EnemyAI.RunRain(Enemy, AttackName: string, Attack)
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)
	local Rain = Attack.Rain
	local Points = {}
	for _, Player in ipairs(PlayersInArea(Enemy)) do
		local Root = EnemyAI.GetPlayerRoot(Player)
		if Root then
			for Index = 1, Rain.PerPlayer or 3 do
				local Offset = Vector3.zero
				if Index > 1 then
					local Angle = math.random() * math.pi * 2
					local Distance = (0.35 + math.random() * 0.65) * (Rain.Spread or 20)
					Offset = Vector3.new(math.cos(Angle), 0, math.sin(Angle)) * Distance
				end
				-- Aim a little ahead of a runner for the one under them.
				local Lead = Index == 1 and Root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * 0.35 or Vector3.zero
				local Floor = EnemyAI.FloorBelow(Enemy, Root.Position + Offset + Lead + Vector3.new(0, 4, 0))
				table.insert(Points, { Position = Floor, Delay = (Rain.Delay or 1) + (#Points) * (Rain.Stagger or 0.1) })
			end
		end
	end
	if #Points == 0 then
		return
	end
	CombatFX.Broadcast("MeteorRain", nil, { Points = Points, Radius = Rain.Radius })
	for _, Point in ipairs(Points) do
		task.delay(Point.Delay, function()
			if Enemy.IsDead then
				return
			end
			local Hits = HitDetection.Sphere(Point.Position + Vector3.new(0, 2, 0), Rain.Radius, { Side = "Players", Origin = Point.Position })
			for _, Hit in ipairs(Hits) do
				HitPlayer(Enemy, AttackName, Attack, Hit.Model, Point.Position)
			end
		end)
	end
end

-- Rings of fire spreading across the floor from the enemy. Anyone
-- whose feet are near the floor where a ring passes is hit once per
-- ring, so they are jumped over.
function EnemyAI.RunShockwave(Enemy, AttackName: string, Attack)
	local Wave = Attack.Shockwave
	local Centre = EnemyAI.FloorBelow(Enemy, Enemy.Root.Position)
	CombatFX.Broadcast("Shockwave", nil, {
		Position = Centre,
		Speed = Wave.Speed,
		MaxRadius = Wave.MaxRadius,
		Width = Wave.Width,
		Rings = Wave.Rings or 1,
		RingGap = Wave.RingGap or 0.6,
	})
	for Ring = 1, Wave.Rings or 1 do
		task.delay((Ring - 1) * (Wave.RingGap or 0.6), function()
			local AlreadyHit: { [Player]: boolean } = {}
			local Start = os.clock()
			while not Enemy.IsDead do
				local Radius = (os.clock() - Start) * Wave.Speed
				if Radius > Wave.MaxRadius then
					break
				end
				for _, Player in ipairs(EnemyAI.GetTargetablePlayers()) do
					local Root = EnemyAI.GetPlayerRoot(Player)
					if Root and not AlreadyHit[Player] then
						local Offset = Root.Position - Centre
						local Flat = Vector3.new(Offset.X, 0, Offset.Z).Magnitude
						-- A standing root is about 3 studs above the floor, so
						-- Height is measured from there.
						local Grounded = Offset.Y < 3 + (Wave.Height or 4)
						if Grounded and math.abs(Flat - Radius) <= Wave.Width then
							AlreadyHit[Player] = true
							HitPlayer(Enemy, AttackName, Attack, Player.Character, Centre)
						end
					end
				end
				task.wait(1 / 30)
			end
		end)
	end
end

-- Lands a melee or area attack right now, with no wind up. Centre is
-- where an area attack lands, the floor under the enemy if nil.
function EnemyAI.Land(Enemy, AttackName: string, Attack, Target: Player?, Centre: Vector3?)
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)
	local Settings = EnemyAI.Settings
	local Kind = KindOf(Attack)
	local Root = Enemy.Root

	if Kind == "Ranged" then
		if Target then
			EnemyAI.FireAt(Enemy, AttackName, Attack, Target)
		end
		CombatFX.Broadcast("Enemy_Swing", Enemy.Model, { Kind = Kind, Sound = Attack.Sound })
		return
	end

	if Kind == "Slam" then
		local Floor = Centre or EnemyAI.FloorBelow(Enemy, Root.Position)
		local Hits = HitDetection.Sphere(Floor + Vector3.new(0, 2, 0), Attack.Radius, { Side = "Players", Origin = Floor })
		for _, Hit in ipairs(Hits) do
			HitPlayer(Enemy, AttackName, Attack, Hit.Model, Floor)
		end
		CombatFX.Broadcast("Enemy_Swing", Enemy.Model, { Kind = Kind })
		CombatFX.Broadcast("StunSlam_Land", nil, {
			Position = Floor,
			Radius = Attack.Radius,
			Material = Enum.Material.Slate,
			Colour = Color3.fromRGB(90, 60, 60),
			Sound = Attack.Sound,
			Hostile = true,
		})
		return
	end

	-- Melee: a box in front of the enemy out to the attack range.
	local Scale = ScaleOf(Enemy)
	local Reach = Attack.Range + Settings.MeleeHitTolerance
	local Size = Vector3.new(Settings.MeleeBoxWidth * Scale, Settings.MeleeBoxHeight * Scale, Reach)
	local BoxCFrame = Root.CFrame * CFrame.new(0, 0, -Reach / 2)
	local Hits = HitDetection.Box(BoxCFrame, Size, { Side = "Players", Origin = Root.Position })
	for _, Hit in ipairs(Hits) do
		HitPlayer(Enemy, AttackName, Attack, Hit.Model, Root.Position)
	end
	CombatFX.Broadcast("Enemy_Swing", Enemy.Model, { Kind = Kind, Scale = Scale, Sound = Attack.Sound })
end

-- A dash in a straight line along Direction, hitting every player it
-- passes through once. Yields for the length of the dash.
function EnemyAI.RunCharge(Enemy, AttackName: string, Attack, Direction: Vector3)
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)
	local Settings = EnemyAI.Settings
	local Charge = Attack.Charge
	local Root = Enemy.Root
	local Humanoid = Enemy.Humanoid
	local Duration = Charge.Distance / Charge.Speed
	local Scale = ScaleOf(Enemy)
	local AlreadyHit: { [Model]: boolean } = {}
	local Ends = os.clock() + Duration

	CombatFX.Broadcast("Enemy_Swing", Enemy.Model, { Kind = "Charge", Duration = Duration, Sound = Attack.Sound })
	-- The humanoid does the running: its speed is raised to the charge
	-- speed and it walks to a point the charge distance away, so it
	-- keeps to the floor and turns nothing on the way.
	Humanoid.WalkSpeed = Charge.Speed
	Humanoid:MoveTo(Root.Position + Direction * (Charge.Distance + 5))
	while os.clock() < Ends and not Enemy.IsDead and not Enemy.IsStunned and Root.Parent do

		local Box = Root.CFrame * CFrame.new(0, 0, -1.5 * Scale)
		local Hits = HitDetection.Box(Box, Vector3.new(Charge.Width, 6 * Scale, 4 * Scale), { Side = "Players", Origin = Root.Position })
		for _, Hit in ipairs(Hits) do
			if not AlreadyHit[Hit.Model] then
				AlreadyHit[Hit.Model] = true
				HitPlayer(Enemy, AttackName, Attack, Hit.Model, Root.Position - Direction * 4)
			end
		end

		-- A wall ends it early.
		local Ahead = workspace:Raycast(Root.Position, Direction * (2.5 * Scale), HitDetection.MapRaycastParams({ Enemy.Model }))
		if Ahead then
			break
		end
		task.wait(Settings.ChargeStep)
	end
	if Root.Parent and not Enemy.IsStunned then
		Humanoid.WalkSpeed = Enemy.BaseWalkSpeed or Enemy.Data.WalkSpeed
	end
	Stop(Enemy)
end

-- The generic attack: plant, face, telegraph, wait the wind up, land.
-- Subclasses call this for anything they do not do specially.
function EnemyAI.PerformAttack(Enemy, AttackName: string, Target: Player?)
	local Attack = Enemy.Attacks[AttackName]
	if not Attack then
		return
	end
	local Settings = EnemyAI.Settings
	local Kind = KindOf(Attack)
	local WindUp = (Attack.WindUp or 0) * (Enemy.WindUpMultiplier or 1)

	Enemy.Busy = true
	Stop(Enemy)
	local TargetRoot = Target and EnemyAI.GetPlayerRoot(Target)
	if TargetRoot then
		EnemyAI.Face(Enemy, TargetRoot.Position)
	end
	Enemy:StartAttackCooldown(AttackName, Enemy.CooldownMultiplier)

	CombatFX.Broadcast("Enemy_WindUp", Enemy.Model, { Duration = WindUp, Kind = Kind })
	-- An area attack lands on the floor under the enemy, or with
	-- AtTarget under where the target was standing when it started,
	-- and the red circle shows where for the whole wind up.
	local Centre = nil
	if Kind == "Slam" then
		local From = (Attack.AtTarget and TargetRoot) and TargetRoot.Position or Enemy.Root.Position
		Centre = EnemyAI.FloorBelow(Enemy, From)
		CombatFX.Broadcast("Telegraph_Circle", nil, {
			Position = Centre,
			Radius = Attack.Radius,
			Duration = WindUp,
		})
	end

	task.spawn(function()
		if Kind == "Charge" then
			-- Track the target through most of the wind up, then lock
			-- in. The red line follows so the tell is always true.
			local Charge = Attack.Charge
			local LockAt = os.clock() + math.max(0, WindUp - Settings.ChargeLockTime)
			local Ends = os.clock() + WindUp
			local Direction = Enemy.Root.CFrame.LookVector
			local LineId = tostring(Enemy.Model) .. os.clock()
			while os.clock() < Ends do
				if Enemy.IsDead or Enemy.IsStunned then
					CombatFX.Broadcast("Telegraph_Line", nil, { Id = LineId, Remove = true })
					Enemy.Busy = false
					return
				end
				local Root = Target and EnemyAI.GetPlayerRoot(Target)
				if Root and os.clock() < LockAt then
					local Flat = (Root.Position - Enemy.Root.Position) * Vector3.new(1, 0, 1)
					if Flat.Magnitude > 0.5 then
						Direction = Flat.Unit
						EnemyAI.Face(Enemy, Root.Position)
					end
				end
				local Floor = EnemyAI.FloorBelow(Enemy, Enemy.Root.Position)
				CombatFX.Broadcast("Telegraph_Line", nil, {
					Id = LineId,
					From = Floor,
					Direction = Direction,
					Length = Charge.Distance,
					Width = Charge.Width,
					Duration = Ends - os.clock(),
				})
				task.wait(0.1)
			end
			CombatFX.Broadcast("Telegraph_Line", nil, { Id = LineId, Remove = true })
			local Ok, Error = pcall(EnemyAI.RunCharge, Enemy, AttackName, Attack, Direction)
			if not Ok then
				warn("[EnemyAI] " .. Enemy.TypeName .. " charge failed: " .. tostring(Error))
			end
			task.wait(Enemy.AttackRecovery or Enemy.Data.AttackRecovery or Settings.AttackRecovery)
			Enemy.Busy = false
			return
		end

		-- Melee keeps turning to follow a target that moves during the
		-- wind up, so a swing is only dodged by getting out of reach.
		local Ends = os.clock() + WindUp
		while os.clock() < Ends do
			if Enemy.IsDead or Enemy.IsStunned then
				Enemy.Busy = false
				return
			end
			local Root = Target and EnemyAI.GetPlayerRoot(Target)
			if Root and (Kind == "Melee" or Kind == "Ranged") then
				EnemyAI.Face(Enemy, Root.Position)
			end
			task.wait(0.05)
		end
		if Enemy.IsDead or Enemy.IsStunned then
			Enemy.Busy = false
			return
		end

		-- The lunge: a jump forward as the swing comes out, if the
		-- target has got a little out of reach.
		local Root = Target and EnemyAI.GetPlayerRoot(Target)
		if Kind == "Melee" and Attack.Lunge and Root then
			local Flat = (Root.Position - Enemy.Root.Position) * Vector3.new(1, 0, 1)
			if Flat.Magnitude > 2.5 then
				-- A burst of speed straight at the target for a moment.
				local Lunge = Attack.Lunge
				local Humanoid = Enemy.Humanoid
				Humanoid.WalkSpeed = Lunge.Speed
				Humanoid:MoveTo(Enemy.Root.Position + Flat.Unit * math.min(Flat.Magnitude, Lunge.Speed * (Lunge.Time or 0.12) + 2))
				task.wait(Lunge.Time or 0.12)
				if not Enemy.IsDead and not Enemy.IsStunned then
					Humanoid.WalkSpeed = Enemy.BaseWalkSpeed or Enemy.Data.WalkSpeed
					Stop(Enemy)
				end
			end
		end

		local Handler = (Kind == "Rain" and EnemyAI.RunRain) or (Kind == "Shockwave" and EnemyAI.RunShockwave) or nil
		local Ok, Error
		if Handler then
			CombatFX.Broadcast("Enemy_Swing", Enemy.Model, { Kind = "Slam", Sound = Attack.Sound })
			Ok, Error = pcall(Handler, Enemy, AttackName, Attack)
		else
			Ok, Error = pcall(EnemyAI.Land, Enemy, AttackName, Attack, Target, Centre)
		end
		if not Ok then
			warn("[EnemyAI] " .. Enemy.TypeName .. " " .. AttackName .. " failed: " .. tostring(Error))
		end
		task.wait(Enemy.AttackRecovery or Enemy.Data.AttackRecovery or Settings.AttackRecovery)
		Enemy.Busy = false
	end)
end

----------------------------------------------------------------------
-- THINK
----------------------------------------------------------------------

local function EnsureState(Enemy)
	if not Enemy.AI then
		Enemy.AI = {
			Unreachable = {},
			Angle = math.random() * math.pi * 2,
			StuckStrikes = 0,
			StrafeSign = math.random() < 0.5 and -1 or 1,
			NextStrafeFlip = os.clock() + 1 + math.random() * 2,
		}
	end
	return Enemy.AI
end

-- One decision for one enemy.
function EnemyAI.Think(Enemy)
	if Enemy.IsDead or Enemy.Stationary or not Enemy.Root.Parent then
		return
	end
	local AI = EnsureState(Enemy)

	if Enemy.IsStunned then
		if AI.Moving then
			Stop(Enemy)
		end
		return
	end
	if Enemy.Busy then
		return
	end

	local Target = type(Enemy.PickTarget) == "function" and Enemy:PickTarget() or EnemyAI.PickTarget(Enemy)
	if Target ~= Enemy.Target then
		Enemy.Target = Target
		AI.Path = nil
		AI.NextRepathAt = 0
	end
	local TargetRoot = Target and EnemyAI.GetPlayerRoot(Target)
	if not TargetRoot then
		if AI.Moving then
			Stop(Enemy)
		end
		return
	end

	local Distance = (TargetRoot.Position - Enemy.Root.Position).Magnitude
	UpdateSpeed(Enemy, Distance)
	if type(Enemy.OnThink) == "function" then
		Enemy:OnThink(Target, Distance)
		if Enemy.Busy or Enemy.IsDead then
			return
		end
	end

	local Unreachable = IsUnreachable(Enemy, Target)
	local AttackName = EnemyAI.ChooseAttack(Enemy, Distance, Unreachable)
	if AttackName then
		if type(Enemy.Attack) == "function" then
			Enemy:Attack(AttackName, Target)
		else
			EnemyAI.PerformAttack(Enemy, AttackName, Target)
		end
		return
	end

	-- No attack: close in to the range it wants, spread out around the
	-- target so a crowd does not stack on one point.
	local Melee = Enemy.Attacks.Melee or Enemy.Attacks.Close
	local MeleeRange = Melee and Melee.Range or 5
	local Desired = MeleeRange * EnemyAI.Settings.SurroundFraction
	local Preferred = Enemy.Data.PreferredDistance
	if Preferred and Preferred > 0 then
		Desired = Preferred
	end
	if type(Enemy.DesiredRange) == "function" then
		Desired = Enemy:DesiredRange(Target, Distance) or Desired
	end

	local Away = Enemy.Root.Position - TargetRoot.Position
	Away = Vector3.new(Away.X, 0, Away.Z)
	if Distance > Desired + 1.5 then
		local Spread = Vector3.new(math.cos(AI.Angle), 0, math.sin(AI.Angle)) * math.min(Desired, 6)
		-- Aim a little ahead of a moving target, so running in a
		-- straight line does not leave the enemy behind.
		local Lead = TargetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * math.clamp(Distance / 60, 0, 0.5)
		local Goal = TargetRoot.Position + Spread + Lead
		if Unreachable then
			-- Stand under them and wait.
			Goal = Vector3.new(TargetRoot.Position.X, Enemy.Root.Position.Y, TargetRoot.Position.Z) + Spread
		end
		MoveTowards(Enemy, Goal, Target)
	elseif Distance < Desired - 3 and Away.Magnitude > 0.1 then
		-- Too close for comfort, back off, circling as it goes.
		local Side = Vector3.new(-Away.Z, 0, Away.X).Unit * AI.StrafeSign
		MoveTowards(Enemy, Enemy.Root.Position + Away.Unit * 8 + Side * 4, nil)
	elseif (Enemy.Data.StrafeSpeed or 0) > 0 and Away.Magnitude > 0.1 then
		-- Circle the target at the range it likes, changing direction
		-- now and then, so it is never a still target.
		if os.clock() >= AI.NextStrafeFlip then
			AI.StrafeSign = -AI.StrafeSign
			AI.NextStrafeFlip = os.clock() + 1.2 + math.random() * 2
		end
		local Side = Vector3.new(-Away.Z, 0, Away.X).Unit * AI.StrafeSign
		MoveTowards(Enemy, Enemy.Root.Position + Side * 10 * Enemy.Data.StrafeSpeed, nil)
		EnemyAI.Face(Enemy, TargetRoot.Position)
	else
		if AI.Moving then
			Stop(Enemy)
		end
		EnemyAI.Face(Enemy, TargetRoot.Position)
	end
end

function EnemyAI.Init()
	if Running then
		return
	end
	Running = true
	task.spawn(function()
		while Running do
			local Alive = EnemyBase.GetAlive()
			-- Who is going for whom, for the crowd penalty.
			local Counts = {}
			for _, Enemy in ipairs(Alive) do
				if Enemy.Target then
					Counts[Enemy.Target] = (Counts[Enemy.Target] or 0) + 1
				end
			end
			TargetCounts = Counts
			for _, Enemy in ipairs(Alive) do
				local Ok, Error = pcall(EnemyAI.Think, Enemy)
				if not Ok then
					warn("[EnemyAI] " .. tostring(Enemy.TypeName) .. " think failed: " .. tostring(Error))
				end
			end
			task.wait(EnemyData.Shared.ThinkRate)
		end
	end)
end

return EnemyAI
