--[[
	HUDEffects

	The feel of the HUD, the part that makes it move and react:

	  Speed FOV     the faster the player moves, the wider the camera's
	                field of view, on top of whatever the movement
	                framework is doing with it (the run and glide boosts).
	  FOV motion    the HUD panels push out toward the screen edges and
	                grow a little as the field of view widens, and come
	                back in as it narrows, so the interface moves forward
	                and back with the camera.
	  Hit marker    a quick cross at the cursor when a hit lands, bigger
	                and red on a kill.
	  Hurt flash    the screen edges flash red when the player takes
	                damage.

	The pieces are designed in the editor, this only moves, scales and
	flashes them. None of it affects the game.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.HitConfirmed from
	  Server.Game.Combat.DamageService, with Killed.
	  ReplicatedStorage.Remotes.Events.StatsUpdated for health, to know
	  when damage was taken.

	Drives:
	  StarterGui.Feedback > Hurt > Top, Bottom, Left, Right
	  StarterGui.Feedback > HitMarker
	Moves (only offsets and scales them from how they were designed):
	  The top level frames of the ScreenGuis in Settings.Fov.Guis. Each
	  has a UIScale called FovScale, made in the editor, which this sets.

	Camera field of view:
	  The movement modules (Run, Spin, Zipline) tween
	  Camera.FieldOfView themselves. This never fights them: it watches
	  for any change it did not make, takes that as the movement
	  framework's value, and renders that plus the speed bonus. The
	  movement code only ever sees its own value, so the bonus cannot
	  build up.

	Started by:
	  ClientGame.ClientMain, last, so every panel it moves already
	  exists.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local Player = Players.LocalPlayer

local HUDEffects = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

HUDEffects.Settings = {
	-- Hit marker. The designed marker is scaled by these.
	HitMarkerLife = 0.15,
	KillMarkerScale = 1.4,
	KillMarkerColour = Color3.fromRGB(255, 60, 60),
	HitMarkerColour = Color3.fromRGB(255, 255, 255),
	CritMarkerColour = Color3.fromRGB(255, 205, 50),

	-- The arrows round the middle of the screen pointing at whatever
	-- just hurt the player. The look is Feedback.Indicators.ArrowTemplate.
	Arrow = {
		-- Pixels from the screen centre.
		Radius = 150,
		Life = 0.9,
		-- Most arrows on screen at once, the oldest goes first.
		Max = 6,
	},

	-- Below this fraction of health the screen edges pulse red.
	LowHealthPercent = 0.25,
	LowHealthPulseRate = 1.2,
	LowHealthPeak = 0.55,

	-- Hurt flash. Transparency at the peak, and how long it fades.
	HurtPeak = 0.55,
	HurtFade = 0.35,

	-- Field of view.
	Fov = {
		Enabled = true,
		-- The field of view the HUD is designed at. Wider than this
		-- pushes the HUD out, narrower pulls it back in.
		Base = 70,
		-- Extra degrees of FOV from horizontal speed: nothing below
		-- SpeedStartSpeed, then SpeedPerStud per stud per second above
		-- it, up to SpeedMax.
		SpeedStartSpeed = 20,
		SpeedPerStud = 0.35,
		SpeedMax = 20,
		-- How quickly the speed FOV follows the speed. Higher is
		-- snappier.
		SpeedSmoothing = 6,
		-- How much the HUD moves with the FOV. Push is the fraction of
		-- each panel's distance from the screen centre it moves out per
		-- 1.0 of (FOV - Base) / Base. Scale is how much it grows for the
		-- same. 0 turns that part off, negative moves the other way.
		Push = 0.18,
		Scale = 0.12,
		-- ScreenGuis whose top level frames move with the FOV.
		Guis = { "HUD", "Hotbar", "ShopUI", "BossBar" },
	},
}

local HurtEdges: { GuiObject } = {}
local Marker: GuiObject? = nil
local MarkerSize = UDim2.fromOffset(36, 36)
local LastHealth: number? = nil

----------------------------------------------------------------------
-- HIT MARKER AND HURT FLASH
----------------------------------------------------------------------

local function ShowHit(Killed: boolean, Crit: boolean?)
	if not Marker then
		return
	end
	local Settings = HUDEffects.Settings
	local Mouse = UserInputService:GetMouseLocation()
	local Scale = (Killed or Crit) and Settings.KillMarkerScale or 1
	Marker.Position = UDim2.fromOffset(Mouse.X, Mouse.Y)
	Marker.Size = UDim2.new(MarkerSize.X.Scale * Scale, MarkerSize.X.Offset * Scale, MarkerSize.Y.Scale * Scale, MarkerSize.Y.Offset * Scale)
	for _, Bar in ipairs(Marker:GetChildren()) do
		if Bar:IsA("GuiObject") then
			Bar.BackgroundColor3 = (Killed and Settings.KillMarkerColour) or (Crit and Settings.CritMarkerColour) or Settings.HitMarkerColour
		end
	end
	Marker.Visible = true
	local Token = os.clock()
	Marker:SetAttribute("Token", Token)
	task.delay(Killed and Settings.HitMarkerLife * 2 or Settings.HitMarkerLife, function()
		if Marker:GetAttribute("Token") == Token then
			Marker.Visible = false
		end
	end)
end

local function Hurt(Amount: number, Max: number)
	local Settings = HUDEffects.Settings
	local Peak = math.clamp(1 - (1 - Settings.HurtPeak) * math.clamp(Amount / (Max * 0.15), 0.4, 1), 0, 1)
	for _, Edge in ipairs(HurtEdges) do
		Edge.BackgroundTransparency = Peak
		TweenService:Create(Edge, TweenInfo.new(Settings.HurtFade), { BackgroundTransparency = 1 }):Play()
	end
	local Ok, CameraShake = pcall(require, ReplicatedStorage.Modules.Shared.CameraShake)
	if Ok and CameraShake and CameraShake.Shake then
		pcall(CameraShake.Shake, CameraShake, 0.25, 0.15)
	end
end

----------------------------------------------------------------------
-- DAMAGE ARROWS AND LOW HEALTH
----------------------------------------------------------------------

local ArrowFolder: GuiObject? = nil
local ArrowTemplate: GuiObject? = nil
-- Live arrows: { Frame, From, Born }.
local Arrows: { any } = {}
local LowHealth = false
local PulseTime = 0

-- Called by CombatFX's DamageIndicator with Data.From, the position
-- the hit came from.
local function ShowArrow(_, Data)
	if not ArrowFolder or not ArrowTemplate or not Data or typeof(Data.From) ~= "Vector3" then
		return
	end
	local Settings = HUDEffects.Settings.Arrow
	if #Arrows >= Settings.Max then
		local Oldest = table.remove(Arrows, 1)
		Oldest.Frame:Destroy()
	end
	local Frame = ArrowTemplate:Clone()
	Frame.Name = "Arrow"
	Frame.Visible = true
	Frame.Parent = ArrowFolder
	table.insert(Arrows, { Frame = Frame, From = Data.From, Born = os.clock(), Base = ArrowTemplate.BackgroundTransparency })
end

local function StepArrows(DeltaTime: number)
	local Camera = workspace.CurrentCamera
	if not Camera or not ArrowFolder then
		return
	end
	local Settings = HUDEffects.Settings
	local Middle = ArrowFolder.AbsoluteSize / 2
	for Index = #Arrows, 1, -1 do
		local Entry = Arrows[Index]
		local Age = os.clock() - Entry.Born
		if Age >= Settings.Arrow.Life or not Entry.Frame.Parent then
			Entry.Frame:Destroy()
			table.remove(Arrows, Index)
			continue
		end
		-- Which way the source is from where the camera faces, so the
		-- arrow keeps pointing at it as the player turns.
		local Relative = Camera.CFrame:VectorToObjectSpace(Entry.From - Camera.CFrame.Position)
		local Angle = math.atan2(Relative.X, -Relative.Z)
		local Radius = Settings.Arrow.Radius
		Entry.Frame.Position = UDim2.fromOffset(Middle.X + math.sin(Angle) * Radius, Middle.Y - math.cos(Angle) * Radius)
		Entry.Frame.Rotation = math.deg(Angle)
		local Fade = Age / Settings.Arrow.Life
		Entry.Frame.BackgroundTransparency = Entry.Base + (1 - Entry.Base) * Fade * Fade
	end

	-- The low health pulse on the screen edges.
	if LowHealth then
		PulseTime += DeltaTime
		local Wave = (math.sin(PulseTime * math.pi * 2 * Settings.LowHealthPulseRate) + 1) / 2
		local Transparency = 1 - (1 - Settings.LowHealthPeak) * Wave * 0.7
		for _, Edge in ipairs(HurtEdges) do
			if Edge.BackgroundTransparency > Transparency then
				Edge.BackgroundTransparency = Transparency
			end
		end
	end
end

----------------------------------------------------------------------
-- FIELD OF VIEW
----------------------------------------------------------------------

-- Panels that move with the FOV: { Object, Base, Scale, Centre }.
local FovTargets: { any } = {}
-- The FOV the movement framework last set, and the value this module
-- last wrote, so its own writes are not mistaken for theirs.
local MovementFov: number? = nil
local LastWritten: number? = nil
local SpeedBonus = 0

local function CollectFovTargets()
	FovTargets = {}
	local PlayerGui = Player:WaitForChild("PlayerGui")
	for _, Name in ipairs(HUDEffects.Settings.Fov.Guis) do
		local Target = PlayerGui:FindFirstChild(Name)
		if Target then
			for _, Child in ipairs(Target:GetChildren()) do
				if Child:IsA("GuiObject") then
					table.insert(FovTargets, {
						Object = Child,
						Base = Child.Position,
						Scale = Child:FindFirstChild("FovScale"),
					})
				end
			end
		end
	end
end

local function WatchCamera(Camera: Camera)
	MovementFov = Camera.FieldOfView
	LastWritten = nil
	Camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		local Value = Camera.FieldOfView
		if LastWritten and math.abs(Value - LastWritten) < 0.001 then
			return
		end
		MovementFov = Value
	end)
end

local function StepFov(DeltaTime: number)
	local Fov = HUDEffects.Settings.Fov
	local Camera = workspace.CurrentCamera
	if not Fov.Enabled or not Camera then
		return
	end

	-- Speed bonus, smoothed.
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	local Target = 0
	if Root then
		local Velocity = Root.AssemblyLinearVelocity
		local Speed = Vector3.new(Velocity.X, 0, Velocity.Z).Magnitude
		Target = math.clamp((Speed - Fov.SpeedStartSpeed) * Fov.SpeedPerStud, 0, Fov.SpeedMax)
	end
	SpeedBonus += (Target - SpeedBonus) * math.min(1, DeltaTime * Fov.SpeedSmoothing)

	local Value = math.clamp((MovementFov or Fov.Base) + SpeedBonus, 1, 120)
	LastWritten = Value
	Camera.FieldOfView = Value

	-- Move the HUD with it.
	local Amount = (Value - Fov.Base) / Fov.Base
	local Middle = Camera.ViewportSize / 2
	for _, Entry in ipairs(FovTargets) do
		local Object = Entry.Object
		if Object.Parent then
			if not Entry.Centre then
				-- Where it was designed to sit, measured once.
				Entry.Centre = Object.AbsolutePosition + Object.AbsoluteSize / 2
			end
			local Push = (Entry.Centre - Middle) * Amount * Fov.Push
			local Base = Entry.Base
			Object.Position = UDim2.new(Base.X.Scale, Base.X.Offset + Push.X, Base.Y.Scale, Base.Y.Offset + Push.Y)
			if Entry.Scale then
				Entry.Scale.Scale = 1 + Amount * Fov.Scale
			end
		end
	end
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function HUDEffects.Init()
	local PlayerGui = Player:WaitForChild("PlayerGui")
	local Gui = PlayerGui:WaitForChild("Feedback", 10)
	if Gui then
		local HurtFrame = Gui:FindFirstChild("Hurt")
		if HurtFrame then
			for _, Edge in ipairs(HurtFrame:GetChildren()) do
				if Edge:IsA("GuiObject") then
					Edge.BackgroundTransparency = 1
					table.insert(HurtEdges, Edge)
				end
			end
		end
		Marker = Gui:FindFirstChild("HitMarker")
		if Marker then
			MarkerSize = Marker.Size
			Marker.Visible = false
		end
		ArrowFolder = Gui:FindFirstChild("Indicators")
		ArrowTemplate = ArrowFolder and ArrowFolder:FindFirstChild("ArrowTemplate")
		if ArrowTemplate then
			ArrowTemplate.Visible = false
		end
	else
		warn("[HUDEffects] no Feedback ScreenGui in StarterGui")
	end

	-- Wait a moment for the other controllers before recording where
	-- everything was designed to sit.
	task.delay(1, CollectFovTargets)
	if workspace.CurrentCamera then
		WatchCamera(workspace.CurrentCamera)
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if workspace.CurrentCamera then
			WatchCamera(workspace.CurrentCamera)
		end
	end)
	-- A new window size moves the designed spots, so measure again.
	task.defer(function()
		local Camera = workspace.CurrentCamera
		if Camera then
			Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				for _, Entry in ipairs(FovTargets) do
					Entry.Object.Position = Entry.Base
					Entry.Centre = nil
				end
			end)
		end
	end)

	Events:WaitForChild("HitConfirmed").OnClientEvent:Connect(function(Killed, Crit)
		ShowHit(Killed == true, Crit == true)
	end)

	local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
	CombatFX.Register("DamageIndicator", ShowArrow)
	RunService.RenderStepped:Connect(StepArrows)

	Events:WaitForChild("StatsUpdated").OnClientEvent:Connect(function(Snapshot)
		if type(Snapshot) ~= "table" or type(Snapshot.Health) ~= "number" then
			return
		end
		if LastHealth and Snapshot.Health < LastHealth - 0.5 and Snapshot.IsAlive ~= false then
			Hurt(LastHealth - Snapshot.Health, Snapshot.MaxHealth or 100)
		end
		LastHealth = Snapshot.Health
		local Max = math.max(Snapshot.MaxHealth or 100, 1)
		LowHealth = Snapshot.IsAlive ~= false and Snapshot.Health / Max <= HUDEffects.Settings.LowHealthPercent
	end)

	-- Last before the frame is drawn, so the movement framework's FOV
	-- tweens for this frame have already run.
	RunService:BindToRenderStep("HUDEffectsFov", Enum.RenderPriority.Last.Value, StepFov)
end

return HUDEffects
