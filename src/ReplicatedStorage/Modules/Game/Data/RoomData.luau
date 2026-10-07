--[[
	RoomData

	Describes the layout of the built map rather than what spawns in it.
	The map is one continuous level in workspace.MainGameObj, split into
	8 areas by 7 gates, so this holds that order and what each gate
	joins.

	The order is Spawn, Room1, Room2, Shop1, Room3, Room4, Shop2,
	BossRoom, and the gates map onto it like this:
	  Gate1  Spawn to Room1
	  Gate2  Room1 to Room2
	  Gate3  Room2 to Shop1
	  Gate4  Shop1 to Room3
	  Gate5  Room3 to Room4
	  Gate6  Room4 to Shop2
	  Gate7  Shop2 to BossRoom

	Each area entry holds its name, whether it is a combat area, a shop
	or the boss room, the gate that leads into it, the gate that leads
	out of it, and how it is opened. Combat gates open when every wave in
	the area is cleared. Shop gates open on a proximity prompt instead,
	so the players leave the shop when they are ready rather than being
	pushed out.

	Keeping it as an ordered list means the progression can be changed,
	or a room added, without touching RoomManager.
]]

--[[
	What connects to this

	Points at the map:
	  workspace.MainGameObj.Gates holds Gate1 to Gate7, each a Model with
	  a Part inside it.
	  workspace.MainGameObj.RoomZones needs one part per area, named the
	  same as the area in this table. That part is the volume used to
	  tell whether a player is in that area, so it wants to be anchored,
	  CanCollide off, Transparency 1, and tall enough that a player
	  wall running or mid leap is still inside it.
	  workspace.MainGameObj.PlayerSpawns has a folder per area holding
	  the points players get placed at when they are pulled forward.
	  workspace.MainGameObj.EnemySpawns has a folder per combat area
	  holding the spawn platforms.
	  workspace.MainGameObj.ShopPodiums.Shop1 and Shop2 hold Podium1 to
	  Podium4 for the shop areas.
	  workspace.MainGameObj.KillPlanes catches anything that falls out.

	Read by:
	  Server.Game.Rooms.RoomManager for the area order and what opens
	  each gate.
	  Server.Game.Rooms.GateController to find the gate model for an
	  area.
	  Server.Game.Rooms.RoomZones to find the zone part for an area.
	  Server.Game.Enemies.EnemySpawner for the EnemySpawns folder.
	  Server.Game.Shop.ShopManager for the podium folder of a shop.
	  Server.Game.Combat.Abilities.Teleport, which needs the current
	  area's zone to stop a player teleporting through a shut gate.

	Area names in here have to match three things: the zone part names in
	RoomZones, the folder names in EnemySpawns and PlayerSpawns, and the
	keys in Game.Data.WaveData for the combat areas.

	Note the map has 4 combat rooms plus the boss room. The design
	document says 5 combat rooms, so either a room is missing from the
	map or the document needs updating. Adding a fifth is only a new
	entry in this list, an extra gate, and a new key in WaveData.
]]

-- Note on when changes take effect. The area list is read once when
-- the run is set up, so it needs a restart. The Gate table is read
-- each time a gate opens, so it can be tuned live.

local MapData = require(script.Parent.MapData)

local RoomData = {}

----------------------------------------------------------------------
-- MAP FOLDERS
----------------------------------------------------------------------

-- Where in workspace everything lives. Change these if the map is
-- reorganised rather than hunting through the room modules.
RoomData.MapFolder = "MainGameObj"
RoomData.Folders = {
	Gates = "Gates",
	RoomZones = "RoomZones",
	PlayerSpawns = "PlayerSpawns",
	EnemySpawns = "EnemySpawns",
	ShopPodiums = "ShopPodiums",
	KillPlanes = "KillPlanes",
}

----------------------------------------------------------------------
-- GATES
----------------------------------------------------------------------

-- How every gate behaves when it opens. Individual areas can override
-- any of these in their own Gate table.
RoomData.Gate = {
	-- "Sink" lowers the gate part into the floor, "Fade" makes it
	-- transparent and non collidable, "Destroy" removes it.
	OpenStyle = "Sink",
	-- Seconds the open animation takes.
	OpenTime = 1.5,
	-- Studs it sinks when OpenStyle is "Sink". The gates are 32 tall
	-- and sit on the floor, so this has to be more than 32 or the
	-- open gate still blocks the doorway.
	SinkDistance = 34,
	Sound = "GateOpen",
	CloseSound = "GateClose",
	-- The text on the proximity prompt for prompt opened gates, and
	-- how long the key has to be held.
	PromptText = "Continue",
	PromptHoldTime = 1,
	-- true means every alive player has to be within PromptRadius of
	-- the gate before a prompt opens it, so nobody gets left behind in
	-- a shop.
	PromptNeedsEveryone = true,
	PromptRadius = 25,
}

----------------------------------------------------------------------
-- AREAS
----------------------------------------------------------------------

