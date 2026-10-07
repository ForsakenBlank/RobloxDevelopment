--[[
	RunStats

	Works out each player's numbers for a run from their save (gear, core
	and passes) with the lobby's CharacterStats module, so the lobby's
	Stats screen and the run always agree.

	CharacterStats is copied in from the lobby (see
	LobbyConnectionChecklist.md, section 3). Until it is there, or if it
	errors, everyone gets the neutral numbers in RunStats.Defaults, so
	the run plays exactly as it did before.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Core.RunSetup when it builds a player's PlayerStats,
	  through RunStats.Compute and RunStats.Apply.

	Read by:
	  Server.Game.Core.RunManager for ExpMultiplier and CashMultiplier
	  at the end of a run.

	Reads:
	  ReplicatedStorage.Modules.Shared.CharacterStats (from the lobby)
	  ServerScriptService.Server.Modules.DataManager for the save.

	Gear and cores only change in the lobby, so working this out once
	when the run starts is enough.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)
local PassService = require(script.Parent.PassService)

local RunStats = {}

-- the numbers everyone gets without CharacterStats. MaxHealth and MaxEnergy are nil so GameConfig.Player is used
RunStats.Defaults = {
	MaxHealth = nil,
	MaxEnergy = nil,
	HealthRegenPerSecond = nil,
	EnergyRegenPerSecond = nil,
	WeaponDamageMultiplier = 1,
	AbilityDamageMultiplier = 1,
	CritsEnabled = false,
	CritChance = 0,
	CritDamageMultiplier = 1,
	DamageTakenMultiplier = 1,
	MeleeDamageTakenMultiplier = 1,
	FireDamageTakenMultiplier = 1,
	MagicDamageTakenMultiplier = 1,
	NoHealthRegenInCombat = false,
	KnockbackMultiplier = 1,
	IgnoreKnockbackChance = 0,
	WeaponCooldownMultiplier = 1,
	AbilityCooldownMultiplier = 1,
	SpeedMultiplier = 1,
	Lifesteal = 0,
	HealingMultiplier = 1,
	CoinMultiplier = 1,
	PickupRangeMultiplier = 1,
	ExpMultiplier = 1,
	CashMultiplier = 1,
}

local ByPlayer: { [Player]: { [string]: any } } = {}
local CharacterStats = nil
local Warned = false

-- the lobby's module, or nil while it has not been copied in
local function GetCharacterStats()
	if CharacterStats then
		return CharacterStats
	end
	local Shared = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Shared")
	local Module = Shared and Shared:FindFirstChild("CharacterStats")
	if not Module then
		if not Warned then
			Warned = true
			warn("[RunStats] no CharacterStats in ReplicatedStorage.Modules.Shared yet, gear and cores do nothing in runs")
		end
		return nil
	end
	local Ok, Result = pcall(require, Module)
	if Ok then
		CharacterStats = Result
	else
		warn("[RunStats] CharacterStats errored: " .. tostring(Result))
	end
	return CharacterStats
end

-- works out and keeps one player's numbers. Call once their save has
-- loaded. Anything CharacterStats leaves out falls back to Defaults.
function RunStats.Compute(Player: Player): { [string]: any }
	local Numbers = table.clone(RunStats.Defaults)
	local Module = GetCharacterStats()
	local Save = DataManager.GetAll(Player)
	if Module and Save then
		-- passes (AccessorySlots, DoubleExp, VIP), asked for before the pcall since it can yield
		local Context = { Passes = PassService.Owned(Player), DevAll = PassService.DevAll(Player) }
		local Ok, Result = pcall(function()
			local Sheet = Module.Compute(Save, Context)
			return Module.ForRun(Sheet)
		end)
		if Ok and type(Result) == "table" then
			for Key, Value in pairs(Result) do
				Numbers[Key] = Value
			end
		else
			warn("[RunStats] could not work out " .. Player.Name .. "'s stats: " .. tostring(Result))
		end
	end
	ByPlayer[Player] = Numbers
	if GameConfig.Debug.LogRunStats then
		local Keys = {}
		for Key in pairs(Numbers) do
			table.insert(Keys, Key)
		end
		table.sort(Keys)
		local Parts = {}
		for _, Key in ipairs(Keys) do
			table.insert(Parts, Key .. "=" .. tostring(Numbers[Key]))
		end
		print("[RunStats] " .. Player.Name .. ": " .. table.concat(Parts, ", "))
	end
	return Numbers
end

-- one player's numbers, or the defaults if they were never worked out.
function RunStats.Get(Player: Player): { [string]: any }
	return ByPlayer[Player] or RunStats.Defaults
end

-- one number for one player, with the default when it is missing.
function RunStats.Value(Player: Player?, Name: string): any
	local Numbers = Player and ByPlayer[Player]
	local Value = Numbers and Numbers[Name]
	if Value == nil then
		return RunStats.Defaults[Name]
	end
	return Value
end

-- the starting values PlayerStats.new takes.
function RunStats.Overrides(Player: Player): { [string]: any }
	local Numbers = RunStats.Get(Player)
	return { MaxHealth = Numbers.MaxHealth, MaxEnergy = Numbers.MaxEnergy }
end

-- puts the numbers that live on PlayerStats onto a fresh one.
function RunStats.Apply(Player: Player, Stats)
	if not Stats then
		return
	end
	local Numbers = RunStats.Get(Player)
	if Numbers.SpeedMultiplier and Numbers.SpeedMultiplier ~= 1 then
		Stats:SetSpeedMultiplier("Gear", Numbers.SpeedMultiplier)
	end
	if Numbers.Lifesteal and Numbers.Lifesteal > 0 then
		Stats:SetLifesteal("Gear", Numbers.Lifesteal)
	end
	Stats:SetGearCooldownMultipliers(Numbers.WeaponCooldownMultiplier, Numbers.AbilityCooldownMultiplier)
end

Players.PlayerRemoving:Connect(function(Player)
	ByPlayer[Player] = nil
end)

return RunStats
