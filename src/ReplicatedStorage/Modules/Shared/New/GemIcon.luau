-- GemIcon
-- Draws a core's gemstone out of plain GUI frames, so it works in any
-- menu and in a BillboardGui above someone's head, and needs no image
-- uploads. Every size and position is Scale, so it fills whatever it is
-- put in: size the returned frame however you like and it stays square.
--
--   local Gem = GemIcon.Create("Ruby")
--   Gem.Size = UDim2.fromOffset(64, 64)
--   Gem.Parent = SomeFrame
--
-- Each core has its own cut (Shape in Shared.CoreData) so they read
-- apart even without colour: Ruby a rhombus, Sapphire a round stone,
-- Amethyst a crystal cluster, Diamond a brilliant. A core with an Icon
-- set in CoreData uses that image instead.
--
-- Used by the client's CoreUI and CharacterCreationUI, and by
-- Server.Services.CoreService for the overhead tag.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreData = require(ReplicatedStorage.Modules.Shared.CoreData)

local GemIcon = {}

local Center = Vector2.new(0.5, 0.5)

local function Frame(Props: { [string]: any }): Frame
	local F = Instance.new("Frame")
	F.BorderSizePixel = 0
	F.AnchorPoint = Center
	F.BackgroundColor3 = Color3.new(1, 1, 1)
	for Key, Value in pairs(Props) do
		if Key ~= "Parent" then
			(F :: any)[Key] = Value
		end
	end
	F.Parent = Props.Parent
	return F
end

local function Round(Parent: Instance)
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0.5, 0)
	Corner.Parent = Parent
end

-- A gradient from A to B with a hard edge at Split, which is what makes
-- a flat frame read as two facets. Rotation is on screen, so a frame
-- that is itself rotated passes its own rotation to cancel it out.
local function Facets(Parent: Instance, A: Color3, B: Color3, Rotation: number, Split: number?)
	local S = Split or 0.5
	local G = Instance.new("UIGradient")
	G.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, A),
		ColorSequenceKeypoint.new(S - 0.001, A),
		ColorSequenceKeypoint.new(S, B),
		ColorSequenceKeypoint.new(1, B),
	})
	G.Rotation = Rotation
	G.Parent = Parent
	return G
end

local function Smooth(Parent: Instance, A: Color3, B: Color3, Rotation: number)
	local G = Instance.new("UIGradient")
	G.Color = ColorSequence.new(A, B)
	G.Rotation = Rotation
	G.Parent = Parent
	return G
end

local function Shine(Parent: Instance, X: number, Y: number, Size: number, Z: number)
	Frame({
		Name = "Shine",
		Size = UDim2.fromScale(Size, Size),
		Position = UDim2.fromScale(X, Y),
		Rotation = 45,
		BackgroundTransparency = 0.15,
		ZIndex = Z,
		Parent = Parent,
	})
end

----------------------------------------------------------------------
-- CUTS
----------------------------------------------------------------------

local Cuts = {}

-- A square turned 45 degrees, split left and right, with a smaller
-- table facet on top split top and bottom.
function Cuts.Rhombus(Root: Frame, Core)
	local Body = Frame({ Name = "Body", Size = UDim2.fromScale(0.64, 0.64), Position = UDim2.fromScale(0.5, 0.5), Rotation = 45, ZIndex = 2, Parent = Root })
	Facets(Body, Core.Colour, Core.Dark, -45)
	local Table = Frame({ Name = "Table", Size = UDim2.fromScale(0.32, 0.32), Position = UDim2.fromScale(0.5, 0.5), Rotation = 45, ZIndex = 3, Parent = Root })
	Facets(Table, Core.Light, Core.Colour, 45)
	Shine(Root, 0.36, 0.34, 0.09, 4)
end

-- A round stone seen from above: a shaded disc, a ring of facets and a
-- square table.
function Cuts.Round(Root: Frame, Core)
	local Body = Frame({ Name = "Body", Size = UDim2.fromScale(0.84, 0.84), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 2, Parent = Root })
	Round(Body)
	Smooth(Body, Core.Light, Core.Dark, 45)
	local Ring = Frame({ Name = "Ring", Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 3, Parent = Root })
	Round(Ring)
	Facets(Ring, Core.Colour, Core.Dark, 45)
	local Table = Frame({ Name = "Table", Size = UDim2.fromScale(0.34, 0.34), Position = UDim2.fromScale(0.5, 0.5), Rotation = 45, ZIndex = 4, Parent = Root })
	Facets(Table, Core.Light, Core.Colour, 45)
	Shine(Root, 0.33, 0.3, 0.08, 5)
end

