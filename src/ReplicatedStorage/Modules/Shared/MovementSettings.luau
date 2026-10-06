-- MovementSettings
-- Every tuning value for every movement ability, in one place.
-- This is the only file you need to open to change how movement feels.
--
-- Every ability has these four no matter what else it has:
--   Enabled       false turns the ability off completely
--   Cooldown      seconds before it can be used again
--   MaxAirUses    how many times it can be used without touching the
--                 ground. 0 means it cannot be used in the air at all,
--                 math.huge means unlimited. Using it while stood on
--                 the ground never counts towards this.
--   AllowOnGround / AllowInAir
--                 whether it can be started at all in that situation
--
-- MovementGate is what enforces those four. The rest of the values in
-- each ability are read by that ability's own module.
--
-- Note on when changes take effect. Enabled, Cooldown, MaxAirUses,
-- AllowOnGround and AllowInAir are read live, so you can change them
-- while playtesting and they apply straight away. The tuning numbers
-- like speeds and durations are read when the module first loads, so
-- those need a restart of the playtest to take effect.

local MovementSettings = {}

----------------------------------------------------------------------
-- KEYBINDS
----------------------------------------------------------------------

MovementSettings.Keybinds = {
	Keyboard = {
		Run = Enum.KeyCode.LeftShift,
		Dash = Enum.KeyCode.Q,
		Slide = Enum.KeyCode.C,
		Crouch = Enum.KeyCode.V,
		Crawl = Enum.KeyCode.X,
		Sit = Enum.KeyCode.M,
		Leap = Enum.KeyCode.F,
		["Spin/Glide"] = Enum.KeyCode.F,
	},

	Gamepad = {
		Slide = Enum.KeyCode.ButtonX,
		Dash = Enum.KeyCode.ButtonY,
		Crouch = Enum.KeyCode.ButtonL1,
		Crawling = Enum.KeyCode.ButtonL2,
		Run = Enum.KeyCode.ButtonL3,
		Sit = Enum.KeyCode.ButtonR1,
		Jump = Enum.KeyCode.ButtonR2,
		Leap = Enum.KeyCode.DPadDown,
		Glide = Enum.KeyCode.DPadRight,
	},
}

----------------------------------------------------------------------
-- DEFAULTS
----------------------------------------------------------------------

MovementSettings.Defaults = {
	WalkSpeed = 16,
	JumpPower = 50,
	FallbackFov = 70,

	-- Space itself has a small cooldown separate from the double jump,
	-- which stops the jump input being spammed.
	SpaceCooldown = 0.5,
}

----------------------------------------------------------------------
-- ABILITIES
----------------------------------------------------------------------

