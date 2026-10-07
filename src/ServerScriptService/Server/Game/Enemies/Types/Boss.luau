--[[
	Boss

	The single enemy in the BossRoom area at the end of the map. It has
	four attack patterns and picks between them based on where the
	players are and which patterns are off cooldown. That satisfies the
	success criteria of at least three different attack patterns.

	  Close   a heavy cleave in front of it that lunges and knocks back
	  Medium  a ground slam. A red circle fills in on the floor during
	          the wind up and everyone inside it when it lands is hit
	  Charge  it lines up (a red line on the floor shows where) and
	          charges straight through its target
	  Long    a wide fan of bolts at its target

	Below a health threshold it enrages: it roars, calls in a pack of
	Dashers, moves faster, hits harder and its cooldowns and wind ups
	get shorter, so the last part of the fight feels different to the
	first.

	It has a lot more health than a normal enemy and its health has to be
	visible to every player through the boss bar, so unlike other enemies
	it reports its health to the client every time it changes.

	It also does not fixate on one player in a multiplayer session. It
	re-picks its target on a timer, favouring whoever is closest but with
	a chance to switch to someone else.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Enemies.EnemyBase, but overrides the target selection
	  and adds the enrage on top.

	Reads:
	  The Boss entry in Game.Data.EnemyData, which holds the three
	  patterns with the damage, range and cooldown of each, and the
	  Enrage table.

	Uses:
	  Server.Game.Enemies.EnemyAI for movement and the three attacks. The
	  Medium attack has a Radius, so EnemyAI treats it as an area slam
	  with a floor telegraph, and the Long attack has a Projectile table
	  with Count and Spread, so it fires an even fan.
	  Stun does not affect the boss, StatusEffectData.Stun.AffectsBoss is
	  false, so Stun Slam does not trivialise the fight.

	Sends:
	  ReplicatedStorage.Remotes.Events.BossHealthChanged with
	  (Current, Max, DisplayName, Enraged) on spawn, on damage (throttled
	  to Settings.BarSendRate so damage over time cannot spam it), and
	  with Current 0 on death. ClientGame.Controllers.BossBarController
	  listens for it. The scaled max health is sent rather than letting
	  the client read EnemyData, because the client does not know what
	  scaling was applied.

	Signals to:
	  Server.Game.Rooms.WaveManager on death like any other enemy, which
	  clears the BossRoom area, and Server.Game.Core.RunManager then ends
	  the run in a win.

	Spawned from:
	  Game.Data.WaveData, where BossRoom is a single wave containing only
	  the boss, so it goes through the normal spawner path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local EnemyBase = require(script.Parent.Parent.EnemyBase)
local EnemyAI = require(script.Parent.Parent.EnemyAI)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BossHealthChanged = Remotes.Events:WaitForChild("BossHealthChanged")

local Boss = setmetatable({}, { __index = EnemyBase })
Boss.__index = Boss

Boss.Settings = {
	-- Seconds between health bar updates while taking damage.
	BarSendRate = 0.1,
	-- Seconds between target re-picks.
	RetargetTime = 7,
	-- Chance on each re-pick of going for someone other than the
	-- closest player, when there is more than one.
	SwitchChance = 0.4,
	-- Wind ups are multiplied by this while enraged.
	EnragedWindUpMultiplier = 0.8,
	-- The flash when it enrages.
	EnrageColour = Color3.fromRGB(255, 40, 40),
}

----------------------------------------------------------------------
-- HEALTH BAR
----------------------------------------------------------------------

function Boss:SendBar(Force: boolean?)
	local Now = os.clock()
	if not Force and Now - (self.LastBarSend or 0) < Boss.Settings.BarSendRate then
		if not self.BarQueued then
			self.BarQueued = true
			task.delay(Boss.Settings.BarSendRate, function()
				self.BarQueued = false
				self:SendBar(true)
			end)
		end
		return
	end
	self.LastBarSend = Now
	BossHealthChanged:FireAllClients(math.max(0, self.Health), self.MaxHealth, self.Data.DisplayName, self.Enraged == true)
end

function Boss:OnSpawned()
	self:SendBar(true)
end

function Boss:OnDamaged(Amount: number, Attacker, Info)
	self:SendBar(false)
	self:CheckEnrage()
end

function Boss:OnDied(Killer)
	self.Health = 0
	self:SendBar(true)
	-- Its pack goes down with it.
	for _, Minion in ipairs(self.Summons or {}) do
		if not Minion.IsDead then
			Minion:Die(nil)
		end
	end
end

----------------------------------------------------------------------
-- ENRAGE
----------------------------------------------------------------------

function Boss:CheckEnrage()
	local Enrage = self.Data.Enrage
	if self.Enraged or not Enrage or not Enrage.Enabled or self.IsDead then
		return
	end
	if self.Health / self.MaxHealth > Enrage.BelowHealthPercent then
		return
	end
	self.Enraged = true
	self.DamageMultiplier = Enrage.DamageMultiplier
	self.CooldownMultiplier = Enrage.CooldownMultiplier * (self.CooldownMultiplier or 1)
	self.WindUpMultiplier = Boss.Settings.EnragedWindUpMultiplier * (self.WindUpMultiplier or 1)
	self.AttackRecovery = Enrage.AttackRecovery
	self.BaseWalkSpeed = self.Data.WalkSpeed * Enrage.SpeedMultiplier * (self.SpeedMultiplier or 1)
	self.Humanoid.WalkSpeed = self.BaseWalkSpeed
	self.WalkSpeedBeforeStun = self.Humanoid.WalkSpeed
	CombatFX.Broadcast("Enemy_WindUp", self.Model, { Duration = 0.6, Kind = "Slam" })
	CombatFX.Broadcast("BossEnrage", self.Model, { Colour = Boss.Settings.EnrageColour })
	CombatFX.Broadcast("StunSlam_Land", nil, {
		Position = EnemyAI.FloorBelow(self, self.Root.Position),
		Radius = 20,
		Material = Enum.Material.Neon,
		Colour = Boss.Settings.EnrageColour,
		Sound = "BossRoar",
		Hostile = true,
	})
	self:SendBar(true)

	-- Help arrives, in a ring round the boss.
	local Summon = Enrage.Summon
	if Summon and (Summon.Count or 0) > 0 then
		local EnemySpawner = require(script.Parent.Parent.EnemySpawner)
		local Positions = {}
		for Index = 1, Summon.Count do
			local Angle = (Index / Summon.Count) * math.pi * 2
			local Position = self.Root.Position + Vector3.new(math.cos(Angle), 0, math.sin(Angle)) * 12
			local Minion = EnemySpawner.SpawnAt(Summon.Type or "Dasher", CFrame.new(Position), {
				AreaName = self.AreaName,
				SummonedBy = self,
				RewardMultiplier = 0.5,
			})
			if Minion then
				table.insert(Positions, Position)
				self.Summons = self.Summons or {}
				table.insert(self.Summons, Minion)
			end
		end
		CombatFX.Broadcast("Enemy_Summon", nil, { Positions = Positions, Colour = Boss.Settings.EnrageColour })
	end
end

----------------------------------------------------------------------
-- TARGETING
----------------------------------------------------------------------

-- Nearest by default, but re-picked every RetargetTime with a chance
-- of switching so one player does not tank the whole fight.
function Boss:PickTarget()
	local Now = os.clock()
	local Current = self.Target
	if Current and EnemyAI.GetPlayerRoot(Current) and Now < (self.RetargetAt or 0) then
		return Current
	end
	self.RetargetAt = Now + Boss.Settings.RetargetTime

	local Candidates = EnemyAI.GetTargetablePlayers()
	if #Candidates == 0 then
		return nil
	end
	table.sort(Candidates, function(A, B)
		local RA, RB = EnemyAI.GetPlayerRoot(A), EnemyAI.GetPlayerRoot(B)
		return (RA.Position - self.Root.Position).Magnitude < (RB.Position - self.Root.Position).Magnitude
	end)
	if #Candidates > 1 and math.random() < Boss.Settings.SwitchChance then
		return Candidates[math.random(2, #Candidates)]
	end
	return Candidates[1]
end

return Boss
