--[[
	StunSlam

	The ability that slams the player downwards and, on landing, damages
	and stuns every enemy in a large area around them. This is StunSlam
	from the function plan.

	It has two halves. First the player hops up and is driven down to
	the ground, then when they land it does the area hit. So it needs to
	detect the landing rather than just waiting a fixed time, since the
	player could activate it from any height.

	It is the crowd control answer in the game, so it is the one that
	turns a room full of Noobs around, and its energy cost should reflect
	that.
]]

--[[
	What connects to this

	Inherits from:
	  Server.Game.Combat.Abilities.AbilityBase, which has already taken
	  the energy and started the cooldown before this runs.

	Reads:
	  The StunSlam entry in Game.Data.AbilityData for the damage, radius,
	  stun duration and how hard it drives the player down.

	Uses:
	  Server.Game.Combat.HitDetection with a sphere at the landing point
	  to find the enemies caught in it.
	  Server.Game.Combat.DamageService for the damage on each one.
	  Server.Game.Effects.StatusEffectService to apply the Stun effect,
	  which then has to be respected by Server.Game.Enemies.EnemyAI,
	  which skips its update while stunned.
	  Game.Shared.CombatFX to broadcast the jump pose and the landing,
	  which draws the floor breaking up around the player using the
	  material and colour of whatever they landed on. The floor itself
	  is never changed.

	Movement:
	  The character is moved on the client that owns it, by
	  ClientGame.Controllers.AbilityInput, using the numbers this
	  returns as client data. That keeps it instant and lets it use the
	  same HelperFunctions the dash does. The server tells the anti
	  cheat to expect it and waits for the landing itself, so the hit is
	  still decided here.

	Landing detection watches Humanoid.FloorMaterial, which replicates,
	going Air then not Air, with a timeout in case the player somehow
	never lands so the ability cannot be left hanging.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StatFormulas = require(ReplicatedStorage.Modules.Game.Shared.StatFormulas)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local AbilityBase = require(script.Parent.AbilityBase)
local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local PlayerStats = require(script.Parent.Parent.Parent.Core.PlayerStats)
local HitDetection = require(script.Parent.Parent.HitDetection)
local DamageService = require(script.Parent.Parent.DamageService)
local StatusEffectService = require(script.Parent.Parent.Parent.Effects.StatusEffectService)

local StunSlam = setmetatable({}, { __index = AbilityBase })
StunSlam.__index = StunSlam

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

StunSlam.Settings = {
	-- Seconds to wait for the player to leave the ground after the
	-- hop before assuming they never did and resolving where they are.
	LeaveGroundTimeout = 0.6,
	-- Seconds to wait for the landing before giving up.
	LandTimeout = 4,
	-- How often the landing check runs.
	PollRate = 0.03,
	-- How far below the root to look for the floor that was landed on.
	FloorRayDepth = 8,
}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Finds the floor under the root, for the debris to copy.
local function FindFloor(Root: BasePart, Character: Model): (Vector3, Enum.Material, Color3)
	local Result = workspace:Raycast(Root.Position, Vector3.new(0, -StunSlam.Settings.FloorRayDepth, 0), HitDetection.MapRaycastParams({ Character }))
	if Result then
		return Result.Position, Result.Material, Result.Instance.Color
	end
	-- Nothing from the map underneath, so use the root's own height
	-- and a neutral look.
	return Root.Position - Vector3.new(0, 3, 0), Enum.Material.Concrete, Color3.fromRGB(120, 120, 120)
end

-- The damage multiplier for a fall of this many studs, from the
-- HeightBonus settings.
function StunSlam:HeightMultiplier(FallHeight: number): number
	local Bonus = self.Data.HeightBonus
	if not Bonus or not Bonus.Enabled then
		return 1
	end
	local Extra = math.max(0, FallHeight - Bonus.FreeHeight)
	return 1 + math.min(Extra * Bonus.DamagePerStud, Bonus.MaxBonus)
end

-- PeakY is the highest the root got during the slam, so the fall can
-- be measured. nil means no bonus.
function StunSlam:Resolve(Context, PeakY: number?)
	self.Active = false
	local Root = Context.Root
	if not Root or not Root.Parent then
		return
	end
	local Data = self.Data
	local Position, Material, Colour = FindFloor(Root, Context.Character)

	local FallHeight = PeakY and math.max(0, PeakY - Root.Position.Y) or 0
	local Multiplier = self:HeightMultiplier(FallHeight)

	local Hits = HitDetection.Sphere(Position, Data.Radius, {
		Side = "Enemies",
		Origin = Position,
	})

	for _, Hit in ipairs(Hits) do
		local Damage = StatFormulas.FalloffDamage(Data.Damage * Multiplier, Hit.Distance, Data.Radius, Data.Falloff)
		DamageService.ApplyDamage(Hit.Model, Damage, Context.Player, {
			Source = self.Name,
			Knockback = Data.Knockback,
			From = Position,
		})
		StatusEffectService.Apply(Hit.Model, "Stun", Data.StunDuration, nil, Context.Player)
	end

	CombatFX.Broadcast("StunSlam_Land", Context.Character, {
		Position = Position,
		Radius = Data.Radius,
		Material = Material,
		Colour = Colour,
		-- The effect can scale with the fall too.
		Multiplier = Multiplier,
	})
end

----------------------------------------------------------------------
-- USE
----------------------------------------------------------------------

function StunSlam:OnUse(Context)
	local Data = self.Data
	local Settings = StunSlam.Settings
	self.Active = true

	-- The anti cheat would see the drop as a teleport otherwise.
	AntiCheat.GrantException(Context.Player, Settings.LandTimeout + 1)

	-- I-frames for the whole time in the air, then a moment after
	-- landing (GameConfig.IFrames.Abilities.StunSlam).
	local IFrames = GameConfig.IFrames
	local Rule = IFrames and IFrames.Enabled and IFrames.Abilities.StunSlam
	local Stats = PlayerStats.Get(Context.Player)
	if type(Rule) == "table" and Rule.While and Stats then
		Stats:SetInvulnerable(Settings.LeaveGroundTimeout + Settings.LandTimeout + 1)
	end
	local function Landed()
		if type(Rule) == "table" and Stats then
			Stats:SetInvulnerableExactly(Rule.After or 0)
		end
	end

	-- Everyone else sees the jump pose. The user's client plays it
	-- itself the moment the key is pressed.
	CombatFX.Broadcast("StunSlam_Jump", Context.Character, nil, Context.Player)

	-- Wait for the landing on a separate thread so the use call can
	-- return the client data straight away.
	task.spawn(function()
		local Humanoid = Context.Humanoid
		local Root = Context.Root
		local Deadline = os.clock() + Settings.LeaveGroundTimeout
		local WasGrounded = Humanoid.FloorMaterial ~= Enum.Material.Air
		local PeakY = Root.Position.Y

		-- Leaving the ground, if the hop is on.
		if WasGrounded and Data.GroundHopHeight > 0 then
			while os.clock() < Deadline and Humanoid.FloorMaterial ~= Enum.Material.Air do
				if self.Destroyed or Humanoid.Health <= 0 then
					self.Active = false
					Landed()
					return
				end
				task.wait(Settings.PollRate)
			end
		end

		-- Landing. The highest point reached is what the fall is
		-- measured from.
		Deadline = os.clock() + Settings.LandTimeout
		while os.clock() < Deadline and Humanoid.FloorMaterial == Enum.Material.Air do
			if self.Destroyed or Humanoid.Health <= 0 then
				self.Active = false
				Landed()
				return
			end
			PeakY = math.max(PeakY, Root.Position.Y)
			task.wait(Settings.PollRate)
		end

		Landed()
		if not self.Destroyed and Humanoid.Health > 0 then
			self:Resolve(Context, PeakY)
		else
			self.Active = false
		end
	end)

	-- What the client needs to move the character.
	return {
		GroundHopHeight = Data.GroundHopHeight,
		SlamSpeed = Data.SlamSpeed,
		LandingRecovery = Data.LandingRecovery,
		MaxAirTime = Settings.LandTimeout,
	}
end

return StunSlam
