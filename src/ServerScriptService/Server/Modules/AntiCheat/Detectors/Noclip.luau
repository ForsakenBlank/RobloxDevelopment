-- Noclip
-- Two separate checks with deliberately different weights.
--
-- The first asks whether the player is currently standing inside
-- something solid and anchored. That is what noclip actually
-- looks like and it is hard to do by accident, so it carries a
-- real severity.
--
-- The second traces the straight line between where a player was
-- and where they are now, and asks whether that line goes through
-- a wall. It is useful but it is not proof, because a player
-- running a tight circle around a pillar produces the same
-- straight line as a player clipping through it. That is why it
-- needs a longer streak and is scored low enough that it can
-- never remove anyone on its own.

local Noclip = {}

Noclip.Name = "Noclip"
Noclip.Order = 2

local api
local Config

function Noclip.Init(context)
	api = context
	Config = context.Config
end

-- Other players and anything they are carrying can overlap you
-- for a moment without either of you doing anything wrong.
local function belongsToCharacter(part)
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return true
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local function checkInside(profile)
	local settings = Config.Noclip
	local parts = workspace:GetPartsInPart(profile.root, profile.overlapParams)

	local blocker = nil
	for _, part in ipairs(parts) do
		-- Only anchored solid geometry counts. An unanchored crate
		-- pushed against a player is not the player's fault.
		if part.CanCollide and part.Anchored and not belongsToCharacter(part) then
			blocker = part
			break
		end
	end

	if not blocker then
		profile.insideStreak = 0
		return
	end

	profile.insideStreak += 1

	if profile.insideStreak >= settings.InsideStreak then
		api.Flag(profile.player, "Noclip", settings.Severity.Inside, "standing inside " .. blocker.Name)
		profile.insideStreak = 0
	end
end

local function checkTrace(profile)
	local settings = Config.Noclip
	local previous = profile.lastPosition
	if not previous then
		return
	end

	local delta = profile.root.Position - previous
	if delta.Magnitude < settings.MinTraceDistance then
		profile.traceStreak = 0
		return
	end

	local result = workspace:Raycast(previous, delta, profile.raycastParams)
	-- dashing through an enemy or past a teammate is not noclipping
	if not result or not result.Instance or not result.Instance.CanCollide or belongsToCharacter(result.Instance) then
		profile.traceStreak = 0
		return
	end

	profile.traceStreak += 1

	if profile.traceStreak >= settings.TraceStreak then
		api.Flag(profile.player, "NoclipTrace", settings.Severity.Trace, "path crossed " .. result.Instance.Name)
		profile.traceStreak = 0
	end
end

function Noclip.Step(profile, deltaTime, clock)
	if not Config.Noclip.Enabled then
		return
	end

	local humanoid = profile.humanoid
	if humanoid.SeatPart or profile.root.Anchored then
		profile.insideStreak = 0
		profile.traceStreak = 0
		return
	end

	checkInside(profile)
	checkTrace(profile)
end

return Noclip
