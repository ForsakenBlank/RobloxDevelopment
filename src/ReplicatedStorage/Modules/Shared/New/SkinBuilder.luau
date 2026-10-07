-- SkinBuilder
-- Turns a skin from Shared.SkinData into a working R6 character model.
-- Used by the server for the real character (Server.Services.
-- CharacterService) and by the client for previews and thumbnails, so
-- both always look the same.
--
--   local Model = SkinBuilder.Build({ Skin = "Monkey" })
--   local Model = SkinBuilder.Build({ Skin = "Cape", Colours = { Torso = "#2F6BFF" }, Face = "Grin" })
--
-- The models in ReplicatedStorage.Assets.Models.Characters come from all
-- over the place, so every build:
--   * strips every script (one skin shipped with a hidden backdoor that
--     would have run on the server the moment it spawned) and saved
--     animations
--   * pulls the six limbs up to the top of the model if they were nested
--   * adds a HumanoidRootPart if there isn't one
--   * replaces the joints between the limbs with the standard R6 ones,
--     so broken or missing joints (and Welds where Motor6Ds belong) don't
--     stop the game's animations
--   * welds any loose extra part (hair, face plates) to the limb it sits
--     nearest to
--   * converts an R15 model to R6 by moving its clothes, colours, face
--     and accessories onto the plain Base model, since the game's
--     movement and animations are R6 only
-- and then adds the cape, body colours and face asked for.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinData = require(script.Parent.SkinData)

local SkinBuilder = {}

SkinBuilder.BaseModel = "Base"

local LIMBS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
local IS_RIG_PART = { HumanoidRootPart = true }
for _, Name in ipairs(LIMBS) do
	IS_RIG_PART[Name] = true
end

-- The standard R6 joints.
local JOINTS = {
	{ "RootJoint", "HumanoidRootPart", "Torso", CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	{ "Neck", "Torso", "Head", CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0) },
	{ "Right Shoulder", "Torso", "Right Arm", CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	{ "Left Shoulder", "Torso", "Left Arm", CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
	{ "Right Hip", "Torso", "Right Leg", CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0) },
	{ "Left Hip", "Torso", "Left Leg", CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0) },
}

-- R15 part -> the R6 limb its colour goes on.
local R15_COLOURS = {
	Head = "HeadColor3",
	UpperTorso = "TorsoColor3",
	LeftUpperArm = "LeftArmColor3",
	RightUpperArm = "RightArmColor3",
	LeftUpperLeg = "LeftLegColor3",
	RightUpperLeg = "RightLegColor3",
}
local R6_COLOURS = {
	Head = "HeadColor3",
	Torso = "TorsoColor3",
	["Left Arm"] = "LeftArmColor3",
	["Right Arm"] = "RightArmColor3",
	["Left Leg"] = "LeftLegColor3",
	["Right Leg"] = "RightLegColor3",
}

function SkinBuilder.Folder(): Instance
	return ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Models"):WaitForChild("Characters")
end

local function IsRigPart(Model: Model, Part: Instance): boolean
	return Part:IsA("BasePart") and Part.Parent == Model and IS_RIG_PART[Part.Name] == true
end

local function InAccessory(Item: Instance): boolean
	return Item:FindFirstAncestorWhichIsA("Accoutrement") ~= nil
end

-- Everything that can run code or carries baggage from another game.
local function Strip(Model: Instance)
	for _, Item in ipairs(Model:GetDescendants()) do
		if Item.Parent and (Item:IsA("LuaSourceContainer") or Item:IsA("KeyframeSequence") or Item:IsA("ForceField")) then
			Item:Destroy()
		end
	end
end

local function FaceDecal(Head: BasePart): Decal?
	for _, Item in ipairs(Head:GetChildren()) do
		if Item:IsA("Decal") and Item.Name:lower() == "face" then
			return Item
		end
	end
	return nil
end

