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
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
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
	-- A little wider than the body so paths keep off walls and edges
	-- instead of hugging them.
	Agent = {
		AgentRadius = 2.6,
		AgentHeight = 5,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	},

	-- how fast an enemy turns to face a player while planted or strafing (AlignOrientation responsiveness)
	TurnResponsiveness = 22,
	-- radius of the thick line check for walking straight at something, times the model's scale
	LineRadius = 1.4,
	-- straight walks check for floor every this many studs (at most FloorCheckMax times), and a drop deeper than MaxDrop counts as a ledge
	FloorCheckSpacing = 7,
	FloorCheckMax = 6,
	MaxDrop = 10,
	-- waypoints ahead a path follower looks for one it can walk straight to
	LookAhead = 4,
	-- the goal has to move this many studs before a new path is worked out
	RepathMoveThreshold = 6,

	-- enemies push apart within this many studs (times scale), by up to SeparationWeight studs, so a crowd never becomes one blob
	SeparationRadius = 5,
	SeparationWeight = 7,
	-- far away, each enemy heads for a point off to its own side of the target (up to FlankMaxAngle radians, out to FlankRadius studs),
	-- easing to straight on by FlankFullDistance, so a room comes at you from several sides instead of in single file
	FlankMaxAngle = 0.9,
	FlankRadius = 16,
	FlankFullDistance = 35,
	-- how many enemies can be swinging at one player at once (a difficulty can set MeleeAttackers instead).
	-- the rest circle just outside reach, WaitRingExtra studs past their melee range, and take turns
	MaxMeleeAttackers = 2,
	WaitRingExtra = 5,
	-- during a melee wind up the enemy keeps stepping in at this fraction of its speed, instead of stopping dead
	WindUpStepSpeed = 0.4,
	-- after a melee swing the enemy steps back and to the side for this long (an entry's BackOffTime overrides, 0 turns it off)
	BackOffTime = 0.45,
}

local Running = false
-- How many enemies are going for each player, rebuilt every tick, for
-- spreading a crowd over the team.
local TargetCounts: { [Player]: number } = {}
-- how many enemies are mid swing at each player right now, for taking turns
local SwingCounts: { [Player]: number } = {}

-- attacks that need the enemy right next to the player, which take turns
local CloseKinds = { Melee = true, Charge = true, Slam = true }

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

-- The physics turn used while an enemy is planted or strafing, so it
-- turns smoothly to face a player instead of snapping round. Made the
-- first time it is needed.
local function Facer(Enemy): AlignOrientation?
	local Root = Enemy.Root
	if not Root or not Root.Parent then
		return nil
	end
	local Existing = Root:FindFirstChild("AIFacing")
	if Existing and Existing:IsA("AlignOrientation") then
		return Existing
	end
	local Attachment = Instance.new("Attachment")
	Attachment.Name = "AIFacingAttachment"
	Attachment.Parent = Root
	local Align = Instance.new("AlignOrientation")
	Align.Name = "AIFacing"
	Align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	Align.Attachment0 = Attachment
	Align.RigidityEnabled = false
	Align.MaxTorque = math.huge
	Align.Responsiveness = EnemyAI.Settings.TurnResponsiveness
	Align.Enabled = false
	Align.Parent = Root
	return Align
end

-- Turns the enemy to face a point without tilting it. The turn is
-- smooth, and the humanoid stops turning itself to its walk direction
-- until FreeTurn, so it can strafe while facing the player.
function EnemyAI.Face(Enemy, Position: Vector3)
	local Root = Enemy.Root
	local Flat = (Position - Root.Position) * Vector3.new(1, 0, 1)
	if Flat.Magnitude < 0.1 then
		return
	end
	local Align = Facer(Enemy)
	if not Align then
		return
	end
	Enemy.Humanoid.AutoRotate = false
	Align.CFrame = CFrame.lookAt(Vector3.zero, Flat.Unit)
	Align.Enabled = true
end