MovementSettings.Abilities = {

	-- Sprint, started by double tapping a movement key.
	Run = {
		Enabled = true,
		Cooldown = 0,
		MaxAirUses = math.huge,
		AllowOnGround = true,
		AllowInAir = true,
		HotbarLabel = "LSHIFT",
		CooldownKey = "Run",

		-- true means hold the key to run and let go to stop. false
		-- makes it a toggle, so one press starts running and the next
		-- press stops it.
		HoldToRun = false,
		BaseSpeed = 36,
		FastSpeed = 52,
		FastRunDelay = 1.8,
		SpeedAfterStop = 30,

		-- With HoldToRun off, running is a toggle that stays on while
		-- you stand still. PauseWhenStill stops the run animation, the
		-- speed lines and the footstep sound while there is no movement
		-- input, and starts them again when you move. Read live.
		PauseWhenStill = true,
		-- How much movement input counts as moving. MoveDirection is
		-- 0 to 1, so this only matters for analogue sticks.
		StillThreshold = 0.05,
		-- Only count as still when stood on the floor, so letting go
		-- of the keys mid jump or on a zipline does not pause the run.
		StillOnlyOnGround = true,
		-- true drops the fast run boost while stood still, so you go
		-- back to regular sprint and the FastRunDelay has to build up
		-- again. false keeps the boost, you carry on at full speed
		-- when you move again.
		StillResetsBoost = true,

		FovBonus = 10,
		FovTweenTime = 0.5,
		StopFovTweenTime = 0.3,
	},

	-- The mid air jump. This is the one that had no limit before, so
	-- MaxAirUses is what stops the player jumping forever. Set it to 2
	-- for a triple jump, or 0 to remove the double jump entirely.
	DoubleJump = {
		Enabled = true,
		Cooldown = 0.15,
		MaxAirUses = 2,
		AllowOnGround = false,
		AllowInAir = true,
		HotbarLabel = "SPACEAIR",
		CooldownKey = "Double Jump",

		JumpPower = 135,
		JumpDuration = 0.1,
	},

	Dash = {
		Enabled = true,
		Cooldown = 0.6,
		MaxAirUses = 3,
		AllowOnGround = true,
		AllowInAir = true,
		HotbarLabel = "Q",
		CooldownKey = "Dash",

		Velocities = {
			Front = 72,
			Back = 60,
			Right = 60,
			Left = 60,
		},

		DebrisTime = 0.5,
		FaceDuration = 0.5,
		MinVelocityDuration = 0.12,
		VelocityEndLeadTime = 0.1,
		VelocityDurationScale = 1,

		SideSpeedScale = 3,
		BackSpeedScale = 1,
		ForwardSpeedScale = 2,

		FrontBurstVelocityScale = 1.55,
		SideBurstVelocityScale = 1.8,
		NonBackCarryVelocityScale = 0.72,
		NonBackBurstRatio = 0.36,
		SideBurstRatio = 0.42,

		BackInitialVelocityScale = 0.35,
		BackBoostVelocityScale = 3,
		BackBoostDuration = 0.2,
		BackBoostShakeIntensity = 0.18,
		BackBoostShakeDuration = 0.12,

		NonBackShakeIntensity = 0.08,
		NonBackShakeDuration = 0.08,

		AirKeepVerticalVelocity = true,
	},

	Slide = {
		Enabled = true,
		Cooldown = 0.8,
		MaxAirUses = 0,
		AllowOnGround = true,
		AllowInAir = false,
		HotbarLabel = "V",
		CooldownKey = "Slide",

		Duration = 1.15,
		Speed = 85,

		CancelDuration = 0.3,
		CancelForwardSpeed = 115,
		CancelUpSpeed = 52,
	},

	Crouch = {
		Enabled = false,
		Cooldown = 0.25,
		MaxAirUses = 0,
		AllowOnGround = true,
		AllowInAir = false,
		HotbarLabel = "C",
		CooldownKey = "Crouch",

		IdleFadeTime = 0.1,
		WalkFadeTime = 0.1,
		SpeedThreshold = 0.1,
	},

	Crawl = {
		Enabled = false,
		Cooldown = 0.25,
		MaxAirUses = 0,
		AllowOnGround = true,
		AllowInAir = false,
		HotbarLabel = "X",
		CooldownKey = "Crawl",

		IdleFadeTime = 0.1,
		WalkFadeTime = 0.1,
		SpeedThreshold = 0.1,
	},

	Sit = {
		Enabled = false,
		Cooldown = 1,
		MaxAirUses = 0,
		AllowOnGround = true,
		AllowInAir = false,
		HotbarLabel = "M",
		CooldownKey = "Sit",

		GetUpFallbackDuration = 0.8,
	},

	-- The glide, which is the Spin module.
	Glide = {
		Enabled = true,
		Cooldown = 2.5,
		MaxAirUses = 1,
		AllowOnGround = false,
		AllowInAir = true,
		HotbarLabel = "E",
		CooldownKey = "Spinning",

		Duration = 1.25,
		InitialForwardSpeed = 172,
		EndForwardSpeed = 135,
		UpwardBoost = 0,

		FovBoost = 15,
		FovTweenTime = 0.16,
	},

	Leap = {
		Enabled = false,
		Cooldown = 2,
		MaxAirUses = 1,
		AllowOnGround = true,
		AllowInAir = true,
		HotbarLabel = "F",
		CooldownKey = "Leaping",

		ForwardSpeed = 95,
		UpwardBoost = 28,
		VelocityDuration = 0.45,

		-- The upward part is divided by this when leaping in mid air,
		-- so an air leap gives less height than one from the ground.
		AirUpwardDivisor = 3,

		FovBoost = 5,
		FovTweenTime = 0.16,

		-- The weaker leap used when jumping off a zipline.
		ZiplineLeap = {
			ForwardSpeed = 52,
			UpwardBoost = 12,
			VelocityDuration = 0.36,
		},
	},

	-- Wall running starts on its own when you are airborne next to a
	-- wall, so it has no keybind and no hotbar slot. MaxAirUses is what
	-- stops a player chaining walls forever without landing.
	WallRun = {
		Enabled = true,
		Cooldown = 0,
		MaxAirUses = math.huge,
		AllowOnGround = false,
		AllowInAir = true,
		HotbarLabel = nil,
		CooldownKey = "WallRun",

		Speed = 75,

		-- How far to the side it looks for a wall.
		WallCheckDistance = 3,
		-- How far down it looks to decide the player is off the ground.
		GroundCheckDistance = 5.5,
		-- How far forward it looks to make sure nothing is in the way.
		FrontCheckDistance = 1.5,
		-- Seconds after leaving a wall before another one can start.
		RestartDelay = 1,
		-- Speed bleeds off by this much per second while on the wall.
		SpeedDecayPerSecond = 45,
		-- It will not start on a wall you are running almost straight
		-- into. Lower is stricter.
		MinApproachDot = -0.7,
	},

	WallJump = {
		Enabled = false,
		Cooldown = 0,
		MaxAirUses = math.huge,
		AllowOnGround = false,
		AllowInAir = true,
		HotbarLabel = nil,
		CooldownKey = "WallJump",

		ForwardPower = 70,
		SidePower = 55,
		UpPower = 35,

		-- The three powers above fall off while the jump plays.
		ForwardDecayPerSecond = 10.8,
		ForwardFloor = 50,
		SideDecayPerSecond = 81,
		SideFloor = 30,
		UpDecayPerSecond = 90,

		Duration = 0.4,
		BackwardsStrength = 15,
		UpwardsStrength = 20,
		VelocityDuration = 0.3,
		ResetDelay = 0.1,

		-- Chaining to a wall on the other side.
		ChainEnabled = true,
		ChainCheckDistance = 17,
		ChainMaxDistance = 8,
		ChainCheckDelay = 0.05,
	},

	Vault = {
		Enabled = false,
		Cooldown = 0.7,
		MaxAirUses = 0,
		AllowOnGround = true,
		AllowInAir = false,
		HotbarLabel = nil,
		CooldownKey = "Vault",

		GroundForwardOffset = 8,
		GroundUpOffset = 5.5,
		GroundTime = 0.4,

		LedgeForwardCheck = 1.5,
		LedgeDownCheck = 8,
		LedgeForwardOffset = 1.2,
		LedgeUpOffset = 1,
		LedgeTime = 0.2,
		MaxLedgeHeight = 5,
	},

	Climb = {
		Enabled = false,
		Cooldown = 0,
		MaxAirUses = math.huge,
		AllowOnGround = true,
		AllowInAir = true,
		HotbarLabel = nil,
		CooldownKey = "Climb",

		Speed = 25,
		WallCheckDistance = 1.3,
	},

	Swing = {
		Enabled = false,
		Cooldown = 0.3,
		MaxAirUses = math.huge,
		AllowOnGround = true,
		AllowInAir = true,
		HotbarLabel = nil,
		CooldownKey = "Swing",

		DetectRadius = 12,
		PullSpeed = 40,
		UpBoost = 20,
		Duration = 0.6,
		-- How long before the same bar can be grabbed again, which
		-- stops the player hanging on one bar forever.
		SameBarCooldown = 2,
		VerticalOffset = 3,

		FovBoost = 12,
		FovTweenTime = 0.18,
	},

	Zipline = {
		Enabled = true,
		Cooldown = 0.25,
		MaxAirUses = math.huge,
		AllowOnGround = true,
		AllowInAir = true,
		HotbarLabel = nil,
		CooldownKey = "Zipline",

		DetectRadius = 7.5,
		TravelSpeed = 95,
		EndDistance = 0.5,
		EarlyDetachRatio = 0.05,
		MinDetachTime = 0.2,
		JumpOffMinTime = 0.5,
		JumpOffExtraCooldown = 0.9,

		HeightOffsetFromHip = 0,
		LeftArmYOffset = 1,
		PitchInfluence = 1,
		LineSnapStrength = 12,
		MaxSnapSpeed = 45,

		AttachFovBoost = 6,
		FovTweenTime = 0.2,
		StartShakeIntensity = 0.35,
		StartShakeDuration = 0.2,
	},
}

