local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local Pocket = require(ReplicatedStorage.Modules.Shared.Pocket)
local Run = require(ReplicatedStorage.Modules.Movement.Run)
local MovementConfig = require(ReplicatedStorage.Modules.Shared.MovementConfig)
local Sound = require(ReplicatedStorage.Modules.Shared.Sound)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)
local MovementGate = require(ReplicatedStorage.Modules.Shared.MovementGate)

local WallRunSettings = MovementSettings.Abilities.WallRun
local WallJumpSettings = MovementSettings.Abilities.WallJump

local AnimationsFolder = ReplicatedStorage.Assets.Animations["Wall Movement"]
local WALL_RUN_LEFT_ANIMATION: Animation = AnimationsFolder.WallRunLeft
local WALL_RUN_RIGHT_ANIMATION: Animation = AnimationsFolder.WallRunRight
local WALL_JUMP_ANIMATION: Animation = AnimationsFolder.Wall_Jump
local FREE_FALLING_ANIMATION: Animation = ReplicatedStorage.Assets.Animations.Sliding.Slide_Cancel

type PocketType = typeof(Pocket.new())
type WallSide = "left" | "right"

type MovementStates = {
	IsWallRunning: boolean,
	CanWallRun: boolean,
	CurrentWallSide: WallSide?,
	LastWallrunTime: number,
	LastWallEndTime: number,
	VelocityForce: BodyVelocity?,
	GyroForce: BodyGyro?,
	WallrunSpeed: number,
	Vaulting: boolean,
}

export type WallRun = {
	Player: Player?,
	Character: Model?,
	Humanoid: Humanoid?,
	Pocket: PocketType?,
	MovementStates: MovementStates,
	WallLedge: { Active: boolean },
	CurrentWallRunTrack: AnimationTrack?,
	CurrentWallJumpTrack: AnimationTrack?,
	WallJumpTrack: AnimationTrack?,
	RunTrack: AnimationTrack?,
	LeftWallRunTrack: AnimationTrack?,
	RightWallRunTrack: AnimationTrack?,
	RenderConnection: RBXScriptConnection?,
	PostSimulationConnection: RBXScriptConnection?,
	PreviousMovementState: string?,
}

local WallRun = {}
WallRun.__index = WallRun

local Registry: { [Model]: WallRun } = {}
WallRun.Registry = Registry

local function GetCharacterAndRoot(self: WallRun): (Model?, Humanoid?, BasePart?)
	local Character = self.Character
	if not Character then
		return nil, nil, nil
	end

	local HumanoidInstance = Character:FindFirstChildOfClass("Humanoid")
	local RootPartInstance = Character:FindFirstChild("HumanoidRootPart")
	if not HumanoidInstance or not RootPartInstance then
		return Character, nil, nil
	end

	if not RootPartInstance:IsA("BasePart") then
		return Character, nil, nil
	end

	return Character, HumanoidInstance, RootPartInstance
end

function WallRun:CreateBodyVelocity(Parent: BasePart): BodyVelocity
	local BodyVelocityInstance = Instance.new("BodyVelocity")
	BodyVelocityInstance.MaxForce = Vector3.one * 2000 * Parent.AssemblyMass
	BodyVelocityInstance.Velocity = Vector3.zero
	BodyVelocityInstance.Parent = Parent
	return BodyVelocityInstance
end

function WallRun:CheckChainWall(RaycastParamsObject: RaycastParams): (RaycastResult?, WallSide?)
	local Character, _, RootPart = GetCharacterAndRoot(self)
	if not Character or not RootPart or not self.MovementStates.IsWallRunning then
		return nil, nil
	end

	local CurrentWallSide = self.MovementStates.CurrentWallSide
	if not CurrentWallSide then
		return nil, nil
	end

	local ChainSide: WallSide = if CurrentWallSide == "right" then "left" else "right"
	local ChainDirection = if ChainSide == "left" then -RootPart.CFrame.RightVector else RootPart.CFrame.RightVector
	local ChainResult = workspace:Raycast(RootPart.Position, ChainDirection * WallJumpSettings.ChainCheckDistance, RaycastParamsObject)

	if ChainResult and ChainResult.Instance and ChainResult.Instance.CanCollide then
		local ChainNormal = ChainResult.Normal
		if RootPart.CFrame.LookVector:Dot(ChainNormal) < WallRunSettings.MinApproachDot then
			return nil, nil
		end

		return ChainResult, ChainSide
	end

	return nil, nil
