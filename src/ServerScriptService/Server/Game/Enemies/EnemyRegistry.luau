--[[
	EnemyRegistry

	Maps an enemy type name to the class that runs it. So the string
	"Noob" gives back the Noob module, "Bob" gives back Bob and so on.
	It is a small module but it means nothing else has to hold a big if
	else chain of enemy names.

	Adding a fourth enemy type later is then one line in here, one entry
	in EnemyData and one new module under Types, with no changes needed
	to the spawner or the wave system.
]]

--[[
	What connects to this

	Requires:
	  Server.Game.Enemies.Types.Noob, Bob, Necromancer and Boss.

	Used by:
	  Server.Game.Enemies.EnemySpawner, which is handed a type name from
	  a wave in Game.Data.WaveData and asks this for the class to build.
	  Server.Game.Enemies.Types.Necromancer, which needs the Noob class
	  to create the enemies it summons.

	The keys here have to match the keys in Game.Data.EnemyData and the
	names used in Game.Data.WaveData. Those three lists are the ones that
	have to stay in step, so it is worth a check at startup that every
	name in the registry has an EnemyData entry and warning if one is
	missing, rather than finding out when a wave tries to spawn it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyData = require(ReplicatedStorage.Modules.Game.Data.EnemyData)
local WaveData = require(ReplicatedStorage.Modules.Game.Data.WaveData)
local EnemyBase = require(script.Parent.EnemyBase)

local Types = script.Parent.Types

local EnemyRegistry = {}

-- Type name to the ModuleScript for its class. A module that is still
-- a planning stub, or missing, falls back to EnemyBase so the enemy
-- can at least stand there and take damage.
local Modules = {
	Noob = Types:FindFirstChild("Noob"),
	Bob = Types:FindFirstChild("Bob"),
	Necromancer = Types:FindFirstChild("Necromancer"),
	Dasher = Types:FindFirstChild("Dasher"),
	Bomber = Types:FindFirstChild("Bomber"),
	Boss = Types:FindFirstChild("Boss"),
}

local Classes: { [string]: any } = {}
local WarnedFallback: { [string]: boolean } = {}

-- The class table for a type name. Cached after the first lookup.
function EnemyRegistry.Get(TypeName: string)
	local Cached = Classes[TypeName]
	if Cached then
		return Cached
	end

	local Module = Modules[TypeName]
	local Class = nil

	if Module then
		local Ok, Result = pcall(require, Module)
		if Ok and type(Result) == "table" and Result.__index then
			Class = Result
		end
	end

	if not Class then
		if not WarnedFallback[TypeName] then
			WarnedFallback[TypeName] = true
			warn("[EnemyRegistry] no class for " .. tostring(TypeName) .. " yet, using EnemyBase")
		end
		Class = EnemyBase
	end

	Classes[TypeName] = Class
	return Class
end

-- Every type name this registry knows.
function EnemyRegistry.GetNames(): { string }
	local Names = {}
	for Name in pairs(Modules) do
		table.insert(Names, Name)
	end
	table.sort(Names)
	return Names
end

-- Checks the registry, EnemyData and WaveData agree, and warns about
-- anything that does not line up.
function EnemyRegistry.Init()
	for Name in pairs(Modules) do
		if not EnemyData.Enemies[Name] then
			warn("[EnemyRegistry] " .. Name .. " is registered but has no EnemyData entry")
		end
	end
	for Name in pairs(EnemyData.Enemies) do
		if not Modules[Name] then
			warn("[EnemyRegistry] EnemyData has " .. Name .. " but it is not registered")
		end
	end
	for AreaName, Area in pairs(WaveData.Areas) do
		for WaveIndex, Wave in ipairs(Area.Waves) do
			for Name in pairs(Wave.Enemies) do
				if not Modules[Name] then
					warn(string.format("[EnemyRegistry] WaveData %s wave %d uses unknown enemy %s", AreaName, WaveIndex, Name))
				end
			end
		end
	end
end

return EnemyRegistry
