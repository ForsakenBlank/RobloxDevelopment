--[[
	EnemyAnimator

	Brings the enemies to life on each client. The enemy models are R6
	rigs with no Animate script and no uploaded animations, so without
	this they slide around stiff as boards. It does three things:

	  Walk and run: every frame it swings the arms and legs of every
	  enemy by an amount based on how fast that enemy is moving, leans
	  it into the run, and lets it breathe when it stands still.

	  Hit reactions: whenever an enemy's health drops it flashes white
	  for a moment and flinches, so every hit is felt, not just seen as
	  a number.

	  Stops when it dies, and leaves the body to CombatFX's EnemyDeath.

	It writes Motor6D.Transform, which sits on top of the joint's C0, so
	the attack poses CombatFX tweens on C0 still play over the walk
	rather than fighting it.

	It changes nothing on the server and nothing about where an enemy
	is, it is purely how the limbs look.
]]

--[[
	What connects to this

	Reads:
	  workspace.Runtime.Enemies, which Server.Game.Enemies.EnemySpawner
	  fills. Only models with the IsEnemy attribute EnemyBase writes are
	  animated. The enemy's Humanoid health (the server keeps it equal to
	  the enemy's real health) for the hit flash.

	Started by:
	  ClientGame.ClientMain.

	Transform has to be written in RunService.PreSimulation (Stepped),
	after the Animator has had its turn, or the Animator resets it.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EnemyAnimator = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

EnemyAnimator.Settings = {
	-- Degrees the legs swing at full walk speed, and the arms.
	LegSwing = 42,
	ArmSwing = 34,
	-- Swings per second at 16 studs per second, scaled with speed.
	StepRate = 1.6,
	-- Below this horizontal speed the enemy counts as standing.
	MinSpeed = 1,
	-- Degrees the body leans forward at full speed.
	Lean = 12,
	-- Idle breathing: degrees the arms sway and how fast.
	BreatheAngle = 4,
	BreatheRate = 0.35,
	-- The hit flash and flinch.
	FlashColour = Color3.fromRGB(255, 255, 255),
	FlashTime = 0.1,
	FlinchAngle = 14,
	FlinchTime = 0.18,
	-- Studs away from the camera past which enemies are not animated.
	MaxDistance = 250,
	EnemyAttribute = "IsEnemy",
}

-- Per model: { Joints, Phase, Root, Humanoid, Flinch, Flash }
local Tracked: { [Model]: any } = {}

local function Track(Model: Instance)
	if not Model:IsA("Model") or Tracked[Model] then
		return
	end
	local Torso = Model:WaitForChild("Torso", 5)
	local Root = Model:WaitForChild("HumanoidRootPart", 5)
	local Humanoid = Model:FindFirstChildOfClass("Humanoid")
	if not Torso or not Root or not Humanoid then
		return
	end
	local Rig = {
		Root = Root,
		Humanoid = Humanoid,
		Phase = math.random() * math.pi * 2,
		-- How big the rig is next to a normal one (an R6 root is 2 studs
		-- tall), so a giant takes slow, heavy strides.
		Scale = math.max(1, Root.Size.Y / 2),
		Breathe = math.random() * math.pi * 2,
		Flinch = 0,
		LastHealth = Humanoid.Health,
		RightShoulder = Torso:FindFirstChild("Right Shoulder"),
		LeftShoulder = Torso:FindFirstChild("Left Shoulder"),
		RightHip = Torso:FindFirstChild("Right Hip"),
		LeftHip = Torso:FindFirstChild("Left Hip"),
		RootJoint = Root:FindFirstChild("RootJoint"),
		Neck = Torso:FindFirstChild("Neck"),
	}
	Tracked[Model] = Rig

	-- The hit flash: a white Highlight that fades out fast, and a jolt
	-- back. It is only Enabled while flashing, because Roblox only draws
	-- a limited number of Highlights at once and a room has a lot of
	-- enemies.
	local Flash = Instance.new("Highlight")
	Flash.Name = "HitFlash"
	Flash.FillColor = EnemyAnimator.Settings.FlashColour
	Flash.OutlineTransparency = 1
	Flash.FillTransparency = 1
	Flash.DepthMode = Enum.HighlightDepthMode.Occluded
	Flash.Enabled = false
	Flash.Parent = Model
	Rig.Flash = Flash
	local FlashToken = 0
	Humanoid.HealthChanged:Connect(function(Health)
		local Settings = EnemyAnimator.Settings
		if Health < Rig.LastHealth - 0.01 and Health > 0 then
			FlashToken += 1
			local Token = FlashToken
			Flash.Enabled = true
			Flash.FillTransparency = 0.15
			TweenService:Create(Flash, TweenInfo.new(Settings.FlashTime), { FillTransparency = 1 }):Play()
			task.delay(Settings.FlashTime + 0.02, function()
				if FlashToken == Token then
					Flash.Enabled = false
				end
			end)
			Rig.Flinch = 1
		end
		Rig.LastHealth = Health
	end)

	Model.AncestryChanged:Connect(function(_, Parent)
		if not Parent then
			Tracked[Model] = nil
		end
	end)
end

local function SetAngle(Motor: Motor6D?, Degrees: number)
	if Motor then
		Motor.Transform = CFrame.Angles(0, 0, math.rad(Degrees))
	end
end

local function Step(DeltaTime: number)
	local Settings = EnemyAnimator.Settings
	local Camera = workspace.CurrentCamera
	local CameraPosition = Camera and Camera.CFrame.Position or Vector3.zero
	for Model, Rig in pairs(Tracked) do
		if not Model.Parent or not Rig.Root.Parent then
			Tracked[Model] = nil
			continue
		end
		if Rig.Humanoid.Health <= 0 then
			continue
		end
		if (Rig.Root.Position - CameraPosition).Magnitude > Settings.MaxDistance then
			continue
		end
		local Velocity = Rig.Root.AssemblyLinearVelocity
		local Speed = Vector3.new(Velocity.X, 0, Velocity.Z).Magnitude
		local Amount = 0
		if Speed > Settings.MinSpeed then
			local Relative = Speed / math.sqrt(Rig.Scale)
			Amount = math.clamp(Relative / 16, 0.3, 1.4)
			Rig.Phase += DeltaTime * Settings.StepRate * math.pi * 2 * math.clamp(Relative / 16, 0.5, 1.8)
		else
			-- Ease back to standing.
			Rig.Phase = Rig.Phase * 0.8
		end
		local Swing = math.sin(Rig.Phase) * Amount

		-- Breathing, only really visible when standing.
		Rig.Breathe += DeltaTime * Settings.BreatheRate * math.pi * 2
		local Breathe = math.sin(Rig.Breathe) * Settings.BreatheAngle * (1 - math.min(Amount, 1))

		-- The flinch decays quickly after a hit.
		Rig.Flinch = math.max(0, Rig.Flinch - DeltaTime / Settings.FlinchTime)
		local Flinch = Rig.Flinch * Rig.Flinch * Settings.FlinchAngle

		-- R6 left joints are mirrored, so the same sign on both sides
		-- swings them in opposite directions, which is a walk.
		SetAngle(Rig.RightShoulder, Swing * Settings.ArmSwing + Breathe + Flinch)
		SetAngle(Rig.LeftShoulder, Swing * Settings.ArmSwing - Breathe - Flinch)
		SetAngle(Rig.RightHip, -Swing * Settings.LegSwing)
		SetAngle(Rig.LeftHip, -Swing * Settings.LegSwing)

		-- Lean into the run, and snap back on a hit.
		if Rig.RootJoint then
			local Lean = math.min(Amount, 1) * Settings.Lean - Flinch
			Rig.RootJoint.Transform = CFrame.Angles(math.rad(-Lean), 0, 0)
		end
		if Rig.Neck then
			Rig.Neck.Transform = CFrame.Angles(math.rad(Flinch * 0.8), 0, 0)
		end
	end
end

function EnemyAnimator.Init()
	task.spawn(function()
		local Runtime = workspace:WaitForChild("Runtime", 30)
		local Folder = Runtime and Runtime:WaitForChild("Enemies", 30)
		if not Folder then
			return
		end
		for _, Child in ipairs(Folder:GetChildren()) do
			task.spawn(Track, Child)
		end
		Folder.ChildAdded:Connect(function(Child)
			task.spawn(Track, Child)
		end)
	end)
	RunService.Stepped:Connect(function(_, DeltaTime)
		Step(DeltaTime)
	end)
end

return EnemyAnimator
