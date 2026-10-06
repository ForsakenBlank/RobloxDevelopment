local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreModules = ServerStorage.Modules.Core

local Namespace = require(ReplicatedStorage.Modules.Shared.Network.namespace)
local TrailHandler = require(ReplicatedStorage.Modules.Shared.TrailHandler)

local GameManager = {}
GameManager.__index = GameManager

local function fxFolder(player)
	local folder = Instance.new("Folder")
	
	folder.Parent = workspace:FindFirstChild("ClientFX")
	folder.Name = player.Name
end

function GameManager.new()
	local self = {}
	
	setmetatable(self, GameManager)

	self:main()
	
	return self
end

function GameManager:main()
	self:network()
	
	Players.PlayerAdded:Connect(function(player)
		self:onPlayerAdded(player)
		
		player.CharacterAdded:Connect(function(character)
			TrailHandler.new(character, character.Humanoid)
		end)
	end)
	
	Players.PlayerRemoving:Connect(function(player)
		self:onPlayerLeaving(player)
	end)
end

function GameManager:onPlayerAdded(player : Player)
	fxFolder(player)
end

function GameManager:network()
	local function getModule(data, player)
		local targetModule = CoreModules[data.module]

		local module = require(targetModule)
		
		return module
	end
	
	Namespace.Core.listen(function(data, player)
		local module = getModule(data, player)
		module[data.method](player, data.msg, data.animLength)
	end)
	
	Namespace.Hitbox.listen(function(data, player)
		local module = getModule(data, player)
		module[data.method](player, data.msg, data.hits)
	end)
end

function GameManager:onPlayerLeaving(player : Player)
	workspace.ClientFX[player.Name]:Destroy()
end

return GameManager