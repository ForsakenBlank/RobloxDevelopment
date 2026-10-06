--!nonstrict

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage.Modules
local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations
local Fundamentals = Animations.Fundamental

local HelperFunctions = require(Modules.Shared.HelperFunctions)
local Pocket = require(Modules.Shared.Pocket)
local Leap = require(Modules.Movement.Leap)
local CameraShake = require(Modules.Shared.CameraShake)
local Network = require(Modules.Shared.Network.Network)

local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)
local MovementGate = require(ReplicatedStorage.Modules.Shared.MovementGate)

-- Searches every folder in MovementSettings.MapFolders instead of
-- only workspace.Map, and returns nil rather than yielding forever
-- when a map has no ziplines in it.
local ZiplinesFolder = MovementSettings.FindInMap("Ziplines")
local LocalPlayer = Players.LocalPlayer
local ZIPLINE_BLOCK_JUMP_ACTION = "Zipline_BlockJump"

type PocketType = typeof(Pocket.new())

type ZiplineSettings = {
	DetectRadius: number,
	TravelSpeed: number,
	EndDistance: number,
	EarlyDetachRatio: number,
	MinDetachTime: number,
	Cooldown: number,
	JumpOffMinTime: number,
	JumpOffExtraCooldown: number,
	HeightOffsetFromHip: number,
	LeftArmYOffset: number,
	AttachFovBoost: number,
	FovTweenTime: number,
	StartShakeIntensity: number,
	StartShakeDuration: number,
	PitchInfluence: number,
	LineSnapStrength: number,
	MaxSnapSpeed: number,
	DisableZiplineCollisions: boolean,
	ZiplineAnimation: Animation | nil,
}

type ZiplineTarget = {
	Zipline: Instance,
	StartPosition: Vector3,
	EndPosition: Vector3,
	ClosestPoint: Vector3,
	SegmentLength: number,
}

export type ZiplineState = {
	Character: Model,
	Humanoid: Humanoid | nil,
	RootPart: BasePart | nil,
	IsZiplining: boolean,
	LastSurfacePoint: Vector3 | nil,
	ControlsLockedByZipline: boolean,
	JumpLockedByZipline: boolean,
	PreviousJumpStateEnabled: boolean | nil,
	LastZiplineTime: number,
	PreviousAutoRotate: boolean | nil,
	ZiplineTrack: AnimationTrack | nil,
	CurrentTarget: ZiplineTarget | nil,
	HeartbeatConnection: RBXScriptConnection | nil,
	Pocket: PocketType,
}

local Zipline = {}
Zipline.__index = Zipline

local Settings: ZiplineSettings = {
	DetectRadius = 7.5,
	TravelSpeed = 80,
	EndDistance = 0.5,
	EarlyDetachRatio = 0.05,
	MinDetachTime = 0.2,
	Cooldown = 0.25,
	JumpOffMinTime = 0.5,
	JumpOffExtraCooldown = 0.9,
	HeightOffsetFromHip = 0,
	LeftArmYOffset = 1,
	AttachFovBoost = 6,
	FovTweenTime = 0.2,
	StartShakeIntensity = 0.35,
	StartShakeDuration = 0.2,
	PitchInfluence = 1,
	LineSnapStrength = 12,
	MaxSnapSpeed = 45,
	DisableZiplineCollisions = true,
	ZiplineAnimation = Fundamentals.Ziplining,
}

Zipline.Settings = Settings
Zipline.StateByCharacter = {} :: { [Model]: ZiplineState }

local function GetRootPart(Character: Model): BasePart | nil
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	if RootPartObject and RootPartObject:IsA("BasePart") then
		return RootPartObject
	end

	return nil
end

local function GetCharacterState(self, Character: Model): ZiplineState
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
		IsZiplining = false,
		LastSurfacePoint = nil,
		ControlsLockedByZipline = false,
		JumpLockedByZipline = false,
		PreviousJumpStateEnabled = nil,
		LastZiplineTime = 0,
		PreviousAutoRotate = nil,
		ZiplineTrack = nil,
		CurrentTarget = nil,
		HeartbeatConnection = nil,
		Pocket = Pocket.new(),
	}

	self.StateByCharacter[Character] = State
	return State
end

