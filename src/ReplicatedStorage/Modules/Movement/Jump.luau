local Jump = {}
Jump.__index = Jump

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.Fundamental
local Modules = ReplicatedStorage.Modules

local Network = require(Modules.Shared.Network.Network)
local HelperFunctions = require(Modules.Shared.HelperFunctions)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local Sound = require(ReplicatedStorage.Modules.Shared.Sound)

Jump.Settings = {
	JumpPower = MovementConfig.JUMP_POWER,
	JumpDuration = MovementConfig.JUMP_DURATION,

	DoubleJumpAnimation = Animations.DoubleJump,
	DoubleJumpVelocityName = "DoubleJumpVelocity",

	NetworkModuleName = "Visuals",
	NetworkMethodName = "doublejump",

	AirJumpSoundName = "Jump",
} :: {string | boolean | number}

export type JumpModule = typeof(Jump)

function Jump:Main(Character: Model)
	self.RootPart = Character:FindFirstChild("HumanoidRootPart") :: Part

	if not self.RootPart then
		return
	end
	
	if Character:GetAttribute("WallRunning") then
		return
	end
	
	if Character:GetAttribute("WallJumping") then
		return
	end

	self.JumpVelocity = Vector3.new(0, self.Settings.JumpPower, 0)

	self.AnimationTrack = HelperFunctions.playAnim(
		Character,
		self.Settings.DoubleJumpAnimation,
		true
	) :: AnimationTrack

	if self.AnimationTrack then
		self.AnimationTrack.Priority = Enum.AnimationPriority.Action4
	end

	HelperFunctions.velocity(
		self.RootPart,
		self.JumpVelocity,
		self.Settings.JumpDuration,
		false,
		self.Settings.DoubleJumpVelocityName
	)

	Network.Fire({
		module = self.Settings.NetworkModuleName,
		method = self.Settings.NetworkMethodName,
		msg = "",
		animLength = 0,
	}, "Core")

	Sound:Play(self.Settings.AirJumpSoundName, Character)
end

return Jump