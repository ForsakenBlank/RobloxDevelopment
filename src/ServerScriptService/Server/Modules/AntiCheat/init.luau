-- AntiCheat
-- Server side exploit detection and correction.
--
-- How it works in one paragraph: the server watches where every
-- player actually ends up and compares that against where they
-- could possibly have got to. Anything impossible adds to a
-- score. Small amounts of weirdness are ignored, because lag and
-- physics produce weirdness constantly. Sustained impossible
-- behaviour pulls the player back to their last believable
-- position, and only someone who keeps doing it gets removed.
--
-- Read the notes at the bottom of this file before you change
-- anything. There are a few API calls your own game code has to
-- use or you will end up flagging your own players.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(script.Config)

local AntiCheat = {}

-- Fires as (player, checkName, severity, detail, score) every
-- time something is reported. Connect your own logging to this.
AntiCheat.Reported = Instance.new("BindableEvent")

local profiles = {}
local detectors = {}
local sanctioned = setmetatable({}, { __mode = "k" })
local extraIgnored = setmetatable({}, { __mode = "k" })

local serverStartedAt = os.clock()
local sampleInterval = 1 / Config.SampleRate
local accumulator = 0

local function rebuildFilters(profile)
	local ignored = { profile.character }

	for _, folderName in ipairs(Config.IgnoredWorkspaceFolders) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			table.insert(ignored, folder)
		end
	end

	for instance in pairs(extraIgnored) do
		table.insert(ignored, instance)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignored
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	profile.raycastParams = raycastParams

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignored
	overlapParams.MaxParts = 12
	profile.overlapParams = overlapParams
end

local function onCharacterAdded(profile, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end

	profile.character = character
	profile.humanoid = humanoid
	profile.root = root
	profile.lastPosition = root.Position
	profile.safePosition = root.Position

	-- Limits go back to normal on respawn. If a player is meant
	-- to keep a speed boost through death, reapply it yourself.
	profile.speedLimit = Config.Movement.DefaultWalkSpeed
	profile.jumpPowerLimit = Config.Movement.DefaultJumpPower
	profile.jumpHeightLimit = Config.Movement.DefaultJumpHeight

	profile.movementBank = 0
	profile.speedStreak = 0
	profile.insideStreak = 0
	profile.traceStreak = 0
	profile.airborneSince = nil
	profile.airborneApexY = nil

	rebuildFilters(profile)
	AntiCheat.GrantException(profile.player, Config.Response.SpawnGrace)

	for _, detector in ipairs(detectors) do
		if detector.CharacterAdded then
			detector.CharacterAdded(profile, character)
		end
	end
end

local function onPlayerAdded(player)
	local profile = {
		player = player,
		character = nil,
		humanoid = nil,
		root = nil,

		score = 0,
		exemptUntil = 0,

		speedLimit = Config.Movement.DefaultWalkSpeed,
		jumpPowerLimit = Config.Movement.DefaultJumpPower,
		jumpHeightLimit = Config.Movement.DefaultJumpHeight,

		lastPosition = nil,
		safePosition = nil,
		movementBank = 0,
		speedStreak = 0,
		insideStreak = 0,
		traceStreak = 0,
		airborneSince = nil,
		airborneApexY = nil,

		raycastParams = nil,
		overlapParams = nil,
	}

	profiles[player] = profile

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(profile, character)
	end)

	if player.Character then
		task.spawn(onCharacterAdded, profile, player.Character)
	end
end

local function onPlayerRemoving(player)
	profiles[player] = nil
end

function AntiCheat.GetProfile(player)
	return profiles[player]
end

function AntiCheat.GetScore(player)
	local profile = profiles[player]
	return profile and profile.score or 0
end

function AntiCheat.ClearScore(player)
	local profile = profiles[player]
	if profile then
		profile.score = 0
	end
end

-- Skips every check for this player for a moment. Use it around
-- anything that moves a player without them walking, launch pads,
-- knockback, cutscenes, ragdolls, that sort of thing.
function AntiCheat.GrantException(player, seconds)
	local profile = profiles[player]
	if not profile then
		return
	end
	local duration = seconds or Config.Response.DefaultExceptionTime
	profile.exemptUntil = math.max(profile.exemptUntil, os.clock() + duration)
end

function AntiCheat.IsExempt(player)
	local profile = profiles[player]
	return profile ~= nil and os.clock() < profile.exemptUntil
end

