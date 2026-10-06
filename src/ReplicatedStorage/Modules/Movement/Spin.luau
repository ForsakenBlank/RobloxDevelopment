local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage.Modules
local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations

local HelperFunctions = require(Modules.Shared.HelperFunctions)
local Pocket = require(Modules.Shared.Pocket)
local Sound = require(Modules.Shared.Sound)
local Network = require(ReplicatedStorage.Modules.Shared.Network.Network)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)

local GlideTuning = MovementSettings.Abilities.Glide

local FovBoost = GlideTuning.FovBoost
local FovTweenTime = GlideTuning.FovTweenTime
local BaseFov = MovementSettings.Defaults.FallbackFov

type PocketType = typeof(Pocket.new())

type SpinSettings = {
	SpinAnimation: Animation?,
	SpinDuration: number,
	InitialForwardSpeed: number,
	EndForwardSpeed: number,
	UpwardBoost: number,
}

export type SpinState = {
	Character: Model,
	Humanoid: Humanoid?,
	RootPart: BasePart?,
	IsSpinning: boolean,
	SpinTrack: AnimationTrack?,
	SpinVelocity: LinearVelocity?,
	HeartbeatConnection: RBXScriptConnection?,
	Pocket: PocketType,
}

local Spin = {}
Spin.__index = Spin

local Settings: SpinSettings = {
	SpinAnimation = Animations.Fundamental.Spin,
	SpinDuration = GlideTuning.Duration,
	InitialForwardSpeed = GlideTuning.InitialForwardSpeed,
	EndForwardSpeed = GlideTuning.EndForwardSpeed,
	UpwardBoost = GlideTuning.UpwardBoost,
}

Spin.Settings = Settings
Spin.StateByCharacter = {} :: { [Model]: SpinState }

local function GetRootPart(Character: Model): BasePart?
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	if RootPartObject and RootPartObject:IsA("BasePart") then
		return RootPartObject
	end

	return nil
end

local function GetAimDirection(FallbackDirection: Vector3): Vector3
	local CurrentCamera = workspace.CurrentCamera
	if not CurrentCamera then
		return FallbackDirection
	end

	if UserInputService.TouchEnabled or UserInputService.GamepadEnabled then
		local CameraDirection = CurrentCamera.CFrame.LookVector
		if CameraDirection.Magnitude <= 0 then
			return FallbackDirection
		end

		return CameraDirection.Unit
	end

	local MouseLocation = UserInputService:GetMouseLocation()
	local MouseRay = CurrentCamera:ViewportPointToRay(MouseLocation.X, MouseLocation.Y)
	local AimDirection = MouseRay.Direction

	if AimDirection.Magnitude <= 0 then
		return FallbackDirection
	end

	return AimDirection.Unit
end

function Spin:GetCharacterState(Character: Model): SpinState
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
		IsSpinning = false,
		SpinTrack = nil,
		SpinVelocity = nil,
		HeartbeatConnection = nil,
		Pocket = Pocket.new(),
	}

	self.StateByCharacter[Character] = State
	return State
end

function Spin:Stop(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State or not State.IsSpinning then
		return
	end

	State.IsSpinning = false
	Character:SetAttribute("spinning", nil)

	local CurrentCamera = workspace.CurrentCamera
	if CurrentCamera then
		local ResetFovTween = TweenService:Create(
			CurrentCamera,
			TweenInfo.new(FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = BaseFov }
		)
		ResetFovTween:Play()
	end

	if State.HeartbeatConnection then
		State.HeartbeatConnection:Disconnect()
		State.HeartbeatConnection = nil
	end

	if State.SpinVelocity and State.SpinVelocity.Parent then
		State.SpinVelocity:Destroy()
		State.SpinVelocity = nil
	end

	if State.SpinTrack and State.SpinTrack.IsPlaying then
		State.SpinTrack:Stop()
	end

	State.Pocket:destroy()
	State.Pocket = Pocket.new()
end

function Spin:Start(Character: Model, SpinAnimation: Animation?): boolean
	local State = self:GetCharacterState(Character)
	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	local RootPart = State.RootPart or GetRootPart(Character)

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart or State.IsSpinning then
		return false
	end

	local SelectedAnimation = SpinAnimation or self.Settings.SpinAnimation
	if not SelectedAnimation then
		return false
	end

	State.IsSpinning = true
	Character:SetAttribute("spinning", true)

	local CurrentCamera = workspace.CurrentCamera
	if CurrentCamera then
		local BoostFovTween = TweenService:Create(
			CurrentCamera,
			TweenInfo.new(FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = BaseFov + FovBoost }
		)
		BoostFovTween:Play()
	end

	HelperFunctions.stopAll(Character)
	Sound:Play("Boost", Character)

	Network.Fire({
		module = "Visuals",
		method = "glidevfx",
		msg = "",
		animLength = 0,
	}, "Core")

	local SpinTrack = HelperFunctions.playAnim(Character, SelectedAnimation, true)
	if not SpinTrack then
		State.IsSpinning = false
		Character:SetAttribute("spinning", nil)
		return false
	end

	SpinTrack.Priority = Enum.AnimationPriority.Action4
	SpinTrack.Looped = false
	State.SpinTrack = SpinTrack
	State.Pocket:add(SpinTrack)

	local ForwardDirection = RootPart.CFrame.LookVector
	local SpinVelocity = HelperFunctions.velocity(
		RootPart,
		ForwardDirection * self.Settings.InitialForwardSpeed + Vector3.yAxis * self.Settings.UpwardBoost,
		self.Settings.SpinDuration + 0.5,
		true,
		"SpinVelocity"
	)

	State.SpinVelocity = SpinVelocity
	if SpinVelocity then
		State.Pocket:add(SpinVelocity)
	end

	local Elapsed = 0
	State.HeartbeatConnection = RunService.Heartbeat:Connect(function(DeltaTime)
		if not State.IsSpinning or not State.SpinVelocity or not State.SpinVelocity.Parent then
			return
		end

		local AimDirection = GetAimDirection(ForwardDirection)
		ForwardDirection = AimDirection
		RootPart.CFrame = CFrame.lookAt(RootPart.Position, RootPart.Position + AimDirection)

		Elapsed += DeltaTime
		local Alpha = math.clamp(Elapsed / self.Settings.SpinDuration, 0, 1)
		local CurrentSpeed = self.Settings.InitialForwardSpeed + (self.Settings.EndForwardSpeed - self.Settings.InitialForwardSpeed) * Alpha
		State.SpinVelocity.VectorVelocity = AimDirection * CurrentSpeed + Vector3.yAxis * self.Settings.UpwardBoost
	end)

	State.Pocket:add(State.HeartbeatConnection)

	local TrackEndedConnection = SpinTrack.Ended:Connect(function()
		self:Stop(Character)
	end)
	State.Pocket:add(TrackEndedConnection)

	local TrackStoppedConnection = SpinTrack.Stopped:Connect(function()
		self:Stop(Character)
	end)
	State.Pocket:add(TrackStoppedConnection)

	return true
end

return Spin