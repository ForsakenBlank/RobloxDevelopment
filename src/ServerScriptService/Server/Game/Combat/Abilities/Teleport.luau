--[[
	Teleport

	Instantly moves the player to wherever their cursor is pointing. This
	is Teleport from the function plan. It is the fastest way around a
	room, and it lands with a strike: every enemy near the arrival point
	takes damage and is knocked away, and the player cannot be hurt for
	a moment after arriving. So it works both as an escape and as a way
	into a crowd, which pairs well with the Sword and Shotgun.

	Because it is a position change and the position comes from the
	client, this is the ability most open to being abused, so the
	distance limit and the check that the destination is somewhere valid
	both matter more here than anywhere else.

	On the client it is a two step ability: the key (E) shows a ghost at
	the cursor, the click sends the position here. That is all in
	ClientGame.Controllers.AbilityInput. This module only ever sees the
	final position, and treats it as a request.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Abilities.AbilityBase, which has taken the
	  energy and started the cooldown already.

	Reads:
	  The Teleport entry in Game.Data.AbilityData for the maximum
	  distance, the line of sight and area rules, and the arrival
	  height.

	Uses:
	  ServerScriptService.Server.Modules.AntiCheat Teleport, which moves
	  the character and tells the movement detector to expect the jump,
	  rather than setting the CFrame directly.
	  Server.Game.Combat.HitDetection for the line of sight ray.
	  Server.Game.Rooms.RoomZones to keep the destination inside the
	  player's current area so a shut gate cannot be skipped.
	  Game.Shared.CombatFX for the flash at both ends.

	The destination is clamped along the line from the player, so a
	client sending a position on the far side of the map only ever
	gets the nearest point on that line within MaxDistance. If the
	line of sight rule is on and the map is in the way, the arrival is
	pulled back to just in front of whatever was hit.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local AbilityBase = require(script.Parent.AbilityBase)
local HitDetection = require(script.Parent.Parent.HitDetection)

local Teleport = setmetatable({}, { __index = AbilityBase })
Teleport.__index = Teleport

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

Teleport.Settings = {
	-- When the map blocks the line, arrive this far back from the hit.
	BlockedPullback = 2,
	-- Face the same way after arriving.
	KeepFacing = true,
	-- How finely the line is checked when pulling a destination back
	-- inside the current area.
	AreaClampSteps = 20,
}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Works out where the player actually ends up from what the client
-- asked for. Public so the client can run the same maths for the
-- ghost if it wants to.
function Teleport:ResolveDestination(Context, Requested: Vector3): Vector3
	local Data = self.Data
	local Origin = Context.Root.Position
	local Offset = Requested - Origin
	if Offset.Magnitude > Data.MaxDistance then
		Offset = Offset.Unit * Data.MaxDistance
	end
	local Destination = Origin + Offset

	if Data.RequireLineOfSight then
		local Result = workspace:Raycast(Origin, Destination - Origin, HitDetection.MapRaycastParams({ Context.Character }))
		if Result then
			local Back = (Origin - Result.Position)
			Back = Back.Magnitude > 0.01 and Back.Unit or Vector3.zero
			Destination = Result.Position + Back * Teleport.Settings.BlockedPullback
		end
	end

	-- A teleport can never land inside a different area's zone, which
	-- is what would put the player on the far side of a shut gate.
	-- Points that are in no zone at all (a corridor) are fine, so a
	-- player standing between two rooms can still teleport. A blocked
	-- destination walks back along the line to the last allowed point.
	if Data.StayInCurrentArea then
		local RoomZones = require(script.Parent.Parent.Parent.Rooms.RoomZones)
		local Area = RoomZones.GetArea(Context.Player)
		local function Allowed(Point: Vector3): boolean
			local At = RoomZones.GetAreaAt(Point)
			return At == nil or At == Area
		end
		if Area and not Allowed(Destination) then
			local Steps = Teleport.Settings.AreaClampSteps
			local Found = Origin
			for Step = Steps - 1, 1, -1 do
				local Point = Origin:Lerp(Destination, Step / Steps)
				if Allowed(Point) then
					Found = Point
					break
				end
			end
			Destination = Found
		end
	end

	return Destination + Vector3.new(0, Data.ArrivalHeightOffset or 0, 0)
end

----------------------------------------------------------------------
-- USE
----------------------------------------------------------------------

function Teleport:OnUse(Context)
	local Data = self.Data
	local Root = Context.Root
	local Destination = self:ResolveDestination(Context, Context.AimPosition)

	CombatFX.Broadcast("Teleport_Out", Context.Character, { Position = Root.Position })

	if not Data.KeepVelocity then
		HelperFunctions.clearVelocity(Root)
	end

	local Target = Teleport.Settings.KeepFacing and (Root.CFrame.Rotation + Destination) or CFrame.new(Destination)
	AntiCheat.Teleport(Context.Player, Target)
	AntiCheat.GrantException(Context.Player, Data.AntiCheatGrace or 1)

	CombatFX.Broadcast("Teleport_In", Context.Character, { Position = Destination, Radius = Data.Strike and Data.Strike.Radius or 0 })

	-- The arrival i-frames, from GameConfig.IFrames.Abilities.Teleport,
	-- counted from the arrival rather than the key press.
	local IFrames = require(game:GetService("ReplicatedStorage").Modules.Game.Config.GameConfig).IFrames
	local Arrival = IFrames and IFrames.Enabled and IFrames.Abilities.Teleport
	if type(Arrival) == "number" and Arrival > 0 then
		local Stats = require(script.Parent.Parent.Parent.Core.PlayerStats).Get(Context.Player)
		if Stats then
			Stats:SetInvulnerable(Arrival)
		end
	end

	-- The strike where the player lands.
	local Strike = Data.Strike
	if Strike and (Strike.Damage or 0) > 0 then
		local StatFormulas = require(game:GetService("ReplicatedStorage").Modules.Game.Shared.StatFormulas)
		local DamageService = require(script.Parent.Parent.DamageService)
		local Hits = HitDetection.Sphere(Destination, Strike.Radius, { Side = "Enemies", Origin = Destination })
		for _, Hit in ipairs(Hits) do
			local Damage = StatFormulas.FalloffDamage(Strike.Damage, Hit.Distance, Strike.Radius, Strike.Falloff)
			DamageService.ApplyDamage(Hit.Model, Damage, Context.Player, {
				Source = self.Name,
				Knockback = Strike.Knockback,
				From = Destination,
				HitSound = "SwordHit",
			})
		end
	end

	return { Destination = Destination }
end

return Teleport
