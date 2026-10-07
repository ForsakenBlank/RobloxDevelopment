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

-- Session locking: while a server has a player's save it stamps it with
-- its JobId (SessionLock), and no other server loads or writes that save
-- until it is released, so two servers can never save over each other.
-- It only works when every place uses it, so turn it on in the lobby and
-- the game place together (copy this file to both, then set it to true
-- in both). A lock older than LOCK_EXPIRE is taken as a crashed server's
-- and taken over, and a load waits at most LOCK_WAIT for a lock to be
-- released before taking it.
local SESSION_LOCK = false
local LOCK_EXPIRE = 600
local LOCK_WAIT = 30
local LOCK_RETRY = 2

local sessionData = {}
local dataLoaded = {}
local loading = {}
-- players whose save could not be read, so the template never gets written over their real save
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

local function newLock()
	return { JobId = game.JobId, Time = os.time() }
end

-- whether another live server holds this save
local function lockedByOther(saved)
	local lock = type(saved) == "table" and saved.SessionLock
	if type(lock) ~= "table" or lock.JobId == game.JobId then
		return false
	end
	return os.time() - (tonumber(lock.Time) or 0) < LOCK_EXPIRE
end

-- Takes the session lock and reads the save in one go. Waits for another
-- server to let go, up to LOCK_WAIT, then takes it anyway. Returns like
-- attempt: (success, saved data or nil for a new player).
local function claim(player, live, key)
	local giveUpAt = os.clock() + LOCK_WAIT
	while true do
		local force = os.clock() >= giveUpAt
		local blocked = false
		local success, result = attempt(function()
			return live:UpdateAsync(key, function(old)
				blocked = false
				if not force and lockedByOther(old) then
					blocked = true
					return nil
				end
				if type(old) ~= "table" then
					-- a new player, there is nothing to lock yet (the first save writes it)
					return nil
				end
				old.SessionLock = newLock()
				return old
			end)
		end)
		if not success or not blocked then
			if force then
				warn("DataManager: took " .. player.Name .. "'s save from a server that did not let go of it")
			end
			return success, result
		end
		if player.Parent ~= Players then
			return false, nil
		end
		task.wait(LOCK_RETRY)
	end
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
	if live and SESSION_LOCK then
		-- the lock makes sure the last server has saved and let go, so there is no version to wait for
		success, result = claim(player, live, key)
	elseif live then
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
			warn("DataManager: giving up loading data for " .. player.Name .. ", using template and not saving this session")
			noSave[player.UserId] = true
		end
		data = deepCopy(PlayerDataTemplate)
	end

	loading[player.UserId] = nil

	-- they left while this was loading and Release already ran, so keep nothing
	if player.Parent ~= Players then
		noSave[player.UserId] = nil
		return data
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

	-- the real save is still out there, so never write the template over it
	if noSave[player.UserId] then
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

	local success
	if SESSION_LOCK then
		-- only written while this server still holds the lock, which also keeps the lock fresh
		local lost = false
		success = attempt(function()
			live:UpdateAsync(key, function(old)
				lost = false
				if lockedByOther(old) then
					lost = true
					return nil
				end
				data.SessionLock = newLock()
				return data
			end)
		end)
		if success and lost then
			warn("DataManager: another server took " .. player.Name .. "'s save, this server stops saving it")
			noSave[player.UserId] = true
			return
		end
	else
		success = attempt(function()
			live:SetAsync(key, data)
		end)
	end

	if not success then
		warn("DataManager: giving up saving data for " .. player.Name)
	end
end

-- lets go of a player's session lock, if this server holds it
local function releaseLock(userId)
	local live = store()
	if not SESSION_LOCK or not live or noSave[userId] or not dataLoaded[userId] then
		return
	end
	attempt(function()
		live:UpdateAsync("Player_" .. userId, function(old)
			local lock = type(old) == "table" and old.SessionLock
			if type(lock) ~= "table" or lock.JobId ~= game.JobId then
				return nil
			end
			old.SessionLock = nil
			return old
		end)
	end)
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
	releaseLock(player.UserId)
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
		releaseLock(player.UserId)
	end
end)

return DataManager
