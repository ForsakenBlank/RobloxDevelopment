--[[
	Bob

	The heavy enemy. Slow, a lot of health, and hits hard in melee. He
	also has a long range attack so he is still a threat while walking
	towards you, which is what makes him different from the Noob rather
	than just a bigger version of it.

	So he has two attacks, a heavy melee for close range and a thrown
	rock for when the player is far away, each with their own cooldown
	so he cannot use both at once.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Enemies.EnemyBase for health, damage taking and death.

	Reads:
	  His entry in Game.Data.EnemyData, which holds both the melee and
	  the ranged attack numbers, their ranges and their separate
	  cooldowns.

	Uses:
	  Server.Game.Enemies.EnemyAI for the range decision, which picks
	  melee when close (higher priority) and the throw when the ranged
	  cooldown is ready and the player is further than its MinRange.
	  The throw goes through Server.Game.Combat.ProjectileService with
	  Side "Players", so it cannot hit the Noobs in front of him.

	Registered in:
	  Server.Game.Enemies.EnemyRegistry under "Bob".

	Because he is slow and tanky he is the enemy most likely to get stuck
	behind geometry while chasing a player who is wall running. When
	EnemyAI marks the target unreachable, the throw ignores its minimum
	range, so he stands and throws rather than walking into a wall.

	His melee knocks the player back hard, which is Bob's identity: you
	do not stand next to him.
]]

local EnemyBase = require(script.Parent.Parent.EnemyBase)

local Bob = setmetatable({}, { __index = EnemyBase })
Bob.__index = Bob

-- Bob keeps walking in while his throw is on cooldown, and plants
-- himself a little further out than a Noob so the swing reaches.
function Bob:DesiredRange(Target, Distance: number): number?
	local Melee = self.Attacks.Melee
	return Melee and Melee.Range * 0.7 or nil
end

return Bob
