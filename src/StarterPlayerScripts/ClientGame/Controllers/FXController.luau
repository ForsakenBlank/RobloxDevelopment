--[[
	FXController

	Receives combat effect broadcasts from the server and renders them
	through Game.Shared.CombatFX. That is the whole job. It exists so
	the effect library does not need to know about remotes, and so
	there is one listener rather than one in every controller.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.CombatFX with
	  (Name, Character, Data), fired by CombatFX.Broadcast on the
	  server from the weapons, abilities, DamageService and
	  StatusEffectService.

	Uses:
	  Game.Shared.CombatFX to render.

	Started by:
	  ClientGame.ClientMain.

	The local player's own attacks are rendered by CombatInput and
	AbilityInput the instant the key is pressed. The server leaves the
	attacker out of the broadcast for those, so nothing plays twice.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local FXController = {}

function FXController.Init()
	local Remote = Events:WaitForChild("CombatFX", 10)
	if not Remote then
		warn("[FXController] no CombatFX remote, effects from other players will not show")
		return
	end
	Remote.OnClientEvent:Connect(function(Name: string, Character: Model?, Data: any)
		CombatFX.Play(Name, Character, Data)
	end)
end

return FXController