local function GetPrimaryPartFromInstance(ZiplineInstance: Instance): BasePart | nil
	if ZiplineInstance:IsA("BasePart") then
		return ZiplineInstance
	end

	if ZiplineInstance:IsA("Model") then
		if ZiplineInstance.PrimaryPart then
			return ZiplineInstance.PrimaryPart
		end

		local Descendants = ZiplineInstance:GetDescendants()
		for Index = 1, #Descendants do
			local Descendant = Descendants[Index]
			if Descendant:IsA("BasePart") then
				return Descendant
			end
		end
	end

	return nil
end

local function FindNamedAttachment(ZiplineInstance: Instance, NameA: string, NameB: string): Attachment | nil
	local Descendants = ZiplineInstance:GetDescendants()
	for Index = 1, #Descendants do
		local Descendant = Descendants[Index]
		if Descendant:IsA("Attachment") then
			if Descendant.Name == NameA or Descendant.Name == NameB then
				return Descendant
			end
		end
	end

	return nil
end

local function ResolveZiplineEndpoints(ZiplineInstance: Instance): (Vector3 | nil, Vector3 | nil)
	local StartAttachment = FindNamedAttachment(ZiplineInstance, "Start", "StartAttachment")
	local EndAttachment = FindNamedAttachment(ZiplineInstance, "End", "EndAttachment")

	if StartAttachment and EndAttachment then
		return StartAttachment.WorldPosition, EndAttachment.WorldPosition
	end

	local ReferencePart = GetPrimaryPartFromInstance(ZiplineInstance)
	if not ReferencePart then
		return nil, nil
	end

	local Size = ReferencePart.Size
	local AxisVector = ReferencePart.CFrame.RightVector
	local AxisHalf = Size.X * 0.5

	if Size.Y >= Size.X and Size.Y >= Size.Z then
		AxisVector = ReferencePart.CFrame.UpVector
		AxisHalf = Size.Y * 0.5
	elseif Size.Z >= Size.X and Size.Z >= Size.Y then
		AxisVector = ReferencePart.CFrame.LookVector
		AxisHalf = Size.Z * 0.5
	end

	local StartPosition = ReferencePart.Position - AxisVector * AxisHalf
	local EndPosition = ReferencePart.Position + AxisVector * AxisHalf
	return StartPosition, EndPosition
end

local function GetClosestPointOnSegment(Point: Vector3, StartPosition: Vector3, EndPosition: Vector3): Vector3
	local Segment = EndPosition - StartPosition
	local SegmentLengthSq = Segment:Dot(Segment)
	if SegmentLengthSq <= 0 then
		return StartPosition
	end

	local Alpha = math.clamp((Point - StartPosition):Dot(Segment) / SegmentLengthSq, 0, 1)
	return StartPosition + Segment * Alpha
end

local function GetClosestPointOnZipline(ZiplineInstance: Instance, Point: Vector3, StartPosition: Vector3, EndPosition: Vector3): Vector3
	if ZiplineInstance:IsA("UnionOperation") then
		local Success, ClosestPoint = pcall(function()
			return ZiplineInstance:GetClosestPointOnSurface(Point)
		end)
		if Success and ClosestPoint then
			return ClosestPoint
		end
	end

	return GetClosestPointOnSegment(Point, StartPosition, EndPosition)
end

local function GetSlopeLookDirection(Direction: Vector3, CurrentRootPart: BasePart, PitchInfluence: number): Vector3
	local HorizontalDirection = Vector3.new(Direction.X, 0, Direction.Z)
	if HorizontalDirection.Magnitude <= 0.001 then
		local CurrentLook = CurrentRootPart.CFrame.LookVector
		HorizontalDirection = Vector3.new(CurrentLook.X, 0, CurrentLook.Z)
	end

	if HorizontalDirection.Magnitude <= 0.001 then
		return Direction
	end

	HorizontalDirection = HorizontalDirection.Unit
	local Pitch = math.asin(math.clamp(Direction.Y, -1, 1)) * PitchInfluence
	local RightAxis = HorizontalDirection:Cross(Vector3.yAxis)
	if RightAxis.Magnitude <= 0.001 then
		return Direction
	end

	RightAxis = RightAxis.Unit
	local TiltedDirection = CFrame.fromAxisAngle(RightAxis, Pitch):VectorToWorldSpace(HorizontalDirection)
	if TiltedDirection.Magnitude <= 0.001 then
		return Direction
	end

	return TiltedDirection.Unit