end

function WallRun:RestartRunIfNeeded()
	local Character = self.Character
	if not Character or not Character.Parent then
		return
	end

	if Character:GetAttribute("state") ~= "running" then
		return
	end

	task.spawn(function()
		Run:ResumeAfterVault(Character)
	end)
end

function WallRun:WallJump()
	if not self.MovementStates.IsWallRunning then
		return
	end

	if not MovementGate:IsEnabled("WallJump") then
		return
	end

	local Character, Humanoid, RootPart = GetCharacterAndRoot(self)
	if not Character or not Humanoid or not RootPart then
		return
	end

	self.Humanoid = Humanoid

	local RaycastParamsObject = RaycastParams.new()
	RaycastParamsObject.FilterDescendantsInstances = MovementSettings.GetMapInstances()
	RaycastParamsObject.FilterType = Enum.RaycastFilterType.Include

	local ChainWall, ChainSide = self:CheckChainWall(RaycastParamsObject)
	local CurrentWallSide = self.MovementStates.CurrentWallSide
	if not CurrentWallSide then
		return
	end

	self.MovementStates.IsWallRunning = false
	self.MovementStates.CanWallRun = false
	self.MovementStates.LastWallEndTime = tick()
	Character:SetAttribute("WallRunning", nil)
	Character:SetAttribute("WallJumping", true)

	if self.CurrentWallRunTrack then
		self.CurrentWallRunTrack:Stop()
		self.CurrentWallRunTrack = nil
	end

	local RootChildren = RootPart:GetChildren()
	for Index = 1, #RootChildren do
		local Child = RootChildren[Index]
		if Child:IsA("BodyVelocity") or Child:IsA("BodyGyro") then
			Child:Destroy()
		end
	end

	HelperFunctions.clearVelocity(RootPart)
	RootPart.AssemblyLinearVelocity = Vector3.zero
	RootPart.AssemblyAngularVelocity = Vector3.zero

	local JumpVelocityBody = self:CreateBodyVelocity(RootPart)
	JumpVelocityBody.Name = "WallrunJumpBv"
	JumpVelocityBody.MaxForce = Vector3.one * RootPart.AssemblyMass * 2000
	if self.Pocket then
		self.Pocket:add(JumpVelocityBody)
	end

	local ForwardPower = WallJumpSettings.ForwardPower
	local SidePower = WallJumpSettings.SidePower
	local UpPower = WallJumpSettings.UpPower
	local WallJumpDirection = if CurrentWallSide == "right" then -RootPart.CFrame.RightVector else RootPart.CFrame.RightVector
	local ChainTransition = false

	HelperFunctions.stopAll(Character, "Wall_Jump")
	HelperFunctions.flashoutlinedHighlight(Character, 0.4)

	Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

	local ChainCheckDelay = WallJumpSettings.ChainCheckDelay
	local PostSimulationConnection: RBXScriptConnection?
	PostSimulationConnection = RunService.PostSimulation:Connect(function(DeltaTime)
		local ElapsedWallrunTime = tick() - self.MovementStates.LastWallrunTime

		if ForwardPower > WallJumpSettings.ForwardFloor then
			ForwardPower -= WallJumpSettings.ForwardDecayPerSecond * DeltaTime
		end

		if SidePower > WallJumpSettings.SideFloor then
			SidePower -= WallJumpSettings.SideDecayPerSecond * DeltaTime
		end

		UpPower -= WallJumpSettings.UpDecayPerSecond * DeltaTime

		if WallJumpSettings.ChainEnabled and ChainWall and not ChainTransition and ElapsedWallrunTime > ChainCheckDelay then
			local CurrentChainWall, CurrentChainSide = self:CheckChainWall(RaycastParamsObject)
			if CurrentChainWall and CurrentChainSide == ChainSide then
				local DistanceToChain = (CurrentChainWall.Position - RootPart.Position).Magnitude
				if DistanceToChain <= WallJumpSettings.ChainMaxDistance then
					local AngleToChainWall = RootPart.CFrame.LookVector:Dot(CurrentChainWall.Normal)
					if AngleToChainWall > -0.8 then
						ChainTransition = true

						if JumpVelocityBody and JumpVelocityBody.Parent then
							JumpVelocityBody:Destroy()
						end

						task.wait(0.03)

						self.MovementStates.LastWallEndTime = 0
						self.MovementStates.CanWallRun = true
						Character:SetAttribute("WallJumping", nil)
						self:StartWallrun(CurrentChainWall, CurrentChainSide)

						if PostSimulationConnection then
							PostSimulationConnection:Disconnect()
							PostSimulationConnection = nil
							self.PostSimulationConnection = nil
						end

						return
					end
				end
			end
		end

		if JumpVelocityBody and JumpVelocityBody.Parent then
			JumpVelocityBody.Velocity = RootPart.CFrame.LookVector * ForwardPower + WallJumpDirection * SidePower + Vector3.yAxis * UpPower
		end
	end)

	self.PostSimulationConnection = PostSimulationConnection
	if self.Pocket and PostSimulationConnection then
		self.Pocket:add(PostSimulationConnection)
	end
	
	Sound:Play("Wall Jump", Character)
	local WallJumpTrack = HelperFunctions.playAnim(Character, WALL_JUMP_ANIMATION, true)
	self.WallJumpTrack = WallJumpTrack
	if WallJumpTrack then
		local PlayedFreeFalling = false
		local function PlayFreeFalling()
			if PlayedFreeFalling then
				return
			end

			PlayedFreeFalling = true
			local FreeFallTrack = HelperFunctions.playAnim(Character, FREE_FALLING_ANIMATION, true)
			if FreeFallTrack then
				FreeFallTrack.Priority = Enum.AnimationPriority.Action4
			end
		end

		local StoppedConnection = WallJumpTrack.Stopped:Connect(function()
			PlayFreeFalling()
		end)

		local EndedConnection = WallJumpTrack.Ended:Connect(function()
			PlayFreeFalling()
		end)

		if self.Pocket then
			self.Pocket:add(StoppedConnection)
			self.Pocket:add(EndedConnection)
		end
	end

	local CleanupThread = task.delay(WallJumpSettings.Duration, function()
		if PostSimulationConnection then
			PostSimulationConnection:Disconnect()
			PostSimulationConnection = nil
			self.PostSimulationConnection = nil
		end

		if JumpVelocityBody and JumpVelocityBody.Parent then
			JumpVelocityBody:Destroy()
		end

		if not ChainTransition then
			self.MovementStates.CanWallRun = true
			Character:SetAttribute("WallJumping", nil)
			if self.Player then
				self.Player:SetAttribute("DisabledShiftlock", nil)
			end

			self:RestartRunIfNeeded()
		end
	end)

	if self.Pocket then
		self.Pocket:add(CleanupThread)
	end
