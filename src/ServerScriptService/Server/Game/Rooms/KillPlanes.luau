--[[
	KillPlanes

	Catches anything that falls out of the map. workspace.MainGameObj.
	KillPlanes holds one big invisible block under the whole level, and
	anything whose position drops below the top of it (while over its
	footprint) is dealt with here.

	Enemies are killed through EnemyBase:Die, never just deleted, so the
	wave count in WaveManager still goes down and the gate still opens.
	Players are put back at the player spawn of the area they were in
	and lose a little health, or are killed, depending on
	GameConfig.KillPlane.PlayerAction.

	It is a height test on a timer rather than a Touched event. A
	falling character can move further than the block is thick between
	two physics steps, and Touched would miss it, but it can never be
	below the plane without the height test noticing. It also means the
	block can be any size or shape of part and more can be added to the
	folder if a room ever has a pit.
]]

--[[
	What connects to this

	Reads:
	  Game.Config.GameConfig.KillPlane for the check rate and what
	  happens to players.
	  workspace.MainGameObj.KillPlanes, through Game.Data.RoomData, for
	  the parts.

	Uses:
	  Server.Game.Enemies.EnemyBase to kill enemies.
	  Server.Game.Core.PlayerStats to damage or kill players.
	  Server.Game.Rooms.RoomZones for the area a fallen player was in.
	  Server.Game.Rooms.RoomManager.PlacePlayer to put them back, which
	  goes through the anti cheat.

	Started by:
	  Server.Game.GameInit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local EnemyBase = require(script.Parent.Parent.Enemies.EnemyBase)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local RoomZones = require(script.Parent.RoomZones)

local KillPlanes = {}

local Running = false

-- Whether a point is under any kill plane.
function KillPlanes.IsBelow(Point: Vector3): boolean
	local Folder = RoomData.GetFolder("KillPlanes")
	if not Folder then
		return false
	end
	for _, Part in ipairs(Folder:GetDescendants()) do
		if Part:IsA("BasePart") then
			local Local = Part.CFrame:PointToObjectSpace(Point)
			local Half = Part.Size / 2
			if math.abs(Local.X) <= Half.X and math.abs(Local.Z) <= Half.Z and Local.Y <= Half.Y then
				return true
			end
		end
	end
	return false
end

local function CatchPlayer(Player: Player)
	local Config = GameConfig.KillPlane
	local Stats = PlayerStats.Get(Player)
	if Config.PlayerAction == "Kill" and Stats and Stats:IsAlive() then
		Stats:Kill("KillPlane")
		return
	end
	local RoomManager = require(script.Parent.RoomManager)
	local Area = RoomZones.GetArea(Player) or RoomData.Areas[1].Name
	RoomManager.PlacePlayer(Player, Area, 1)
	if Stats and Stats:IsAlive() and (Config.ReturnDamage or 0) > 0 then
		Stats:TakeDamage(Config.ReturnDamage, "KillPlane")
	end
end

function KillPlanes.Check()
	for _, Enemy in ipairs(EnemyBase.GetAlive()) do
		if Enemy.Root and Enemy.Root.Parent and KillPlanes.IsBelow(Enemy.Root.Position) then
			Enemy:Die(nil)
		end
	end
	for _, Player in ipairs(Players:GetPlayers()) do
		local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
		if Root and KillPlanes.IsBelow(Root.Position) then
			CatchPlayer(Player)
		end
	end
end

function KillPlanes.Init()
	if Running or not GameConfig.KillPlane.Enabled then
		return
	end
	Running = true
	task.spawn(function()
		while Running do
			local Ok, Error = pcall(KillPlanes.Check)
			if not Ok then
				warn("[KillPlanes] check failed: " .. tostring(Error))
			end
			task.wait(GameConfig.KillPlane.CheckRate)
		end
	end)
end

return KillPlanes
