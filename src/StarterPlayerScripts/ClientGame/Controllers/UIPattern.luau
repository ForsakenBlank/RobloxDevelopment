--[[
	UIPattern

	Slides the rows of grey squares behind the HUD panels. Each row is
	twice as wide as its panel and repeats every half, so moving it by
	one panel width and jumping back is seamless. Rows take turns
	going right and left.

	The rows are designed in the editor (a Frame called Pattern in each
	panel, with Frames called Row in it). This only moves them.
]]

--[[
	What connects to this

	Moves:
	  Every Frame tagged ScrollingPattern in this player's PlayerGui,
	  including the panels HUDTilt moved onto SurfaceGuis. Each row's
	  attributes say how:
	    Direction  1 slides right, -1 slides left
	    Speed      panel widths per second

	Started by:
	  ClientGame.ClientMain.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local UIPattern = {}

UIPattern.Settings = {
	Tag = "ScrollingPattern",
	-- Used when a row has no Speed attribute.
	DefaultSpeed = 0.02,
}

-- Row -> true, for rows in this player's gui.
local Rows: { [GuiObject]: boolean } = {}

function UIPattern.Init()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local Tag = UIPattern.Settings.Tag

	local function Add(Row: Instance)
		if Row:IsA("GuiObject") and Row:IsDescendantOf(PlayerGui) then
			Rows[Row] = true
		end
	end
	for _, Row in ipairs(CollectionService:GetTagged(Tag)) do
		Add(Row)
	end
	CollectionService:GetInstanceAddedSignal(Tag):Connect(function(Row)
		-- Cloned rows (squad members) arrive before they are parented.
		task.defer(Add, Row)
	end)
	CollectionService:GetInstanceRemovedSignal(Tag):Connect(function(Row)
		Rows[Row] = nil
	end)

	RunService.RenderStepped:Connect(function()
		local Now = os.clock()
		for Row in pairs(Rows) do
			if not Row.Parent then
				Rows[Row] = nil
			elseif Row.Visible then
				local Speed = Row:GetAttribute("Speed") or UIPattern.Settings.DefaultSpeed
				local Shift = (Now * Speed) % 1
				local X = (Row:GetAttribute("Direction") or 1) > 0 and Shift - 1 or -Shift
				Row.Position = UDim2.new(X, 0, Row.Position.Y.Scale, 0)
			end
		end
	end)
end

return UIPattern
