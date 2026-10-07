-- DataManager
-- Handles saving and loading player data with DataStoreService.
-- Each player's whole data table is stored under one key, so it
-- is one read and one write per player rather than one per stat.
--
-- To add a new saved variable, add it to PlayerDataTemplate in
-- ReplicatedStorage.Modules.Shared. This module handles the rest
-- automatically, including filling it in for players who already
-- have a save from before that variable existed.
--
-- The lobby and the game place share this save, and a player moves
-- between them by teleport. Every save is stamped with SaveVersion, one
-- higher each time it is written. The place that sends a player on
-- saves first and puts that number in the teleport data (SaveVersion at
-- the top, or in Loadouts[UserId] for a squad, see GameManager); Load
-- then waits for a copy at least that new, reading past the DataStore
-- cache, so a player never plays on (and later saves over) an old copy.
-- The game place's DataManager must do the same (see
-- VelocityGameConnection.md, next to VelocityBuildPlan.md).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataTemplate = require(ReplicatedStorage.Modules.Shared.PlayerDataTemplate)

local dataUpdatedRemote = ReplicatedStorage.Remotes.Events:WaitForChild("DataUpdated")

local DataManager = {}

local STORE_NAME = "PlayerData_v1"

local dataStore
local storeWarned = false

-- Fetched on first use rather than up here. Asking for a
-- DataStore throws outright on a place that has not been
-- published, and doing that at the top of the module would stop
-- it loading, which would take Main and the whole server with it.
-- This way an unpublished place still runs, it just does not save.
local function store()
	if dataStore then
		return dataStore
	end

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok then
		dataStore = result
		return dataStore
	end

	if not storeWarned then
		storeWarned = true
		warn("[DataManager] saving is off, DataStores are not available here. "
			.. "Publish the place, and turn on Studio access to API services in Game Settings under Security. "
			.. "Until then everyone starts on the default template every time.")
	end

	return nil
end

local AUTOSAVE_INTERVAL = 120
local MAX_ATTEMPTS = 3
-- How many times, and how far apart, Load reads again while the save it
-- got is older than the one the last place said it wrote.
local VERSION_TRIES = 8
local VERSION_DELAY = 1.5

local sessionData = {}
local dataLoaded = {}
local loading = {}

local function deepCopy(original)
	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = deepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