end

function WallRun:StartWallrun(WallHit: RaycastResult, WallSide: WallSide)
	local Character, Humanoid, RootPart = GetCharacterAndRoot(self)
	if Character and not MovementGate:TryUse(Character, "WallRun") then
		return
	end
	if not Character or not Humanoid or not RootPart then
		return
	end

	self.Humanoid = Humanoid

	local WallNormal = WallHit.Normal
	local RootChildren = RootPart:GetChildren()
	for Index = 1, #RootChildren do
		local Child = RootChildren[Index]
		if Child:IsA("BodyVelocity") or Child:IsA("BodyGyro") then
			Child:Destroy()
		end
	end

	task.wait()

	Humanoid.AutoRotate = false
	local PreviousState = Character:GetAttribute("state")
	if type(PreviousState) == "string" then
		self.PreviousMovementState = PreviousState
	else
		self.PreviousMovementState = nil
	end

	HelperFunctions.stopAll(Character, "WalkAnim")

	if WallSide == "left" and self.LeftWallRunTrack then
		self.LeftWallRunTrack:Stop()
		self.LeftWallRunTrack.Priority = Enum.AnimationPriority.Action4
		self.LeftWallRunTrack.Looped = true
		self.LeftWallRunTrack:Play()
		self.CurrentWallRunTrack = self.LeftWallRunTrack
	elseif WallSide == "right" and self.RightWallRunTrack then
		self.RightWallRunTrack:Stop()
		self.RightWallRunTrack.Priority = Enum.AnimationPriority.Action4
		self.RightWallRunTrack.Looped = true
		self.RightWallRunTrack:Play()
		self.CurrentWallRunTrack = self.RightWallRunTrack
	else
		self.CurrentWallRunTrack = HelperFunctions.playAnim(
			Character,
			if WallSide == "left" then WALL_RUN_LEFT_ANIMATION else WALL_RUN_RIGHT_ANIMATION,
			true
		)

		if self.CurrentWallRunTrack then
			self.CurrentWallRunTrack.Priority = Enum.AnimationPriority.Action4
			self.CurrentWallRunTrack.Looped = true
		end
	end

	self.MovementStates.IsWallRunning = true
	self.MovementStates.CurrentWallSide = WallSide
	self.MovementStates.LastWallrunTime = tick()

	Character:SetAttribute("WallRunning", true)
	Character:SetAttribute("WallRunSide", WallSide)
	Character:SetAttribute("WallRunMaterial", WallHit.Instance.Material)

	local VelocityForce = self:CreateBodyVelocity(RootPart)
	self.MovementStates.VelocityForce = VelocityForce
	if self.Pocket then
		self.Pocket:add(VelocityForce)
	end

	local RunDirection = (RootPart.CFrame.LookVector - WallNormal * RootPart.CFrame.LookVector:Dot(WallNormal)).Unit
	VelocityForce.Velocity = RunDirection * self.MovementStates.WallrunSpeed

	local GyroForce = Instance.new("BodyGyro")
	GyroForce.P = RootPart.AssemblyMass * 10000
	GyroForce.MaxTorque = Vector3.one * RootPart.AssemblyMass * 10000
	GyroForce.Parent = RootPart
	self.MovementStates.GyroForce = GyroForce
	if self.Pocket then
		self.Pocket:add(GyroForce)
	end

	local DesiredCFrame = CFrame.lookAt(RootPart.Position, RootPart.Position + RunDirection)
	task.spawn(function()
		local SlerpDuration = 0.1
		local SlerpElapsed = 0
		local StartCFrame = RootPart.CFrame

		while SlerpElapsed < SlerpDuration and self.MovementStates.GyroForce do
			SlerpElapsed += RunService.Heartbeat:Wait()
			local SlerpAlpha = math.clamp(SlerpElapsed / SlerpDuration, 0, 1)
			local InterpolatedCFrame = StartCFrame:Lerp(DesiredCFrame, SlerpAlpha)

			if self.MovementStates.GyroForce and self.MovementStates.GyroForce.Parent then
				self.MovementStates.GyroForce.CFrame = InterpolatedCFrame
			end
		end

		if self.MovementStates.GyroForce and self.MovementStates.GyroForce.Parent then
			self.MovementStates.GyroForce.CFrame = DesiredCFrame
		end
	end)
