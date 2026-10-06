--[[
	AbilityBase

	The base class for the abilities. It does the part that is the same
	for all of them, which is the check that runs before any ability
	fires: is it off cooldown, does the player have enough energy, and is
	the player alive and in a state where they can use it.

	If any of those fail it stops there and nothing happens, which is
	what the design says. If they pass it takes the energy, starts the
	cooldown, and then calls the subclass for the actual effect.

	Taking the energy here rather than in each ability means it is
	impossible for an ability to fire without paying for it, and
	impossible for one to take the energy twice.

	A player carries 2 abilities and has 1 out at a time, so there are
	two of these objects per player. The one that is put away keeps its
	cooldown running, so swapping cannot be used to dodge a cooldown.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.AbilityData for the energy cost and cooldown of the
	  ability being used.

	Subclassed by:
	  Server.Game.Combat.Abilities.StunSlam, Teleport, Rage and HealBurst.
	  Each defines OnUse(Context) and may return a table of data for
	  the client, such as how to move the character. A subclass that is
	  still a stub falls back to this base, which warns and does
	  nothing.

	Created by:
	  Server.Game.Core.Loadout, one for each of the player's two ability
	  slots, built from the abilities they picked in the lobby.

	Uses:
	  Server.Game.Combat.EnergyService for the affordability check and
	  the subtract. The subclasses never touch energy themselves.
	  Server.Game.Core.PlayerStats to check the player is alive.
	  Server.Game.Effects.StatusEffectService to refuse while stunned.

	Called by:
	  Server.Game.Combat.CombatService, which is the only thing that
	  triggers an ability, and which has already checked with
	  Server.Game.Core.Loadout that this is the ability the player
	  currently has equipped.

	Sends:
	  CombatService fires ReplicatedStorage.Remotes.Events.AbilityUsed
	  back down with the result so
	  ClientGame.Controllers.AbilityInput can start or cancel the hotbar
	  sweep and, for StunSlam, move the character.

	Cooldowns are os.clock timestamps on the object, the same as
	WeaponBase, so the HUD can be told the remaining time after a swap.

	Order matters. Check first, then take the energy, then run the
	effect. If the effect runs first and then errors, the player has
	spent nothing and can spam it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local AbilityData = require(ReplicatedStorage.Modules.Game.Data.AbilityData)
local PlayerStats = require(script.Parent.Parent.Parent.Core.PlayerStats)
local EnergyService = require(script.Parent.Parent.EnergyService)

local AbilityBase = {}
AbilityBase.__index = AbilityBase

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

AbilityBase.Settings = {
	MinCooldown = 0.1,
	-- Attribute on the character that blocks abilities while set, the
	-- one StatusEffectService sets for Stun.
	StunnedAttribute = "Stunned",
}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function FindClass(AbilityName: string)
	local Module = script.Parent:FindFirstChild(AbilityName)
	if not Module or Module == script then
		return nil
	end
	local Ok, Result = pcall(require, Module)
	if Ok and type(Result) == "table" and Result.__index then
		return Result
	end
	return nil
end

----------------------------------------------------------------------
-- CONSTRUCTION
----------------------------------------------------------------------

function AbilityBase.new(Player: Player, AbilityName: string)
	local Data = AbilityData.Get(AbilityName)
	if not Data then
		AbilityName = GameConfig.Loadout.FallbackAbility
		Data = AbilityData.Get(AbilityName)
	end

	local Class = FindClass(AbilityName)
	if not Class then
		warn("[AbilityBase] " .. AbilityName .. " has no ability class yet, it will not fire")
		Class = AbilityBase
	end

	local self = setmetatable({}, Class)
	self.Player = Player
	self.Name = AbilityName
	self.Data = Data
	self.CooldownEndsAt = 0
	self.CooldownLength = 0
	self.Active = false
	self.CastThread = nil
	self.Destroyed = false
	return self
end

function AbilityBase:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:Cancel()
end

----------------------------------------------------------------------
-- CHECKS
----------------------------------------------------------------------

function AbilityBase:GetCooldownRemaining(): number
	return math.max(0, self.CooldownEndsAt - os.clock())
end

function AbilityBase:CanUse(): (boolean, string?)
	if self.Destroyed then
		return false, "destroyed"
	end
	if self.Active then
		return false, "already active"
	end
	if not GameConfig.Debug.FreeAbilities and self:GetCooldownRemaining() > 0 then
		return false, "on cooldown"
	end

	local Stats = PlayerStats.Get(self.Player)
	if not Stats or not Stats:IsAlive() then
		return false, "dead"
	end
	if not EnergyService.CanAfford(self.Player, self.Data.EnergyCost) then
		return false, "not enough energy"
	end

	local Character = self.Player.Character
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
	if not Character or not Humanoid or Humanoid.Health <= 0 then
		return false, "no character"
	end
	if Character:GetAttribute(AbilityBase.Settings.StunnedAttribute) then
		return false, "stunned"
	end
	if not AbilityData.Shared.AllowInAir and Humanoid.FloorMaterial == Enum.Material.Air then
		return false, "in the air"
	end

	if type(self.CanUseExtra) == "function" then
		local Ok, Reason = self:CanUseExtra(Character)
		if not Ok then
			return false, Reason
		end
	end

	return true, nil
end

function AbilityBase:StartCooldown(): number
	-- Rage and anything else that speeds cooldowns up.
	local Stats = PlayerStats.Get(self.Player)
	local Multiplier = Stats and Stats:GetCooldownMultiplier() or 1
	local Length = math.max(self.Data.Cooldown * Multiplier, AbilityBase.Settings.MinCooldown)
	if GameConfig.Debug.FreeAbilities then
		Length = AbilityBase.Settings.MinCooldown
	end
	self.CooldownLength = Length
	self.CooldownEndsAt = os.clock() + Length
	return Length
end

----------------------------------------------------------------------
-- USE
----------------------------------------------------------------------

-- Cancels a cast that has not resolved yet.
function AbilityBase:Cancel()
	if self.CastThread then
		task.cancel(self.CastThread)
		self.CastThread = nil
	end
	self.Active = false
end

-- The shared path. Returns (true, Cooldown, ClientData) on success
-- or (false, Reason). ClientData is whatever OnUse returned, sent to
-- the client so it can move the character or draw something.
function AbilityBase:Use(AimPosition: Vector3?): (boolean, any, any)
	local Allowed, Reason = self:CanUse()
	if not Allowed then
		return false, Reason, nil
	end

	-- Check, then pay, then fire. Never the other way round.
	if not EnergyService.TryUse(self.Player, self.Data.EnergyCost) then
		return false, "not enough energy", nil
	end
	local Length = self:StartCooldown()

	-- Invincibility frames for this ability, see GameConfig.IFrames.
	-- Stun Slam handles its own, since it lasts until it lands.
	local IFrames = GameConfig.IFrames
	local Seconds = IFrames and IFrames.Enabled and IFrames.Abilities[self.Name]
	if type(Seconds) == "number" and Seconds > 0 then
		local Stats = PlayerStats.Get(self.Player)
		if Stats then
			Stats:SetInvulnerable(Seconds)
		end
	end

	local Character = self.Player.Character
	local Root = Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local Aim = AimPosition or (Root.Position + Root.CFrame.LookVector * 30)
	local Context = {
		Player = self.Player,
		Character = Character,
		Root = Root,
		Humanoid = Humanoid,
		Origin = Root.Position,
		Facing = Root.CFrame,
		AimPosition = Aim,
		AimDirection = (Aim - Root.Position).Magnitude > 0.01 and (Aim - Root.Position).Unit or Root.CFrame.LookVector,
	}

	local ClientData = nil
	local function Fire()
		self.CastThread = nil
		if self.Destroyed then
			return
		end
		if type(self.OnUse) ~= "function" then
			warn("[AbilityBase] " .. self.Name .. " has no OnUse")
			return
		end
		local Ok, Result = pcall(self.OnUse, self, Context)
		if not Ok then
			warn("[AbilityBase] " .. self.Name .. " errored: " .. tostring(Result))
			self.Active = false
			return
		end
		ClientData = Result
	end

	if self.Data.CastTime and self.Data.CastTime > 0 then
		-- The client is told straight away so it can start its
		-- animation, the effect lands after the cast.
		self.CastThread = task.delay(self.Data.CastTime, Fire)
	else
		Fire()
	end

	if GameConfig.Debug.LogCombat then
		print(string.format("[AbilityBase] %s used %s, cooldown %.1f", self.Player.Name, self.Name, Length))
	end

	return true, Length, ClientData
end

return AbilityBase
