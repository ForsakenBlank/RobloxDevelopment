--[[
	CombatFX

	The look and sound of combat, built from code so nothing needs
	uploading. Animations are done by tweening the R6 Motor6D joints
	(shoulder, root) and effects are Parts and ParticleEmitters made on
	the fly. Sounds are clones of the Sounds under SoundService.Sounds.
	Everything is rendered on the client.

	The same module runs on both sides. On the server, Broadcast fires
	the CombatFX remote so every client renders the effect on that
	character. On the client, Play renders one, and the local player
	calls Play directly the moment they press a button so it feels
	instant, then ignores the echo of its own broadcast.

	When a real Animation asset with the same name exists under
	ReplicatedStorage.Assets.Animations, CombatInput plays that instead
	and only the effect half of the entry here runs. So these can be
	replaced one at a time.

	Sound: any effect sent with Data.Sound plays that sound at the
	character (or at Data.Position), and some effects have a default in
	Settings.DefaultSounds, so the server only ever has to name a sound
	and never plays one itself.
]]

--[[
	What connects to this

	Server callers:
	  Server.Game.Combat.Weapons.Sword and Pistol after an attack lands,
	  Server.Game.Combat.Abilities.StunSlam on the jump and the landing,
	  Server.Game.Effects.StatusEffectService when a visual effect starts
	  or ends, and Server.Game.Combat.DamageService for hit sparks.

	Client callers:
	  ClientGame.Controllers.FXController receives the broadcast and
	  calls Play. ClientGame.Controllers.CombatInput and AbilityInput
	  call Play directly for the local player.
	  Controllers that draw screen UI for an effect (HUDEffects for the
	  damage direction arrow) register a handler with CombatFX.Register.

	Reads:
	  Game.Config.HUDConfig is not involved, the colours live in
	  Settings below so they can be tuned in one place.
	  ReplicatedStorage.Modules.Shared.CameraShake for the local shake.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

CombatFX.Settings = {
	-- Where effect parts are parented on the client.
	EffectsFolder = "Effects",

	-- Sounds effects play when the server did not name one. Effects in
	-- OwnSound play their sounds themselves (the Pistol fan plays one
	-- per shot), so the automatic one is skipped for them.
	DefaultSounds = {
		Explosion = "Explosion",
		StunSlam_Land = "StunSlam",
		Teleport_In = "Teleport",
		HealBurst = "HealBurst",
		Rage = "Rage",
		Parry = "Parry",
		BossEnrage = "BossRoar",
		Enemy_Summon = "Summon",
	},
	OwnSound = {
		Pistol_Fan = true,
		DamageNumber = true,
		DamageIndicator = true,
		PlaySound = true,
		Bomber_Fuse = true,
		EnemyDeath = true,
	},
	-- Random pitch spread on every sound, so repeats do not sound
	-- mechanical. 0.08 is up to 8% either way.
	PitchSpread = 0.08,

	-- The Sword's Cleave: a fan of light across the arc it hits.
	SwordCleave = {
		Colour = Color3.fromRGB(215, 235, 255),
		EdgeColour = Color3.fromRGB(120, 190, 255),
		Radius = 10,
		ArcDegrees = 150,
		Segments = 11,
		Height = 0.6,
		Life = 0.22,
		SwingTime = 0.1,
		ReturnTime = 0.18,
	},
	-- The Sword's Whirlwind.
	SwordWhirlwind = {
		PullColour = Color3.fromRGB(120, 190, 255),
		FinalColour = Color3.fromRGB(255, 240, 200),
		RingLife = 0.3,
		ArmAngle = 90,
	},
	-- The flash when the Sword knocks a projectile back.
	Parry = {
		Colour = Color3.fromRGB(255, 230, 120),
		Size = 7,
		Life = 0.25,
		ShakeIntensity = 0.5,
		ShakeDuration = 0.15,
	},
	-- Floating numbers over what you hit. The look is the DamageNumber
	-- template in ReplicatedStorage.Assets.UI.
	DamageNumber = {
		Template = "DamageNumber",
		HitColour = Color3.fromRGB(255, 240, 200),
		CritColour = Color3.fromRGB(255, 205, 50),
		KillColour = Color3.fromRGB(255, 80, 80),
		HealColour = Color3.fromRGB(90, 255, 140),
		-- Hits during the quick swap bonus.
		SwapColour = Color3.fromRGB(90, 220, 255),
		RiseStuds = 3.5,
		Life = 0.75,
		-- Hits on the same target within this many seconds add onto one
		-- number instead of stacking a pile of them (a shotgun blast).
		MergeTime = 0.12,
		PopScale = 1.35,
		-- The hitter's own hit sounds play quieter than world sounds.
		SoundVolume = 0.7,
	},
	-- An enemy dying: it flashes, then breaks up into bits of its colour.
	EnemyDeath = {
		FlashTime = 0.08,
		DissolveDelay = 0.35,
		DissolveTime = 0.45,
		Bits = 14,
		BitSize = 0.5,
		BitSpeed = 22,
	},
	-- The red line on the floor before a charge.
	TelegraphLine = {
		Colour = Color3.fromRGB(255, 40, 40),
		Transparency = 0.45,
		Thickness = 0.15,
	},
	-- A Bomber's fuse: the flashing, the blast radius and the beeping.
	BomberFuse = {
		FlashColour = Color3.fromRGB(255, 60, 30),
		RadiusColour = Color3.fromRGB(255, 80, 40),
		RadiusTransparency = 0.82,
		Beeps = 5,
	},

	-- Procedural arm swings. Angles in degrees, times in seconds.
	PistolShot = {
		AimAngle = 90,
		AimTime = 0.05,
		HoldTime = 0.12,
		RecoilAngle = 12,
		ReturnTime = 0.2,
		FlashColour = Color3.fromRGB(255, 200, 90),
		FlashSize = 0.9,
		FlashLife = 0.06,
	},
	Hit = {
		Colour = Color3.fromRGB(255, 230, 150),
		Count = 8,
		Speed = 14,
		Life = 0.3,
		Size = 0.25,
	},
	StunSlamJump = {
		-- Arms fly up while airborne.
		ArmAngle = 170,
		RaiseTime = 0.12,
	},
	StunSlamLand = {
		-- Chunks of floor that pop up in a ring and sink back down.
		ChunkCount = 16,
		ChunkMinSize = 3,
		ChunkMaxSize = 5.5,
		-- Fraction of the hit radius the ring sits at.
		RingFraction = 0.8,
		-- Chunks start this many studs below the floor surface and pop
		-- up by PopHeight from there, so a bigger SinkOffset keeps them
		-- lower and more embedded in the ground.
		SinkOffset = 2,
		PopHeight = 6,
		PopTime = 0.22,
		HoldTime = 1.4,
		SinkTime = 1.2,
		-- A flat expanding ring of light on the ground.
		ShockColour = Color3.fromRGB(255, 240, 200),
		ShockLife = 0.35,
		-- Camera shake for the local player, scaled by distance.
		ShakeIntensity = 0.9,
		ShakeDuration = 0.35,
		ShakeRange = 60,
		-- Arms slam down.
		ArmAngle = -20,
		SlamTime = 0.08,
		ReturnTime = 0.3,
	},
	Teleport = {
		Colour = Color3.fromRGB(90, 170, 255),
		FlashSize = 6,
		FlashLife = 0.3,
		Particles = 18,
	},
	StatusEffect = {
		-- A ring over the head for Stun, a glow for the rest.
		StunRingRadius = 1.6,
		StunRingHeight = 2.4,
		StunSpinSpeed = 4,
		GlowTransparency = 0.6,
	},

	-- Enemy tells. Every enemy attack flashes the enemy this colour for
	-- its wind up, so the player can see what is about to hit them.
	EnemyWindUp = {
		Colour = Color3.fromRGB(255, 60, 60),
		RangedColour = Color3.fromRGB(255, 160, 40),
		SummonColour = Color3.fromRGB(170, 80, 255),
		FillTransparency = 0.35,
		ArmRaise = 160,
	},
	EnemySwing = {
		ArcColour = Color3.fromRGB(255, 90, 90),
		ArcSize = Vector3.new(7, 0.15, 5),
		SwingTime = 0.1,
		ReturnTime = 0.2,
	},
	-- The red circle on the floor before an area attack lands.
	Telegraph = {
		Colour = Color3.fromRGB(255, 50, 50),
		Transparency = 0.55,
		Thickness = 0.2,
	},
	Summon = {
		Colour = Color3.fromRGB(170, 80, 255),
		PillarHeight = 10,
		Life = 0.6,
	},
	Explosion = {
		Colour = Color3.fromRGB(255, 150, 50),
		CoreColour = Color3.fromRGB(255, 240, 180),
		Life = 0.4,
		ShakeIntensity = 1.1,
		ShakeDuration = 0.35,
		ShakeRange = 70,
		-- Rocket jumping: the player who fired the rocket and is inside
		-- the blast gets thrown away from it at this speed, less the
		-- further out they are. 0 turns it off.
		LaunchSpeed = 95,
		LaunchUp = 0.6,
		LaunchTime = 0.2,
	},
	Tracer = {
		Colour = Color3.fromRGB(255, 230, 150),
		Width = 0.18,
		Life = 0.08,
	},
	ShotgunBlast = {
		AimAngle = 90,
		AimTime = 0.04,
		HoldTime = 0.1,
		RecoilAngle = 35,
		ReturnTime = 0.3,
		FlashColour = Color3.fromRGB(255, 190, 80),
		FlashSize = 2,
		FlashLife = 0.08,
	},
	RocketFire = {
		AimAngle = 90,
		AimTime = 0.08,
		HoldTime = 0.3,
		RecoilAngle = 15,
		ReturnTime = 0.35,
		FlashColour = Color3.fromRGB(255, 140, 60),
		FlashSize = 2.2,
		FlashLife = 0.15,
	},
	-- Player knockback is applied by the player's own client, since it
	-- owns its character's physics. This is how long the push lasts.
	KnockbackTime = 0.15,

	-- A projectile the Sword knocked back turns this colour.
	DeflectedColour = Color3.fromRGB(255, 215, 80),

	-- How each projectile looks, keyed by the ModelName the weapon or
	-- enemy data gives. The server only sends where it started, its
	-- velocity and gravity, and the client draws it moving smoothly with
	-- a trail. The visible size is smaller than the hit radius in the
	-- data on purpose, so shots that look like they hit do hit.
	--   Shape        "Ball" or "Block"
	--   Size         a number (ball) or Vector3 (block, Z is the length)
	--   Colour, Material, Transparency
	--   Light        range of a glow, 0 for none
	--   Trail        { Colour, Width, Life, Transparency } or nil
	--   Fire         size of a flame burning on it, or nil
	--   Spin         radians a second it tumbles end over end, or nil
	-- The Molotov's burning patch, see Effects.MolotovBurn.
	Molotov = {
		FlameColour = Color3.fromRGB(255, 120, 30),
		GlassColour = Color3.fromRGB(120, 180, 90),
		ScorchColour = Color3.fromRGB(28, 20, 16),
		Shards = 10,
		-- Flame emitters per stud of radius, and particles each a second.
		FlamesPerStud = 1.6,
		FlameRate = 14,
		-- Seconds the scorch mark takes to fade once the fire is out.
		ScorchFade = 1.5,
		ShakeIntensity = 0.25,
		ShakeDuration = 0.25,
	},
	ProjectileVisuals = {
		-- The Sword's Crescent Wave: a wide flat blade of light. Its
		-- trail runs across its width (Axis "X") so it leaves a sheet.
		-- The Sword's Crescent Cannon: a huge flat blade of light with a
		-- white hot core, leaving a sheet behind it (Axis "X").
		SwordCrescent = {
			Shape = "Block", Size = Vector3.new(15, 0.5, 2), Colour = Color3.fromRGB(140, 200, 255), Material = Enum.Material.Neon,
			Transparency = 0.1, Light = 20,
			Core = { Size = Vector3.new(11, 0.3, 0.8), Colour = Color3.fromRGB(255, 255, 255) },
			Trail = { Colour = Color3.fromRGB(110, 180, 255), Width = 14.5, Life = 0.25, Transparency = 0.25, Axis = "X" },
		},
		-- The boss's homing orbs.
		BossOrb = {
			Shape = "Ball", Size = 5, Colour = Color3.fromRGB(255, 70, 40), Material = Enum.Material.Neon,
			Light = 18, Fire = 6, Trail = { Colour = Color3.fromRGB(255, 120, 40), Width = 4, Life = 0.4, Transparency = 0.2 },
		},
		Bullet = {
			Shape = "Ball", Size = 0.6, Colour = Color3.fromRGB(255, 225, 90), Material = Enum.Material.Neon,
			Light = 6, Trail = { Colour = Color3.fromRGB(255, 200, 80), Width = 0.45, Life = 0.12, Transparency = 0.2 },
		},
		Pellet = {
			Shape = "Ball", Size = 0.45, Colour = Color3.fromRGB(255, 190, 70), Material = Enum.Material.Neon,
			Light = 0, Trail = { Colour = Color3.fromRGB(255, 170, 60), Width = 0.3, Life = 0.08, Transparency = 0.3 },
		},
		Rocket = {
			Shape = "Block", Size = Vector3.new(0.8, 0.8, 2.4), Colour = Color3.fromRGB(95, 105, 60), Material = Enum.Material.SmoothPlastic,
			Light = 10, Trail = { Colour = Color3.fromRGB(200, 200, 200), Width = 1.4, Life = 0.45, Transparency = 0.35 },
		},
		Bolt = {
			Shape = "Block", Size = Vector3.new(0.3, 0.3, 2.6), Colour = Color3.fromRGB(230, 230, 255), Material = Enum.Material.Neon,
			Light = 4, Trail = { Colour = Color3.fromRGB(170, 200, 255), Width = 0.4, Life = 0.18, Transparency = 0.2 },
		},
		Rock = {
			Shape = "Ball", Size = 2, Colour = Color3.fromRGB(110, 95, 80), Material = Enum.Material.Slate,
			Light = 0, Trail = { Colour = Color3.fromRGB(150, 130, 110), Width = 1.2, Life = 0.25, Transparency = 0.4 },
		},
		NecroBolt = {
			Shape = "Ball", Size = 1.4, Colour = Color3.fromRGB(170, 80, 255), Material = Enum.Material.Neon,
			Light = 10, Trail = { Colour = Color3.fromRGB(150, 60, 255), Width = 1, Life = 0.25, Transparency = 0.2 },
		},
		BossBolt = {
			Shape = "Ball", Size = 3, Colour = Color3.fromRGB(255, 110, 40), Material = Enum.Material.Neon,
			Light = 12, Fire = 3, Trail = { Colour = Color3.fromRGB(255, 70, 30), Width = 2.2, Life = 0.25, Transparency = 0.15 },
		},
		-- A glass bottle with a burning rag, tumbling as it flies.
		Molotov = {
			Shape = "Block", Size = Vector3.new(0.6, 0.6, 1.2), Colour = Color3.fromRGB(110, 170, 80), Material = Enum.Material.Glass,
			Transparency = 0.15, Light = 8, Fire = 2, Spin = 14,
			Trail = { Colour = Color3.fromRGB(255, 140, 40), Width = 0.7, Life = 0.25, Transparency = 0.3 },
		},
	},
}

----------------------------------------------------------------------
-- REMOTE
----------------------------------------------------------------------

local Remote: RemoteEvent? = nil

local function GetRemote(): RemoteEvent?
	if Remote then
		return Remote
	end
	local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local Events = Remotes and Remotes:FindFirstChild("Events")
	if not Events then
		return nil
	end
	local Found = Events:FindFirstChild("CombatFX")
	if not Found and RunService:IsServer() then
		Found = Instance.new("RemoteEvent")
		Found.Name = "CombatFX"
		Found.Parent = Events
	end
	Remote = Found
	return Remote
end

-- Server side. Tells every client to render an effect on a character.
-- Except is the player who already rendered it locally.
function CombatFX.Broadcast(Name: string, Character: Model?, Data: { [string]: any }?, Except: Player?)
	if not RunService:IsServer() then
		CombatFX.Play(Name, Character, Data)
		return
	end
	local Event = GetRemote()
	if not Event then
		return
	end
	for _, Player in ipairs(Players:GetPlayers()) do
		if Player ~= Except then
			Event:FireClient(Player, Name, Character, Data)
		end
	end
end

function CombatFX.GetRemote(): RemoteEvent?
	return GetRemote()
end

-- Server side. Renders an effect for one player only, for things that
-- only matter to them, such as their own knockback.
function CombatFX.SendTo(Player: Player, Name: string, Character: Model?, Data: { [string]: any }?)
	if not RunService:IsServer() then
		CombatFX.Play(Name, Character, Data)
		return
	end
	local Event = GetRemote()
	if Event and Player.Parent == Players then
		Event:FireClient(Player, Name, Character, Data)
	end
end

----------------------------------------------------------------------
-- CLIENT HELPERS
----------------------------------------------------------------------

local function EffectsFolder(): Instance
	local Folder = workspace:FindFirstChild(CombatFX.Settings.EffectsFolder)
	if not Folder then
		Folder = Instance.new("Folder")
		Folder.Name = CombatFX.Settings.EffectsFolder
		Folder.Parent = workspace
	end
	return Folder
end

local function Part(Props: { [string]: any }): BasePart
	local P = Instance.new("Part")
	P.Anchored = true
	P.CanCollide = false
	P.CanQuery = false
	P.CanTouch = false
	P.CastShadow = false
	P.Material = Enum.Material.Neon
	P.TopSurface = Enum.SurfaceType.Smooth
	P.BottomSurface = Enum.SurfaceType.Smooth
	for Key, Value in pairs(Props) do
		(P :: any)[Key] = Value
	end
	return P
end

local function Tween(Object: Instance, Time: number, Goal: { [string]: any }, Style: Enum.EasingStyle?, Direction: Enum.EasingDirection?)
	local T = TweenService:Create(Object, TweenInfo.new(Time, Style or Enum.EasingStyle.Quad, Direction or Enum.EasingDirection.Out), Goal)
	T:Play()
	return T
end

local function RootOf(Character: Model?): BasePart?
	return Character and (Character:FindFirstChild("HumanoidRootPart") or Character.PrimaryPart) or nil
end

-- The R6 joints. Each character keeps its rest C0s so tweens always
-- return to the right place even if two effects overlap.
local RestC0: { [Motor6D]: CFrame } = {}

local function Joint(Character: Model?, Name: string): Motor6D?
	if not Character then
		return nil
	end
	local Torso = Character:FindFirstChild("Torso")
	local Root = Character:FindFirstChild("HumanoidRootPart")
	local Motor = (Torso and Torso:FindFirstChild(Name)) or (Root and Root:FindFirstChild(Name))
	if Motor and Motor:IsA("Motor6D") then
		if not RestC0[Motor] then
			RestC0[Motor] = Motor.C0
		end
		return Motor
	end
	return nil
end

-- Tweens a joint to Rest * Offset over Time. Chain with task.delay.
local function Pose(Motor: Motor6D?, Offset: CFrame, Time: number, Style: Enum.EasingStyle?)
	if not Motor then
		return
	end
	Tween(Motor, Time, { C0 = RestC0[Motor] * Offset }, Style)
end

-- Rotation about the shoulder axis. Positive swings the arm forward
-- and up on an R6 shoulder.
local function ArmForward(Degrees: number): CFrame
	return CFrame.Angles(0, 0, math.rad(Degrees))
end

local function LocalCharacter(): Model?
	local Player = Players.LocalPlayer
	return Player and Player.Character or nil
end

local function ShakeIfNear(Position: Vector3, Intensity: number, Duration: number, Range: number)
	local Root = RootOf(LocalCharacter())
	if not Root then
		return
	end
	local Distance = (Root.Position - Position).Magnitude
	if Distance > Range then
		return
	end
	local Scale = 1 - Distance / Range
	local CameraShake = require(ReplicatedStorage.Modules.Shared.CameraShake)
	CameraShake:Shake(Intensity * Scale, Duration)
end

----------------------------------------------------------------------
-- SOUNDS
----------------------------------------------------------------------

local SoundCache: { [string]: any } = {}

local function FindSound(Name: string): Sound?
	local Cached = SoundCache[Name]
	if Cached ~= nil then
		return Cached or nil
	end
	local SoundService = game:GetService("SoundService")
	local Folder = SoundService:FindFirstChild("Sounds")
	local Found = Folder and Folder:FindFirstChild(Name, true)
	if Found and Found:IsA("Sound") then
		SoundCache[Name] = Found
		return Found
	end
	SoundCache[Name] = false
	return nil
end

-- Plays a sound from SoundService.Sounds. At is a part, attachment or
-- model to play it from, a position, or nil for a flat sound with no
-- position (for the player's own feedback). Volume and Pitch scale the
-- template's own values.
local function PlaySound(Name: string?, At: any, Volume: number?, Pitch: number?)
	if not Name or Name == "" or RunService:IsServer() then
		return nil
	end
	local Template = FindSound(Name)
	if not Template then
		return nil
	end
	local Sound = Template:Clone()
	-- Some files have silence at the front. A StartOffset attribute on
	-- the Sound (seconds) skips it, so the sound lands with the action.
	local Offset = Template:GetAttribute("StartOffset")
	if type(Offset) == "number" and Offset > 0 then
		Sound.TimePosition = Offset
	end
	local Spread = CombatFX.Settings.PitchSpread
	Sound.PlaybackSpeed = Template.PlaybackSpeed * (Pitch or 1) * (1 + (math.random() * 2 - 1) * Spread)
	Sound.Volume = Template.Volume * (Volume or 1)
	-- effects go through SFXGroup so the player's effects volume reaches them
	if not Sound.SoundGroup then
		Sound.SoundGroup = game:GetService("SoundService"):FindFirstChild("SFXGroup")
	end

	local Holder: Instance? = nil
	if typeof(At) == "Instance" and (At:IsA("BasePart") or At:IsA("Attachment")) then
		Sound.Parent = At
	elseif typeof(At) == "Instance" and At:IsA("Model") then
		Sound.Parent = At.PrimaryPart or At:FindFirstChild("HumanoidRootPart") or At:FindFirstChildWhichIsA("BasePart")
	elseif typeof(At) == "Vector3" then
		local Attachment = Instance.new("Attachment")
		Attachment.WorldPosition = At
		Attachment.Parent = workspace.Terrain
		Sound.Parent = Attachment
		Holder = Attachment
	else
		Sound.Parent = game:GetService("SoundService")
	end
	if not Sound.Parent then
		Sound:Destroy()
		return nil
	end
	Sound:Play()
	local Life = math.max(Template.TimeLength, 1) / math.max(Sound.PlaybackSpeed, 0.1) + 0.3
	Debris:AddItem(Holder or Sound, math.min(Life, 12))
	return Sound
end

-- Public so client controllers can play a sound the same way.
function CombatFX.PlaySound(Name: string?, At: any, Volume: number?, Pitch: number?)
	return PlaySound(Name, At, Volume, Pitch)
end

-- Client controllers that draw an effect as screen UI register a
-- handler for its name here, called with (Character, Data).
local Handlers: { [string]: (Model?, any) -> () } = {}

function CombatFX.Register(Name: string, Handler: (Model?, any) -> ())
	Handlers[Name] = Handler
end

----------------------------------------------------------------------
-- EFFECTS
----------------------------------------------------------------------

local Effects: { [string]: (Character: Model?, Data: any) -> () } = {}


-- Cleave: a quick flat slash across the body, alternating direction
-- each swing, and a fan of light over the arc it hits.
local CleaveSide: { [Model]: number } = {}

Effects.Sword_Cleave = function(Character, Data)
	local S = CombatFX.Settings.SwordCleave
	if not Character then
		return
	end
	local First = CleaveSide[Character] == nil
	local Side = -(CleaveSide[Character] or -1)
	CleaveSide[Character] = Side
	if First then
		Character.Destroying:Once(function()
			CleaveSide[Character] = nil
		end)
	end

	local Shoulder = Joint(Character, "Right Shoulder")
	local Torso = Joint(Character, "RootJoint")
	local StartYaw, EndYaw = 70 * Side, -60 * Side
	Pose(Shoulder, CFrame.Angles(0, math.rad(StartYaw), 0) * ArmForward(95), 0.04)
	Pose(Torso, CFrame.Angles(0, math.rad(-StartYaw * 0.35), 0), 0.04)
	task.delay(0.04, function()
		Pose(Shoulder, CFrame.Angles(0, math.rad(EndYaw), 0) * ArmForward(95), S.SwingTime, Enum.EasingStyle.Back)
		Pose(Torso, CFrame.Angles(0, math.rad(-EndYaw * 0.35), 0), S.SwingTime)
		task.delay(S.SwingTime + 0.04, function()
			Pose(Shoulder, CFrame.new(), S.ReturnTime)
			Pose(Torso, CFrame.new(), S.ReturnTime)
		end)
	end)

	local Root = RootOf(Character)
	if not Root then
		return
	end
	-- The arc faces where the server will hit: the cursor for the local
	-- player, the way the character faces for everyone else.
	local Facing = Root.CFrame.LookVector
	if Data and typeof(Data.Direction) == "Vector3" and Data.Direction.Magnitude > 0.1 then
		Facing = Data.Direction
	end
	Facing = Vector3.new(Facing.X, 0, Facing.Z)
	if Facing.Magnitude < 0.01 then
		return
	end
	local Base = CFrame.lookAt(Root.Position, Root.Position + Facing.Unit)
	local Folder = EffectsFolder()
	local Half = S.ArcDegrees / 2
	local Tilt = math.rad(12 * Side)
	local Length = S.Radius * math.rad(S.ArcDegrees) / S.Segments * 1.25
	for Index = 1, S.Segments do
		local T = (Index - 1) / (S.Segments - 1)
		local Angle = math.rad(-Half + S.ArcDegrees * T) * Side
		task.delay(T * 0.06, function()
			local Segment = Part({
				Size = Vector3.new(Length, S.Height, 0.25),
				Color = Index % 2 == 0 and S.Colour or S.EdgeColour,
				Transparency = 0.15,
				CFrame = Base * CFrame.Angles(Tilt, Angle, 0) * CFrame.new(0, 0.4, -S.Radius),
				Parent = Folder,
			})
			Tween(Segment, S.Life, {
				Transparency = 1,
				Size = Vector3.new(Length * 1.2, 0.05, 0.05),
				CFrame = Segment.CFrame * CFrame.new(0, 0, -1.5),
			})
			Debris:AddItem(Segment, S.Life)
		end)
	end
end

-- Whirlwind: the body spins for the whole attack, a ring closes in on
-- each dragging tick, and the last one bursts outwards.
Effects.Sword_Whirlwind = function(Character, Data)
	local S = CombatFX.Settings.SwordWhirlwind
	local WeaponData = require(ReplicatedStorage.Modules.Game.Data.WeaponData)
	local Attack = WeaponData.Weapons.Sword.MB2
	local Ticks = Attack.Ticks or 1
	local Interval = Attack.TickInterval or 0.15
	local Radius = Attack.Radius or 14
	local SpinTime = (Ticks - 1) * Interval + 0.2

	local RootJoint = Joint(Character, "RootJoint")
	local Shoulder = Joint(Character, "Right Shoulder")
	local Other = Joint(Character, "Left Shoulder")
	Pose(Shoulder, ArmForward(S.ArmAngle), 0.06)
	Pose(Other, ArmForward(-S.ArmAngle), 0.06)
	if RootJoint then
		-- Turns in 120 degree steps so the tween never takes the short
		-- way round.
		local Rest = RestC0[RootJoint]
		local Steps = math.max(3, Ticks * 3)
		local Step = SpinTime / Steps
		for Index = 1, Steps do
			task.delay((Index - 1) * Step, function()
				if RootJoint.Parent then
					Tween(RootJoint, Step, { C0 = Rest * CFrame.Angles(0, math.rad((Index % 3) * 120), 0) }, Enum.EasingStyle.Linear)
				end
			end)
		end
		task.delay(SpinTime, function()
			if RootJoint.Parent then
				Tween(RootJoint, 0.1, { C0 = Rest })
			end
		end)
	end
	task.delay(SpinTime, function()
		Pose(Shoulder, CFrame.new(), 0.15)
		Pose(Other, CFrame.new(), 0.15)
	end)

	for Index = 1, Ticks do
		task.delay((Index - 1) * Interval, function()
			local Root = RootOf(Character)
			if not Root then
				return
			end
			local Final = Index == Ticks
			local Centre = CFrame.new(Root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
			local Ring = Part({
				Shape = Enum.PartType.Cylinder,
				Size = Final and Vector3.new(0.25, 3, 3) or Vector3.new(0.2, Radius * 2, Radius * 2),
				Color = Final and S.FinalColour or S.PullColour,
				Transparency = 0.25,
				CFrame = Centre,
				Parent = EffectsFolder(),
			})
			if Final then
				Tween(Ring, S.RingLife, { Size = Vector3.new(0.25, Radius * 2.4, Radius * 2.4), Transparency = 1 })
				ShakeIfNear(Root.Position, 0.6, 0.2, 30)
				if Index > 1 then
					PlaySound("SwordSwingHeavy", Root, 1, 0.8)
				end
			else
				-- A dragging tick: the ring closes in.
				Tween(Ring, S.RingLife, { Size = Vector3.new(0.2, 2, 2), Transparency = 1 })
				if Index > 1 then
					PlaySound("SwordSwing", Root, 0.8, 1.1)
				end
			end
			Debris:AddItem(Ring, S.RingLife)
		end)
	end
end

-- The big swing the Crescent Cannon is fired from: arm back, then a
-- flat sweep across with a burst of light at the hand.
Effects.Sword_Crescent = function(Character, Data)
	local Shoulder = Joint(Character, "Right Shoulder")
	local Torso = Joint(Character, "RootJoint")
	Pose(Shoulder, CFrame.Angles(0, math.rad(80), 0) * ArmForward(100), 0.08)
	Pose(Torso, CFrame.Angles(0, math.rad(-35), 0), 0.08)
	task.delay(0.1, function()
		Pose(Shoulder, CFrame.Angles(0, math.rad(-70), 0) * ArmForward(95), 0.1, Enum.EasingStyle.Back)
		Pose(Torso, CFrame.Angles(0, math.rad(30), 0), 0.1)
		local Root = RootOf(Character)
		if Root then
			local Flash = Part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 2,
				Color = Color3.fromRGB(170, 220, 255),
				Transparency = 0.1,
				Position = Root.Position + Root.CFrame.LookVector * 3,
				Parent = EffectsFolder(),
			})
			Tween(Flash, 0.25, { Size = Vector3.one * 12, Transparency = 1 })
			Debris:AddItem(Flash, 0.25)
			if Character == LocalCharacter() then
				local CameraShake = require(ReplicatedStorage.Modules.Shared.CameraShake)
				CameraShake:Shake(0.45, 0.15)
			end
		end
		task.delay(0.22, function()
			Pose(Shoulder, CFrame.new(), 0.2)
			Pose(Torso, CFrame.new(), 0.2)
		end)
	end)
end

-- Meteors: a red circle at every point that fills in, a burning rock
-- falling out of the sky onto it, and a blast when it lands.
-- Data: Points = { { Position, Delay } }, Radius.
Effects.MeteorRain = function(Character, Data)
	if not Data or type(Data.Points) ~= "table" then
		return
	end
	local Radius = Data.Radius or 8
	for _, Point in ipairs(Data.Points) do
		local Position = Point.Position
		local Delay = Point.Delay or 1
		if typeof(Position) ~= "Vector3" then
			continue
		end
		Effects.Telegraph_Circle(nil, { Position = Position, Radius = Radius, Duration = Delay })
		-- The rock drops for the last FallTime seconds of the delay.
		local FallTime = math.min(0.45, Delay)
		task.delay(Delay - FallTime, function()
			local Start = Position + Vector3.new(math.random(-12, 12), 90, math.random(-12, 12))
			local Rock = Part({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * 4,
				Color = Color3.fromRGB(255, 110, 40),
				Material = Enum.Material.Neon,
				Position = Start,
				Parent = EffectsFolder(),
			})
			local Fire = Instance.new("Fire")
			Fire.Size = 8
			Fire.Heat = 15
			Fire.Color = Color3.fromRGB(255, 120, 40)
			Fire.SecondaryColor = Color3.fromRGB(255, 40, 20)
			Fire.Parent = Rock
			Tween(Rock, FallTime, { Position = Position }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(Rock, FallTime + 0.05)
			if Point == Data.Points[1] then
				PlaySound("Whoosh", Position, 0.8, 0.8)
			end
		end)
		task.delay(Delay, function()
			Effects.Explosion(nil, { Position = Position, Radius = Radius, Hostile = true })
			PlaySound("Explosion", Position, 0.6, 1.1)
		end)
	end
end

-- Rings of fire that spread across the floor. Data: Position, Speed,
-- MaxRadius, Width, Rings, RingGap.
Effects.Shockwave = function(Character, Data)
	if not Data or typeof(Data.Position) ~= "Vector3" then
		return
	end
	local Speed = Data.Speed or 60
	local MaxRadius = Data.MaxRadius or 120
	local Width = Data.Width or 4
	local Life = MaxRadius / Speed
	for Ring = 1, Data.Rings or 1 do
		task.delay((Ring - 1) * (Data.RingGap or 0.6), function()
			local At = CFrame.new(Data.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
			-- Two cylinders: a bright rim and a faint fill behind it, so
			-- the edge that hits is easy to read.
			local Rim = Part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2.5, Width * 2, Width * 2),
				Color = Color3.fromRGB(255, 90, 30),
				Transparency = 0.25,
				CFrame = At,
				Parent = EffectsFolder(),
			})
			local Inner = Part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(2.6, 1, 1),
				Color = Color3.fromRGB(30, 10, 10),
				Material = Enum.Material.SmoothPlastic,
				Transparency = 0.5,
				CFrame = At,
				Parent = EffectsFolder(),
			})
			Tween(Rim, Life, { Size = Vector3.new(2.5, MaxRadius * 2 + Width, MaxRadius * 2 + Width), Transparency = 0.6 }, Enum.EasingStyle.Linear)
			Tween(Inner, Life, { Size = Vector3.new(2.6, MaxRadius * 2 - Width, MaxRadius * 2 - Width), Transparency = 0.9 }, Enum.EasingStyle.Linear)
			Debris:AddItem(Rim, Life)
			Debris:AddItem(Inner, Life)
			ShakeIfNear(Data.Position, 0.8, 0.3, MaxRadius)
		end)
	end
