local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Pocket = require(ReplicatedStorage.Modules.Shared.Pocket)

local Models = ReplicatedStorage.Assets.Models
local TrailTemplate = Models:WaitForChild("Trail")

local TrailHandler = {}
local cache = {}

local MAX_AIR_TIME = 1.2
local ATT0_NAME = "JumpTrailAttachment0"
local ATT1_NAME = "JumpTrailAttachment1"
local TRAIL_NAME = "JumpTrail"
local FOLDER_NAME = "JumpTrailFolder"
local TEMP_ATTR = "JumpTrailTempAttachment"

local DEFAULT_LIMBS = {"Right Leg", "Left Leg", "Right Arm", "Left Arm"}

TrailHandler.__index = TrailHandler

export type TrailHandler = typeof(setmetatable({} :: {
	character : Model,
	humanoid : Humanoid,
	_pocket : Pocket.Pocket,
	_airborne : boolean,
	_timeout : thread?,
	_limbs : {string},
}, TrailHandler))

local function getLimb(character : Model, name : string) : BasePart?
	return character:FindFirstChild(name) :: BasePart
end

local function ensureAttachments(limb : BasePart)
	local att0 = limb:FindFirstChild(ATT0_NAME) :: Attachment
	local att1 = limb:FindFirstChild(ATT1_NAME) :: Attachment

	if not att0 then
		att0 = Instance.new("Attachment")
		att0.Name = ATT0_NAME
		att0.Position = Vector3.new(0, 0.5, 0)
		att0:SetAttribute(TEMP_ATTR, true)
		att0.Parent = limb
	end
	if not att1 then
		att1 = Instance.new("Attachment")
		att1.Name = ATT1_NAME
		att1.Position = Vector3.new(0, -0.5, 0)
		att1:SetAttribute(TEMP_ATTR, true)
		att1.Parent = limb
	end

	return att0, att1
end

local function addTrailToLimb(limb : BasePart)
	if not limb or not TrailTemplate or not TrailTemplate:IsA("Folder") then
		return
	end
	if limb:FindFirstChild(FOLDER_NAME) or limb:FindFirstChild(TRAIL_NAME) then
		return
	end

	local folderClone = TrailTemplate:Clone()
	folderClone.Name = FOLDER_NAME
	folderClone.Parent = limb

	local templateAttachments = {}
	for _, inst in folderClone:GetDescendants() do
		if inst:IsA("Attachment") then
			inst.Parent = limb
			inst:SetAttribute(TEMP_ATTR, true)
			table.insert(templateAttachments, inst)
		end
	end

	local att0, att1
	if #templateAttachments >= 2 then
		att0, att1 = templateAttachments[1], templateAttachments[2]
	else
		att0, att1 = ensureAttachments(limb)
	end

	for _, inst in folderClone:GetDescendants() do
		if inst:IsA("Trail") then
			inst.Name = TRAIL_NAME
			inst.Attachment0 = att0
			inst.Attachment1 = att1
			inst.Enabled = true
			inst.Parent = limb
			break
		end
	end
end

local function removeTrailFromLimb(limb : BasePart)
	if not limb then
		return
	end

	local trail = limb:FindFirstChild(TRAIL_NAME)
	if trail then
		trail:Destroy()
	end

	local folder = limb:FindFirstChild(FOLDER_NAME)
	if folder then
		folder:Destroy()
	end

	for _, child in limb:GetChildren() do
		if child:IsA("Attachment") and child:GetAttribute(TEMP_ATTR) then
			child:Destroy()
		end
	end
end

function TrailHandler.new(character : Model, humanoid : Humanoid, limbs : {string}?) : TrailHandler
	if cache[character] then
		return cache[character]
	end

	local self = setmetatable({}, TrailHandler)
	
	self.character = character
	self.humanoid = humanoid
	self._pocket = Pocket.new()
	self._airborne = false
	self._timeout = nil
	self._limbs = limbs or DEFAULT_LIMBS

	self:_bind()

	cache[character] = self

	return self
end

function TrailHandler:_bind() : TrailHandler
	
	self._pocket:add(self.character:GetAttributeChangedSignal("state"):Connect(function()
		local state = self.character:GetAttribute("state")

		if state == "running" then
			self:_addTrails()
			self:_startFailsafe()
		else
			self._airborne = false
			self:_cancelFailsafe()
			self:_removeTrails()
		end
	end))
	
	self._pocket:add(self.humanoid.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping or newState == Enum.HumanoidStateType.Freefall then
			if not self._airborne then
				self._airborne = true
				self:_addTrails()
				self:_startFailsafe()
			end
			return
		end

		if newState == Enum.HumanoidStateType.Landed and self._airborne then
			self._airborne = false
			self:_cancelFailsafe()
			self:_removeTrails()
		end
	end))

	self.humanoid.Died:Once(function()
		self:_cancelFailsafe()
		self:_removeTrails()
		self:destroy()
	end)

	self._pocket:add(self.character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:_cancelFailsafe()
			self:_removeTrails()
			self:destroy()
		end
	end))

	return self
end

function TrailHandler:_startFailsafe()
	self:_cancelFailsafe()
	self._timeout = task.delay(MAX_AIR_TIME, function()
		self._airborne = false
		self:_removeTrails()
		self._timeout = nil
	end)
end

function TrailHandler:_cancelFailsafe()
	if self._timeout then
		task.cancel(self._timeout)
		self._timeout = nil
	end
end

function TrailHandler:_addTrails()
	for _, limbName in self._limbs do
		addTrailToLimb(getLimb(self.character, limbName))
	end
end

function TrailHandler:_removeTrails()
	for _, limbName in self._limbs do
		removeTrailFromLimb(getLimb(self.character, limbName))
	end
end

function TrailHandler:destroy()
	self:_cancelFailsafe()
	self._pocket:destroy()
	cache[self.character] = nil
end

return TrailHandler
