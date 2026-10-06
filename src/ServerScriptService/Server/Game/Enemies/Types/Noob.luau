--[[
	Noob

	The basic enemy. It walks at the nearest player and does a melee
	attack when it gets in range, and that is all it does. No ranged
	attack and no special behaviour, which is what makes it the one that
	fills out most of the waves.

	Because it is simple it is the one to build first and test the whole
	spawn, damage and death path with, before the more complicated
	enemies get written.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Enemies.EnemyBase, which already handles its health,
	  damage taking, death and money drop.

	Reads:
	  Its own entry in Game.Data.EnemyData for health, speed, damage,
	  attack range and attack cooldown.

	Uses:
	  Server.Game.Enemies.EnemyAI for the decision of whether to move or
	  attack, and for the melee itself. The generic melee there (plant,
	  red flash, wind up, box in front, DamageService) is exactly what a
	  Noob does, so this module has nothing to override. It is still its
	  own class so a Noob specific tweak has somewhere to go.

	Registered in:
	  Server.Game.Enemies.EnemyRegistry under the key "Noob", which is
	  the same string used in Game.Data.WaveData.

	Also summoned by:
	  Server.Game.Enemies.Types.Necromancer. A summoned Noob is built the
	  same way as a spawned one, with SummonedBy set, so nothing special
	  is needed here.
]]

local EnemyBase = require(script.Parent.Parent.EnemyBase)

local Noob = setmetatable({}, { __index = EnemyBase })
Noob.__index = Noob

return Noob
