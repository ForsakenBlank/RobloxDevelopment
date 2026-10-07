-- CoreTag
-- The tag over a player's head showing their active core, in the lobby
-- menus' style: a navy plate outlined in the core's colour, the core's
-- gem, its name in its colour, and a yellow level chip. VIPs get a gold
-- plate with a shine that sweeps across it (Client.Modules.CoreTags
-- moves the shine; every tag has the CollectionService tag "CoreTag").
--
--   local Tag = CoreTag.Build("Ruby", 3, IsVip)
--   Tag.Adornee = Character.Head
--   Tag.Parent = Character.Head
--
-- The gem, the name and the level each have their own part of the tag,
-- so a long name (SAPPHIRE, AMETHYST) shrinks to fit instead of running
-- into the level.
--
-- Built on the server (Server.Services.CoreService) so everyone sees it.
-- It only needs Shared.CoreData, Shared.UIIcons and Shared.GemIcon, so the
-- game place can copy these modules and show the same tag in a run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreData = require(ReplicatedStorage.Modules.Shared.CoreData)
local GemIcon = require(ReplicatedStorage.Modules.Shared.GemIcon)
local GameText = require(ReplicatedStorage.Modules.Shared.GameText)

local CoreTag = {}

CoreTag.Settings = {
	Name = "CoreTag",
	-- Studs above the head, and how far away it can be seen from.
	Height = 2.4,
	MaxDistance = 90,
	Font = Font.new("rbxasset://fonts/families/Montserrat.json", Enum.FontWeight.Heavy),
	Navy = Color3.fromRGB(14, 26, 46),
	Yellow = Color3.fromRGB(255, 210, 31),
	-- The VIP plate: a gold gradient, top to bottom, and its edge.
	GoldTop = Color3.fromRGB(255, 238, 150),
	GoldMiddle = Color3.fromRGB(255, 196, 40),
	GoldBottom = Color3.fromRGB(205, 132, 0),
	GoldEdge = Color3.fromRGB(110, 64, 0),
	-- The CollectionService tags clients look for.
	Tag = "CoreTag",
	ShineTag = "CoreTagShine",
}

