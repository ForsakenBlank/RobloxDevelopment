-- RemoteGuard
-- Rate limits remotes so a client cannot spam them.
--
-- This is the part of an anti cheat that matters most in
-- practice. Movement hacks are loud and obvious, but a remote
-- fired two thousand times a second is silent, needs no movement
-- at all, and will happily drain your economy or your server's
-- frame rate. Every remote your game exposes should go through
-- here.
--
-- Use it instead of connecting OnServerEvent yourself:
--
--     local RemoteGuard = require(AntiCheat.RemoteGuard)
--
--     RemoteGuard.BindEvent(buyItemRemote, { Rate = 5 }, function(player, itemName)
--         -- runs at most 5 times a second per player
--     end)
--
-- Rate limiting is not validation. It stops someone calling
-- BuyItem a thousand times a second, it does not stop them
-- calling it once with a negative price. Check the arguments in
-- your handler, always, and never trust a number a client sent.

local Players = game:GetService("Players")

local AntiCheat = require(script.Parent)
local Config = require(script.Parent.Config)

local RemoteGuard = {}

local buckets = {}

local function resolve(options)
	options = options or {}
	return {
		Rate = options.Rate or Config.Remotes.DefaultRate,
		Burst = options.Burst or Config.Remotes.DefaultBurst,
		Validate = options.Validate,
	}
end

local function bucketFor(remote, player, settings)
	local perRemote = buckets[remote]
	if not perRemote then
		perRemote = {}
		buckets[remote] = perRemote
	end

	local bucket = perRemote[player]
	if not bucket then
		bucket = {
			tokens = settings.Burst,
			lastRefill = os.clock(),
			drops = 0,
		}
		perRemote[player] = bucket
	end

	return bucket
end

-- Standard token bucket. Tokens refill at Rate per second up to
-- Burst, and every call spends one. A player who clicks in bursts
-- is fine, a player holding down a fire loop runs dry.
local function allow(remote, player, settings)
	local bucket = bucketFor(remote, player, settings)
	local clock = os.clock()

	bucket.tokens = math.min(settings.Burst, bucket.tokens + (clock - bucket.lastRefill) * settings.Rate)
	bucket.lastRefill = clock

	if bucket.tokens < 1 then
		bucket.drops += 1

		if bucket.drops >= Config.Remotes.DropsBeforeFlag then
			bucket.drops = 0
			AntiCheat.Flag(
				player,
				"RemoteSpam",
				Config.Remotes.Severity,
				string.format("%s over its %d per second limit", remote.Name, settings.Rate)
			)
		end

		return false
	end

	bucket.tokens -= 1
	return true
end

function RemoteGuard.BindEvent(remote, options, handler)
	local settings = resolve(options)

	return remote.OnServerEvent:Connect(function(player, ...)
		if not allow(remote, player, settings) then
			return
		end

		if settings.Validate and not settings.Validate(player, ...) then
			return
		end

		handler(player, ...)
	end)
end

function RemoteGuard.BindFunction(remote, options, handler)
	local settings = resolve(options)

	remote.OnServerInvoke = function(player, ...)
		if not allow(remote, player, settings) then
			return nil
		end

		if settings.Validate and not settings.Validate(player, ...) then
			return nil
		end

		return handler(player, ...)
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, perRemote in pairs(buckets) do
		perRemote[player] = nil
	end
end)

return RemoteGuard