end

-- The Sword knocking a projectile back. Data: Position.
Effects.Parry = function(Character, Data)
	local S = CombatFX.Settings.Parry
	local Position = Data and Data.Position or (RootOf(Character) and RootOf(Character).Position)
	if not Position then
		return
	end
	local Flash = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one,
		Color = S.Colour,
		Transparency = 0.05,
		Position = Position,
		Parent = EffectsFolder(),
	})
	local Light = Instance.new("PointLight")
	Light.Color = S.Colour
	Light.Brightness = 6
	Light.Range = 18
	Light.Parent = Flash
	Tween(Flash, S.Life, { Size = Vector3.one * S.Size, Transparency = 1 })
	Debris:AddItem(Flash, S.Life)
	Effects.Hit(nil, { Position = Position, Colour = S.Colour, Crit = true })
	-- Only the parrying player feels it.
	if Character and Character == LocalCharacter() then
		local CameraShake = require(ReplicatedStorage.Modules.Shared.CameraShake)
		CameraShake:Shake(S.ShakeIntensity, S.ShakeDuration)
	end
end

local function GunPose(Character, S)
	local Shoulder = Joint(Character, "Right Shoulder")
	Pose(Shoulder, ArmForward(S.AimAngle + S.RecoilAngle), S.AimTime)
	task.delay(S.AimTime, function()
		Pose(Shoulder, ArmForward(S.AimAngle), S.HoldTime)
		task.delay(S.HoldTime, function()
			Pose(Shoulder, CFrame.new(), S.ReturnTime)
		end)
	end)
