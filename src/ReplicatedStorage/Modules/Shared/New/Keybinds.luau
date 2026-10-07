-- Keybinds
-- Every control a player can change (Settings > CONTROLS), its default
-- key, and the player's own keys.
--
-- Saved as Keybinds in the save (Shared.PlayerDataTemplate): only the
-- controls a player changed, as { [Action] = "KeyName" }, so a new
-- default reaches everyone who never changed that one. A key is saved
-- by name: an Enum.KeyCode name ("Q", "LeftShift") or MouseButton1,
-- MouseButton2 or MouseButton3.
--
-- Place says where a control works: "Lobby", "Game" (a run) or "Both".
-- Two controls can't share a key if they can be pressed in the same
-- place, so setting a key that's taken swaps the two (SetKey). Movement
-- controls follow Shared.MovementSettings: one whose ability is switched
-- off there isn't listed (Shown). WASD, Space, Tab, Esc and the other
-- keys Roblox keeps for itself can't be used (Reserved), and the left
-- mouse button only works for the attacks.
--
-- The server checks every change with it (Server.Services.
-- SettingsService). On a client it is also the live key map: Load puts
-- the save's keys in, Get, Is and Label answer for a control, and
-- Changed fires when they change. The lobby's menus and movement read
-- it, and the game place's combat and movement should too (copy this
-- module there), so one change applies everywhere. The control names
-- and descriptions are in Shared.GameText.Settings.Keybinds.

local MovementSettings = require(script.Parent.MovementSettings)

local Keybinds = {}

-- The sections on the CONTROLS tab, in order.
Keybinds.Groups = { "Menus", "Movement", "Combat" }

--   Key       the control's name (saved, and read by the scripts)
--   Group     its section on the CONTROLS tab
--   Place     "Lobby", "Game" or "Both"
--   Default   its key
--   Ability   a movement ability in MovementSettings.Abilities: only
--             listed while it is Enabled there
--   Shares    another control it may share a key with (the leap and the
--             glide are both F: one is on the ground, one in the air)
--   Mouse     the left mouse button can be used (attacks)
Keybinds.Actions = {
	{ Key = "ToggleMenu", Group = "Menus", Place = "Lobby", Default = "B" },
	{ Key = "MenuButton1", Group = "Menus", Place = "Lobby", Default = "One" },
	{ Key = "MenuButton2", Group = "Menus", Place = "Lobby", Default = "Two" },
	{ Key = "MenuButton3", Group = "Menus", Place = "Lobby", Default = "Three" },
	{ Key = "MenuButton4", Group = "Menus", Place = "Lobby", Default = "Four" },
	{ Key = "MenuButton5", Group = "Menus", Place = "Lobby", Default = "Five" },
	{ Key = "MenuButton6", Group = "Menus", Place = "Lobby", Default = "Six" },
	{ Key = "OpenLoadout", Group = "Menus", Place = "Lobby", Default = "L" },
	-- Was C, which is also Slide.
	{ Key = "OpenCore", Group = "Menus", Place = "Lobby", Default = "J" },
	{ Key = "OpenStats", Group = "Menus", Place = "Lobby", Default = "K" },
	{ Key = "OpenShop", Group = "Menus", Place = "Lobby", Default = "N" },
	{ Key = "OpenSettings", Group = "Menus", Place = "Lobby", Default = "P" },
	{ Key = "StartRun", Group = "Menus", Place = "Lobby", Default = "Return" },

	{ Key = "Run", Group = "Movement", Place = "Both", Default = "LeftShift", Ability = "Run" },
	{ Key = "Dash", Group = "Movement", Place = "Both", Default = "Q", Ability = "Dash" },
	{ Key = "Slide", Group = "Movement", Place = "Both", Default = "C", Ability = "Slide" },
	{ Key = "Glide", Group = "Movement", Place = "Both", Default = "F", Ability = "Glide" },
	{ Key = "Leap", Group = "Movement", Place = "Both", Default = "F", Ability = "Leap", Shares = "Glide" },
	{ Key = "Crouch", Group = "Movement", Place = "Both", Default = "V", Ability = "Crouch" },
	{ Key = "Crawl", Group = "Movement", Place = "Both", Default = "X", Ability = "Crawl" },
	{ Key = "Sit", Group = "Movement", Place = "Both", Default = "M", Ability = "Sit" },
	{ Key = "ShiftLock", Group = "Movement", Place = "Both", Default = "LeftControl" },

	{ Key = "Attack", Group = "Combat", Place = "Game", Default = "MouseButton1", Mouse = true },
	{ Key = "AltAttack", Group = "Combat", Place = "Game", Default = "MouseButton2", Mouse = true },
	{ Key = "SwapWeapon", Group = "Combat", Place = "Game", Default = "R" },
	{ Key = "UseAbility", Group = "Combat", Place = "Game", Default = "E" },
	{ Key = "SwapAbility", Group = "Combat", Place = "Game", Default = "G" },
	-- The core's ultimate (core level 5). Not in the game place yet.
	{ Key = "Ultimate", Group = "Combat", Place = "Game", Default = "T" },
	-- Gates and the shop in a run (their ProximityPrompts).
	{ Key = "Interact", Group = "Combat", Place = "Game", Default = "Z" },
}

