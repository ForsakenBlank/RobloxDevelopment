-- FlagLog
-- Writes every anti cheat flag to a DataStore so you can read
-- them later, from any server, including ones you were never in.
--
-- The output log on its own is per server and disappears when
-- that server shuts down, which is most of the time. This keeps
-- the record.
--
-- To read it, open Studio and run this in the command bar:
--
--     require(game.ServerScriptService.Server.Modules.AntiCheat.FlagLog).PrintReport()
--
-- That needs Studio access to API services turned on, in Game
-- Settings under Security.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Parent.Config)

local FlagLog = {}

local settings = Config.Logging

local records, recentIndex, totalIndex
local storesReady = false
local storesWarned = false

-- Fetched on first use rather than up here, because asking for a
-- DataStore throws outright on a place that has not been
-- published. Doing that at the top would stop this module
-- loading, which would take the whole anti cheat down with it.
--
-- Two ordered stores sit alongside the main one so flags can be
-- sorted without reading every player. One answers "who was
-- flagged most recently", the other "who has been flagged most".
local function stores()
	if storesReady then
		return true
	end

	local ok = pcall(function()
		records = DataStoreService:GetDataStore(settings.StoreName)
		recentIndex = DataStoreService:GetOrderedDataStore(settings.StoreName .. "_Recent")
		totalIndex = DataStoreService:GetOrderedDataStore(settings.StoreName .. "_Totals")
	end)

	if ok then
		storesReady = true
		return true
	end

	if not storesWarned then
		storesWarned = true
		warn("[AntiCheat] flag log is off, DataStores are not available here. "
			.. "Publish the place, and turn on Studio access to API services in Game Settings under Security. "
			.. "Detection still works, flags just will not be kept.")
	end

	return false
end

local pending = {}
local flushing = {}
local started = false

local function keyFor(userId)
	return "Player_" .. userId
end

