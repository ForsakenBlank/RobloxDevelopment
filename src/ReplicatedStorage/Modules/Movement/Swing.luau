--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local Pocket = require(ReplicatedStorage.Modules.Shared.Pocket)
local Sound = require(ReplicatedStorage.Modules.Shared.Sound)
local Run = require(ReplicatedStorage.Modules.Movement.Run)

local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)
local MovementGate = require(ReplicatedStorage.Modules.Shared.MovementGate)

-- Looks through every folder listed in MovementSettings.MapFolders
-- rather than workspace.Map only, so swing bars work in the rogue
-- like map as well as the parkour one.
local Swingables = MovementSettings.FindInMap("Swingable")

local Animations = ReplicatedStorage.Assets.Animations
local SlideCancel = Animations.Sliding.Slide_Cancel

type PocketType = typeof(Pocket.new())

export type SwingState = {
	Character: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Swinging: boolean,
	LastSwingTime: number,
	LastAnchor: BasePart?,
	LastAnchorTime: number,
	Lock: AlignPosition?,
	Pocket: PocketType,
	OriginalFov: number?,
}

type SwingSettings = {
	DetectRadius: number,
	PullSpeed: number,
	UpBoost: number,
	Duration: number,
	Cooldown: number,
	SameBarCooldown: number,
	VerticalOffset: number,
	FovBoost: number,
	FovTweenTime: number,
}

type SwingClass = {
	__index: SwingClass,
	StateByCharacter: { [Model]: SwingState },
	Settings: SwingSettings,
	GetState: (self: SwingClass, Character: Model) -> SwingState?,
	FindNearbySwingable: (self: SwingClass, State: SwingState) -> BasePart?,
	LockUnderAnchor: (self: SwingClass, State: SwingState, Anchor: BasePart) -> (),
	Unlock: (self: SwingClass, State: SwingState) -> (),
	TweenFov: (self: SwingClass, TargetFov: number) -> (),
	StartSwingFov: (self: SwingClass, State: SwingState) -> (),
	TryAutoSwing: (self: SwingClass, Character: Model, SwingAnimation: Animation) -> (),
	Stop: (self: SwingClass, Character: Model) -> (),
}

local Swing = {} :: SwingClass
Swing.__index = Swing

Swing.StateByCharacter = {}

-- Values live in MovementSettings.Abilities.Swing.
Swing.Settings = MovementSettings.Abilities.Swing

local function GetSwingLaunchDirection(FallbackDirection: Vector3): Vector3
	local CurrentCamera = workspace.CurrentCamera
	if CurrentCamera then
		local CameraLook = CurrentCamera.CFrame.LookVector
		if CameraLook.Magnitude > 0 then
			return CameraLook.Unit
		end
	end

	if FallbackDirection.Magnitude > 0 then
		return FallbackDirection.Unit
	end

	return Vector3.zAxis
end

function Swing:GetState(Character: Model): SwingState?
	local HumanoidInstance = Character:FindFirstChildOfClass("Humanoid")
	local RootPartInstance = Character:FindFirstChild("HumanoidRootPart")

	if not HumanoidInstance or not RootPartInstance then
		return nil
	end

	if not HumanoidInstance:IsA("Humanoid") then
		return nil
	end

	if not RootPartInstance:IsA("BasePart") then
		return nil
	end

	local Humanoid: Humanoid = HumanoidInstance
	local RootPart: BasePart = RootPartInstance

	local ExistingState = self.StateByCharacter[Character]
	if ExistingState then
		return ExistingState
	end

	local State: SwingState = {
		Character = Character,
		Humanoid = Humanoid,
		RootPart = RootPart,
		Swinging = false,
		LastSwingTime = 0,
		LastAnchor = nil,
		LastAnchorTime = 0,
		Lock = nil,
		Pocket = Pocket.new(),
		OriginalFov = nil,
	}

	self.StateByCharacter[Character] = State
	return State
end

function Swing:FindNearbySwingable(State: SwingState): BasePart?
	-- Nothing to grab if swinging is switched off in
	-- MovementSettings, or if the loaded map has no Swingable
	-- folder in it.
	if not MovementGate:IsEnabled("Swing") or not Swingables then
		return nil
	end

	local Children = Swingables:GetChildren()

	for Index = 1, #Children do
		local Part = Children[Index]
		if Part:IsA("BasePart") then
			if (Part.Position - State.RootPart.Position).Magnitude <= self.Settings.DetectRadius then
				return Part
			end
		end
	end

	return nil
end

