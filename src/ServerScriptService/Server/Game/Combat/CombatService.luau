--[[
	CombatService

	The front door for everything the player does in combat. The client
	never calls a weapon or an ability directly. It fires one of the
	combat remotes, this module receives it, checks the request is
	allowed, and only then hands it to the right weapon or ability.

	The checks it does are: is there actually a run in progress, does the
	player have a PlayerStats object, is the weapon or ability the one
	they currently have equipped, is it off cooldown on the server clock,
	and for abilities does the player have the energy. Doing the checks
	here means a weapon module can be written assuming it was called
	legally.

	Weapon and ability swapping (R and G) comes through here too, rather
	than having its own remote. A swap is a request from the client like
	any other and needs the same validation, so it goes through the same
	door and gets passed on to Server.Game.Core.Loadout.

	This is also where the rate limit goes. A client that fires the
	attack remote a hundred times a second should be dropped and flagged
	rather than served.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.WeaponAttack, with
	  (Button, AimPosition, WeaponName). The same remote is fired back
	  to the client with (Button, Accepted, Cooldown) so the hotbar can
	  correct itself if the server said no.
	  ReplicatedStorage.Remotes.Events.LoadoutSwap, with (Kind, Index),
	  Kind being "Weapon" or "Ability" and Index the slot or nil for
	  the other one.
	  ReplicatedStorage.Remotes.Events.AbilityUsed, with
	  (AbilityName, AimPosition), for the equipped ability.

	Fired by:
	  ClientGame.Controllers.CombatInput and
	  ClientGame.Controllers.AbilityInput.

	Asks:
	  Server.Game.Core.Loadout which weapon and which ability the player
	  currently has equipped. It should not keep its own copy of that,
	  since the player can swap at any time.

	Hands off to:
	  Server.Game.Combat.Weapons.WeaponBase, which routes to Sword,
	  Pistol, RPG or Shotgun and their MB1 or MB2.
	  Server.Game.Combat.Abilities.AbilityBase, which routes to StunSlam,
	  Teleport, Rage or HealBurst.
	  Server.Game.Core.Loadout for a swap request.

	Reads:
	  Server.Game.Core.PlayerStats for the player's current energy.
	  Game.Data.WeaponData and Game.Data.AbilityData for the cooldowns it
	  is checking against.

	Reports to:
	  ServerScriptService.Server.Modules.AntiCheat, specifically
	  AntiCheat.RemoteGuard and AntiCheat.FlagLog, when a request fails a
	  check. That way suspicious combat requests end up in the same place
	  as the movement flags rather than in a separate log.

	The cursor position for a Pistol shot or a Teleport comes from the
	client, and there is no way around that since the server does not
	know where the mouse is. So it has to be treated as a request and
	range checked here, not trusted. Teleport in particular needs its
	distance clamped, and the destination checked against the player's
	current area through Server.Game.Rooms.RoomZones, or a client can
	send any position in the map and skip a shut gate.

	An attack sent for a weapon the player is not holding must be
	rejected, not silently redirected to the one they are holding. If a
	client can name the weapon it fires, it can name the one with the
	best damage regardless of what it swapped to.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local RemoteGuard = require(ServerScriptService.Server.Modules.AntiCheat.RemoteGuard)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local Loadout = require(script.Parent.Parent.Core.Loadout)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local function GetOrCreateEvent(Name: string): RemoteEvent
	local Existing = Events:FindFirstChild(Name)
	if Existing then
		return Existing
	end
	local Remote = Instance.new("RemoteEvent")
	Remote.Name = Name
	Remote.Parent = Events
	return Remote
end

local WeaponAttack = GetOrCreateEvent("WeaponAttack")
local AbilityUsed = GetOrCreateEvent("AbilityUsed")
local LoadoutSwap = GetOrCreateEvent("LoadoutSwap")

local CombatService = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

CombatService.Settings = {
	-- Remote rate limits, per player per second, with the burst the
	-- token bucket allows. Attacks are capped just above the fastest
	-- weapon (Pistol MB1 at 0.2s is 5 a second).
	AttackRate = 12,
	AttackBurst = 6,
	SwapRate = 8,
	SwapBurst = 4,
	AbilityRate = 4,
	AbilityBurst = 2,
	-- The furthest an aim position may be from the player before it is
	-- pulled in along the same line. Stops a client aiming at the far
	-- side of the map.
	MaxAimDistance = 500,
	-- How many rejected requests in a row before the anti cheat is
	-- told. Ordinary lag produces one or two, a modified client
	-- produces a stream.
	RejectionsBeforeFlag = 12,
	FlagSeverity = 1,
}

local Rejections: { [Player]: number } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function Reject(Player: Player, Reason: string)
	Rejections[Player] = (Rejections[Player] or 0) + 1
	if Rejections[Player] >= CombatService.Settings.RejectionsBeforeFlag then
		Rejections[Player] = 0
		AntiCheat.Flag(Player, "Combat", CombatService.Settings.FlagSeverity, Reason)
	end
	if GameConfig.Debug.LogCombat then
		print("[CombatService] rejected " .. Player.Name .. ": " .. Reason)
	end
end

local function Accept(Player: Player)
	Rejections[Player] = 0
end

-- The common checks every combat request needs. Returns the stats and
-- loadout objects, or nil and a reason.
local function GetCombatState(Player: Player)
	if not RunConfig.IsSet() then
		return nil, nil, "no run"
	end
	local Stats = PlayerStats.Get(Player)
	if not Stats then
		return nil, nil, "no stats"
	end
	if not Stats:IsAlive() then
		return nil, nil, "dead"
	end
	local PlayerLoadout = Loadout.Get(Player)
	if not PlayerLoadout then
		return nil, nil, "no loadout"
	end
	return Stats, PlayerLoadout, nil
end

-- Pulls an aim position in to MaxAimDistance from the player.
local function ClampAim(Player: Player, AimPosition: any): Vector3?
	if typeof(AimPosition) ~= "Vector3" then
		return nil
	end
	local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
	if not Root then
		return AimPosition
	end
	local Offset = AimPosition - Root.Position
	local Max = CombatService.Settings.MaxAimDistance
	if Offset.Magnitude > Max then
		return Root.Position + Offset.Unit * Max
	end
	return AimPosition
end

----------------------------------------------------------------------
-- HANDLERS
----------------------------------------------------------------------

local function OnWeaponAttack(Player: Player, Button: any, AimPosition: any, WeaponName: any)
	if Button ~= "MB1" and Button ~= "MB2" then
		Reject(Player, "bad button")
		return
	end

	local Stats, PlayerLoadout, Reason = GetCombatState(Player)
	if not Stats then
		WeaponAttack:FireClient(Player, Button, false, 0)
		Reject(Player, Reason)
		return
	end

	-- The client names the weapon it thinks it is firing. If that is
	-- not the one equipped, the request is dropped rather than moved
	-- to the equipped one. (A swap and a click sent together arrive in
	-- order, so a fast swap then click still matches.)
	local Equipped = PlayerLoadout:GetEquippedWeapon()
	if type(WeaponName) == "string" and WeaponName ~= PlayerLoadout:GetEquippedWeaponName() then
		WeaponAttack:FireClient(Player, Button, false, 0)
		Reject(Player, "attack with unequipped weapon " .. WeaponName)
		-- The client has the wrong weapon out (a swap it sent was
		-- dropped), so it gets the real loadout back.
		PlayerLoadout:Send()
		return
	end
	if not Equipped then
		WeaponAttack:FireClient(Player, Button, false, 0)
		Reject(Player, "no weapon")
		return
	end

	local Ok, Result = Equipped:Attack(Button, ClampAim(Player, AimPosition))
	if not Ok then
		WeaponAttack:FireClient(Player, Button, false, Equipped:GetCooldownRemaining(Button))
		-- A cooldown miss is normal on a laggy connection, so it does
		-- not count towards a flag.
		if Result ~= "on cooldown" then
			Reject(Player, tostring(Result))
		end
		return
	end

	Accept(Player)
	WeaponAttack:FireClient(Player, Button, true, Result)
end

local function OnLoadoutSwap(Player: Player, Kind: any, Index: any)
	local Stats, PlayerLoadout, Reason = GetCombatState(Player)
	if not Stats then
		Reject(Player, Reason)
		return
	end
	if Index ~= nil and Index ~= 1 and Index ~= 2 then
		Reject(Player, "bad swap index")
		return
	end

	local Ok, Why
	if Kind == "Weapon" then
		Ok, Why = PlayerLoadout:SwapWeapon(Index)
	elseif Kind == "Ability" then
		Ok, Why = PlayerLoadout:SwapAbility(Index)
	else
		Reject(Player, "bad swap kind")
		return
	end

	if Ok then
		Accept(Player)
	elseif Why ~= "already equipped" then
		-- The client already shows the swap, so it is sent the real
		-- loadout to snap back to.
		PlayerLoadout:Send()
		if Why ~= "swap cooldown" then
			Reject(Player, tostring(Why))
		end
	end
end

local function OnAbilityUsed(Player: Player, AbilityName: any, AimPosition: any)
	local Stats, PlayerLoadout, Reason = GetCombatState(Player)
	if not Stats then
		AbilityUsed:FireClient(Player, AbilityName, false, 0, nil)
		Reject(Player, Reason)
		return
	end

	-- Same rule as weapons: the named ability has to be the equipped
	-- one, never redirected.
	local Equipped = PlayerLoadout:GetEquippedAbility()
	if type(AbilityName) == "string" and AbilityName ~= PlayerLoadout:GetEquippedAbilityName() then
		AbilityUsed:FireClient(Player, AbilityName, false, 0, nil)
		Reject(Player, "use of unequipped ability " .. AbilityName)
		return
	end
	if not Equipped then
		AbilityUsed:FireClient(Player, AbilityName, false, 0, nil)
		Reject(Player, "no ability")
		return
	end

	local Ok, Result, ClientData = Equipped:Use(ClampAim(Player, AimPosition))
	if not Ok then
		AbilityUsed:FireClient(Player, Equipped.Name, false, Equipped:GetCooldownRemaining(), nil)
		-- Cooldown and energy misses are normal, the client only
		-- predicts them.
		if Result ~= "on cooldown" and Result ~= "not enough energy" and Result ~= "already active" then
			Reject(Player, tostring(Result))
		end
		return
	end

	Accept(Player)
	AbilityUsed:FireClient(Player, Equipped.Name, true, Result, ClientData)
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function CombatService.Init()
	local Settings = CombatService.Settings

	RemoteGuard.BindEvent(WeaponAttack, { Rate = Settings.AttackRate, Burst = Settings.AttackBurst }, OnWeaponAttack)
	RemoteGuard.BindEvent(LoadoutSwap, { Rate = Settings.SwapRate, Burst = Settings.SwapBurst }, OnLoadoutSwap)
	RemoteGuard.BindEvent(AbilityUsed, { Rate = Settings.AbilityRate, Burst = Settings.AbilityBurst }, OnAbilityUsed)

	game:GetService("Players").PlayerRemoving:Connect(function(Player)
		Rejections[Player] = nil
	end)
end

return CombatService
