-- AntiCheat Config
-- Every number the anti cheat uses lives here so you can tune it
-- without touching any logic.
--
-- If you are getting false flags, raise BankSeconds first and
-- SpeedStreak second. Those two absorb lag and stutter without
-- handing out free speed, which is the trap the other settings
-- fall into. Read the note on PositionSlack before touching it.

local Config = {}

-- How many times per second every player is checked. 5 is a good
-- balance. Going higher costs more and catches slightly faster,
-- going lower is cheaper but lets short bursts through.
Config.SampleRate = 5

-- Anything inside these Workspace folders is invisible to the
-- position and noclip checks. Put decorative or non solid things
-- here so they can never be mistaken for a wall.
Config.IgnoredWorkspaceFolders = { "Effects", "Runtime", "ClientFX" }

Config.Movement = {
	Enabled = true,

	-- What a normal player is allowed to do. If your game gives
	-- speed or jump boosts, do not raise these, call
	-- AntiCheat.SetSpeedLimit instead so the limit follows the
	-- boost and drops back when it ends.
	DefaultWalkSpeed = 16,
	DefaultJumpPower = 50,
	DefaultJumpHeight = 7.2,

	-- Multiplier on top of the speed limit before anything counts
	-- as too far. Covers normal physics overshoot and slopes.
	-- This doubles as the speed a cheater can get away with
	-- forever. Together with PositionSlack the current numbers
	-- let someone hold about 22 studs/s against a 16 limit and
	-- never be caught. That gap is the price of not punishing
	-- laggy players, every distance based check has one. Keep it
	-- small rather than trying to close it.
	SpeedTolerance = 1.3,

	-- Flat studs of slack added to every check, for the sub stud
	-- wobble a standing character has.
	--
	-- Keep this tiny. It is added on every single check, so at 5
	-- checks a second every 1 stud here hands out 5 studs/s of
	-- speed that will never be caught no matter how long someone
	-- uses it. Lag is meant to be absorbed by BankSeconds below,
	-- not by this.
	PositionSlack = 0.25,

	-- Movement a player does not use gets banked, up to this many
	-- seconds worth. A player who freezes for a second and then
	-- snaps forward spends the bank instead of being flagged.
	-- This is the single most important anti false flag setting.
	-- Raised from 2 to 3 when the movement abilities were buffed, so a
	-- full glide or slide chain spends the bank rather than being
	-- pulled back.
	BankSeconds = 3,

	-- Bad readings in a row before a speed report. Lag spikes are
	-- one or two readings, real speed hacks are continuous.
	SpeedStreak = 4,

	-- Horizontal studs in one reading that count as a teleport
	-- rather than speed. Only sideways distance counts, so long
	-- falls never trip this.
	TeleportDistance = 80,

	-- Seconds a player may be off the ground before the flight
	-- check looks at them, and how far they must have dropped in
	-- that time to be treated as falling rather than flying.
	MaxAirborneTime = 6,
	MinFallDistance = 12,

	Severity = {
		Speed = 12,
		-- Matches CorrectScore, so a single impossible jump pulls
		-- the player straight back rather than landing first.
		Teleport = 30,
		Flight = 14,
	},
}

Config.Noclip = {
	Enabled = true,

	-- Readings in a row with the player standing inside something
	-- solid. This is the reliable signal.
	InsideStreak = 3,

	-- Readings in a row where the line between two positions goes
	-- through a wall, plus the minimum distance worth tracing.
	-- Deliberately stricter, see the notes in the Noclip module.
	TraceStreak = 5,
	MinTraceDistance = 3,

	Severity = {
		Inside = 20,
		Trace = 6,
	},
}

Config.Physics = {
	Enabled = true,

	-- Puts humanoid properties back if something raises them past
	-- the player's current limit.
	ClampHumanoidProperties = true,

	-- Off by default. Your own game code setting WalkSpeed
	-- directly would otherwise punish an innocent player, so the
	-- value is corrected quietly instead. Turn this on only once
	-- you are sure every speed change goes through
	-- AntiCheat.SetSpeedLimit.
	FlagPropertyChanges = false,

	-- Deletes movement objects that appear on a character without
	-- the server marking them with AntiCheat.Sanction.
	RemoveInjectedMovers = true,

	BannedClasses = {
		"BodyVelocity",
		"BodyGyro",
		"BodyPosition",
		"BodyThrust",
		"BodyAngularVelocity",
		"RocketPropulsion",
		"LinearVelocity",
		"AngularVelocity",
		"VectorForce",
		"Torque",
		"AlignPosition",
		"AlignOrientation",
	},

	Severity = {
		Property = 8,
		Mover = 18,
	},
}

Config.Remotes = {
	-- Defaults for anything bound through RemoteGuard without its
	-- own settings. Rate is calls per second, Burst is how many
	-- can stack up for players who click quickly.
	DefaultRate = 10,
	DefaultBurst = 20,

	-- Ignored calls before anything is reported. Generous on
	-- purpose, a dropped call is already harmless.
	DropsBeforeFlag = 25,

	Severity = 6,
}

Config.Logging = {
	-- Writes flags to a DataStore so they survive the server
	-- shutting down. Without this the only record is the output
	-- log, which is per server and gone the moment it empties.
	Enabled = true,

	StoreName = "AntiCheatLog_v1",

	-- Seconds between batched writes. Flags are buffered rather
	-- than written one at a time, because someone who is actually
	-- cheating produces one every second or so and that would
	-- throttle the DataStore immediately.
	FlushInterval = 30,

	-- How many individual flags are kept per player. Counts and
	-- totals are kept forever, this is just the detail trail.
	MaxRecentPerPlayer = 25,
}

Config.Response = {
	-- Prints every flag to the output. Leave this on while you
	-- are testing, it is how you find out whether your own game
	-- code is tripping the checks.
	LogFlags = true,

	-- Score at which the player gets pulled back to their last
	-- believable position. This is the normal response and it is
	-- harmless if it ever happens to an innocent player.
	CorrectScore = 30,

	-- Score at which the player is removed. Set KickEnabled to
	-- false for the first few days of a game, watch the log, and
	-- only turn it on once you are sure nothing legitimate is
	-- being reported.
	KickEnabled = false,
	KickScore = 110,
	KickMessage = "You were removed for exploiting.",

	-- Score bled off per second. A player who trips something
	-- once and then plays normally returns to clean.
	ScoreDecayPerSecond = 2.5,

	-- Windows where checks are skipped entirely, because the
	-- player is being moved by something other than themselves.
	SpawnGrace = 4,
	TeleportGrace = 2,
	CorrectionGrace = 1.5,
	SpeedChangeGrace = 1,
	ServerStartGrace = 10,
	DefaultExceptionTime = 3,
}

return Config
