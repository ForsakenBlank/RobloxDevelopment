local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SharedModules = ReplicatedStorage.Modules.Shared
local CameraShake = require(SharedModules.CameraShake)
local HelperFunctions = require(SharedModules.HelperFunctions)
local MovementConfig = require(SharedModules.MovementConfig)
local Network = require(SharedModules.Network.Network)
local Pocket = require(SharedModules.Pocket)
local Sound = require(SharedModules.Sound)
local MovementSettings = require(SharedModules.MovementSettings)

local DashTuning = MovementSettings.Abilities.Dash

local Animations = ReplicatedStorage.Assets.Animations.Dashing

type DashState = {
	Character: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Cleaner: any,
	FaceConnection: RBXScriptConnection | nil,
}

local Dash = {}
Dash.__index = Dash

Dash.Settings = {
	DashDirections = {
		Front = Vector3.new(0, 0, -2),
		Back = Vector3.new(0, 0, 3),
		Right = Vector3.new(2, 0, 0),
		Left = Vector3.new(-2, 0, 0),
	},
	DebrisTime = DashTuning.DebrisTime,
	-- As strong as the air dash, so the character's own ground movement
	-- never drags a dash on the ground.
	GroundMaxForce = Vector3.new(99999, 0, 99999),
	AirMaxForce = Vector3.new(99999, 99999, 99999),
	SideSpeedScale = DashTuning.SideSpeedScale,
	BackSpeedScale = DashTuning.BackSpeedScale,
	ForwardSpeedScale = DashTuning.ForwardSpeedScale,
	AttributeDashing = "dashing",
	BackDashSound = "Back Dash",
	DashSound = "Dash",
	FaceDuration = DashTuning.FaceDuration,
	VelocityEndLeadTime = DashTuning.VelocityEndLeadTime,
	MinVelocityDuration = DashTuning.MinVelocityDuration,
	BackBoostMarkerName = "Boost",
	BackBoostShakeIntensity = DashTuning.BackBoostShakeIntensity,
	BackBoostShakeDuration = DashTuning.BackBoostShakeDuration,
	BackInitialVelocityScale = DashTuning.BackInitialVelocityScale,
	BackBoostVelocityScale = DashTuning.BackBoostVelocityScale,
	BackBoostDuration = DashTuning.BackBoostDuration,
	FrontBurstVelocityScale = DashTuning.FrontBurstVelocityScale,
	SideBurstVelocityScale = DashTuning.SideBurstVelocityScale,
	NonBackCarryVelocityScale = DashTuning.NonBackCarryVelocityScale,
	NonBackBurstRatio = DashTuning.NonBackBurstRatio,
	SideBurstRatio = DashTuning.SideBurstRatio,
	VelocityDurationScale = DashTuning.VelocityDurationScale,
	NonBackShakeIntensity = DashTuning.NonBackShakeIntensity,
	NonBackShakeDuration = DashTuning.NonBackShakeDuration,
	AirKeepVerticalVelocity = DashTuning.AirKeepVerticalVelocity,
}

Dash.CharacterStates = {} :: { [Model]: DashState }

function Dash:GetState(Character: Model): DashState?
	return self.CharacterStates[Character]
end

function Dash:SetState(Character: Model, StateTable: DashState)
	self.CharacterStates[Character] = StateTable
end

function Dash:ClearState(Character: Model)
	local CurrentState = self:GetState(Character)
	if not CurrentState then
		return
	end

	if CurrentState.Cleaner then
		CurrentState.Cleaner:destroy()
	end

	self.CharacterStates[Character] = nil
end

