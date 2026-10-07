--[[
	KeybindController

	Puts the player's own keys (Settings > CONTROLS in the lobby) into
	effect in a run. The save's Keybinds arrive on the DataUpdated remote
	and go into Shared.Keybinds, which CombatInput, AbilityInput and the
	HUD read.

	It also does the two places that can't read Keybinds themselves:
	  the gate and shop ProximityPrompts are made by the server, so their
	  key is set here on the client when one shows
	  the movement keys in MovementSettings.Keybinds.Keyboard are written
	  over with the player's keys, for the movement scripts that read
	  that table
]]

--[[
	What connects to this

	Started first by ClientGame.ClientMain, because remote events are only
	queued for the first listener and the save is sent as soon as it
	loads.

	Listens on:
	  ReplicatedStorage.Remotes.Events.DataUpdated for "Keybinds", sent by
	  Server.Modules.DataManager.
	  ProximityPromptService.PromptShown.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keybinds = require(ReplicatedStorage.Modules.Shared.Keybinds)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)

local Events = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events")

local KeybindController = {}

-- control name in Keybinds -> name in MovementSettings.Keybinds.Keyboard
local MovementKeys = {
	Run = "Run",
	Dash = "Dash",
	Slide = "Slide",
	Crouch = "Crouch",
	Crawl = "Crawl",
	Sit = "Sit",
	Leap = "Leap",
	Glide = "Spin/Glide",
}

local function ApplyMovement()
	local Keyboard = MovementSettings.Keybinds.Keyboard
	for Action, Name in pairs(MovementKeys) do
		local Key = Keybinds.Get(Action)
		if typeof(Key) == "EnumItem" and Key.EnumType == Enum.KeyCode and Key ~= Enum.KeyCode.Unknown then
			Keyboard[Name] = Key
		end
	end
end

local function SetPromptKey(Prompt: ProximityPrompt)
	local Key = Keybinds.Get("Interact")
	if typeof(Key) == "EnumItem" and Key.EnumType == Enum.KeyCode and Key ~= Enum.KeyCode.Unknown then
		Prompt.KeyboardKeyCode = Key
	end
end

function KeybindController.Init()
	Events:WaitForChild("DataUpdated").OnClientEvent:Connect(function(Name, Value)
		if Name == "Keybinds" then
			Keybinds.Load(Value)
		end
	end)

	Keybinds.Changed.Event:Connect(ApplyMovement)
	ApplyMovement()

	-- prompts can show before the keys arrive, and the key can change while one is up
	ProximityPromptService.PromptShown:Connect(SetPromptKey)
end

return KeybindController