end

function WallRun:StopWallrun()
	local Character, Humanoid = GetCharacterAndRoot(self)
	if not Character or not Humanoid then
		return
	end

	self.Humanoid = Humanoid
	self.MovementStates.IsWallRunning = false
	Character:SetAttribute("WallRunning", nil)
	Humanoid.AutoRotate = true

	if self.CurrentWallRunTrack then
		self.CurrentWallRunTrack:Stop()
		self.CurrentWallRunTrack = nil
	end

	HelperFunctions.stopAll(Character, "WalkAnim")
	HelperFunctions.playAnim(Character, WALL_JUMP_ANIMATION, true)

	if self.Player then
		self.Player:SetAttribute("DisabledShiftlock", nil)
	end

	if self.MovementStates.VelocityForce then
		self.MovementStates.VelocityForce:Destroy()
		self.MovementStates.VelocityForce = nil
	end

	if self.MovementStates.GyroForce then
		self.MovementStates.GyroForce:Destroy()
		self.MovementStates.GyroForce = nil
	end

	self.MovementStates.WallrunSpeed = MovementConfig.WALL_RUN_SPEED
	self.MovementStates.LastWallEndTime = tick()
	self.MovementStates.CanWallRun = true

	self:RestartRunIfNeeded()
end

function WallRun:BindUpdate()
	local RaycastParamsObject = RaycastParams.new()
	RaycastParamsObject.FilterDescendantsInstances = MovementSettings.GetMapInstances()
	RaycastParamsObject.FilterType = Enum.RaycastFilterType.Include

	self.RenderConnection = RunService.RenderStepped:Connect(function(DeltaTime)
		local Character, Humanoid, RootPart = GetCharacterAndRoot(self)
		if not Character or not Humanoid or not RootPart then
			return
		end

		self.Humanoid = Humanoid

		if self.WallLedge.Active then
			if self.MovementStates.IsWallRunning then
				self:StopWallrun()
			end
			return
		end

		local CharacterPosition = RootPart.Position
		local SideOffset = RootPart.CFrame.RightVector * WallRunSettings.WallCheckDistance
		local GroundCheckResult = workspace:Raycast(CharacterPosition, Vector3.new(0, -WallRunSettings.GroundCheckDistance, 0), RaycastParamsObject)
		local IsGrounded = not GroundCheckResult or not GroundCheckResult.Instance or not GroundCheckResult.Instance.CanCollide
		local ForwardVector = RootPart.CFrame.LookVector
		local FrontCheckResult = workspace:Raycast(CharacterPosition - ForwardVector * 0.5, ForwardVector * WallRunSettings.FrontCheckDistance, RaycastParamsObject)
		local HorizontalSpeed = Humanoid.MoveDirection.Magnitude

		if not self.MovementStates.IsWallRunning and self.MovementStates.WallrunSpeed ~= MovementConfig.WALL_RUN_SPEED then
			self:StopWallrun()
		end

		if self.MovementStates.IsWallRunning and self.MovementStates.VelocityForce then
			local MoveDirection = Humanoid.MoveDirection
			if MoveDirection.Magnitude < 0.1 then
				self:StopWallrun()
				return
			end

			if MoveDirection:Dot(RootPart.CFrame.LookVector) < 0.2 then
				self:StopWallrun()
				return
			end

			local CurrentWallSide = self.MovementStates.CurrentWallSide
			if not CurrentWallSide then
				self:StopWallrun()
				return
			end

			local WallRayResult = workspace:Raycast(
				CharacterPosition,
				if CurrentWallSide == "right" then SideOffset else -SideOffset,
				RaycastParamsObject
			)

			local WallInstance = WallRayResult and WallRayResult.Instance or nil
			local WallNormal = WallRayResult and WallRayResult.Normal or nil
			local CameraObject = workspace.CurrentCamera
			if not CameraObject then
				return
			end

			local ViewOffset = CameraObject.CFrame.LookVector.Unit:Dot(Vector3.yAxis) / 10

			if WallInstance and WallNormal and WallInstance.CanCollide and IsGrounded and not FrontCheckResult then
				local ForwardDirection = RootPart.CFrame.LookVector
				local WallDirection = (ForwardDirection - WallNormal * ForwardDirection:Dot(WallNormal)).Unit

				if self.MovementStates.GyroForce then
					self.MovementStates.GyroForce.CFrame = CFrame.lookAt(
						CharacterPosition,
						CharacterPosition + WallDirection + Vector3.yAxis * ViewOffset
					)
				end

				self.MovementStates.VelocityForce.Velocity = WallDirection * self.MovementStates.WallrunSpeed

				if self.MovementStates.WallrunSpeed > MovementConfig.WALL_RUN_SPEED - 7 then
					self.MovementStates.WallrunSpeed -= WallRunSettings.SpeedDecayPerSecond * DeltaTime
				end

				task.spawn(function()
					self:CheckChainWall(RaycastParamsObject)
				end)
			else
				self:StopWallrun()
			end
		elseif self.MovementStates.CanWallRun
			and not FrontCheckResult
			and IsGrounded
			and Humanoid:GetState() == Enum.HumanoidStateType.Freefall
			and HorizontalSpeed > 0.1
		then
			local RightCheck = workspace:Raycast(CharacterPosition, SideOffset, RaycastParamsObject)
			local LeftCheck = workspace:Raycast(CharacterPosition, -SideOffset, RaycastParamsObject)

			local RightDistance = if RightCheck and RightCheck.Instance and RightCheck.Instance.CanCollide then RightCheck.Distance else math.huge
			local LeftDistance = if LeftCheck and LeftCheck.Instance and LeftCheck.Instance.CanCollide then LeftCheck.Distance else math.huge

			local WallHit: RaycastResult? = nil
			local WallSide: WallSide? = nil

			if RightDistance < LeftDistance then
				WallSide = "right"
				WallHit = RightCheck
			elseif LeftDistance < RightDistance then
				WallSide = "left"
				WallHit = LeftCheck
			end

			if WallHit and WallSide then
				local TimeSinceWallEnd = tick() - self.MovementStates.LastWallEndTime
				if TimeSinceWallEnd < WallRunSettings.RestartDelay then
					return
				end

				local WallNormal = WallHit.Normal
				if RootPart.CFrame.LookVector:Dot(WallNormal) < WallRunSettings.MinApproachDot then
					return
				end

				self:StartWallrun(WallHit, WallSide)
			end
		end
	end)

	if self.Pocket and self.RenderConnection then
		self.Pocket:add(self.RenderConnection)
	end
