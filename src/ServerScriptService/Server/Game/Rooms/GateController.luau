--[[
	GateController

	Owns the 7 gates in workspace.MainGameObj.Gates. It opens a gate,
	closes and locks one, and sets the yellow highlight that shows
	players which gate they are meant to go to next.

	The highlight rule is: when a gate becomes the way forward it turns
	yellow, and it stays yellow until the players have gone through and
	the next thing has started. In a room that means until the next wave
	begins, and in a shop it means until the next gate opens. So the
	highlight is not simply on while open, it is on while that gate is
	the objective.

	A locked gate has to be a real physical block, collidable and
	staying that way even while it is animating. If a player can slip
	through a gate that is part way open they can skip a wave, and the
	movement system in this place makes players fast enough to try. So
	a gate only stops colliding once it has finished sinking, and it
	starts colliding again the moment it starts closing.

	The gates are Models with a Part inside, so this works on the model
	and finds the parts rather than assuming the structure, in case a
	gate gets more parts added to it later.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.RoomData for how gates open (Sink, Fade or Destroy), the
	  timings and the prompt text.
	  workspace.MainGameObj.Gates for Gate1 to Gate7.

	Called by:
	  Server.Game.Rooms.RoomManager, which opens a gate when a combat
	  area is cleared, closes the gate behind the players when a new area
	  starts, and sets or clears the highlight.
	  Server.Game.Core.RunManager, which resets every gate when a run
	  ends.

	Prompt gates:
	  Gate1 out of Spawn, Gate4 out of Shop1 and Gate7 out of Shop2 open
	  on a proximity prompt. RoomManager calls AddPrompt with a callback,
	  and that callback is where the check that the run is actually in
	  that area lives, so a player cannot trigger a prompt for a shop
	  they have not reached.

	Uses:
	  ReplicatedStorage.Modules.Shared.Sound for the gate sound, if a
	  sound with the name in RoomData exists. A missing sound is skipped
	  quietly.
	  A Highlight instance for the yellow, which is simpler than
	  swapping materials and reverts cleanly. One is made per gate and
	  switched on and off rather than created each time.

	The opening is done on the server, not the client. If the movement
	is client side, one player can walk through a gate that another
	player still sees as shut.

	Every gate starts closed and locked, including Gate1, so players
	cannot walk into Room1 before the run has set itself up.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local Sound = require(ReplicatedStorage.Modules.Shared.Sound)

local GateController = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

GateController.Settings = {
	-- The objective highlight.
	HighlightFill = Color3.fromRGB(255, 220, 60),
	HighlightOutline = Color3.fromRGB(255, 240, 150),
	HighlightFillTransparency = 0.55,
	HighlightOutlineTransparency = 0,
	-- Seconds a closing gate takes to rise back up.
	CloseTime = 0.6,
	-- Studs the prompt can be used from.
	PromptDistance = 18,
	-- Keyboard key for the gate prompts. E is the ability key and F is
	-- Leap in MovementSettings, so prompts use Z.
	PromptKey = Enum.KeyCode.Z,
	PromptGamepadKey = Enum.KeyCode.ButtonY,
	-- Attribute on the gate model, true while open, for the client.
	OpenAttribute = "Open",
	-- Studs above the bottom of a gate that count as where a player
	-- stands in front of it.
	ChestHeight = 3,
}

-- Per gate: { Model, Parts = { [BasePart] = ClosedCFrame, ... },
-- Transparency = { [BasePart] = number }, Open, Highlight, Prompt,
-- Tweens }
local Gates: { [string]: any } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function PlaySound(Name: string?, Gate)
	if not Name or Name == "" then
		return
	end
	local Folder = SoundService:FindFirstChild("Sounds")
	if not Folder or not Folder:FindFirstChild(Name, true) then
		return
	end
	local Primary = next(Gate.Parts)
	if Primary then
		Sound:Play(Name, Primary)
	end
end

local function StopTweens(Gate)
	for _, Tween in ipairs(Gate.Tweens) do
		Tween:Cancel()
	end
	Gate.Tweens = {}
end

local function Register(Model: Instance)
	local Parts, Transparency = {}, {}
	if Model:IsA("BasePart") then
		Parts[Model] = Model.CFrame
		Transparency[Model] = Model.Transparency
	end
	for _, Descendant in ipairs(Model:GetDescendants()) do
		if Descendant:IsA("BasePart") then
			Parts[Descendant] = Descendant.CFrame
			Transparency[Descendant] = Descendant.Transparency
		end
	end
	if next(Parts) == nil then
		warn("[GateController] " .. Model.Name .. " has no parts")
		return
	end

	local Highlight = Instance.new("Highlight")
	Highlight.Name = "ObjectiveHighlight"
	Highlight.FillColor = GateController.Settings.HighlightFill
	Highlight.OutlineColor = GateController.Settings.HighlightOutline
	Highlight.FillTransparency = GateController.Settings.HighlightFillTransparency
	Highlight.OutlineTransparency = GateController.Settings.HighlightOutlineTransparency
	Highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	Highlight.Enabled = false
	Highlight.Parent = Model

	Gates[Model.Name] = {
		Model = Model,
		Parts = Parts,
		Transparency = Transparency,
		Open = false,
		Highlight = Highlight,
		Prompt = nil,
		Tweens = {},
	}
end

local function Get(GateName: string?)
	if not GateName then
		return nil
	end
	local Gate = Gates[GateName]
	if not Gate then
		warn("[GateController] no gate called " .. tostring(GateName))
	end
	return Gate
end

----------------------------------------------------------------------
-- OPEN AND CLOSE
----------------------------------------------------------------------

-- Opens a gate. AreaName is the area whose GateOut this is, for the
-- per area overrides in RoomData. Returns once the animation is
-- started, not finished.
function GateController.Open(GateName: string, AreaName: string?)
	local Gate = Get(GateName)
	if not Gate or Gate.Open then
		return
	end
	Gate.Open = true
	Gate.Model:SetAttribute(GateController.Settings.OpenAttribute, true)
	GateController.RemovePrompt(GateName)
	StopTweens(Gate)

	local Settings = RoomData.GetGateSettings(AreaName or "")
	PlaySound(Settings.Sound, Gate)

	local Info = TweenInfo.new(Settings.OpenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for Part, ClosedCFrame in pairs(Gate.Parts) do
		if Settings.OpenStyle == "Fade" then
			table.insert(Gate.Tweens, TweenService:Create(Part, Info, { Transparency = 1 }))
		elseif Settings.OpenStyle == "Destroy" then
			Part.Transparency = 1
			Part.CanCollide = false
			Part.CanQuery = false
		else
			table.insert(Gate.Tweens, TweenService:Create(Part, Info, { CFrame = ClosedCFrame - Vector3.new(0, Settings.SinkDistance, 0) }))
		end
	end
	for _, Tween in ipairs(Gate.Tweens) do
		Tween:Play()
	end

	-- Only let players through once it is fully open.
	task.delay(Settings.OpenTime, function()
		if not Gate.Open then
			return
		end
		for Part in pairs(Gate.Parts) do
			Part.CanCollide = false
			Part.CanQuery = false
		end
	end)
end

-- Closes and locks a gate. Collision comes back straight away so it
-- is a wall the moment it starts rising. Instant skips the animation,
-- for resets.
function GateController.Close(GateName: string, Instant: boolean?)
	local Gate = Get(GateName)
	if not Gate then
		return
	end
	local WasOpen = Gate.Open
	Gate.Open = false
	Gate.Model:SetAttribute(GateController.Settings.OpenAttribute, false)
	StopTweens(Gate)

	local Info = TweenInfo.new(GateController.Settings.CloseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for Part, ClosedCFrame in pairs(Gate.Parts) do
		Part.CanCollide = true
		Part.CanQuery = true
		if Instant or not WasOpen then
			Part.CFrame = ClosedCFrame
			Part.Transparency = Gate.Transparency[Part]
		else
			table.insert(Gate.Tweens, TweenService:Create(Part, Info, {
				CFrame = ClosedCFrame,
				Transparency = Gate.Transparency[Part],
			}))
		end
	end
	for _, Tween in ipairs(Gate.Tweens) do
		Tween:Play()
	end
	if WasOpen and not Instant then
		PlaySound(RoomData.Gate.CloseSound, Gate)
	end
end

function GateController.IsOpen(GateName: string): boolean
	local Gate = Gates[GateName]
	return Gate ~= nil and Gate.Open
end

-- A point at chest height in the middle of the closed gate's doorway,
-- for distance checks, facing and the prompt. Measured from the
-- bottom of the gate rather than its centre, because the gates are 32
-- studs tall and the centre is far above anyone standing there.
function GateController.GetPosition(GateName: string): Vector3?
	local Gate = Gates[GateName]
	if not Gate then
		return nil
	end
	local Part = next(Gate.Parts)
	if not Part then
		return nil
	end
	local Closed = Gate.Parts[Part]
	return Closed.Position - Vector3.new(0, Part.Size.Y / 2 - GateController.Settings.ChestHeight, 0)
end

----------------------------------------------------------------------
-- HIGHLIGHT
----------------------------------------------------------------------

-- Turns the yellow objective highlight on or off for one gate.
function GateController.SetHighlight(GateName: string, On: boolean)
	local Gate = Get(GateName)
	if Gate then
		Gate.Highlight.Enabled = On
	end
end

function GateController.ClearHighlights()
	for _, Gate in pairs(Gates) do
		Gate.Highlight.Enabled = false
	end
end

----------------------------------------------------------------------
-- PROMPTS
----------------------------------------------------------------------

-- Puts a proximity prompt on a gate. Callback(Player) runs when a
-- player finishes holding it, and decides whether the gate actually
-- opens. AreaName picks up the per area prompt text.
function GateController.AddPrompt(GateName: string, AreaName: string?, Callback: (Player) -> ())
	local Gate = Get(GateName)
	if not Gate then
		return
	end
	GateController.RemovePrompt(GateName)

	local Settings = RoomData.GetGateSettings(AreaName or "")
	-- The gates are tall, so a prompt on the part's centre would be out
	-- of reach from the floor. It goes on an attachment at chest height
	-- on the side players walk up to, which is the -X side since the
	-- map runs along +X.
	local Part = next(Gate.Parts)
	local Anchor = Part:FindFirstChild("PromptAttachment")
	if not Anchor then
		Anchor = Instance.new("Attachment")
		Anchor.Name = "PromptAttachment"
		Anchor.Parent = Part
	end
	Anchor.WorldPosition = GateController.GetPosition(GateName) - Vector3.new(Part.Size.X / 2 + 1, 0, 0)
	local Prompt = Instance.new("ProximityPrompt")
	Prompt.Name = "GatePrompt"
	Prompt.ActionText = Settings.PromptText or "Continue"
	Prompt.ObjectText = "Gate"
	Prompt.HoldDuration = Settings.PromptHoldTime or 1
	Prompt.MaxActivationDistance = GateController.Settings.PromptDistance
	Prompt.KeyboardKeyCode = GateController.Settings.PromptKey
	Prompt.GamepadKeyCode = GateController.Settings.PromptGamepadKey
	Prompt.RequiresLineOfSight = false
	Prompt.Parent = Anchor
	Prompt.Triggered:Connect(Callback)
	Gate.Prompt = Prompt
end

function GateController.RemovePrompt(GateName: string)
	local Gate = Gates[GateName]
	if Gate and Gate.Prompt then
		Gate.Prompt:Destroy()
		Gate.Prompt = nil
	end
end

----------------------------------------------------------------------
-- RESET
----------------------------------------------------------------------

-- Every gate closed, locked, unlit and without a prompt.
function GateController.ResetAll()
	for GateName in pairs(Gates) do
		GateController.RemovePrompt(GateName)
		GateController.SetHighlight(GateName, false)
		GateController.Close(GateName, true)
	end
end

function GateController.Init()
	local Folder = RoomData.GetFolder("Gates")
	if not Folder then
		return
	end
	for _, Model in ipairs(Folder:GetChildren()) do
		Register(Model)
	end
	GateController.ResetAll()
end

return GateController