-- Puts an accessory on Model by its attachment, like Humanoid:AddAccessory
-- does, but without needing the model to be in the workspace.
local function Attach(Model: Model, Accessory: Accoutrement)
	local Handle = Accessory:FindFirstChild("Handle")
	if not Handle or not Handle:IsA("BasePart") then
		Accessory:Destroy()
		return
	end
	for _, Item in ipairs(Handle:GetChildren()) do
		if Item:IsA("JointInstance") or Item:IsA("WeldConstraint") then
			Item:Destroy()
		end
	end
	local Target: BasePart? = nil
	local Goal: CFrame? = nil
	for _, Mine in ipairs(Handle:GetChildren()) do
		if Mine:IsA("Attachment") then
			for _, Part in ipairs(Model:GetChildren()) do
				local Theirs = Part:IsA("BasePart") and Part:FindFirstChild(Mine.Name)
				if Theirs and Theirs:IsA("Attachment") then
					Target = Part
					Goal = Theirs.WorldCFrame * Mine.CFrame:Inverse()
					break
				end
			end
		end
		if Target then
			break
		end
	end
	if not Target then
		-- An old hat with no attachment: AttachmentPoint from the top of the head.
		local Head = Model:FindFirstChild("Head") :: BasePart?
		if not Head then
			Accessory:Destroy()
			return
		end
		Target = Head
		Goal = Head.CFrame * CFrame.new(0, Head.Size.Y / 2, 0) * Accessory.AttachmentPoint:Inverse()
	end
	Handle.CFrame = Goal :: CFrame
	local Weld = Instance.new("Weld")
	Weld.Name = "AccessoryWeld"
	Weld.Part0 = Handle
	Weld.Part1 = Target
	Weld.C0 = CFrame.identity
	Weld.C1 = (Target :: BasePart).CFrame:ToObjectSpace(Handle.CFrame)
	Weld.Parent = Handle
	Accessory.Parent = Model
end

-- Makes an R6 model's rig sound. Returns false if it is missing a limb.
local function Repair(Model: Model): boolean
	-- Limbs nested inside a sub-model (one skin keeps its head in one).
	for Name in pairs(IS_RIG_PART) do
		if not Model:FindFirstChild(Name) then
			for _, Item in ipairs(Model:GetDescendants()) do
				if Item.Name == Name and Item:IsA("BasePart") and not InAccessory(Item) then
					Item.Parent = Model
					break
				end
			end
		end
	end
	for _, Name in ipairs(LIMBS) do
		local Part = Model:FindFirstChild(Name)
		if not Part or not Part:IsA("BasePart") then
			return false
		end
	end
	local Torso = Model:FindFirstChild("Torso") :: BasePart

	local Root = Model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not Root then
		local NewRoot = Instance.new("Part")
		NewRoot.Name = "HumanoidRootPart"
		NewRoot.Size = Vector3.new(2, 2, 1)
		NewRoot.CFrame = Torso.CFrame
		NewRoot.Transparency = 1
		NewRoot.CanCollide = false
		NewRoot.Parent = Model
		Root = NewRoot
	end
	(Root :: BasePart).Transparency = 1
	Model.PrimaryPart = Root

	-- Joints between two limbs (or pointing at nothing) go; the standard
	-- ones replace them below.
	for _, Item in ipairs(Model:GetDescendants()) do
		if Item:IsA("JointInstance") or Item:IsA("WeldConstraint") then
			local A, B = (Item :: any).Part0, (Item :: any).Part1
			if not A or not B or not A:IsDescendantOf(Model) or not B:IsDescendantOf(Model) then
				Item:Destroy()
			elseif IsRigPart(Model, A) and IsRigPart(Model, B) then
				Item:Destroy()
			end
		end
	end
	for _, Joint in ipairs(JOINTS) do
		local Name, Part0, Part1, C0, C1 = Joint[1], Joint[2], Joint[3], Joint[4], Joint[5]
		local Motor = Instance.new("Motor6D")
		Motor.Name = Name
		Motor.Part0 = Model:FindFirstChild(Part0) :: BasePart
		Motor.Part1 = Model:FindFirstChild(Part1) :: BasePart
		Motor.C0 = C0
		Motor.C1 = C1
		Motor.Parent = Motor.Part0
	end

	-- Loose extra parts get welded to the nearest limb where they stand.
	for _, Part in ipairs(Model:GetDescendants()) do
		if Part:IsA("BasePart") and not IS_RIG_PART[Part.Name] and not InAccessory(Part) then
			if #Part:GetJoints() == 0 then
				local Nearest, Best = nil, math.huge
				for _, Name in ipairs(LIMBS) do
					local Limb = Model:FindFirstChild(Name) :: BasePart
					local Distance = (Limb.Position - Part.Position).Magnitude
					if Distance < Best then
						Nearest, Best = Limb, Distance
					end
				end
				local Weld = Instance.new("WeldConstraint")
				Weld.Part0 = Nearest
				Weld.Part1 = Part
				Weld.Parent = Part
			end
		end
	end

	for _, Part in ipairs(Model:GetDescendants()) do
		if Part:IsA("BasePart") then
			Part.Anchored = false
			if not IS_RIG_PART[Part.Name] then
				Part.Massless = true
				Part.CanCollide = false
			end
		end
	end

	local Humanoid = Model:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		Humanoid = Instance.new("Humanoid")
		Humanoid.Parent = Model
	end
	Humanoid.RigType = Enum.HumanoidRigType.R6
	Humanoid.HipHeight = 0
	return true
