--[[
	PlayTimeService

	Counts time spent in this place into the shared save, the same way
	the lobby does: PlayTime goes up in seconds, and 1 Timebux is paid
	for every GameConfig.Timebux.SecondsPerTimebux of PlayTime.

	Timebux is worked out from PlayTime crossing each step, so time in
	the lobby and time here add up to the same Timebux whichever place
	it was played in.
]]

--[[
	What connects to this

	Started by Server.Game.GameInit.

	Writes PlayTime and Timebux through
	ServerScriptService.Server.Modules.DataManager.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)

local PlayTimeService = {}

PlayTimeService.Settings = {
	-- seconds between writes, the leftover is added when a player leaves
	Interval = 30,
}

local CountedUntil: { [Player]: number } = {}

-- adds the time since the last count to one player's save
local function Count(Player: Player)
	local From = CountedUntil[Player]
	if not From or not DataManager.IsLoaded(Player) then
		return
	end
	local Now = os.clock()
	local Seconds = math.floor(Now - From)
	if Seconds <= 0 then
		return
	end
	CountedUntil[Player] = From + Seconds

	local Before = tonumber(DataManager.Get(Player, "PlayTime")) or 0
	local After = Before + Seconds
	DataManager.Set(Player, "PlayTime", After)

	local Step = GameConfig.Timebux and GameConfig.Timebux.SecondsPerTimebux or 0
	if Step > 0 then
		local Earned = math.floor(After / Step) - math.floor(Before / Step)
		if Earned > 0 then
			DataManager.Increment(Player, "Timebux", Earned)
		end
	end
end

function PlayTimeService.Init()
	local function Start(Player: Player)
		CountedUntil[Player] = os.clock()
	end
	Players.PlayerAdded:Connect(Start)
	for _, Player in ipairs(Players:GetPlayers()) do
		Start(Player)
	end

	-- the last few seconds go in before the leaving save is written
	local PlayerManager = require(ServerScriptService.Server.Modules.PlayerManager)
	PlayerManager.OnLeaving(Count)
	Players.PlayerRemoving:Connect(function(Player)
		task.delay(5, function()
			CountedUntil[Player] = nil
		end)
	end)

	task.spawn(function()
		while true do
			task.wait(PlayTimeService.Settings.Interval)
			for _, Player in ipairs(Players:GetPlayers()) do
				Count(Player)
			end
		end
	end)
end

return PlayTimeService