end

local function MuzzleFlash(Character, S)
	local Arm = Character and Character:FindFirstChild("Right Arm")
	if not Arm then
		return
	end
	local Flash = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(S.FlashSize, S.FlashSize, S.FlashSize),
		Color = S.FlashColour,
		Transparency = 0.1,
		CFrame = Arm.CFrame * CFrame.new(0, -1.2, -1.5),
		Parent = EffectsFolder(),
	})
	local Light = Instance.new("PointLight")
	Light.Color = S.FlashColour
	Light.Brightness = 3
	Light.Range = 10
	Light.Parent = Flash
	Tween(Flash, S.FlashLife, { Transparency = 1, Size = Flash.Size * 1.6 })
	Debris:AddItem(Flash, S.FlashLife)
end

Effects.Pistol_Shoot = function(Character, Data)
	local S = CombatFX.Settings.PistolShot
	GunPose(Character, S)
	MuzzleFlash(Character, S)
end

-- Sparks at a hit point. Data.Position is required.
Effects.Hit = function(Character, Data)
	local S = CombatFX.Settings.Hit
	local Position = Data and Data.Position
	if not Position then
		local Root = RootOf(Character)
		Position = Root and Root.Position
	end
	if not Position then
		return
	end
	local Anchor = Part({
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		Position = Position,
		Parent = EffectsFolder(),
	})
	local Crit = Data and Data.Crit
	local Emitter = Instance.new("ParticleEmitter")
	Emitter.Color = ColorSequence.new(Data and Data.Colour or (Crit and Color3.fromRGB(255, 215, 60) or S.Colour))
	Emitter.Size = NumberSequence.new(Crit and S.Size * 1.8 or S.Size, 0)
	Emitter.Lifetime = NumberRange.new(S.Life * 0.6, S.Life)
	Emitter.Speed = NumberRange.new(S.Speed * 0.5, Crit and S.Speed * 1.6 or S.Speed)
	Emitter.SpreadAngle = Vector2.new(180, 180)
	Emitter.Rate = 0
	Emitter.LightEmission = 1
	Emitter.Drag = 4
	Emitter.Parent = Anchor
	Emitter:Emit(Data and Data.Small and math.ceil(S.Count / 2) or (Crit and S.Count * 2 or S.Count))
	Debris:AddItem(Anchor, S.Life + 0.1)
