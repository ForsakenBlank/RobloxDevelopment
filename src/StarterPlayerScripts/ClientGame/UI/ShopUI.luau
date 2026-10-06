--[[
	ShopUI

	Drives the shop display. All of it is designed in the editor, this
	only fills in text and colours:

	  ReplicatedStorage.Assets.UI.ShopBillboard   the BillboardGui cloned
	      above each stocked podium, with the item name, rarity,
	      description, price and whether it is instant or goes in the
	      inventory. One instance of this class per podium.
	  StarterGui.ShopUI.ItemInfo   the on screen panel the design asks
	      for, showing the name, description and price of the item the
	      player is standing next to.

	Deciding when a billboard or the panel should show is
	ShopController's job. Carried items are Tools in the Roblox Backpack
	(see InventoryController), so there is no item row here. The buying itself is the
	podium's ProximityPrompt, handled on the server.
]]

--[[
	What connects to this

	Created and driven by:
	  ClientGame.Controllers.ShopController.

	Reads:
	  Game.Data.ShopItemData for the display name, description and
	  rarity colour of the item id it was given. The price comes from the
	  server stock, not from here, because the difficulty multiplier has
	  already been applied to it.

	The server colours the podium's CarpetRarity part from the same
	rarity table, so the billboard and the carpet always agree.

	Billboards are destroyed, not hidden, when the item is bought or the
	shop is cleared, so a long run does not leave a pile of them.
	MaxDistance on the BillboardGui does the distance fade for free.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopItemData = require(ReplicatedStorage.Modules.Game.Data.ShopItemData)

local ShopUI = {}
ShopUI.__index = ShopUI

ShopUI.Settings = {
	AffordableColour = Color3.fromRGB(110, 255, 130),
	UnaffordableColour = Color3.fromRGB(255, 90, 90),
	Template = "ShopBillboard",
}

local function Set(Root: Instance, Name: string, Props: { [string]: any })
	local Item = Root:FindFirstChild(Name, true)
	if Item then
		for Key, Value in pairs(Props) do
			(Item :: any)[Key] = Value
		end
	end
end

-- Colours every part named Edge under Root, the rarity stripe.
local function Tint(Root: Instance, Colour: Color3)
	for _, Item in ipairs(Root:GetDescendants()) do
		if Item.Name == "Edge" and Item:IsA("GuiObject") then
			Item.BackgroundColor3 = Colour
		end
	end
end

-- Fills any designed item display (the billboard or the panel) with
-- an item.
function ShopUI.Fill(Root: Instance, ItemId: string, Price: number, Affordable: boolean)
	local Item = ShopItemData.Items[ItemId]
	local Rarity = ShopItemData.GetRarity(ItemId)
	Set(Root, "ItemName", { Text = Item and Item.DisplayName or ItemId, TextColor3 = Rarity.Colour })
	Set(Root, "Rarity", { Text = string.upper(Rarity.DisplayName), TextColor3 = Rarity.Colour })
	Set(Root, "Description", { Text = Item and Item.Description or "" })
	Set(Root, "Price", {
		Text = "$" .. tostring(Price),
		TextColor3 = Affordable and ShopUI.Settings.AffordableColour or ShopUI.Settings.UnaffordableColour,
	})
	if Item and Root:FindFirstChild("Hint", true) and Root:IsA("BillboardGui") then
		Set(Root, "Hint", { Text = Item.UseType == "Instant" and "Instant" or "Inventory" })
	end
	Tint(Root, Rarity.Colour)
end

----------------------------------------------------------------------
-- PODIUM BILLBOARD
----------------------------------------------------------------------

-- Adornee is the part the billboard floats over.
function ShopUI.new(Adornee: BasePart, ItemId: string, Price: number)
	local self = setmetatable({}, ShopUI)
	self.ItemId = ItemId
	self.Price = Price
	local Folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI")
	local Template = Folder and Folder:FindFirstChild(ShopUI.Settings.Template)
	if not Template then
		warn("[ShopUI] no " .. ShopUI.Settings.Template .. " template in ReplicatedStorage.Assets.UI")
		return self
	end
	self.Gui = Template:Clone()
	self.Gui.Adornee = Adornee
	ShopUI.Fill(self.Gui, ItemId, Price, true)
	self.Gui.Parent = Adornee
	return self
end

function ShopUI:SetAffordable(Affordable: boolean)
	if self.Gui then
		Set(self.Gui, "Price", {
			TextColor3 = Affordable and ShopUI.Settings.AffordableColour or ShopUI.Settings.UnaffordableColour,
		})
	end
end

function ShopUI:Destroy()
	if self.Gui then
		self.Gui:Destroy()
		self.Gui = nil
	end
end

return ShopUI
