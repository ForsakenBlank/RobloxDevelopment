--[[
	LobbyLink

	The way out of the run. This place is a separate "dimension" the
	players are teleported into from the lobby, and when the run ends (or
	a player chooses to leave) this sends them back there.

	It works out where the lobby is (the place id the lobby sent in its
	teleport data, or GameConfig.Lobby.PlaceId), teleports the players
	with a summary of how the run went, and retries if Roblox refuses
	the teleport. If there is no lobby, or every attempt fails, it says
	so and the caller restarts the run in place instead, so nobody is
	ever stuck on a finished run.
]]

--[[
	THE FORMAT SENT BACK TO THE LOBBY

	    {
	        Version = 1,
	        Source = "Run",
	        Result = "Won" | "Lost" | "Left",
	        ReachedArea = "Room3",
	        Kills = 42,             -- this player's kills in the run
	        Money = 310,            -- money they ended the run with
	        CashEarned = 77,        -- Cash already saved to their data
	        SaveVersion = 12,       -- the save written just before the teleport
	    }

	Each player gets their own copy, so the lobby can show them their
	own result. The lifetime stats and the Cash are already saved to the
	player's data by RunManager before the teleport, so the lobby only
	needs this for showing a results screen, never for rewards. That way
	a teleport that fails part way can not duplicate or lose rewards.

	Each player's save is written just before their teleport. The lobby
	loads the same save as soon as they arrive, and the normal save when
	they leave this server can land after that. The lobby would then
	show (and later save over) their data from before the run, losing
	the XP and Cash it earned.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Core.RunManager at the end of a run.

	Reads:
	  Server.Game.Core.TeleportDataReader for the lobby's place id.
	  Game.Config.GameConfig.Lobby for the fallback place id, the retry
	  count and whether leaving early is allowed.

	Listens on:
	  ReplicatedStorage.Remotes.Events.ReturnToLobby, fired by
	  ClientGame.Controllers.RoomBannerController's "Back to lobby"
	  button. Only works when there is a lobby.

	Studio cannot teleport between places, so in a playtest every send
	fails and the run restarts in place, which is the right fallback.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)
local TeleportDataReader = require(script.Parent.TeleportDataReader)

local LobbyLink = {}

LobbyLink.Settings = {
	-- Seconds a player has to wait between two "Back to lobby" presses.
	LeaveCooldown = 5,
}

-- Fired with (Player) when a player asks to leave early, after they
-- have been sent. RunManager saves their stats first.
LobbyLink.PlayerLeaving = Instance.new("BindableEvent")

local LastLeave: { [Player]: number } = {}
local Sending: { [Player]: boolean } = {}

----------------------------------------------------------------------
-- WHERE THE LOBBY IS
----------------------------------------------------------------------

-- The lobby's place id, or 0 if there is no lobby to go back to.
function LobbyLink.GetLobbyPlaceId(): number
	local Data = TeleportDataReader.GetRunData()
	if Data and Data.LobbyPlaceId then
		return Data.LobbyPlaceId
	end
	return GameConfig.Lobby.PlaceId or 0
end

-- Whether there is somewhere to send players back to. Studio can never
-- teleport, so it always says no there.
function LobbyLink.HasLobby(): boolean
	if RunService:IsStudio() then
		return false
	end
	return LobbyLink.GetLobbyPlaceId() > 0
end

----------------------------------------------------------------------
-- SENDING
----------------------------------------------------------------------

-- Teleports Players back to the lobby. PayloadFor(Player) returns that
-- player's teleport data. Yields while it tries. Returns true if the
-- teleport was accepted by Roblox for everyone.
function LobbyLink.SendToLobby(PlayerList: { Player }, PayloadFor: ((Player) -> any)?): boolean
	local PlaceId = LobbyLink.GetLobbyPlaceId()
	if PlaceId <= 0 or RunService:IsStudio() then
		return false
	end

	-- One teleport per player so each carries their own result, all at
	-- the same time so a squad is not sent one by one behind each other's
	-- saves. Players already being sent are skipped.
	local AllOk = true
	local Pending = 0
	local AllDone = Instance.new("BindableEvent")
	local function SendOne(Player: Player)
		local Payload = PayloadFor and PayloadFor(Player) or {}
		Payload.Version = 1
		Payload.Source = "Run"
		-- See the note at the top.
		if DataManager.IsLoaded(Player) then
			DataManager.Save(Player)
			-- the lobby waits for this save to show up before loading them
			Payload.SaveVersion = DataManager.Get(Player, "SaveVersion")
		end

		local Sent = false
		for Attempt = 1, math.max(1, GameConfig.Lobby.TeleportRetries or 1) do
			local Ok, Error = pcall(function()
				local Options = Instance.new("TeleportOptions")
				Options:SetTeleportData(Payload)
				TeleportService:TeleportAsync(PlaceId, { Player }, Options)
			end)
			if Ok then
				Sent = true
				break
			end
			warn(string.format("[LobbyLink] teleport of %s failed (attempt %d): %s", Player.Name, Attempt, tostring(Error)))
			task.wait(GameConfig.Lobby.TeleportRetryDelay or 2)
		end
		if not Sent then
			Sending[Player] = nil
			AllOk = false
		end
	end
	for _, Player in ipairs(PlayerList) do
		if Player.Parent ~= Players or Sending[Player] then
			continue
		end
		Sending[Player] = true
		Pending += 1
		task.spawn(function()
			local Ok, Error = pcall(SendOne, Player)
			if not Ok then
				warn("[LobbyLink] sending " .. Player.Name .. " failed: " .. tostring(Error))
				Sending[Player] = nil
				AllOk = false
			end
			Pending -= 1
			if Pending == 0 then
				AllDone:Fire()
			end
		end)
	end
	if Pending > 0 then
		AllDone.Event:Wait()
	end
	AllDone:Destroy()
	return AllOk
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function LobbyLink.Init()
	local Events = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events")
	local ReturnToLobby = Events:FindFirstChild("ReturnToLobby")
	if not ReturnToLobby then
		ReturnToLobby = Instance.new("RemoteEvent")
		ReturnToLobby.Name = "ReturnToLobby"
		ReturnToLobby.Parent = Events
	end

	ReturnToLobby.OnServerEvent:Connect(function(Player)
		if not GameConfig.Lobby.AllowEarlyLeave or not LobbyLink.HasLobby() then
			return
		end
		if os.clock() - (LastLeave[Player] or 0) < LobbyLink.Settings.LeaveCooldown then
			return
		end
		LastLeave[Player] = os.clock()
		LobbyLink.PlayerLeaving:Fire(Player)
	end)

	-- A teleport that Roblox accepted can still fail on the way (the
	-- lobby server is full, say). Let the player be sent again.
	TeleportService.TeleportInitFailed:Connect(function(Player, Result, Message)
		warn(string.format("[LobbyLink] teleport of %s did not go through: %s %s", Player.Name, tostring(Result), tostring(Message)))
		Sending[Player] = nil
	end)

	Players.PlayerRemoving:Connect(function(Player)
		LastLeave[Player] = nil
		Sending[Player] = nil
	end)
end

return LobbyLink
