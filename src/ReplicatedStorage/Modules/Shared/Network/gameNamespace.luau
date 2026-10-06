--[[
	gameNamespace

	ByteNet packet definitions for the gameplay traffic that fires often
	enough that a normal RemoteEvent would be wasteful. That is mainly
	the combat packets, so a weapon attack going up with its aim
	direction, a hit result coming back down, and the enemy position or
	state updates that drive client side visuals.

	This sits next to the existing namespace module rather than being
	added to it, so the movement framework's packets stay untouched and
	the game packets can be changed without any risk of breaking
	movement.

	Anything that fires rarely, like a room being entered or a purchase
	going through, should stay on the plain RemoteEvents in
	ReplicatedStorage.Remotes instead. Those are easier to read and the
	saving is not worth it.
]]

--[[
	What connects to this

	Built the same way as ReplicatedStorage.Modules.Shared.Network.
	namespace, using ByteNet.defineNamespace with a different namespace
	name so the two do not clash.

	Server.Game.Combat.CombatService listens on the attack packets and is
	the only server module that should. It validates the request and then
	hands off to Server.Game.Combat.Weapons.WeaponBase.

	ClientGame.Controllers.CombatInput sends on those packets when the
	player clicks.

	Sending goes through ReplicatedStorage.Modules.Shared.Network.Network
	with Network.Fire, but note that Network.Fire currently indexes the
	old namespace module directly, so it needs either a second argument
	for which namespace to use or its own wrapper here. Do not edit
	Network.Fire in a way that changes behaviour for the movement
	modules that already call it.

	Packet struct fields have to match exactly on both sides. If a field
	is added here the client and server both need rebuilding, and a
	mismatch shows up as a decode error rather than a clear message.
]]