end

-- Puts every limb where its Motor6D says (and whatever is welded to it
-- along with it), so the model looks right even where nothing simulates
-- it, like a ViewportFrame.
local function Pose(Model: Model)
	local Root = Model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not Root then
		return
	end
	-- Parts held to Part by anything but a Motor6D, not crossing to
	-- another limb.
	local function Group(Part: BasePart): { BasePart }
		local Seen = { [Part] = true }
		local Out = { Part }
		local Queue = { Part }
		while #Queue > 0 do
			local Current = table.remove(Queue)
			for _, Joint in ipairs(Current:GetJoints()) do
				if not Joint:IsA("Motor6D") then
					local J = Joint :: any
					for _, Other in ipairs({ J.Part0, J.Part1 }) do
						if Other and Other:IsA("BasePart") and not Seen[Other] and Other:IsDescendantOf(Model) and not IsRigPart(Model, Other) then
							Seen[Other] = true
							table.insert(Out, Other)
							table.insert(Queue, Other)
						end
					end
				end
			end
		end
		return Out
	end
	for _, Joint in ipairs(JOINTS) do
		local Part0 = Model:FindFirstChild(Joint[2]) :: BasePart?
		local Part1 = Model:FindFirstChild(Joint[3]) :: BasePart?
		if Part0 and Part1 then
			local Goal = Part0.CFrame * Joint[4] * Joint[5]:Inverse()
			local Delta = Goal * Part1.CFrame:Inverse()
			for _, Part in ipairs(Group(Part1)) do
				Part.CFrame = Delta * Part.CFrame
			end
		end
	end
end

-- A fresh copy of the Base model, repaired.
local function NewBase(): Model?
	local Template = SkinBuilder.Folder():FindFirstChild(SkinBuilder.BaseModel)
	if not Template then
		return nil
	end
	local Model = Template:Clone()
	Strip(Model)
	if not Repair(Model) then
		Model:Destroy()
		return nil
	end
	return Model
end

