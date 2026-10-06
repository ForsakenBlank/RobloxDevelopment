--[[
	EnergyService

	Owns the energy side of the game. It runs the regen loop that gives
	every living player energy back each second, it does the subtract
	when an ability is used, and it answers whether a player can afford
	an ability.

	The rule from the design is that energy regens passively over time,
	and if the player does not have enough for an ability then nothing
	happens at all, the ability does not fire and no energy is taken.
	Energy also never goes above the player's max, which changes when an
	energy artifact is bought.

	One loop for every player rather than a loop per player, so the cost
	does not grow with a full server.
]]

--[[
	What connects to this

	Reads:
	  Game.Config.GameConfig for the regen per second and the tick rate.
	  Game.Data.AbilityData for the cost of each ability.

	Writes:
	  Server.Game.Core.PlayerStats, through its methods so the value gets
	  clamped to max energy and the client update fires. It should not
	  write the field directly.

	Called by:
	  Server.Game.Combat.Abilities.AbilityBase, which asks whether the
	  player can afford an ability and then tells this to take the cost.
	  The individual abilities never touch energy themselves.
	  Server.Game.Combat.CombatService for its early affordability check,
	  so a request that cannot be afforded is dropped before it reaches
	  the ability.
	  Server.Game.Shop.ShopItems for the Energy Potion, which refills to
	  full, and for the energy artifact which raises max energy.

	Started by:
	  Server.Game.Game.GameInit through its Init.

	Client side, ClientGame.Controllers.AbilityInput greys out an ability
	the player cannot afford, but it reads the value it got from
	ReplicatedStorage.Remotes.Events.StatsUpdated. The real check is the
	one in here.

	A dead player waiting for the rest of the team should not be
	regenerating energy, so check the player is alive in the loop.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local AbilityData = require(ReplicatedStorage.Modules.Game.Data.AbilityData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local StatFormulas = require(ReplicatedStorage.Modules.Game.Shared.StatFormulas)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)

local EnergyService = {}

-- Set false to freeze regen for everyone, for example during the
-- results screen. Read live.
EnergyService.RegenEnabled = true

local Accumulator = 0
local Connection: RBXScriptConnection? = nil

----------------------------------------------------------------------
-- REGEN
----------------------------------------------------------------------

-- One tick for every living player. Called from the heartbeat once
-- per EnergyRegenTickRate.
local function Tick(TickLength: number)
	-- Nothing to regenerate until RunSetup has locked the run in.
	if not RunConfig.IsSet() then
		return
	end
	local Run = RunConfig.Get()

	local Amount = StatFormulas.EnergyRegenPerSecond(Run) * TickLength
	local HealthAmount = StatFormulas.HealthRegenPerSecond(Run) * TickLength
	local Delay = GameConfig.Player.EnergyRegenDelayAfterUse

	for _, Stats in pairs(PlayerStats.GetAll()) do
		if Stats:IsAlive() then
			if Amount > 0 and Stats:GetEnergy() < Stats:GetMaxEnergy() then
				if Delay <= 0 or Stats:TimeSinceEnergyUse() >= Delay then
					Stats:AddEnergy(Amount)
				end
			end
			-- Health trickles back too, on the same tick.
			if HealthAmount > 0 and Stats:GetHealth() < Stats:GetMaxHealth() then
				Stats:Heal(HealthAmount)
			end
		end
	end
end

function EnergyService.Init()
	if Connection then
		return
	end

	Connection = RunService.Heartbeat:Connect(function(DeltaTime)
		if not EnergyService.RegenEnabled then
			return
		end

		local Rate = math.max(GameConfig.Player.EnergyRegenTickRate, 1 / 60)
		Accumulator += DeltaTime
		if Accumulator < Rate then
			return
		end

		-- Pay out however many whole ticks have built up, so a lag
		-- spike does not lose regen, then keep the remainder.
		local Ticks = math.floor(Accumulator / Rate)
		Accumulator -= Ticks * Rate
		Tick(Rate * Ticks)
	end)
end

function EnergyService.Stop()
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end
end

----------------------------------------------------------------------
-- COSTS
----------------------------------------------------------------------

-- The energy cost of an ability by name. 0 with a warning for a name
-- that does not exist, so a bad name fails safe on the cost side and
-- gets caught by the ability lookup instead.
function EnergyService.GetAbilityCost(AbilityName: string): number
	local Ability = AbilityData.Get(AbilityName)
	if not Ability then
		return 0
	end
	return Ability.EnergyCost
end

function EnergyService.CanAfford(Player: Player, Cost: number): boolean
	local Stats = PlayerStats.Get(Player)
	if not Stats or not Stats:IsAlive() then
		return false
	end
	return Stats:CanAfford(Cost)
end

function EnergyService.CanAffordAbility(Player: Player, AbilityName: string): boolean
	return EnergyService.CanAfford(Player, EnergyService.GetAbilityCost(AbilityName))
end

-- Takes the cost if the player can afford it. Returns whether it was
-- taken. Nothing is taken on a fail, which is the design rule.
function EnergyService.TryUse(Player: Player, Cost: number): boolean
	local Stats = PlayerStats.Get(Player)
	if not Stats or not Stats:IsAlive() then
		return false
	end
	return Stats:UseEnergy(Cost)
end

function EnergyService.TryUseAbility(Player: Player, AbilityName: string): boolean
	return EnergyService.TryUse(Player, EnergyService.GetAbilityCost(AbilityName))
end

----------------------------------------------------------------------
-- SHOP
----------------------------------------------------------------------

-- Refills energy by a fraction of max. 1 is a full refill. Returns the
-- amount actually added.
function EnergyService.Refill(Player: Player, Fraction: number?): number
	local Stats = PlayerStats.Get(Player)
	if not Stats then
		return 0
	end
	return Stats:AddEnergy(Stats:GetMaxEnergy() * (Fraction or 1))
end

-- Raises max energy, for the energy artifact.
function EnergyService.AddMax(Player: Player, Delta: number, RefillBy: number?)
	local Stats = PlayerStats.Get(Player)
	if not Stats then
		return
	end
	Stats:AddMaxEnergy(Delta, RefillBy)
end

return EnergyService
