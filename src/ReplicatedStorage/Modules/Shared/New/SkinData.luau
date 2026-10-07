-- SkinData
-- The skins (character models) a player can wear as their Custom
-- Character, the faces and body colours the Customise gamepass unlocks,
-- the gamepasses themselves, and who counts as a developer.
--
-- The models live in ReplicatedStorage.Assets.Models.Characters. Each
-- skin below names its Model there; Shared.SkinBuilder turns that model
-- into a working R6 character (it repairs missing root parts and joints,
-- converts R15 models to R6 and strips every script out of it), so a new
-- skin is just: drop the model in that folder and add an entry here.
--
-- How a skin is unlocked (Unlock):
--   Free = true        everyone has it
--   Cash = 15000       bought with Cash (the skins popup and the shop)
--   Level = 20         unlocked at that player level
--   Pass = "VIP"       owning that gamepass (see Passes below) unlocks it
--                      too; with Level, either one is enough
--   Special = true     unlocked by something outside the lobby (a boss in
--                      the game place), described by its Unlock line in
--                      GameText.Characters.Skins. The game grants it by
--                      adding the key to OwnedSkins in the save.
-- Names, unlock lines, face and body part names and gamepass names and
-- descriptions are in Shared.GameText.Characters.
-- Anything bought or granted is saved as OwnedSkins[Key] = true.
--
-- Read by Server.Services.SkinService and CharacterService, and the
-- client's CharacterUI (skins popup) and LobbyMenu.

local UIIcons = require(script.Parent.UIIcons)
local GameText = require(script.Parent.GameText)

local SkinData = {}

-- The skin a new player wears. Cape and Plain are both free.
SkinData.Default = "Cape"

-- The order skins are shown in.
SkinData.Order = {
	"Cape", "Plain", "Noob", "Guest", "OriginalCharacter", "Monkey", "PizzaGuy",
	"BusinessMan", "HighschoolBoy", "StrangeDetective", "Guy", "1x1x1x1", "Hacker",
}

SkinData.Skins = {
	Cape = { Model = "Base", Cape = true, Unlock = { Free = true } },
	Plain = { Model = "Base", Unlock = { Free = true } },
	Noob = { Model = "Noob", Unlock = { Special = true } },
	Guest = { Model = "Guest", Unlock = { Special = true } },
	OriginalCharacter = { Model = "OriginalCharacter", Unlock = { Cash = 15000 } },
	Monkey = { Model = "Monkey", Unlock = { Level = 20 } },
	PizzaGuy = { Model = "PizzaGuy", Unlock = { Cash = 15000 } },
	BusinessMan = { Model = "BusinessMan", Unlock = { Cash = 10000 } },
	HighschoolBoy = { Model = "HighschoolBoy", Unlock = { Level = 30 } },
	StrangeDetective = { Model = "StrangeDetective", Unlock = { Cash = 50000 } },
	Guy = { Model = "Guy", Unlock = { Cash = 5000 } },
	["1x1x1x1"] = { Model = "1x1x1x1", Unlock = { Level = 100, Pass = "VIP" } },
	Hacker = { Model = "Hacker", Unlock = { Level = 50 } },
}

-- The cape worn by the Cape skin (a MeshPart in the same folder).
SkinData.CapeModel = "Cape"

-- Faces for the Customise gamepass.
--   Icon    the picture on the face button (Shared.UIIcons face_*)
--   Image   the decal texture put on the character's head: a face on a
--           transparent background, like Roblox's own faces (the icons
--           are UI tiles, not head textures). "" keeps the skin's own
--           face until there is one.
SkinData.Faces = {
	{ Key = "Smile", Icon = UIIcons.Get("face_smile"), Image = "rbxasset://textures/face.png" },
	{ Key = "Grin", Icon = UIIcons.Get("face_grin"), Image = "" },
	{ Key = "Focused", Icon = UIIcons.Get("face_focused"), Image = "" },
	{ Key = "Smug", Icon = UIIcons.Get("face_smug"), Image = "" },
	{ Key = "Chill", Icon = UIIcons.Get("face_chill"), Image = "" },
	{ Key = "Angry", Icon = UIIcons.Get("face_angry"), Image = "" },
}

-- Body parts the Customise gamepass can colour, in BodyColors terms.
SkinData.BodyParts = {
	{ Key = "Head", Property = "HeadColor3" },
	{ Key = "Torso", Property = "TorsoColor3" },
	{ Key = "LeftArm", Property = "LeftArmColor3" },
	{ Key = "RightArm", Property = "RightArmColor3" },
	{ Key = "LeftLeg", Property = "LeftLegColor3" },
	{ Key = "RightLeg", Property = "RightLegColor3" },
}