end

local function CollectBaseParts(RootInstance: Instance): { BasePart }
	local Parts = {}

	if RootInstance:IsA("BasePart") then
		table.insert(Parts, RootInstance)
		return Parts
	end

	local Descendants = RootInstance:GetDescendants()
	for Index = 1, #Descendants do
		local Descendant = Descendants[Index]
		if Descendant:IsA("BasePart") then
			table.insert(Parts, Descendant)
		end
	end

	return Parts
end

local function GetLeftArmPart(Character: Model): BasePart | nil
	local LeftArm = Character:FindFirstChild("Left Arm")
	if LeftArm and LeftArm:IsA("BasePart") then
		return LeftArm
	end

	local LeftHand = Character:FindFirstChild("LeftHand")
	if LeftHand and LeftHand:IsA("BasePart") then
		return LeftHand
	end

	local LeftLowerArm = Character:FindFirstChild("LeftLowerArm")
	if LeftLowerArm and LeftLowerArm:IsA("BasePart") then
		return LeftLowerArm
	end

	local LeftUpperArm = Character:FindFirstChild("LeftUpperArm")
	if LeftUpperArm and LeftUpperArm:IsA("BasePart") then
		return LeftUpperArm
	end

	return nil
end

local function GetMovementControls()
	if not LocalPlayer then
		return nil
	end

	local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if not PlayerScripts then
		return nil
	end

	local PlayerModule = PlayerScripts:FindFirstChild("PlayerModule")
	if not PlayerModule or not PlayerModule:IsA("ModuleScript") then
		return nil
	end

	local Success, ModuleOrError = pcall(require, PlayerModule)
	if not Success then
		return nil
	end

	if typeof(ModuleOrError) ~= "table" or typeof(ModuleOrError.GetControls) ~= "function" then
		return nil
	end

	local Controls = ModuleOrError:GetControls()
	if not Controls then
		return nil
	end

	return Controls
end

local function BlockJumpAction(): Enum.ContextActionResult
	return Enum.ContextActionResult.Sink
end

local function EnforceZiplineAnimationOnly(State: ZiplineState, Humanoid: Humanoid)
	local ZiplineTrack = State.ZiplineTrack
	if not ZiplineTrack then
		return
	end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		return
	end

	local PlayingTracks = Animator:GetPlayingAnimationTracks()
	for Index = 1, #PlayingTracks do
		local Track = PlayingTracks[Index]
		if Track ~= ZiplineTrack then
			Track:Stop(0.05)
		end
	end
end

function Zipline:FindNearbyZipline(Character: Model, RootPart: BasePart): ZiplineTarget | nil
	-- Nothing to attach to if ziplining is switched off in
	-- MovementSettings, or if the loaded map has no Ziplines
	-- folder in it.
	if not MovementGate:IsEnabled("Zipline") or not ZiplinesFolder then
		return nil
	end

	local BestTarget: ZiplineTarget | nil = nil
	local BestDistance = math.huge

	local Children = ZiplinesFolder:GetChildren()
	for Index = 1, #Children do
		local ZiplineInstance = Children[Index]
		local StartPosition, EndPosition = ResolveZiplineEndpoints(ZiplineInstance)
		if StartPosition and EndPosition then
			local SegmentLength = (EndPosition - StartPosition).Magnitude
			if SegmentLength > 0.01 then
				local ClosestPoint = GetClosestPointOnZipline(ZiplineInstance, RootPart.Position, StartPosition, EndPosition)
				local Distance = (ClosestPoint - RootPart.Position).Magnitude
				if Distance <= self.Settings.DetectRadius and Distance < BestDistance then
					BestDistance = Distance
					BestTarget = {
						Zipline = ZiplineInstance,
						StartPosition = StartPosition,
						EndPosition = EndPosition,
						ClosestPoint = ClosestPoint,
						SegmentLength = SegmentLength,
					}
				end
			end
		end
	end

	return BestTarget
end

