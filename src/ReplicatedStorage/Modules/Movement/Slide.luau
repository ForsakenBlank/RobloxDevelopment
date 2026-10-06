local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.Sliding
local Modules = ReplicatedStorage.Modules

local HelperFunctions = require(Modules.Shared.HelperFunctions)
local Network = require(Modules.Shared.Network.Network)
local Pocket = require(Modules.Shared.Pocket)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local Sound = require(Modules.Shared.Sound)

type PocketType = typeof(Pocket.new())

type SlideSettings = {
	SlideStartAnimation: Animation,
	SlideLoopedAnimation: Animation,
	SlideCancelAnimation: Animation,
	SlideDuration: number,
	BaseSlideSpeed: number,
	MaxExtraFromMomentum: number,
	SlideCooldown: number,
	SlideCancelDuration: number,
	SlideCancelForwardSpeed: number,
	SlideCancelUpSpeed: number,
}

export type SlideState = {
	Character: Model,
	Humanoid: Humanoid?,
	RootPart: BasePart?,
	CanSlide: boolean,
	IsSliding: boolean,
	CancelRequested: boolean,
	SlideStartTrack: AnimationTrack?,
	SlideLoopedTrack: AnimationTrack?,
	CancelTrack: AnimationTrack?,
	HeartbeatConnection: RBXScriptConnection?,
	Pocket: PocketType,
}

local Slide = {}
Slide.__index = Slide

local function GetAnimation(Name: string): Animation
	local AnimationObject = Animations:WaitForChild(Name)
	if AnimationObject:IsA("Animation") then
		return AnimationObject
	end

	error("Missing animation: " .. Name)
end

local Settings: SlideSettings = {
	SlideStartAnimation = GetAnimation("Slide_Start"),
	SlideLoopedAnimation = GetAnimation("Slide_Looped"),
	SlideCancelAnimation = GetAnimation("Slide_Cancel"),
	SlideDuration = MovementConfig.SLIDE_DURATION,
	BaseSlideSpeed = MovementConfig.BASE_SLIDE_SPEED,
	MaxExtraFromMomentum = math.huge,
	SlideCooldown = MovementConfig.SLIDE_COOLDOWN,
	SlideCancelDuration = MovementConfig.SLIDE_CANCEL_DURATION,
	SlideCancelForwardSpeed = MovementConfig.SLIDE_CANCEL_FORWARD_SPEED,
	SlideCancelUpSpeed = MovementConfig.SLIDE_CANCEL_UP_SPEED,
}

Slide.Settings = Settings
Slide.StateByCharacter = {} :: { [Model]: SlideState }

local function GetRootPart(Character: Model): BasePart?
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	if not RootPartObject or not RootPartObject:IsA("BasePart") then
		return nil
	end

	return RootPartObject
end

function Slide:GetCharacterState(Character: Model): SlideState
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
		CanSlide = true,
		IsSliding = false,
		CancelRequested = false,
		SlideStartTrack = nil,
		SlideLoopedTrack = nil,
		CancelTrack = nil,
		HeartbeatConnection = nil,
		Pocket = Pocket.new(),
	}

	self.StateByCharacter[Character] = State
	return State
end