-- Keys Roblox keeps for itself (moving, jumping, chat, the menu, the
-- player list, camera zoom, the developer console...).
Keybinds.Reserved = {
	W = true, A = true, S = true, D = true,
	Up = true, Down = true, Left = true, Right = true,
	Space = true, Escape = true, Tab = true, Slash = true, Backquote = true,
	I = true, O = true,
	F9 = true, F10 = true, F11 = true, F12 = true,
	LeftSuper = true, RightSuper = true, LeftMeta = true, RightMeta = true,
	Menu = true, Print = true, SysReq = true, Pause = true, Unknown = true,
}

-- Short names for key badges and the CONTROLS tab.
local Labels = {
	LeftShift = "LSHIFT", RightShift = "RSHIFT",
	LeftControl = "LCTRL", RightControl = "RCTRL",
	LeftAlt = "LALT", RightAlt = "RALT",
	Return = "ENTER", KeypadEnter = "ENTER",
	Backspace = "BKSP", Delete = "DEL", Insert = "INS",
	PageUp = "PGUP", PageDown = "PGDN", CapsLock = "CAPS",
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
	Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	KeypadZero = "NUM 0", KeypadOne = "NUM 1", KeypadTwo = "NUM 2", KeypadThree = "NUM 3",
	KeypadFour = "NUM 4", KeypadFive = "NUM 5", KeypadSix = "NUM 6", KeypadSeven = "NUM 7",
	KeypadEight = "NUM 8", KeypadNine = "NUM 9",
	Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]",
	Semicolon = ";", Quote = "'", Comma = ",", Period = ".", BackSlash = "\\",
	MouseButton1 = "MB1", MouseButton2 = "MB2", MouseButton3 = "MB3",
}

local ByKey = {}
for Order, Action in ipairs(Keybinds.Actions) do
	Action.Order = Order
	ByKey[Action.Key] = Action
end

local Places = {
	Lobby = { Lobby = true },
	Game = { Game = true },
	Both = { Lobby = true, Game = true },
}

----------------------------------------------------------------------
-- CHECKING
----------------------------------------------------------------------

function Keybinds.GetAction(Key: any)
	return type(Key) == "string" and ByKey[Key] or nil
end

-- Whether a control is listed: movement whose ability is switched off in
-- MovementSettings isn't.
function Keybinds.Shown(Action: any): boolean
	if Action.Ability then
		local Ability = MovementSettings.Abilities[Action.Ability]
		return Ability ~= nil and Ability.Enabled ~= false
	end
	return true
end

local function IsMouse(Name: string): boolean
	return Name == "MouseButton1" or Name == "MouseButton2" or Name == "MouseButton3"
end

local function KeyCodeFor(Name: string): Enum.KeyCode?
	local Ok, Code = pcall(function()
		return (Enum.KeyCode :: any)[Name]
	end)
	return Ok and Code or nil
end

function Keybinds.IsReserved(Name: any): boolean
	return type(Name) == "string" and Keybinds.Reserved[Name] == true
end

-- Whether Name is a key or button that can be used for a control.
function Keybinds.IsAllowed(ActionKey: any, Name: any): boolean
	local Action = Keybinds.GetAction(ActionKey)
	if not Action or type(Name) ~= "string" then
		return false
	end
	if Name == "MouseButton1" then
		return Action.Mouse == true
	end
	if IsMouse(Name) then
		return true
	end
	if Keybinds.Reserved[Name] then
		return false
	end
	-- Gamepad buttons aren't keyboard controls.
	if string.find(Name, "^Button") or string.find(Name, "^Thumbstick") or string.find(Name, "^DPad") then
		return false
	end
	return KeyCodeFor(Name) ~= nil
end