----------------------------------------------------------------------
-- SHIFT LOCK
----------------------------------------------------------------------

-- Shift lock is Roblox's own camera feature rather than one of our
-- abilities, so it is not in the list above. It reads its key from a
-- BoundKeys value inside the player's MouseLockController, and the
-- Client script writes this key into it when the character spawns.
--
-- It used to be on Left Shift, which is now the run key, so it has
-- moved to Left Control.
MovementSettings.ShiftLock = {
	Enabled = true,
	Key = Enum.KeyCode.LeftControl,
}

----------------------------------------------------------------------
-- MAP
----------------------------------------------------------------------

-- Wall running, swinging and ziplining raycast against the map, and
-- they used to point at workspace.Map only. The rogue like level is in
-- workspace.MainGameObj, so anything not listed here is a surface the
-- player cannot wall run on. Names are checked against workspace and
-- missing ones are skipped, so it is safe to leave one in the list
-- before you have made it.
MovementSettings.MapFolders = {
	"MainGameObj",
	"Map",
}

-- Returns the map folders that actually exist, for a raycast filter.
function MovementSettings.GetMapInstances(): { Instance }
	local Found = {}
	for _, Name in ipairs(MovementSettings.MapFolders) do
		local Folder = workspace:FindFirstChild(Name)
		if Folder then
			table.insert(Found, Folder)
		end
	end
	return Found
end

