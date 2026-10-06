-- LeaderstatsManager
-- Mirrors chosen variables from DataManager into leaderstats so
-- they show up on the Roblox leaderboard. Add or remove names in
-- TRACKED_STATS to change what's shown, they must exist in
-- PlayerDataTemplate and be numbers.

local Players = game:GetService("Players")

local DataManager = require(script.Parent.DataManager)

local LeaderstatsManager = {}

local TRACKED_STATS = { "Cash", "Level" }

local function build(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"

	for _, statName in ipairs(TRACKED_STATS) do
		local value = Instance.new("IntValue")
		value.Name = statName
		value.Value = DataManager.Get(player, statName) or 0
		value.Parent = leaderstats
	end

	leaderstats.Parent = player
end

function LeaderstatsManager.Refresh(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	for _, statName in ipairs(TRACKED_STATS) do
		local value = leaderstats:FindFirstChild(statName)
		if value then
			value.Value = DataManager.Get(player, statName) or 0
		end
	end
end

function LeaderstatsManager.Init()
	Players.PlayerAdded:Connect(function(player)
		-- waits for PlayerManager to finish loading this player's data
		task.spawn(function()
			while not DataManager.IsLoaded(player) do
				task.wait(0.1)
			end
			build(player)
		end)
	end)
end

return LeaderstatsManager
