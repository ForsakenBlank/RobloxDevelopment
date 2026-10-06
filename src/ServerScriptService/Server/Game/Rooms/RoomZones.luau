--[[
	RoomZones

	Works out which area each player is currently standing in, and tells
	RoomManager when someone enters a new one. This is the detection
	behind the whole room progression.

	It does this with a volume check rather than a Touched event. Each
	area has an invisible part in workspace.MainGameObj.RoomZones, and
	this runs a point in box test of every player's HumanoidRootPart
	against those parts on a timer to get who is inside.

	Touched is the wrong tool here. This game has dashes, leaps,
	ziplines and wall runs, so a player crossing a thin trigger part
	between two physics steps can pass straight through it without
	Touched ever firing. A volume test asks where the player is right
	now, so speed cannot beat it. It is also server side, so it cannot
	be faked, and it does not need debouncing the way Touched does.

	Four checks a second is plenty. With 8 zones and at most 4 players
	that is a trivial amount of work, and nothing in the game needs to
	know about a room change faster than that.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.RoomData for the list of areas and their zone part names.
	  workspace.MainGameObj.RoomZones for the parts themselves. Each area
	  is either a part named the same as the area, or a folder named the
	  same as the area holding one or more parts (the map uses a folder
	  with a part called Room in it). Several parts in one folder count
	  as one area, so an L shaped room can be two boxes. They need to be
	  anchored, CanCollide off, Transparency 1, and tall enough to cover
	  a player who is mid air or wall running, because a player who
	  jumps over the top of a short zone would read as being nowhere.

	Reports to:
	  Server.Game.Rooms.RoomManager through the Entered signal, which is
	  what decides what happens when a player enters an area. This
	  module only says who is where.

	Also asked by:
	  Server.Game.Combat.Abilities.Teleport, to check that a teleport
	  destination is still inside the player's current area, which stops
	  the ability being used to skip a shut gate.
	  Server.Game.Core.RunManager and RoomManager, to find out if any
	  player is still behind when the run needs to pull everyone forward.
	  Server.Game.Rooms.WaveManager, to notice an enemy that has left
	  its area.

	Started by:
	  Server.Game.GameInit.

	A point in box test against the zone parts' own CFrame and size is
	used instead of an OverlapParams query. It needs no filter at all,
	so there is nothing to rebuild and nothing in workspace.Map gets
	tested.

	The zones should not overlap. If two zones cover the same space a
	player would read as being in both, so the first match in the
	RoomData order is taken, which keeps the result consistent.

	A player standing between two zones, in a corridor say, keeps the
	last area they were in rather than reading as nowhere.

	A dead player is still somewhere. Report them, and let RoomManager
	decide whether to ignore them, since it is the one that knows the
	run rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)

local RoomZones = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

RoomZones.Settings = {
	-- Studs of slack added to every side of a zone when testing a
	-- point, so standing right on the edge still counts.
	EdgePadding = 1,
	-- Attribute written on the Player with the area they are in, so
	-- the client and the Explorer can read it.
	AreaAttribute = "CurrentArea",
}

-- Fired with (Player, NewAreaName, OldAreaName) when a player moves
-- into a different area.
RoomZones.Entered = Instance.new("BindableEvent")

local ZoneParts: { [string]: { BasePart } } = {}
local CurrentArea: { [Player]: string } = {}
local Running = false

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Reads the zone parts for every area out of the map. Called once at
-- Init, and again if a lookup misses in case the map loaded late.
local function CollectZones()
	ZoneParts = {}
	local Folder = RoomData.GetFolder("RoomZones")
	if not Folder then
		return
	end
	for _, Area in ipairs(RoomData.Areas) do
		local Found = Folder:FindFirstChild(Area.Name)
		local Parts = {}
		if Found and Found:IsA("BasePart") then
			table.insert(Parts, Found)
		elseif Found then
			for _, Child in ipairs(Found:GetDescendants()) do
				if Child:IsA("BasePart") then
					table.insert(Parts, Child)
				end
			end
		end
		if #Parts == 0 then
			warn("[RoomZones] no zone part for " .. Area.Name .. " in " .. Folder:GetFullName())
		end
		ZoneParts[Area.Name] = Parts
	end
end

local function PointInPart(Point: Vector3, Part: BasePart): boolean
	local Local = Part.CFrame:PointToObjectSpace(Point)
	local Half = Part.Size / 2 + Vector3.one * RoomZones.Settings.EdgePadding
	return math.abs(Local.X) <= Half.X and math.abs(Local.Y) <= Half.Y and math.abs(Local.Z) <= Half.Z
end

----------------------------------------------------------------------
-- QUERIES
----------------------------------------------------------------------

-- Whether a world point is inside an area's zone.
function RoomZones.IsPointInArea(Point: Vector3, AreaName: string): boolean
	local Parts = ZoneParts[AreaName]
	if not Parts then
		return false
	end
	for _, Part in ipairs(Parts) do
		if PointInPart(Point, Part) then
			return true
		end
	end
	return false
end

-- The first area in RoomData order containing this point, or nil.
function RoomZones.GetAreaAt(Point: Vector3): string?
	for _, Area in ipairs(RoomData.Areas) do
		if RoomZones.IsPointInArea(Point, Area.Name) then
			return Area.Name
		end
	end
	return nil
end

-- The area a player was last seen in, or nil before the first check.
function RoomZones.GetArea(Player: Player): string?
	return CurrentArea[Player]
end

-- Every player whose last known area is this one.
function RoomZones.GetPlayersIn(AreaName: string): { Player }
	local List = {}
	for Player, Area in pairs(CurrentArea) do
		if Area == AreaName and Player.Parent == Players then
			table.insert(List, Player)
		end
	end
	return List
end

-- The zone parts for an area, for anything that needs the bounds.
function RoomZones.GetZoneParts(AreaName: string): { BasePart }
	return ZoneParts[AreaName] or {}
end

-- Forces a player's recorded area, for when the server moves them.
-- Fires Entered like a normal move would.
function RoomZones.SetArea(Player: Player, AreaName: string)
	local Old = CurrentArea[Player]
	if Old == AreaName then
		return
	end
	CurrentArea[Player] = AreaName
	Player:SetAttribute(RoomZones.Settings.AreaAttribute, AreaName)
	RoomZones.Entered:Fire(Player, AreaName, Old)
end

----------------------------------------------------------------------
-- CHECK
----------------------------------------------------------------------

-- One pass over every player. Public so a test can drive it.
function RoomZones.Check()
	for _, Player in ipairs(Players:GetPlayers()) do
		local Character = Player.Character
		local Root = Character and Character:FindFirstChild("HumanoidRootPart")
		if Root then
			local Area = RoomZones.GetAreaAt(Root.Position)
			if Area and Area ~= CurrentArea[Player] then
				RoomZones.SetArea(Player, Area)
			end
		end
	end
end

function RoomZones.Init()
	CollectZones()

	Players.PlayerRemoving:Connect(function(Player)
		CurrentArea[Player] = nil
	end)

	if Running then
		return
	end
	Running = true
	task.spawn(function()
		while Running do
			local Ok, Error = pcall(RoomZones.Check)
			if not Ok then
				warn("[RoomZones] check failed: " .. tostring(Error))
			end
			task.wait(GameConfig.Rooms.ZoneCheckRate)
		end
	end)
end

return RoomZones