-- Use this anywhere the server moves a player, instead of setting
-- HumanoidRootPart.CFrame yourself. Setting the CFrame directly
-- looks exactly like a teleport exploit from the server's side.
function AntiCheat.Teleport(player, target)
	local profile = profiles[player]
	if not profile or not profile.root then
		return false
	end

	local cframe = typeof(target) == "Vector3" and CFrame.new(target) or target
	profile.root.CFrame = cframe
	profile.root.AssemblyLinearVelocity = Vector3.zero

	profile.lastPosition = cframe.Position
	profile.safePosition = cframe.Position
	profile.movementBank = 0
	profile.speedStreak = 0

	AntiCheat.GrantException(player, Config.Response.TeleportGrace)
	return true
end

-- Banks extra distance for a burst of movement a client does on its
-- own, a dash or a slide, so a legitimate burst is not mistaken for a
-- speed hack. Each Key can be claimed at most once every Interval
-- seconds, so claiming it over and over is worth no more than really
-- dashing, and a teleport sized jump is still caught.
function AntiCheat.CreditMovement(player, key, studs, interval)
	local profile = profiles[player]
	if not profile then
		return
	end
	profile.credits = profile.credits or {}
	local now = os.clock()
	if now - (profile.credits[key] or 0) < (interval or 0) then
		return
	end
	profile.credits[key] = now
	local cap = profile.speedLimit * Config.Movement.BankSeconds + studs
	profile.movementBank = math.min((profile.movementBank or 0) + studs, cap)
end

-- Use this instead of setting Humanoid.WalkSpeed yourself. It
-- raises the allowance and the humanoid together, so a speed
-- boost does not look like a speed hack.
function AntiCheat.SetSpeedLimit(player, walkSpeed)
	local profile = profiles[player]
	if not profile then
		return
	end

	profile.speedLimit = walkSpeed
	if profile.humanoid then
		profile.humanoid.WalkSpeed = walkSpeed
	end

	AntiCheat.GrantException(player, Config.Response.SpeedChangeGrace)
end

function AntiCheat.ResetSpeedLimit(player)
	AntiCheat.SetSpeedLimit(player, Config.Movement.DefaultWalkSpeed)
end

-- Raises the allowance only, without touching the humanoid. For when
-- a client side movement system owns Humanoid.WalkSpeed itself, as
-- the movement framework does, and the server only needs to say how
-- fast that system is now allowed to go. Server.Game.Core.PlayerStats
-- uses this for speed buffs.
function AntiCheat.SetSpeedAllowance(player, walkSpeed)
	local profile = profiles[player]
	if not profile then
		return
	end

	profile.speedLimit = walkSpeed
	AntiCheat.GrantException(player, Config.Response.SpeedChangeGrace)
end

function AntiCheat.SetJumpLimit(player, jumpPower, jumpHeight)
	local profile = profiles[player]
	if not profile then
		return
	end

	profile.jumpPowerLimit = jumpPower or profile.jumpPowerLimit
	profile.jumpHeightLimit = jumpHeight or profile.jumpHeightLimit

	local humanoid = profile.humanoid
	if humanoid then
		if jumpPower then
			humanoid.JumpPower = jumpPower
		end
		if jumpHeight then
			humanoid.JumpHeight = jumpHeight
		end
	end

	AntiCheat.GrantException(player, Config.Response.SpeedChangeGrace)
end

-- Marks a BodyVelocity, AlignPosition or similar as something the
-- server created, so the physics check leaves it alone. Call it
-- before you parent the object to the character.
function AntiCheat.Sanction(instance)
	sanctioned[instance] = true
	return instance
end

function AntiCheat.IsSanctioned(instance)
	return sanctioned[instance] == true
end

-- Hides an instance from the position and noclip checks. Useful
-- for invisible barriers or anything the game moves through
-- players on purpose.
function AntiCheat.IgnoreInstance(instance)
	extraIgnored[instance] = true
	for _, profile in pairs(profiles) do
		if profile.character then
			rebuildFilters(profile)
		end
	end
end

-- Pulls a player back to the last position that made sense.
function AntiCheat.Correct(player)
	local profile = profiles[player]
	if not profile or not profile.root or not profile.safePosition then
		return
	end

	profile.root.CFrame = CFrame.new(profile.safePosition)
	profile.root.AssemblyLinearVelocity = Vector3.zero

	profile.lastPosition = profile.safePosition
	profile.movementBank = 0
	profile.speedStreak = 0

	-- Without this the correction itself reads as a teleport.
	AntiCheat.GrantException(player, Config.Response.CorrectionGrace)
end