end

function WallRun.new(Player: Player): WallRun
	local self = setmetatable({}, WallRun)

	self.Player = Player
	self.Character = Player.Character or Player.CharacterAdded:Wait()
	self.Pocket = Pocket.new()
	local HumanoidInstance = self.Character:WaitForChild("Humanoid")
	if not HumanoidInstance:IsA("Humanoid") then
		error("Expected Humanoid on character")
	end
	self.Humanoid = HumanoidInstance

	self.MovementStates = {
		IsWallRunning = false,
		CanWallRun = true,
		CurrentWallSide = nil,
		LastWallrunTime = 0,
		LastWallEndTime = 0,
		VelocityForce = nil,
		GyroForce = nil,
		WallrunSpeed = MovementConfig.WALL_RUN_SPEED,
		Vaulting = false,
	}

	self.WallLedge = { Active = false }
	self.CurrentWallRunTrack = nil
	self.CurrentWallJumpTrack = nil
	self.PreviousMovementState = nil

	self.LeftWallRunTrack = self.Humanoid:LoadAnimation(WALL_RUN_LEFT_ANIMATION)
	self.RightWallRunTrack = self.Humanoid:LoadAnimation(WALL_RUN_RIGHT_ANIMATION)
	self.WallJumpTrack = self.Humanoid:LoadAnimation(WALL_JUMP_ANIMATION)
	self.RunTrack = nil
	self.RenderConnection = nil
	self.PostSimulationConnection = nil

	self:BindUpdate()

	if self.Character then
		WallRun.Registry[self.Character] = self
	end

	return self
