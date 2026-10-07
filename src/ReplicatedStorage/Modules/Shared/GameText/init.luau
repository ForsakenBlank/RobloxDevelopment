-- GameText
-- Every word the players see, in one place. Change any text in the
-- modules under this one and it changes in the game: menu titles,
-- buttons, messages, item, core, map and skin descriptions, and the
-- Info pages in Settings.
--
--   Common       words used all over (BACK, EQUIP, LV 5...)
--   Menu         the lobby menu and HUD
--   Play, Squad, Character, Loadout, CoreMenu, Stats, Shop, Settings
--                each lobby screen
--   Buy          the gamepass buy prompt
--   Info         the Info tab in Settings (the game and equipment guides)
--   Messages     pop-up messages, mostly the server's replies
--   Items        weapons, abilities, armour, accessories, stat names
--   Cores        the four cores
--   Characters   skins, faces, body parts, gamepasses
--   Maps         maps, areas, difficulties
--
-- Anything in {curly brackets} is filled in by the game: "LV {Level}"
-- shows as "LV 12". Keep those words as they are; move them around or
-- drop them freely.
--
-- Scripts read text with GameText.Get("Shop.Title") or, with blanks,
-- GameText.Get("Common.Level", { Level = 12 }). The lobby's screens also
-- keep each label's key (the TextKey attribute), so editing a line here
-- changes it next time the game runs without rebuilding the UI.

local GameText = {}

for _, Child in ipairs(script:GetChildren()) do
	if Child:IsA("ModuleScript") then
		GameText[Child.Name] = require(Child) :: any
	end
end

local Warned = {}

-- The text at Path ("Shop.Tabs.Characters"), with any {Name} blanks
-- filled from Vars. A missing path shows the path itself, and warns
-- once, so it's easy to spot.
function GameText.Get(Path: string, Vars: { [string]: any }?): string
	local Node: any = GameText
	for Part in string.gmatch(Path, "[^%.]+") do
		if type(Node) ~= "table" then
			Node = nil
			break
		end
		Node = Node[Part]
	end
	if type(Node) ~= "string" then
		if not Warned[Path] then
			Warned[Path] = true
			warn("[GameText] missing text: " .. Path)
		end
		return Path
	end
	if Vars then
		return GameText.Fill(Node, Vars)
	end
	return Node
end

-- Fills {Name} blanks in any text.
function GameText.Fill(Text: string, Vars: { [string]: any }): string
	return (string.gsub(Text, "{(%w+)}", function(Name)
		local Value = Vars[Name]
		if Value == nil then
			return "{" .. Name .. "}"
		end
		return tostring(Value)
	end))
end

-- The table at Path (for lists like Info pages), or nil.
function GameText.Table(Path: string): any
	local Node: any = GameText
	for Part in string.gmatch(Path, "[^%.]+") do
		if type(Node) ~= "table" then
			return nil
		end
		Node = Node[Part]
	end
	return type(Node) == "table" and Node or nil
end

return GameText
