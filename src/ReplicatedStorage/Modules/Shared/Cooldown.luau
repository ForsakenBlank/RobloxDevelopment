--!strict

local CooldownManager = {}

type CooldownMap = { [string]: boolean }

local Cooldowns: CooldownMap = {}
CooldownManager.Cooldowns = Cooldowns

function CooldownManager.Set(Key: string, Duration: number): ()
	if not CooldownManager.Cooldowns[Key] then
		CooldownManager.Cooldowns[Key] = false
	end

	CooldownManager.Cooldowns[Key] = true

	task.delay(Duration, function()
		CooldownManager.Cooldowns[Key] = false
	end)
end

function CooldownManager.Check(Key: string): boolean
	return CooldownManager.Cooldowns[Key] or false
end

function CooldownManager.GetCooldowns(): CooldownMap
	return CooldownManager.Cooldowns
end

return CooldownManager