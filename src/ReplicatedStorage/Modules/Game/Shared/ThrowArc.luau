--[[
	ThrowArc

	The maths of a thrown item's arc, shared by the server (which throws
	it for real through ProjectileService) and the client (which draws
	the trajectory while the player is aiming). Both use the same
	functions, so the arc the player sees is the arc the item flies.

	A throw leaves from just above and in front of the player, aimed a
	little high so that with gravity it comes down on the aim point.
]]

--[[
	What connects to this

	Used by:
	  Server.Game.Shop.ShopItems for the Molotov throw.
	  ClientGame.Controllers.InventoryController for the aiming arc.
	The throw numbers (Speed, Gravity, MaxRange) are the item's Throw
	table in Game.Data.ShopItemData.
]]

local ThrowArc = {}

ThrowArc.Settings = {
	-- Studs above the root a throw leaves from, and how far in front.
	OriginHeight = 2,
	OriginForward = 1.5,
}

-- Keeps the aim point within MaxRange studs of the thrower.
function ThrowArc.ClampAim(RootPosition: Vector3, Aim: Vector3, MaxRange: number): Vector3
	local Offset = Aim - RootPosition
	if Offset.Magnitude > MaxRange then
		return RootPosition + Offset.Unit * MaxRange
	end
	return Aim
end

-- Where the throw leaves from, facing the aim point.
function ThrowArc.Origin(RootPosition: Vector3, Aim: Vector3): Vector3
	local Flat = (Aim - RootPosition) * Vector3.new(1, 0, 1)
	local Facing = Flat.Magnitude > 0.01 and Flat.Unit or Vector3.new(0, 0, -1)
	return RootPosition + Vector3.new(0, ThrowArc.Settings.OriginHeight, 0) + Facing * ThrowArc.Settings.OriginForward
end

-- The launch velocity: straight at the aim point, lifted by how far
-- gravity will pull it down on the way.
function ThrowArc.Velocity(Origin: Vector3, Aim: Vector3, Speed: number, Gravity: number): Vector3
	local Distance = (Aim - Origin).Magnitude
	local Time = Distance / Speed
	local Lifted = Aim + Vector3.new(0, 0.5 * Gravity * Time * Time, 0)
	local Direction = Lifted - Origin
	if Direction.Magnitude < 0.01 then
		return Vector3.new(0, 0, -Speed)
	end
	return Direction.Unit * Speed
end

-- Where the item is T seconds after leaving.
function ThrowArc.PositionAt(Origin: Vector3, Velocity: Vector3, Gravity: number, T: number): Vector3
	return Origin + Velocity * T - Vector3.new(0, 0.5 * Gravity * T * T, 0)
end

-- Follows the arc until it hits something. Returns the points along
-- it (Step seconds apart) and where it landed, or nil if it never did
-- within MaxTime.
function ThrowArc.Trace(Origin: Vector3, Velocity: Vector3, Gravity: number, Params: RaycastParams, Step: number, MaxTime: number): ({ Vector3 }, Vector3?)
	local Points = { Origin }
	local Previous = Origin
	local T = 0
	while T < MaxTime do
		T += Step
		local Next = ThrowArc.PositionAt(Origin, Velocity, Gravity, T)
		local Hit = workspace:Raycast(Previous, Next - Previous, Params)
		if Hit then
			table.insert(Points, Hit.Position)
			return Points, Hit.Position
		end
		table.insert(Points, Next)
		Previous = Next
	end
	return Points, nil
end

return ThrowArc
