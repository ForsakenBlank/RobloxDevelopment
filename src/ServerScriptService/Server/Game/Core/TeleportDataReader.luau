--[[
	TeleportDataReader

	Reads the settings the lobby place sends across when it teleports the
	players into this place (the run "dimension"). On the server that
	means player:GetJoinData().TeleportData, which is the only
	trustworthy way to get it, because the client side
	TeleportService:GetLocalPlayerTeleportData can be faked.

	What it looks for is the difficulty, the party size and who is in
	the party, the lobby's place id (so the run knows where to send
	everyone back) and, optionally, each player's loadout.

	When the place is opened straight from Studio, or joined without a
	teleport, there is no teleport data. Read then returns nil and
	Server.Game.Core.RunSetup falls back to "Normal" difficulty and a
	live count of players, and the run restarts in place when it ends.
	That fallback must keep working even with the lobby finished.
]]

--[[
	THE FORMAT THE LOBBY SENDS

	The lobby teleports the whole party together, ideally into a
	reserved server, with this table as the teleport data:

	    local Options = Instance.new("TeleportOptions")
	    Options.ShouldReserveServer = true
	    Options:SetTeleportData({
	        Version = 1,
	        Source = "Lobby",
	        Difficulty = "Normal",            -- a key in DifficultyConfig
	        Map = "VeloCITY",                  -- which map, for MapBest and MapRuns
	        PartySize = #PartyPlayers,         -- how many are coming
	        PartyUserIds = { 111, 222 },       -- who is coming
	        LobbyPlaceId = game.PlaceId,       -- where to send them back
	        Loadouts = {                        -- optional, keyed by
	            ["111"] = {                     -- UserId as a string
	                Weapons = { "Sword", "Pistol" },
	                Abilities = { "StunSlam", "HealBurst" },
	            },
	        },
	    })
	    TeleportService:TeleportAsync(RunPlaceId, PartyPlayers, Options)

	Every field is optional and checked here, so a missing or bad value
	falls back rather than breaking the run. Anything else in the table
	is ignored.

	The lobby also writes the chosen loadout into the player's save
	(both places are in the same experience, so they share DataStores).
	The Loadouts field is there so the choice still arrives if that save
	has not reached this server yet.

	When the run ends, Server.Game.Core.LobbyLink sends everyone back to
	LobbyPlaceId with teleport data of its own, written down there.
]]

--[[
	What connects to this

	Called by:
	  Server.Game.Core.RunSetup, for the difficulty and party size when
	  the run is locked in, and for each player's loadout.
	  Server.Game.Core.LobbyLink, for the lobby's place id.

	The difficulty string gets looked up in Game.Config.DifficultyConfig,
	so the strings the lobby sends have to match the keys in that table
	exactly.

	GetJoinData is ready on the server as soon as the player object
	exists, but an empty read is still handled rather than assumed away,
	and a missing read never stops the run starting.

	Multiplayer note: every player arriving in the same teleport carries
	the same teleport data, so the run settings come from the first
	player whose data is valid.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DifficultyConfig = require(ReplicatedStorage.Modules.Game.Config.DifficultyConfig)

local TeleportDataReader = {}

TeleportDataReader.Settings = {
	-- The Version this place understands. Newer data is still read, a
	-- warning just goes to the output.
	Version = 1,
	-- Largest party that is believed. Anything bigger is clamped.
	MaxPartySize = 8,
}

-- Per player, the cleaned up data (or false for "read, nothing there").
local Cache: { [Player]: any } = {}
-- The first valid table seen, which the run settings come from.
local RunData = nil

----------------------------------------------------------------------
-- CLEANING
----------------------------------------------------------------------

local function CleanNames(List: any): { string }?
	if type(List) ~= "table" then
		return nil
	end
	local Out = {}
	for Index = 1, 2 do
		if type(List[Index]) ~= "string" then
			return nil
		end
		Out[Index] = List[Index]
	end
	return Out
end

-- Turns whatever arrived into a table with only known, checked fields,
-- or nil if it is not lobby data at all.
local function Clean(Raw: any)
	if type(Raw) ~= "table" then
		return nil
	end
	local Data = {}

	if type(Raw.Version) == "number" and Raw.Version > TeleportDataReader.Settings.Version then
		warn("[TeleportDataReader] teleport data is version " .. Raw.Version .. ", this place reads version " .. TeleportDataReader.Settings.Version)
	end

	if type(Raw.Difficulty) == "string" and DifficultyConfig.Difficulties[Raw.Difficulty] then
		Data.Difficulty = Raw.Difficulty
	end

	-- only used to file the end of run stats under the right map
	if type(Raw.Map) == "string" and #Raw.Map > 0 and #Raw.Map <= 40 then
		Data.Map = Raw.Map
	end

	if type(Raw.PartySize) == "number" and Raw.PartySize == Raw.PartySize then
		Data.PartySize = math.clamp(math.floor(Raw.PartySize), 1, TeleportDataReader.Settings.MaxPartySize)
	end

	if type(Raw.PartyUserIds) == "table" then
		local Ids = {}
		for _, Id in ipairs(Raw.PartyUserIds) do
			if type(Id) == "number" then
				table.insert(Ids, Id)
			end
		end
		if #Ids > 0 then
			Data.PartyUserIds = Ids
			Data.PartySize = Data.PartySize or math.min(#Ids, TeleportDataReader.Settings.MaxPartySize)
		end
	end

	if type(Raw.LobbyPlaceId) == "number" and Raw.LobbyPlaceId > 0 then
		Data.LobbyPlaceId = math.floor(Raw.LobbyPlaceId)
	end

	if type(Raw.Loadouts) == "table" then
		Data.Loadouts = {}
		for Key, Entry in pairs(Raw.Loadouts) do
			if type(Entry) == "table" then
				local Weapons = CleanNames(Entry.Weapons)
				local Abilities = CleanNames(Entry.Abilities)
				if Weapons and Abilities then
					Data.Loadouts[tostring(Key)] = { Weapons = Weapons, Abilities = Abilities }
				end
			end
		end
	end

	-- Nothing recognisable means this did not come from the lobby.
	if next(Data) == nil then
		return nil
	end
	Data.FromLobby = true
	return Data
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

-- The cleaned teleport data a player arrived with, or nil if they did
-- not come from the lobby. Cached, so it is safe to call often.
function TeleportDataReader.Read(Player: Player)
	local Cached = Cache[Player]
	if Cached ~= nil then
		return Cached or nil
	end
	local Ok, JoinData = pcall(function()
		return Player:GetJoinData()
	end)
	local Data = Ok and type(JoinData) == "table" and Clean(JoinData.TeleportData) or nil
	Cache[Player] = Data or false
	if Data and not RunData then
		RunData = Data
	end
	return Data
end

-- The run settings: the first valid lobby data any player brought, or
-- nil if nobody came from the lobby.
function TeleportDataReader.GetRunData()
	if RunData then
		return RunData
	end
	for _, Player in ipairs(Players:GetPlayers()) do
		local Data = TeleportDataReader.Read(Player)
		if Data then
			return Data
		end
	end
	return nil
end

-- The loadout the lobby sent for one player, or nil.
function TeleportDataReader.GetLoadout(Player: Player)
	local Data = TeleportDataReader.Read(Player) or TeleportDataReader.GetRunData()
	local Loadouts = Data and Data.Loadouts
	return Loadouts and Loadouts[tostring(Player.UserId)] or nil
end

Players.PlayerRemoving:Connect(function(Player)
	Cache[Player] = nil
end)

return TeleportDataReader
