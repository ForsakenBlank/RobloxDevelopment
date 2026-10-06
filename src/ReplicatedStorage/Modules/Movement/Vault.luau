--!nonstrict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SharedModules = ReplicatedStorage.Modules.Shared
local Modules = ReplicatedStorage.Modules

local HelperFunctions = require(SharedModules.HelperFunctions)
local Run = require(Modules.Movement.Run)
local Pocket = require(SharedModules.Pocket)
local MovementConfig = require(SharedModules.MovementConfig)
local Sound = require(SharedModules.Sound)

local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.Vaulting

type PocketType = typeof(Pocket.new())

type VaultSettings = {
	GroundVaultForwardOffset: number,
	GroundVaultUpOffset: number,
	GroundVaultTime: number,
	LedgeForwardCheck: number,
	LedgeDownCheck: number,
	LedgeForwardOffset: number,
	LedgeUpOffset: number,
	LedgeVaultTime: number,
	GroundVaultCooldown: number,
	MaxLedgeHeight: number,
}

export type VaultState = {
	Character: Model,
	Humanoid: Humanoid?,
	RootPart: BasePart?,
	IsVaulting: boolean,
	Pocket: PocketType,
}

local Vault = {}
Vault.__index = Vault

local Settings: VaultSettings = {
	GroundVaultForwardOffset = MovementConfig.GROUND_VAULT_FORWARD_OFFSET,
	GroundVaultUpOffset = MovementConfig.GROUND_VAULT_UP_OFFSET,
	GroundVaultTime = MovementConfig.GROUND_VAULT_TIME,
	LedgeForwardCheck = MovementConfig.LEDGE_FORWARD_CHECK,
	LedgeDownCheck = MovementConfig.LEDGE_DOWN_CHECK,
	LedgeForwardOffset = MovementConfig.LEDGE_FORWARD_OFFSET,
	LedgeUpOffset = MovementConfig.LEDGE_UP_OFFSET,
	LedgeVaultTime = MovementConfig.LEDGE_VAULT_TIME,
	GroundVaultCooldown = MovementConfig.GROUND_VAULT_TIME,
	MaxLedgeHeight = MovementConfig.MAX_LEDGE_HEIGHT,
}
Vault.Settings = Settings

local StateByCharacter: { [Model]: VaultState } = {}
Vault.StateByCharacter = StateByCharacter

function Vault:GetCharacterState(Character: Model): VaultState
	local ExistingState = self.StateByCharacter[Character]

	if not ExistingState then
		ExistingState = {
			Character = Character,
			Humanoid = nil,
			RootPart = nil,
			IsVaulting = false,
			Pocket = Pocket.new(),
		}
		self.StateByCharacter[Character] = ExistingState
	elseif not ExistingState.Pocket then
		ExistingState.Pocket = Pocket.new()
	end

	return ExistingState
end

function Vault:CanUseVault(Character: Model): boolean
	local CurrentState = Character:GetAttribute("state")
	if CurrentState and CurrentState ~= "neutral" and CurrentState ~= "running" then
		return false
	end

	if Character:GetAttribute("dashing") then
		return false
	end

	return true
end

function Vault:CastRay(Origin: Vector3, Direction: Vector3, IgnoreList: { Instance }): RaycastResult?
	local RaycastParamsObject = RaycastParams.new()
	RaycastParamsObject.FilterType = Enum.RaycastFilterType.Exclude
	RaycastParamsObject.FilterDescendantsInstances = IgnoreList
	RaycastParamsObject.IgnoreWater = true

	return Workspace:Raycast(Origin, Direction, RaycastParamsObject)
end

