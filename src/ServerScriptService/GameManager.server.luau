local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage.Modules
local SharedModules = Modules.Shared
local NetworkModules = SharedModules.Network

local GameManager = require(SharedModules.GameManager)
GameManager.new()