function AntiCheat.Flag(player, checkName, severity, detail)
	local profile = profiles[player]
	if not profile then
		return
	end

	-- Nothing is reported during a grace window, or during the
	-- first few seconds of a server while things settle.
	if AntiCheat.IsExempt(player) then
		return
	end
	if os.clock() - serverStartedAt < Config.Response.ServerStartGrace then
		return
	end

	profile.score += severity

	if Config.Response.LogFlags then
		warn(string.format(
			"[AntiCheat] %s | %s | +%d | score %d | %s",
			player.Name,
			checkName,
			severity,
			math.floor(profile.score),
			detail or "no detail"
		))
	end

	AntiCheat.Reported:Fire(player, checkName, severity, detail, profile.score)

	if Config.Response.KickEnabled and profile.score >= Config.Response.KickScore then
		profile.score = 0
		player:Kick(Config.Response.KickMessage)
	elseif profile.score >= Config.Response.CorrectScore then
		AntiCheat.Correct(player)
	end
end

local function step(deltaTime)
	local clock = os.clock()

	for player, profile in pairs(profiles) do
		if profile.score > 0 then
			profile.score = math.max(0, profile.score - Config.Response.ScoreDecayPerSecond * deltaTime)
		end

		local character = profile.character
		local humanoid = profile.humanoid
		local root = profile.root

		local alive = character ~= nil
			and character.Parent ~= nil
			and humanoid ~= nil
			and root ~= nil
			and humanoid.Health > 0

		if alive then
			if AntiCheat.IsExempt(player) then
				-- Reset anything that counts upwards so a grace
				-- window never leaves half finished evidence
				-- behind for the next check to act on.
				profile.speedStreak = 0
				profile.insideStreak = 0
				profile.traceStreak = 0
				profile.airborneSince = nil
				profile.safePosition = root.Position
			else
				for _, detector in ipairs(detectors) do
					if detector.Step then
						detector.Step(profile, deltaTime, clock)
					end
				end
			end

			profile.lastPosition = root.Position
		end
	end
end

function AntiCheat.Init()
	local api = {
		Config = Config,
		Flag = AntiCheat.Flag,
		IsExempt = AntiCheat.IsExempt,
		IsSanctioned = AntiCheat.IsSanctioned,
		GrantException = AntiCheat.GrantException,
	}

	for _, module in ipairs(script.Detectors:GetChildren()) do
		if module:IsA("ModuleScript") then
			local detector = require(module)
			if detector.Init then
				detector.Init(api)
			end
			table.insert(detectors, detector)
		end
	end

	table.sort(detectors, function(a, b)
		return (a.Order or 100) < (b.Order or 100)
	end)

	-- Handed the event rather than requiring this module back, so
	-- there is no loop between the two.
	if Config.Logging.Enabled then
		require(script.FlagLog).Init(AntiCheat.Reported)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime
		if accumulator < sampleInterval then
			return
		end

		local elapsed = accumulator
		accumulator = 0
		step(elapsed)
	end)
end

return AntiCheat


-- NOTES
--
-- What this can and cannot do
--
-- You cannot detect an injected script from inside your game. An
-- exploiter's executor runs above your LocalScripts. It can read
-- them, rewrite them, delete them, and lie to anything they
-- report back. Any check that lives in a LocalScript is asking
-- the cheater's own machine whether the cheater is cheating, so
-- everything here runs on the server instead.
--
-- What does work is the thing this module does. An exploiter can
-- make their own screen show them flying at 500 studs a second,
-- but the position that reaches the server is still just a
-- position, and the server is allowed to refuse it. That is why
-- the movement check carries most of the weight here and the
-- physics check is only a cheap extra.
--
-- The gap none of this covers is your own remotes. If you have a
-- RemoteEvent that hands out cash to whoever fires it, no
-- movement check will save you. Validate on the server and put
-- every remote through RemoteGuard.
--
--
-- API your game code should use
--
-- AntiCheat.Teleport(player, cframeOrPosition)
--     Anywhere the server moves a player.
--
-- AntiCheat.SetSpeedLimit(player, walkSpeed)
-- AntiCheat.ResetSpeedLimit(player)
-- AntiCheat.SetJumpLimit(player, jumpPower, jumpHeight)
--     Instead of setting the humanoid properties directly.
--
-- AntiCheat.GrantException(player, seconds)
--     Around launch pads, knockback, cutscenes, ragdolls.
--
-- AntiCheat.Sanction(instance)
--     On a BodyVelocity or similar before parenting it.
--
-- AntiCheat.IgnoreInstance(instance)
--     On anything players are meant to pass through.
--
-- AntiCheat.Reported.Event:Connect(function(player, check, severity, detail, score)
--     For your own logging or analytics.
--
--
-- Tuning it
--
-- Leave Config.Response.KickEnabled off for the first few days of
-- a live game and watch the output. If nothing legitimate is
-- being reported, turn it on. If your own systems are showing up
-- in the log, that is a sign they should be going through the
-- API above rather than a sign the thresholds are wrong.