-- Flags are buffered and written in batches. Writing on every
-- flag would throttle instantly, since a player who is actually
-- cheating produces one every second or so.
local function flush(userId)
	local queued = pending[userId]
	if not queued or #queued == 0 or flushing[userId] then
		return
	end

	if not stores() then
		pending[userId] = nil
		return
	end

	pending[userId] = nil
	flushing[userId] = true

	local total = 0

	local ok, err = pcall(function()
		records:UpdateAsync(keyFor(userId), function(record)
			record = record or {
				UserId = userId,
				Name = queued[1].Name,
				FirstFlagAt = queued[1].Time,
				Total = 0,
				Kicks = 0,
				Counts = {},
				Recent = {},
			}

			record.Name = queued[#queued].Name
			record.Counts = record.Counts or {}
			record.Recent = record.Recent or {}

			for _, entry in ipairs(queued) do
				record.Total += 1
				record.Counts[entry.Check] = (record.Counts[entry.Check] or 0) + 1
				if entry.Kicked then
					record.Kicks += 1
				end
				table.insert(record.Recent, entry)
			end

			while #record.Recent > settings.MaxRecentPerPlayer do
				table.remove(record.Recent, 1)
			end

			record.LastFlagAt = queued[#queued].Time
			total = record.Total

			return record
		end)
	end)

	if not ok then
		-- Put them back so the next flush tries again rather than
		-- losing the evidence. They go in front of anything that
		-- arrived while the write was in flight, so the trail
		-- stays in order.
		local retry = pending[userId] or {}
		for index = #queued, 1, -1 do
			table.insert(retry, 1, queued[index])
		end
		pending[userId] = retry
		flushing[userId] = nil
		warn("[AntiCheat] failed to write flag log for " .. userId .. " - " .. tostring(err))
		return
	end

	pcall(function()
		recentIndex:SetAsync(tostring(userId), queued[#queued].Time)
		totalIndex:SetAsync(tostring(userId), total)
	end)

	flushing[userId] = nil
end

-- The id list is taken first because flush edits pending as it
-- goes. Blocking is used on shutdown, where spawned writes would
-- be cut off before they finish.
local function flushAll(blocking)
	local ids = {}
	for userId in pairs(pending) do
		table.insert(ids, userId)
	end

	for _, userId in ipairs(ids) do
		if blocking then
			flush(userId)
		else
			task.spawn(flush, userId)
		end
	end
end

local function record(player, checkName, severity, detail, score)
	if not stores() then
		return
	end

	local queued = pending[player.UserId]
	if not queued then
		queued = {}
		pending[player.UserId] = queued
	end

	table.insert(queued, {
		Time = os.time(),
		Name = player.Name,
		Check = checkName,
		Severity = severity,
		Detail = detail,
		Score = math.floor(score),
		Kicked = Config.Response.KickEnabled and score >= Config.Response.KickScore or nil,
		Studio = RunService:IsStudio() or nil,
		JobId = game.JobId ~= "" and game.JobId or nil,
	})
end

-- Called by AntiCheat.Init, you do not need to start this
-- yourself. Takes the Reported event rather than requiring
-- AntiCheat back, which would be a loop.
function FlagLog.Init(reported)
	if started or not settings.Enabled then
		return
	end
	started = true

	reported.Event:Connect(record)

	Players.PlayerRemoving:Connect(function(player)
		flush(player.UserId)
	end)

	task.spawn(function()
		while true do
			task.wait(settings.FlushInterval)
			flushAll()
		end
	end)

	game:BindToClose(function()
		flushAll(true)
	end)
end

function FlagLog.GetRecord(userId)
	if not stores() then
		return nil
	end

	local ok, result = pcall(function()
		return records:GetAsync(keyFor(userId))
	end)
	return ok and result or nil
end

local function readIndex(store, limit, ascending)
	if not stores() then
		return {}
	end

	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(ascending, math.clamp(limit, 1, 100))
		return pages:GetCurrentPage()
	end)

	if not ok then
		warn("[AntiCheat] could not read flag index - " .. tostring(result))
		return {}
	end

	local rows = {}
	for _, entry in ipairs(result) do
		table.insert(rows, { UserId = tonumber(entry.key), Value = entry.value })
	end
	return rows
end

-- Players flagged most recently, newest first. This is the one
-- that answers "did anything happen while I was away".
function FlagLog.GetRecentlyFlagged(limit)
	return readIndex(recentIndex, limit or 10, false)
end

-- Players with the most flags on record, worst first.
function FlagLog.GetWorstOffenders(limit)
	return readIndex(totalIndex, limit or 10, false)
end

function FlagLog.PrintReport(limit)
	limit = limit or 10

	local rows = FlagLog.GetRecentlyFlagged(limit)
	if #rows == 0 then
		print("[AntiCheat] nothing on record")
		return
	end

	print(string.format("[AntiCheat] %d most recently flagged", #rows))

	for _, row in ipairs(rows) do
		local entry = FlagLog.GetRecord(row.UserId)
		if entry then
			local counts = {}
			for checkName, count in pairs(entry.Counts or {}) do
				table.insert(counts, string.format("%s x%d", checkName, count))
			end
			table.sort(counts)

			print(string.format(
				"  %s (%d)  %d flags, %d kicks  last %s",
				entry.Name or "?",
				row.UserId,
				entry.Total or 0,
				entry.Kicks or 0,
				os.date("%Y-%m-%d %H:%M", entry.LastFlagAt or 0)
			))
			print("      " .. (#counts > 0 and table.concat(counts, ", ") or "no breakdown"))

			local recent = entry.Recent or {}
			for index = math.max(1, #recent - 2), #recent do
				local flag = recent[index]
				if flag then
					print(string.format(
						"      %s  %s  %s%s",
						os.date("%m-%d %H:%M", flag.Time),
						flag.Check,
						flag.Detail or "",
						flag.Studio and "  [studio]" or ""
					))
				end
			end
		end
	end
end

return FlagLog