-- Adds any keys that exist in the template but not in the saved
-- data, without touching values that are already there.
local function fillMissing(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			if type(value) == "table" then
				data[key] = deepCopy(value)
			else
				data[key] = value
			end
		elseif type(value) == "table" and type(data[key]) == "table" then
			fillMissing(data[key], value)
		end
	end
	return data
end

-- Retries a datastore call a few times before giving up, since
-- calls can fail from normal throttling and not just real errors.
local function attempt(callback)
	for tryNumber = 1, MAX_ATTEMPTS do
		local success, result = pcall(callback)
		if success then
			return true, result
		end

		warn("DataManager: attempt " .. tryNumber .. " failed - " .. tostring(result))

		if tryNumber < MAX_ATTEMPTS then
			task.wait(tryNumber * 2)
		end
	end

	return false, nil
end

local function fireUpdate(player, variableName, value)
	dataUpdatedRemote:FireClient(player, variableName, value)
end

-- The SaveVersion the place that sent this player here said it saved,
-- from the teleport data, or nil. (Teleport data can be faked by a
-- client; the worst a fake number does is make Load wait a little.)
local function expectedVersion(player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local data = ok and type(joinData) == "table" and joinData.TeleportData
	if type(data) ~= "table" then
		return nil
	end
	local version = data.SaveVersion
	if type(data.Loadouts) == "table" then
		local mine = data.Loadouts[tostring(player.UserId)]
		if type(mine) == "table" and mine.SaveVersion ~= nil then
			version = mine.SaveVersion
		end
	end
	if type(version) ~= "number" or version ~= version then
		return nil
	end
	return version
end

-- Reads past the DataStore's few seconds of caching, so a save written
-- by another server a moment ago is seen.
local function readOptions()
	local ok, options = pcall(function()
		local made = Instance.new("DataStoreGetOptions")
		made.UseCache = false
		return made
	end)
	return ok and options or nil
end

local function versionOf(saved)
	return type(saved) == "table" and tonumber(saved.SaveVersion) or 0
end

function DataManager.Load(player)
	-- One load per player. PlayerManager can ask twice for a player who
	-- joins as the server starts (PlayerAdded and its loop over players
	-- already in), and a second load would replace the first one's data
	-- after other services have already changed it.
	if dataLoaded[player.UserId] then
		return sessionData[player.UserId]
	end
	if loading[player.UserId] then
		while loading[player.UserId] and player.Parent == Players do
			task.wait(0.1)
		end
		return sessionData[player.UserId]
	end
	loading[player.UserId] = true

	local key = "Player_" .. player.UserId

	local live = store()

	local success, result = false, nil
	if live then
		local options = readOptions()
		success, result = attempt(function()
			return live:GetAsync(key, options)
		end)

		-- Wait for the copy the last place saved (see the top).
		local expected = expectedVersion(player)
		if success and expected then
			local tries = 0
			while versionOf(result) < expected and tries < VERSION_TRIES and player.Parent == Players do
				tries += 1
				task.wait(VERSION_DELAY)
				local ok, newer = attempt(function()
					return live:GetAsync(key, options)
				end)
				if ok and versionOf(newer) >= versionOf(result) then
					result = newer
				end
			end
			if versionOf(result) < expected then
				warn("DataManager: " .. player.Name .. "'s save is version " .. versionOf(result) .. ", the last place saved version " .. expected .. ". Using the newest copy found.")
			end
		end
	end

	local data
	if success and result then
		data = fillMissing(result, PlayerDataTemplate)
	else
		if live and not success then
			warn("DataManager: giving up loading data for " .. player.Name .. ", using template")
		end
		data = deepCopy(PlayerDataTemplate)
	end

	sessionData[player.UserId] = data
	dataLoaded[player.UserId] = true
	loading[player.UserId] = nil

	return data
end

function DataManager.Save(player)
	local data = sessionData[player.UserId]
	if not data then
		return
	end

	local key = "Player_" .. player.UserId

	local live = store()
	if not live then
		return
	end

	-- See the top. Counted even if the write fails, so the next one is
	-- still newer than anything already out there.
	data.SaveVersion = versionOf(data) + 1

	local success = attempt(function()
		live:SetAsync(key, data)
	end)

	if not success then
		warn("DataManager: giving up saving data for " .. player.Name)
	end
end

function DataManager.IsLoaded(player)
	return dataLoaded[player.UserId] == true
end

function DataManager.GetAll(player)
	return sessionData[player.UserId]
end

function DataManager.Get(player, variableName)
	local data = sessionData[player.UserId]
	if not data then
		return nil
	end
	return data[variableName]
end

function DataManager.Set(player, variableName, value)
	local data = sessionData[player.UserId]
	if not data then
		return
	end
	data[variableName] = value
	fireUpdate(player, variableName, value)
end

function DataManager.Increment(player, variableName, amount)
	local data = sessionData[player.UserId]
	if not data then
		return
	end
	data[variableName] = (data[variableName] or 0) + amount
	fireUpdate(player, variableName, data[variableName])
end

-- Sends every top level variable to the client at once, used
-- right after a player's data finishes loading.
function DataManager.SyncAll(player)
	local data = sessionData[player.UserId]
	if not data then
		return
	end
	for variableName, value in pairs(data) do
		fireUpdate(player, variableName, value)
	end
end

function DataManager.Release(player)
	sessionData[player.UserId] = nil
	dataLoaded[player.UserId] = nil
end

function DataManager.Init()
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				if DataManager.IsLoaded(player) then
					DataManager.Save(player)
				end
			end
		end
	end)
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		DataManager.Save(player)
	end
end)

return DataManager
