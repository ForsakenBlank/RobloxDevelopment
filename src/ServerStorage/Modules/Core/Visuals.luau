local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MovementVisuals = require(ReplicatedStorage.Modules.Visuals.MovementVisuals)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)

-- Every dash and slide sends dashsmoke. A ground dash covers about 65
-- studs in half a second, far past the walking speed check, so each
-- one banks that much with the anti cheat, at most once per this many
-- seconds (just under the dash cooldown in MovementSettings).
local DashCredit = 70
local DashCreditInterval = 0.5

local Visuals = {}
Visuals.__index = Visuals

--------------------------------------------------------------------------------------

function Visuals.runvfx(player : Player, msg : string, animLength : number)
	MovementVisuals.runvfx(player, "start", animLength)
end

function Visuals.runvfxstop(player : Player, msg : string, animLength : number)
	MovementVisuals.runvfx(player, "stop", animLength)
end

--------------------------------------------------------------------------------------

function Visuals.cloudvfx(player : Player, direction : string, animLength : number)	
	MovementVisuals.cloudvfx(player, direction, animLength)
end

--------------------------------------------------------------------------------------

function Visuals.landvfx(player : Player, direction : string, animLength : number)	
	MovementVisuals.landvfx(player, direction, animLength)
end

--------------------------------------------------------------------------------------

function Visuals.doublejump(player : Player, direction : string, animLength : number)	
	MovementVisuals.doublejump(player, direction, animLength)
end

--------------------------------------------------------------------------------------

-- The dash i-frames (GameConfig.IFrames.Dash), at most once per dash
-- cooldown so they can not be kept up by spamming.
local LastIFrames: { [Player]: number } = {}
game:GetService("Players").PlayerRemoving:Connect(function(Leaving)
	LastIFrames[Leaving] = nil
end)

function Visuals.dashsmoke(player : Player, direction : string, animLength : number)	
	AntiCheat.CreditMovement(player, "Dash", DashCredit, DashCreditInterval)
	local IFrames = GameConfig.IFrames
	if IFrames and IFrames.Enabled and (IFrames.Dash or 0) > 0 and os.clock() - (LastIFrames[player] or 0) >= DashCreditInterval then
		LastIFrames[player] = os.clock()
		local PlayerStats = require(ServerScriptService.Server.Game.Core.PlayerStats)
		local Stats = PlayerStats.Get(player)
		if Stats then
			Stats:SetInvulnerable(IFrames.Dash)
		end
	end
	MovementVisuals.dashsmoke(player, direction, animLength)
end

function Visuals.frontdash(player : Player, direction : string, animLength : number)	
	MovementVisuals.frontdash(player, direction, animLength)
end

--------------------------------------------------------------------------------------

function Visuals.glidevfx(player : Player, direction : string, animLength : number)	
	MovementVisuals.glidevfx(player, direction, animLength)
end

--------------------------------------------------------------------------------------

function Visuals.sidedash(player : Player, direction : string, animLength : number)	
	MovementVisuals.sidedash(player, direction, animLength)
end

function Visuals.backdash(player : Player, direction : string, animLength : number)	
	MovementVisuals.backdash(player, direction, animLength)
end

--------------------------------------------------------------------------------------

function Visuals.ziplinestart(player : Player, direction : string, animLength : number)	
	MovementVisuals.ziplinestart(player, direction, animLength)
end

function Visuals.ziplinestop(player : Player, direction : string, animLength : number)	
	MovementVisuals.ziplinestop(player, direction, animLength)
end

return Visuals