-- Hands turning back to the humanoid, which faces where it walks.
local function FreeTurn(Enemy)
	local Align = Enemy.Root:FindFirstChild("AIFacing")
	if Align and Align.Enabled then
		Align.Enabled = false
	end
	if not Enemy.Humanoid.AutoRotate then
		Enemy.Humanoid.AutoRotate = true
	end
end
EnemyAI.FreeTurn = FreeTurn

local function MapParams(Enemy): RaycastParams
	local HitDetection = require(script.Parent.Parent.Combat.HitDetection)
	return HitDetection.MapRaycastParams({ Enemy.Model })
end

-- Whether the enemy's body fits along a straight line to To. A thick
-- check, so it does not catch a corner the thin line would have missed.
local function HasClearLine(Enemy, To: Vector3, Params: RaycastParams?): boolean
	local From = Enemy.Root.Position
	local Offset = To - From
	if Offset.Magnitude < 0.5 then
		return true
	end
	Params = Params or MapParams(Enemy)
	local Radius = EnemyAI.Settings.LineRadius * (Enemy.AI and Enemy.AI.Scale or 1)
	local Ok, Result = pcall(workspace.Spherecast, workspace, From, Radius, Offset, Params)
	if not Ok then
		Result = workspace:Raycast(From, Offset, Params)
	end
	return Result == nil
end

