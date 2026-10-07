-- PlayerManager
-- Loads player data when they join, saves it when they leave.

local Players = game:GetService("Players")

local DataManager = require(script.Parent.DataManager)

local PlayerManager = {}

-- run for a leaving player before their save is written, so anything they earned gets into it
local leavingCallbacks = {}

function PlayerManager.OnLeaving(callback)
	table.insert(leavingCallbacks, callback)
end

local function load(player)
	DataManager.Load(player)
	DataManager.SyncAll(player)
end

function PlayerManager.Init()
	Players.PlayerAdded:Connect(load)

	Players.PlayerRemoving:Connect(function(player)
		for _, callback in ipairs(leavingCallbacks) do
			local ok, err = pcall(callback, player)
			if not ok then
				warn("PlayerManager: leaving callback errored - " .. tostring(err))
			end
		end
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
