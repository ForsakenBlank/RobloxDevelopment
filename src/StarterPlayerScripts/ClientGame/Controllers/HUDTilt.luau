--[[
	HUDTilt

	Makes the main HUD panels look like they are facing into the screen.
	A ScreenGui is always flat, so the panels are moved onto SurfaceGuis
	on invisible parts that float just in front of the camera, and each
	part is turned a little so the panel angles in toward the middle of
	the screen. They are real 3D surfaces, so they have proper
	perspective.

	Each part is placed so the panel covers the same spot and size on
	screen as it was designed in StarterGui.HUD, at the design field of
	view. The parts are fixed in front of the camera, so when the field
	of view widens (running, gliding, the speed FOV in HUDEffects) the
	panels recede a little, and when it narrows they come forward again.
]]

--[[
	What connects to this

	Reads (all set up in the editor):
	  StarterGui.TiltStats, TiltCooldowns and TiltTop, SurfaceGuis whose
	  attributes say what they do:
	    Panel   the name of the frame in StarterGui.HUD it holds
	    Yaw     degrees it turns left or right. Positive turns the
	            panel's left edge toward the camera, so the left panel
	            faces into the screen. Negative for the right panel.
	    Pitch   degrees it tips. Positive brings the top edge toward the
	            camera
	    Depth   studs in front of the camera. Only changes how the
	            perspective looks, the size on screen stays the same
	    FovFollow  how much of a field of view change the panel follows.
	            1 recedes fully as the FOV widens, 0 keeps it the designed
	            size, 0.25 is a light hint that stays readable
	  Add another SurfaceGui with these attributes to tilt another panel.

	Moves:
	  The named panels out of StarterGui.HUD into their SurfaceGui, once,
	  at start. HUD.lua keeps its references to them, so it carries on
	  updating them exactly as before.

	Settings.DesignFov should match HUDEffects.Settings.Fov.Base, the
	field of view the HUD was designed at.

	Started by:
	  ClientGame.ClientMain, before HUDEffects, so HUDEffects does not
	  also try to push these panels around.

	The anchor parts are parented to the camera, which keeps them on
	this client only and out of every raycast and collision.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer

local HUDTilt = {}

HUDTilt.Settings = {
	Enabled = true,
	-- The field of view the HUD was designed at.
	DesignFov = 70,
	-- Where the HUD panels are designed.
	HUDName = "HUD",
}

-- { Gui, Panel, Part, Design = { Position, Size, AnchorPoint } }
local Entries = {}

local function Build(PlayerGui: PlayerGui, Hud: Instance, Gui: SurfaceGui)
	local PanelName = Gui:GetAttribute("Panel")
	local Panel = PanelName and Hud:FindFirstChild(PanelName)
	if not Panel or not Panel:IsA("GuiObject") then
		warn("[HUDTilt] " .. Gui.Name .. " has no panel called " .. tostring(PanelName) .. " in " .. Hud.Name)
		return
	end
	local Design = { Position = Panel.Position, Size = Panel.Size, AnchorPoint = Panel.AnchorPoint }

	local Part = Instance.new("Part")
	Part.Name = Gui.Name .. "Anchor"
	Part.Anchored = true
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.CastShadow = false
	Part.Transparency = 1
	Part.Size = Vector3.new(1, 1, 0.05)
	Part.Parent = workspace.CurrentCamera

	Gui.Adornee = Part
	Panel.AnchorPoint = Vector2.zero
	Panel.Position = UDim2.fromScale(0, 0)
	Panel.Parent = Gui

	table.insert(Entries, { Gui = Gui, Panel = Panel, Part = Part, Design = Design })
end

local function Step()
	local Camera = workspace.CurrentCamera
	if not Camera then
		return
	end
	local View = Camera.ViewportSize
	local Design0 = HUDTilt.Settings.DesignFov
	for _, Entry in ipairs(Entries) do
		local Gui, Part, Design = Entry.Gui, Entry.Part, Entry.Design
		-- Sized for a field of view part way between the design one and
		-- the current one. FovFollow 1 lets the panel recede fully as
		-- the FOV widens, 0 keeps it exactly the designed size.
		local Follow = Gui:GetAttribute("FovFollow") or 0.25
		local Fov = Design0 + (Camera.FieldOfView - Design0) * Follow
		local Tan = math.tan(math.rad(Camera.FieldOfView) / 2) * (math.tan(math.rad(Design0) / 2) / math.tan(math.rad(Fov) / 2))
		if Part.Parent ~= Camera then
			Part.Parent = Camera
		end
		-- The panel's rectangle on screen as it was designed.
		local SizePx = Vector2.new(
			Design.Size.X.Scale * View.X + Design.Size.X.Offset,
			Design.Size.Y.Scale * View.Y + Design.Size.Y.Offset
		)
		local TopLeft = Vector2.new(
			Design.Position.X.Scale * View.X + Design.Position.X.Offset,
			Design.Position.Y.Scale * View.Y + Design.Position.Y.Offset
		) - Design.AnchorPoint * SizePx
		local Centre = TopLeft + SizePx / 2

		-- Studs per pixel at this depth, for the design field of view.
		local Depth = Gui:GetAttribute("Depth") or 5
		local PerPixel = 2 * Depth * Tan / View.Y
		local Local = Vector3.new((Centre.X - View.X / 2) * PerPixel, -(Centre.Y - View.Y / 2) * PerPixel, -Depth)

		Gui.CanvasSize = SizePx
		Part.Size = Vector3.new(SizePx.X * PerPixel, SizePx.Y * PerPixel, 0.05)
		-- Front face toward the camera, then the tilt. The panel turns
		-- about its outer edge (the screen edge it sits against), so
		-- that edge stays exactly where it was designed and the inner
		-- edge goes back into the screen. Turning about the middle
		-- would push the outer half off the screen.
		local Yaw = math.rad(Gui:GetAttribute("Yaw") or 0)
		local Pitch = math.rad(Gui:GetAttribute("Pitch") or 0)
		local Half = Part.Size / 2
		-- After the half turn the part's +X is the screen's left and
		-- +Y is up.
		local Pivot = Vector3.new(
			Yaw > 0 and Half.X or (Yaw < 0 and -Half.X or 0),
			Pitch > 0 and Half.Y or (Pitch < 0 and -Half.Y or 0),
			0
		)
		Part.CFrame = Camera.CFrame
			* CFrame.new(Local)
			* CFrame.Angles(0, math.pi, 0)
			* CFrame.new(Pivot)
			* CFrame.Angles(-Pitch, Yaw, 0)
			* CFrame.new(-Pivot)
	end
end

function HUDTilt.Init()
	if not HUDTilt.Settings.Enabled then
		return
	end
	local PlayerGui = Player:WaitForChild("PlayerGui")
	local Hud = PlayerGui:WaitForChild(HUDTilt.Settings.HUDName, 10)
	if not Hud then
		return
	end
	for _, Gui in ipairs(PlayerGui:GetChildren()) do
		if Gui:IsA("SurfaceGui") and Gui:GetAttribute("Panel") then
			Build(PlayerGui, Hud, Gui)
		end
	end
	-- Right after the camera has moved for this frame.
	RunService:BindToRenderStep("HUDTilt", Enum.RenderPriority.Camera.Value + 1, Step)
end

return HUDTilt
