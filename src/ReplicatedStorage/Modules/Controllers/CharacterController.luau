local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local Pocket = require(ReplicatedStorage.Modules.Shared.Pocket)
local SmartBone = require(ReplicatedStorage.Modules.Visuals.SmartBone)
local Zipline = require(ReplicatedStorage.Modules.Movement.Zipline)

local CharacterController = {}
CharacterController.__index = CharacterController

export type CharacterController = typeof(setmetatable(
	{} :: {},
	CharacterController
))

function CharacterController.new(character: Model, INPUTS: {})
	local self = {}
	self._pocket = Pocket.new()
	self.INPUTS = INPUTS
	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.hrp = character:WaitForChild("HumanoidRootPart")
	self.rootJoint = self.hrp:WaitForChild("RootJoint")
	self.ORIGINALC0 = self.rootJoint.C0
	
	self.player = Players.LocalPlayer :: Player
	self.playergui = self.player:FindFirstChildOfClass("PlayerGui") :: ScreenGui

	setmetatable(self, CharacterController)

	self:main()
	
	return self
end

function CharacterController:main()
	self:bindInputs()
	self:initializeTilt()
	self:clientLogic()
	self:defaultstate()
	self:initalizesmartbones()
	
	self.character:SetAttribute("ziplining", false)
	
	self.character:GetAttributeChangedSignal("ziplining"):Connect(function()
		local Ziplining = self.character:GetAttribute("ziplining")
		local ExitZipline = self.playergui.MOBILE_BUTTONS.ExitZipline

		ExitZipline.Visible = Ziplining
		
		ExitZipline.Base.Activated:Connect(function()
			Zipline:JumpOff(self.character)
		end)
		
	end)
	
	self.humanoid.Died:Once(function()
		self:clean()
	end)
end

function CharacterController:bindInputs()
	for name, value in self.INPUTS do
		
		if name == "SetChar" then
			continue
		end
		
		ContextActionService:BindAction(name, value.Callback, false, value.Keycode)
	end
end

function CharacterController:initializeTilt()
	self._pocket:add(RunService.RenderStepped:Connect(function(step)
		if self.character:GetAttribute("state") ~= "stunned" then
			local DotFrontBack = self.hrp.CFrame.LookVector:Dot(self.humanoid.MoveDirection)
			local DotLeftRight = self.hrp.CFrame.RightVector:Dot(self.humanoid.MoveDirection)
			self.rootJoint.C0 = self.rootJoint.C0:Lerp(self.ORIGINALC0 * CFrame.Angles(DotFrontBack * 0.12, -DotLeftRight * 0.12, 0), 1 - (0.97 ^ (step * 60)))
		end
	end))
end

function CharacterController:clientLogic()
	local function logic(character : Model)
		local rootPart = character.HumanoidRootPart
		local humanoid = character.Humanoid
		local animator : Animator = humanoid.Animator
		
		HelperFunctions.clearVelocity(rootPart, "knockback")
		
		for _, anim in animator:GetPlayingAnimationTracks() do
			if string.find(anim.Name, "hit") or string.find(anim.Name, "Animation") or
				string.find(anim.Name, "Walk") or string.find(anim.Name, "Parried") then
				continue
			end
			
			anim:Stop()
		end

	end
	
	self._pocket:add(self.character:GetAttributeChangedSignal("state"):Connect(function()
		local state = self.character:GetAttribute("state")
		
		if state == "stunned" or state == "ragdolled" then
			logic(self.character)
		end
	end))
end

function CharacterController:initalizesmartbones()
	SmartBone.Start()
end

function CharacterController:defaultstate()
	self.character:SetAttribute("state", "neutral")
end

function CharacterController:clean()
	self._pocket:destroy()
end

return CharacterController