function Zipline:Stop(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State or not State.IsZiplining then
		return
	end

	State.IsZiplining = false
	Character:SetAttribute("ziplining", false)
	Character:SetAttribute("busy", false)

	if State.ControlsLockedByZipline then
		local Controls = GetMovementControls()
		if Controls and typeof(Controls.Enable) == "function" then
			Controls:Enable()
		end
	end
	State.ControlsLockedByZipline = false

	if State.JumpLockedByZipline then
		ContextActionService:UnbindAction(ZIPLINE_BLOCK_JUMP_ACTION)
	end
	State.JumpLockedByZipline = false

	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	if Humanoid and State.PreviousJumpStateEnabled ~= nil then
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, State.PreviousJumpStateEnabled)
	end
	State.PreviousJumpStateEnabled = nil

	Network.Fire({
		module = "Visuals",
		method = "ziplinestop",
		msg = "",
		animLength = 0,
	}, "Core")

	local CurrentCamera = workspace.CurrentCamera
	if CurrentCamera then
		local ResetFovTween = TweenService:Create(
			CurrentCamera,
			TweenInfo.new(self.Settings.FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 70 }
		)
		ResetFovTween:Play()
	end

	if State.HeartbeatConnection then
		State.HeartbeatConnection:Disconnect()
		State.HeartbeatConnection = nil
	end

	if State.ZiplineTrack and State.ZiplineTrack.IsPlaying then
		State.ZiplineTrack:Stop()
	end

	local RootPart = State.RootPart or GetRootPart(Character)
	if RootPart then
		HelperFunctions.clearVelocity(RootPart, "ZiplineVelocity")
	end

	Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	if Humanoid and State.PreviousAutoRotate ~= nil then
		Humanoid.AutoRotate = State.PreviousAutoRotate
	end
	State.PreviousAutoRotate = nil

	State.LastSurfacePoint = nil
	State.CurrentTarget = nil
	State.Pocket:destroy()
	State.Pocket = Pocket.new()
end

function Zipline:TriggerEndLeap(Character: Model)
	Leap:ZiplineLeap(Character)
end

function Zipline:JumpOff(Character: Model): boolean
	local State = self.StateByCharacter[Character]
	if not State or not State.IsZiplining then
		return false
	end

	if (os.clock() - State.LastZiplineTime) < self.Settings.JumpOffMinTime then
		return false
	end

	local RootPart = State.RootPart or GetRootPart(Character)
	if RootPart then
		local CurrentCamera = workspace.CurrentCamera
		if CurrentCamera then
			local CameraLookDirection = CurrentCamera.CFrame.LookVector
			if CameraLookDirection.Magnitude > 0 then
				RootPart.CFrame = CFrame.lookAt(
					RootPart.Position,
					RootPart.Position + CameraLookDirection.Unit
				)
			end
		end
	end

	self:Stop(Character)
	State.LastZiplineTime = os.clock() + self.Settings.JumpOffExtraCooldown
	self:TriggerEndLeap(Character)
	return true
end