-- Whether there is floor under the whole of a straight walk to To, so
-- an enemy never runs off a ledge or the edge of the map chasing
-- someone on the far side of a gap.
local function HasFloorAlong(Enemy, To: Vector3, Params: RaycastParams?): boolean
	local Settings = EnemyAI.Settings
	local From = Enemy.Root.Position
	local Offset = (To - From) * Vector3.new(1, 0, 1)
	local Length = Offset.Magnitude
	if Length < 4 then
		return true
	end
	Params = Params or MapParams(Enemy)
	local Steps = math.clamp(math.floor(Length / Settings.FloorCheckSpacing), 1, Settings.FloorCheckMax)
	local Down = Vector3.new(0, -(Settings.MaxDrop + 4), 0)
	for Step = 1, Steps do
		local Point = From + Offset * (Step / (Steps + 1))
		if not workspace:Raycast(Point + Vector3.new(0, 2, 0), Down, Params) then
			return false
		end
	end
	return true
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
			local Waypoints = Path:GetWaypoints()
			-- Start from the waypoint just past the nearest one, so a
			-- fresh path never sends the enemy back the way it came.
			local Start, Nearest = 2, math.huge
			local Position = Enemy.Root.Position
			for Index = 1, math.min(#Waypoints, 6) do
				local Flat = ((Waypoints[Index].Position - Position) * Vector3.new(1, 0, 1)).Magnitude
				if Flat < Nearest then
					Start, Nearest = Index, Flat
				end
			end
			AI.Path = Waypoints
			AI.WaypointIndex = math.min(Start + 1, #Waypoints)
			AI.PathGoal = Goal
			AI.PathFails = 0
		else
			AI.Path = nil
			AI.PathGoal = nil
			AI.PathFails = (AI.PathFails or 0) + 1
		end
	end)
end

-- Follows the current path. Instead of walking to each waypoint in
-- turn (which hugs every corner and zig zags), it heads for the
-- furthest waypoint a few ahead that it can walk to in a straight line.
local function FollowPath(Enemy, Params: RaycastParams): boolean
	local Settings = EnemyAI.Settings
	local AI = Enemy.AI
	local Path = AI.Path
	if not Path or AI.WaypointIndex > #Path then
		return false
	end
	local Root = Enemy.Root
	local Humanoid = Enemy.Humanoid
	local Waypoint = Path[AI.WaypointIndex]
	local Flat = (Waypoint.Position - Root.Position) * Vector3.new(1, 0, 1)
	if Flat.Magnitude < Settings.WaypointReachedDistance then
		AI.WaypointIndex += 1
		Waypoint = Path[AI.WaypointIndex]
		if not Waypoint then
			return false
		end
	end
	if Waypoint.Action == Enum.PathWaypointAction.Jump then
		Humanoid.Jump = true
		Humanoid:MoveTo(Waypoint.Position)
		return true
	end

	local Lift = Vector3.new(0, Root.Position.Y - (Path[math.max(1, AI.WaypointIndex - 1)].Position.Y), 0)
	local Best = AI.WaypointIndex
	for Look = AI.WaypointIndex + 1, math.min(#Path, AI.WaypointIndex + Settings.LookAhead) do
		local Ahead = Path[Look]
		if Ahead.Action == Enum.PathWaypointAction.Jump or Path[Look - 1].Action == Enum.PathWaypointAction.Jump then
			break
		end
		if math.abs(Ahead.Position.Y - Waypoint.Position.Y) > Settings.DirectChaseMaxHeight then
			break
		end
		if not HasClearLine(Enemy, Ahead.Position + Lift, Params) then
			break
		end
		Best = Look
	end
	AI.WaypointIndex = Best
	Humanoid:MoveTo(Path[Best].Position)
	return true
end

-- Walks toward Goal, straight if it can, along a path if not.
local function MoveTowards(Enemy, Goal: Vector3, Target: Player?)
	local Settings = EnemyAI.Settings
	local AI = Enemy.AI
	local Humanoid = Enemy.Humanoid
	local Root = Enemy.Root
	local Now = os.clock()
	AI.Moving = true

	local Params = MapParams(Enemy)
	local Offset = Goal - Root.Position
	local Direct = Offset.Magnitude <= Settings.DirectChaseDistance
		and math.abs(Offset.Y) <= Settings.DirectChaseMaxHeight
		and HasClearLine(Enemy, Goal, Params)
		and HasFloorAlong(Enemy, Goal, Params)

	if Direct or Enemy.Data.DirectChaseOnly or not EnemyData.Shared.UsePathfinding then
		AI.Path = nil
		Humanoid:MoveTo(Goal)
	else
		-- A new path only when the goal has really moved, so the route
		-- does not flicker every half second.
		local Stale = not AI.Path or not AI.PathGoal or (Goal - AI.PathGoal).Magnitude > Settings.RepathMoveThreshold
			or AI.WaypointIndex > #AI.Path
		if Now >= (AI.NextRepathAt or 0) and Stale then
			AI.NextRepathAt = Now + EnemyData.Shared.RepathRate * (0.8 + math.random() * 0.4)
			ComputePath(Enemy, Goal)
		end
		if not FollowPath(Enemy, Params) then
			if (AI.PathFails or 0) >= 2 and Target then
				-- No path at all: the target is somewhere feet cannot go.
				AI.Unreachable[Target] = Now + Settings.UnreachableTime
				AI.PathFails = 0
			end
			-- Never walk blind off a ledge while waiting for a path.
			if HasFloorAlong(Enemy, Goal, Params) then
				Humanoid:MoveTo(Goal)
			else
				Humanoid:Move(Vector3.zero)
			end
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
		AI.PathGoal = nil
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

-- How many enemies may swing at one player at once.
local function MaxSwingers(): number
	local Run = RunConfig.IsSet() and RunConfig.Get() or nil
	local FromDifficulty = Run and Run.Difficulty and Run.Difficulty.MeleeAttackers
	return FromDifficulty or EnemyAI.Settings.MaxMeleeAttackers
end

-- Whether this enemy has to wait its turn before a close attack on
-- Target. Bosses never wait.
function EnemyAI.MustWaitTurn(Enemy, Target: Player?): boolean
	if not Target or Enemy.Data.IsBoss then
		return false
	end
	return (SwingCounts[Target] or 0) >= MaxSwingers()
end

-- The highest priority attack the target is in range of that is off
-- cooldown. Unreachable limits it to attacks that do not need feet,
-- and a close attack waits while enough others are already swinging.
function EnemyAI.ChooseAttack(Enemy, Distance: number, Unreachable: boolean, Target: Player?): string?
	local BestName, BestPriority = nil, -math.huge
	local Waiting = EnemyAI.MustWaitTurn(Enemy, Target)
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
		if Waiting and CloseKinds[Kind] then
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
		-- a hit in reach counts as melee unless the attack says otherwise
		DamageType = Attack.DamageType or "Melee",
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
			DamageType = Attack.DamageType,
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
	local AI = Enemy.AI or {}
	local Humanoid = Enemy.Humanoid
	local BaseSpeed = Enemy.BaseWalkSpeed or Enemy.Data.WalkSpeed

	Enemy.Busy = true
	-- counted by the think loop so enemies take turns swinging at one player
	AI.AttackKind = Kind
	AI.AttackTarget = Target
	local function Done()
		AI.AttackKind = nil
		AI.AttackTarget = nil
		Enemy.Busy = false
	end

	-- a melee swing keeps stepping in (see below), everything else plants
	if Kind == "Melee" then
		Humanoid.WalkSpeed = BaseSpeed * Settings.WindUpStepSpeed
	else
		Stop(Enemy)
	end
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
					Done()
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
			Done()
			return
		end

		-- Melee keeps turning to follow a target that moves during the
		-- wind up, so a swing is only dodged by getting out of reach,
		-- and keeps closing in slowly so it never stops dead mid chase.
		local Ends = os.clock() + WindUp
		while os.clock() < Ends do
			if Enemy.IsDead or Enemy.IsStunned then
				Humanoid.WalkSpeed = BaseSpeed
				Done()
				return
			end
			local Root = Target and EnemyAI.GetPlayerRoot(Target)
			if Root and (Kind == "Melee" or Kind == "Ranged") then
				EnemyAI.Face(Enemy, Root.Position)
			end
			if Root and Kind == "Melee" then
				local Flat = (Root.Position - Enemy.Root.Position) * Vector3.new(1, 0, 1)
				if Flat.Magnitude > Attack.Range * 0.55 then
					Humanoid:MoveTo(Root.Position - Flat.Unit * Attack.Range * 0.45)
				else
					Humanoid:Move(Vector3.zero)
					Humanoid:MoveTo(Enemy.Root.Position)
				end
			end
			task.wait(0.05)
		end
		if Kind == "Melee" then
			Humanoid.WalkSpeed = BaseSpeed
		end
		if Enemy.IsDead or Enemy.IsStunned then
			Done()
			return
		end

		-- The lunge: a jump forward as the swing comes out, if the
		-- target has got most of the way out of reach.
		local Root = Target and EnemyAI.GetPlayerRoot(Target)
		if Kind == "Melee" and Attack.Lunge and Root then
			local Flat = (Root.Position - Enemy.Root.Position) * Vector3.new(1, 0, 1)
			if Flat.Magnitude > Attack.Range * 0.75 then
				-- A burst of speed straight at the target for a moment.
				local Lunge = Attack.Lunge
				Humanoid.WalkSpeed = Lunge.Speed
				Humanoid:MoveTo(Enemy.Root.Position + Flat.Unit * math.min(Flat.Magnitude, Lunge.Speed * (Lunge.Time or 0.12) + 2))
				task.wait(Lunge.Time or 0.12)
				if not Enemy.IsDead and not Enemy.IsStunned then
					Humanoid.WalkSpeed = BaseSpeed
				end
			end
		end
		if Kind == "Melee" then
			Stop(Enemy)
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
		-- after a swing, step back and to one side so the next enemy in
		-- line gets its turn and this one is not a statue to hit
		local BackOff = Enemy.Data.BackOffTime or Settings.BackOffTime
		if Kind == "Melee" and BackOff > 0 and not Enemy.Data.IsBoss then
			AI.BackOffUntil = os.clock() + BackOff
			AI.BackOffSide = math.random() < 0.5 and -1 or 1
		end
		Done()
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
			-- which side of the target this enemy comes in from, -1 to 1 of FlankMaxAngle
			Flank = math.random() * 2 - 1,
			Separation = Vector3.zero,
		}
	end
	return Enemy.AI
end

-- Turns a flat direction round the vertical by Angle radians.
local function Turn(Direction: Vector3, Angle: number): Vector3
	local C, S = math.cos(Angle), math.sin(Angle)
	return Vector3.new(Direction.X * C - Direction.Z * S, 0, Direction.X * S + Direction.Z * C)
end

-- Every enemy's push away from the others near it, worked out once a
-- tick for all of them. Enemies do not collide with each other, so
-- without this a crowd walks into one spot.
local function UpdateSeparation(Alive: { any })
	local Settings = EnemyAI.Settings
	local Positions = {}
	local Radii = {}
	for Index, Enemy in ipairs(Alive) do
		if Enemy.Root.Parent and not Enemy.IsDead then
			Positions[Index] = Enemy.Root.Position
			Radii[Index] = Settings.SeparationRadius * ScaleOf(Enemy)
		end
	end
	for Index, Enemy in ipairs(Alive) do
		local Mine = Positions[Index]
		if Mine and Enemy.AI then
			local Push = Vector3.zero
			for Other, Theirs in pairs(Positions) do
				if Other ~= Index then
					local Offset = (Mine - Theirs) * Vector3.new(1, 0, 1)
					local Distance = Offset.Magnitude
					local Radius = math.max(Radii[Index], Radii[Other])
					if Distance < Radius then
						if Distance < 0.05 then
							Offset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
							Distance = math.max(Offset.Magnitude, 0.01)
						end
						Push += (Offset / Distance) * (1 - Distance / Radius)
					end
				end
			end
			if Push.Magnitude > 1 then
				Push = Push.Unit
			end
			Enemy.AI.Separation = Push
		end
	end
end

-- One decision for one enemy.
function EnemyAI.Think(Enemy)
	if Enemy.IsDead or Enemy.Stationary or not Enemy.Root.Parent then
		return
	end
	local Settings = EnemyAI.Settings
	local AI = EnsureState(Enemy)
	local Now = os.clock()

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
		AI.PathGoal = nil
		AI.NextRepathAt = 0
	end
	local TargetRoot = Target and EnemyAI.GetPlayerRoot(Target)
	if not TargetRoot then
		if AI.Moving then
			Stop(Enemy)
		end
		FreeTurn(Enemy)
		return
	end

	-- a heavy hit makes it stagger for a moment
	if Now < (Enemy.FlinchUntil or 0) then
		Enemy.Humanoid:Move(Vector3.zero)
		Enemy.Humanoid:MoveTo(Enemy.Root.Position)
		AI.Moving = false
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

	local Away = Enemy.Root.Position - TargetRoot.Position
	Away = Vector3.new(Away.X, 0, Away.Z)
	local Separation = AI.Separation * Settings.SeparationWeight

	-- straight after a swing: step back and to the side, still facing
	if Now < (AI.BackOffUntil or 0) and Away.Magnitude > 0.1 then
		local Side = Vector3.new(-Away.Z, 0, Away.X).Unit * (AI.BackOffSide or 1)
		MoveTowards(Enemy, Enemy.Root.Position + Away.Unit * 5 + Side * 5 + Separation, nil)
		EnemyAI.Face(Enemy, TargetRoot.Position)
		return
	end

	local Unreachable = IsUnreachable(Enemy, Target)
	local AttackName = EnemyAI.ChooseAttack(Enemy, Distance, Unreachable, Target)
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
	local Desired = MeleeRange * Settings.SurroundFraction
	local Preferred = Enemy.Data.PreferredDistance
	if Preferred and Preferred > 0 then
		Desired = Preferred
	end
	if type(Enemy.DesiredRange) == "function" then
		Desired = Enemy:DesiredRange(Target, Distance) or Desired
	end
	-- enough others are already swinging at this player: hold just out
	-- of reach and circle, ready to step in when one backs off
	local Waiting = Melee ~= nil and EnemyAI.MustWaitTurn(Enemy, Target) and Desired < MeleeRange
	if Waiting then
		Desired = MeleeRange + Settings.WaitRingExtra
	end

	if Distance > Desired + 1.5 then
		-- Come in from this enemy's own side: aim at a point off to the
		-- side of the target while far away, easing to straight on as
		-- it gets close, so a room closes in from several directions.
		local Bearing = Away.Magnitude > 0.1 and Away.Unit or Vector3.new(math.cos(AI.Angle), 0, math.sin(AI.Angle))
		local Far = math.clamp((Distance - Desired) / Settings.FlankFullDistance, 0, 1)
		local Slot = Turn(Bearing, AI.Flank * Settings.FlankMaxAngle * Far)
		local SlotRadius = Desired + math.min((Distance - Desired) * 0.5, Settings.FlankRadius * Far)
		-- Aim a little ahead of a moving target, so running in a
		-- straight line does not leave the enemy behind.
		local Lead = TargetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * math.clamp(Distance / 60, 0, 0.5)
		local Goal = TargetRoot.Position + Slot * SlotRadius + Lead + Separation
		if Unreachable then
			-- Stand under them and wait.
			Goal = Vector3.new(TargetRoot.Position.X, Enemy.Root.Position.Y, TargetRoot.Position.Z) + Slot * math.min(Desired, 6) + Separation
		end
		FreeTurn(Enemy)
		MoveTowards(Enemy, Goal, Target)
	elseif Distance < Desired - 3 and Away.Magnitude > 0.1 then
		-- Too close for comfort, back off, circling as it goes.
		local Side = Vector3.new(-Away.Z, 0, Away.X).Unit * AI.StrafeSign
		MoveTowards(Enemy, Enemy.Root.Position + Away.Unit * 8 + Side * 4 + Separation, nil)
		EnemyAI.Face(Enemy, TargetRoot.Position)
	elseif ((Enemy.Data.StrafeSpeed or 0) > 0 or Waiting or Separation.Magnitude > 2) and Away.Magnitude > 0.1 then
		-- Circle the target at the range it likes, changing direction
		-- now and then, so it is never a still target. Waiting enemies
		-- and ones pressed by the crowd drift round too.
		if Now >= AI.NextStrafeFlip then
			AI.StrafeSign = -AI.StrafeSign
			AI.NextStrafeFlip = Now + 1.2 + math.random() * 2
		end
		local Speed = (Enemy.Data.StrafeSpeed or 0) > 0 and Enemy.Data.StrafeSpeed or 0.5
		local Side = Vector3.new(-Away.Z, 0, Away.X).Unit * AI.StrafeSign
		MoveTowards(Enemy, Enemy.Root.Position + Side * 10 * Speed + Separation, nil)
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

	EnemyBase.Died:Connect(function(Enemy)
		local Align = Enemy.Root and Enemy.Root:FindFirstChild("AIFacing")
		if Align then
			Align.Enabled = false
		end
	end)

	task.spawn(function()
		while Running do
			local Alive = EnemyBase.GetAlive()
			-- Who is going for whom, for the crowd penalty, and who is
			-- mid swing at whom, for taking turns.
			local Counts = {}
			local Swings = {}
			for _, Enemy in ipairs(Alive) do
				EnsureState(Enemy)
				if Enemy.Target then
					Counts[Enemy.Target] = (Counts[Enemy.Target] or 0) + 1
				end
				local AI = Enemy.AI
				if Enemy.Busy and AI.AttackTarget and AI.AttackKind and CloseKinds[AI.AttackKind] then
					Swings[AI.AttackTarget] = (Swings[AI.AttackTarget] or 0) + 1
				end
			end
			TargetCounts = Counts
			SwingCounts = Swings
			local Ok, Error = pcall(UpdateSeparation, Alive)
			if not Ok then
				warn("[EnemyAI] separation failed: " .. tostring(Error))
			end
			for _, Enemy in ipairs(Alive) do
				local ThinkOk, ThinkError = pcall(EnemyAI.Think, Enemy)
				if not ThinkOk then
					warn("[EnemyAI] " .. tostring(Enemy.TypeName) .. " think failed: " .. tostring(ThinkError))
				end
			end
			task.wait(EnemyData.Shared.ThinkRate)
		end
	end)
end

return EnemyAI