-- In progression order. Each area has:
--   Name       must match the RoomZones part, the spawn folders and,
--              for combat areas, the WaveData key
--   Kind       "Spawn", "Combat", "Shop" or "Boss"
--   GateIn     the gate players come through to enter. nil for the
--              first area
--   GateOut    the gate that leads onward. nil for the last area
--   OpenRule   how GateOut opens:
--              "Clear"   when every wave in WaveData is dead
--              "Prompt"  when a player uses the proximity prompt
--              "Timer"   after OpenAfter seconds in the area
--              "Never"   it stays shut, for the final area
--   Banner     text for the room banner on entry. nil uses the
--              WaveData banner for combat areas or the Name otherwise
--   Gate       optional overrides for RoomData.Gate on this area's
--              GateOut only
--   Podiums    shops only, how many podiums get stocked
--   IsRunEnd   true means clearing this area wins the run

RoomData.Areas = {
	{
		Name = "Spawn",
		Kind = "Spawn",
		GateIn = nil,
		GateOut = "Gate1",
		OpenRule = "Prompt",
		Banner = "Get Ready",
		Gate = { PromptText = "Start" },
	},
	{
		Name = "Room1",
		Kind = "Combat",
		GateIn = "Gate1",
		GateOut = "Gate2",
		OpenRule = "Clear",
	},
	{
		Name = "Room2",
		Kind = "Combat",
		GateIn = "Gate2",
		GateOut = "Gate3",
		OpenRule = "Clear",
	},
	{
		Name = "Shop1",
		Kind = "Shop",
		GateIn = "Gate3",
		GateOut = "Gate4",
		OpenRule = "Prompt",
		Banner = "Shop",
		Podiums = 4,
	},
	{
		Name = "Room3",
		Kind = "Combat",
		GateIn = "Gate4",
		GateOut = "Gate5",
		OpenRule = "Clear",
	},
	{
		Name = "Room4",
		Kind = "Combat",
		GateIn = "Gate5",
		GateOut = "Gate6",
		OpenRule = "Clear",
	},
	{
		Name = "Shop2",
		Kind = "Shop",
		GateIn = "Gate6",
		GateOut = "Gate7",
		OpenRule = "Prompt",
		Banner = "Shop",
		Podiums = 4,
	},
	{
		Name = "BossRoom",
		Kind = "Boss",
		GateIn = "Gate7",
		GateOut = nil,
		OpenRule = "Never",
		Banner = "Boss",
		IsRunEnd = true,
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Name to entry lookup, built once so the list above stays the single
-- source of truth.
local AreaByName = {}
local IndexByName = {}
local function Index()
	table.clear(AreaByName)
	table.clear(IndexByName)
	for Position, Area in ipairs(RoomData.Areas) do
		AreaByName[Area.Name] = Area
		IndexByName[Area.Name] = Position
	end
end
Index()

----------------------------------------------------------------------
-- MAPS
----------------------------------------------------------------------

-- Areas for maps that are laid out differently, by map key (see
-- Game.Data.MapData), in the same format as Areas above. A map not
-- listed here uses Areas as it is.
RoomData.MapAreas = {}

local DefaultAreas = table.clone(RoomData.Areas)

-- switches Areas to one map's list, in place, so code holding RoomData.Areas sees the change
function RoomData.UseMap(Key: string)
	local List = RoomData.MapAreas[Key] or DefaultAreas
	table.clear(RoomData.Areas)
	for _, Area in ipairs(List) do
		table.insert(RoomData.Areas, Area)
	end
	Index()
end

MapData.Watch(RoomData.UseMap)

-- Looks an area up by name and warns rather than erroring if the name
-- is wrong, which usually means a zone part or folder is misnamed.
function RoomData.GetArea(AreaName: string)
	local Area = AreaByName[AreaName]
	if not Area then
		warn("[RoomData] no area called " .. tostring(AreaName))
	end
	return Area
end

-- Position of an area in the progression, 1 for Spawn.
function RoomData.GetIndex(AreaName: string): number?
	return IndexByName[AreaName]
end

-- The area after this one, or nil at the end.
function RoomData.GetNext(AreaName: string)
	local Index = IndexByName[AreaName]
	return Index and RoomData.Areas[Index + 1] or nil
end

-- The gate settings for an area's GateOut, with any per area overrides
-- laid over the defaults.
function RoomData.GetGateSettings(AreaName: string)
	local Settings = table.clone(RoomData.Gate)
	local Area = AreaByName[AreaName]
	if Area and Area.Gate then
		for Key, Value in pairs(Area.Gate) do
			Settings[Key] = Value
		end
	end
	return Settings
end

-- The workspace folder for the map, or nil with a warning if it has
-- been renamed.
function RoomData.GetMap(): Instance?
	local Map = workspace:FindFirstChild(RoomData.MapFolder)
	if not Map then
		warn("[RoomData] workspace has no folder called " .. RoomData.MapFolder)
	end
	return Map
end

-- A named folder inside the map, such as "Gates", or nil with a
-- warning.
function RoomData.GetFolder(Key: string): Instance?
	local Map = RoomData.GetMap()
	local FolderName = RoomData.Folders[Key]
	if not Map or not FolderName then
		return nil
	end
	local Folder = Map:FindFirstChild(FolderName)
	if not Folder then
		warn("[RoomData] " .. RoomData.MapFolder .. " has no folder called " .. FolderName)
	end
	return Folder
end

return RoomData
