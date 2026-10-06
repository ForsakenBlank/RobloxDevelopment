--[[
	CollisionController

	Lets the player's own dash and slide go straight through enemies.
	While the character has the dashing or sliding attribute set, every
	part of it is moved into the pass through collision group, which
	does not collide with enemies, and back into the normal player group
	once the move ends and the player is clear of every enemy.

	Without this a dash on the ground stopped dead the moment it met an
	enemy, which in a fight is most of the time. In the air it was fine
	because the dash went over them.

	The character is simulated on this client (the client owns its
	physics), so changing the groups here is all it takes. The server
	never needs to know.
]]

--[[
	What connects to this

	Reads:
	  The "dashing" attribute set by ReplicatedStorage.Modules.Movement.
	  Dash and the "sliding" attribute set by Movement.Slide, on the
	  local character.

	Uses:
	  The collision groups Server.Game.Enemies.EnemySpawner registers
	  (also saved in the place so they exist before the server starts):
	  "Players", "PlayersPassThrough" and "Enemies". EnemySpawner puts
	  every character in "Players" and keeps new parts in it.
	  workspace.Runtime.Enemies, to check the player is clear of every
	  enemy before going solid again.

	Started by:
	  ClientGame.ClientMain, which also hands it each new character.
]]

local CollisionController = {}

CollisionController.Settings = {
	NormalGroup = "Players",
	PassThroughGroup = "PlayersPassThrough",
	-- Character attributes that mean "going through enemies".
	Attributes = { "dashing", "sliding" },
	-- Seconds between checks for being clear of enemies after the move
	-- ends, and the longest it waits before going solid anyway.
	ExitCheckRate = 0.1,
	ExitMaxWait = 1,
	-- Studs round the root that must be free of enemies.
	ClearRadius = 2.5,
	EnemiesFolder = { "Runtime", "Enemies" },
}

local Character: Model? = nil
local Passing = false
-- Bumped on every change, so an older exit check stops.
local Token = 0
local Connections: { RBXScriptConnection } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function SetGroup(Model: Model, Group: string)
	for _, Descendant in ipairs(Model:GetDescendants()) do
		if Descendant:IsA("BasePart") then
			Descendant.CollisionGroup = Group
		end
	end
end

local function IsMoving(Model: Model): boolean
	for _, Name in ipairs(CollisionController.Settings.Attributes) do
		if Model:GetAttribute(Name) == true then
			return true
		end
	end
	return false
end

local function EnemiesFolder(): Instance?
	local Current: Instance? = workspace
	for _, Name in ipairs(CollisionController.Settings.EnemiesFolder) do
		Current = Current and Current:FindFirstChild(Name)
	end
	return Current
end

-- Whether an enemy is close enough that going solid would wedge the
-- player inside it.
local function InsideEnemy(Model: Model): boolean
	local Root = Model:FindFirstChild("HumanoidRootPart")
	local Folder = EnemiesFolder()
	if not Root or not Folder then
		return false
	end
	local Params = OverlapParams.new()
	Params.FilterType = Enum.RaycastFilterType.Include
	Params.FilterDescendantsInstances = { Folder }
	return #workspace:GetPartBoundsInRadius((Root :: BasePart).Position, CollisionController.Settings.ClearRadius, Params) > 0
end

local function Refresh()
	local Model = Character
	if not Model then
		return
	end
	local Settings = CollisionController.Settings
	Token += 1
	if IsMoving(Model) then
		if not Passing then
			Passing = true
			SetGroup(Model, Settings.PassThroughGroup)
		end
		return
	end
	if not Passing then
		return
	end
	-- The move ended: go solid again once clear of every enemy.
	local MyToken = Token
	task.spawn(function()
		local Waited = 0
		while Waited < Settings.ExitMaxWait and InsideEnemy(Model) do
			task.wait(Settings.ExitCheckRate)
			Waited += Settings.ExitCheckRate
			if MyToken ~= Token or Model ~= Character then
				return
			end
		end
		if MyToken ~= Token or Model ~= Character then
			return
		end
		Passing = false
		SetGroup(Model, Settings.NormalGroup)
	end)
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

function CollisionController.OnCharacter(NewCharacter: Model)
	for _, Connection in ipairs(Connections) do
		Connection:Disconnect()
	end
	table.clear(Connections)
	Character = NewCharacter
	Passing = false
	Token += 1
	for _, Name in ipairs(CollisionController.Settings.Attributes) do
		table.insert(Connections, NewCharacter:GetAttributeChangedSignal(Name):Connect(Refresh))
	end
end

-- Nothing to set up: ClientMain hands over the character, including
-- one that already exists.
function CollisionController.Init() end

return CollisionController
