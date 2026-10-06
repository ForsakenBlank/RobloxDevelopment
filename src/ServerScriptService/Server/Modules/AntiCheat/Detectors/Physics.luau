-- Physics
-- Keeps humanoid properties inside the limits the server set, and
-- removes movement objects that turn up on a character without
-- the server putting them there.
--
-- Worth being honest about what this is for. Most modern exploits
-- never send anything to the server at all, they just move the
-- character, which is why the Movement check matters far more
-- than this one. This catches the lazy cases cheaply and stops a
-- raised WalkSpeed from doing anything, and that is all.
--
-- Property changes correct quietly instead of reporting, because
-- the likeliest cause of an out of range WalkSpeed is your own
-- game code setting it directly, and punishing a player for that
-- would be worse than the exploit.

local Physics = {}

Physics.Name = "Physics"
Physics.Order = 3

local api
local Config
local bannedClasses = {}

function Physics.Init(context)
	api = context
	Config = context.Config

	for _, className in ipairs(Config.Physics.BannedClasses) do
		bannedClasses[className] = true
	end
end

local function watchProperty(profile, propertyName, getLimit)
	local humanoid = profile.humanoid
	local settings = Config.Physics

	humanoid:GetPropertyChangedSignal(propertyName):Connect(function()
		local limit = getLimit()
		local value = humanoid[propertyName]

		if value <= limit then
			return
		end

		humanoid[propertyName] = limit

		if settings.FlagPropertyChanges then
			api.Flag(
				profile.player,
				"Humanoid",
				settings.Severity.Property,
				string.format("%s set to %.0f against a limit of %.0f", propertyName, value, limit)
			)
		end
	end)
end

function Physics.CharacterAdded(profile, character)
	local settings = Config.Physics
	if not settings.Enabled then
		return
	end

	if settings.ClampHumanoidProperties then
		watchProperty(profile, "WalkSpeed", function()
			return profile.speedLimit
		end)
		watchProperty(profile, "JumpPower", function()
			return profile.jumpPowerLimit
		end)
		watchProperty(profile, "JumpHeight", function()
			return profile.jumpHeightLimit
		end)
	end

	if not settings.RemoveInjectedMovers then
		return
	end

	character.DescendantAdded:Connect(function(descendant)
		if not bannedClasses[descendant.ClassName] then
			return
		end

		-- Deferred so server code can parent the object first and
		-- call AntiCheat.Sanction on the next line without the
		-- order mattering.
		task.defer(function()
			if api.IsSanctioned(descendant) or not descendant.Parent then
				return
			end

			descendant:Destroy()

			api.Flag(
				profile.player,
				"PhysicsObject",
				settings.Severity.Mover,
				descendant.ClassName .. " appeared on the character"
			)
		end)
	end)
end

return Physics
