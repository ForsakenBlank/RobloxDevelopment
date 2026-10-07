--[[
	Bomber

	Runs straight at the nearest player and blows itself up. When it gets
	close it lights its fuse: it flashes and beeps for the wind up while
	still chasing, then explodes, hurting every player in the blast. That
	fuse is the window to get away, or to kill it.

	Killing it first is the better answer. A Bomber killed by a player
	still goes off a moment later, but its blast then hurts the enemies
	around it instead, for extra damage. Bombers caught in each other's
	blasts chain, so a crowd with Bombers in it is a good target for a
	rocket.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Enemies.EnemyBase, overriding Attack and OnDied.

	Reads:
	  The Bomber entry in Game.Data.EnemyData: the Detonate attack (its
	  WindUp is the fuse, Explode the blast) and DeathExplosion.

	Uses:
	  Server.Game.Combat.ProjectileService.Explode for both blasts, so
	  they use the same falloff and effect as a rocket.
	  Server.Game.Enemies.EnemyAI for chasing during the fuse.

	Tells the clients:
	  Game.Shared.CombatFX Bomber_Fuse for the flashing and beeping.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local EnemyBase = require(script.Parent.Parent.EnemyBase)
local EnemyAI = require(script.Parent.Parent.EnemyAI)

local Bomber = setmetatable({}, { __index = EnemyBase })
Bomber.__index = Bomber

Bomber.Settings = {
	-- Seconds between the chase updates during the fuse.
	FuseChaseRate = 0.1,
	-- Its walk speed is multiplied by this while the fuse burns, so the
	-- player can actually get out of the blast.
	FuseSpeedMultiplier = 0.75,
}

-- The attack with an Explode table, whatever it is named.
function Bomber:_ExplodeAttack()
	for Name, Attack in pairs(self.Attacks) do
		if Attack.Explode then
			return Name, Attack
		end
	end
	return nil, nil
end

function Bomber:Attack(AttackName: string, Target)
	local Attack = self.Attacks[AttackName]
	if not Attack or not Attack.Explode then
		EnemyAI.PerformAttack(self, AttackName, Target)
		return
	end
	if self.Fused then
		return
	end
	self.Fused = true
	self.Busy = true
	self:StartAttackCooldown(AttackName)
	local Fuse = Attack.WindUp or 0.7
	CombatFX.Broadcast("Bomber_Fuse", self.Model, { Duration = Fuse, Radius = Attack.Explode.Radius })

	self.BaseWalkSpeed = self.Data.WalkSpeed * Bomber.Settings.FuseSpeedMultiplier
	self.Humanoid.WalkSpeed = self.BaseWalkSpeed
	-- it runs at the player, so it faces where it runs
	EnemyAI.FreeTurn(self)

	task.spawn(function()
		local Ends = os.clock() + Fuse
		while os.clock() < Ends and not self.IsDead do
			-- It keeps coming during the fuse, a stun does not stop a
			-- lit bomb.
			local Root = Target and EnemyAI.GetPlayerRoot(Target)
			if Root and self.Humanoid.Parent then
				self.Humanoid:MoveTo(Root.Position)
			end
			task.wait(Bomber.Settings.FuseChaseRate)
		end
		if not self.IsDead then
			self:Detonate(nil)
		end
	end)
end

-- Blows up. With a Killer (the player who shot it) the blast hurts
-- enemies and is credited to them, otherwise it hurts players.
function Bomber:Detonate(Killer: Player?)
	if self.Detonated then
		return
	end
	self.Detonated = true
	local _, Attack = self:_ExplodeAttack()
	if not Attack or not self.Root then
		return
	end
	local ProjectileService = require(script.Parent.Parent.Parent.Combat.ProjectileService)
	local Position = self.Root.Position
	local Spec = {
		Explosion = Attack.Explode,
		Damage = EnemyAI.DamageOf(self, Attack),
		Side = "Players",
		Owner = self,
		Knockback = Attack.Knockback,
		Source = "Bomber",
	}
	if Killer then
		local Death = self.Data.DeathExplosion or {}
		Spec.Side = "Enemies"
		Spec.Owner = Killer
		Spec.Damage = Attack.Damage * (Death.DamageMultiplier or 1)
		Spec.Exclude = { self.Model }
		Spec.Source = "Bomber chain"
		Spec.HitSound = "BulletHit"
	end
	ProjectileService.Explode(Spec, Position, self.Model)
	if not self.IsDead then
		self:Die(nil)
	end
end

function Bomber:OnDied(Killer)
	if self.Detonated then
		return
	end
	-- Killed by a player: its bomb goes off on the enemies instead.
	if typeof(Killer) == "Instance" and Killer:IsA("Player") then
		local Delay = (self.Data.DeathExplosion and self.Data.DeathExplosion.Delay) or 0.15
		task.delay(Delay, function()
			self:Detonate(Killer)
		end)
	else
		self.Detonated = true
	end
end

return Bomber
