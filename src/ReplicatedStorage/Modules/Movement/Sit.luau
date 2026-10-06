local Sit = {}
Sit.__index = Sit

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.Sitting
local Modules = ReplicatedStorage.Modules

local HelperFunctions = require(Modules.Shared.HelperFunctions)
local Pocket = require(Modules.Shared.Pocket)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)

Sit.Settings = {
	SitAnimation = Animations:WaitForChild("Sit"),
	SitLoopAnimation = Animations:WaitForChild("Sit_Looped"),
	GetUpAnimation = Animations:WaitForChild("Get_Up"),

	ActionName = "SitLock",

	DefaultWalkSpeed = MovementConfig.DEFAULT_WALKSPEED,
	DefaultJumpPower = MovementConfig.DEFAULT_JUMP_POWER,

	GetUpFallbackDuration = MovementSettings.Abilities.Sit.GetUpFallbackDuration,

	BlockedKeys = {
		Enum.KeyCode.W,
		Enum.KeyCode.A,
		Enum.KeyCode.S,
		Enum.KeyCode.D,
		Enum.KeyCode.Space,
		Enum.KeyCode.LeftShift,
	},
}

Sit.StateByCharacter = {}

export type SitState = {
	Character: Model,
	Humanoid: Humanoid?,

	EnterTrack: AnimationTrack?,
	LoopTrack: AnimationTrack?,
	GetUpTrack: AnimationTrack?,

	OldWalkSpeed: number?,
	OldJumpPower: number?,
	OldAutoRotate: boolean?,

	Pocket: any,
}

export type SitModule = typeof(Sit)

function Sit:GetCharacterState(Character: Model): SitState
	self.Character = Character
	self.State = self.StateByCharacter[Character]

	if not self.State then
		self.State = {
			Character = Character,
			Humanoid = Character:FindFirstChildOfClass("Humanoid"),
			EnterTrack = nil,
			LoopTrack = nil,
			GetUpTrack = nil,
			OldWalkSpeed = nil,
			OldJumpPower = nil,
			OldAutoRotate = nil,
			Pocket = Pocket.new(),
		}
		self.StateByCharacter[Character] = self.State
	elseif not self.State.Pocket then
		self.State.Pocket = Pocket.new()
	end

	return self.State
end

function Sit:ClearTracks(Character: Model)
	self.State = self.StateByCharacter[Character]

	if not self.State then
		return
	end

	if self.State.EnterTrack and self.State.EnterTrack.IsPlaying then
		self.State.EnterTrack:Stop()
	end

	if self.State.LoopTrack and self.State.LoopTrack.IsPlaying then
		self.State.LoopTrack:Stop()
	end

	if self.State.GetUpTrack and self.State.GetUpTrack.IsPlaying then
		self.State.GetUpTrack:Stop()
	end

	self.State.EnterTrack = nil
	self.State.LoopTrack = nil
	self.State.GetUpTrack = nil
end

function Sit:BlockAction(ActionName, InputState, InputObject)
	return Enum.ContextActionResult.Sink
end

function Sit:LockControls()
	ContextActionService:BindAction(
		self.Settings.ActionName,
		function(ActionName, InputState, InputObject)
			return self:BlockAction(ActionName, InputState, InputObject)
		end,
		false,
		table.unpack(self.Settings.BlockedKeys)
	)
end

function Sit:UnlockControls()
	ContextActionService:UnbindAction(self.Settings.ActionName)
end

function Sit:Start(Character: Model)
	self.State = self:GetCharacterState(Character)
	self.Humanoid = self.State.Humanoid or Character:FindFirstChildOfClass("Humanoid")

	if not self.Humanoid then
		return
	end

	self.CurrentState = Character:GetAttribute("state")
	if self.CurrentState == "sitting" then
		return
	end

	self.State.OldWalkSpeed = self.Humanoid.WalkSpeed
	self.State.OldJumpPower = self.Humanoid.JumpPower
	self.State.OldAutoRotate = self.Humanoid.AutoRotate

	Character:SetAttribute("busy", true)
	Character:SetAttribute("state", "sitting")
	Character:SetAttribute("SitCanToggle", nil)

	self.Humanoid.WalkSpeed = 0
	self.Humanoid.JumpPower = 0
	self.Humanoid.Jump = false
	self.Humanoid.AutoRotate = false

	self:LockControls()
	HelperFunctions.stopAll(Character)
	self:ClearTracks(Character)

	self.State.EnterTrack = HelperFunctions.playAnim(
		Character,
		self.Settings.SitAnimation,
		true
	)

	if self.State.EnterTrack then
		self.State.EnterTrack.Looped = false

		self.State.EnterStoppedConnection = self.State.EnterTrack.Stopped:Connect(function()
			if Character:GetAttribute("state") ~= "sitting" then
				return
			end

			self.State.LoopTrack = HelperFunctions.playAnim(
				Character,
				self.Settings.SitLoopAnimation,
				true
			)

			if self.State.LoopTrack then
				self.State.LoopTrack.Looped = true
				self.State.Pocket:add(self.State.LoopTrack)
			end

			Character:SetAttribute("SitCanToggle", true)
		end)

		self.State.Pocket:add(self.State.EnterTrack)
		self.State.Pocket:add(self.State.EnterStoppedConnection)
	else
		self.State.LoopTrack = HelperFunctions.playAnim(
			Character,
			self.Settings.SitLoopAnimation,
			true
		)

		if self.State.LoopTrack then
			self.State.LoopTrack.Looped = true
			self.State.Pocket:add(self.State.LoopTrack)
		end

		Character:SetAttribute("SitCanToggle", true)
	end
end

function Sit:Stop(Character: Model)
	self.State = self:GetCharacterState(Character)
	self.Humanoid = self.State.Humanoid or Character:FindFirstChildOfClass("Humanoid")

	if not self.Humanoid then
		return
	end

	Character:SetAttribute("SitCanToggle", nil)
	Character:SetAttribute("state", "sitting")

	HelperFunctions.stopAll(Character)
	self:ClearTracks(Character)

	self.State.GetUpTrack = HelperFunctions.playAnim(
		Character,
		self.Settings.GetUpAnimation,
		true
	)

	self.State.Duration = self.Settings.GetUpFallbackDuration

	if self.State.GetUpTrack and self.State.GetUpTrack.Length > 0 then
		self.State.GetUpTrack.Looped = false
		self.State.Duration = self.State.GetUpTrack.Length
		self.State.Pocket:add(self.State.GetUpTrack)
	end

	task.delay(self.State.Duration, function()
		self.Humanoid = Character:FindFirstChildOfClass("Humanoid")

		if self.Humanoid then
			if typeof(self.State.OldWalkSpeed) == "number" then
				self.Humanoid.WalkSpeed = self.State.OldWalkSpeed
			else
				self.Humanoid.WalkSpeed = self.Settings.DefaultWalkSpeed
			end

			if typeof(self.State.OldJumpPower) == "number" then
				self.Humanoid.JumpPower = self.State.OldJumpPower
			else
				self.Humanoid.JumpPower = self.Settings.DefaultJumpPower
			end

			if self.State.OldAutoRotate ~= nil then
				self.Humanoid.AutoRotate = self.State.OldAutoRotate
			else
				self.Humanoid.AutoRotate = true
			end
		end

		self:UnlockControls()
		self:ClearTracks(Character)

		if self.State.Pocket then
			self.State.Pocket:destroy()
		end

		self.StateByCharacter[Character] = nil

		Character:SetAttribute("state", "neutral")
		Character:SetAttribute("busy", nil)
		Character:SetAttribute("SitCanToggle", nil)
	end)
end

return Sit