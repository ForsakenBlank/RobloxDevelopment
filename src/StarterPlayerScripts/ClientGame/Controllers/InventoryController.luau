--[[
	InventoryController

	Makes the Roblox Backpack the item inventory. Server.Game.Core.
	Loadout keeps one Tool in the Backpack for each shop item the player
	is carrying (a Health Potion, a Molotov and so on), marked with the
	LoadoutKind "Item" and LoadoutId attributes. Weapons and abilities
	are not in the Backpack, they are swapped with R and G.

	Picking an item with the number keys or by clicking its slot:
	  A normal item is used straight away: this asks the server to use
	  it and puts the Tool back, so it is never actually held.
	  A thrown item (one with a Throw table in ShopItemData, the Molotov)
	  is held ready instead. The arm goes back, the arc it will fly is
	  drawn from the hand to where it will land, with a ring the size of
	  the area it covers. Left click throws it, right click or putting
	  the Tool away cancels.
]]

--[[
	What connects to this

	Reads:
	  The LoadoutKind and LoadoutId attributes Loadout writes on every
	  item Tool.
	  Game.Data.ShopItemData for which items are thrown, their Throw
	  numbers and their Radius.
	  Game.Shared.ThrowArc for the arc, the same maths the server throws
	  with.

	Sends:
	  ReplicatedStorage.Remotes.Events.ItemUse with (ItemId,
	  AimPosition), handled by Server.Game.Shop.ShopItems, which checks
	  the player really has that item.

	Used by:
	  ClientGame.Controllers.CombatInput, which asks IsAiming so a click
	  that throws is not also a weapon attack.

	Started by:
	  ClientGame.ClientMain, and given every new character through
	  OnCharacter.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local ThrowArc = require(ReplicatedStorage.Modules.Game.Shared.ThrowArc)
local ShopItemData = require(ReplicatedStorage.Modules.Game.Data.ShopItemData)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local Player = Players.LocalPlayer

local InventoryController = {}

InventoryController.Settings = {
	KindAttribute = "LoadoutKind",
	IdAttribute = "LoadoutId",
	AimRayLength = 1000,
	-- Attribute on the LocalPlayer set while a menu is open.
	UIOpenAttribute = "UIOpen",

	-- The aiming arc: dots this many seconds of flight apart, and the
	-- longest flight drawn.
	ArcStep = 0.04,
	ArcMaxTime = 3,
	DotSize = 0.35,
	ArcColour = Color3.fromRGB(255, 170, 60),
	-- The ring where it will land.
	RingColour = Color3.fromRGB(255, 110, 30),
	RingTransparency = 0.55,
	-- The arm: angle (degrees, around the shoulder) held back while
	-- aiming, and swung forward to on the throw.
	ArmBackAngle = 200,
	ArmThrowAngle = 70,
	ThrowSwingTime = 0.12,
	-- The bottle held in the hand while aiming.
	HeldColour = Color3.fromRGB(110, 170, 80),
}

local Character: Model? = nil
local Humanoid: Humanoid? = nil
local Connections: { RBXScriptConnection } = {}

-- The item being held ready to throw, or nil.
local Aiming: {
	Tool: Tool,
	ItemId: string,
	Item: any,
	Folder: Folder,
	Dots: { BasePart },
	Ring: BasePart,
	Bottle: BasePart?,
	Aim: Vector3,
	Connection: RBXScriptConnection?,
}? = nil
-- Extra angle on the right shoulder, written every frame while it is
-- not zero (the aiming pose and the throw swing).
local ArmAngle = 0

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function IgnoreList(): { Instance }
	local Exclude: { Instance } = { workspace.CurrentCamera }
	for _, Name in ipairs({ "Effects", "Runtime", "ClientFX" }) do
		local Folder = workspace:FindFirstChild(Name)
		if Folder then
			table.insert(Exclude, Folder)
		end
	end
	for _, Other in ipairs(Players:GetPlayers()) do
		if Other.Character then
			table.insert(Exclude, Other.Character)
		end
	end
	return Exclude
end

local function GetAimPosition(): Vector3
	local Camera = workspace.CurrentCamera
	local Mouse = UserInputService:GetMouseLocation()
	local Ray = Camera:ViewportPointToRay(Mouse.X, Mouse.Y)
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = IgnoreList()
	local Length = InventoryController.Settings.AimRayLength
	local Result = workspace:Raycast(Ray.Origin, Ray.Direction * Length, Params)
	return Result and Result.Position or (Ray.Origin + Ray.Direction * Length)
end

local function RightShoulder(): Motor6D?
	local Torso = Character and Character:FindFirstChild("Torso")
	local Joint = Torso and Torso:FindFirstChild("Right Shoulder")
	return Joint and Joint:IsA("Motor6D") and Joint or nil
end

local function EffectPart(Props): BasePart
	local P = Instance.new("Part")
	P.Anchored = true
	P.CanCollide = false
	P.CanQuery = false
	P.CanTouch = false
	P.CastShadow = false
	P.Material = Enum.Material.Neon
	for Key, Value in pairs(Props) do
		(P :: any)[Key] = Value
	end
	return P
end

local function StopAiming()
	local Current = Aiming
	if not Current then
		return
	end
	Aiming = nil
	if Current.Connection then
		Current.Connection:Disconnect()
	end
	Current.Folder:Destroy()
	if Current.Bottle then
		Current.Bottle:Destroy()
	end
	ArmAngle = 0
end

-- Redraws the arc and the landing ring for where the cursor is now.
local function UpdateArc()
	local Current = Aiming
	local Root = Character and Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not Current or not Root then
		return
	end
	local Settings = InventoryController.Settings
	local Throw = Current.Item.Throw
	local Aim = ThrowArc.ClampAim(Root.Position, GetAimPosition(), Throw.MaxRange)
	Current.Aim = Aim
	local Origin = ThrowArc.Origin(Root.Position, Aim)
	local Velocity = ThrowArc.Velocity(Origin, Aim, Throw.Speed, Throw.Gravity)

	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = IgnoreList()
	local Points, Landing = ThrowArc.Trace(Origin, Velocity, Throw.Gravity, Params, Settings.ArcStep, Settings.ArcMaxTime)

	-- Enough dots for the arc, the spare ones hidden.
	for Index = 1, math.max(#Points, #Current.Dots) do
		local Dot = Current.Dots[Index]
		local Point = Points[Index]
		if Point and not Dot then
			Dot = EffectPart({
				Shape = Enum.PartType.Ball,
				Size = Vector3.one * Settings.DotSize,
				Color = Settings.ArcColour,
			})
			Dot.Parent = Current.Folder
			Current.Dots[Index] = Dot
		end
		if Dot then
			if Point then
				Dot.Position = Point
				-- Fades towards the far end.
				Dot.Transparency = 0.15 + 0.6 * (Index / math.max(#Points, 1))
			else
				Dot.Transparency = 1
			end
		end
	end

	local Ring = Current.Ring
	if Landing then
		Ring.Transparency = Settings.RingTransparency
		Ring.CFrame = CFrame.new(Landing + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	else
		Ring.Transparency = 1
	end
end

local function StartAiming(Tool: Tool, ItemId: string, Item)
	StopAiming()
	local Settings = InventoryController.Settings
	local Folder = Instance.new("Folder")
	Folder.Name = "ThrowPreview"
	Folder.Parent = workspace:FindFirstChild("Effects") or workspace
	local Radius = Item.Radius or 5
	local Ring = EffectPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, Radius * 2, Radius * 2),
		Color = Settings.RingColour,
		Transparency = 1,
	})
	Ring.Parent = Folder

	-- A bottle in the hand, lit.
	local Bottle = nil
	local Arm = Character and Character:FindFirstChild("Right Arm") :: BasePart?
	if Arm then
		Bottle = EffectPart({
			Size = Vector3.new(0.5, 0.9, 0.5),
			Color = Settings.HeldColour,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Anchored = false,
			Massless = true,
			CFrame = Arm.CFrame * CFrame.new(0, -1.3, 0),
		})
		local Weld = Instance.new("WeldConstraint")
		Weld.Part0 = Arm
		Weld.Part1 = Bottle
		Weld.Parent = Bottle
		local Flame = Instance.new("Fire")
		Flame.Size = 2
		Flame.Heat = 4
		Flame.Parent = Bottle
		Bottle.Parent = Character
	end

	Aiming = {
		Tool = Tool,
		ItemId = ItemId,
		Item = Item,
		Folder = Folder,
		Dots = {},
		Ring = Ring,
		Bottle = Bottle,
		Aim = Vector3.zero,
		Connection = RunService.RenderStepped:Connect(UpdateArc),
	}
	ArmAngle = Settings.ArmBackAngle
	CombatFX.PlaySound("UIClick", nil, 0.5, 0.9)
end

-- Throws the held item at the aim point: the arm swings forward, the
-- server is asked to throw it, and the Tool goes back in the Backpack.
local function Throw()
	local Current = Aiming
	if not Current then
		return
	end
	local Aim = Current.Aim
	local ItemId = Current.ItemId
	StopAiming()
	InventoryController.UseItem(ItemId, Aim)
	if Humanoid and Humanoid.Parent then
		Humanoid:UnequipTools()
	end
	-- The swing forward, then back to normal.
	local Settings = InventoryController.Settings
	ArmAngle = Settings.ArmBackAngle
	local Value = Instance.new("NumberValue")
	Value.Value = Settings.ArmBackAngle
	Value.Changed:Connect(function(New)
		ArmAngle = New
	end)
	local Tween = TweenService:Create(Value, TweenInfo.new(Settings.ThrowSwingTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = Settings.ArmThrowAngle })
	Tween:Play()
	Tween.Completed:Once(function()
		task.wait(0.15)
		Value:Destroy()
		if not Aiming then
			ArmAngle = 0
		end
	end)
end

-- An item Tool was picked. The put back is deferred a frame, because
-- this runs from inside the Tool being equipped and Roblox has not
-- finished moving it yet.
local function OnToolEquipped(Tool: Tool)
	local Settings = InventoryController.Settings
	if Tool:GetAttribute(Settings.KindAttribute) ~= "Item" then
		return
	end
	local ItemId = Tool:GetAttribute(Settings.IdAttribute)
	local Item = type(ItemId) == "string" and ShopItemData.Items[ItemId] or nil
	if Item and Item.Throw then
		if not Player:GetAttribute(Settings.UIOpenAttribute) then
			StartAiming(Tool, ItemId, Item)
		end
		return
	end
	task.defer(function()
		if Humanoid and Humanoid.Parent and Tool.Parent == Character then
			Humanoid:UnequipTools()
		end
	end)
	InventoryController.UseItem(ItemId)
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

-- Asks the server to use one of an item. The server checks the player
-- really has it.
function InventoryController.UseItem(ItemId: string?, AimPosition: Vector3?)
	if type(ItemId) ~= "string" then
		return
	end
	if Player:GetAttribute(InventoryController.Settings.UIOpenAttribute) then
		return
	end
	Events:WaitForChild("ItemUse"):FireServer(ItemId, AimPosition or GetAimPosition())
	CombatFX.PlaySound("UIClick", nil, 0.6)
end

-- Whether a thrown item is held ready, so clicks belong to it.
function InventoryController.IsAiming(): boolean
	return Aiming ~= nil
end

function InventoryController.OnCharacter(NewCharacter: Model)
	StopAiming()
	for _, Connection in ipairs(Connections) do
		Connection:Disconnect()
	end
	Connections = {}
	Character = NewCharacter
	Humanoid = NewCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	table.insert(Connections, NewCharacter.ChildAdded:Connect(function(Child)
		if Child:IsA("Tool") then
			OnToolEquipped(Child)
		end
	end))
	-- Putting the Tool away (or picking another) cancels the throw.
	table.insert(Connections, NewCharacter.ChildRemoved:Connect(function(Child)
		if Aiming and Child == Aiming.Tool then
			StopAiming()
		end
	end))
end

function InventoryController.Init()
	UserInputService.InputBegan:Connect(function(Input: InputObject, GameProcessed: boolean)
		if not Aiming or GameProcessed then
			return
		end
		if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.KeyCode == Enum.KeyCode.ButtonR2 then
			Throw()
		elseif Input.UserInputType == Enum.UserInputType.MouseButton2 or Input.KeyCode == Enum.KeyCode.ButtonB then
			StopAiming()
			if Humanoid and Humanoid.Parent then
				Humanoid:UnequipTools()
			end
		end
	end)

	-- The arm pose, written after the Animator each step so it sits on
	-- top of whatever animation is playing.
	RunService.Stepped:Connect(function()
		if ArmAngle == 0 then
			return
		end
		local Joint = RightShoulder()
		if Joint then
			Joint.Transform = CFrame.Angles(0, 0, math.rad(ArmAngle))
		end
	end)
end

return InventoryController
