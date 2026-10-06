--!strict

-- MovementGate
-- Enforces the Enabled, Cooldown, MaxAirUses, AllowOnGround and
-- AllowInAir settings from MovementSettings. Every movement ability
-- asks this before it runs, so all four rules are applied in one place
-- instead of each ability doing its own checks.
--
-- Air uses are counted per character per ability and reset the moment
-- the character lands. Using an ability while stood on the ground does
-- not count towards the air limit, which is what makes MaxAirUses = 1
-- mean one double jump per airtime rather than one per life.
--
-- Typical use from an input handler:
--
--   if not MovementGate:TryUse(Character, "Dash") then return end
--   Dash:Dash(Character, Direction)
--
-- TryUse does the checking and the consuming together, so there is no
-- way to check and then forget to start the cooldown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)
local CooldownManager = require(ReplicatedStorage.Modules.Shared.Cooldown)

local MovementGate = {}

type AbilityState = {
	AirUses: number,
	CooldownEndsAt: number,
}

type CharacterState = {
	Abilities: { [string]: AbilityState },
	Connections: { RBXScriptConnection },
	Grounded: boolean,
}

local StateByCharacter: { [Model]: CharacterState } = {}

-- The hotbar only exists on the client, so it is required lazily and
-- the gate still works on the server or in a test without one.
local Hotbar: any = nil
local function GetHotbar(): any
	if Hotbar ~= nil then
		return Hotbar
	end

	local Ok, Result = pcall(function()
		return require(ReplicatedStorage.Modules.UI.Hotbar)
	end)

	Hotbar = if Ok then Result else false
	return Hotbar
end

local function GetHumanoid(Character: Model): Humanoid?
	return Character:FindFirstChildOfClass("Humanoid")
end

local function IsGrounded(Character: Model): boolean
	local Humanoid = GetHumanoid(Character)
	if not Humanoid then
		return false
	end

	return Humanoid.FloorMaterial ~= Enum.Material.Air
end

local function GetAbilityState(State: CharacterState, AbilityName: string): AbilityState
	local Existing = State.Abilities[AbilityName]
	if Existing then
		return Existing
	end

	local Fresh: AbilityState = {
		AirUses = 0,
		CooldownEndsAt = 0,
	}

	State.Abilities[AbilityName] = Fresh
	return Fresh
end

-- Hooks the landing detection for a character. Safe to call more than
-- once, it will not add a second set of connections.
function MovementGate:Attach(Character: Model)
	if StateByCharacter[Character] then
		return
	end

	local State: CharacterState = {
		Abilities = {},
		Connections = {},
		Grounded = IsGrounded(Character),
	}

	StateByCharacter[Character] = State

	local Humanoid = GetHumanoid(Character)
	if not Humanoid then
		return
	end

	-- FloorMaterial leaving Air is the most reliable landing signal.
	-- The Landed state on its own misses cases like sliding onto a
	-- ledge or being pushed down onto the floor without a jump.
	local FloorConnection = Humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		local NowGrounded = Humanoid.FloorMaterial ~= Enum.Material.Air
		if NowGrounded and not State.Grounded then
			MovementGate:ResetAirUses(Character)
		end
		State.Grounded = NowGrounded
	end)

	table.insert(State.Connections, FloorConnection)

	local DiedConnection = Humanoid.Died:Connect(function()
		MovementGate:Detach(Character)
	end)

	table.insert(State.Connections, DiedConnection)

	local AncestryConnection = Character.AncestryChanged:Connect(function()
		if not Character:IsDescendantOf(game) then
			MovementGate:Detach(Character)
		end
	end)

	table.insert(State.Connections, AncestryConnection)
end

function MovementGate:Detach(Character: Model)
	local State = StateByCharacter[Character]
	if not State then
		return
	end

	for _, Connection in ipairs(State.Connections) do
		Connection:Disconnect()
	end

	StateByCharacter[Character] = nil
end

-- Clears the air use count for every ability. Called on landing, and
-- worth calling manually after anything that should count as touching
-- down, such as leaving a zipline onto solid ground.
function MovementGate:ResetAirUses(Character: Model)
	local State = StateByCharacter[Character]
	if not State then
		return
	end

	for _, Ability in pairs(State.Abilities) do
		Ability.AirUses = 0
	end
