--[[
	ShopController

	Handles the player side of the shop. It keeps a billboard above
	every stocked podium showing the item, its description and its price,
	with the price turning green or red depending on whether this player
	can afford it. The buying itself is the podium's ProximityPrompt,
	which the server handles, so this never sends a price or an item.

	It also shows the item panel the design asks for: when the player is
	close to a stocked podium, a panel on screen shows that item's name,
	description and price, as well as the billboard above it.

	What the player is carrying is not drawn here any more: bought items
	are Tools in the Roblox Backpack (Server.Game.Core.Loadout), used by
	picking them, see ClientGame.Controllers.InventoryController.

	And it spins the item models on the podiums, locally, so the server
	does not have to replicate a rotation every frame.
]]

--[[
	What connects to this

	Calls:
	  ReplicatedStorage.Remotes.Functions.GetShopStock when it starts, in
	  case a shop was stocked before this client was listening.

	Listens on:
	  ReplicatedStorage.Remotes.Events.ShopStockChanged with
	  (ShopName, Stock), sent whenever a shop is stocked, bought from or
	  cleared, so when another player buys something this player's
	  billboard for that podium disappears too.
	  ReplicatedStorage.Remotes.Events.StatsUpdated for money (the price
	  colour).

	Reads:
	  Game.Data.ShopItemData for the item names, descriptions and rarities.
	  workspace.MainGameObj.ShopPodiums.Shop1 and Shop2, each holding
	  Podium1 to Podium4.

	Writes into (through ClientGame.UI.ShopUI, all designed in the
	editor):
	  ReplicatedStorage.Assets.UI.ShopBillboard, cloned per podium.
	  StarterGui.ShopUI.ItemInfo, the item panel.
	  StarterGui.ShopUI.Inventory, the carried items row.

	Started by:
	  ClientGame.ClientMain.

	The podium prompts use Z and the gate prompts use Z too, but they
	are far apart and only the nearest prompt in range is shown by
	Roblox, so holding the key near a podium never opens a gate.
	Failure messages ("Not enough money", "Already sold") come back on
	the Notify remote and are shown by RoomBannerController.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local ShopItemData = require(ReplicatedStorage.Modules.Game.Data.ShopItemData)
local ShopUI = require(script.Parent.Parent.UI.ShopUI)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")
local Functions = Remotes:WaitForChild("Functions")

local Player = Players.LocalPlayer

local ShopController = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

ShopController.Settings = {
	-- Degrees per second the item models turn, and how far they bob.
	SpinSpeed = 90,
	BobHeight = 0.35,
	BobSpeed = 2,
	DisplayName = "ShopDisplay",
	-- Studs from a podium within which its item panel shows.
	InfoDistance = 12,
	-- Seconds between the nearest podium checks.
	InfoRate = 0.15,
}

local ItemInfo: GuiObject? = nil
-- Podiums with stock, for the item panel: { Podium, ItemId, Price }.
local Stocked: { any } = {}

local Billboards: { [string]: { any } } = {}
local Money = 0
local Displays: { [Model]: CFrame } = {}

----------------------------------------------------------------------
-- BILLBOARDS
----------------------------------------------------------------------

local function PodiumOf(ShopName: string, Index: number): Model?
	local Map = workspace:FindFirstChild(RoomData.MapFolder)
	local Folder = Map and Map:FindFirstChild(RoomData.Folders.ShopPodiums)
	local Shop = Folder and Folder:FindFirstChild(ShopName)
	return Shop and Shop:FindFirstChild("Podium" .. Index) or nil
end

local function AnchorOf(Podium: Model): BasePart?
	local Prompt = Podium:FindFirstChildWhichIsA("ProximityPrompt", true)
	if Prompt and Prompt.Parent:IsA("BasePart") then
		return Prompt.Parent
	end
	return Podium:FindFirstChildWhichIsA("BasePart", true)
end

local function RefreshAffordable()
	for _, List in pairs(Billboards) do
		for _, Board in ipairs(List) do
			Board:SetAffordable(Money >= Board.Price)
		end
	end
end

local function OnStock(ShopName: string, Stock)
	if type(ShopName) ~= "string" then
		return
	end
	for _, Board in ipairs(Billboards[ShopName] or {}) do
		Board:Destroy()
	end
	Billboards[ShopName] = {}
	for Index = #Stocked, 1, -1 do
		if Stocked[Index].Shop == ShopName then
			table.remove(Stocked, Index)
		end
	end
	if type(Stock) ~= "table" then
		return
	end
	for _, Entry in ipairs(Stock) do
		local Podium = PodiumOf(ShopName, Entry.Podium)
		local Anchor = Podium and AnchorOf(Podium)
		if Anchor and ShopItemData.Items[Entry.ItemId] then
			local Board = ShopUI.new(Anchor, Entry.ItemId, Entry.Price)
			Board:SetAffordable(Money >= Entry.Price)
			table.insert(Billboards[ShopName], Board)
			table.insert(Stocked, { Shop = ShopName, Anchor = Anchor, ItemId = Entry.ItemId, Price = Entry.Price })
		end
	end
end

----------------------------------------------------------------------
-- INVENTORY
----------------------------------------------------------------------

local function OnStats(Snapshot)
	if type(Snapshot) ~= "table" then
		return
	end
	Money = Snapshot.Money or Money
	RefreshAffordable()
end

----------------------------------------------------------------------
-- SPIN
----------------------------------------------------------------------

local function Track(Model: Instance)
	if Model:IsA("Model") and Model.Name == ShopController.Settings.DisplayName then
		-- The parts can replicate a moment after the model itself, and
		-- the pivot is wrong until they have.
		local Deadline = os.clock() + 3
		while not Model:FindFirstChildWhichIsA("BasePart", true) and os.clock() < Deadline and Model.Parent do
			task.wait(0.05)
		end
		if not Model.Parent then
			return
		end
		Displays[Model] = Model:GetPivot()
		Model.AncestryChanged:Connect(function(_, Parent)
			if not Parent then
				Displays[Model] = nil
			end
		end)
	end
end

local function Spin()
	local Settings = ShopController.Settings
	local Now = os.clock()
	for Model, Base in pairs(Displays) do
		if Model.Parent then
			local Bob = math.sin(Now * Settings.BobSpeed) * Settings.BobHeight
			Model:PivotTo(Base * CFrame.new(0, Bob, 0) * CFrame.Angles(0, math.rad(Now * Settings.SpinSpeed), 0))
		else
			Displays[Model] = nil
		end
	end
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

-- Shows the item panel for the nearest stocked podium in range.
local function UpdateItemInfo()
	if not ItemInfo then
		return
	end
	local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
	local Best, BestDistance = nil, ShopController.Settings.InfoDistance
	if Root then
		for _, Entry in ipairs(Stocked) do
			if Entry.Anchor.Parent then
				local Distance = (Entry.Anchor.Position - Root.Position).Magnitude
				if Distance < BestDistance then
					Best, BestDistance = Entry, Distance
				end
			end
		end
	end
	if Best then
		ShopUI.Fill(ItemInfo, Best.ItemId, Best.Price, Money >= Best.Price)
	end
	ItemInfo.Visible = Best ~= nil
end

function ShopController.Init()
	local PlayerGui = Player:WaitForChild("PlayerGui")
	local Gui = PlayerGui:WaitForChild("ShopUI", 10)
	if not Gui then
		warn("[ShopController] no ShopUI ScreenGui in StarterGui")
		return
	end
	ItemInfo = Gui:WaitForChild("ItemInfo", 5)
	if ItemInfo then
		ItemInfo.Visible = false
	end
	-- The old on screen item row, from before the items became Tools
	-- in the Backpack.
	local OldRow = Gui:FindFirstChild("Inventory")
	if OldRow then
		OldRow.Visible = false
	end
	task.spawn(function()
		while true do
			task.wait(ShopController.Settings.InfoRate)
			pcall(UpdateItemInfo)
		end
	end)

	Events:WaitForChild("ShopStockChanged").OnClientEvent:Connect(OnStock)
	Events:WaitForChild("StatsUpdated").OnClientEvent:Connect(OnStats)

	-- Item models on the podiums, spun locally.
	local Map = workspace:WaitForChild(RoomData.MapFolder, 10)
	local Folder = Map and Map:WaitForChild(RoomData.Folders.ShopPodiums, 10)
	if Folder then
		for _, Descendant in ipairs(Folder:GetDescendants()) do
			task.spawn(Track, Descendant)
		end
		Folder.DescendantAdded:Connect(function(Descendant)
			task.spawn(Track, Descendant)
		end)
	end
	RunService.RenderStepped:Connect(Spin)

	-- Stock that went out before this client was listening.
	task.spawn(function()
		local GetShopStock = Functions:WaitForChild("GetShopStock", 10)
		if not GetShopStock then
			return
		end
		for _, Area in ipairs(RoomData.Areas) do
			if Area.Kind == "Shop" then
				local Ok, Stock = pcall(GetShopStock.InvokeServer, GetShopStock, Area.Name)
				if Ok and type(Stock) == "table" and #Stock > 0 then
					OnStock(Area.Name, Stock)
				end
			end
		end
	end)
end

return ShopController
