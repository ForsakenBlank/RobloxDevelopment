--[[
	Necromancer

	The support enemy. It has a strong melee attack that stuns the player
	for a short time, a slow magic bolt so it is still dangerous from
	range, and it can summon more Noobs, which is what makes a room get
	chaotic when one is left alive.

	The summon has a cooldown and a cap on how many it can have out at
	once, otherwise a room can never be cleared and the enemy count just
	grows. It also stops summoning if the whole server is at the enemy
	limit in EnemyAI.Settings.MaxEnemiesAlive.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Enemies.EnemyBase.

	Reads:
	  Its entry in Game.Data.EnemyData for the melee damage, the stun
	  duration, the bolt, the summon count, the summon cooldown and the
	  cap on live summons. The summoned type (Noob) is read from the
	  Summon attack's SummonType.

	Uses:
	  Server.Game.Effects.StatusEffectService, through the melee's
	  StatusEffect, to stun the player it hits.
	  Server.Game.Enemies.EnemySpawner to create the summons, so they go
	  through the same path as normal spawns and end up in
	  workspace.Runtime.Enemies like everything else.
	  Server.Game.Enemies.EnemyAI for the decisions and the generic melee
	  and bolt.

	Registered in:
	  Server.Game.Enemies.EnemyRegistry under "Necromancer".

	Summons and the wave count, the decision:
	  Summons do NOT count towards Server.Game.Rooms.WaveManager's alive
	  count. Instead, when a Necromancer dies every summon it still has
	  dies with it. So a room cannot be cleared with summons walking
	  around (the Necromancer is a wave enemy, and while it lives the
	  wave is not clear), and a room can never be made unclearable by
	  summons (killing the Necromancer ends them). It also gives players
	  a clear priority target.

	Stunning the player goes through the Stunned attribute that
	StatusEffectService sets. The movement framework already respects
	it for input, and combat input on the client refuses attacks while
	it is set.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local EnemyBase = require(script.Parent.Parent.EnemyBase)
local EnemyAI = require(script.Parent.Parent.EnemyAI)

local Necromancer = setmetatable({}, { __index = EnemyBase })
Necromancer.__index = Necromancer

Necromancer.Settings = {
	-- Studs from the Necromancer the summons appear at.
	SummonRadius = 6,
	-- true kills every summon when the Necromancer dies.
	SummonsDieWithSummoner = true,
}

----------------------------------------------------------------------
-- DECISIONS
----------------------------------------------------------------------

-- It hangs back at its preferred distance rather than walking up.
function Necromancer:DesiredRange(Target, Distance: number): number?
	return self.Data.PreferredDistance or nil
end

-- Living summons this Necromancer has out.
function Necromancer:CountSummons(): number
	local Count = 0
	for _, Summon in ipairs(self.Summons or {}) do
		if not Summon.IsDead then
			Count += 1
		end
	end
	return Count
end

-- The summon is refused at its own cap or the server wide cap.
function Necromancer:CanUseAttackNow(AttackName: string, Distance: number): boolean
	if AttackName ~= "Summon" then
		return true
	end
	local Summon = self.Attacks.Summon
	if self:CountSummons() >= (Summon.MaxAlive or 4) then
		return false
	end
	return EnemyBase.CountAlive() < EnemyAI.Settings.MaxEnemiesAlive
end

----------------------------------------------------------------------
-- ATTACKS
----------------------------------------------------------------------

function Necromancer:Attack(AttackName: string, Target)
	if AttackName ~= "Summon" then
		EnemyAI.PerformAttack(self, AttackName, Target)
		return
	end

	local Summon = self.Attacks.Summon
	self.Busy = true
	EnemyAI.Stop(self)
	self:StartAttackCooldown("Summon", self.CooldownMultiplier)
	CombatFX.Broadcast("Enemy_WindUp", self.Model, { Duration = Summon.WindUp, Kind = "Summon" })

	task.delay(Summon.WindUp, function()
		if self.IsDead or self.IsStunned then
			self.Busy = false
			return
		end
		self:SpawnSummons(Summon)
		CombatFX.Broadcast("Enemy_Swing", self.Model, { Kind = "Summon" })
		task.delay(EnemyAI.Settings.AttackRecovery, function()
			self.Busy = false
		end)
	end)
end

function Necromancer:SpawnSummons(Summon)
	local EnemySpawner = require(script.Parent.Parent.EnemySpawner)
	self.Summons = self.Summons or {}

	local Room = math.min(Summon.Count or 1, (Summon.MaxAlive or 4) - self:CountSummons())
	local Positions = {}
	for Index = 1, Room do
		local Angle = (Index / Room) * math.pi * 2 + math.random() * 0.5
		local Offset = Vector3.new(math.cos(Angle), 0, math.sin(Angle)) * Necromancer.Settings.SummonRadius
		local Position = self.Root.Position + Offset
		local Enemy = EnemySpawner.SpawnAt(Summon.SummonType or "Noob", CFrame.new(Position), {
			AreaName = self.AreaName,
			SummonedBy = self,
			RewardMultiplier = Summon.SummonRewardMultiplier or 0.5,
		})
		if Enemy then
			table.insert(self.Summons, Enemy)
			table.insert(Positions, Position)
		end
	end
	CombatFX.Broadcast("Enemy_Summon", nil, { Positions = Positions })
end

----------------------------------------------------------------------
-- DEATH
----------------------------------------------------------------------

function Necromancer:OnDied(Killer)
	if not Necromancer.Settings.SummonsDieWithSummoner then
		return
	end
	for _, Summon in ipairs(self.Summons or {}) do
		if not Summon.IsDead then
			Summon:Die(nil)
		end
	end
end

return Necromancer
