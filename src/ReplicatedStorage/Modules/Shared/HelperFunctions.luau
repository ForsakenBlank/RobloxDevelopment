local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local HelperFunctions = {}

type ConnectionMap = { [string]: RBXScriptConnection }

local PING_SAMPLE_MAX = 0.2
local PING_VELOCITY_FACTOR = 0.35
local MAX_HORIZONTAL_VELOCITY = 130
local MAX_UPWARD_VELOCITY = 90
local MAX_DOWNWARD_VELOCITY = 12
local MAX_TOTAL_VELOCITY = 150

local function GetOrCreateAttachment(Part: BasePart, Name: string): Attachment
	local Existing = Part:FindFirstChild(Name)
	if Existing and Existing:IsA("Attachment") then
		return Existing
	end

	local NewAttachment = Instance.new("Attachment")
	NewAttachment.Name = Name
	NewAttachment.Parent = Part
	return NewAttachment
end

function HelperFunctions.disableVfx(Part: BasePart): ()
	local Descendants = Part:GetDescendants()
	for Index = 1, #Descendants do
		local Object = Descendants[Index]
		if Object:IsA("ParticleEmitter") then
			Object.Enabled = false
		end
	end
end

function HelperFunctions.emit(Part: BasePart): ()
	local Descendants = Part:GetDescendants()
	for Index = 1, #Descendants do
		local ParticleEmitter = Descendants[Index]
		if ParticleEmitter:IsA("ParticleEmitter") then
			local EmitCount = ParticleEmitter:GetAttribute("EmitCount")
			if typeof(EmitCount) == "number" then
				ParticleEmitter:Emit(EmitCount)
			else
				ParticleEmitter:Emit(1)
			end
		end
	end
end