end

function WallRun:destroy()
	self:StopWallrun()

	if self.CurrentWallJumpTrack then
		self.CurrentWallJumpTrack:Stop()
		self.CurrentWallJumpTrack = nil
	end

	if self.LeftWallRunTrack then
		self.LeftWallRunTrack:Stop()
		self.LeftWallRunTrack = nil
	end

	if self.RightWallRunTrack then
		self.RightWallRunTrack:Stop()
		self.RightWallRunTrack = nil
	end

	if self.WallJumpTrack then
		self.WallJumpTrack:Stop()
		self.WallJumpTrack = nil
	end

	if self.RunTrack then
		self.RunTrack:Stop()
		self.RunTrack = nil
	end

	if self.PostSimulationConnection then
		self.PostSimulationConnection:Disconnect()
		self.PostSimulationConnection = nil
	end

	if self.RenderConnection then
		self.RenderConnection:Disconnect()
		self.RenderConnection = nil
	end

	local Character = self.Character
	if Character then
		task.delay(0.2, function()
			Character:SetAttribute("WallRunning", nil)
		end)

		Character:SetAttribute("WallJumping", nil)
		Character:SetAttribute("WallRunSide", nil)
		Character:SetAttribute("WallRunMaterial", nil)

		WallRun.Registry[Character] = nil
	end

	if self.Player then
		self.Player:SetAttribute("DisabledShiftlock", nil)
	end

	if self.Pocket then
		self.Pocket:destroy()
		self.Pocket = nil
	end

	self.Humanoid = nil
	self.Character = nil
	self.Player = nil
end

return WallRun