-- Gamepasses. GamePassId is the pass made on the Roblox website
-- (Creator Dashboard > the experience > Monetization > Passes); leave it
-- 0 until it exists and only Timebux buys it. 1 Robux = 1 Timebux, so
-- Timebux is the same number as Robux.
SkinData.PassOrder = { "AccessorySlots", "DoubleExp", "Customise", "VIP" }
SkinData.Passes = {
	AccessorySlots = { Robux = 299, GamePassId = 0 },
	DoubleExp = { Robux = 349, GamePassId = 0 },
	Customise = { Robux = 99, GamePassId = 0 },
	VIP = { Robux = 499, GamePassId = 0 },
}

-- The words from GameText.Characters.
do
	local Text = GameText.Table("Characters") or {}
	for Key, Skin in pairs(SkinData.Skins) do
		local Info = (Text.Skins or {})[Key] or {}
		Skin.DisplayName = Info.Name or Key
		Skin.Unlock.Text = Info.Unlock
	end
	for _, Face in ipairs(SkinData.Faces) do
		Face.DisplayName = (Text.Faces or {})[Face.Key] or Face.Key
	end
	for _, Part in ipairs(SkinData.BodyParts) do
		Part.DisplayName = (Text.BodyParts or {})[Part.Key] or Part.Key
	end
	for Key, Pass in pairs(SkinData.Passes) do
		local Info = (Text.Passes or {})[Key] or {}
		Pass.DisplayName = Info.Name or Key
		Pass.Description = Info.Description or ""
	end
end

-- Players who get the developer tools (the UNLOCK ALL button). By
-- UserId, so a name change doesn't matter. 1743245583 is ForsakenBlank.
SkinData.DevUserIds = { 1743245583 }

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

function SkinData.Get(Key: any)
	return type(Key) == "string" and SkinData.Skins[Key] or nil
end

function SkinData.IsDev(UserId: number): boolean
	return table.find(SkinData.DevUserIds, UserId) ~= nil
end

function SkinData.GetFace(Key: any)
	for _, Face in ipairs(SkinData.Faces) do
		if Face.Key == Key then
			return Face
		end
	end
	return nil
end

-- What the ownership checks need to know about a player:
--   Level        player level
--   OwnedSkins   { [Key] = true } from the save
--   Passes       { [PassKey] = true }, owned however (Robux or Timebux)
--   DevUnlockAll the developer's unlock-everything switch
export type Context = {
	Level: number,
	OwnedSkins: { [string]: any },
	Passes: { [string]: any },
	DevUnlockAll: boolean?,
}

function SkinData.IsOwned(Key: string, Context: Context): boolean
	local Skin = SkinData.Get(Key)
	if not Skin then
		return false
	end
	local Unlock = Skin.Unlock or {}
	if Unlock.Free or Context.DevUnlockAll then
		return true
	end
	if Context.OwnedSkins and Context.OwnedSkins[Key] then
		return true
	end
	if Unlock.Level and (Context.Level or 1) >= Unlock.Level then
		return true
	end
	if Unlock.Pass and Context.Passes and Context.Passes[Unlock.Pass] then
		return true
	end
	return false
end

-- The short line under a skin card: "OWNED", "$15,000", "LV 20"...
function SkinData.StatusText(Key: string, Context: Context, Equipped: boolean?): string
	local Skin = SkinData.Get(Key)
	if not Skin then
		return ""
	end
	if Equipped then
		return GameText.Get("Characters.Status.Equipped")
	end
	if SkinData.IsOwned(Key, Context) then
		return GameText.Get("Characters.Status.Owned")
	end
	local Unlock = Skin.Unlock or {}
	if Unlock.Text then
		return string.upper(Unlock.Text)
	end
	if Unlock.Level and Unlock.Pass then
		local Pass = SkinData.Passes[Unlock.Pass]
		return GameText.Get("Characters.Status.LevelOrPass", { Level = Unlock.Level, Pass = Pass and Pass.DisplayName or Unlock.Pass })
	end
	if Unlock.Level then
		return GameText.Get("Characters.Status.Level", { Level = Unlock.Level })
	end
	if Unlock.Cash then
		return GameText.Get("Characters.Status.Cash", { Price = SkinData.Comma(Unlock.Cash) })
	end
	return GameText.Get("Characters.Status.Locked")
end

-- 15000 -> "15,000"
function SkinData.Comma(Number: number): string
	local Text = tostring(math.floor(Number))
	local Sign, Digits = Text:match("^(%-?)(%d+)$")
	if not Digits then
		return Text
	end
	local Out = Digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if Out:sub(1, 1) == "," then
		Out = Out:sub(2)
	end
	return Sign .. Out
end

-- Colours are saved as "#RRGGBB" text, since the save can't hold Color3.
function SkinData.ToHex(Colour: Color3): string
	return "#" .. Colour:ToHex():upper()
end

function SkinData.FromHex(Hex: any): Color3?
	if type(Hex) ~= "string" then
		return nil
	end
	local Digits = Hex:gsub("#", "")
	if not Digits:match("^%x%x%x%x%x%x$") then
		return nil
	end
	local Ok, Colour = pcall(Color3.fromHex, Digits)
	return Ok and Colour or nil
end

return SkinData