-- Whether two controls can be pressed in the same place (so can't share).
local function Overlap(A: any, B: any): boolean
	if A.Shares == B.Key or B.Shares == A.Key then
		return false
	end
	for Place in pairs(Places[A.Place] or {}) do
		if (Places[B.Place] or {})[Place] then
			return true
		end
	end
	return false
end

-- Every control's key, from a saved Keybinds table (defaults filled in,
-- anything that isn't allowed any more dropped).
function Keybinds.Read(Saved: any): { [string]: string }
	local Map = {}
	for _, Action in ipairs(Keybinds.Actions) do
		local Name = type(Saved) == "table" and Saved[Action.Key] or nil
		if Name ~= nil and Keybinds.IsAllowed(Action.Key, Name) then
			Map[Action.Key] = Name
		else
			Map[Action.Key] = Action.Default
		end
	end
	return Map
end

-- The listed controls that share a key with ActionKey where both work.
function Keybinds.Conflicts(Map: { [string]: string }, ActionKey: string): { string }
	local Action = Keybinds.GetAction(ActionKey)
	local Out = {}
	if not Action then
		return Out
	end
	for _, Other in ipairs(Keybinds.Actions) do
		if Other ~= Action and Map[Other.Key] == Map[Action.Key] and Keybinds.Shown(Other) and Overlap(Action, Other) then
			table.insert(Out, Other.Key)
		end
	end
	return Out
end

-- Only the controls that differ from their defaults (what gets saved).
local function Diff(Map: { [string]: string }): { [string]: string }
	local Out = {}
	for _, Action in ipairs(Keybinds.Actions) do
		if Map[Action.Key] ~= Action.Default then
			Out[Action.Key] = Map[Action.Key]
		end
	end
	return Out
end

-- Gives ActionKey the key Name. Any listed control already on that key
-- where it would clash gets ActionKey's old key instead. Returns the new
-- Keybinds table to save and the controls that moved. Name must already
-- have passed IsAllowed.
function Keybinds.SetKey(Saved: any, ActionKey: string, Name: string): ({ [string]: string }, { string })
	local Map = Keybinds.Read(Saved)
	local Action = Keybinds.GetAction(ActionKey)
	local Old = Map[ActionKey]
	local Moved = {}
	if Action and Old ~= Name then
		for _, Other in ipairs(Keybinds.Actions) do
			if Other ~= Action and Map[Other.Key] == Name and Keybinds.Shown(Other) and Overlap(Action, Other) and Keybinds.IsAllowed(Other.Key, Old) then
				Map[Other.Key] = Old
				table.insert(Moved, Other.Key)
			end
		end
		Map[ActionKey] = Name
	end
	return Diff(Map), Moved
end

-- Puts one control back on its default key (swapping like SetKey).
function Keybinds.ResetKey(Saved: any, ActionKey: string): ({ [string]: string }, { string })
	local Action = Keybinds.GetAction(ActionKey)
	if not Action then
		return Diff(Keybinds.Read(Saved)), {}
	end
	return Keybinds.SetKey(Saved, ActionKey, Action.Default)
end

-- A key's short name for badges: "Q", "LSHIFT", "MB1", "ENTER".
function Keybinds.NameLabel(Name: string?): string
	if not Name then
		return "-"
	end
	return Labels[Name] or string.upper(Name)
end

----------------------------------------------------------------------
-- THE LIVE KEY MAP (client)
----------------------------------------------------------------------

-- Every control's key right now (by name), and as an Enum.
Keybinds.Current = Keybinds.Read(nil)
local Enums: { [string]: EnumItem } = {}

-- Fired whenever Load changes the keys.
Keybinds.Changed = Instance.new("BindableEvent")

-- True while the CONTROLS tab is waiting for a new key, so nothing else
-- acts on that key press. QuietUntil keeps it that way for a moment after
-- the key is taken, since other scripts may see the same press later in
-- the frame.
Keybinds.Capturing = false
Keybinds.QuietUntil = 0

-- Whether key presses should be ignored right now (a key is being set).
-- Every script that acts on a key checks this first.
function Keybinds.IsCapturing(): boolean
	return Keybinds.Capturing or os.clock() < Keybinds.QuietUntil
end

local function Rebuild()
	table.clear(Enums)
	for Key, Name in pairs(Keybinds.Current) do
		if IsMouse(Name) then
			Enums[Key] = (Enum.UserInputType :: any)[Name]
		else
			Enums[Key] = KeyCodeFor(Name) or Enum.KeyCode.Unknown
		end
	end
end
Rebuild()

-- Puts a saved Keybinds table into effect.
function Keybinds.Load(Saved: any)
	Keybinds.Current = Keybinds.Read(Saved)
	Rebuild()
	Keybinds.Changed:Fire()
end

-- The key name a control is on.
function Keybinds.Name(ActionKey: string): string?
	return Keybinds.Current[ActionKey]
end

-- The Enum a control is on: an Enum.KeyCode, or an Enum.UserInputType for
-- a mouse button. Ready for ContextActionService:BindAction.
function Keybinds.Get(ActionKey: string): EnumItem
	return Enums[ActionKey] or Enum.KeyCode.Unknown
end

-- Whether an input is the control's key.
function Keybinds.Is(ActionKey: string, Input: InputObject): boolean
	local Bound = Enums[ActionKey]
	if not Bound then
		return false
	end
	if Bound.EnumType == Enum.UserInputType then
		return Input.UserInputType == Bound
	end
	if Input.KeyCode == Bound then
		return true
	end
	-- Either Enter key starts a run.
	return Bound == Enum.KeyCode.Return and Input.KeyCode == Enum.KeyCode.KeypadEnter
end

-- A control's key as a badge: "Q", "LSHIFT", "MB1".
function Keybinds.Label(ActionKey: string): string
	return Keybinds.NameLabel(Keybinds.Current[ActionKey])
end

-- The key name an input would be saved as, or nil if it isn't a key or
-- mouse button.
function Keybinds.FromInput(Input: InputObject): string?
	local Type = Input.UserInputType
	if Type == Enum.UserInputType.MouseButton1 or Type == Enum.UserInputType.MouseButton2 or Type == Enum.UserInputType.MouseButton3 then
		return Type.Name
	end
	if Type == Enum.UserInputType.Keyboard and Input.KeyCode ~= Enum.KeyCode.Unknown then
		return Input.KeyCode.Name
	end
	return nil
end

return Keybinds
