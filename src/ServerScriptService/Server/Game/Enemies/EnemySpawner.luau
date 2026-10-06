--[[
	EnemySpawner

	Puts enemies into the world. Given a wave and an area, it works out
	which spawn platforms to use, clones the right model, parents it into
	the world, and creates the class instance that drives it.

	It spreads the spawns across the platforms in that area rather than
	putting everything on one, and if a wave asks for more enemies than
	the area has platforms it reuses them with a small offset so they do
	not spawn inside each other.

	It should also stagger the spawns slightly instead of creating them
	all in the same frame. Creating twenty models at once causes a
	visible hitch, and the design says the game has to hold 60 FPS.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Rooms.WaveManager, one wave at a time, with the area
	  name to spawn in.

	Reads:
	  Game.Data.EnemyData for the model name of each type.
	  workspace.MainGameObj.EnemySpawns, which has a folder per combat
	  area: Room1, Room2, Room3, Room4 and BossRoom. The spawn platforms
	  go in those folders. The boss spawns from BossRoom the same way
	  everything else does.

	Clones from:
	  ServerStorage.Assets.Enemies. Keeping the models in ServerStorage
	  rather than ReplicatedStorage means the client never downloads
	  enemy models it has not met yet.

	Parents into:
	  workspace.Runtime.Enemies, which is separate from
	  workspace.MainGameObj so the built map and the things spawned into
	  it never get mixed up. That also gives one folder to clear when a
	  run ends and one place to count from.

	Builds through:
	  Server.Game.Enemies.EnemyRegistry to turn a type name into a class,
	  then that class through Server.Game.Enemies.EnemyBase.

	Returns the list of enemies it created back to WaveManager, which
	needs them to connect to their died signals for the alive count.

	Spawn platforms should be placed so enemies do not drop into the
	player straight away, and so a wave cannot spawn on top of a player
	who is standing on the platform. Checking the platform is clear
	before using it, and falling back to the next one, is worth doing.

	The models need their collision set up so enemies do not push players
	around or get stuck on each other. A collision group for enemies that
	does not collide with itself is the usual fix, and it also stops a
	spawned wave shoving each other off a platform.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local EnemyData = require(ReplicatedStorage.Modules.Game.Data.EnemyData)
local WaveData = require(ReplicatedStorage.Modules.Game.Data.WaveData)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local EnemyBase = require(script.Parent.EnemyBase)
local EnemyRegistry = require(script.Parent.EnemyRegistry)

local EnemySpawner = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

EnemySpawner.Settings = {
	-- Where spawned enemies go in the workspace.
	RuntimeFolder = "Runtime",
	EnemiesFolder = "Enemies",
	-- Collision groups. Enemies do not collide with each other or
	-- push players. Players still collide with enemies so you cannot
	-- walk through them.
	EnemyGroup = "Enemies",
	PlayerGroup = "Players",
	EnemiesCollideWithEachOther = false,
	EnemiesCollideWithPlayers = true,
	-- The group a player's own client moves their character into while
	-- dashing or sliding (ClientGame.Controllers.CollisionController),
	-- so a dash goes through a crowd instead of stopping dead in it.
	-- It collides with everything the player group does except enemies.
	PassThroughGroup = "PlayersPassThrough",
	-- The group for enemies with CollideWithPlayers = false in
	-- EnemyData (the boss): it only collides with the map.
	GhostGroup = "EnemiesGhost",
	-- Studs above the platform the model is placed, so it drops onto
	-- it rather than spawning inside it.
	SpawnHeight = 3,
	-- When a wave has more enemies than platforms, extra spawns are
	-- offset sideways by up to this many studs.
	ReuseOffsetRadius = 4,
	-- A platform with a player within this many studs is skipped.
	PlayerClearRadius = 8,

	-- Training dummies for testing combat before rooms exist. Spawned
	-- at server start when GameConfig.Debug.TrainingDummies is above 0.
	TrainingDummy = {
		Type = "Noob",
		-- Offset from the SpawnLocation, so they stand in front of it.
		Offset = Vector3.new(18, 3, 0),
		Spacing = 6,
		Stationary = true,
		-- Bring a dead dummy back after this many seconds. 0 leaves it
		-- dead.
		RespawnDelay = 3,
	},
}

local EnemiesFolder: Folder? = nil

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function GetFolder(): Folder
	if EnemiesFolder and EnemiesFolder.Parent then
		return EnemiesFolder
	end
	local Settings = EnemySpawner.Settings
	local Runtime = workspace:FindFirstChild(Settings.RuntimeFolder)
	if not Runtime then
		Runtime = Instance.new("Folder")
		Runtime.Name = Settings.RuntimeFolder
		Runtime.Parent = workspace
	end
	local Folder = Runtime:FindFirstChild(Settings.EnemiesFolder)
	if not Folder then
		Folder = Instance.new("Folder")
		Folder.Name = Settings.EnemiesFolder
		Folder.Parent = Runtime
	end
	EnemiesFolder = Folder
	return Folder
end

local function SetupCollisionGroups()
	local Settings = EnemySpawner.Settings
	local Ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(Settings.EnemyGroup) then
			PhysicsService:RegisterCollisionGroup(Settings.EnemyGroup)
		end
		if not PhysicsService:IsCollisionGroupRegistered(Settings.PlayerGroup) then
			PhysicsService:RegisterCollisionGroup(Settings.PlayerGroup)
		end
		PhysicsService:CollisionGroupSetCollidable(Settings.EnemyGroup, Settings.EnemyGroup, Settings.EnemiesCollideWithEachOther)
		PhysicsService:CollisionGroupSetCollidable(Settings.EnemyGroup, Settings.PlayerGroup, Settings.EnemiesCollideWithPlayers)
		if not PhysicsService:IsCollisionGroupRegistered(Settings.PassThroughGroup) then
			PhysicsService:RegisterCollisionGroup(Settings.PassThroughGroup)
		end
		PhysicsService:CollisionGroupSetCollidable(Settings.PassThroughGroup, Settings.EnemyGroup, false)
		PhysicsService:CollisionGroupSetCollidable(Settings.PassThroughGroup, Settings.PlayerGroup, PhysicsService:CollisionGroupsAreCollidable(Settings.PlayerGroup, Settings.PlayerGroup))
		if not PhysicsService:IsCollisionGroupRegistered(Settings.GhostGroup) then
			PhysicsService:RegisterCollisionGroup(Settings.GhostGroup)
		end
		for _, Other in ipairs({ Settings.EnemyGroup, Settings.PlayerGroup, Settings.PassThroughGroup, Settings.GhostGroup }) do
			PhysicsService:CollisionGroupSetCollidable(Settings.GhostGroup, Other, false)
		end
	end)
	if not Ok then
		warn("[EnemySpawner] could not set up collision groups")
	end
end

local function SetGroup(Model: Model, Group: string)
	for _, Part in ipairs(Model:GetDescendants()) do
		if Part:IsA("BasePart") then
			Part.CollisionGroup = Group
		end
	end
end

local function PlayerNear(Position: Vector3, Radius: number): boolean
	for _, Player in ipairs(Players:GetPlayers()) do
		local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
		if Root and (Root.Position - Position).Magnitude < Radius then
			return true
		end
	end
	return false
end

----------------------------------------------------------------------
-- SPAWNING
----------------------------------------------------------------------

-- Spawns one enemy of a type at a CFrame. Options go through to
-- EnemyBase.new. Returns the enemy object or nil.
function EnemySpawner.SpawnAt(TypeName: string, At: CFrame, Options: { [string]: any }?)
	local Data = EnemyData.Get(TypeName)
	if not Data then
		return nil
	end

	local Template = ServerStorage.Assets.Enemies:FindFirstChild(Data.ModelName)
	if not Template then
		warn("[EnemySpawner] no model called " .. Data.ModelName .. " in ServerStorage.Assets.Enemies")
		return nil
	end

	local Model = Template:Clone()
	Model.Name = TypeName
	SetGroup(Model, Data.CollideWithPlayers == false and EnemySpawner.Settings.GhostGroup or EnemySpawner.Settings.EnemyGroup)
	-- A model taller than a normal one (the boss) is lifted so its feet
	-- land on the spot instead of its legs spawning inside the floor.
	local BoxCFrame, BoxSize = Model:GetBoundingBox()
	local FeetBelowPivot = Model:GetPivot().Position.Y - (BoxCFrame.Position.Y - BoxSize.Y / 2)
	local Lift = math.max(0, FeetBelowPivot - EnemySpawner.Settings.SpawnHeight)
	Model:PivotTo(At + Vector3.new(0, Lift, 0))
	Model.Parent = GetFolder()

	Options = Options or {}
	Options.Class = EnemyRegistry.Get(TypeName)

	local Enemy = EnemyBase.new(TypeName, Model, Options)
	if not Enemy then
		Model:Destroy()
		return nil
	end

	-- The server runs enemy physics. Left to Roblox, ownership moves
	-- to whichever player is closest, and that player's client then
	-- decides where the enemy is, which makes the AI stutter and lets
	-- a modified client drag enemies around.
	pcall(function()
		Enemy.Root:SetNetworkOwner(nil)
	end)

	if GameConfig.Debug.LogWaves then
		print(string.format("[EnemySpawner] spawned %s with %d health", TypeName, Enemy.MaxHealth))
	end

	return Enemy
end

-- The spawn platforms for an area, in the order WaveData asks for.
local function GetPlatforms(AreaName: string, NearPosition: Vector3?): { BasePart }
	local Folder = RoomData.GetFolder("EnemySpawns")
	local AreaFolder = Folder and Folder:FindFirstChild(AreaName)
	local Platforms = {}
	if AreaFolder then
		for _, Child in ipairs(AreaFolder:GetChildren()) do
			if Child:IsA("BasePart") then
				table.insert(Platforms, Child)
			end
		end
	end

	local Order = WaveData.Defaults.PlatformOrder
	if Order == "Sequence" then
		table.sort(Platforms, function(A, B)
			return A.Name < B.Name
		end)
	elseif Order == "Furthest" and NearPosition then
		table.sort(Platforms, function(A, B)
			return (A.Position - NearPosition).Magnitude > (B.Position - NearPosition).Magnitude
		end)
	else
		for Index = #Platforms, 2, -1 do
			local Swap = math.random(Index)
			Platforms[Index], Platforms[Swap] = Platforms[Swap], Platforms[Index]
		end
	end

	return Platforms
end

-- Spawns a whole wave into an area, staggered by the wave's interval.
-- Returns the enemies once they have all been created, so this yields
-- for Count * Interval seconds. OnSpawned(Enemy) is called the moment
-- each one exists, so a caller counting deaths never misses one that
-- dies before the rest of the wave has finished spawning.
-- ShouldStop() is checked between spawns, so a run ending mid wave
-- stops the rest appearing.
function EnemySpawner.SpawnWave(AreaName: string, Wave, OnSpawned: ((any) -> ())?, ShouldStop: (() -> boolean)?): { any }
	local Settings = EnemySpawner.Settings

	-- Nearest player to the area, for the "Furthest" platform order.
	local Nearest = nil
	local Zone = RoomData.GetFolder("RoomZones")
	local ZonePart = Zone and Zone:FindFirstChild(AreaName)
	if ZonePart and ZonePart:IsA("BasePart") then
		local Best = math.huge
		for _, Player in ipairs(Players:GetPlayers()) do
			local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
			if Root then
				local Distance = (Root.Position - ZonePart.Position).Magnitude
				if Distance < Best then
					Best = Distance
					Nearest = Root.Position
				end
			end
		end
	end

	local Platforms = GetPlatforms(AreaName, Nearest)
	if #Platforms == 0 then
		warn("[EnemySpawner] " .. AreaName .. " has no spawn platforms in EnemySpawns, nothing spawned")
		return {}
	end

	local Interval = Wave.Interval or WaveData.Defaults.SpawnInterval
	local Spawned = {}
	local PlatformIndex = 0

	for TypeName, Count in pairs(Wave.Enemies) do
		-- A wave can pin a type to one platform, the boss for instance.
		local Fixed = nil
		local FixedName = Wave.SpawnPoints and Wave.SpawnPoints[TypeName]
		if FixedName then
			for _, Candidate in ipairs(Platforms) do
				if Candidate.Name == FixedName then
					Fixed = Candidate
					break
				end
			end
			if not Fixed then
				warn("[EnemySpawner] " .. AreaName .. " has no spawn platform called " .. tostring(FixedName) .. " for " .. TypeName)
			end
		end
		for _ = 1, Count do
			if ShouldStop and ShouldStop() then
				return Spawned
			end
			-- Next platform that does not have a player stood on it.
			local Platform = Fixed
			if not Platform then
				for _ = 1, #Platforms do
					PlatformIndex = PlatformIndex % #Platforms + 1
					local Candidate = Platforms[PlatformIndex]
					if not PlayerNear(Candidate.Position, Settings.PlayerClearRadius) then
						Platform = Candidate
						break
					end
				end
			end
			Platform = Platform or Platforms[PlatformIndex]

			local Offset = Vector3.new(0, Settings.SpawnHeight, 0)
			if PlatformIndex <= #Spawned then
				local Angle = math.random() * math.pi * 2
				local Radius = math.random() * Settings.ReuseOffsetRadius
				Offset += Vector3.new(math.cos(Angle) * Radius, 0, math.sin(Angle) * Radius)
			end

			local Enemy = EnemySpawner.SpawnAt(TypeName, CFrame.new(Platform.Position + Offset), { AreaName = AreaName })
			if Enemy then
				table.insert(Spawned, Enemy)
				if OnSpawned then
					OnSpawned(Enemy)
				end
			end

			if Interval > 0 then
				task.wait(Interval)
			end
		end
	end

	return Spawned
end

----------------------------------------------------------------------
-- TRAINING DUMMIES
----------------------------------------------------------------------

local function SpawnDummy(Index: number, Origin: Vector3)
	local Config = EnemySpawner.Settings.TrainingDummy
	local Position = Origin + Config.Offset + Vector3.new(0, 0, (Index - 1) * Config.Spacing)
	local Enemy = EnemySpawner.SpawnAt(Config.Type, CFrame.new(Position, Position - Vector3.new(1, 0, 0)), {
		Stationary = Config.Stationary,
	})
	if Enemy and Config.RespawnDelay > 0 then
		Enemy.Died.Event:Once(function()
			task.delay(Config.RespawnDelay, function()
				SpawnDummy(Index, Origin)
			end)
		end)
	end
	return Enemy
end

function EnemySpawner.SpawnTrainingDummies(Count: number)
	local SpawnLocation = workspace:FindFirstChildOfClass("SpawnLocation", true)
	if not SpawnLocation then
		warn("[EnemySpawner] no SpawnLocation to put the training dummies near")
		return
	end
	for Index = 1, Count do
		SpawnDummy(Index, SpawnLocation.Position)
	end
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function EnemySpawner.Init()
	GetFolder()
	SetupCollisionGroups()

	-- Put every player character in the player group so the enemy
	-- rules above apply to them.
	local function OnCharacter(Character: Model)
		SetGroup(Character, EnemySpawner.Settings.PlayerGroup)
		Character.DescendantAdded:Connect(function(Descendant)
			if Descendant:IsA("BasePart") then
				Descendant.CollisionGroup = EnemySpawner.Settings.PlayerGroup
			end
		end)
	end
	Players.PlayerAdded:Connect(function(Player)
		Player.CharacterAdded:Connect(OnCharacter)
		if Player.Character then
			OnCharacter(Player.Character)
		end
	end)
	for _, Player in ipairs(Players:GetPlayers()) do
		Player.CharacterAdded:Connect(OnCharacter)
		if Player.Character then
			OnCharacter(Player.Character)
		end
	end

	local Dummies = GameConfig.Debug.TrainingDummies or 0
	if Dummies > 0 then
		task.defer(EnemySpawner.SpawnTrainingDummies, Dummies)
	end
end

return EnemySpawner
