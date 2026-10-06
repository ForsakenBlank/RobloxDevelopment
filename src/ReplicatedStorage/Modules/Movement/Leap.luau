local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage.Modules
local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations
local Fundamentals = Animations.Fundamental

local HelperFunctions = require(Modules.Shared.HelperFunctions)
local Pocket = require(Modules.Shared.Pocket)
local Network = require(ReplicatedStorage.Modules.Shared.Network.Network)
local Sound = require(ReplicatedStorage.Modules.Shared.Sound)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)

local LeapTuning = MovementSettings.Abilities.Leap

local FovBoost = LeapTuning.FovBoost
local FovTweenTime = LeapTuning.FovTweenTime
local BaseFov = MovementSettings.Defaults.FallbackFov

type PocketType = typeof(Pocket.new())

type ZiplineLeapSettings = {
	ForwardSpeed: number,
	UpwardBoost: number,
	VelocityDuration: number,
	VelocityName: string,
	UseVisualEffects: boolean,
	ApplyVelocityOnStart: boolean,
}

type LeapSettings = {
	LeapAnimation: Animation?,
	ForwardSpeed: number,
	UpwardBoost: number,
	VelocityDuration: number,
	VelocityName: string,
	MarkerName: string,
	ZiplineLeap: ZiplineLeapSettings,
}

type LeapStartOverrides = {
	LeapAnimation: Animation?,
	ForwardSpeed: number?,
	UpwardBoost: number?,
	VelocityDuration: number?,
	VelocityName: string?,
	MarkerName: string?,
	UseVisualEffects: boolean?,
	ApplyVelocityOnStart: boolean?,
}

export type LeapState = {
	Character: Model,
	Humanoid: Humanoid?,
	RootPart: BasePart?,
	IsLeaping: boolean,
	UseVisualEffects: boolean,
	LeapTrack: AnimationTrack?,
	VelocityObject: LinearVelocity?,
	Pocket: PocketType,
}

local Leap = {}
Leap.__index = Leap

local Settings: LeapSettings = {
	LeapAnimation = Fundamentals.Leap,
	ForwardSpeed = LeapTuning.ForwardSpeed,
	UpwardBoost = LeapTuning.UpwardBoost,
	VelocityDuration = LeapTuning.VelocityDuration,
	VelocityName = "LeapVelocity",
	MarkerName = "Velocity",
	ZiplineLeap = {
		ForwardSpeed = LeapTuning.ZiplineLeap.ForwardSpeed,
		UpwardBoost = LeapTuning.ZiplineLeap.UpwardBoost,
		VelocityDuration = LeapTuning.ZiplineLeap.VelocityDuration,
		VelocityName = "ZiplineLeapVelocity",
		UseVisualEffects = false,
		ApplyVelocityOnStart = true,
	},
}

Leap.Settings = Settings
Leap.StateByCharacter = {} :: { [Model]: LeapState }

local function GetRootPart(Character: Model): BasePart?
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	if RootPartObject and RootPartObject:IsA("BasePart") then
		return RootPartObject
	end

	return nil
end

function Leap:GetCharacterState(Character: Model): LeapState
	local State = self.StateByCharacter[Character]
	if State then
		if not State.Pocket then
			State.Pocket = Pocket.new()
		end
		return State
	end

	State = {
		Character = Character,
		Humanoid = Character:FindFirstChildOfClass("Humanoid"),
		RootPart = GetRootPart(Character),
		IsLeaping = false,
		UseVisualEffects = true,
		LeapTrack = nil,
		VelocityObject = nil,
		Pocket = Pocket.new(),
	}

	self.StateByCharacter[Character] = State
	return State
end