-- Moves the look of an R15 (or otherwise unusable) model onto Base.
local function Convert(Source: Model): Model?
	local Model = NewBase()
	if not Model then
		return nil
	end
	for _, Item in ipairs(Model:GetChildren()) do
		if Item:IsA("Clothing") or Item:IsA("ShirtGraphic") or Item:IsA("BodyColors") or Item:IsA("Accoutrement") then
			Item:Destroy()
		end
	end
	local Colours = Source:FindFirstChildOfClass("BodyColors")
	if Colours then
		Colours:Clone().Parent = Model
	else
		local New = Instance.new("BodyColors")
		for PartName, Property in pairs(R15_COLOURS) do
			local Part = Source:FindFirstChild(PartName)
			if Part and Part:IsA("BasePart") then
				(New :: any)[Property] = Part.Color
			end
		end
		for PartName, Property in pairs(R6_COLOURS) do
			local Part = Source:FindFirstChild(PartName)
			if Part and Part:IsA("BasePart") then
				(New :: any)[Property] = Part.Color
			end
		end
		New.Parent = Model
	end
	for _, Item in ipairs(Source:GetChildren()) do
		if Item:IsA("Clothing") or Item:IsA("ShirtGraphic") then
			Item:Clone().Parent = Model
		end
	end
	local OldHead = Source:FindFirstChild("Head") :: BasePart?
	local NewHead = Model:FindFirstChild("Head") :: BasePart
	if OldHead and OldHead:IsA("BasePart") then
		local OldFace = FaceDecal(OldHead)
		if OldFace then
			local Mine = FaceDecal(NewHead)
			if Mine then
				Mine:Destroy()
			end
			OldFace:Clone().Parent = NewHead
		end
		-- Face plates and hair welded to the old head (not the body parts,
		-- which are joined to it with Motor6Ds), at the same offset.
		for _, Part in ipairs(Source:GetDescendants()) do
			if Part:IsA("BasePart") and Part ~= OldHead and not InAccessory(Part) then
				local Joined = false
				for _, Joint in ipairs(Part:GetJoints()) do
					local J = Joint :: any
					if not J:IsA("Motor6D") and (J.Part0 == OldHead or J.Part1 == OldHead) then
						Joined = true
					end
				end
				if Joined then
					local Copy = Part:Clone()
					for _, Item in ipairs(Copy:GetChildren()) do
						if Item:IsA("JointInstance") or Item:IsA("WeldConstraint") then
							Item:Destroy()
						end
					end
					Copy.CFrame = NewHead.CFrame * OldHead.CFrame:ToObjectSpace(Part.CFrame)
					Copy.Anchored = false
					Copy.Massless = true
					Copy.CanCollide = false
					local Weld = Instance.new("WeldConstraint")
					Weld.Part0 = NewHead
					Weld.Part1 = Copy
					Weld.Parent = Copy
					Copy.Parent = Model
				end
			end
		end
	end
	for _, Item in ipairs(Source:GetChildren()) do
		if Item:IsA("Accoutrement") then
			Attach(Model, Item:Clone())
		end
	end
	return Model
end

local function AddCape(Model: Model)
	local Template = SkinBuilder.Folder():FindFirstChild(SkinData.CapeModel)
	local Torso = Model:FindFirstChild("Torso") :: BasePart?
	if not Template or not Template:IsA("BasePart") or not Torso then
		return
	end
	local Cape = Template:Clone()
	Strip(Cape)
	Cape.Name = "Cape"
	local Weld = Cape:FindFirstChildWhichIsA("JointInstance")
	if not Weld then
		Weld = Instance.new("Weld")
		Weld.C0 = CFrame.new(0, 0.7, 0.6) * CFrame.Angles(0, math.pi, 0)
		Weld.Parent = Cape
	end
	local W = Weld :: Weld
	W.Part0 = Cape
	W.Part1 = Torso
	Cape.CFrame = Torso.CFrame * W.C1 * W.C0:Inverse()
	Cape.Anchored = false
	Cape.Massless = true
	Cape.CanCollide = false
	Cape.CanQuery = false
	Cape.CanTouch = false
	Cape.Parent = Model
end

