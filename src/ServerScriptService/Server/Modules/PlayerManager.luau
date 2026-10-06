-- PlayerManager
-- Loads player data when they join, saves it when they leave.

local Players = game:GetService("Players")

local DataManager = require(script.Parent.DataManager)

local PlayerManager = {}

local function load(player)
	DataManager.Load(player)
	DataManager.SyncAll(player)
end

function PlayerManager.Init()
	Players.PlayerAdded:Connect(load)

	Players.PlayerRemoving:Connect(function(player)
		DataManager.Save(player)
		DataManager.Release(player)
	end)

	-- Covers players who joined before this script ran, mostly
	-- matters when testing with Run instead of Play.
	for _, player in ipairs(Players:GetPlayers()) do
		if not DataManager.IsLoaded(player) then
			load(player)
		end
	end
end

return PlayerManager