function Slide:ClearSlideState(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State then
		return
	end

	if State.HeartbeatConnection then
		State.HeartbeatConnection:Disconnect()
		State.HeartbeatConnection = nil
	end

	if State.SlideStartTrack and State.SlideStartTrack.IsPlaying then
		State.SlideStartTrack:Stop()
	end

	if State.SlideLoopedTrack and State.SlideLoopedTrack.IsPlaying then
		State.SlideLoopedTrack:Stop()
	end

	if State.CancelTrack and State.CancelTrack.IsPlaying then
		State.CancelTrack:Stop()
	end

	State.Pocket:destroy()
	self.StateByCharacter[Character] = nil
end

function Slide:Stop(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State or not State.IsSliding then
		return
	end

	State.IsSliding = false
	State.CancelRequested = false
	Character:SetAttribute("sliding", nil)

	if State.HeartbeatConnection then
		State.HeartbeatConnection:Disconnect()
		State.HeartbeatConnection = nil
	end

	if State.SlideStartTrack and State.SlideStartTrack.IsPlaying then
		State.SlideStartTrack:Stop()
	end

	if State.SlideLoopedTrack and State.SlideLoopedTrack.IsPlaying then
		State.SlideLoopedTrack:Stop()
	end
end

function Slide:Start(Character: Model)
	local State = self:GetCharacterState(Character)
	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	local RootPart = State.RootPart or GetRootPart(Character)

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart then
		return
	end

	if not State.CanSlide or State.IsSliding then
		return
	end

	if Humanoid.FloorMaterial == Enum.Material.Air then
		return
	end

	if Character:GetAttribute("state") == "crouching" then
		return
	end

	State.CanSlide = false
	State.IsSliding = true
	State.CancelRequested = false

	Character:SetAttribute("sliding", true)
	Sound:Play("Slide", Character)

	local SlideStartTrack = HelperFunctions.playAnim(Character, self.Settings.SlideStartAnimation, true)
	State.SlideStartTrack = SlideStartTrack
	if SlideStartTrack then
		State.Pocket:add(SlideStartTrack)
	end

	local StartTrackLength = if SlideStartTrack then SlideStartTrack.Length else 0
	local StartToLoopThread = task.delay(StartTrackLength, function()
		local CurrentState = self.StateByCharacter[Character]
		if not CurrentState or not CurrentState.IsSliding then
			return
		end

		if CurrentState.CancelRequested or Character:GetAttribute("SlideCancel") then
			return
		end

		local SlideLoopedTrack = HelperFunctions.playAnim(Character, self.Settings.SlideLoopedAnimation, true)
		CurrentState.SlideLoopedTrack = SlideLoopedTrack
		if SlideLoopedTrack then
			SlideLoopedTrack.Looped = false
			CurrentState.Pocket:add(SlideLoopedTrack)

			local SlideEndThread = task.delay(SlideLoopedTrack.Length, function()
				if Character and Character.Parent then
					Character:SetAttribute("sliding", nil)
				end
			end)
			CurrentState.Pocket:add(SlideEndThread)
		end
	end)
	State.Pocket:add(StartToLoopThread)

	Network.Fire({
		module = "Visuals",
		method = "dashsmoke",
		msg = "",
		animLength = 0
	}, "Core")

	local CurrentVelocity = RootPart.AssemblyLinearVelocity
	local HorizontalVelocity = Vector3.new(CurrentVelocity.X, 0, CurrentVelocity.Z)
	local HorizontalSpeed = HorizontalVelocity.Magnitude
	local SlideDirection = if HorizontalSpeed > 1 then HorizontalVelocity.Unit else RootPart.CFrame.LookVector
	local ExtraFromMomentum = math.clamp(HorizontalSpeed, 0, self.Settings.MaxExtraFromMomentum)
	local InitialExtraSlideSpeed = self.Settings.BaseSlideSpeed + ExtraFromMomentum
	local StartTime = tick()

	State.HeartbeatConnection = RunService.Heartbeat:Connect(function()
		local CurrentState = self.StateByCharacter[Character]
		local CurrentRootPart = GetRootPart(Character)
		if not CurrentState or not CurrentState.IsSliding or not CurrentRootPart or not Character.Parent then
			self:Stop(Character)
			return
		end

		local Elapsed = tick() - StartTime
		if Elapsed >= self.Settings.SlideDuration then
			self:Stop(Character)
			return
		end

		local CurrentLinearVelocity = CurrentRootPart.AssemblyLinearVelocity
		local CurrentHorizontalVelocity = Vector3.new(CurrentLinearVelocity.X, 0, CurrentLinearVelocity.Z)
		local TimeAlpha = math.clamp(Elapsed / self.Settings.SlideDuration, 0, 1)
		local TargetExtraSpeed = InitialExtraSlideSpeed * (1 - TimeAlpha)
		local ProjectedSpeed = SlideDirection:Dot(CurrentHorizontalVelocity)

		if ProjectedSpeed < TargetExtraSpeed then
			local RequiredExtra = TargetExtraSpeed - ProjectedSpeed
			local AdditionalVector = SlideDirection * RequiredExtra
			local NewHorizontalVelocity = CurrentHorizontalVelocity + AdditionalVector

			CurrentRootPart.AssemblyLinearVelocity = Vector3.new(
				NewHorizontalVelocity.X,
				CurrentLinearVelocity.Y,
				NewHorizontalVelocity.Z
			)
		end
	end)

	State.Pocket:add(State.HeartbeatConnection)

	local CooldownThread = task.delay(self.Settings.SlideCooldown, function()
		local CurrentState = self.StateByCharacter[Character]
		if not CurrentState then
			return
		end

		if not CurrentState.IsSliding then
			CurrentState.CanSlide = true
			return
		end

		local SecondCooldownThread = task.delay(0.1, function()
			local LatestState = self.StateByCharacter[Character]
			if LatestState and not LatestState.IsSliding then
				LatestState.CanSlide = true
			end
		end)

		CurrentState.Pocket:add(SecondCooldownThread)
	end)

	State.Pocket:add(CooldownThread)
end

function Slide:CanCancel(Character: Model): boolean
	local State = self.StateByCharacter[Character]
	if not State then
		return false
	end

	if Character:GetAttribute("vaulting") then
		return false
	end

	return State.IsSliding == true
end

function Slide:Cancel(Character: Model)
	local State = self:GetCharacterState(Character)
	local Humanoid = State.Humanoid or Character:FindFirstChildOfClass("Humanoid")
	local RootPart = State.RootPart or GetRootPart(Character)

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not State.IsSliding or not Humanoid or not RootPart then
		return
	end

	State.CancelRequested = true
	State.IsSliding = false
	Character:SetAttribute("sliding", nil)

	if State.HeartbeatConnection then
		State.HeartbeatConnection:Disconnect()
		State.HeartbeatConnection = nil
	end

	if State.SlideStartTrack and State.SlideStartTrack.IsPlaying then
		State.SlideStartTrack:Stop()
	end

	if State.SlideLoopedTrack and State.SlideLoopedTrack.IsPlaying then
		State.SlideLoopedTrack:Stop()
	end

	HelperFunctions.stopAll(Character)
	HelperFunctions.flashoutlinedHighlight(Character, 0.5)

	local CancelTrack = HelperFunctions.playAnim(Character, self.Settings.SlideCancelAnimation, true)
	State.CancelTrack = CancelTrack
	if CancelTrack then
		CancelTrack.Priority = Enum.AnimationPriority.Action4
		CancelTrack.Looped = false
		State.Pocket:add(CancelTrack)
	end

	Sound:Play("Slide Cancel", Character)
	Character:SetAttribute("SlideCancel", true)

	local CancelResetThread = task.delay((if CancelTrack then CancelTrack.Length + 1 else 1), function()
		if Character and Character.Parent then
			Character:SetAttribute("SlideCancel", nil)
		end
	end)
	State.Pocket:add(CancelResetThread)

	HelperFunctions.clearVelocity(RootPart, "SlideCancel")

	local ForwardDirection = RootPart.CFrame.LookVector
	local LaunchVelocity = ForwardDirection * self.Settings.SlideCancelForwardSpeed + Vector3.yAxis * self.Settings.SlideCancelUpSpeed

	HelperFunctions.velocity(
		RootPart,
		LaunchVelocity,
		self.Settings.SlideCancelDuration,
		false,
		"SlideCancel"
	)
end

return Slide