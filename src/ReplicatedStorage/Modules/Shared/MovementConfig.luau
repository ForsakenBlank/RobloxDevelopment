-- MovementConfig
-- This used to be where the movement values were typed in. They now
-- live in MovementSettings, which groups them per ability and adds the
-- Enabled, MaxAirUses and air rules that this flat list had no room
-- for.
--
-- This file is kept because the movement modules all read from it by
-- these old key names. It builds the exact same table it always did,
-- just from MovementSettings instead of from hardcoded numbers, so
-- nothing that reads MovementConfig had to change.
--
-- Do not edit the numbers here. Edit MovementSettings. Anything typed
-- in this file gets overwritten the next time the mapping below is
-- touched, and it will disagree with what MovementGate is enforcing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)

local Abilities = MovementSettings.Abilities
local Defaults = MovementSettings.Defaults

local Run = Abilities.Run
local DoubleJump = Abilities.DoubleJump
local Dash = Abilities.Dash
local Slide = Abilities.Slide
local Crouch = Abilities.Crouch
local Sit = Abilities.Sit
local Glide = Abilities.Glide
local Leap = Abilities.Leap
local WallRun = Abilities.WallRun
local WallJump = Abilities.WallJump
local Vault = Abilities.Vault
local Climb = Abilities.Climb

return {

	-- KEYBINDS
	KEYBOARD = MovementSettings.Keybinds.Keyboard,
	GAMEPAD = MovementSettings.Keybinds.Gamepad,

	----------------------------------------------------

	-- DASHING CONFIGURATIONS
	DASHING_VELOCITYS = Dash.Velocities,

	----------------------------------------------------

	-- DOUBLE JUMPING CONFIGURATIONS
	JUMP_POWER = DoubleJump.JumpPower,
	JUMP_DURATION = DoubleJump.JumpDuration,

	----------------------------------------------------

	-- RUNNING CONFIGURATIONS
	FAST_RUN_DELAY = Run.FastRunDelay,

	BASE_RUN_SPEED = Run.BaseSpeed,
	FAST_RUN_SPEED = Run.FastSpeed,

	FOV_BONUS = Run.FovBonus,
	FOV_TWEEN_TIME = Run.FovTweenTime,
	STOP_FOV_TWEEN_TIME = Run.StopFovTweenTime,
	DEFAULT_FALLBACK_FOV = Defaults.FallbackFov,

	----------------------------------------------------

	-- SLIDING CONFIGURATIONS
	SLIDE_DURATION = Slide.Duration,
	BASE_SLIDE_SPEED = Slide.Speed,

	SLIDE_CANCEL_DURATION = Slide.CancelDuration,
	SLIDE_CANCEL_FORWARD_SPEED = Slide.CancelForwardSpeed,
	SLIDE_CANCEL_UP_SPEED = Slide.CancelUpSpeed,

	----------------------------------------------------

	-- GROUND VAULTING CONFIGURATIONS
	GROUND_VAULT_FORWARD_OFFSET = Vault.GroundForwardOffset,
	GROUND_VAULT_UP_OFFSET = Vault.GroundUpOffset,
	GROUND_VAULT_TIME = Vault.GroundTime,

	-- LEDGE VAULTING CONFIGURATIONS
	LEDGE_FORWARD_CHECK = Vault.LedgeForwardCheck,
	LEDGE_DOWN_CHECK = Vault.LedgeDownCheck,
	LEDGE_FORWARD_OFFSET = Vault.LedgeForwardOffset,
	LEDGE_UP_OFFSET = Vault.LedgeUpOffset,
	LEDGE_VAULT_TIME = Vault.LedgeTime,

	GROUND_VAULT_COOLDOWN = Vault.Cooldown,
	MAX_LEDGE_HEIGHT = Vault.MaxLedgeHeight,

	-- CLIMBING CONFIGURATIONS
	CLIMBING_SPEED = Climb.Speed,
	WALL_CHECK_DISTANCE = Climb.WallCheckDistance,

	----------------------------------------------------

	WALL_JUMP_BACKWARDS_STRENGTH = WallJump.BackwardsStrength,
	WALL_JUMP_UPWARDS_STRENGTH = WallJump.UpwardsStrength,
	WALL_JUMP_VELOCITY_DURATION = WallJump.VelocityDuration,
	WALL_JUMP_RESET_DELAY = WallJump.ResetDelay,

	----------------------------------------------------

	-- WALL RUNNING CONFIGURATIONS
	WALL_RUN_SPEED = WallRun.Speed,

	----------------------------------------------------

	-- ACTIONS/KEYBINDS COOLDOWNS
	DOUBLE_JUMP_COOLDOWN = DoubleJump.Cooldown,
	SLIDE_COOLDOWN = Slide.Cooldown,
	SIT_COOLDOWN = Sit.Cooldown,
	SPACE_COOLDOWN = Defaults.SpaceCooldown,
	DASH_COOLDOWN = Dash.Cooldown,
	CROUCH_COOLDOWN = Crouch.Cooldown,
	GLIDE_COOLDOWN = Glide.Cooldown,
	LEAP_COOLDOWN = Leap.Cooldown,

	----------------------------------------------------

	-- DEFAULT CONFIGURATIONS
	DEFAULT_WALKSPEED = Defaults.WalkSpeed,
	DEFAULT_JUMP_POWER = Defaults.JumpPower,
}
