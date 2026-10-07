--[[
	ClientMain

	The client side entry point, the mirror of what
	ServerScriptService.Server.Core.Main does on the server. It requires
	every controller in the Controllers folder and calls their Init, so
	each controller does not need its own LocalScript.

	Order is: build the UI modules first so the controllers have
	something to write into, then start the controllers, then ask the
	server for the current run state so a player who joined late or
	respawned gets a correct HUD straight away rather than an empty one.

	It also has to wait for the character, since the input controllers
	need a character to work with, and a LocalScript in
	StarterPlayerScripts runs before the first character exists.
]]

--[[
	What connects to this

	Requires and initialises:
	  ClientGame.Controllers.HUDController
	  ClientGame.Controllers.FXController
	  ClientGame.Controllers.InventoryController
	  ClientGame.Controllers.CombatInput
	  ClientGame.Controllers.AbilityInput
	  ClientGame.Controllers.ShopController
	  ClientGame.Controllers.BossBarController
	  ClientGame.Controllers.RoomBannerController
	  ClientGame.Controllers.EnemyAnimator,
	  MusicController, PartyController, HUDTilt and HUDEffects

	Which in turn use:
	  ClientGame.UI.HUD and ClientGame.UI.ShopUI.

	Asks the server:
	  ReplicatedStorage.Remotes.Functions.GetRunState on startup for the
	  difficulty, player count and current room, so the HUD is correct
	  before the first StatsUpdated arrives. HUDController does this.

	Does not touch:
	  The movement framework. StarterCharacterScripts.Client and its
	  MOVEMENT_INPUTS module already own movement input, and
	  StarterGui.Hotbar.Hotbar.SWITCH_INPUT owns the hotbar switching.
	  The movement keys come from MovementSettings.Keybinds, so check
	  there before choosing a combat key. The weapon and ability keys
	  live in WeaponData.Keybinds and AbilityData.Keybinds.

	Respawning:
	  This script is in StarterPlayerScripts so it does not restart when
	  the character dies, which is what we want. But the controllers that
	  hold a reference to the character do need to pick up the new one on
	  CharacterAdded, so handle that here in one place rather than in
	  each controller. A controller with an OnCharacter function gets
	  called with every new character.
]]

local Players = game:GetService("Players")

local Controllers = script.Parent:WaitForChild("Controllers")

local Player = Players.LocalPlayer

-- Every controller, in start order. A controller that is still a
-- planning stub with no Init is skipped with a note rather than
-- erroring. Uncomment each as it gets written.
local ControllerList = {
	-- first, it is the one listener for the save's values
	{ Name = "PlayerData", Module = Controllers.PlayerData },
	{ Name = "KeybindController", Module = Controllers.KeybindController },
	-- volumes, camera shake and moving backgrounds from the lobby's Settings
	{ Name = "SettingsController", Module = Controllers.SettingsController },
	{ Name = "HUDController", Module = Controllers.HUDController },
	{ Name = "FXController", Module = Controllers.FXController },
	-- The Roblox Backpack as the item inventory.
	{ Name = "InventoryController", Module = Controllers.InventoryController },
	{ Name = "CombatInput", Module = Controllers.CombatInput },
	{ Name = "AbilityInput", Module = Controllers.AbilityInput },
	{ Name = "ShopController", Module = Controllers.ShopController },
	{ Name = "BossBarController", Module = Controllers.BossBarController },
	{ Name = "RoomBannerController", Module = Controllers.RoomBannerController },
	{ Name = "EnemyAnimator", Module = Controllers.EnemyAnimator },
	{ Name = "MusicController", Module = Controllers.MusicController },
	{ Name = "PartyController", Module = Controllers.PartyController },
	-- Dashes and slides pass through enemies.
	{ Name = "CollisionController", Module = Controllers.CollisionController },
	-- Speed lines and colour grading.
	{ Name = "ScreenEffects", Module = Controllers.ScreenEffects },
	-- The sliding squares behind the HUD panels.
	{ Name = "UIPattern", Module = Controllers.UIPattern },
	-- Moves the main HUD panels onto tilted 3D surfaces. Before
	-- HUDEffects, so HUDEffects leaves those panels alone.
	{ Name = "HUDTilt", Module = Controllers.HUDTilt },
	-- Last, so every panel it moves already exists.
	{ Name = "HUDEffects", Module = Controllers.HUDEffects },
}

local Started = {}

for _, Entry in ipairs(ControllerList) do
	local Ok, Result = pcall(require, Entry.Module)
	if not Ok then
		warn("[ClientMain] " .. Entry.Name .. " failed to load: " .. tostring(Result))
		continue
	end

	if type(Result) ~= "table" or type(Result.Init) ~= "function" then
		warn("[ClientMain] " .. Entry.Name .. " has no Init yet, skipped")
		continue
	end

	local InitOk, InitError = pcall(Result.Init)
	if not InitOk then
		warn("[ClientMain] " .. Entry.Name .. ".Init errored: " .. tostring(InitError))
		continue
	end

	table.insert(Started, Result)
end

-- Hand every new character to the controllers that want one.
local function OnCharacter(Character: Model)
	for _, Controller in ipairs(Started) do
		if type(Controller.OnCharacter) == "function" then
			task.spawn(Controller.OnCharacter, Character)
		end
	end
end

Player.CharacterAdded:Connect(OnCharacter)
if Player.Character then
	OnCharacter(Player.Character)
end

print("[ClientMain] client controllers started")