end

Effects.StunSlam_Jump = function(Character, Data)
	local S = CombatFX.Settings.StunSlamJump
	Pose(Joint(Character, "Right Shoulder"), ArmForward(S.ArmAngle), S.RaiseTime)
	Pose(Joint(Character, "Left Shoulder"), ArmForward(-S.ArmAngle), S.RaiseTime)
end

-- Data: Position, Radius, Material, Colour (the floor that was hit).
Effects.StunSlam_Land = function(Character, Data)
	local S = CombatFX.Settings.StunSlamLand
	Pose(Joint(Character, "Right Shoulder"), ArmForward(S.ArmAngle), S.SlamTime)
	Pose(Joint(Character, "Left Shoulder"), ArmForward(-S.ArmAngle), S.SlamTime)
	task.delay(S.SlamTime + 0.1, function()
		Pose(Joint(Character, "Right Shoulder"), CFrame.new(), S.ReturnTime)
		Pose(Joint(Character, "Left Shoulder"), CFrame.new(), S.ReturnTime)
	end)

	local Position = Data and Data.Position
	if not Position then
		local Root = RootOf(Character)
		Position = Root and (Root.Position - Vector3.new(0, 3, 0))
	end
	if not Position then
		return
	end
	local Radius = Data and Data.Radius or 16
	local Material = Data and Data.Material or Enum.Material.Concrete
	local Colour = Data and Data.Colour or Color3.fromRGB(120, 120, 120)
	local Folder = EffectsFolder()

	-- Shockwave ring on the ground.
	local Ring = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		Color = S.ShockColour,
		Transparency = 0.2,
		CFrame = CFrame.new(Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = Folder,
	})
	Tween(Ring, S.ShockLife, { Size = Vector3.new(0.3, Radius * 2, Radius * 2), Transparency = 1 })
	Debris:AddItem(Ring, S.ShockLife)

	-- Floor chunks. They match the floor so it looks like the ground
	-- broke up, then sink back into it and vanish. The real floor is
	-- never touched. Each one finds the actual floor under its own spot,
	-- so on uneven ground or near an edge they sit on (and half inside)
	-- the ground rather than floating, and a spot with no floor under
	-- it gets no chunk.
	local RingRadius = Radius * S.RingFraction
	local FloorParams = RaycastParams.new()
	FloorParams.FilterType = Enum.RaycastFilterType.Exclude
	local Ignore = { Folder, workspace.CurrentCamera }
	for _, Name in ipairs({ "Runtime", "ClientFX" }) do
		local Found = workspace:FindFirstChild(Name)
		if Found then
			table.insert(Ignore, Found)
		end
	end
	for _, Other in ipairs(Players:GetPlayers()) do
		if Other.Character then
			table.insert(Ignore, Other.Character)
		end
	end
	FloorParams.FilterDescendantsInstances = Ignore
	for Index = 1, S.ChunkCount do
		local Angle = (Index / S.ChunkCount) * math.pi * 2 + math.random() * 0.4
		local Distance = RingRadius * (0.7 + math.random() * 0.4)
		local Size = S.ChunkMinSize + math.random() * (S.ChunkMaxSize - S.ChunkMinSize)
		local Spot = Position + Vector3.new(math.cos(Angle) * Distance, 0, math.sin(Angle) * Distance)
		local Floor = workspace:Raycast(Spot + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), FloorParams)
		if not Floor then
			continue
		end
		-- Starts fully under the floor and rises until a bit more than
		-- half of it shows, so it is always planted in the ground.
		local Base = Floor.Position - Vector3.new(0, Size / 2 + 0.2, 0)
		local Chunk = Part({
			Size = Vector3.new(Size, Size, Size),
			Material = Material,
			Color = Colour,
			CastShadow = true,
			CFrame = CFrame.new(Base) * CFrame.Angles(math.random() * 0.4, math.random() * math.pi, math.random() * 0.4),
			Parent = Folder,
		})
		local Up = Chunk.CFrame + Vector3.new(0, Size * (0.45 + math.random() * 0.2), 0)
		local Tilt = Up * CFrame.Angles(math.random() * 0.6 - 0.3, 0, math.random() * 0.6 - 0.3)
		Tween(Chunk, S.PopTime, { CFrame = Tilt }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(S.PopTime + S.HoldTime, function()
			Tween(Chunk, S.SinkTime, { CFrame = CFrame.new(Base - Vector3.new(0, Size, 0)) * Tilt.Rotation, Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		Debris:AddItem(Chunk, S.PopTime + S.HoldTime + S.SinkTime)
	end

	ShakeIfNear(Position, S.ShakeIntensity, S.ShakeDuration, S.ShakeRange)
end

local function TeleportFlash(Position: Vector3, Grow: boolean)
	local S = CombatFX.Settings.Teleport
	local Flash = Part({
		Shape = Enum.PartType.Ball,
		Size = Grow and Vector3.new(0.5, 0.5, 0.5) or Vector3.new(S.FlashSize, S.FlashSize, S.FlashSize),
		Color = S.Colour,
		Transparency = 0.2,
		Position = Position,
		Parent = EffectsFolder(),
	})
	local Light = Instance.new("PointLight")
	Light.Color = S.Colour
	Light.Brightness = 2
	Light.Range = 12
	Light.Parent = Flash
	Tween(Flash, S.FlashLife, {
		Size = Grow and Vector3.new(S.FlashSize, S.FlashSize, S.FlashSize) or Vector3.new(0.5, 0.5, 0.5),
		Transparency = 1,
	})
	local Emitter = Instance.new("ParticleEmitter")
	Emitter.Color = ColorSequence.new(S.Colour)
	Emitter.Size = NumberSequence.new(0.35, 0)
	Emitter.Lifetime = NumberRange.new(0.3, 0.5)
	Emitter.Speed = NumberRange.new(6, 12)
	Emitter.SpreadAngle = Vector2.new(180, 180)
	Emitter.Rate = 0
	Emitter.LightEmission = 1
	Emitter.Parent = Flash
	Emitter:Emit(S.Particles)
	Debris:AddItem(Flash, 0.6)
end

Effects.Teleport_Out = function(Character, Data)
	local Position = Data and Data.Position or (RootOf(Character) and RootOf(Character).Position)
	if Position then
		TeleportFlash(Position, false)
	end
end

Effects.Teleport_In = function(Character, Data)
	local Position = Data and Data.Position or (RootOf(Character) and RootOf(Character).Position)
	if Position then
		TeleportFlash(Position, true)
		-- The strike where it lands.
		local Radius = Data and Data.Radius or 0
		if Radius > 0 then
			local S = CombatFX.Settings.Teleport
			local Ring = Part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.3, 2, 2),
				Color = S.Colour,
				Transparency = 0.1,
				CFrame = CFrame.new(Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Parent = EffectsFolder(),
			})
			Tween(Ring, 0.3, { Size = Vector3.new(0.3, Radius * 2, Radius * 2), Transparency = 1 })
			Debris:AddItem(Ring, 0.3)
			ShakeIfNear(Position, 0.5, 0.2, 30)
		end
	end
end

-- Ongoing status effect visuals, keyed by character then effect.
local StatusVisuals: { [Model]: { [string]: Instance } } = {}

Effects.StatusEffectStart = function(Character, Data)
	if not Character or not Data or not Data.Name then
		return
	end
	local S = CombatFX.Settings.StatusEffect
	local Existing = StatusVisuals[Character] and StatusVisuals[Character][Data.Name]
	if Existing then
		Existing:Destroy()
	end
	local Head = Character:FindFirstChild("Head") or RootOf(Character)
	if not Head then
		return
	end

	local Visual: Instance
	if Data.Name == "Stun" then
		local Ring = Part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.15, S.StunRingRadius * 2, S.StunRingRadius * 2),
			Color = Data.Colour or Color3.fromRGB(255, 230, 80),
			Transparency = 0.2,
			Parent = EffectsFolder(),
		})
		local Spin = 0
		local Conn
		Conn = RunService.Heartbeat:Connect(function(DeltaTime)
			if not Ring.Parent or not Head.Parent then
				Conn:Disconnect()
				return
			end
			Spin += DeltaTime * S.StunSpinSpeed
			Ring.CFrame = CFrame.new(Head.Position + Vector3.new(0, S.StunRingHeight, 0)) * CFrame.Angles(0, Spin, math.rad(90))
		end)
		Visual = Ring
	else
		local Glow = Instance.new("Highlight")
		Glow.FillColor = Data.Colour or Color3.new(1, 1, 1)
		Glow.FillTransparency = S.GlowTransparency
		Glow.OutlineTransparency = 0.5
		Glow.Parent = Character
		Visual = Glow
	end

	StatusVisuals[Character] = StatusVisuals[Character] or {}
	StatusVisuals[Character][Data.Name] = Visual
	if Data.Duration then
		Debris:AddItem(Visual, Data.Duration + 0.2)
	end