function Dash:EnsureState(Character: Model): DashState?
	local CurrentState = self:GetState(Character)
	if CurrentState then
		local CurrentHumanoid = Character:FindFirstChildOfClass("Humanoid")
		local CurrentRootPart = Character:FindFirstChild("HumanoidRootPart")
		if CurrentHumanoid and CurrentRootPart and CurrentRootPart:IsA("BasePart") then
			CurrentState.Humanoid = CurrentHumanoid
			CurrentState.RootPart = CurrentRootPart
			return CurrentState
		end
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local RootPart = Character:FindFirstChild("HumanoidRootPart")
	if not Humanoid or not RootPart or not RootPart:IsA("BasePart") then
		return nil
	end

	local Cleaner = Pocket.new()
	local NewState: DashState = {
		Character = Character,
		Humanoid = Humanoid,
		RootPart = RootPart,
		Cleaner = Cleaner,
		FaceConnection = nil,
	}

	self:SetState(Character, NewState)
	return NewState
end

function Dash:FaceForward(Character: Model)
	local State = self:EnsureState(Character)
	if not State then
		return
	end

	local CurrentCamera = workspace.CurrentCamera
	if not CurrentCamera then
		return
	end

	if State.FaceConnection then
		State.FaceConnection:Disconnect()
		State.FaceConnection = nil
	end

	local FaceElapsed = 0
	State.FaceConnection = RunService.Heartbeat:Connect(function(DeltaTime)
		FaceElapsed += DeltaTime

		local LookDirection = CurrentCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
		if LookDirection.Magnitude > 0 then
			local HorizontalLook = LookDirection.Unit
			State.RootPart.CFrame = CFrame.lookAt(
				State.RootPart.Position,
				State.RootPart.Position + HorizontalLook
			)
		end

		if FaceElapsed >= self.Settings.FaceDuration then
			if State.FaceConnection then
				State.FaceConnection:Disconnect()
				State.FaceConnection = nil
			end
		end
	end)

	State.Cleaner:add(State.FaceConnection)
end

