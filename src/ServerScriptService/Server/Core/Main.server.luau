-- Main
-- Starts up all server modules. Add new modules to the require
-- list below and call their Init function.

local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService.Server.Modules
local Services = ServerScriptService.Server.Services

local DataManager = require(Modules.DataManager)
local PlayerManager = require(Modules.PlayerManager)
local LeaderstatsManager = require(Modules.LeaderstatsManager)
local AntiCheat = require(Modules.AntiCheat)
local GameManager = require(Modules.GameManager)
--asdasd
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local SharedModules = Modules.Shared
local NetworkModules = SharedModules.Network

local GameManager2 = require(SharedModules.GameManager)
GameManager2.new()
--asdasd
DataManager.Init()
PlayerManager.Init()
LeaderstatsManager.Init()
AntiCheat.Init()
GameManager.Init()

-- require and Init your own services from Server.Services here

-- The rogue like systems. GameInit starts every game module in
-- order, and goes after the framework so DataManager is up first.
local GameInit = require(ServerScriptService.Server.Game.GameInit)
GameInit.Init()

print("Server modules loaded")
