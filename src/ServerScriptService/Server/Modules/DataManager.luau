-- DataManager
-- Handles saving and loading player data with DataStoreService.
-- Each player's whole data table is stored under one key, so it
-- is one read and one write per player rather than one per stat.
--
-- To add a new saved variable, add it to PlayerDataTemplate in
-- ReplicatedStorage.Modules.Shared. This module handles the rest
-- automatically, including filling it in for players who already
-- have a save from before that variable existed.

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

-- how long to keep re-reading a save that is older than the teleport data says it should be
local VERSION_WAIT = 12
local VERSION_RETRY = 1.5

local sessionData = {}
local dataLoaded = {}
-- players whose load is running, so a second Load waits for the first instead of starting over
local loading = {}
-- players whose save could not be read, so the template never gets written over their real data
local noSave = {}

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

-- the SaveVersion the other place wrote right before teleporting this player here, or 0 if there was none
local function expectedVersion(player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	local teleportData = ok and type(joinData) == "table" and joinData.TeleportData
	if type(teleportData) ~= "table" then
		return 0
	end

	local version = teleportData.SaveVersion
	if type(version) ~= "number" and type(teleportData.Loadouts) == "table" then
		local mine = teleportData.Loadouts[tostring(player.UserId)] or teleportData.Loadouts[player.UserId]
		version = type(mine) == "table" and mine.SaveVersion
	end

	return type(version) == "number" and version or 0
end

local function fireUpdate(player, variableName, value)
	dataUpdatedRemote:FireClient(player, variableName, value)
end

function DataManager.Load(player)
	local userId = player.UserId

	-- only ever load a player once, a second call just waits for the first
	if dataLoaded[userId] then
		return sessionData[userId]
	end
	if loading[userId] then
		while loading[userId] do
			task.wait()
		end
		return sessionData[userId]
	end
	loading[userId] = true

	local key = "Player_" .. userId

	local live = store()

	local success, result = false, nil
	if live then
		success, result = attempt(function()
			return live:GetAsync(key)
		end)

		-- the save from the other place can still be on its way, so skip the cache and read again until it shows up
		local wanted = expectedVersion(player)
		local giveUpAt = os.clock() + VERSION_WAIT
		while success and wanted > 0 and os.clock() < giveUpAt and player.Parent == Players do
			local version = type(result) == "table" and result.SaveVersion or 0
			if version >= wanted then
				break
			end
			task.wait(VERSION_RETRY)
			success, result = attempt(function()
				local options = Instance.new("DataStoreGetOptions")
				options.UseCache = false
				return live:GetAsync(key, options)
			end)
		end
		if success and wanted > 0 and (type(result) ~= "table" or (result.SaveVersion or 0) < wanted) then
			warn("DataManager: " .. player.Name .. "'s save is older than expected (wanted version " .. wanted .. "), loading it anyway")
		end
	end

	local data
	if success and result then
		data = fillMissing(result, PlayerDataTemplate)
	else
		if live and not success then
			warn("DataManager: giving up loading data for " .. player.Name .. ", using template and not saving this session")
			noSave[userId] = true
		end
		data = deepCopy(PlayerDataTemplate)
	end

	loading[userId] = nil

	-- they left while we were loading, Release already ran so keep nothing
	if player.Parent ~= Players then
		noSave[userId] = nil
		return data
	end

	sessionData[userId] = data
	dataLoaded[userId] = true

	return data
end

function DataManager.Save(player)
	local data = sessionData[player.UserId]
	if not data then
		return
	end

	if noSave[player.UserId] then
		return
	end

	local key = "Player_" .. player.UserId

	local live = store()
	if not live then
		return
	end

	-- every write gets a higher number, so the next place can tell if it read an old copy
	data.SaveVersion = (data.SaveVersion or 0) + 1

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
	noSave[player.UserId] = nil
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