-- Three pointed columns, the middle one tallest. Each column is a
-- rectangle with a turned square for its point, and is split down the
-- middle for a lit face and a shaded one.
function Cuts.Crystal(Root: Frame, Core)
	local function Column(X: number, Width: number, Height: number, Bottom: number, Z: number)
		local Side = Width / math.sqrt(2)
		local Tip = Frame({ Name = "Tip", Size = UDim2.fromScale(Side, Side), Position = UDim2.fromScale(X, Bottom - Height), Rotation = 45, ZIndex = Z, Parent = Root })
		Facets(Tip, Core.Light, Core.Colour, -45)
		local Shaft = Frame({ Name = "Shaft", AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromScale(Width, Height), Position = UDim2.fromScale(X, Bottom), ZIndex = Z + 1, Parent = Root })
		Facets(Shaft, Core.Colour, Core.Dark, 0)
	end
	Column(0.27, 0.2, 0.3, 0.9, 2)
	Column(0.73, 0.2, 0.36, 0.9, 2)
	Column(0.5, 0.28, 0.48, 0.92, 4)
	local Base = Frame({ Name = "Base", Size = UDim2.fromScale(0.78, 0.1), Position = UDim2.fromScale(0.5, 0.9), ZIndex = 6, BackgroundColor3 = Core.Dark, Parent = Root })
	Round(Base)
	Shine(Root, 0.45, 0.42, 0.06, 7)
end

-- The classic cut from the side: a wide crown on top of a pointed
-- pavilion. The pavilion is a turned square with its top half faded out
-- behind the crown.
function Cuts.Brilliant(Root: Frame, Core)
	local Pavilion = Frame({ Name = "Pavilion", Size = UDim2.fromScale(0.62, 0.62), Position = UDim2.fromScale(0.5, 0.4), Rotation = 45, ZIndex = 2, Parent = Root })
	local G = Smooth(Pavilion, Core.Colour, Core.Dark, 45)
	G.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.499, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	-- Facet lines from the crown down to the point.
	local function Line(X: number, Rotation: number)
		Frame({
			Name = "Facet",
			Size = UDim2.fromScale(0.025, 0.44),
			Position = UDim2.fromScale(X, 0.61),
			Rotation = Rotation,
			BackgroundColor3 = Core.Light,
			BackgroundTransparency = 0.35,
			ZIndex = 3,
			Parent = Root,
		})
	end
	Line(0.5, 0)
	Line(0.395, -25)
	Line(0.605, 25)
	local Crown = Frame({ Name = "Crown", Size = UDim2.fromScale(0.88, 0.22), Position = UDim2.fromScale(0.5, 0.29), ZIndex = 4, Parent = Root })
	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0.3, 0)
	Corner.Parent = Crown
	local Mid = Core.Colour:Lerp(Core.Light, 0.5)
	local CG = Instance.new("UIGradient")
	CG.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Core.Colour),
		ColorSequenceKeypoint.new(0.249, Core.Colour),
		ColorSequenceKeypoint.new(0.25, Core.Light),
		ColorSequenceKeypoint.new(0.499, Core.Light),
		ColorSequenceKeypoint.new(0.5, Mid),
		ColorSequenceKeypoint.new(0.749, Mid),
		ColorSequenceKeypoint.new(0.75, Core.Dark:Lerp(Core.Colour, 0.4)),
		ColorSequenceKeypoint.new(1, Core.Dark:Lerp(Core.Colour, 0.4)),
	})
	CG.Parent = Crown
	Shine(Root, 0.3, 0.26, 0.07, 5)
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

-- Returns a transparent square frame with the gem drawn inside it.
-- Options.Glow adds a soft disc of the core's colour behind the gem.
-- An unknown key gives an empty grey socket.
function GemIcon.Create(Key: string?, Options: { Glow: boolean? }?): Frame
	local Root = Instance.new("Frame")
	Root.Name = "Gem"
	Root.BackgroundTransparency = 1
	Root.Size = UDim2.fromScale(1, 1)
	local Aspect = Instance.new("UIAspectRatioConstraint")
	Aspect.AspectRatio = 1
	Aspect.Parent = Root

	local Core = CoreData.Get(Key)
	if not Core then
		local Socket = Frame({ Name = "Socket", Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.5, 0.5), Rotation = 45, BackgroundColor3 = Color3.fromRGB(45, 45, 55), Parent = Root })
		local Stroke = Instance.new("UIStroke")
		Stroke.Color = Color3.fromRGB(90, 90, 100)
		Stroke.Parent = Socket
		return Root
	end

	if Options and Options.Glow then
		local Glow = Frame({ Name = "Glow", Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Core.Colour, ZIndex = 1, Parent = Root })
		Round(Glow)
		-- A radial fall off isn't possible, so fade it from the middle out
		-- in both directions instead.
		local G = Instance.new("UIGradient")
		G.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		G.Rotation = 90
		G.Parent = Glow
	end

	if Core.Icon then
		local Image = Instance.new("ImageLabel")
		Image.Name = "Image"
		Image.BackgroundTransparency = 1
		Image.Size = UDim2.fromScale(1, 1)
		Image.Image = Core.Icon
		Image.ZIndex = 2
		Image.Parent = Root
		return Root
	end

	local Cut = Cuts[Core.Shape] or Cuts.Rhombus
	Cut(Root, Core)
	return Root
end

return GemIcon
