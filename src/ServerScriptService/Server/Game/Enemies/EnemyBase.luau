--[[
	EnemyBase

	The base class every enemy inherits from. It holds what all enemies
	have in common: the model, the humanoid, current and max health, the
	stats it was built with, its target, its attack cooldown timers, and
	a died signal.

	It also does the shared behaviour: taking damage, dying, dropping
	money, cleaning up its model and connections, and running the update
	loop that EnemyAI drives. Subclasses only add their own attacks and
	their own decision about what to do at a given range.

	This is where the scaling gets applied. When an enemy is created the
	base stats from EnemyData go through StatFormulas first, so the
	health an enemy actually spawns with already has the player count and
	difficulty multipliers in it. Doing it here means no subclass can
	forget to scale, and no value gets scaled twice.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.EnemyData for the base stats of whichever type it is
	  building.
	  Game.Shared.StatFormulas to scale health and damage. This is the
	  only place enemy stats get scaled.

	Subclassed by:
	  Server.Game.Enemies.Types.Noob, Bob, Necromancer and Boss, using
	  setmetatable on this class the same way the movement modules do it.

	Created by:
	  Server.Game.Enemies.EnemySpawner, which clones the model from
	  ServerStorage.Assets.Enemies and hands it to the right subclass
	  through Server.Game.Enemies.EnemyRegistry.

	Uses:
	  Server.Game.Enemies.EnemyAI for target selection and the per frame
	  or per tick update, so the movement and decision logic is not
	  copied into every subclass. Until EnemyAI exists an enemy just
	  stands where it was spawned, which is what the training dummies
	  want anyway.
	  Server.Game.Combat.DamageService, which is what calls TakeDamage on
	  it. Enemies should never have their health written directly from
	  outside.
	  Server.Game.Effects.StatusEffectService, since enemies can be
	  stunned, burned and poisoned the same as players.
	  ReplicatedStorage.Modules.Shared.Pocket for cleaning up
	  connections on death, which is the pattern the existing movement
	  modules already use.

	Signals to:
	  Server.Game.Rooms.WaveManager through its died signal, which is how
	  the alive count for a wave goes down.

	Death has to be safe to call twice. An enemy hit by two players in
	the same frame must only pay out money once, or players can farm it.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyData = require(ReplicatedStorage.Modules.Game.Data.EnemyData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local StatFormulas = require(ReplicatedStorage.Modules.Game.Shared.StatFormulas)
local Pocket = require(ReplicatedStorage.Modules.Shared.Pocket)
local Signal = require(ReplicatedStorage.Modules.Game.Shared.Signal)

local EnemyBase = {}
EnemyBase.__index = EnemyBase

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

EnemyBase.Settings = {
	-- The health bar drawn over normal enemies. The boss has its own
	-- bar on the HUD instead.
	HealthBar = {
		-- The BillboardGui in ReplicatedStorage.Assets.UI that is
		-- cloned over each enemy. Its size, colours, offset and fade
		-- distance are all set on the template in the editor.
		Template = "EnemyHealthBar",
		ShowName = true,
	},
	-- Delete the Health regen script Roblox adds to a character model.
	RemoveDefaultRegen = true,
	-- Attribute names written onto the model, so other code and the
	-- client can tell what it is without a lookup.
	TypeAttribute = "EnemyType",
	EnemyAttribute = "IsEnemy",
}

-- Fired with (Enemy, Killer) whenever any enemy dies.
-- A Signal rather than a BindableEvent, which would deep copy the
-- enemy and lose its methods, see Game.Shared.Signal.
EnemyBase.Died = Signal.new()

local ByModel: { [Model]: any } = {}
local Alive: { any } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Clones the health bar designed in the editor
-- (ReplicatedStorage.Assets.UI.EnemyHealthBar) above the enemy. Its
-- Fill sits inside a rotated Shape, so sizing it keeps the slanted end.
local function BuildHealthBar(self)
	local Config = EnemyBase.Settings.HealthBar
	local Folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI")
	local Template = Folder and Folder:FindFirstChild(Config.Template)
	if not Template then
		warn("[EnemyBase] no " .. Config.Template .. " template in ReplicatedStorage.Assets.UI")
		return
	end
	local Head = self.Model:FindFirstChild("Head") or self.Root
	local Gui = Template:Clone()
	Gui.Name = "HealthBar"
	Gui.Adornee = Head
	local Name = Gui:FindFirstChild("EnemyName", true)
	if Name then
		Name.Text = string.upper(self.Data.DisplayName)
		Name.Visible = Config.ShowName
	end
	Gui.Parent = Head
	self.HealthBarFill = Gui:FindFirstChild("Fill", true)
end

function EnemyBase:_UpdateHealthBar()
	if self.HealthBarFill then
		self.HealthBarFill.Size = UDim2.new(math.clamp(self.Health / self.MaxHealth, 0, 1), 0, 1, 0)
	end
end

----------------------------------------------------------------------
-- CONSTRUCTION
----------------------------------------------------------------------

-- Wraps an already cloned and positioned model. Options:
--   Stationary   true means EnemyAI leaves it alone, for dummies
--   RewardMultiplier   scales the money it pays, for summons
--   Class        the subclass table to use as the metatable, set by
--                EnemyRegistry. Defaults to EnemyBase itself
function EnemyBase.new(TypeName: string, Model: Model, Options: { [string]: any }?)
	Options = Options or {}
	local Data = EnemyData.Get(TypeName)
	if not Data then
		return nil
	end

	local Humanoid = Model:FindFirstChildOfClass("Humanoid")
	local Root = Model:FindFirstChild("HumanoidRootPart") or Model.PrimaryPart
	if not Humanoid or not Root then
		warn("[EnemyBase] model for " .. TypeName .. " needs a Humanoid and a HumanoidRootPart")
		return nil
	end

	local Run = RunConfig.Get()

	local self = setmetatable({}, Options.Class or EnemyBase)
	self.TypeName = TypeName
	self.Data = Data
	self.Model = Model
	self.Humanoid = Humanoid
	self.Root = Root
	self.Stationary = Options.Stationary == true
	self.RewardMultiplier = Options.RewardMultiplier or 1
	-- The area it was spawned into, and the enemy that summoned it if
	-- any, for WaveManager and the Necromancer.
	self.AreaName = Options.AreaName
	self.SummonedBy = Options.SummonedBy
	self.IsDead = false
	self.IsStunned = false
	self.Target = nil
	self.Cleaner = Pocket.new()
	self.Died = Signal.new()
	self.SpawnedAt = os.clock()

	-- Scaling happens here and only here.
	self.MaxHealth = StatFormulas.EnemyHealth(Data.Health, Run)
	self.Health = self.MaxHealth
	self.Attacks = {}
	for Name, Attack in pairs(Data.Attacks) do
		local Scaled = table.clone(Attack)
		Scaled.Damage = StatFormulas.EnemyDamage(Attack.Damage, Run)
		Scaled.CooldownEndsAt = 0
		self.Attacks[Name] = Scaled
	end

	Model:SetAttribute(EnemyBase.Settings.TypeAttribute, TypeName)
	Model:SetAttribute(EnemyBase.Settings.EnemyAttribute, true)

	Humanoid.MaxHealth = self.MaxHealth
	Humanoid.Health = self.MaxHealth
	-- The speed before any sprint. EnemyAI sprints on top of this, and
	-- the Boss raises it when it enrages.
	-- the difficulty's speed, wind up and cooldown on top of the enemy's own numbers
	local Difficulty = Run and Run.Difficulty or {}
	self.SpeedMultiplier = Difficulty.EnemySpeed or 1
	self.WindUpMultiplier = Difficulty.EnemyWindUp
	self.CooldownMultiplier = Difficulty.EnemyCooldown
	self.BaseWalkSpeed = Data.WalkSpeed * self.SpeedMultiplier
	Humanoid.WalkSpeed = self.BaseWalkSpeed
	Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	Humanoid.BreakJointsOnDeath = false

	if EnemyBase.Settings.RemoveDefaultRegen then
		local Regen = Model:FindFirstChild("Health")
		if Regen and Regen:IsA("BaseScript") then
			Regen:Destroy()
		end
	end

	-- Anything that kills the humanoid directly, a kill plane say,
	-- still goes through Die so the wave count stays right.
	self.Cleaner:add(Humanoid.Died:Connect(function()
		self:Die(nil)
	end))
	self.Cleaner:add(Model.AncestryChanged:Connect(function(_, Parent)
		if Parent == nil then
			self:Die(nil)
		end
	end))

	if EnemyData.Shared.ShowHealthBar and not Data.IsBoss then
		BuildHealthBar(self)
	end

	ByModel[Model] = self
	table.insert(Alive, self)

	-- Subclasses that need to set something up once the base is ready,
	-- the boss bar for instance.
	if type(self.OnSpawned) == "function" then
		task.spawn(self.OnSpawned, self)
	end
	return self
end

----------------------------------------------------------------------
-- LOOKUPS
----------------------------------------------------------------------

-- The enemy object for a model, or for any part inside one.
function EnemyBase.FromInstance(Instance: Instance?)
	local Current = Instance
	while Current do
		local Enemy = ByModel[Current :: any]
		if Enemy then
			return Enemy
		end
		Current = Current.Parent
	end
	return nil
end

function EnemyBase.GetAlive(): { any }
	return table.clone(Alive)
end

-- The models of every living enemy, for HitDetection's filter.
function EnemyBase.GetAliveModels(): { Model }
	local Models = {}
	for _, Enemy in ipairs(Alive) do
		table.insert(Models, Enemy.Model)
	end
	return Models
end

function EnemyBase.CountAlive(): number
	return #Alive
end

-- Removes every enemy, for the end of a run.
function EnemyBase.ClearAll()
	for _, Enemy in ipairs(table.clone(Alive)) do
		Enemy:Destroy()
	end
end

----------------------------------------------------------------------
-- HEALTH
----------------------------------------------------------------------

function EnemyBase:IsAlive(): boolean
	return not self.IsDead
end

function EnemyBase:GetPosition(): Vector3
	return self.Root.Position
end

-- Takes damage. Returns the amount actually removed and whether this
-- killed it. Attacker is the Player or enemy responsible, Info is the
-- table DamageService was given, for subclasses that react to hits.
function EnemyBase:TakeDamage(Amount: number, Attacker: any, Info: any?): (number, boolean)
	if self.IsDead or Amount <= 0 then
		return 0, false
	end

	local Before = self.Health
	self.Health = math.max(0, self.Health - Amount)
	local Dealt = Before - self.Health

	self.Humanoid.Health = self.Health
	self:_UpdateHealthBar()

	if self.Data.AggroOnHit ~= false and EnemyData.Shared.AggroOnHit and typeof(Attacker) == "Instance" and Attacker:IsA("Player") then
		self.Target = Attacker
		self.AggroUntil = os.clock() + EnemyData.Shared.AggroDuration
	end

	-- a heavy hit staggers it for a moment (EnemyAI stops it moving), never a boss
	if not self.Data.IsBoss and Dealt >= self.MaxHealth * (EnemyData.Shared.FlinchFraction or 1) then
		self.FlinchUntil = os.clock() + (EnemyData.Shared.FlinchTime or 0)
	end

	if type(self.OnDamaged) == "function" then
		self:OnDamaged(Dealt, Attacker, Info)
	end

	if self.Health <= 0 then
		self:Die(Attacker)
		return Dealt, true
	end

	return Dealt, false
end

function EnemyBase:Heal(Amount: number): number
	if self.IsDead or Amount <= 0 then
		return 0
	end
	local Before = self.Health
	self.Health = math.min(self.MaxHealth, self.Health + Amount)
	self.Humanoid.Health = self.Health
	self:_UpdateHealthBar()
	return self.Health - Before
end

-- Safe to call twice. The second call does nothing, which is what
-- stops two players being paid for one kill.
function EnemyBase:Die(Killer: any)
	if self.IsDead then
		return
	end
	self.IsDead = true
	self.Health = 0

	local Index = table.find(Alive, self)
	if Index then
		table.remove(Alive, Index)
	end

	if type(self.OnDied) == "function" then
		self:OnDied(Killer)
	end

	self.Died:Fire(Killer)
	EnemyBase.Died:Fire(self, Killer)

	-- Every client dissolves the body and plays the death sound.
	local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
	CombatFX.Broadcast("EnemyDeath", self.Model, {
		Colour = self.Data.DeathColour,
		Sound = self.Data.Sounds and self.Data.Sounds.Death,
		Delay = EnemyData.Shared.DespawnTime,
	})

	-- Let the death play out, then clean up.
	if self.Humanoid.Health > 0 then
		self.Humanoid.Health = 0
	end
	local Bar = self.Model:FindFirstChild("HealthBar", true)
	if Bar then
		Bar:Destroy()
	end
	Debris:AddItem(self.Model, EnemyData.Shared.DespawnTime)
	task.delay(EnemyData.Shared.DespawnTime, function()
		self:Destroy()
	end)
end

-- Immediate removal with no death, for clearing a run.
function EnemyBase:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self.IsDead = true

	local Index = table.find(Alive, self)
	if Index then
		table.remove(Alive, Index)
	end
	ByModel[self.Model] = nil

	self.Cleaner:destroy()
	if self.Model.Parent then
		self.Model:Destroy()
	end
end

----------------------------------------------------------------------
-- ATTACKS
----------------------------------------------------------------------

-- Whether a named attack is off cooldown.
function EnemyBase:CanUseAttack(AttackName: string): boolean
	local Attack = self.Attacks[AttackName]
	return Attack ~= nil and os.clock() >= Attack.CooldownEndsAt and not self.IsStunned and not self.IsDead
end

function EnemyBase:StartAttackCooldown(AttackName: string, Multiplier: number?)
	local Attack = self.Attacks[AttackName]
	if Attack then
		Attack.CooldownEndsAt = os.clock() + Attack.Cooldown * (Multiplier or 1)
	end
end

return EnemyBase
