-- Movement
-- Compares how far a player actually moved against how far they
-- could have moved. This is the check that stops speed hacks,
-- teleporting and flying, because whatever an exploiter does on
-- their own machine, the position that reaches the server is
-- still a position the server can refuse.
--
-- The hard part of a check like this is not catching cheaters, it
-- is not catching everyone else. A player on a bad connection
-- freezes and then snaps forward, and the snap looks identical to
-- a teleport. The movement bank below is what separates them: any
-- distance a player does not use gets saved up, and the snap
-- spends what was saved. A real speed hack drains the bank in a
-- fraction of a second and then has nothing left to hide behind.

local Movement = {}

Movement.Name = "Movement"
Movement.Order = 1

local api
local Config

local FLOOR_RAY = Vector3.new(0, -8, 0)

function Movement.Init(context)
	api = context
	Config = context.Config
end

-- Standing on a moving platform or a conveyor moves a player
-- without them doing anything, so that speed is added to what
-- they are allowed.
local function floorSpeed(profile)
	local result = workspace:Raycast(profile.root.Position, FLOOR_RAY, profile.raycastParams)
	if not result or not result.Instance then
		return 0
	end

	local velocity = result.Instance.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function checkDistance(profile, deltaTime)
	local settings = Config.Movement
	local root = profile.root
	local humanoid = profile.humanoid
	local previous = profile.lastPosition

	if not previous then
		return
	end

	local position = root.Position

	-- Anything that legitimately moves a player without them
	-- walking is skipped rather than guessed at.
	if humanoid.SeatPart or humanoid.PlatformStand or root.Anchored then
		profile.safePosition = position
		profile.movementBank = 0
		profile.speedStreak = 0
		return
	end

	local delta = position - previous
	local horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude

	local ping = 0
	pcall(function()
		ping = profile.player:GetNetworkPing()
	end)

	local limit = profile.speedLimit + floorSpeed(profile)
	local allowance = limit * deltaTime * settings.SpeedTolerance + settings.PositionSlack

	-- Players further away get a slightly deeper bank, since their
	-- updates arrive in bigger, less frequent chunks.
	local maxBank = profile.speedLimit * (settings.BankSeconds + math.min(ping, 0.5))

	if horizontal <= allowance then
		profile.movementBank = math.min(profile.movementBank + (allowance - horizontal), maxBank)
		profile.speedStreak = math.max(0, profile.speedStreak - 1)
		profile.safePosition = position
		return
	end

	local excess = horizontal - allowance

	if excess <= profile.movementBank then
		-- Covered by distance banked while they were slower. This
		-- is what a connection catching up looks like.
		profile.movementBank -= excess
		profile.safePosition = position
		return
	end

	profile.movementBank = 0

	if horizontal >= settings.TeleportDistance then
		api.Flag(
			profile.player,
			"Teleport",
			settings.Severity.Teleport,
			string.format("%.0f studs in %.2fs", horizontal, deltaTime)
		)
		profile.speedStreak = 0
		return
	end

	profile.speedStreak += 1

	if profile.speedStreak >= settings.SpeedStreak then
		api.Flag(
			profile.player,
			"Speed",
			settings.Severity.Speed,
			string.format("%.0f studs/s against a limit of %.0f", horizontal / deltaTime, profile.speedLimit)
		)
		profile.speedStreak = 0
	end
end

-- Flying and hovering both look the same from the server: a
-- player who has been off the ground for a while without going
-- down. A long fall is off the ground too, so the check only
-- reports someone who has not dropped in that whole time.
local function checkAirborne(profile, clock)
	local settings = Config.Movement
	local humanoid = profile.humanoid
	local position = profile.root.Position

	local state = humanoid:GetState()
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local excused = state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Seated
		or state == Enum.HumanoidStateType.Dead

	if grounded or excused then
		profile.airborneSince = nil
		profile.airborneApexY = nil
		return
	end

	if not profile.airborneSince then
		profile.airborneSince = clock
		profile.airborneApexY = position.Y
	end

	profile.airborneApexY = math.max(profile.airborneApexY, position.Y)

	local airborneFor = clock - profile.airborneSince
	if airborneFor < settings.MaxAirborneTime then
		return
	end

	local dropped = profile.airborneApexY - position.Y
	if dropped < settings.MinFallDistance then
		api.Flag(
			profile.player,
			"Flight",
			settings.Severity.Flight,
			string.format("off the ground %.1fs, dropped %.0f studs", airborneFor, dropped)
		)
	end

	-- Restart the window either way, so one long fall cannot
	-- report over and over.
	profile.airborneSince = clock
	profile.airborneApexY = position.Y
end

function Movement.Step(profile, deltaTime, clock)
	if not Config.Movement.Enabled then
		return
	end

	checkDistance(profile, deltaTime)
	checkAirborne(profile, clock)
end

return Movement