end

Effects.StatusEffectEnd = function(Character, Data)
	local Visuals = Character and StatusVisuals[Character]
	local Visual = Visuals and Data and Visuals[Data.Name]
	if Visual then
		Visual:Destroy()
		Visuals[Data.Name] = nil
	end
end

----------------------------------------------------------------------
-- WEAPONS
----------------------------------------------------------------------

-- A thin beam from the muzzle to where a hitscan shot ended.
-- Data: From, To.
Effects.Tracer = function(Character, Data)
	if not Data or not Data.From or not Data.To then
		return
	end
	local S = CombatFX.Settings.Tracer
	local Length = (Data.To - Data.From).Magnitude
	if Length < 0.1 then
		return
	end
	local Beam = Part({
		Size = Vector3.new(S.Width, S.Width, Length),
		Color = Data.Colour or S.Colour,
		Transparency = 0.1,
		CFrame = CFrame.lookAt(Data.From, Data.To) * CFrame.new(0, 0, -Length / 2),
		Parent = EffectsFolder(),
	})
	Tween(Beam, S.Life, { Transparency = 1, Size = Vector3.new(0.02, 0.02, Length) })
	Debris:AddItem(Beam, S.Life)
end

Effects.Pistol_Fan = function(Character, Data)
	local S = CombatFX.Settings.PistolShot
	local Count = Data and Data.Shots or 6
	local Gap = Data and Data.Gap or 0.07
	local Shoulder = Joint(Character, "Right Shoulder")
	local Other = Joint(Character, "Left Shoulder")
	Pose(Shoulder, ArmForward(S.AimAngle), S.AimTime)
	Pose(Other, CFrame.Angles(0, math.rad(40), 0) * ArmForward(-80), S.AimTime)
	for Index = 1, Count do
		task.delay((Index - 1) * Gap, function()
			Pose(Shoulder, ArmForward(S.AimAngle + S.RecoilAngle), 0.02)
			MuzzleFlash(Character, S)
			PlaySound(Data and Data.Sound or "PistolFan", RootOf(Character), 0.85, 1 + Index * 0.02)
			task.delay(0.03, function()
				Pose(Shoulder, ArmForward(S.AimAngle), Gap * 0.6)
			end)
		end)
	end
	task.delay(Count * Gap + 0.1, function()
		Pose(Shoulder, CFrame.new(), S.ReturnTime)
		Pose(Other, CFrame.new(), S.ReturnTime)
	end)
end

Effects.Shotgun_Fire = function(Character, Data)
	local S = CombatFX.Settings.ShotgunBlast
	GunPose(Character, S)
	MuzzleFlash(Character, S)
	local Root = RootOf(Character)
	if Root then
		ShakeIfNear(Root.Position, 0.35, 0.12, 8)
	end
end

Effects.Shotgun_Burst = function(Character, Data)
	local S = CombatFX.Settings.ShotgunBlast
	GunPose(Character, S)
	MuzzleFlash(Character, S)
	task.delay(0.04, function()
		MuzzleFlash(Character, S)
	end)
	local Root = RootOf(Character)
	if Root then
		ShakeIfNear(Root.Position, 0.6, 0.18, 8)
	end
end

Effects.RPG_Fire = function(Character, Data)
	local S = CombatFX.Settings.RocketFire
	GunPose(Character, S)
	MuzzleFlash(Character, S)
	local Root = RootOf(Character)
	if Root then
		ShakeIfNear(Root.Position, 0.4, 0.15, 8)
	end
end

-- Data: Position, Radius, LaunchOwner (UserId of the player who fired
-- it, for rocket jumping).
-- The Molotov bursting: glass flying, a flash of flame, then a patch
-- of fire across the whole area (flames, embers, smoke, a flickering
-- light and a scorch mark) that burns down and fades at the end.
-- Data: Position, Radius, Duration.
Effects.MolotovBurn = function(Character, Data)
	local S = CombatFX.Settings.Molotov
	local Position = Data and Data.Position
	if typeof(Position) ~= "Vector3" then
		return
	end
	local Radius = Data.Radius or 10
	local Duration = Data.Duration or 5
	local Folder = EffectsFolder()
	local Flat = CFrame.new(Position) * CFrame.Angles(0, 0, math.rad(90))

	-- Glass.
	for _ = 1, S.Shards do
		local Angle = math.random() * math.pi * 2
		local Out = Vector3.new(math.cos(Angle), 0, math.sin(Angle))
		local Shard = Part({
			Size = Vector3.new(0.3, 0.1, 0.4) * (0.6 + math.random()),
			Color = S.GlassColour,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			CFrame = CFrame.new(Position + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Parent = Folder,
		})
		Tween(Shard, 0.45, {
			CFrame = CFrame.new(Position + Out * (2 + math.random() * 4) + Vector3.new(0, 0.2, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Transparency = 1,
		})
		Debris:AddItem(Shard, 0.5)
	end

	-- The flash of flame rolling out over the area.
	local Burst = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2,
		Color = S.FlameColour,
		Transparency = 0.1,
		Position = Position,
		Parent = Folder,
	})
	Tween(Burst, 0.35, { Size = Vector3.new(Radius * 2, Radius * 0.6, Radius * 2), Transparency = 1 })
	Debris:AddItem(Burst, 0.4)
	ShakeIfNear(Position, S.ShakeIntensity, S.ShakeDuration, Radius * 4)

	-- The scorch and the edge of the burning area, so it is clear where
	-- it hurts.
	local Scorch = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.1, Radius * 1.2, Radius * 1.2),
		Color = S.ScorchColour,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.25,
		CFrame = Flat + Vector3.new(0, 0.06, 0),
		Parent = Folder,
	})
	Tween(Scorch, 0.3, { Size = Vector3.new(0.1, Radius * 2, Radius * 2) })
	local Edge = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, Radius * 2, Radius * 2),
		Color = S.FlameColour,
		Transparency = 0.8,
		CFrame = Flat + Vector3.new(0, 0.1, 0),
		Parent = Folder,
	})

	-- Flames spread across the patch.
	local Sources = {}
	local Count = math.clamp(math.floor(Radius * S.FlamesPerStud), 4, 40)
	for Index = 1, Count do
		local Distance = Radius * math.sqrt((Index - 0.5) / Count) * 0.9
		local Angle = Index * 2.39996
		local At = Position + Vector3.new(math.cos(Angle) * Distance, 0.5, math.sin(Angle) * Distance)
		local Holder = Part({ Size = Vector3.one * 0.2, Transparency = 1, Position = At, Parent = Folder })
		local Flames = Instance.new("ParticleEmitter")
		Flames.Texture = "rbxasset://textures/particles/fire_main.dds"
		Flames.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 120)),
			ColorSequenceKeypoint.new(0.4, S.FlameColour),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 30, 10)),
		})
		Flames.LightEmission = 1
		Flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.4) })
		Flames.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		Flames.Lifetime = NumberRange.new(0.5, 1)
		Flames.Speed = NumberRange.new(3, 7)
		Flames.SpreadAngle = Vector2.new(15, 15)
		Flames.EmissionDirection = Enum.NormalId.Top
		Flames.Rate = S.FlameRate
		Flames.RotSpeed = NumberRange.new(-60, 60)
		Flames.Parent = Holder
		table.insert(Sources, Flames)
		if Index % 4 == 0 then
			local Embers = Instance.new("ParticleEmitter")
			Embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			Embers.Color = ColorSequence.new(Color3.fromRGB(255, 170, 60))
			Embers.LightEmission = 1
			Embers.Size = NumberSequence.new(0.25, 0)
			Embers.Lifetime = NumberRange.new(1, 2)
			Embers.Speed = NumberRange.new(4, 9)
			Embers.SpreadAngle = Vector2.new(35, 35)
			Embers.Acceleration = Vector3.new(0, 3, 0)
			Embers.Rate = 6
			Embers.Parent = Holder
			table.insert(Sources, Embers)
		end
	end
	local Centre = Part({ Size = Vector3.one * 0.2, Transparency = 1, Position = Position + Vector3.new(0, 1, 0), Parent = Folder })
	local Smoke = Instance.new("ParticleEmitter")
	Smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	Smoke.Color = ColorSequence.new(Color3.fromRGB(45, 40, 38))
	Smoke.Size = NumberSequence.new(Radius * 0.3, Radius * 0.7)
	Smoke.Transparency = NumberSequence.new(0.5, 1)
	Smoke.Lifetime = NumberRange.new(2, 3)
	Smoke.Speed = NumberRange.new(4, 7)
	Smoke.SpreadAngle = Vector2.new(20, 20)
	Smoke.Rate = 5
	Smoke.Parent = Centre
	table.insert(Sources, Smoke)
	local Light = Instance.new("PointLight")
	Light.Color = S.FlameColour
	Light.Range = Radius * 1.8
	Light.Brightness = 3
	Light.Parent = Centre

	-- Flicker the light while it burns, then let it all die down.
	local Ends = os.clock() + Duration
	task.spawn(function()
		while os.clock() < Ends and Centre.Parent do
			Light.Brightness = 2.2 + math.random() * 1.8
			task.wait(0.08)
		end
		for _, Source in ipairs(Sources) do
			Source.Enabled = false
		end
		Tween(Light, 0.8, { Brightness = 0 })
		Tween(Edge, 0.8, { Transparency = 1 })
		Tween(Scorch, S.ScorchFade, { Transparency = 1 })
		task.wait(S.ScorchFade)
		for _, Item in ipairs(Sources) do
			local Holder = Item.Parent
			if Holder then
				Holder:Destroy()
			end
		end
		Centre:Destroy()
		Edge:Destroy()
		Scorch:Destroy()
	end)
