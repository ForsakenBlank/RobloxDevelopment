--[[
	Dasher

	A fast, fragile enemy that keeps moving. It circles its target just
	outside charge range, then lines up and charges in a straight line,
	hitting everyone it runs through. A red line on the floor shows the
	charge for its whole wind up, so it is dodged by stepping sideways,
	not by running away. Up close it falls back on a quick swipe.

	Everything it does is in its EnemyData entry (Charge and Melee
	attacks, PreferredDistance and StrafeSpeed for the circling), and
	EnemyAI runs it, so the class itself adds nothing. It exists so the
	registry has a class for every type and there is an obvious place to
	add Dasher only behaviour later.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Enemies.EnemyBase.

	Run by:
	  Server.Game.Enemies.EnemyAI, whose RunCharge does the charge.

	Registered in:
	  Server.Game.Enemies.EnemyRegistry. Spawned from Game.Data.WaveData
	  and by the Boss when it enrages.
]]

local EnemyBase = require(script.Parent.Parent.EnemyBase)

local Dasher = setmetatable({}, { __index = EnemyBase })
Dasher.__index = Dasher

return Dasher
