--[[
	MapData

	Which map this server is running. Every map is played in this one
	place: the lobby sends the map's key (a key in Shared.GameText.Maps,
	"VeloCITY" or "RetroCity") in the teleport data, and
	Server.Game.Core.MapLoader puts that map in workspace and sets the
	workspace attribute MapKey, which both the server and the clients
	read through Current.

	A map that plays differently from VeloCITY gives RoomData.MapAreas
	and WaveData.MapAreas an entry under its key. A map without one uses
	the default areas and waves.
]]

local MapData = {}

-- the map used when nothing says otherwise (Studio, a direct join)
MapData.Default = "VeloCITY"

-- the workspace attribute MapLoader sets
MapData.Attribute = "MapKey"

-- the map this server is running
function MapData.Current(): string
	local Key = workspace:GetAttribute(MapData.Attribute)
	return type(Key) == "string" and Key ~= "" and Key or MapData.Default
end

-- calls Callback with the map key now and whenever it changes
function MapData.Watch(Callback: (string) -> ())
	workspace:GetAttributeChangedSignal(MapData.Attribute):Connect(function()
		Callback(MapData.Current())
	end)
	Callback(MapData.Current())
end

return MapData