end

Effects.Explosion = function(Character, Data)
	local S = CombatFX.Settings.Explosion
	local Position = Data and Data.Position
	if not Position then
		return
	end
	local Radius = Data.Radius or 12
	local Folder = EffectsFolder()
	local Colour = Data.Hostile and Color3.fromRGB(255, 90, 40) or S.Colour

	-- A ring of smoke along the ground.
	local Smoke = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, Radius * 0.6, Radius * 0.6),
		Color = Color3.fromRGB(70, 70, 70),
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.4,
		CFrame = CFrame.new(Position - Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = Folder,
	})
	Tween(Smoke, S.Life * 2, { Size = Vector3.new(0.2, Radius * 2.6, Radius * 2.6), Transparency = 1 })
	Debris:AddItem(Smoke, S.Life * 2)

	local Ball = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Color = Colour,
		Transparency = 0.15,
		Position = Position,
		Parent = Folder,
	})
	local Core = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1, 1, 1),
		Color = S.CoreColour,
		Transparency = 0,
		Position = Position,
		Parent = Folder,
	})
	local Light = Instance.new("PointLight")
	Light.Color = S.Colour
	Light.Brightness = 5
	Light.Range = Radius * 2
	Light.Parent = Core
	Tween(Ball, S.Life, { Size = Vector3.one * Radius * 2, Transparency = 1 })
	Tween(Core, S.Life * 0.7, { Size = Vector3.one * Radius, Transparency = 1 })
	Debris:AddItem(Ball, S.Life)
	Debris:AddItem(Core, S.Life)
	Effects.Hit(nil, { Position = Position, Colour = S.Colour })
	ShakeIfNear(Position, S.ShakeIntensity, S.ShakeDuration, S.ShakeRange)

	-- Rocket jump for the player who fired it.
	local LocalPlayer = Players.LocalPlayer
	if S.LaunchSpeed > 0 and LocalPlayer and Data.LaunchOwner == LocalPlayer.UserId then
		local Root = RootOf(LocalCharacter())
		if Root then
			local Offset = Root.Position - Position
			local Distance = Offset.Magnitude
			if Distance <= Radius then
				local Flat = Vector3.new(Offset.X, 0, Offset.Z)
				local Away = Flat.Magnitude > 0.1 and Flat.Unit or Vector3.zero
				local Direction = (Away + Vector3.new(0, 1 + S.LaunchUp, 0)).Unit
				local Scale = 1 - 0.5 * (Distance / Radius)
				local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
				HelperFunctions.velocity(Root, Direction * S.LaunchSpeed * Scale, S.LaunchTime)
			end
		end
	end
end

-- The server moving a player (room pull forward, kill plane). The
-- client owns its character's physics, so it moves itself too.
-- Data: CFrame.
Effects.PlaceAt = function(Character, Data)
	local LocalPlayer = Players.LocalPlayer
	local Root = LocalPlayer and RootOf(LocalPlayer.Character)
	if not Root or not Data or typeof(Data.CFrame) ~= "CFrame" then
		return
	end
	local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
	HelperFunctions.clearVelocity(Root)
	Root.CFrame = Data.CFrame
end

-- The player's own client applies knockback, since it owns the
-- physics of its character. Data: Velocity.
Effects.Knockback = function(Character, Data)
	local LocalPlayer = Players.LocalPlayer
	if not LocalPlayer or not Data or not Data.Velocity then
		return
	end
	local Root = RootOf(LocalPlayer.Character)
	if not Root then
		return
	end
	local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
	HelperFunctions.velocity(Root, Data.Velocity, Data.Time or CombatFX.Settings.KnockbackTime)
end

----------------------------------------------------------------------
-- ENEMIES
----------------------------------------------------------------------

-- The tell before an enemy attack. Data: Duration, Kind ("Melee",
-- "Ranged", "Slam", "Summon").
Effects.Enemy_WindUp = function(Character, Data)
	if not Character then
		return
	end
	local S = CombatFX.Settings.EnemyWindUp
	local Duration = Data and Data.Duration or 0.4
	local Kind = Data and Data.Kind or "Melee"
	local Colour = (Kind == "Ranged" and S.RangedColour) or (Kind == "Summon" and S.SummonColour) or S.Colour

	local Glow = Instance.new("Highlight")
	Glow.FillColor = Colour
	Glow.OutlineColor = Colour
	Glow.FillTransparency = 1
	Glow.OutlineTransparency = 0.2
	Glow.DepthMode = Enum.HighlightDepthMode.Occluded
	Glow.Parent = Character
	Tween(Glow, Duration, { FillTransparency = S.FillTransparency }, Enum.EasingStyle.Linear)
	Debris:AddItem(Glow, Duration + 0.1)

	local Right = Joint(Character, "Right Shoulder")
	local Left = Joint(Character, "Left Shoulder")
	if Kind == "Slam" or Kind == "Summon" or Kind == "Rain" or Kind == "Shockwave" then
		Pose(Right, ArmForward(S.ArmRaise), Duration * 0.8)
		Pose(Left, ArmForward(-S.ArmRaise), Duration * 0.8)
	elseif Kind == "Ranged" then
		Pose(Right, ArmForward(-40), Duration * 0.8)
	else
		Pose(Right, ArmForward(S.ArmRaise), Duration * 0.8)
	end
end

-- The enemy attack landing. Data: Kind.
Effects.Enemy_Swing = function(Character, Data)
	if not Character then
		return
	end
	local S = CombatFX.Settings.EnemySwing
	local Kind = Data and Data.Kind or "Melee"
	local Right = Joint(Character, "Right Shoulder")
	local Left = Joint(Character, "Left Shoulder")

	if Kind == "Charge" then
		-- Arms back and a red streak behind it for the whole dash.
		Pose(Right, ArmForward(-60), 0.08)
		Pose(Left, ArmForward(60), 0.08)
		local Torso = Character:FindFirstChild("Torso")
		local Life = (Data and Data.Duration or 0.4) + 0.3
		if Torso then
			local A0 = Instance.new("Attachment")
			A0.Position = Vector3.new(0, 1, 0)
			A0.Parent = Torso
			local A1 = Instance.new("Attachment")
			A1.Position = Vector3.new(0, -1, 0)
			A1.Parent = Torso
			local Streak = Instance.new("Trail")
			Streak.Attachment0 = A0
			Streak.Attachment1 = A1
			Streak.Color = ColorSequence.new(Color3.fromRGB(255, 70, 70))
			Streak.Transparency = NumberSequence.new(0.3, 1)
			Streak.Lifetime = 0.25
			Streak.LightEmission = 1
			Streak.Parent = Torso
			Debris:AddItem(Streak, Life)
			Debris:AddItem(A0, Life)
			Debris:AddItem(A1, Life)
		end
		task.delay(Life - 0.3, function()
			Pose(Right, CFrame.new(), S.ReturnTime)
			Pose(Left, CFrame.new(), S.ReturnTime)
		end)
		return
	elseif Kind == "Slam" or Kind == "Summon" then
		Pose(Right, ArmForward(-10), S.SwingTime, Enum.EasingStyle.Back)
		Pose(Left, ArmForward(10), S.SwingTime, Enum.EasingStyle.Back)
	elseif Kind == "Ranged" then
		Pose(Right, ArmForward(130), S.SwingTime, Enum.EasingStyle.Back)
	else
		Pose(Right, ArmForward(20), S.SwingTime, Enum.EasingStyle.Back)
		local Root = RootOf(Character)
		if Root then
			local Scale = Data and Data.Scale or 1
			local Arc = Part({
				Size = S.ArcSize * Vector3.new(Scale, 1, Scale),
				Color = S.ArcColour,
				Transparency = 0.3,
				CFrame = Root.CFrame * CFrame.new(0, 0.5, -3.5 * Scale) * CFrame.Angles(0, 0, math.rad(35)),
				Parent = EffectsFolder(),
			})
			Tween(Arc, 0.18, { Transparency = 1, CFrame = Arc.CFrame * CFrame.Angles(0, 0, math.rad(-70)) })
			Debris:AddItem(Arc, 0.18)
		end
	end
	task.delay(S.SwingTime + 0.05, function()
		Pose(Right, CFrame.new(), S.ReturnTime)
		Pose(Left, CFrame.new(), S.ReturnTime)
	end)
end

-- A red circle on the floor that fills in over Duration, then the
-- attack lands. Data: Position, Radius, Duration.
Effects.Telegraph_Circle = function(Character, Data)
	if not Data or not Data.Position then
		return
	end
	local S = CombatFX.Settings.Telegraph
	local Radius = Data.Radius or 10
	local Duration = Data.Duration or 0.8
	local Folder = EffectsFolder()
	local At = CFrame.new(Data.Position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))

	local Outline = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(S.Thickness, Radius * 2, Radius * 2),
		Color = S.Colour,
		Transparency = S.Transparency + 0.25,
		CFrame = At,
		Parent = Folder,
	})
	local Fill = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(S.Thickness + 0.05, 0.5, 0.5),
		Color = S.Colour,
		Transparency = S.Transparency,
		CFrame = At,
		Parent = Folder,
	})
	Tween(Fill, Duration, { Size = Vector3.new(S.Thickness + 0.05, Radius * 2, Radius * 2) }, Enum.EasingStyle.Linear)
	Debris:AddItem(Outline, Duration + 0.05)
	Debris:AddItem(Fill, Duration + 0.05)
end

----------------------------------------------------------------------
-- PROJECTILES
----------------------------------------------------------------------

-- Live projectile visuals by the server's id: { Part, Origin,
-- Velocity, Gravity, Born, DiesAt }.
local LiveProjectiles: { [number]: any } = {}
local ProjectileConnection: RBXScriptConnection? = nil

local function EndProjectile(Id: number, Position: Vector3?)
	local Entry = LiveProjectiles[Id]
	if not Entry then
		return
	end
	LiveProjectiles[Id] = nil
	local P = Entry.Part
	if Position then
		P.Position = Position
	end
	-- Leave the trail a moment to fade rather than cutting it off.
	P.Transparency = 1
	for _, Child in ipairs(P:GetChildren()) do
		if Child:IsA("PointLight") then
			Child:Destroy()
		elseif Child:IsA("Trail") then
			Child.Enabled = false
		end
	end
	Debris:AddItem(P, 0.5)
end

-- Turns a velocity towards a point by at most TurnRate radians a
-- second, the same maths as the server's ProjectileService.
local function Steer(Velocity: Vector3, Position: Vector3, TargetPosition: Vector3, TurnRate: number, DeltaTime: number): Vector3
	local Speed = Velocity.Magnitude
	local Wanted = TargetPosition - Position
	if Speed < 0.01 or Wanted.Magnitude < 0.01 then
		return Velocity
	end
	local Current = Velocity.Unit
	Wanted = Wanted.Unit
	local Angle = math.acos(math.clamp(Current:Dot(Wanted), -1, 1))
	local MaxTurn = TurnRate * DeltaTime
	if Angle <= MaxTurn then
		return Wanted * Speed
	end
	local Axis = Current:Cross(Wanted)
	if Axis.Magnitude < 1e-4 then
		return Velocity
	end
	return (CFrame.fromAxisAngle(Axis.Unit, MaxTurn) * Current) * Speed
end