function HelperFunctions.flashHighlight(Character: Model, Duration: number): ()
	local Highlight = Instance.new("Highlight")
	Highlight.FillColor = Color3.new(1, 1, 1)
	Highlight.FillTransparency = 1
	Highlight.OutlineTransparency = 1
	Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	Highlight.Parent = Character

	local TweenInfoValue = TweenInfo.new(Duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local FadeIn = TweenService:Create(Highlight, TweenInfoValue, { FillTransparency = 0.15 })
	local FadeOut = TweenService:Create(Highlight, TweenInfoValue, { FillTransparency = 1 })

	FadeIn:Play()
	FadeIn.Completed:Connect(function()
		FadeOut:Play()
	end)

	FadeOut.Completed:Connect(function()
		Highlight:Destroy()
	end)
end

function HelperFunctions.flashoutlinedHighlight(Character: Model, Duration: number, OutlineColor: Color3?): ()
	local Highlight = Instance.new("Highlight")
	Highlight.FillTransparency = 1
	Highlight.OutlineTransparency = 0
	Highlight.Parent = Character
	Highlight.OutlineColor = OutlineColor or Color3.new(1, 1, 1)
	Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	Highlight.Enabled = true

	Debris:AddItem(Highlight, Duration)
end

function HelperFunctions.playAnim(Character: Model, Anim: Animation, ShouldReturn: boolean): AnimationTrack?
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return nil
	end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		Animator = Instance.new("Animator")
		Animator.Parent = Humanoid
	end

	local LoadedAnim = Animator:LoadAnimation(Anim)
	LoadedAnim:Play()

	if ShouldReturn then
		return LoadedAnim
	end

	return nil
end

function HelperFunctions.stopAll(Character: Model, Exclude: string?): ()
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return
	end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		return
	end

	local Tracks = Animator:GetPlayingAnimationTracks()
	for Index = 1, #Tracks do
		local AnimTrack = Tracks[Index]
		if AnimTrack.Name == "Animation1" or AnimTrack.Name == "WalkAnim" or
			AnimTrack.Name == "Run" or
			AnimTrack.Name == "FallAnim" or
			AnimTrack.Name == "Ziplining" or
			(Exclude and AnimTrack.Name == Exclude) then
			continue
		end

		AnimTrack:Stop()
	end
end

function HelperFunctions.dashVelocity(Part: BasePart, Velocity: Vector3, DebrisTime: number, MaxForce: Vector3?): ()
	local Attachment = GetOrCreateAttachment(Part, "DashVelocityAttachment")
	Attachment.WorldPosition = Part.AssemblyCenterOfMass

	local LinearVelocity = Instance.new("LinearVelocity")
	LinearVelocity.Name = "DashLinearVelocity"
	LinearVelocity.ForceLimitsEnabled = true
	LinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	LinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	LinearVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	LinearVelocity.MaxAxesForce = MaxForce or Vector3.new(99999, 0, 99999)
	LinearVelocity.VectorVelocity = Velocity
	LinearVelocity.Attachment0 = Attachment
	LinearVelocity.Parent = Attachment

	Debris:AddItem(LinearVelocity, DebrisTime)
end

function HelperFunctions.clearVelocity(Part: BasePart, Exception: string?): ()
	local Descendants = Part:GetDescendants()

	for Index = 1, #Descendants do
		local Object = Descendants[Index]
		if Object:IsA("BodyVelocity") or Object:IsA("LinearVelocity") then
			if Exception and string.match(Object.Name, Exception) then
				continue
			end

			Object:Destroy()
		end
	end

	for Index = 1, #Descendants do
		local Object = Descendants[Index]
		if Object:IsA("Attachment") and (Object.Name == "DashVelocityAttachment" or Object.Name == "VelocityAttachment") then
			if #Object:GetChildren() == 0 then
				Object:Destroy()
			end
		end
	end

	Part.AssemblyLinearVelocity = Vector3.zero
	Part.AssemblyAngularVelocity = Vector3.zero
end

function HelperFunctions.velocity(Part: BasePart, Velocity: Vector3, DebrisTime: number, ReturnVelocity: boolean?, Name: string?): LinearVelocity?
	local Attachment = GetOrCreateAttachment(Part, "VelocityAttachment")

	local PingSeconds = 0
	local LocalPlayer = Players.LocalPlayer
	if LocalPlayer then
		pcall(function()
			PingSeconds = LocalPlayer:GetNetworkPing()
		end)
	end

	PingSeconds = math.clamp(PingSeconds, 0, PING_SAMPLE_MAX)
	local CompensationMultiplier = 1 + PingSeconds * PING_VELOCITY_FACTOR
	local CompensatedVelocity = Velocity * CompensationMultiplier

	local HorizontalVelocity = Vector3.new(CompensatedVelocity.X, 0, CompensatedVelocity.Z)
	if HorizontalVelocity.Magnitude > MAX_HORIZONTAL_VELOCITY then
		HorizontalVelocity = HorizontalVelocity.Unit * MAX_HORIZONTAL_VELOCITY
	end

	local VerticalVelocity = math.clamp(
		CompensatedVelocity.Y,
		-MAX_DOWNWARD_VELOCITY,
		MAX_UPWARD_VELOCITY
	)

	local FinalVelocity = Vector3.new(
		HorizontalVelocity.X,
		VerticalVelocity,
		HorizontalVelocity.Z
	)

	if FinalVelocity.Magnitude > MAX_TOTAL_VELOCITY then
		FinalVelocity = FinalVelocity.Unit * MAX_TOTAL_VELOCITY
	end

	local LinearVelocity = Instance.new("LinearVelocity")
	LinearVelocity.Name = Name or "LinearVelocity"
	LinearVelocity.ForceLimitsEnabled = true
	LinearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	LinearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	LinearVelocity.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	LinearVelocity.MaxAxesForce = Vector3.one * math.max(50000, Part.AssemblyMass * 5500)
	LinearVelocity.VectorVelocity = FinalVelocity
	LinearVelocity.Attachment0 = Attachment
	LinearVelocity.Parent = Attachment

	Debris:AddItem(LinearVelocity, math.max(0.03, DebrisTime + PingSeconds * 0.08))

	if ReturnVelocity then
		return LinearVelocity
	end

	return nil
end

function HelperFunctions.SetInvisiblity(Character: Model, Invisible: boolean): ()
	local Descendants = Character:GetDescendants()

	for Index = 1, #Descendants do
		local Object = Descendants[Index]

		if Object:IsA("BasePart") then
			Object.LocalTransparencyModifier = Invisible and 1 or 0
		elseif Object:IsA("Decal") or Object:IsA("Texture") then
			if Invisible then
				if Object:GetAttribute("OriginalTransparency") == nil then
					Object:SetAttribute("OriginalTransparency", Object.Transparency)
				end

				Object.Transparency = 1
			else
				local Transparency = Object:GetAttribute("OriginalTransparency")
				if typeof(Transparency) == "number" then
					Object.Transparency = Transparency
				end
			end
		elseif Object:IsA("Accessory") then
			local Handle = Object:FindFirstChildWhichIsA("BasePart")
			if Handle then
				Handle.LocalTransparencyModifier = Invisible and 1 or 0
			end
		end
	end
end

function HelperFunctions.alignPosition(Part: BasePart, TargetPart: BasePart, MaxVelocity: number?, DebrisTime: number?, Offset: number?): ()
	local AlignPosition = Instance.new("AlignPosition")

	local Attachment0 = Part:FindFirstChild("RootAttachment")
	if not Attachment0 or not Attachment0:IsA("Attachment") then
		Attachment0 = Instance.new("Attachment")
		Attachment0.Name = "RootAttachment"
		Attachment0.Parent = Part
	end

	local Attachment1 = TargetPart:FindFirstChild("RootAttachment")
	if not Attachment1 or not Attachment1:IsA("Attachment") then
		Attachment1 = Instance.new("Attachment")
		Attachment1.Name = "RootAttachment"
		Attachment1.Parent = TargetPart
	end

	AlignPosition.Attachment0 = Attachment0
	AlignPosition.Attachment1 = Attachment1
	AlignPosition.RigidityEnabled = false
	AlignPosition.MaxForce = 50000
	AlignPosition.MaxVelocity = MaxVelocity or 50
	AlignPosition.Responsiveness = 20
	AlignPosition.Parent = Part

	Attachment1.Position = TargetPart.CFrame.LookVector * (Offset or 0)

	if DebrisTime then
		Debris:AddItem(AlignPosition, DebrisTime)
	end
end

function HelperFunctions.playSound(Part: BasePart, Sound: Sound): ()
	local Clone = Sound:Clone()
	Clone.PlayOnRemove = false
	Clone.RollOffMaxDistance = 100
	Clone.RollOffMinDistance = 12
	Clone.Parent = Part

	local EndedConnection: RBXScriptConnection?
	EndedConnection = Clone.Ended:Connect(function()
		if EndedConnection then
			EndedConnection:Disconnect()
			EndedConnection = nil
		end

		Clone:Destroy()
	end)

	Clone:Play()

	local CleanupDelay = math.max(Clone.TimeLength, 0.5) + 1
	Debris:AddItem(Clone, CleanupDelay)
end

function HelperFunctions.isAir(Humanoid: Humanoid): boolean
	return Humanoid.FloorMaterial == Enum.Material.Air
end

function HelperFunctions.checkLocalPlayer(Character: Model, Player: Player): boolean
	return Character.Name == Player.Name
end

function HelperFunctions.stopAllAnimsClient(Character: Model): ()
	local Player = Players:GetPlayerFromCharacter(Character)
	if not Player then
		return
	end
end

function HelperFunctions.discnonect(Connections: ConnectionMap | RBXScriptConnection?, Connection: string): ()
	if typeof(Connections) ~= "table" then
		if Connections and typeof(Connections) == "RBXScriptConnection" then
			Connections:Disconnect()
		end
		return
	end

	local Selected = Connections[Connection]
	if Selected and typeof(Selected) == "RBXScriptConnection" then
		Selected:Disconnect()
		Connections[Connection] = nil
	end
end

return HelperFunctions
