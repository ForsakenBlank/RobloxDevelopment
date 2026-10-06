local Run = {}
Run.__index = Run

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.Fundamental

local Modules = ReplicatedStorage.Modules
local SharedModules = Modules.Shared

local HelperFunctions = require(SharedModules.HelperFunctions)
local Network = require(SharedModules.Network.Network)
local Pocket = require(SharedModules.Pocket)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)
local Sound = require(ReplicatedStorage.Modules.Shared.Sound)

Run.States = {}
Run.Camera = workspace.CurrentCamera
Run.RunAnimation = Animations.Run

Run.Settings = {
	FastRunDelay = MovementConfig.FAST_RUN_DELAY,
	BaseRunSpeed = MovementConfig.BASE_RUN_SPEED,
	FastRunSpeed = MovementConfig.FAST_RUN_SPEED,
	
	FOVBonus = MovementConfig.FOV_BONUS,
	FOVTweenTime = MovementConfig.FOV_TWEEN_TIME,
	StopFOVTweenTime = MovementConfig.STOP_FOV_TWEEN_TIME,
	DefaultFallbackFOV = MovementConfig.DEFAULT_FALLBACK_FOV,
	DefaultWalkSpeedAfterStop = MovementConfig.DEFAULT_WALKSPEED,
}

function Run:GetState(Character: Model)
	return self.States[Character]
end

function Run:SetState(Character: Model, State)
	self.States[Character] = State
end