function Vault:BeginVaultState(Character: Model)
	local State = self:GetCharacterState(Character)

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	local RootPart = if RootPartObject and RootPartObject:IsA("BasePart") then RootPartObject else nil

	State.Humanoid = Humanoid
	State.RootPart = RootPart
	State.IsVaulting = true

	State.Pocket:destroy()
	State.Pocket = Pocket.new()

	local PreviousState = Character:GetAttribute("state") or "neutral"
	Character:SetAttribute("Vault_PrevState", PreviousState)

	HelperFunctions.stopAll(Character)
	HelperFunctions.flashHighlight(Character, 0.4)

	if RootPart then
		Sound:Play("Vault", Character)
	end

	Character:SetAttribute("state", "vaulting")
	Character:SetAttribute("Climbing", nil)
	Character:SetAttribute("dashing", nil)

	if Humanoid then
		Character:SetAttribute("Vault_OldWalkSpeed", Humanoid.WalkSpeed)
		Character:SetAttribute("Vault_OldAutoRotate", if Humanoid.AutoRotate then 1 else 0)

		if Humanoid.JumpPower > 0 or not Character:GetAttribute("Vault_OldJump") then
			Character:SetAttribute("Vault_OldJump", Humanoid.JumpPower)
		end

		Humanoid.WalkSpeed = 0
		Humanoid.JumpPower = 0
		Humanoid.Jump = false
		Humanoid.AutoRotate = false
	end

	if RootPart then
		Character:SetAttribute("Vault_OldRootCollide", if RootPart.CanCollide then 1 else 0)
		RootPart.CanCollide = false

		HelperFunctions.clearVelocity(RootPart)
		RootPart.AssemblyLinearVelocity = Vector3.zero
		RootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function Vault:EndVaultState(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State then
		return
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	local RootPart = if RootPartObject and RootPartObject:IsA("BasePart") then RootPartObject else nil

	if Humanoid then
		local WalkSpeedValue = Character:GetAttribute("Vault_OldWalkSpeed")
		local JumpPowerValue = Character:GetAttribute("Vault_OldJump")
		local AutoRotateValue = Character:GetAttribute("Vault_OldAutoRotate")

		if typeof(WalkSpeedValue) == "number" then
			Humanoid.WalkSpeed = WalkSpeedValue
		end
		if typeof(JumpPowerValue) == "number" then
			Humanoid.JumpPower = JumpPowerValue
		end

		Humanoid.AutoRotate = AutoRotateValue == nil or AutoRotateValue == 1
	end

	if RootPart then
		HelperFunctions.clearVelocity(RootPart)
		RootPart.AssemblyLinearVelocity = Vector3.new(
			RootPart.AssemblyLinearVelocity.X,
			0,
			RootPart.AssemblyLinearVelocity.Z
		)

		local CollideValue = Character:GetAttribute("Vault_OldRootCollide")
		RootPart.CanCollide = CollideValue == nil or CollideValue == 1
	end

	Character:SetAttribute("Vault_OldWalkSpeed", nil)
	Character:SetAttribute("Vault_OldJump", nil)
	Character:SetAttribute("Vault_OldAutoRotate", nil)
	Character:SetAttribute("Vault_OldRootCollide", nil)

	local PreviousState = Character:GetAttribute("Vault_PrevState") or "neutral"
	if PreviousState == "running" then
		Character:SetAttribute("state", "running")
		Run:ResumeAfterVault(Character)
	else
		Character:SetAttribute("state", "neutral")
	end

	Character:SetAttribute("Vault_PrevState", nil)

	State.Pocket:destroy()
	State.IsVaulting = false

	if RootPart then
		HelperFunctions.clearVelocity(RootPart)
	end
end

function Vault:TryGroundVaultInternal(Character: Model, LedgePart: BasePart?): boolean
	local State = self:GetCharacterState(Character)

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	local RootPart = if RootPartObject and RootPartObject:IsA("BasePart") then RootPartObject else nil

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart or not LedgePart then
		return false
	end

	if Character:GetAttribute("state") == "vaulting" then
		return false
	end

	if not self:CanUseVault(Character) then
		return false
	end

	if Character:GetAttribute("Climbing") then
		return false
	end

	if Humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	local CurrentTime = tick()
	local LastGroundVaultTime = Character:GetAttribute("LastGroundVaultTime") or 0
	if CurrentTime - LastGroundVaultTime < self.Settings.GroundVaultCooldown then
		return false
	end

	local Map = Workspace:FindFirstChild("Map")
	if not Map or not LedgePart:IsDescendantOf(Map) then
		return false
	end

	local ForwardVector: Vector3
	local MoveDirection = Humanoid.MoveDirection
	if MoveDirection.Magnitude > 0.1 then
		ForwardVector = Vector3.new(MoveDirection.X, 0, MoveDirection.Z).Unit
	else
		local LookVector = RootPart.CFrame.LookVector
		ForwardVector = Vector3.new(LookVector.X, 0, LookVector.Z).Unit
	end

	local StartPosition = RootPart.Position
	local UpHeight = Humanoid.HipHeight * 0.8 + self.Settings.GroundVaultUpOffset
	local ForwardDistance = self.Settings.GroundVaultForwardOffset
	local PeakPosition = StartPosition + Vector3.yAxis * UpHeight

	local TotalTime = self.Settings.GroundVaultTime
	local UpTime = TotalTime * 0.45
	local ForwardTime = TotalTime * 0.55

	self:BeginVaultState(Character)
	Character:SetAttribute("vaulting", true)

	local VaultAnimation = Animations:FindFirstChild("Vault_1")
	if VaultAnimation and VaultAnimation:IsA("Animation") then
		local VaultTrack = HelperFunctions.playAnim(Character, VaultAnimation, true)
		if VaultTrack then
			VaultTrack.Priority = Enum.AnimationPriority.Action4
			VaultTrack.Looped = false

			if VaultTrack.Length > 0 then
				VaultTrack:AdjustSpeed(VaultTrack.Length * 2)
			end

			task.delay(VaultTrack.Length, function()
				Character:SetAttribute("vaulting", nil)
			end)

			State.Pocket:add(VaultTrack)
		end
	end

	local UpVelocity = (PeakPosition - StartPosition) / UpTime
	HelperFunctions.velocity(RootPart, UpVelocity, UpTime, false, "GroundVaultUp")

	Character:SetAttribute("LastGroundVaultTime", CurrentTime)

	local UpPhaseThread = task.delay(UpTime, function()
		local CurrentRootPartObject = Character:FindFirstChild("HumanoidRootPart")
		local CurrentRootPart = if CurrentRootPartObject and CurrentRootPartObject:IsA("BasePart") then CurrentRootPartObject else nil
		if not CurrentRootPart then
			return
		end

		HelperFunctions.clearVelocity(CurrentRootPart)

		local StartForwardPosition = CurrentRootPart.Position
		local TargetPosition = StartForwardPosition + ForwardVector * ForwardDistance
		local ForwardVelocity = (TargetPosition - StartForwardPosition) / ForwardTime

		HelperFunctions.velocity(CurrentRootPart, ForwardVelocity, ForwardTime, false, "GroundVaultForward")

		local ForwardPhaseThread = task.delay(ForwardTime, function()
			self:EndVaultState(Character)
		end)

		State.Pocket:add(ForwardPhaseThread)
	end)

	State.Pocket:add(UpPhaseThread)
	return true
end

function Vault:TryLedgeVaultInternal(Character: Model): boolean
	local State = self:GetCharacterState(Character)

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local RootPartObject = Character:FindFirstChild("HumanoidRootPart")
	local RootPart = if RootPartObject and RootPartObject:IsA("BasePart") then RootPartObject else nil

	State.Humanoid = Humanoid
	State.RootPart = RootPart

	if not Humanoid or not RootPart then
		return false
	end

	if not Character:GetAttribute("Climbing") then
		return false
	end

	if not self:CanUseVault(Character) then
		return false
	end

	local LookVector = RootPart.CFrame.LookVector
	local ForwardVector = Vector3.new(LookVector.X, 0, LookVector.Z).Unit
	local HeadPosition = RootPart.Position

	local ForwardCheckResult = self:CastRay(
		HeadPosition,
		ForwardVector * self.Settings.LedgeForwardCheck,
		{ Character }
	)

	if ForwardCheckResult then
		return false
	end

	local DownOrigin = HeadPosition + ForwardVector * self.Settings.LedgeForwardCheck
	local DownResult = self:CastRay(
		DownOrigin,
		Vector3.new(0, -self.Settings.LedgeDownCheck, 0),
		{ Character }
	)

	if not DownResult then
		return false
	end

	local GroundPosition = DownResult.Position
	local TargetStandPosition = GroundPosition
		+ Vector3.new(0, Humanoid.HipHeight + self.Settings.LedgeUpOffset, 0)
		+ ForwardVector * self.Settings.LedgeForwardOffset

	local HeightDelta = TargetStandPosition.Y - RootPart.Position.Y
	if HeightDelta < 0 or HeightDelta > self.Settings.MaxLedgeHeight then
		return false
	end

	self:BeginVaultState(Character)

	local CurrentPosition = RootPart.Position
	local LiftHeightAbove = 1.5
	local PeakPosition = Vector3.new(
		CurrentPosition.X,
		TargetStandPosition.Y + LiftHeightAbove,
		CurrentPosition.Z
	)

	local FinalPosition = Vector3.new(
		TargetStandPosition.X,
		TargetStandPosition.Y + LiftHeightAbove,
		TargetStandPosition.Z
	)

	local AnimationIndex = math.random(1, 2)
	local LedgeAnimation = Animations:FindFirstChild("Vault_" .. tostring(AnimationIndex))
	if LedgeAnimation and LedgeAnimation:IsA("Animation") then
		local LedgeTrack = HelperFunctions.playAnim(Character, LedgeAnimation, true)
		if LedgeTrack then
			LedgeTrack.Priority = Enum.AnimationPriority.Action4
			LedgeTrack:AdjustSpeed(LedgeTrack.Length * 2)
			State.Pocket:add(LedgeTrack)
		end
	end

	local TotalTime = self.Settings.LedgeVaultTime
	local UpTime = TotalTime * 0.45
	local ForwardTime = TotalTime * 0.55

	local UpVelocity = (PeakPosition - CurrentPosition) / UpTime
	HelperFunctions.velocity(RootPart, UpVelocity, UpTime, false, "LedgeVaultUp")

	local UpPhaseThread = task.delay(UpTime, function()
		local CurrentRootPartObject = Character:FindFirstChild("HumanoidRootPart")
		local CurrentRootPart = if CurrentRootPartObject and CurrentRootPartObject:IsA("BasePart") then CurrentRootPartObject else nil
		if not CurrentRootPart then
			return
		end

		HelperFunctions.clearVelocity(CurrentRootPart)

		local StartForwardPosition = CurrentRootPart.Position
		local ForwardVelocity = (FinalPosition - StartForwardPosition) / ForwardTime
		HelperFunctions.velocity(CurrentRootPart, ForwardVelocity, ForwardTime, false, "LedgeVaultForward")

		local ForwardPhaseThread = task.delay(ForwardTime, function()
			self:EndVaultState(Character)
		end)

		State.Pocket:add(ForwardPhaseThread)
	end)

	State.Pocket:add(UpPhaseThread)
	return true
end

function Vault.TryGroundVault(Character: Model, LedgePart: BasePart?): boolean
	return Vault:TryGroundVaultInternal(Character, LedgePart)
end

function Vault.TryLedgeVault(Character: Model): boolean
	return Vault:TryLedgeVaultInternal(Character)
end

function Vault:ClearCharacterState(Character: Model)
	local State = self.StateByCharacter[Character]
	if not State then
		return
	end

	State.Pocket:destroy()
	self.StateByCharacter[Character] = nil
end

return Vault