local LastStep = os.clock()
local function StepProjectiles()
	local Now = os.clock()
	local DeltaTime = math.min(Now - LastStep, 0.1)
	LastStep = Now
	for Id, Entry in pairs(LiveProjectiles) do
		if Now >= Entry.DiesAt or not Entry.Part.Parent then
			EndProjectile(Id, nil)
		elseif Entry.Homing then
			-- A homing one is stepped frame by frame, since its path is
			-- not a simple curve.
			local Homing = Entry.Homing
			local Target = Homing.Target
			if Now - Entry.Born < (Homing.Duration or 3) and typeof(Target) == "Instance" then
				local Root = Target:IsA("Model") and (Target:FindFirstChild("HumanoidRootPart") or Target.PrimaryPart) or Target
				if Root and Root:IsA("BasePart") and Root.Parent then
					Entry.Velocity = Steer(Entry.Velocity, Entry.Position, Root.Position, Homing.TurnRate or 2, DeltaTime)
				end
			end
			Entry.Position += Entry.Velocity * DeltaTime
			Entry.Part.CFrame = CFrame.lookAt(Entry.Position, Entry.Position + Entry.Velocity)
		else
			local T = Now - Entry.Born
			local Gravity = Vector3.new(0, -Entry.Gravity, 0)
			local Position = Entry.Origin + Entry.Velocity * T + 0.5 * Gravity * T * T
			local Velocity = Entry.Velocity + Gravity * T
			if Velocity.Magnitude > 0.01 then
				Entry.Part.CFrame = CFrame.lookAt(Position, Position + Velocity) * (Entry.Spin and CFrame.Angles(T * Entry.Spin, 0, 0) or CFrame.identity)
			else
				Entry.Part.Position = Position
			end
		end
	end
	if next(LiveProjectiles) == nil and ProjectileConnection then
		ProjectileConnection:Disconnect()
		ProjectileConnection = nil
	end
end

-- Data: Id, Origin, Velocity, Gravity, Lifetime, Visual.
Effects.Projectile = function(Character, Data)
	if not Data or not Data.Id or not Data.Origin or not Data.Velocity then
		return
	end
	local Visuals = CombatFX.Settings.ProjectileVisuals
	local Look = Visuals[Data.Visual or ""] or Visuals.Bullet
	local Size = typeof(Look.Size) == "Vector3" and Look.Size or Vector3.one * Look.Size
	local P = Part({
		Shape = Look.Shape == "Ball" and Enum.PartType.Ball or Enum.PartType.Block,
		Size = Size,
		Color = Look.Colour,
		Material = Look.Material or Enum.Material.Neon,
		Transparency = Look.Transparency or 0,
		CFrame = CFrame.lookAt(Data.Origin, Data.Origin + Data.Velocity),
	})
	if Look.Light and Look.Light > 0 then
		local Light = Instance.new("PointLight")
		Light.Color = Look.Colour
		Light.Range = Look.Light
		Light.Brightness = 2
		Light.Parent = P
	end
	if Look.Fire then
		local Flame = Instance.new("Fire")
		Flame.Size = Look.Fire
		Flame.Heat = 3
		Flame.Parent = P
	end
	-- A brighter core inside, welded so it follows.
	if Look.Core then
		local Core = Part({
			Size = Look.Core.Size,
			Color = Look.Core.Colour,
			CFrame = P.CFrame,
		})
		Core.Anchored = false
		Core.Massless = true
		local Weld = Instance.new("WeldConstraint")
		Weld.Part0 = P
		Weld.Part1 = Core
		Weld.Parent = Core
		Core.Parent = P
	end
	if Look.Trail then
		local T = Look.Trail
		-- The trail's width runs up and down by default, or side to
		-- side with Axis "X".
		local Across = T.Axis == "X" and Vector3.new(T.Width / 2, 0, 0) or Vector3.new(0, T.Width / 2, 0)
		local A0 = Instance.new("Attachment")
		A0.Position = Across
		A0.Parent = P
		local A1 = Instance.new("Attachment")
		A1.Position = -Across
		A1.Parent = P
		local Trail = Instance.new("Trail")
		Trail.Attachment0 = A0
		Trail.Attachment1 = A1
		Trail.Color = ColorSequence.new(T.Colour)
		Trail.Lifetime = T.Life
		Trail.FaceCamera = true
		Trail.LightEmission = 1
		Trail.Transparency = NumberSequence.new(T.Transparency or 0, 1)
		Trail.WidthScale = NumberSequence.new(1, 0.2)
		Trail.Parent = P
	end
	P.Parent = EffectsFolder()

	LiveProjectiles[Data.Id] = {
		Part = P,
		Origin = Data.Origin,
		Position = Data.Origin,
		Velocity = Data.Velocity,
		Gravity = Data.Gravity or 0,
		Homing = type(Data.Homing) == "table" and Data.Homing or nil,
		Spin = Look.Spin,
		Born = os.clock(),
		DiesAt = os.clock() + (Data.Lifetime or 3) + 0.2,
	}
	if not ProjectileConnection then
		ProjectileConnection = RunService.RenderStepped:Connect(StepProjectiles)
	end
end

-- A projectile the Sword knocked back: new path and the parry colour.
-- Data: Id, Origin, Velocity, Gravity, Lifetime.
Effects.ProjectileRedirect = function(Character, Data)
	local Entry = Data and Data.Id and LiveProjectiles[Data.Id]
	if not Entry or typeof(Data.Origin) ~= "Vector3" or typeof(Data.Velocity) ~= "Vector3" then
		return
	end
	-- A homing orb's regular correction only moves it.
	if Data.KeepColour then
		Entry.Position = Data.Origin
		Entry.Velocity = Data.Velocity
		return
	end
	local Colour = CombatFX.Settings.DeflectedColour
	Entry.Origin = Data.Origin
	Entry.Position = Data.Origin
	Entry.Velocity = Data.Velocity
	Entry.Gravity = Data.Gravity or 0
	Entry.Homing = nil
	Entry.Born = os.clock()
	Entry.DiesAt = os.clock() + (Data.Lifetime or 2) + 0.2
	Entry.Part.Color = Colour
	Entry.Part.Material = Enum.Material.Neon
	for _, Child in ipairs(Entry.Part:GetChildren()) do
		if Child:IsA("Trail") then
			Child.Color = ColorSequence.new(Colour)
		elseif Child:IsA("PointLight") then
			Child.Color = Colour
		end
	end
end

Effects.ProjectileEnd = function(Character, Data)
	if Data and Data.Id then
		EndProjectile(Data.Id, Data.Position)
	end
end

----------------------------------------------------------------------
-- ABILITIES
----------------------------------------------------------------------

-- A green ring and sparkles going out from the healer. Data: Position,
-- Radius.
Effects.HealBurst = function(Character, Data)
	local Root = RootOf(Character)
	local Position = Data and Data.Position or (Root and Root.Position)
	if not Position then
		return
	end
	local Radius = Data and Data.Radius or 20
	local Colour = Color3.fromRGB(90, 255, 140)
	local Ring = Part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 2, 2),
		Color = Colour,
		Transparency = 0.2,
		CFrame = CFrame.new(Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Parent = EffectsFolder(),
	})
	Tween(Ring, 0.5, { Size = Vector3.new(0.3, Radius * 2, Radius * 2), Transparency = 1 })
	Debris:AddItem(Ring, 0.5)
	Effects.Hit(nil, { Position = Position, Colour = Colour })
	if Character then
		local Glow = Instance.new("Highlight")
		Glow.FillColor = Colour
		Glow.OutlineColor = Colour
		Glow.FillTransparency = 0.4
		Glow.Parent = Character
		Tween(Glow, 0.6, { FillTransparency = 1, OutlineTransparency = 1 })
		Debris:AddItem(Glow, 0.6)
	end
end

-- A red flash and shake when Rage goes on.
Effects.Rage = function(Character, Data)
	local Root = RootOf(Character)
	if not Root then
		return
	end
	local Colour = Color3.fromRGB(255, 50, 40)
	local Burst = Part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2, 2, 2),
		Color = Colour,
		Transparency = 0.3,
		Position = Root.Position,
		Parent = EffectsFolder(),
	})
	Tween(Burst, 0.35, { Size = Vector3.new(14, 14, 14), Transparency = 1 })
	Debris:AddItem(Burst, 0.35)
	Pose(Joint(Character, "Right Shoulder"), ArmForward(40), 0.1)
	Pose(Joint(Character, "Left Shoulder"), ArmForward(-40), 0.1)
	task.delay(0.3, function()
		Pose(Joint(Character, "Right Shoulder"), CFrame.new(), 0.2)
		Pose(Joint(Character, "Left Shoulder"), CFrame.new(), 0.2)
	end)
	ShakeIfNear(Root.Position, 0.5, 0.25, 20)
end

-- Purple pillars where summons appear. Data: Positions.
Effects.Enemy_Summon = function(Character, Data)
	local S = CombatFX.Settings.Summon
	for _, Position in ipairs(Data and Data.Positions or {}) do
		local Pillar = Part({
			Size = Vector3.new(3, S.PillarHeight, 3),
			Color = Data and Data.Colour or S.Colour,
			Transparency = 0.3,
			CFrame = CFrame.new(Position + Vector3.new(0, S.PillarHeight / 2 - 3, 0)),
			Parent = EffectsFolder(),
		})
		Tween(Pillar, S.Life, { Transparency = 1, Size = Vector3.new(0.2, S.PillarHeight * 1.5, 0.2) })
		Debris:AddItem(Pillar, S.Life)
	end
end

----------------------------------------------------------------------
-- FEEDBACK
----------------------------------------------------------------------

-- Plays a sound by name. Data: Name, Position, Volume, Pitch. With a
-- Character it plays from them, otherwise at Position, otherwise flat.
Effects.PlaySound = function(Character, Data)
	if not Data or not Data.Name then
		return
	end
	PlaySound(Data.Name, Character or Data.Position, Data.Volume, Data.Pitch)
end

-- The number over something the local player hit, and the hit sound.
-- Data: Target, Position, Amount, Kind ("Hit", "Crit", "Kill",
-- "Heal"), Sound.
local LiveNumbers: { [Instance]: any } = {}

