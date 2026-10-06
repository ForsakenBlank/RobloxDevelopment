--[[
	ShopManager

	Runs the two shop areas. Each shop has 4 podiums in the map, so when
	the run reaches a shop this rolls 4 random items from ShopItemData,
	works out their prices with the difficulty multiplier, and puts one
	on each podium.

	Each podium model has a CarpetRarity part in it, so the roll picks a
	rarity as well as an item, and this sets that part's colour to match.
	That gives the player a read on what is worth walking over to before
	they get close enough for the billboard.

	It also handles the buying. This is BuyItem from the function plan:
	check the player has enough money, take the money, give them the
	item, then clear the podium so it cannot be bought again. The check,
	the payment and the clear all happen in one go on the server with no
	yield in between, so two players buying the same podium in the same
	frame cannot both get it.

	Both shops use the same code, they just roll different stock, which
	is what the design asks for.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.ShopItemData for the item list, base prices and the
	  rarity of each item.
	  Game.Config.DifficultyConfig, through Game.Shared.RunConfig, for
	  the ShopPrice multiplier.
	  workspace.MainGameObj.ShopPodiums.Shop1 and Shop2, which each hold
	  Podium1 to Podium4. Each podium is a Model with a CarpetRarity part,
	  a small part with a ProximityPrompt that marks where the item sits,
	  and the parts of the podium itself.

	Told to stock a shop by:
	  Server.Game.Rooms.RoomManager, when the run reaches Shop1 or Shop2,
	  and to clear everything by RoomManager.Reset.

	Calls:
	  Server.Game.Shop.ShopItems to run or file the item once a purchase
	  has gone through. This module handles the money and the podium,
	  ShopItems handles what the item does.
	  Server.Game.Core.PlayerStats to check and take the money, through
	  its methods so the HUD updates.

	Buying:
	  The podium's own ProximityPrompt is the buy button. Its Triggered
	  event fires on the server with the player, so the client never
	  sends a price or an item, only "I held the key on this podium".
	  ReplicatedStorage.Remotes.Functions.RequestPurchase does the same
	  thing for a client that wants to buy from UI, taking only the
	  shop name and podium number, and returns (Ok, Reason).
	  ReplicatedStorage.Remotes.Functions.GetShopStock returns a shop's
	  stock so a client arriving in the shop can build its billboards.

	Sends:
	  ReplicatedStorage.Remotes.Events.ShopStockChanged with
	  (ShopName, Stock) whenever a shop is stocked, bought from or
	  cleared, so every player's billboards stay in step.
	  ReplicatedStorage.Remotes.Events.Notify with the reason a purchase
	  failed, which tells "Not enough money" apart from "Already sold".

	The item models come from ServerStorage.Assets.ShopItems, named to
	match each item id. An item with no model gets a simple coloured
	placeholder so the podium is never empty. The model is destroyed
	when the item is bought.

	Money is per player, so one player buying does not affect what the
	others can afford, but the 4 podiums are shared for the room.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local ShopItemData = require(ReplicatedStorage.Modules.Game.Data.ShopItemData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local ShopItems = require(script.Parent.ShopItems)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShopStockChanged = Remotes.Events:WaitForChild("ShopStockChanged")
local Notify = Remotes.Events:WaitForChild("Notify")
local RequestPurchase = Remotes.Functions:WaitForChild("RequestPurchase")
local GetShopStock = Remotes.Functions:WaitForChild("GetShopStock")

local ShopManager = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

ShopManager.Settings = {
	-- The buy prompt. Z because E is the ability key and F is Leap.
	PromptKey = Enum.KeyCode.Z,
	PromptGamepadKey = Enum.KeyCode.ButtonY,
	PromptDistance = 10,
	-- Carpet colour on an empty or sold podium.
	EmptyCarpetColour = Color3.fromRGB(60, 60, 60),
	-- Name given to the item model on a podium, which the client spins.
	DisplayName = "ShopDisplay",
	-- Placeholder look for an item with no model, keyed by item id.
	-- Anything not listed uses its rarity colour.
	PlaceholderColours = {
		HealthPotion = Color3.fromRGB(230, 60, 60),
		EnergyPotion = Color3.fromRGB(70, 160, 255),
		DamagePotion = Color3.fromRGB(255, 120, 40),
		Mushroom = Color3.fromRGB(200, 60, 200),
		Molotov = Color3.fromRGB(120, 200, 90),
		HealthArtifact = Color3.fromRGB(255, 80, 120),
		EnergyArtifact = Color3.fromRGB(255, 230, 80),
		SpeedArtifact = Color3.fromRGB(140, 255, 220),
		JumpArtifact = Color3.fromRGB(240, 240, 255),
	},
	PlaceholderSize = 1.6,
}

-- Per shop: { [PodiumIndex] = { ItemId, Price, Rarity, Sold, Podium,
-- Model, Prompt } }
local Stock: { [string]: { any } } = {}
-- Per player, how many of each item they bought this run.
local Bought: { [Player]: { [string]: number } } = {}
-- Carpet colours as the map had them, restored on clear.
local OriginalCarpet: { [BasePart]: Color3 } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function Log(Text: string)
	if GameConfig.Debug.LogShop then
		print("[ShopManager] " .. Text)
	end
end

local function Podiums(ShopName: string): { Model }
	local Folder = RoomData.GetFolder("ShopPodiums")
	local ShopFolder = Folder and Folder:FindFirstChild(ShopName)
	local List = {}
	if ShopFolder then
		for Index = 1, 16 do
			local Podium = ShopFolder:FindFirstChild("Podium" .. Index)
			if Podium then
				table.insert(List, Podium)
			end
		end
	end
	return List
end

local function PromptOf(Podium: Model): ProximityPrompt?
	return Podium:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function CarpetOf(Podium: Model): BasePart?
	local Carpet = Podium:FindFirstChild(ShopItemData.Shop.CarpetPartName, true)
	return Carpet and Carpet:IsA("BasePart") and Carpet or nil
end

-- Where the item sits: an ItemPoint attachment if there is one, the
-- prompt's part otherwise, the top of the carpet as a last resort.
local function ItemPosition(Podium: Model): Vector3
	local Point = Podium:FindFirstChild(ShopItemData.Shop.ItemAttachmentName, true)
	if Point and Point:IsA("Attachment") then
		return Point.WorldPosition
	end
	local Prompt = PromptOf(Podium)
	if Prompt and Prompt.Parent:IsA("BasePart") then
		return Prompt.Parent.Position
	end
	local Carpet = CarpetOf(Podium)
	if Carpet then
		return Carpet.Position + Vector3.new(0, 2, 0)
	end
	return Podium:GetPivot().Position + Vector3.new(0, 4, 0)
end

local function PriceFor(ItemId: string): number
	local Item = ShopItemData.Items[ItemId]
	local Rarity = ShopItemData.GetRarity(ItemId)
	local Run = RunConfig.Get()
	local Multiplier = (Rarity.PriceMultiplier or 1) * (Run and Run.Difficulty and Run.Difficulty.ShopPrice or 1)
	local Rounding = ShopItemData.Shop.PriceRounding or 1
	local Price = Item.Price * Multiplier
	return math.max(Rounding, math.floor(Price / Rounding + 0.5) * Rounding)
end

-- Rolls Count distinct items by weight.
local function Roll(Count: number): { string }
	local Pool = {}
	for _, Id in ipairs(ShopItemData.GetEnabledIds()) do
		local Weight = ShopItemData.GetWeight(Id)
		if Weight > 0 then
			table.insert(Pool, { Id = Id, Weight = Weight })
		end
	end
	local Picked = {}
	for _ = 1, Count do
		local Total = 0
		for _, Entry in ipairs(Pool) do
			Total += Entry.Weight
		end
		if Total <= 0 then
			break
		end
		local Pick = math.random() * Total
		for Index, Entry in ipairs(Pool) do
			Pick -= Entry.Weight
			if Pick <= 0 then
				table.insert(Picked, Entry.Id)
				if not ShopItemData.Shop.AllowDuplicates then
					table.remove(Pool, Index)
				end
				break
			end
		end
	end
	return Picked
end

local function BuildDisplay(ItemId: string, At: Vector3): Model
	local Template = ServerStorage:FindFirstChild("Assets")
		and ServerStorage.Assets:FindFirstChild("ShopItems")
		and ServerStorage.Assets.ShopItems:FindFirstChild(ShopItemData.Items[ItemId].ModelName or ItemId)
	local Model
	if Template then
		Model = Template:Clone()
	else
		Model = Instance.new("Model")
		local Item = ShopItemData.Items[ItemId]
		local Colour = ShopManager.Settings.PlaceholderColours[ItemId] or ShopItemData.GetRarity(ItemId).Colour
		local Size = ShopManager.Settings.PlaceholderSize
		local Part = Instance.new("Part")
		Part.Name = "Handle"
		if Item.UseType == "Instant" then
			Part.Shape = Enum.PartType.Ball
			Part.Size = Vector3.one * Size
			Part.Material = Enum.Material.Neon
		else
			Part.Shape = Enum.PartType.Cylinder
			Part.Size = Vector3.new(Size, Size * 0.7, Size * 0.7)
			Part.Material = Enum.Material.Glass
			Part.Transparency = 0.15
		end
		Part.Color = Colour
		Part.Parent = Model
		local Light = Instance.new("PointLight")
		Light.Color = Colour
		Light.Range = 8
		Light.Brightness = 1.5
		Light.Parent = Part
		Model.PrimaryPart = Part
	end
	for _, Part in ipairs(Model:GetDescendants()) do
		if Part:IsA("BasePart") then
			Part.Anchored = true
			Part.CanCollide = false
			Part.CanQuery = false
			Part.CanTouch = false
		end
	end
	Model.Name = ShopManager.Settings.DisplayName
	Model:SetAttribute("ItemId", ItemId)
	Model:PivotTo(CFrame.new(At))
	return Model
end

-- What the clients get for a shop: a list of the unsold podiums, each
-- with its podium number. A list rather than a table keyed by podium,
-- because gaps in number keys do not survive a remote.
local function PublicStock(ShopName: string)
	local List = {}
	for Index, Entry in pairs(Stock[ShopName] or {}) do
		if not Entry.Sold then
			table.insert(List, { Podium = Index, ItemId = Entry.ItemId, Price = Entry.Price, Rarity = Entry.Rarity })
		end
	end
	return List
end

local function SendStock(ShopName: string)
	ShopStockChanged:FireAllClients(ShopName, PublicStock(ShopName))
end

local function ClearPodium(Entry)
	if Entry.Model then
		Entry.Model:Destroy()
		Entry.Model = nil
	end
	if Entry.Prompt then
		Entry.Prompt.Enabled = false
	end
	local Carpet = CarpetOf(Entry.Podium)
	if Carpet then
		Carpet.Color = ShopManager.Settings.EmptyCarpetColour
	end
end

----------------------------------------------------------------------
-- BUYING
----------------------------------------------------------------------

-- Buys the item on a podium. Returns (Ok, Reason).
function ShopManager.Purchase(Player: Player, ShopName: string, PodiumIndex: number): (boolean, string?)
	local Entry = Stock[ShopName] and Stock[ShopName][PodiumIndex]
	if not Entry then
		return false, "Nothing to buy here"
	end
	if Entry.Sold then
		return false, "Already sold"
	end

	local RoomManager = require(script.Parent.Parent.Rooms.RoomManager)
	if RoomManager.GetCurrentArea() ~= ShopName then
		return false, "This shop is closed"
	end

	local Stats = PlayerStats.Get(Player)
	if not Stats or not Stats:IsAlive() then
		return false, "You are dead"
	end

	local Item = ShopItemData.Items[Entry.ItemId]
	local Counts = Bought[Player] or {}
	if Item.MaxPerRun and (Counts[Entry.ItemId] or 0) >= Item.MaxPerRun then
		return false, "You cannot carry more of those"
	end
	local Fits, Why = ShopItems.CanReceive(Player, Entry.ItemId)
	if not Fits then
		return false, Why
	end
	if not Stats:CanAffordMoney(Entry.Price) then
		return false, "Not enough money"
	end

	-- Check, pay, mark sold, then give. No yields in between.
	if not Stats:SpendMoney(Entry.Price) then
		return false, "Not enough money"
	end
	Entry.Sold = true
	Counts[Entry.ItemId] = (Counts[Entry.ItemId] or 0) + 1
	Bought[Player] = Counts
	ClearPodium(Entry)

	ShopItems.Give(Player, Entry.ItemId)
	Log(string.format("%s bought %s for %d", Player.Name, Entry.ItemId, Entry.Price))
	SendStock(ShopName)
	return true, nil
end

local function PurchaseAndTell(Player: Player, ShopName: string, PodiumIndex: number)
	local Ok, Reason = ShopManager.Purchase(Player, ShopName, PodiumIndex)
	local Entry = Stock[ShopName] and Stock[ShopName][PodiumIndex]
	if Ok and Entry then
		Notify:FireClient(Player, "Bought " .. ShopItemData.Items[Entry.ItemId].DisplayName)
		CombatFX.SendTo(Player, "PlaySound", nil, { Name = "Purchase" })
		local Item = ShopItemData.Items[Entry.ItemId]
		if Item.UseType == "Instant" and Item.Sound and Player.Character then
			CombatFX.Broadcast("PlaySound", Player.Character, { Name = Item.Sound })
		end
	elseif Reason then
		Notify:FireClient(Player, Reason)
		CombatFX.SendTo(Player, "PlaySound", nil, { Name = "UIClick" })
	end
	return Ok, Reason
end

----------------------------------------------------------------------
-- STOCKING
----------------------------------------------------------------------

-- Rolls and places the stock for a shop area.
function ShopManager.StockShop(ShopName: string)
	ShopManager.ClearShop(ShopName)
	local List = Podiums(ShopName)
	if #List == 0 then
		warn("[ShopManager] no podiums for " .. ShopName)
		return
	end
	local Area = RoomData.GetArea(ShopName)
	local Count = math.min(#List, Area and Area.Podiums or ShopItemData.Shop.PodiumCount)
	local Items = Roll(Count)

	local ShopStock = {}
	for Index, Podium in ipairs(List) do
		local ItemId = Items[Index]
		local Prompt = PromptOf(Podium)
		local Carpet = CarpetOf(Podium)
		if Carpet and not OriginalCarpet[Carpet] then
			OriginalCarpet[Carpet] = Carpet.Color
		end
		if not ItemId then
			if Prompt then
				Prompt.Enabled = false
			end
			continue
		end

		local Item = ShopItemData.Items[ItemId]
		local Rarity = ShopItemData.GetRarity(ItemId)
		local Price = PriceFor(ItemId)
		local Model = BuildDisplay(ItemId, ItemPosition(Podium) + Vector3.new(0, 1, 0))
		Model.Parent = Podium

		if Carpet then
			Carpet.Color = Rarity.Colour
		end
		if Prompt then
			Prompt.Enabled = true
			Prompt.ActionText = string.format("%s ($%d)", ShopItemData.Shop.PromptText or "Buy", Price)
			Prompt.ObjectText = Item.DisplayName
			Prompt.HoldDuration = ShopItemData.Shop.PromptHoldTime or 0.5
			Prompt.KeyboardKeyCode = ShopManager.Settings.PromptKey
			Prompt.GamepadKeyCode = ShopManager.Settings.PromptGamepadKey
			Prompt.MaxActivationDistance = ShopManager.Settings.PromptDistance
			Prompt.RequiresLineOfSight = false
		end

		ShopStock[Index] = {
			ItemId = ItemId,
			Price = Price,
			Rarity = Item.Rarity,
			Sold = false,
			Podium = Podium,
			Model = Model,
			Prompt = Prompt,
		}
	end
	Stock[ShopName] = ShopStock
	Log(ShopName .. " stocked with " .. table.concat(Items, ", "))
	SendStock(ShopName)
end

-- Empties one shop.
function ShopManager.ClearShop(ShopName: string)
	for _, Entry in pairs(Stock[ShopName] or {}) do
		ClearPodium(Entry)
	end
	Stock[ShopName] = nil
	for _, Podium in ipairs(Podiums(ShopName)) do
		local Prompt = PromptOf(Podium)
		if Prompt then
			Prompt.Enabled = false
		end
		local Carpet = CarpetOf(Podium)
		if Carpet and OriginalCarpet[Carpet] then
			Carpet.Color = OriginalCarpet[Carpet]
		end
		for _, Child in ipairs(Podium:GetChildren()) do
			if Child.Name == ShopManager.Settings.DisplayName then
				Child:Destroy()
			end
		end
	end
	SendStock(ShopName)
end

-- Empties every shop and forgets what everyone bought, for a new run.
function ShopManager.ClearAll()
	for _, Area in ipairs(RoomData.Areas) do
		if Area.Kind == "Shop" then
			ShopManager.ClearShop(Area.Name)
		end
	end
	Bought = {}
end

function ShopManager.GetStock(ShopName: string)
	return PublicStock(ShopName)
end

function ShopManager.Init()
	ShopItems.Init()

	-- Hook every podium prompt once. Which shop and podium it is comes
	-- from where it sits in the map, never from the client.
	for _, Area in ipairs(RoomData.Areas) do
		if Area.Kind == "Shop" then
			for Index, Podium in ipairs(Podiums(Area.Name)) do
				local Prompt = PromptOf(Podium)
				if Prompt then
					Prompt.Enabled = false
					Prompt.Triggered:Connect(function(Player)
						PurchaseAndTell(Player, Area.Name, Index)
					end)
				end
			end
		end
	end

	RequestPurchase.OnServerInvoke = function(Player, ShopName, PodiumIndex)
		if type(ShopName) ~= "string" or type(PodiumIndex) ~= "number" then
			return false, "Bad request"
		end
		return PurchaseAndTell(Player, ShopName, PodiumIndex)
	end
	GetShopStock.OnServerInvoke = function(Player, ShopName)
		if type(ShopName) ~= "string" then
			return nil
		end
		return PublicStock(ShopName)
	end

	Players.PlayerRemoving:Connect(function(Player)
		Bought[Player] = nil
	end)

	ShopManager.ClearAll()
end

return ShopManager
