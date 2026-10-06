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

local sessionData = {}
local dataLoaded = {}

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

function DataManager.Load(player)
	local key = "Player_" .. player.UserId

	local live = store()

	local success, result = false, nil
	if live then
		success, result = attempt(function()
			return live:GetAsync(key)
		end)
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