-- Finds a named folder inside any of the map folders, such as the
-- "Swingable" or "Ziplines" folder. Returns nil rather than yielding
-- forever if no map has one, so a map without swing bars simply has no
-- swinging instead of the module hanging on WaitForChild.
function MovementSettings.FindInMap(FolderName: string): Instance?
	for _, MapFolder in ipairs(MovementSettings.GetMapInstances()) do
		local Found = MapFolder:FindFirstChild(FolderName)
		if Found then
			return Found
		end
	end
	return nil
end

-- Looks an ability up by name and warns rather than erroring if the
-- name is wrong, so a typo in a call site does not break movement.
function MovementSettings.Get(AbilityName: string)
	local Ability = MovementSettings.Abilities[AbilityName]
	if not Ability then
		warn("[MovementSettings] no ability called " .. tostring(AbilityName))
	end
	return Ability
end

----------------------------------------------------------------------
-- GAME MODIFIERS
----------------------------------------------------------------------

-- The rogue like changes speed and jumps mid run, through Rage and the
-- shop artifacts. The server writes these as attributes on the
-- character (from Server.Game.Core.PlayerStats) and the movement
-- modules read them through the helpers below, so a speed buff is
-- applied on top of whatever the run module wants rather than the two
-- fighting over Humanoid.WalkSpeed.
--
-- Walk speed = base * SpeedMultiplier + SpeedBonus, where base is
-- whatever the movement module asked for (16 walking, 32 running,
-- 45 fast running).
MovementSettings.GameModifiers = {
	Enabled = true,

	-- Attribute names on the character. The server sets the first
	-- three, the client keeps BaseWalkSpeed up to date itself.
	SpeedMultiplierAttribute = "SpeedMultiplier",
	SpeedBonusAttribute = "SpeedBonus",
	ExtraJumpsAttribute = "ExtraJumps",
	BaseWalkSpeedAttribute = "BaseWalkSpeed",

	-- Hard ceiling on walk speed after modifiers, so a stacked bug
	-- cannot send someone across the map.
	MaxWalkSpeed = 120,

	-- Which ability the extra jumps are added onto.
	ExtraJumpsAbility = "DoubleJump",
}

-- The speed a character should actually be given for a base speed,
-- after the game modifiers on it.
function MovementSettings.GetModifiedSpeed(Character: Model, BaseSpeed: number): number
	local Modifiers = MovementSettings.GameModifiers
	if not Modifiers.Enabled then
		return BaseSpeed
	end

	local Multiplier = Character:GetAttribute(Modifiers.SpeedMultiplierAttribute)
	local Bonus = Character:GetAttribute(Modifiers.SpeedBonusAttribute)

	if typeof(Multiplier) ~= "number" then
		Multiplier = 1
	end
	if typeof(Bonus) ~= "number" then
		Bonus = 0
	end

	return math.clamp(BaseSpeed * Multiplier + Bonus, 0, Modifiers.MaxWalkSpeed)
end

-- The one call every movement module should use instead of writing
-- Humanoid.WalkSpeed itself. Remembers the base so the speed can be
-- rebuilt when a modifier changes mid run.
function MovementSettings.SetWalkSpeed(Character: Model, Humanoid: Humanoid, BaseSpeed: number)
	Character:SetAttribute(MovementSettings.GameModifiers.BaseWalkSpeedAttribute, BaseSpeed)
	Humanoid.WalkSpeed = MovementSettings.GetModifiedSpeed(Character, BaseSpeed)
end

-- Reapplies the current base speed, for when a modifier attribute has
-- just changed. Falls back to the default walk speed if no base has
-- been recorded yet.
function MovementSettings.RefreshWalkSpeed(Character: Model, Humanoid: Humanoid)
	local Base = Character:GetAttribute(MovementSettings.GameModifiers.BaseWalkSpeedAttribute)
	if typeof(Base) ~= "number" then
		Base = MovementSettings.Defaults.WalkSpeed
	end
	Humanoid.WalkSpeed = MovementSettings.GetModifiedSpeed(Character, Base)
end

-- MaxAirUses for an ability on a character, with the run's extra
-- jumps added on for the ability named in GameModifiers.
function MovementSettings.GetMaxAirUses(Character: Model?, AbilityName: string): number
	local Ability = MovementSettings.Abilities[AbilityName]
	if not Ability then
		return 0
	end

	local Modifiers = MovementSettings.GameModifiers
	if not Modifiers.Enabled or not Character or AbilityName ~= Modifiers.ExtraJumpsAbility then
		return Ability.MaxAirUses
	end

	local Extra = Character:GetAttribute(Modifiers.ExtraJumpsAttribute)
	if typeof(Extra) ~= "number" then
		Extra = 0
	end

	return Ability.MaxAirUses + Extra
end

return MovementSettings
