--[[
	HUDController

	Keeps the HUD showing the right numbers. This is UpdatePlayerHUD from
	the function plan. It listens for stat changes from the server and
	writes them into the HUD, so health, energy and money on screen are
	always the same as the values the server holds.

	That is one of the success criteria, that the values update as soon
	as they change, so this should be driven by the server firing an
	update rather than by polling on a loop.

	It also shows the current room and wave, the active status effect
	icons, and the difficulty the run is on.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.StatsUpdated for health, energy,
	  money and max values. Fired by Server.Game.Core.PlayerStats.
	  ReplicatedStorage.Remotes.Events.EffectChanged for status effect
	  icons and timers, fired by
	  Server.Game.Effects.StatusEffectService. The payload is
	  (EffectName, Duration), with Duration nil meaning it ended.
	  ReplicatedStorage.Remotes.Events.WaveStateChanged for the wave
	  counter, fired by Server.Game.Rooms.WaveManager. The payload is
	  (WaveNumber, WaveTotal, EnemiesLeft), WaveNumber nil between
	  fights.
	  ReplicatedStorage.Remotes.Events.RunStateChanged for the run state
	  and difficulty, fired by Server.Game.Core.RunSetup and RunManager.

	Asks once on startup:
	  ReplicatedStorage.Remotes.Functions.GetStats and GetRunState, so a
	  player who joined late or reset does not sit with a blank HUD
	  until the next update fires.

	Writes into:
	  ClientGame.UI.HUD, which owns the actual labels and bars. This
	  controller should not be reaching into StarterGui.HUD directly,
	  that is the UI module's job.

	Reads:
	  Game.Config.GameConfig for the starting max health and max energy,
	  used to size the bars before the first update arrives.
	  Game.Config.HUDConfig for which core UI to hide.
	  Game.Data.WeaponData and AbilityData for slot names, icons and
	  keys when a loadout is shown.

	Offers to the other controllers:
	  SetLoadout, SetActiveSlots, StartCooldown and GetHUD, so
	  CombatInput and AbilityInput drive the cooldown slots through
	  here rather than each finding the HUD themselves.

	Started by:
	  ClientGame.ClientMain.

	The HUD is in StarterGui.HUD with ResetOnSpawn off, so it survives
	the player dying. That means this controller has to reconnect to the
	new character on respawn but does not need to rebuild the UI.

	Do not calculate anything here. If the HUD works out a value itself
	it will drift from the server's copy, which is the exact problem the
	success criteria is about. Show what the server sent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local HUDConfig = require(ReplicatedStorage.Modules.Game.Config.HUDConfig)
local WeaponData = require(ReplicatedStorage.Modules.Game.Data.WeaponData)
local AbilityData = require(ReplicatedStorage.Modules.Game.Data.AbilityData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local HUD = require(script.Parent.Parent.UI.HUD)
local Keybinds = require(ReplicatedStorage.Modules.Shared.Keybinds)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")
local Functions = Remotes:WaitForChild("Functions")

local HUDController = {}

local Hud = nil
local LastSnapshot = nil
-- the last loadout shown, so the key labels can be redrawn when the keys change
local LastLoadout = nil
local SlotAbilities: { [string]: string? } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Turns off the Roblox core UI the HUD replaces. Retries because the
-- core GUI is not always ready when the first LocalScript runs.
local function ApplyCoreGui()
	local Config = HUDConfig.CoreGui
	local Toggles = {
		{ Enum.CoreGuiType.Health, not Config.HideHealth },
		{ Enum.CoreGuiType.Backpack, not Config.HideBackpack },
		{ Enum.CoreGuiType.PlayerList, not Config.HidePlayerList },
		{ Enum.CoreGuiType.Chat, not Config.HideChat },
		{ Enum.CoreGuiType.EmotesMenu, not Config.HideEmotes },
	}
	for Attempt = 1, 10 do
		local AllOk = true
		for _, Toggle in ipairs(Toggles) do
			local Ok = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Toggle[1], Toggle[2])
			AllOk = AllOk and Ok
		end
		if AllOk then
			return
		end
		task.wait(0.5)
	end
end

local function RefreshAffordable()
	if not Hud or not LastSnapshot then
		return
	end
	for SlotName, AbilityName in pairs(SlotAbilities) do
		local Ability = AbilityName and AbilityData.Abilities[AbilityName]
		if Ability then
			Hud:SetSlotAffordable(SlotName, LastSnapshot.Energy >= Ability.EnergyCost or GameConfig.Debug.FreeAbilities)
		end
	end
end

local function OnStats(Snapshot)
	if not Hud or not Snapshot then
		return
	end
	LastSnapshot = Snapshot
	Hud:SetStats(Snapshot)
	RefreshAffordable()
end

local function OnRunState(Run)
	if not Hud or not Run then
		return
	end
	RunConfig.SetFromServer(Run)
	Hud:SetDifficulty(Run.DifficultyName)
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

function HUDController.GetHUD()
	return Hud
end

-- Fills the four cooldown slots. Weapons and Abilities are lists of
-- names from WeaponData and AbilityData in slot order. Called by
-- whatever receives the loadout from the server.
function HUDController.SetLoadout(Weapons: { string }, Abilities: { string })
	if not Hud then
		return
	end
	LastLoadout = { Weapons, Abilities }
	local WeaponSlots = { WeaponData.Hotbar.Slot1, WeaponData.Hotbar.Slot2 }
	local AbilitySlots = { AbilityData.Hotbar.Slot1, AbilityData.Hotbar.Slot2 }
	-- There are no per slot keys: R and G swap, E uses, and the number
	-- keys belong to the Backpack. The headings say so instead.
	local WeaponSlotKeys = { "", "" }
	local AbilitySlotKeys = { "", "" }

	-- Anything without its own image uses the placeholder.
	local Placeholder = WeaponData.Shared.PlaceholderIcon
	local function IconOf(Entry)
		return (Entry.Icon and Entry.Icon ~= "" and Entry.Icon ~= "rbxassetid://0") and Entry.Icon or Placeholder
	end

	for Index, SlotName in ipairs(WeaponSlots) do
		local Weapon = Weapons[Index] and WeaponData.Weapons[Weapons[Index]]
		Hud:SetSlot(SlotName, Weapon and {
			DisplayName = Weapon.DisplayName,
			Icon = IconOf(Weapon),
			Emoji = Weapon.Emoji,
			Key = WeaponSlotKeys[Index],
		} or nil)
	end

	-- the player's own keys, redrawn when they change
	Hud:SetSwapKey(HUDConfig.Names.WeaponGroup, Keybinds.Label("SwapWeapon") .. " swap")
	Hud:SetSwapKey(HUDConfig.Names.AbilityGroup, Keybinds.Label("UseAbility") .. " use, " .. Keybinds.Label("SwapAbility") .. " swap")

	SlotAbilities = {}
	for Index, SlotName in ipairs(AbilitySlots) do
		local Ability = Abilities[Index] and AbilityData.Abilities[Abilities[Index]]
		SlotAbilities[SlotName] = Abilities[Index]
		Hud:SetSlot(SlotName, Ability and {
			DisplayName = Ability.DisplayName,
			Icon = IconOf(Ability),
			Emoji = Ability.Emoji,
			Key = AbilitySlotKeys[Index],
		} or nil)
	end

	RefreshAffordable()
end

-- Marks which weapon slot and which ability slot are equipped, 1 or
-- 2 each. The other one of each pair is faded. nil leaves that pair
-- as it is.
function HUDController.SetActiveSlots(WeaponIndex: number?, AbilityIndex: number?)
	if not Hud then
		return
	end
	if WeaponIndex then
		Hud:SetSlotActive(WeaponData.Hotbar.Slot1, WeaponIndex == 1)
		Hud:SetSlotActive(WeaponData.Hotbar.Slot2, WeaponIndex == 2)
	end
	if AbilityIndex then
		Hud:SetSlotActive(AbilityData.Hotbar.Slot1, AbilityIndex == 1)
		Hud:SetSlotActive(AbilityData.Hotbar.Slot2, AbilityIndex == 2)
	end
end

-- Runs a cooldown sweep on a slot by name, for CombatInput and
-- AbilityInput.
function HUDController.StartCooldown(SlotName: string, Duration: number, Remaining: number?)
	if Hud then
		Hud:StartCooldown(SlotName, Duration, Remaining)
	end
end

-- A quick flash on a slot, for a weapon being swapped to.
function HUDController.PulseSlot(SlotName: string)
	if Hud then
		Hud:PulseSlot(SlotName)
	end
end

function HUDController.ClearCooldown(SlotName: string)
	if Hud then
		Hud:ClearCooldown(SlotName)
	end
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function HUDController.Init()
	Hud = HUD.new()
	task.spawn(ApplyCoreGui)

	Keybinds.Changed.Event:Connect(function()
		if LastLoadout then
			HUDController.SetLoadout(LastLoadout[1], LastLoadout[2])
		end
	end)

	-- Size the bars from the config until the first server value
	-- arrives, so they are not empty for a frame.
	Hud:SetHealth(GameConfig.Player.MaxHealth, GameConfig.Player.MaxHealth)
	Hud:SetEnergy(GameConfig.Player.MaxEnergy, GameConfig.Player.MaxEnergy)
	Hud:SetMoney(GameConfig.Player.StartingMoney)
	Hud:SetLevel(GameConfig.Player.StartingLevel)

	-- Placeholder until Server.Game.Core.Loadout exists and sends the
	-- real one: the fallback weapon and ability plus the next in the
	-- list, which is what a default loadout would be anyway.
	local WeaponNames = WeaponData.GetEnabledNames()
	local AbilityNames = AbilityData.GetEnabledNames()
	HUDController.SetLoadout({ WeaponNames[1], WeaponNames[2] }, { AbilityNames[1], AbilityNames[2] })
	HUDController.SetActiveSlots(1, 1)

	Events:WaitForChild("StatsUpdated").OnClientEvent:Connect(OnStats)
	Events:WaitForChild("RunStateChanged").OnClientEvent:Connect(OnRunState)

	Events:WaitForChild("EffectChanged").OnClientEvent:Connect(function(EffectName: string, Duration: number?)
		if not Hud then
			return
		end
		if Duration then
			Hud:AddEffect(EffectName, Duration)
		else
			Hud:RemoveEffect(EffectName)
		end
	end)

	-- The room name at the top of the HUD follows the room banner.
	Events:WaitForChild("RoomEntered").OnClientEvent:Connect(function(Info)
		if Hud and type(Info) == "table" then
			Hud:SetRoom(Info.Banner or Info.Area)
		end
	end)

	Events:WaitForChild("WaveStateChanged").OnClientEvent:Connect(function(WaveNumber: number?, WaveTotal: number?, EnemiesLeft: number?)
		if Hud then
			Hud:SetWave(WaveNumber, WaveTotal, EnemiesLeft)
		end
	end)

	-- Ask for the current values in case the first sends went out
	-- before this script was listening.
	task.spawn(function()
		local GetStats = Functions:WaitForChild("GetStats", 10)
		if GetStats then
			local Ok, Snapshot = pcall(GetStats.InvokeServer, GetStats)
			if Ok then
				OnStats(Snapshot)
			end
		end
		local GetRunState = Functions:WaitForChild("GetRunState", 10)
		if GetRunState then
			local Ok, Run = pcall(GetRunState.InvokeServer, GetRunState)
			if Ok then
				OnRunState(Run)
				if type(Run) == "table" and Run.Area then
					Hud:SetRoom(Run.Area)
				end
			end
		end
	end)
end

return HUDController