end

-- Clears the air use count for one ability only.
function MovementGate:ResetAbility(Character: Model, AbilityName: string)
	local State = StateByCharacter[Character]
	if not State then
		return
	end

	local Ability = State.Abilities[AbilityName]
	if Ability then
		Ability.AirUses = 0
	end
end

-- Returns whether the ability can be used right now, and if not, a
-- short reason. The reason is there so it can be printed while tuning
-- rather than the ability just silently doing nothing.
function MovementGate:CanUse(Character: Model, AbilityName: string): (boolean, string?)
	local Settings = MovementSettings.Abilities[AbilityName]
	if not Settings then
		warn("[MovementGate] no ability called " .. tostring(AbilityName))
		return false, "unknown ability"
	end

	if not Settings.Enabled then
		return false, "disabled"
	end

	if not StateByCharacter[Character] then
		self:Attach(Character)
	end

	local State = StateByCharacter[Character]
	if not State then
		return false, "no character state"
	end

	local Ability = GetAbilityState(State, AbilityName)

	if os.clock() < Ability.CooldownEndsAt then
		return false, "on cooldown"
	end

	local Grounded = IsGrounded(Character)

	if Grounded and not Settings.AllowOnGround then
		return false, "not allowed on the ground"
	end

	if not Grounded then
		if not Settings.AllowInAir then
			return false, "not allowed in the air"
		end

		if Ability.AirUses >= MovementSettings.GetMaxAirUses(Character, AbilityName) then
			return false, "out of air uses"
		end
	end

	return true, nil
end

-- Starts the cooldown, counts the air use and runs the hotbar sweep.
-- Only call this after CanUse has passed, or use TryUse instead.
function MovementGate:Consume(Character: Model, AbilityName: string)
	local Settings = MovementSettings.Abilities[AbilityName]
	if not Settings then
		return
	end

	local State = StateByCharacter[Character]
	if not State then
		return
	end

	local Ability = GetAbilityState(State, AbilityName)

	if Settings.Cooldown > 0 then
		Ability.CooldownEndsAt = os.clock() + Settings.Cooldown

		-- Written through to the shared cooldown manager as well, so
		-- any existing code still reading CooldownManager.Check by its
		-- old key carries on working.
		if Settings.CooldownKey then
			CooldownManager.Set(Settings.CooldownKey, Settings.Cooldown)
		end
	end

	if not IsGrounded(Character) then
		Ability.AirUses += 1
	end

	if Settings.HotbarLabel and Settings.Cooldown > 0 then
		local HotbarModule = GetHotbar()
		if HotbarModule then
			HotbarModule:GradientTween(Settings.HotbarLabel, Settings.Cooldown)
		end
	end
end

-- The one to call from an input handler. Checks and consumes together.
function MovementGate:TryUse(Character: Model, AbilityName: string): boolean
	local Allowed = self:CanUse(Character, AbilityName)
	if not Allowed then
		return false
	end

	self:Consume(Character, AbilityName)
	return true
end

-- Whether an ability is switched on. For the places that only need the
-- on and off switch, such as wall running deciding whether to bind its
-- update loop at all.
function MovementGate:IsEnabled(AbilityName: string): boolean
	local Settings = MovementSettings.Abilities[AbilityName]
	return Settings ~= nil and Settings.Enabled == true
end

-- How many air uses are left, for showing on a HUD if you want it.
function MovementGate:GetAirUsesLeft(Character: Model, AbilityName: string): number
	local Settings = MovementSettings.Abilities[AbilityName]
	if not Settings then
		return 0
	end

	local MaxAirUses = MovementSettings.GetMaxAirUses(Character, AbilityName)

	local State = StateByCharacter[Character]
	if not State then
		return MaxAirUses
	end

	local Ability = State.Abilities[AbilityName]
	if not Ability then
		return MaxAirUses
	end

	return math.max(0, MaxAirUses - Ability.AirUses)
end

return MovementGate