function Swing:LockUnderAnchor(State: SwingState, Anchor: BasePart)
	local Attachment0 = Instance.new("Attachment")
	Attachment0.Parent = State.RootPart

	local Attachment1 = Instance.new("Attachment")
	Attachment1.WorldPosition = Anchor.Position - Vector3.yAxis * self.Settings.VerticalOffset
	Attachment1.Parent = workspace.Terrain

	local Align = Instance.new("AlignPosition")
	Align.Attachment0 = Attachment0
	Align.Attachment1 = Attachment1
	Align.MaxForce = math.huge
	Align.Responsiveness = 200
	Align.RigidityEnabled = true
	Align.Parent = State.RootPart

	State.Lock = Align
	State.Pocket:add(Align)
	State.Pocket:add(Attachment0)
	State.Pocket:add(Attachment1)
end

function Swing:Unlock(State: SwingState)
	if State.Lock then
		State.Lock:Destroy()
		State.Lock = nil
	end
end

function Swing:TweenFov(TargetFov: number)
	local CurrentCamera = workspace.CurrentCamera
	if not CurrentCamera then
		return
	end

	local FovTween = TweenService:Create(
		CurrentCamera,
		TweenInfo.new(self.Settings.FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = TargetFov }
	)

	FovTween:Play()
end

function Swing:StartSwingFov(State: SwingState)
	local CurrentCamera = workspace.CurrentCamera
	if CurrentCamera then
		State.OriginalFov = CurrentCamera.FieldOfView
		self:TweenFov(CurrentCamera.FieldOfView + self.Settings.FovBoost)
		return
	end

	local CameraConnection: RBXScriptConnection?
	CameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local NewCamera = workspace.CurrentCamera
		if not NewCamera or not State.Swinging then
			return
		end

		State.OriginalFov = NewCamera.FieldOfView
		self:TweenFov(NewCamera.FieldOfView + self.Settings.FovBoost)

		if CameraConnection then
			CameraConnection:Disconnect()
			CameraConnection = nil
		end
	end)

	State.Pocket:add(CameraConnection)
end

function Swing:TryAutoSwing(Character: Model, SwingAnimation: Animation)
	local State = self:GetState(Character)
	if not State or State.Swinging then
		return
	end

	if os.clock() - State.LastSwingTime < self.Settings.Cooldown then
		return
	end

	if Character:GetAttribute("busy") then
		return
	end

	local Anchor = self:FindNearbySwingable(State)
	if not Anchor then
		return
	end

	if State.LastAnchor == Anchor and (os.clock() - State.LastAnchorTime) < self.Settings.SameBarCooldown then
		return
	end

	State.Swinging = true
	State.LastSwingTime = os.clock()
	State.LastAnchor = Anchor
	State.LastAnchorTime = State.LastSwingTime
	Character:SetAttribute("Swinging", true)
	State.OriginalFov = nil
	self:StartSwingFov(State)

	State.RootPart.AssemblyLinearVelocity = Vector3.zero
	State.RootPart.AssemblyAngularVelocity = Vector3.zero
	HelperFunctions.clearVelocity(State.RootPart)

	self:LockUnderAnchor(State, Anchor)

	HelperFunctions.stopAll(Character)

	Run:Stop(Character)

	local TrackResult = HelperFunctions.playAnim(Character, SwingAnimation, true)
	if not TrackResult then
		self:Stop(Character)
		return
	end

	local Track = TrackResult
	Track.Priority = Enum.AnimationPriority.Action4
	State.Pocket:add(Track)

	local StoppedConnection = Track.Stopped:Connect(function()
		HelperFunctions.playAnim(Character, SlideCancel, false)
	end)
	State.Pocket:add(StoppedConnection)

	Sound:Play("Swing", Character)

	local MarkerConnection: RBXScriptConnection
	MarkerConnection = Track:GetMarkerReachedSignal("Swing"):Connect(function()
		if not State.Swinging then
			return
		end

		self:Unlock(State)

		local Direction = GetSwingLaunchDirection(State.RootPart.CFrame.LookVector)
		local Velocity = Direction * self.Settings.PullSpeed + Vector3.yAxis * self.Settings.UpBoost

		HelperFunctions.velocity(
			State.RootPart,
			Velocity,
			self.Settings.Duration,
			false,
			"SwingVelocity"
		)

		if State.OriginalFov then
			self:TweenFov(State.OriginalFov)
		end

		MarkerConnection:Disconnect()
	end)

	State.Pocket:add(MarkerConnection)

	local StopThread = task.delay(self.Settings.Duration + 0.25, function()
		self:Stop(Character)
	end)
	State.Pocket:add(StopThread)
end

function Swing:Stop(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State then
		return
	end

	self:Unlock(State)

	State.Swinging = false
	Character:SetAttribute("Swinging", nil)

	if State.OriginalFov then
		self:TweenFov(State.OriginalFov)
		State.OriginalFov = nil
	end

	State.Pocket:destroy()
	State.Pocket = Pocket.new()

	self.StateByCharacter[Character] = State
end

return Swing