function Dash:Dash(Character: Model, Direction: string)
	local State = self:EnsureState(Character)
	if not State then
		return
	end

	local RootPart = State.RootPart
	local Humanoid = State.Humanoid
	local DashDirectionVector = self.Settings.DashDirections[Direction]
	local DashForceValue = MovementConfig.DASHING_VELOCITYS[Direction]
	if not RootPart or not Humanoid or not DashDirectionVector or not DashForceValue then
		return
	end

	HelperFunctions.clearVelocity(RootPart)

	local BaseVelocity = DashDirectionVector * DashForceValue
	local Velocity = BaseVelocity
	local MaxForceValue = self.Settings.GroundMaxForce
	local InAir = Humanoid.FloorMaterial == Enum.Material.Air

	if InAir then
		MaxForceValue = self.Settings.AirMaxForce
		if self.Settings.AirKeepVerticalVelocity then
			Velocity = Vector3.new(Velocity.X, RootPart.AssemblyLinearVelocity.Y, Velocity.Z)
		else
			Velocity = Vector3.new(Velocity.X, 0, Velocity.Z)
		end
	end

	if Direction == "Front" and InAir then
		Network.Fire({
			module = "Visuals",
			method = "frontdash",
			msg = Direction,
			animLength = 0,
		}, "Core")
	end

	self:FaceForward(Character)
	HelperFunctions.stopAll(Character, "Run")

	local AnimationAsset = Animations[Direction .. "Dash"]
	if not AnimationAsset then
		return
	end

	local AnimationTrack = HelperFunctions.playAnim(Character, AnimationAsset, true)
	if not AnimationTrack then
		return
	end

	AnimationTrack.Priority = Enum.AnimationPriority.Action4
	local AppliedAnimationSpeed = 1

	if Direction == "Left" or Direction == "Right" then
		
		Sound:Play("Side Dash", Character)
		Network.Fire({
			module = "Visuals",
			method = "sidedash",
			msg = Direction,
			animLength = 0,
		}, "Core")
		
		AppliedAnimationSpeed = math.max(0.05, AnimationTrack.Length * self.Settings.SideSpeedScale)
		AnimationTrack:AdjustSpeed(AppliedAnimationSpeed)
	elseif Direction == "Back" then
		Velocity = BaseVelocity * self.Settings.BackInitialVelocityScale
		AppliedAnimationSpeed = math.max(0.05, AnimationTrack.Length * self.Settings.BackSpeedScale)
		AnimationTrack:AdjustSpeed(AppliedAnimationSpeed)
		Sound:Play(self.Settings.BackDashSound, Character)

		local BoostConnection = AnimationTrack:GetMarkerReachedSignal(self.Settings.BackBoostMarkerName):Connect(function()
			if not Character or not Character.Parent then
				return
			end
			
			Sound:Play("Back Dash Boost", Character)
			
			Network.Fire({
				module = "Visuals",
				method = "backdash",
				msg = "",
				animLength = 0,
			}, "Core")

			CameraShake:Shake(self.Settings.BackBoostShakeIntensity, self.Settings.BackBoostShakeDuration)

			local BoostVelocity = BaseVelocity * self.Settings.BackBoostVelocityScale
			local BoostDuration = math.max(0.03, self.Settings.BackBoostDuration)
			HelperFunctions.dashVelocity(RootPart, BoostVelocity, BoostDuration, MaxForceValue)
		end)
		State.Cleaner:add(BoostConnection)

		task.delay(0.1, function()
			local SecondBackTrack = HelperFunctions.playAnim(Character, AnimationAsset, true)
			if SecondBackTrack then
				SecondBackTrack:AdjustSpeed(SecondBackTrack.Length * self.Settings.BackSpeedScale)
			end
		end)
	else
		AppliedAnimationSpeed = math.max(0.05, AnimationTrack.Length * self.Settings.ForwardSpeedScale)
		AnimationTrack:AdjustSpeed(AppliedAnimationSpeed)
		Sound:Play(self.Settings.DashSound, Character)
	end

	local AnimationLength = AnimationTrack.Length
	if AnimationLength <= 0 then
		AnimationLength = self.Settings.DebrisTime
	end

	local EffectiveAnimationLength = AnimationLength / AppliedAnimationSpeed

	local VelocityDuration = math.max(
		self.Settings.MinVelocityDuration,
		EffectiveAnimationLength * self.Settings.VelocityDurationScale - self.Settings.VelocityEndLeadTime
	)
	VelocityDuration = math.min(VelocityDuration, self.Settings.DebrisTime)

	Character:SetAttribute(self.Settings.AttributeDashing, true)
	if Direction == "Back" then
		HelperFunctions.dashVelocity(RootPart, Velocity, VelocityDuration, MaxForceValue)
	else
		CameraShake:Shake(self.Settings.NonBackShakeIntensity, self.Settings.NonBackShakeDuration)

		local BurstScale = self.Settings.SideBurstVelocityScale
		if Direction == "Front" then
			BurstScale = self.Settings.FrontBurstVelocityScale
		end

		local BurstRatio = self.Settings.NonBackBurstRatio
		if Direction == "Left" or Direction == "Right" then
			BurstRatio = self.Settings.SideBurstRatio
		end

		local BurstDuration = math.clamp(
			VelocityDuration * BurstRatio,
			0.04,
			math.max(0.04, VelocityDuration - 0.06)
		)
		local CarryDuration = math.max(0.06, VelocityDuration - BurstDuration)

		local BurstVelocity = Velocity * BurstScale
		local CarryVelocity = Velocity * self.Settings.NonBackCarryVelocityScale

		HelperFunctions.dashVelocity(RootPart, BurstVelocity, BurstDuration, MaxForceValue)
		task.delay(BurstDuration, function()
			if not Character or not Character.Parent then
				return
			end
			if Character:GetAttribute(self.Settings.AttributeDashing) ~= true then
				return
			end
			HelperFunctions.dashVelocity(RootPart, CarryVelocity, CarryDuration, MaxForceValue)
		end)
	end

	Network.Fire({
		module = "Visuals",
		method = "dashsmoke",
		msg = Direction,
		animLength = AnimationLength,
	}, "Core")

	task.delay(VelocityDuration, function()
		if Character and Character.Parent then
			Character:SetAttribute(self.Settings.AttributeDashing, false)
		end
	end)
end

return Dash