function Leap:Stop(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State or not State.IsLeaping then
		return
	end

	State.IsLeaping = false
	Character:SetAttribute("leaping", nil)

	local CurrentCamera = workspace.CurrentCamera
	if State.UseVisualEffects and CurrentCamera then
		local ResetFovTween = TweenService:Create(
			CurrentCamera,
			TweenInfo.new(FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = BaseFov }
		)
		ResetFovTween:Play()
	end

	if State.LeapTrack and State.LeapTrack.IsPlaying then
		State.LeapTrack:Stop()
	end

	if State.VelocityObject and State.VelocityObject.Parent then
		State.VelocityObject:Destroy()
		State.VelocityObject = nil
	end

	State.Pocket:destroy()
	State.Pocket = Pocket.new()
end

function Leap:Start(Character: Model, LeapAnimation: Animation?, StartOverrides: LeapStartOverrides?, Zipline: boolean): boolean
	local State = self:GetCharacterState(Character)
	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	local RootPart = State.RootPart or GetRootPart(Character)

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart or State.IsLeaping then
		return false
	end

	local SelectedAnimation = LeapAnimation
	if StartOverrides and StartOverrides.LeapAnimation then
		SelectedAnimation = StartOverrides.LeapAnimation
	end
	if not SelectedAnimation then
		SelectedAnimation = self.Settings.LeapAnimation
	end
	if not SelectedAnimation then
		return false
	end

	local EffectiveForwardSpeed = self.Settings.ForwardSpeed
	local EffectiveUpwardBoost = self.Settings.UpwardBoost
	local EffectiveVelocityDuration = self.Settings.VelocityDuration
	local EffectiveVelocityName = self.Settings.VelocityName
	local EffectiveMarkerName = self.Settings.MarkerName
	local EffectiveUseVisualEffects = true
	local EffectiveApplyVelocityOnStart = false
	if StartOverrides then
		if StartOverrides.ForwardSpeed ~= nil then
			EffectiveForwardSpeed = StartOverrides.ForwardSpeed
		end
		if StartOverrides.UpwardBoost ~= nil then
			EffectiveUpwardBoost = StartOverrides.UpwardBoost
		end
		if StartOverrides.VelocityDuration ~= nil then
			EffectiveVelocityDuration = StartOverrides.VelocityDuration
		end
		if StartOverrides.VelocityName ~= nil then
			EffectiveVelocityName = StartOverrides.VelocityName
		end
		if StartOverrides.MarkerName ~= nil then
			EffectiveMarkerName = StartOverrides.MarkerName
		end
		if StartOverrides.UseVisualEffects ~= nil then
			EffectiveUseVisualEffects = StartOverrides.UseVisualEffects
		end
		if StartOverrides.ApplyVelocityOnStart ~= nil then
			EffectiveApplyVelocityOnStart = StartOverrides.ApplyVelocityOnStart
		end
	end

	State.IsLeaping = true
	State.UseVisualEffects = EffectiveUseVisualEffects
	Character:SetAttribute("leaping", true)

	local CurrentCamera = workspace.CurrentCamera
	if EffectiveUseVisualEffects and CurrentCamera then
		local BoostFovTween = TweenService:Create(
			CurrentCamera,
			TweenInfo.new(FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = BaseFov + FovBoost }
		)
		BoostFovTween:Play()
	end
	
	Network.Fire({
		module = "Visuals",
		method = "glidevfx",
		msg = "",
		animLength = 0,
	}, "Core")
		
	
	Sound:Play("Leap", Character)
	HelperFunctions.stopAll(Character)

	local LeapTrack = HelperFunctions.playAnim(Character, SelectedAnimation, true)
	if not LeapTrack then
		State.IsLeaping = false
		Character:SetAttribute("leaping", nil)
		return false
	end

	LeapTrack.Priority = Enum.AnimationPriority.Action4
	LeapTrack.Looped = false
	State.LeapTrack = LeapTrack
	State.Pocket:add(LeapTrack)

	local function ApplyLeapVelocity()
		if not State.IsLeaping then
			return
		end

		local CurrentRootPart = GetRootPart(Character)
		if not CurrentRootPart then
			return
		end

		local CurrentHumanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
		if CurrentHumanoid then
			State.Humanoid = CurrentHumanoid
		end

		local UpwardBoost = EffectiveUpwardBoost
		if CurrentHumanoid and CurrentHumanoid.FloorMaterial == Enum.Material.Air then
			UpwardBoost = EffectiveUpwardBoost / LeapTuning.AirUpwardDivisor
		end

		HelperFunctions.clearVelocity(CurrentRootPart, EffectiveVelocityName)

		local LeapDirection = CurrentRootPart.CFrame.LookVector
		local LeapVelocity = LeapDirection * EffectiveForwardSpeed + Vector3.yAxis * UpwardBoost

		local VelocityObject = HelperFunctions.velocity(
			CurrentRootPart,
			LeapVelocity,
			EffectiveVelocityDuration,
			true,
			EffectiveVelocityName
		)

		State.VelocityObject = VelocityObject
		if VelocityObject then
			State.Pocket:add(VelocityObject)
		end
	end

	if EffectiveApplyVelocityOnStart then
		ApplyLeapVelocity()
	else
		local MarkerConnection = LeapTrack:GetMarkerReachedSignal(EffectiveMarkerName):Connect(function()
			ApplyLeapVelocity()
		end)
		State.Pocket:add(MarkerConnection)
	end

	local TrackEndedConnection = LeapTrack.Ended:Connect(function()
		self:Stop(Character)
	end)
	State.Pocket:add(TrackEndedConnection)

	local TrackStoppedConnection = LeapTrack.Stopped:Connect(function()
		self:Stop(Character)
	end)
	State.Pocket:add(TrackStoppedConnection)

	return true
end

function Leap:ZiplineLeap(Character: Model): boolean
	local ZiplineLeapSettings = self.Settings.ZiplineLeap
	return self:Start(Character, nil, {
		ForwardSpeed = ZiplineLeapSettings.ForwardSpeed,
		UpwardBoost = ZiplineLeapSettings.UpwardBoost,
		VelocityDuration = ZiplineLeapSettings.VelocityDuration,
		VelocityName = ZiplineLeapSettings.VelocityName,
		UseVisualEffects = ZiplineLeapSettings.UseVisualEffects,
		ApplyVelocityOnStart = ZiplineLeapSettings.ApplyVelocityOnStart,
	}, true)
end

return Leap