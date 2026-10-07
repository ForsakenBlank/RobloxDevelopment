--[[
	MapLoader

	Puts the map the lobby picked into workspace, so every map can live
	in this one place.

	How the maps are laid out in Studio (workspace is not synced by Rojo,
	so they are built there as normal):
	  workspace.Maps.<MapKey>     one Folder or Model per map, named by its
	                              key in Shared.GameText.Maps ("VeloCITY",
	                              "RetroCity")
	    MainGameObj               that map's gates, zones, spawns, podiums
	                              and kill planes, the same as now
	    Map, anything else        its scenery

	When the server starts, workspace.Maps is moved to ServerStorage
	straight away, so no client ever downloads every map. Once the first
	player is in, their teleport data says which map (TeleportDataReader,
	the Map field) and that map's children are moved into workspace. The
	rest of the game then finds workspace.MainGameObj exactly as before.

	Without a workspace.Maps folder nothing is moved, and the MainGameObj
	already in workspace is used as the default map, which is how the
	place works today.
]]

--[[
	What connects to this

	Started first by Server.Game.GameInit. Its Init waits for the first
	player, so every service after it starts with the map in place.

	Sets the workspace attribute MapKey (Game.Data.MapData), and switches
	Game.Data.RoomData and Game.Data.WaveData to the map's areas.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MapData = require(ReplicatedStorage.Modules.Game.Data.MapData)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local WaveData = require(ReplicatedStorage.Modules.Game.Data.WaveData)
local TeleportDataReader = require(script.Parent.TeleportDataReader)

local MapLoader = {}

MapLoader.Settings = {
	-- the folder in workspace that holds every map
	FolderName = "Maps",
	-- seconds to wait for a first player before loading the default map
	PlayerWait = 60,
}

local Loaded: string? = nil

local function SetMap(Key: string)
	Loaded = Key
	workspace:SetAttribute(MapData.Attribute, Key)
	RoomData.UseMap(Key)
	WaveData.UseMap(Key)
	print("[MapLoader] map: " .. Key)
end

-- the map key the first player's teleport data asks for
local function WantedMap(): string
	local Deadline = os.clock() + MapLoader.Settings.PlayerWait
	while #Players:GetPlayers() == 0 and os.clock() < Deadline do
		task.wait(0.1)
	end
	local Data = TeleportDataReader.GetRunData()
	return Data and Data.Map or MapData.Default
end

-- The map this server is running, once Init has finished.
function MapLoader.GetLoaded(): string
	return Loaded or MapData.Current()
end

function MapLoader.Init()
	local Folder = workspace:FindFirstChild(MapLoader.Settings.FolderName)
	if not Folder then
		-- one map built straight into workspace
		SetMap(MapData.Default)
		return
	end

	-- out of workspace before anyone can download it
	Folder.Parent = ServerStorage

	local Key = WantedMap()
	local Chosen = Folder:FindFirstChild(Key)
	if not Chosen then
		warn("[MapLoader] no map called " .. tostring(Key) .. " in workspace." .. MapLoader.Settings.FolderName .. ", using " .. MapData.Default)
		Key = MapData.Default
		Chosen = Folder:FindFirstChild(Key)
	end
	if not Chosen then
		warn("[MapLoader] no default map either, the run has nothing to play on")
		SetMap(Key)
		return
	end

	if workspace:FindFirstChild(RoomData.MapFolder) then
		warn("[MapLoader] workspace already has a " .. RoomData.MapFolder .. ", it should be inside a map in workspace." .. MapLoader.Settings.FolderName)
	end
	for _, Child in ipairs(Chosen:GetChildren()) do
		Child.Parent = workspace
	end
	SetMap(Key)

	-- Studio keeps the other maps around for editing, a live server drops them
	if not RunService:IsStudio() then
		Folder:Destroy()
	end
end

return MapLoader