-- Returns a new BillboardGui for Key at Level, or nil for an unknown
-- core. Adornee and Parent are left to the caller.
function CoreTag.Build(Key: string, Level: number, Vip: boolean?): BillboardGui?
	local Core = CoreData.Get(Key)
	if not Core then
		return nil
	end
	local Settings = CoreTag.Settings

	local Tag = Instance.new("BillboardGui")
	Tag.Name = Settings.Name
	-- Sized in studs so it shrinks with distance like a name tag.
	Tag.Size = UDim2.fromScale(4.6, 1)
	Tag.StudsOffset = Vector3.new(0, Settings.Height, 0)
	Tag.MaxDistance = Settings.MaxDistance
	Tag.LightInfluence = 0
	Tag.ResetOnSpawn = false

	-- The plate, from just right of the gem to the end.
	local Plate = Instance.new("Frame")
	Plate.Name = "Plate"
	Plate.AnchorPoint = Vector2.new(0, 0.5)
	Plate.Position = UDim2.fromScale(0.1, 0.5)
	Plate.Size = UDim2.fromScale(0.9, 0.7)
	Plate.BackgroundColor3 = Vip and Color3.new(1, 1, 1) or Settings.Navy
	Plate.BackgroundTransparency = Vip and 0 or 0.1
	Plate.Parent = Tag
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0.2, 0)
	Corner.Parent = Plate
	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Vip and Settings.GoldEdge or Core.Colour
	Stroke.Thickness = Vip and 2.5 or 2
	Stroke.Parent = Plate
	if Vip then
		local Gold = Instance.new("UIGradient")
		Gold.Rotation = 90
		Gold.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Settings.GoldTop),
			ColorSequenceKeypoint.new(0.45, Settings.GoldMiddle),
			ColorSequenceKeypoint.new(1, Settings.GoldBottom),
		})
		Gold.Parent = Plate
		-- A bright band the client sweeps across (its Offset moves).
		local Shine = Instance.new("Frame")
		Shine.Name = "Shine"
		Shine.Size = UDim2.fromScale(1, 1)
		Shine.BackgroundColor3 = Color3.new(1, 1, 1)
		Shine.ZIndex = 1
		Shine.Parent = Plate
		local ShineCorner = Instance.new("UICorner")
		ShineCorner.CornerRadius = UDim.new(0.2, 0)
		ShineCorner.Parent = Shine
		local Band = Instance.new("UIGradient")
		Band.Name = "Band"
		Band.Rotation = 20
		Band.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.38, 1),
			NumberSequenceKeypoint.new(0.47, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(0.53, 0.35),
			NumberSequenceKeypoint.new(0.62, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		Band.Offset = Vector2.new(-1, 0)
		Band.Parent = Shine
		Tag:AddTag(Settings.ShineTag)
	end
	Tag:AddTag(Settings.Tag)

	-- The gem over the plate's left end (0 to 0.22 of the tag).
	local Gem: GuiObject
	if Core.Icon then
		local Image = Instance.new("ImageLabel")
		Image.BackgroundTransparency = 1
		Image.Image = Core.Icon
		Image.ScaleType = Enum.ScaleType.Fit
		Gem = Image
	else
		Gem = GemIcon.Create(Key)
	end
	Gem.Name = "Gem"
	Gem.AnchorPoint = Vector2.new(0.5, 0.5)
	Gem.Position = UDim2.fromScale(0.11, 0.5)
	Gem.Size = UDim2.fromScale(0.22, 1)
	Gem.ZIndex = 3
	Gem.Parent = Tag
	local Ratio = Instance.new("UIAspectRatioConstraint")
	Ratio.Parent = Gem

	-- The name, 0.24 to 0.7 of the tag.
	local Name = Instance.new("TextLabel")
	Name.Name = "CoreName"
	Name.BackgroundTransparency = 1
	Name.AnchorPoint = Vector2.new(0, 0.5)
	Name.Position = UDim2.fromScale(0.24, 0.5)
	Name.Size = UDim2.fromScale(0.46, 0.5)
	Name.FontFace = Settings.Font
	Name.Text = string.upper(Core.DisplayName)
	Name.TextColor3 = Vip and Settings.Navy or Core.Light
	Name.TextScaled = true
	Name.TextXAlignment = Enum.TextXAlignment.Left
	Name.ZIndex = 2
	Name.Parent = Tag

	-- The level chip, 0.73 to 0.97 of the tag.
	local Chip = Instance.new("Frame")
	Chip.Name = "LevelChip"
	Chip.AnchorPoint = Vector2.new(0, 0.5)
	Chip.Position = UDim2.fromScale(0.73, 0.5)
	Chip.Size = UDim2.fromScale(0.24, 0.5)
	Chip.BackgroundColor3 = Vip and Settings.Navy or Settings.Yellow
	Chip.ZIndex = 2
	Chip.Parent = Tag
	local ChipCorner = Instance.new("UICorner")
	ChipCorner.CornerRadius = UDim.new(0.2, 0)
	ChipCorner.Parent = Chip
	local LevelLabel = Instance.new("TextLabel")
	LevelLabel.Name = "Level"
	LevelLabel.BackgroundTransparency = 1
	LevelLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	LevelLabel.Position = UDim2.fromScale(0.5, 0.5)
	LevelLabel.Size = UDim2.fromScale(0.86, 0.8)
	LevelLabel.FontFace = Settings.Font
	LevelLabel.Text = GameText.Get("Common.Level", { Level = Level })
	LevelLabel.TextColor3 = Vip and Settings.GoldMiddle or Settings.Navy
	LevelLabel.TextScaled = true
	LevelLabel.ZIndex = 3
	LevelLabel.Parent = Chip

	return Tag
end

return CoreTag