Effects.DamageNumber = function(Character, Data)
	if not Data then
		return
	end
	local S = CombatFX.Settings.DamageNumber
	if Data.Sound then
		PlaySound(Data.Sound, nil, S.SoundVolume)
	end
	local Amount = Data.Amount or 0
	if Amount <= 0 or typeof(Data.Position) ~= "Vector3" then
		return
	end
	local Kind = Data.Kind or "Hit"
	local Colour = (Kind == "Crit" and S.CritColour) or (Kind == "Kill" and S.KillColour) or (Kind == "Heal" and S.HealColour)
		or (Kind == "Swap" and S.SwapColour) or S.HitColour

	-- Hits on the same target close together add onto one number.
	local Key = Data.Target
	local Existing = Key and LiveNumbers[Key]
	if Existing and Kind ~= "Heal" and os.clock() - Existing.At < S.MergeTime and Existing.Label.Parent then
		Existing.Total += Amount
		Existing.At = os.clock()
		Existing.Crit = Existing.Crit or Kind == "Crit"
		Existing.Label.Text = tostring(math.floor(Existing.Total + 0.5)) .. (Existing.Crit and "!" or "")
		if Kind ~= "Hit" then
			Existing.Label.TextColor3 = Colour
		end
		return
	end

	local Folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI")
	local Template = Folder and Folder:FindFirstChild(S.Template)
	if not Template then
		return
	end
	local Anchor = Part({
		Size = Vector3.new(0.1, 0.1, 0.1),
		Transparency = 1,
		Position = Data.Position + Vector3.new(math.random() * 2 - 1, 2 + math.random(), math.random() * 2 - 1),
		Parent = EffectsFolder(),
	})
	local Gui = Template:Clone()
	Gui.Adornee = Anchor
	Gui.Parent = Anchor
	local Label = Gui:FindFirstChildWhichIsA("TextLabel", true)
	if not Label then
		Anchor:Destroy()
		return
	end
	Label.TextColor3 = Colour
	Label.Text = (Kind == "Heal" and "+" or "") .. tostring(math.floor(Amount + 0.5)) .. (Kind == "Crit" and "!" or "")
	local BaseSize = Label.TextSize
	local Big = Kind == "Crit" or Kind == "Kill"
	Label.TextSize = math.floor(BaseSize * (Big and S.PopScale * 1.3 or S.PopScale))
	Tween(Label, 0.12, { TextSize = math.floor(BaseSize * (Big and 1.25 or 1)) }, Enum.EasingStyle.Back)
	Tween(Anchor, S.Life, { Position = Anchor.Position + Vector3.new(0, S.RiseStuds, 0) })
	task.delay(S.Life * 0.5, function()
		if Label.Parent then
			Tween(Label, S.Life * 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end)
	Debris:AddItem(Anchor, S.Life + 0.05)
	if Key then
		LiveNumbers[Key] = { Label = Label, Total = Amount, At = os.clock(), Crit = Kind == "Crit" }
		task.delay(S.Life + 0.1, function()
			if LiveNumbers[Key] and LiveNumbers[Key].Label == Label then
				LiveNumbers[Key] = nil
			end
		end)
	end
end

-- The arrow on screen pointing at whatever hurt the local player. The
-- drawing is HUDEffects', this only plays the sound and hands it over.
Effects.DamageIndicator = function(Character, Data)
	PlaySound("PlayerHurt", nil, 0.8)
	local Handler = Handlers.DamageIndicator
	if Handler then
		Handler(Character, Data)
	end
end

----------------------------------------------------------------------
-- ENEMY DEATHS AND TELLS
----------------------------------------------------------------------

-- An enemy dying: a white flash, then it breaks into bits of its
-- colour and fades. Data: Colour, Sound.
Effects.EnemyDeath = function(Character, Data)
	if not Character then
		return
	end
	local S = CombatFX.Settings.EnemyDeath
	local Colour = Data and Data.Colour or Color3.fromRGB(255, 255, 255)
	local Root = RootOf(Character)
	PlaySound(Data and Data.Sound, Root or Character)

	local Glow = Instance.new("Highlight")
	Glow.FillColor = Color3.new(1, 1, 1)
	Glow.OutlineColor = Colour
	Glow.FillTransparency = 0
	Glow.OutlineTransparency = 0
	Glow.DepthMode = Enum.HighlightDepthMode.Occluded
	Glow.Parent = Character
	task.delay(S.FlashTime, function()
		if Glow.Parent then
			Glow.FillColor = Colour
			Tween(Glow, S.DissolveDelay + S.DissolveTime, { FillTransparency = 0.6, OutlineTransparency = 1 })
		end
	end)

	task.delay(S.DissolveDelay, function()
		if not Character.Parent then
			return
		end
		for _, Item in ipairs(Character:GetDescendants()) do
			if Item:IsA("BasePart") and Item.Transparency < 1 then
				Tween(Item, S.DissolveTime, { Transparency = 1 })
			elseif Item:IsA("Decal") then
				Tween(Item, S.DissolveTime, { Transparency = 1 })
			elseif Item:IsA("BillboardGui") then
				Item.Enabled = false
			elseif Item:IsA("ParticleEmitter") or Item:IsA("PointLight") or Item:IsA("Fire") then
				Item.Enabled = false
			end
		end
		local Centre = Root and Root.Parent and Root.Position or Character:GetPivot().Position
		local Folder = EffectsFolder()
		for _ = 1, S.Bits do
			local Size = S.BitSize * (0.6 + math.random() * 0.8)
			local Bit = Part({
				Size = Vector3.one * Size,
				Color = Colour,
				Transparency = 0.1,
				CFrame = CFrame.new(Centre + Vector3.new(math.random() * 2 - 1, math.random() * 3 - 1, math.random() * 2 - 1))
					* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
				Parent = Folder,
			})
			local Out = Vector3.new(math.random() * 2 - 1, math.random() * 1.5, math.random() * 2 - 1)
			Tween(Bit, 0.5, {
				CFrame = Bit.CFrame + Out * S.BitSpeed * 0.25,
				Transparency = 1,
				Size = Vector3.one * 0.05,
			})
			Debris:AddItem(Bit, 0.5)
		end
	end)
end

-- A red line on the floor where a charge will go, sent again during
-- the wind up as it turns. Data: Id, From, Direction, Length, Width,
-- Duration, Remove.
local Lines: { [string]: any } = {}

Effects.Telegraph_Line = function(Character, Data)
	if not Data or not Data.Id then
		return
	end
	local Existing = Lines[Data.Id]
	if Data.Remove then
		if Existing then
			Existing.Outline:Destroy()
			Existing.Fill:Destroy()
			Lines[Data.Id] = nil
		end
		return
	end
	if typeof(Data.From) ~= "Vector3" or typeof(Data.Direction) ~= "Vector3" then
		return
	end
	local S = CombatFX.Settings.TelegraphLine
	local Length = Data.Length or 30
	local Width = Data.Width or 5
	local Flat = Vector3.new(Data.Direction.X, 0, Data.Direction.Z)
	if Flat.Magnitude < 0.01 then
		return
	end
	Flat = Flat.Unit
	local Start = Data.From + Vector3.new(0, 0.12, 0)
	local Look = CFrame.lookAt(Start, Start + Flat)
	if not Existing then
		local Duration = math.max(Data.Duration or 0.5, 0.05)
		Existing = {
			Outline = Part({
				Size = Vector3.new(Width, S.Thickness, Length),
				Color = S.Colour,
				Transparency = S.Transparency + 0.25,
				Parent = EffectsFolder(),
			}),
			Fill = Part({
				Size = Vector3.new(Width * 0.8, S.Thickness + 0.02, 0.5),
				Color = S.Colour,
				Transparency = S.Transparency,
				Parent = EffectsFolder(),
			}),
			Ends = os.clock() + Duration,
			Total = Duration,
		}
		Lines[Data.Id] = Existing
		local Id = Data.Id
		local Entry = Existing
		task.delay(Duration + 0.6, function()
			if Lines[Id] == Entry then
				Entry.Outline:Destroy()
				Entry.Fill:Destroy()
				Lines[Id] = nil
			end
		end)
	end
	-- How far along the fill is, from the time left.
	local Progress = 1 - math.clamp((Existing.Ends - os.clock()) / Existing.Total, 0, 1)
	local FillLength = math.max(0.5, Length * Progress)
	Existing.Outline.CFrame = Look * CFrame.new(0, 0, -Length / 2)
	Existing.Fill.Size = Vector3.new(Width * 0.8, S.Thickness + 0.02, FillLength)
	Existing.Fill.CFrame = Look * CFrame.new(0, 0, -FillLength / 2)
end

-- A Bomber's lit fuse: it flashes faster and faster, beeps, and shows
-- the blast radius. Data: Duration, Radius.
Effects.Bomber_Fuse = function(Character, Data)
	if not Character then
		return
	end
	local S = CombatFX.Settings.BomberFuse
	local Duration = Data and Data.Duration or 0.7
	local Radius = Data and Data.Radius or 12
	local Root = RootOf(Character)

	local Glow = Instance.new("Highlight")
	Glow.FillColor = S.FlashColour
	Glow.OutlineColor = S.FlashColour
	Glow.FillTransparency = 1
	Glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	Glow.Parent = Character
	Debris:AddItem(Glow, Duration + 0.2)

	local Sphere = nil
	if Root then
		Sphere = Part({
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * Radius * 2,
			Color = S.RadiusColour,
			Transparency = 1,
			Material = Enum.Material.ForceField,
			CFrame = Root.CFrame,
			Parent = EffectsFolder(),
		})
		Tween(Sphere, Duration, { Transparency = S.RadiusTransparency - 0.4 }, Enum.EasingStyle.Linear)
		Debris:AddItem(Sphere, Duration + 0.1)
	end

	task.spawn(function()
		local Start = os.clock()
		local On = false
		local NextBeep = 0
		local Beeps = 0
		while os.clock() - Start < Duration and Character.Parent do
			local T = (os.clock() - Start) / Duration
			On = not On
			Glow.FillTransparency = On and 0.1 or 0.8
			if Sphere and Root and Root.Parent then
				Sphere.CFrame = Root.CFrame
			end
			if os.clock() >= NextBeep and Beeps < S.Beeps then
				Beeps += 1
				PlaySound("FuseBeep", Root, 1, 1 + T * 0.6)
				NextBeep = os.clock() + Duration / S.Beeps * (1 - T * 0.5)
			end
			task.wait(math.max(0.03, 0.12 * (1 - T)))
		end
	end)
end

-- The boss losing its temper: a red outline and fire for the rest of
-- the fight, and a big shake. Data: Colour.
Effects.BossEnrage = function(Character, Data)
	if not Character then
		return
	end
	local Colour = Data and Data.Colour or Color3.fromRGB(255, 40, 40)
	local Glow = Instance.new("Highlight")
	Glow.Name = "EnrageGlow"
	Glow.FillColor = Colour
	Glow.OutlineColor = Colour
	Glow.FillTransparency = 0.75
	Glow.OutlineTransparency = 0.1
	Glow.DepthMode = Enum.HighlightDepthMode.Occluded
	Glow.Parent = Character
	for _, Name in ipairs({ "Left Arm", "Right Arm", "Head" }) do
		local Limb = Character:FindFirstChild(Name)
		if Limb then
			local Fire = Instance.new("Fire")
			Fire.Color = Colour
			Fire.SecondaryColor = Color3.fromRGB(255, 160, 40)
			Fire.Size = 4
			Fire.Heat = 8
			Fire.Parent = Limb
		end
	end
	local Root = RootOf(Character)
	if Root then
		ShakeIfNear(Root.Position, 1.4, 0.6, 200)
	end
end

----------------------------------------------------------------------
-- PLAY
----------------------------------------------------------------------

-- Renders an effect by name on the client. Unknown names are ignored
-- with a one time warning so a typo shows up in the output.
local WarnedNames: { [string]: boolean } = {}

function CombatFX.Play(Name: string, Character: Model?, Data: { [string]: any }?)
	local Effect = Effects[Name] or Handlers[Name]
	if not Effect then
		if not WarnedNames[Name] then
			WarnedNames[Name] = true
			warn("[CombatFX] no effect called " .. tostring(Name))
		end
		return
	end
	-- The sound the server named, or this effect's default.
	local Settings = CombatFX.Settings
	if not Settings.OwnSound[Name] then
		local SoundName = (Data and Data.Sound) or Settings.DefaultSounds[Name]
		if SoundName then
			local At = Character and RootOf(Character) or (Data and Data.Position)
			PlaySound(SoundName, At)
		end
	end

	local Ok, Error = pcall(Effect, Character, Data)
	if not Ok then
		warn("[CombatFX] " .. Name .. " failed: " .. tostring(Error))
	end
end

function CombatFX.Has(Name: string): boolean
	return Effects[Name] ~= nil or Handlers[Name] ~= nil
end

return CombatFX
