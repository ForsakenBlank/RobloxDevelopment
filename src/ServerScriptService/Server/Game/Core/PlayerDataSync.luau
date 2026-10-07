--[[
	PlayerDataSync

	Answers a client asking for its whole save, so the client's
	PlayerData has every value even if another script heard the first
	DataUpdated messages before it did (remote events are only queued
	for the first listener).
]]

--[[
	What connects to this

	Started by Server.Game.GameInit.

	Answers ReplicatedStorage.Remotes.Functions.GetPlayerData, called by
	ClientGame.Controllers.PlayerData. Waits for the save to load.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.Server.Modules.DataManager)

local PlayerDataSync = {}

PlayerDataSync.Settings = {
	-- seconds a request waits for the save before answering with nothing
	LoadWait = 25,
}

function PlayerDataSync.Init()
	local Functions = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Functions")
	local GetPlayerData = Functions:FindFirstChild("GetPlayerData")
	if not GetPlayerData then
		GetPlayerData = Instance.new("RemoteFunction")
		GetPlayerData.Name = "GetPlayerData"
		GetPlayerData.Parent = Functions
	end

	GetPlayerData.OnServerInvoke = function(Player)
		local Deadline = os.clock() + PlayerDataSync.Settings.LoadWait
		while not DataManager.IsLoaded(Player) and os.clock() < Deadline and Player.Parent == Players do
			task.wait(0.25)
		end
		return DataManager.GetAll(Player)
	end
end

return PlayerDataSync
