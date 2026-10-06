--[[
	HitDetection

	Works out what an attack actually hit. It is given a shape, so a box
	for a sword slash, a sphere for an area attack, or a ray for a bullet,
	and gives back the list of enemies or players inside it.

	Keeping this separate from the weapons means every weapon uses the
	same hit rules, and a hitbox bug gets fixed once instead of four
	times. It also means the hitboxes can be drawn on screen for testing
	from one place.

	Uses the newer spatial query calls with an OverlapParams rather than
	GetTouchingParts, because the parts are not always touching on the
	frame the attack fires, and Region3 is deprecated.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Combat.Weapons.Sword for both its slash and its area
	  attack, Shotgun for its burst, and Server.Game.Combat.Abilities.
	  StunSlam for its area on landing.
	  Server.Game.Combat.ProjectileService when a projectile needs an
	  explosion radius rather than a single hit.
	  Server.Game.Enemies.Types.Noob, Bob and Necromancer for their melee
	  attacks, so enemy hits use the same rules as player hits.

	Passes results to:
	  Server.Game.Combat.DamageService, which is what turns a hit into
	  actual damage. This module never changes health itself, it only
	  reports what was hit.

	Needs to know about:
	  Server.Game.Enemies.EnemyBase for the list of living enemy models,
	  which is what the filter is built from rather than searching the
	  whole workspace.
	  The players, so an attack can be told to hit enemies only. Enemy
	  attacks hit players only. Friendly fire between players is off.

	The map in workspace.MainGameObj and workspace.Map has a lot of parts
	in it, so the OverlapParams filter matters for performance. Whitelist
	the enemy folder and the character models rather than blacklisting
	scenery, which would mean testing against hundreds of parts every
	swing.

	Client side hit detection is not used here. The hitbox packet exists
	in the movement framework's namespace, but for this game the hits
	should be worked out on the server so they cannot be faked.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local EnemyBase = require(script.Parent.Parent.Enemies.EnemyBase)

local HitDetection = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

HitDetection.Settings = {
	-- How the debug hitboxes look when GameConfig.Debug.ShowHitboxes
	-- is on.
	DebugColour = Color3.fromRGB(255, 80, 80),
	DebugTransparency = 0.6,
	DebugDuration = 0.35,
	-- Line of sight rays are cast from this many studs above the
	-- attacker's root, roughly chest height, so a low wall does not
	-- block a hit on a tall enemy.
	LineOfSightHeight = 1,
	-- The map is "everything in the workspace that is not one of
	-- these". The spawn floor and the scenery are loose in the
	-- workspace rather than under MainGameObj, so an include list
	-- would miss them. Folders named here, plus every character and
	-- enemy, are left out of map rays. Paths use "/" for nesting.
	NonMapFolders = { "Runtime/Projectiles", "Effects", "Animations" },
}

-- Resolves the NonMapFolders paths to instances that exist.
local function NonMapInstances(): { Instance }
	local List = {}
	for _, Path in ipairs(HitDetection.Settings.NonMapFolders) do
		local Current: Instance? = workspace
		for Segment in string.gmatch(Path, "[^/]+") do
			Current = Current and Current:FindFirstChild(Segment) or nil
		end
		if Current then
			table.insert(List, Current)
		end
	end
	return List
end

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Every model an attack from Side could hit. "Enemies" gives the
-- living enemies, "Players" the living player characters.
local function GetTargetModels(Side: string): { Model }
	if Side == "Players" then
		local Models = {}
		for _, Player in ipairs(Players:GetPlayers()) do
			local Character = Player.Character
			local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
			-- Spectators (dead players waiting for a revive) cannot be
			-- hit, see PlayerStats.
			if Humanoid and Humanoid.Health > 0 and not Character:GetAttribute("Spectating") then
				table.insert(Models, Character)
			end
		end
		return Models
	end
	return EnemyBase.GetAliveModels()
end

local function RootOf(Model: Model): BasePart?
	return Model:FindFirstChild("HumanoidRootPart") or Model.PrimaryPart
end

-- The model a hit part belongs to, if it is one of the targets.
local function ModelFor(Part: BasePart, Targets: { Model }): Model?
	for _, Model in ipairs(Targets) do
		if Part == Model or Part:IsDescendantOf(Model) then
			return Model
		end
	end
	return nil
end

local function DrawBox(At: CFrame, Size: Vector3)
	local Settings = HitDetection.Settings
	local Part = Instance.new("Part")
	Part.Anchored = true
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.Size = Size
	Part.CFrame = At
	Part.Color = Settings.DebugColour
	Part.Transparency = Settings.DebugTransparency
	Part.Material = Enum.Material.Neon
	Part.Parent = workspace:FindFirstChild("Runtime") or workspace
	Debris:AddItem(Part, Settings.DebugDuration)
end

local function DrawSphere(At: Vector3, Radius: number)
	local Settings = HitDetection.Settings
	local Part = Instance.new("Part")
	Part.Shape = Enum.PartType.Ball
	Part.Anchored = true
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.Size = Vector3.new(Radius * 2, Radius * 2, Radius * 2)
	Part.Position = At
	Part.Color = Settings.DebugColour
	Part.Transparency = Settings.DebugTransparency
	Part.Material = Enum.Material.Neon
	Part.Parent = workspace:FindFirstChild("Runtime") or workspace
	Debris:AddItem(Part, Settings.DebugDuration)
end

-- Everything a map ray should ignore: the effect and runtime folders,
-- every player character and every enemy model, plus Extra.
function HitDetection.GetWorldExclusions(Extra: { Instance }?): { Instance }
	local List: { Instance } = NonMapInstances()
	if workspace.CurrentCamera then
		table.insert(List, workspace.CurrentCamera)
	end
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player.Character then
			table.insert(List, Player.Character)
		end
	end
	for _, Model in ipairs(EnemyBase.GetAliveModels()) do
		table.insert(List, Model)
	end
	if Extra then
		for _, Item in ipairs(Extra) do
			table.insert(List, Item)
		end
	end
	return List
end

-- The NonMapFolders that currently exist, for callers building their
-- own filter.
function HitDetection.GetNonMapInstances(): { Instance }
	return NonMapInstances()
end

-- RaycastParams that hit only the map.
function HitDetection.MapRaycastParams(Extra: { Instance }?): RaycastParams
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = HitDetection.GetWorldExclusions(Extra)
	return Params
end

-- Whether nothing in the map sits between From and the target.
local function HasLineOfSight(From: Vector3, Target: Model): boolean
	local Root = RootOf(Target)
	if not Root then
		return false
	end
	local Direction = Root.Position - From
	local Hit = workspace:Raycast(From, Direction, HitDetection.MapRaycastParams())
	return Hit == nil
end

-- Turns a list of hit parts into a sorted, deduplicated list of hit
-- records, applying the options.
local function Collect(Parts: { BasePart }, Targets: { Model }, Origin: Vector3, Options): { any }
	local Seen: { [Model]: boolean } = {}
	local Hits = {}

	for _, Part in ipairs(Parts) do
		local Model = ModelFor(Part, Targets)
		if Model and not Seen[Model] then
			Seen[Model] = true
			local Root = RootOf(Model)
			local Position = Root and Root.Position or Part.Position
			local Excluded = Options.Exclude and table.find(Options.Exclude, Model) ~= nil
			if not Excluded then
				if not Options.RequireLineOfSight or HasLineOfSight(Origin, Model) then
					table.insert(Hits, {
						Model = Model,
						Position = Position,
						Distance = (Position - Origin).Magnitude,
						Part = Part,
					})
				end
			end
		end
	end

	table.sort(Hits, function(A, B)
		return A.Distance < B.Distance
	end)

	if Options.MaxTargets and #Hits > Options.MaxTargets then
		for Index = #Hits, Options.MaxTargets + 1, -1 do
			Hits[Index] = nil
		end
	end

	return Hits
end

----------------------------------------------------------------------
-- QUERIES
----------------------------------------------------------------------

-- Options for every query:
--   Side                "Enemies" (default) or "Players"
--   MaxTargets          keep only the closest N. nil is everything
--   Exclude             list of models to ignore, the attacker say
--   RequireLineOfSight  drop targets the map blocks from Origin
--   Radius              Ray only, the thickness of the shot in studs
-- Every hit is { Model, Position, Distance, Part }, closest first.

-- A box, for a melee swing. At is the box centre and orientation.
function HitDetection.Box(At: CFrame, Size: Vector3, Options: { [string]: any }?): { any }
	Options = Options or {}
	local Targets = GetTargetModels(Options.Side or "Enemies")
	if #Targets == 0 then
		return {}
	end

	local Params = OverlapParams.new()
	Params.FilterType = Enum.RaycastFilterType.Include
	Params.FilterDescendantsInstances = Targets

	if GameConfig.Debug.ShowHitboxes then
		DrawBox(At, Size)
	end

	local Parts = workspace:GetPartBoundsInBox(At, Size, Params)
	return Collect(Parts, Targets, Options.Origin or At.Position, Options)
end

-- A sphere, for an area attack or an explosion.
function HitDetection.Sphere(At: Vector3, Radius: number, Options: { [string]: any }?): { any }
	Options = Options or {}
	local Targets = GetTargetModels(Options.Side or "Enemies")
	if #Targets == 0 then
		return {}
	end

	local Params = OverlapParams.new()
	Params.FilterType = Enum.RaycastFilterType.Include
	Params.FilterDescendantsInstances = Targets

	if GameConfig.Debug.ShowHitboxes then
		DrawSphere(At, Radius)
	end

	local Parts = workspace:GetPartBoundsInRadius(At, Radius, Params)
	return Collect(Parts, Targets, Options.Origin or At, Options)
end

-- A ray, for a hitscan shot. Stops at the first thing hit, map or
-- target. Returns the single hit record or nil, plus the point the
-- ray ended so a tracer can be drawn to it.
function HitDetection.Ray(Origin: Vector3, Direction: Vector3, MaxDistance: number, Options: { [string]: any }?): (any?, Vector3)
	Options = Options or {}
	local Side = Options.Side or "Enemies"
	local Targets = GetTargetModels(Side)

	-- Exclude everything that is not map or a target: the other side,
	-- the effect folders and anything the caller asked to skip. What
	-- is left is either a target or the map, and the ray stops at the
	-- first of either.
	local Exclusions = {}
	for _, Model in ipairs(GetTargetModels(Side == "Enemies" and "Players" or "Enemies")) do
		table.insert(Exclusions, Model)
	end
	if Options.Exclude then
		for _, Model in ipairs(Options.Exclude) do
			table.insert(Exclusions, Model)
		end
	end
	for _, Folder in ipairs(NonMapInstances()) do
		table.insert(Exclusions, Folder)
	end
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = Exclusions

	local Unit = Direction.Magnitude > 0 and Direction.Unit or Vector3.new(0, 0, -1)
	local Result = workspace:Raycast(Origin, Unit * MaxDistance, Params)

	-- A thick shot: the ray above still decides where walls stop it,
	-- then a sphere of Options.Radius is swept against the targets and
	-- wins if it hits one before that wall.
	if Options.Radius and Options.Radius > 0 and #Targets > 0 then
		local Include = {}
		for _, Model in ipairs(Targets) do
			if not (Options.Exclude and table.find(Options.Exclude, Model)) then
				table.insert(Include, Model)
			end
		end
		local TargetParams = RaycastParams.new()
		TargetParams.FilterType = Enum.RaycastFilterType.Include
		TargetParams.FilterDescendantsInstances = Include
		local Sweep = workspace:Spherecast(Origin, Options.Radius, Unit * MaxDistance, TargetParams)
		local WallDistance = math.huge
		if Result and not ModelFor(Result.Instance, Targets) then
			WallDistance = Result.Distance
		end
		if Sweep and Sweep.Distance <= WallDistance then
			Result = Sweep
		end
	end

	local EndPoint = Result and Result.Position or (Origin + Unit * MaxDistance)

	if GameConfig.Debug.ShowHitboxes then
		local Length = (EndPoint - Origin).Magnitude
		DrawBox(CFrame.lookAt(Origin, EndPoint) * CFrame.new(0, 0, -Length / 2), Vector3.new(0.2, 0.2, Length))
	end

	if not Result then
		return nil, EndPoint
	end

	local Model = ModelFor(Result.Instance, Targets)
	if not Model then
		return nil, EndPoint
	end

	return {
		Model = Model,
		Position = Result.Position,
		Distance = (Result.Position - Origin).Magnitude,
		Part = Result.Instance,
	}, EndPoint
end

-- The models an attack from Side can hit, for anything that wants to
-- build its own query.
function HitDetection.GetTargets(Side: string?): { Model }
	return GetTargetModels(Side or "Enemies")
end

return HitDetection