function Run:ClearState(Character: Model)
	self.CurrentState = self:GetState(Character)
	if not self.CurrentState then
		return
	end

	if self.CurrentState.Cleaner then
		self.CurrentState.Cleaner:destroy()
	end

	if self.Camera and self.CurrentState.DefaultFOV then
		self.TweenInfo = TweenInfo.new(self.Settings.StopFOVTweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		self.TweenGoal = { FieldOfView = 70 }
		TweenService:Create(self.Camera, self.TweenInfo, self.TweenGoal):Play()
	end

	self.States[Character] = nil
end

function Run:StartFastRun(Character: Model)
	self.CurrentState = self:GetState(Character)
	if not self.CurrentState then
		return
	end
	
	if self.CurrentState.HasBoosted then
		return
	end
	
	if Character:GetAttribute("WallRunning") then
		return
	end

	self.CurrentState.HasBoosted = true
	MovementSettings.SetWalkSpeed(Character, self.CurrentState.Humanoid, self.Settings.FastRunSpeed)

	if self.CurrentState.AnimationTrack then
		self.CurrentState.AnimationTrack:AdjustSpeed(1.5)
	end

	if self.Camera then
		self.TweenInfo = TweenInfo.new(self.Settings.FOVTweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		self.TweenGoal = { FieldOfView = self.CurrentState.DefaultFOV + self.Settings.FOVBonus }
		TweenService:Create(self.Camera, self.TweenInfo, self.TweenGoal):Play()
	end

	Network.Fire({
		module = "Visuals",
		method = "runvfx",
		msg = "",
		animLength = 0
	}, "Core")

	self.RootPart = Character:FindFirstChild("HumanoidRootPart")
	if self.RootPart then
		Sound:Play("Running", Character)
	end
end

-- Called by the heartbeat when the player stops giving movement input
-- while running. Freezes the animation and stops the speed lines and
-- footsteps, but leaves the run state on so it picks back up.
function Run:PauseWhileStill(Character: Model)
	local State = self:GetState(Character)
	if not State then
		return
	end

	if State.AnimationTrack and State.AnimationTrack.IsPlaying then
		State.AnimationTrack:Stop()
	end

	if State.HasBoosted then
		Network.Fire({
			module = "Visuals",
			method = "runvfxstop",
			msg = "",
			animLength = 0
		}, "Core")

		local RootPart = Character:FindFirstChild("HumanoidRootPart")
		local RunningSound = RootPart and RootPart:FindFirstChild("Running")
		if RunningSound then
			RunningSound:Destroy()
		end

		-- Back to regular sprint. The boost has to build up again from
		-- the FastRunDelay once the player moves.
		if MovementSettings.Abilities.Run.StillResetsBoost then
			State.HasBoosted = false
			State.TimeElapsed = 0
			MovementSettings.SetWalkSpeed(Character, State.Humanoid, self.Settings.BaseRunSpeed)
			if State.AnimationTrack then
				State.AnimationTrack:AdjustSpeed(1)
			end
			if self.Camera and State.DefaultFOV then
				local Info = TweenInfo.new(self.Settings.StopFOVTweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				TweenService:Create(self.Camera, Info, { FieldOfView = State.DefaultFOV }):Play()
			end
		end
	end
end

-- The other half. Starts the animation again and, if the boost is
-- still on, the speed lines and footsteps.
function Run:ResumeFromStill(Character: Model)
	local State = self:GetState(Character)
	if not State then
		return
	end

	if State.AnimationTrack and not State.AnimationTrack.IsPlaying then
		State.AnimationTrack:Play()
		State.AnimationTrack:AdjustSpeed(State.HasBoosted and 1.5 or 1)
	end

	if State.HasBoosted then
		Network.Fire({
			module = "Visuals",
			method = "runvfx",
			msg = "",
			animLength = 0
		}, "Core")

		if Character:FindFirstChild("HumanoidRootPart") then
			Sound:Play("Running", Character)
		end
	end
end

function Run:ResumeAfterVault(Character: Model)
	if Character:GetAttribute("state") ~= "running" then
		return
	end

	self.CurrentState = self:GetState(Character)

	if self.CurrentState and self.CurrentState.AnimationTrack then
		if not self.CurrentState.AnimationTrack.IsPlaying then
			self.CurrentState.AnimationTrack:Play()
		end
	else
		self:Begin(Character)
	end
end

function Run:Begin(Character: Model)
	self.Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not self.Humanoid then
		return
	end
	
	if Character:GetAttribute("state") == "crouching" then
		return
	end

	Character:SetAttribute("state", "running")
	
	HelperFunctions.stopAll(Character)

	self.AnimationTrack = HelperFunctions.playAnim(Character, self.RunAnimation, true)
	self.AnimationTrack.Priority = Enum.AnimationPriority.Movement
	MovementSettings.SetWalkSpeed(Character, self.Humanoid, self.Settings.BaseRunSpeed)

	self:ClearState(Character)

	self.Cleaner = Pocket.new()
	self.Camera = workspace.CurrentCamera
	self.DefaultFOV = self.Camera and self.Camera.FieldOfView or self.Settings.DefaultFallbackFOV

	self.NewState = {
		Humanoid = self.Humanoid,
		AnimationTrack = self.AnimationTrack,
		TimeElapsed = 0,
		HasBoosted = false,
		DefaultWalkSpeed = self.Settings.BaseRunSpeed,
		DefaultFOV = self.DefaultFOV,
		Cleaner = self.Cleaner
	}

	self:SetState(Character, self.NewState)

	if self.AnimationTrack then
		self.Cleaner:add(function()
			if self.AnimationTrack.IsPlaying then
				self.AnimationTrack:Stop()
			end
		end)
	end

	self.HeartbeatConnection = RunService.Heartbeat:Connect(function(DeltaTime)
		self.ActiveState = self:GetState(Character)
		if not self.ActiveState then
			return
		end

		-- Running is a toggle, so it stays on while stood still. When
		-- there is no movement input the animation, speed lines and
		-- footsteps are paused rather than playing on the spot, and
		-- come back the moment you move.
		local RunSettings = MovementSettings.Abilities.Run
		local Moving = true
		if RunSettings.PauseWhenStill then
			local Humanoid = self.ActiveState.Humanoid
			Moving = Humanoid.MoveDirection.Magnitude > RunSettings.StillThreshold
			if not Moving and RunSettings.StillOnlyOnGround and Humanoid.FloorMaterial == Enum.Material.Air then
				Moving = true
			end
		end
		if self.ActiveState.IsMoving == nil then
			self.ActiveState.IsMoving = true
		end

		if Moving ~= self.ActiveState.IsMoving then
			self.ActiveState.IsMoving = Moving
			if Moving then
				self:ResumeFromStill(Character)
			else
				self:PauseWhileStill(Character)
			end
		end

		if not self.ActiveState.HasBoosted and Moving then
			self.ActiveState.TimeElapsed += DeltaTime
			if self.ActiveState.TimeElapsed >= self.Settings.FastRunDelay then
				self:StartFastRun(Character)
			end
		end
	end)

	self.Cleaner:add(self.HeartbeatConnection)
end

function Run:Stop(Character: Model)
	self.Humanoid = Character:FindFirstChildOfClass("Humanoid")
	Character:SetAttribute("state", "neutral")

	self:ClearState(Character)

	HelperFunctions.stopAll(Character)

	self.RootPart = Character:FindFirstChild("HumanoidRootPart")
	if self.RootPart then
		self.RunningSound = self.RootPart:FindFirstChild("Running")
		if self.RunningSound then
			self.RunningSound:Destroy()
		end
	end

	if self.Humanoid then
		MovementSettings.SetWalkSpeed(Character, self.Humanoid, self.Settings.DefaultWalkSpeedAfterStop)
	end

	Network.Fire({
		module = "Visuals",
		method = "runvfxstop",
		msg = "",
		animLength = 0
	}, "Core")
end

return Run