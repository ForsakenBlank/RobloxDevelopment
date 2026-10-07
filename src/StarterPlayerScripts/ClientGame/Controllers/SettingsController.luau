--[[
	SettingsController

	Puts the player's Settings from the lobby (the Settings screen there,
	saved in the shared save) into effect in a run:
	  MasterVolume, MusicVolume, MusicEnabled   SoundService.MusicGroup
	  MasterVolume, EffectsVolume, SFXEnabled   SoundService.SFXGroup
	  CameraShake                               Shared.CameraShake
	  MovingBackgrounds                         the HUD's sliding squares

	The groups' volumes set in the editor are full volume, and the
	player's settings scale them down from there.
]]

--[[
	What connects to this

	Started by ClientGame.ClientMain, after PlayerData.

	Reads Settings from ClientGame.Controllers.PlayerData.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local CameraShake = require(ReplicatedStorage.Modules.Shared.CameraShake)
local PlayerData = require(script.Parent.PlayerData)
local UIPattern = require(script.Parent.UIPattern)

local SettingsController = {}

-- the editor's volume for each group, so the settings never stack on top of each other
local BaseVolume: { [SoundGroup]: number } = {}

local function Percent(Value: any, Default: number): number
	return math.clamp(tonumber(Value) or Default, 0, 100) / 100
end

local function SetGroup(Name: string, Scale: number)
	local Group = SoundService:FindFirstChild(Name)
	if not Group or not Group:IsA("SoundGroup") then
		return
	end
	if not BaseVolume[Group] then
		BaseVolume[Group] = Group.Volume
	end
	Group.Volume = BaseVolume[Group] * Scale
end

local function Apply(Settings: any)
	if type(Settings) ~= "table" then
		return
	end
	local Master = Percent(Settings.MasterVolume, 100)
	local MusicOn = Settings.MusicEnabled ~= false and 1 or 0
	local EffectsOn = Settings.SFXEnabled ~= false and 1 or 0
	SetGroup("MusicGroup", Master * Percent(Settings.MusicVolume, 70) * MusicOn)
	SetGroup("SFXGroup", Master * Percent(Settings.EffectsVolume, 80) * EffectsOn)

	CameraShake.Enabled = Settings.CameraShake ~= false
	UIPattern.Moving = Settings.MovingBackgrounds ~= false
end

function SettingsController.Init()
	PlayerData.Watch("Settings", Apply)
end

return SettingsController