local function ApplyColours(Model: Model, Colours: { [string]: any })
	local Body = Model:FindFirstChildOfClass("BodyColors")
	if not Body then
		Body = Instance.new("BodyColors")
		-- Start from the parts' own colours so untouched parts don't change.
		for PartName, Property in pairs(R6_COLOURS) do
			local Part = Model:FindFirstChild(PartName)
			if Part and Part:IsA("BasePart") then
				(Body :: any)[Property] = Part.Color
			end
		end
		Body.Parent = Model
	end
	for _, Part in ipairs(SkinData.BodyParts) do
		local Colour = SkinData.FromHex(Colours[Part.Key])
		if Colour then
			(Body :: any)[Part.Property] = Colour
		end
	end
end

local function ApplyFace(Model: Model, Key: string)
	local Face = SkinData.GetFace(Key)
	local Head = Model:FindFirstChild("Head") :: BasePart?
	if not Face or Face.Image == "" or not Head then
		return
	end
	local Decal = FaceDecal(Head)
	if not Decal then
		local New = Instance.new("Decal")
		New.Name = "face"
		New.Face = Enum.NormalId.Front
		New.Parent = Head
		Decal = New
	end
	(Decal :: Decal).Texture = Face.Image
end

-- Builds a skin. Spec:
--   Skin      a key in SkinData.Skins (falls back to SkinData.Default)
--   Colours   { [BodyPartKey] = "#RRGGBB" } (Customise), optional
--   Face      a key in SkinData.Faces (Customise), optional
-- Returns the model, not parented anywhere, or nil if even the Base
-- model can't be built.
function SkinBuilder.Build(Spec: { Skin: string?, Colours: { [string]: any }?, Face: string? }): Model?
	local Key = Spec.Skin
	local Skin = SkinData.Get(Key)
	if not Skin then
		Key = SkinData.Default
		Skin = SkinData.Get(Key)
	end
	local Template = SkinBuilder.Folder():FindFirstChild(Skin.Model)
	local Model: Model? = nil
	if Template and Template:IsA("Model") then
		local Copy = Template:Clone()
		Strip(Copy)
		local Humanoid = Copy:FindFirstChildOfClass("Humanoid")
		local IsR15 = (Humanoid and Humanoid.RigType == Enum.HumanoidRigType.R15) or Copy:FindFirstChild("UpperTorso") ~= nil
		if IsR15 then
			Model = Convert(Copy)
			Copy:Destroy()
		elseif Repair(Copy) then
			Model = Copy
		else
			Model = Convert(Copy)
			Copy:Destroy()
		end
	else
		warn("[SkinBuilder] no model called " .. tostring(Skin.Model) .. " for skin " .. tostring(Key))
	end
	if not Model then
		Model = NewBase()
	end
	if not Model then
		return nil
	end
	local Built = Model :: Model
	Built.Name = Key :: string
	Pose(Built)
	if Skin.Cape then
		AddCape(Built)
	end
	if type(Spec.Colours) == "table" then
		ApplyColours(Built, Spec.Colours)
	end
	if type(Spec.Face) == "string" then
		ApplyFace(Built, Spec.Face)
	end
	Built:SetAttribute("Skin", Key)
	return Built
end

-- The colour of each customisable part on a built model, as hex, for
-- the colour picker to start from.
function SkinBuilder.ReadColours(Model: Model): { [string]: string }
	local Out = {}
	local Body = Model:FindFirstChildOfClass("BodyColors")
	for _, Part in ipairs(SkinData.BodyParts) do
		local Colour: Color3? = nil
		if Body then
			Colour = (Body :: any)[Part.Property]
		end
		if not Colour then
			for PartName, Property in pairs(R6_COLOURS) do
				local Limb = Model:FindFirstChild(PartName)
				if Property == Part.Property and Limb and Limb:IsA("BasePart") then
					Colour = Limb.Color
				end
			end
		end
		Out[Part.Key] = SkinData.ToHex(Colour or Color3.new(1, 1, 1))
	end
	return Out
end

return SkinBuilder
