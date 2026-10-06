--[[
	UIFade

	Fades a whole piece of designed UI in or out. The UI is built in
	StarterGui in the editor, so every frame and label already has the
	transparency it was designed with. The first time a group is faded,
	each part's designed transparency is remembered in an attribute, and
	fading in always returns to exactly that, so the look set in the
	editor is never lost.
]]

--[[
	What connects to this

	Used by the client controllers that show and hide designed UI:
	ClientGame.Controllers.RoomBannerController for the area banner and
	toasts, and any other controller that wants the same fade.
]]

local TweenService = game:GetService("TweenService")

local UIFade = {}

local Properties = {
	TextLabel = { "TextTransparency", "TextStrokeTransparency", "BackgroundTransparency" },
	TextButton = { "TextTransparency", "TextStrokeTransparency", "BackgroundTransparency" },
	ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
	ImageButton = { "ImageTransparency", "BackgroundTransparency" },
	Frame = { "BackgroundTransparency" },
	UIStroke = { "Transparency" },
}

local function Parts(Root: Instance): { Instance }
	local List = { Root }
	for _, Item in ipairs(Root:GetDescendants()) do
		table.insert(List, Item)
	end
	return List
end

-- Remembers every designed transparency under Root, once.
function UIFade.Record(Root: Instance)
	for _, Item in ipairs(Parts(Root)) do
		local Props = Properties[Item.ClassName]
		if Props then
			for _, Prop in ipairs(Props) do
				local Key = "Designed" .. Prop
				if Item:GetAttribute(Key) == nil then
					Item:SetAttribute(Key, (Item :: any)[Prop])
				end
			end
		end
	end
end

-- Fades Root in (back to its designed look) or out (fully clear) over
-- Time seconds. Visible is also set, on at the start of a fade in and
-- off at the end of a fade out.
function UIFade.Fade(Root: GuiObject, Visible: boolean, Time: number)
	UIFade.Record(Root)
	local Token = (Root:GetAttribute("FadeToken") or 0) + 1
	Root:SetAttribute("FadeToken", Token)
	if Visible then
		Root.Visible = true
	end
	for _, Item in ipairs(Parts(Root)) do
		local Props = Properties[Item.ClassName]
		if Props then
			local Goal = {}
			for _, Prop in ipairs(Props) do
				Goal[Prop] = Visible and Item:GetAttribute("Designed" .. Prop) or 1
			end
			if Time > 0 then
				TweenService:Create(Item, TweenInfo.new(Time), Goal):Play()
			else
				for Prop, Value in pairs(Goal) do
					(Item :: any)[Prop] = Value
				end
			end
		end
	end
	if not Visible then
		task.delay(Time, function()
			if Root:GetAttribute("FadeToken") == Token then
				Root.Visible = false
			end
		end)
	end
end

return UIFade