function Zipline:Start(Character, Target, ZiplineAnimation)
	local State = GetCharacterState(self, Character)
	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	local RootPart = State.RootPart or GetRootPart(Character)

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart or State.IsZiplining then
		return false
	end

	local SelectedAnimation = ZiplineAnimation or self.Settings.ZiplineAnimation
	if not SelectedAnimation then
		return false
	end

	Network.Fire({
		module = "Visuals",
		method = "ziplinestart",
		msg = "",
		animLength = 0,
	}, "Core")

	local LineDirection = Target.EndPosition - Target.StartPosition
	if LineDirection.Magnitude <= 0.01 then
		return false
	end

	local ForwardDirection = LineDirection.Unit
	if RootPart.CFrame.LookVector:Dot(ForwardDirection) < 0 then
		local PreviousStart = Target.StartPosition
		Target.StartPosition = Target.EndPosition
		Target.EndPosition = PreviousStart
		Target.SegmentLength = (Target.EndPosition - Target.StartPosition).Magnitude
		ForwardDirection = -ForwardDirection
	end

	local StartClosestPoint = GetClosestPointOnZipline(Target.Zipline, RootPart.Position, Target.StartPosition, Target.EndPosition)
	State.LastSurfacePoint = StartClosestPoint
	local StartLookDirection = GetSlopeLookDirection(ForwardDirection, RootPart, self.Settings.PitchInfluence)
	local StartSnapPosition: Vector3
	local LeftArmPart = GetLeftArmPart(Character)
	if LeftArmPart then
		local StartDesiredArmPosition = StartClosestPoint - Vector3.yAxis * self.Settings.LeftArmYOffset
		local StartArmDelta = StartDesiredArmPosition - LeftArmPart.Position
		StartSnapPosition = RootPart.Position + StartArmDelta
	else
		local StartHeightOffset = math.max(0, Humanoid.HipHeight + self.Settings.HeightOffsetFromHip)
		StartSnapPosition = Vector3.new(
			StartClosestPoint.X,
			StartClosestPoint.Y - StartHeightOffset,
			StartClosestPoint.Z
		)
	end

	HelperFunctions.clearVelocity(RootPart)
	RootPart.AssemblyLinearVelocity = Vector3.zero
	RootPart.AssemblyAngularVelocity = Vector3.zero
	RootPart.CFrame = CFrame.lookAt(StartSnapPosition, StartSnapPosition + StartLookDirection)

	State.IsZiplining = true
	State.LastZiplineTime = os.clock()
	State.CurrentTarget = Target
	Character:SetAttribute("ziplining", true)
	Character:SetAttribute("busy", true)

	State.ControlsLockedByZipline = false
	State.JumpLockedByZipline = false
	if LocalPlayer and LocalPlayer.Character == Character then
		local Controls = GetMovementControls()
		if Controls and typeof(Controls.Disable) == "function" then
			Controls:Disable()
			State.ControlsLockedByZipline = true
		end

		ContextActionService:BindActionAtPriority(
			ZIPLINE_BLOCK_JUMP_ACTION,
			BlockJumpAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.PlayerActions.CharacterJump
		)
		State.JumpLockedByZipline = true

		State.PreviousJumpStateEnabled = Humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
		Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		Humanoid.Jump = false
	end

	State.PreviousAutoRotate = Humanoid.AutoRotate
	Humanoid.AutoRotate = false

	local CurrentCamera = workspace.CurrentCamera
	if CurrentCamera then
		local BoostFovTween = TweenService:Create(
			CurrentCamera,
			TweenInfo.new(self.Settings.FovTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 70 + self.Settings.AttachFovBoost }
		)
		BoostFovTween:Play()
	end

	CameraShake:Shake(self.Settings.StartShakeIntensity, self.Settings.StartShakeDuration)

	HelperFunctions.stopAll(Character)

	local ZiplineTrack = HelperFunctions.playAnim(Character, SelectedAnimation, true)
	State.ZiplineTrack = ZiplineTrack
	if ZiplineTrack then
		ZiplineTrack.Priority = Enum.AnimationPriority.Action4
		ZiplineTrack.Looped = true
		State.Pocket:add(ZiplineTrack)
		EnforceZiplineAnimationOnly(State, Humanoid)

		local Animator = Humanoid:FindFirstChildOfClass("Animator")
		if Animator then
			local AnimationGuardConnection = Animator.AnimationPlayed:Connect(function(Track)
				if not State.IsZiplining then
					return
				end
				if Track ~= State.ZiplineTrack then
					Track:Stop(0.05)
				end
			end)
			State.Pocket:add(AnimationGuardConnection)
		end
	end

	if self.Settings.DisableZiplineCollisions then
		local CharacterParts = CollectBaseParts(Character)
		local ZiplineParts = CollectBaseParts(Target.Zipline)
		for CharacterIndex = 1, #CharacterParts do
			local CharacterPart = CharacterParts[CharacterIndex]
			for ZiplineIndex = 1, #ZiplineParts do
				local ZiplinePart = ZiplineParts[ZiplineIndex]
				local Constraint = Instance.new("NoCollisionConstraint")
				Constraint.Part0 = CharacterPart
				Constraint.Part1 = ZiplinePart
				Constraint.Parent = Character
				State.Pocket:add(Constraint)
			end
		end
	end

	local DurationFromLength = Target.SegmentLength / math.max(self.Settings.TravelSpeed, 1)
	local ZiplineVelocity = HelperFunctions.velocity(
		RootPart,
		ForwardDirection * self.Settings.TravelSpeed,
		DurationFromLength + 1,
		true,
		"ZiplineVelocity"
	)
	if ZiplineVelocity then
		State.Pocket:add(ZiplineVelocity)
	end

	State.HeartbeatConnection = RunService.Heartbeat:Connect(function()
		if not State.IsZiplining then
			return
		end

		local CurrentHumanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
		if CurrentHumanoid then
			State.Humanoid = CurrentHumanoid
			if CurrentHumanoid.AutoRotate then
				CurrentHumanoid.AutoRotate = false
			end
			EnforceZiplineAnimationOnly(State, CurrentHumanoid)
		end

		local CurrentRootPart = GetRootPart(Character)
		if not CurrentRootPart or not Character.Parent then
			self:Stop(Character)
			return
		end

		local CurrentTarget = State.CurrentTarget
		if not CurrentTarget then
			self:Stop(Character)
			return
		end

		local DirectionVector = CurrentTarget.EndPosition - CurrentTarget.StartPosition
		if DirectionVector.Magnitude <= 0.01 then
			self:Stop(Character)
			return
		end

		local Direction = DirectionVector.Unit
		local ClosestPoint = GetClosestPointOnZipline(
			CurrentTarget.Zipline,
			CurrentRootPart.Position,
			CurrentTarget.StartPosition,
			CurrentTarget.EndPosition
		)
		if CurrentTarget.Zipline:IsA("UnionOperation") then
			if State.LastSurfacePoint then
				local SurfaceDirection = ClosestPoint - State.LastSurfacePoint
				if SurfaceDirection.Magnitude > 0.05 then
					Direction = SurfaceDirection.Unit
				end
			end
			State.LastSurfacePoint = ClosestPoint
		end
		local DistanceToEnd = (CurrentTarget.EndPosition - ClosestPoint).Magnitude
		local EarlyDetachDistance = math.max(self.Settings.EndDistance, CurrentTarget.SegmentLength * self.Settings.EarlyDetachRatio)
		local ElapsedOnZipline = os.clock() - State.LastZiplineTime
		if ElapsedOnZipline >= self.Settings.MinDetachTime and DistanceToEnd <= EarlyDetachDistance then
			self:Stop(Character)
			self:TriggerEndLeap(Character)
			return
		end

		local LookDirection = GetSlopeLookDirection(Direction, CurrentRootPart, self.Settings.PitchInfluence)
		CurrentRootPart.CFrame = CFrame.lookAt(CurrentRootPart.Position, CurrentRootPart.Position + LookDirection)

		local CurrentVelocityObject = CurrentRootPart:FindFirstChild("ZiplineVelocity", true)
		if CurrentVelocityObject and CurrentVelocityObject:IsA("LinearVelocity") then
			local LeftArmReference = GetLeftArmPart(Character)
			local PositionError: Vector3
			if LeftArmReference then
				local DesiredArmPosition = ClosestPoint - Vector3.yAxis * self.Settings.LeftArmYOffset
				PositionError = DesiredArmPosition - LeftArmReference.Position
			else
				local HeightOffset = math.max(0, Humanoid.HipHeight + self.Settings.HeightOffsetFromHip)
				local DesiredY = ClosestPoint.Y - HeightOffset
				local DesiredPosition = Vector3.new(ClosestPoint.X, DesiredY, ClosestPoint.Z)
				PositionError = DesiredPosition - CurrentRootPart.Position
			end

			local CorrectionPerpendicular = PositionError - Direction * PositionError:Dot(Direction)
			local CorrectionVelocity = CorrectionPerpendicular * self.Settings.LineSnapStrength
			if CorrectionVelocity.Magnitude > self.Settings.MaxSnapSpeed then
				CorrectionVelocity = CorrectionVelocity.Unit * self.Settings.MaxSnapSpeed
			end
			CurrentVelocityObject.VectorVelocity = Direction * self.Settings.TravelSpeed + CorrectionVelocity
		end
	end)

	State.Pocket:add(State.HeartbeatConnection)
	return true
end

function Zipline:TryAutoZipline(Character: Model, ZiplineAnimation: Animation | nil)
	local State = GetCharacterState(self, Character)
	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	local RootPart = State.RootPart or GetRootPart(Character)

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart then
		return
	end

	if State.IsZiplining then
		return
	end

	if Character:GetAttribute("busy") then
		return
	end

	if Character:GetAttribute("leaping") then
		return
	end

	if os.clock() - State.LastZiplineTime < self.Settings.Cooldown then
		return
	end

	local Target = self:FindNearbyZipline(Character, RootPart)
	if not Target then
		return
	end

	self:Start(Character, Target, ZiplineAnimation)
end

return Zipline