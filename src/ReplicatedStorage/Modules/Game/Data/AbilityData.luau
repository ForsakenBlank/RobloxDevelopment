--[[
	AbilityData

	Stats for the 4 abilities. Each entry holds the energy cost, cooldown,
	and the numbers that ability needs. Stun Slam has its damage, radius
	and stun duration. Teleport has its maximum distance and the strike
	it lands where it arrives. Rage has its damage multiplier, speed
	bonus, lifesteal, duration and a health cost that can never take the
	player below 1 health. Heal Burst has its instant heal amount, the
	radius it reaches teammates in (reviving any that are down), and the
	Regeneration duration it leaves behind.

	A player brings 2 abilities into a run and has 1 of them out at a
	time, the same as weapons: E uses the equipped one and G swaps to the
	other. The original design document only listed 3 abilities, which
	is the minimum the success criteria asks for, but with 2 being
	carried a 4th (Heal Burst) was added so the choice is not almost
	every ability in the game.

	Abilities are paid for with energy, which only comes back slowly
	(GameConfig.Player), so the costs here are what stop them being
	spammed. Every ability is meant to be worth its cost: Stun Slam and
	Rage for fighting a crowd, Teleport for getting in and out, Heal
	Burst for keeping the team alive.
]]

--[[
	What connects to this

	Server.Game.Core.Loadout reads two entries per player and checks the
	names from their saved data are real entries in here.

	Server.Game.Combat.Abilities.AbilityBase reads the energy cost and
	cooldown for the shared check that runs before any ability fires.
	StunSlam, Teleport, Rage and HealBurst each read their own numbers.

	Server.Game.Combat.EnergyService is given the cost by AbilityBase and
	does the actual subtract. The ability does not touch energy itself.

	Server.Game.Effects.StatusEffectService gets called by StunSlam for
	the stun, by Rage for the damage buff, and by HealBurst for the
	Regeneration it leaves behind, so the effect names used here have
	to exist in Game.Data.StatusEffectData.

	Client side, ClientGame.Controllers.AbilityInput reads the keybinds
	and the cooldowns to sweep the HUD, and dims an ability when the
	player's energy is below the cost. Both slots show on the HUD, with
	the one not equipped faded but still running its own cooldown.

	The lobby place reads the same list for character creation, so the
	keys here are what end up in the player's save.

	The energy check is repeated on the server in AbilityBase. The client
	check is only there so the player gets instant feedback.
]]

-- Note on when changes take effect. Keybinds and Enabled are read live.
-- The ability numbers are read when the ability object is built at the
-- start of a run, so those need the run restarting.

local AbilityData = {}

----------------------------------------------------------------------
-- KEYBINDS
----------------------------------------------------------------------

-- Movement already uses LeftShift, Q, C, V, X, M, F and LeftControl,
-- weapons use R, prompts use Z and the number keys are the Roblox
-- Backpack. Check MovementSettings before changing these.
AbilityData.Keybinds = {
	Keyboard = {
		-- Fires whichever ability is currently equipped.
		Use = Enum.KeyCode.E,
		-- Swaps to the other ability.
		SwapAbility = Enum.KeyCode.G,
	},
	Gamepad = {
		Use = Enum.KeyCode.ButtonB,
		SwapAbility = Enum.KeyCode.DPadLeft,
	},
}

----------------------------------------------------------------------
-- HOTBAR
----------------------------------------------------------------------

-- Frame names the HUD's cooldown panel uses for the two ability slots.
AbilityData.Hotbar = {
	Slot1 = "AbilitySlot1",
	Slot2 = "AbilitySlot2",
}

----------------------------------------------------------------------
-- SHARED
----------------------------------------------------------------------

-- Rules that apply to every ability unless its own entry overrides.
AbilityData.Shared = {
	-- Abilities can be used in the air, while sliding and so on. Set
	-- false to only allow them on the ground.
	AllowInAir = true,
	-- Using an ability cancels the attack that is winding up.
	CancelsAttack = true,
	-- Dim the HUD slot on the client when energy is below the cost.
	-- The real check is on the server either way.
	ShowUnaffordable = true,
}

----------------------------------------------------------------------
-- ABILITIES
----------------------------------------------------------------------

-- Every ability has these no matter what else it has:
--   Enabled       false removes it from the picker and from Get
--   DisplayName   shown on the HUD and the picker
--   Description   one line for the picker
--   Icon          image on the HUD slot. "" uses the placeholder
--   EnergyCost    taken by AbilityBase before the effect runs
--   Cooldown      seconds before it can be used again
--   CastTime      seconds between the key press and the effect. The
--                 energy is taken at the press, not at the effect
--   Animation     procedural stand in in CombatFX
--   Sound         played on every client when it fires
--   CameraShake   nil, or { Intensity, Duration } for the user
--
-- The rest of each entry is that ability's own numbers.
AbilityData.Abilities = {

	-- Drives the player straight down, and on landing damages and stuns
	-- every enemy in a radius.
	StunSlam = {
		Enabled = true,
		-- Shown filling its cooldown slot on the HUD.
		Emoji = "",
		DisplayName = "Stun Slam",
		Description = "Slam down and stun everything around where you land. Hits harder the higher you fall.",
		Icon = "rbxassetid://7057382865",
		EnergyCost = 35,
		Cooldown = 6,
		CastTime = 0,
		Animation = "StunSlam",
		Sound = "StunSlam",
		CameraShake = { Intensity = 0.6, Duration = 0.3 },

		-- Base damage to every enemy in the radius on landing.
		Damage = 40,
		Radius = 20,
		-- Seconds the enemies stay stunned. Goes through
		-- StatusEffectService as a Stun effect.
		StunDuration = 2.5,
		-- Downward speed in studs per second while slamming.
		SlamSpeed = 120,
		-- If used while stood on the ground the player first hops up
		-- by this many studs so the slam still reads as a slam. 0
		-- lands it instantly on the spot.
		GroundHopHeight = 8,
		-- Studs per second enemies get pushed away on landing.
		Knockback = 20,
		-- Damage falls to this fraction at the edge of the radius. 1 is
		-- full damage everywhere.
		Falloff = 0.5,
		-- Seconds the player is locked in the landing pose.
		LandingRecovery = 0.4,
		-- The higher the slam started from, the harder it lands. The
		-- fall is measured from the highest point reached to the
		-- landing. FreeHeight is ignored, so the hop on its own gives
		-- no bonus, then every stud above that adds DamagePerStud as a
		-- fraction, up to MaxBonus. 0.04 with MaxBonus 1.5 means a 45
		-- stud drop does 2.5x.
		HeightBonus = {
			Enabled = true,
			FreeHeight = 8,
			DamagePerStud = 0.04,
			MaxBonus = 1.5,
		},
	},

	-- Moves the player to where the cursor is pointing, up to a
	-- distance, and never through a shut gate.
	Teleport = {
		Enabled = true,
		-- Shown filling its cooldown slot on the HUD.
		Emoji = "",
		DisplayName = "Teleport",
		Description = "Blink to your cursor and strike everything where you land. Brief invulnerability on arrival.",
		Icon = "rbxassetid://138500272033904",
		EnergyCost = 15,
		Cooldown = 3.5,
		CastTime = 0,
		Animation = "Teleport",
		Sound = "Teleport",
		CameraShake = nil,

		-- Pressing the key shows a blue ghost of the character at the
		-- cursor instead of firing straight away. Clicking teleports
		-- there and starts the cooldown, pressing the key again puts
		-- the ghost away with nothing spent.
		Targeting = true,
		-- Ghost look.
		GhostColour = Color3.fromRGB(80, 160, 255),
		GhostBlockedColour = Color3.fromRGB(255, 80, 80),
		-- How see through the ghost body is, and the fill of the
		-- outline drawn over it (1 is no fill).
		GhostTransparency = 0.6,
		GhostFillTransparency = 0.75,
		-- Furthest the destination can be from the player. A cursor
		-- further away is clamped to this along the same direction.
		MaxDistance = 300,
		-- The destination has to be visible from the player, so you
		-- cannot teleport through a wall. false lets it go anywhere
		-- inside MaxDistance.
		RequireLineOfSight = true,
		-- The destination has to be inside the area the player is
		-- currently in, using the RoomZones part. Stops teleporting
		-- past a shut gate.
		StayInCurrentArea = true,
		-- Lifted above the hit point by this so the player does not
		-- clip into the floor.
		ArrivalHeightOffset = 3,
		-- true keeps whatever speed the player had. false zeroes it so
		-- they arrive still, which is what the design wants.
		KeepVelocity = false,
		-- Seconds of invulnerability on arrival. 0 is none.
		ArrivalInvulnerability = 0.6,
		-- The strike where the player lands: damage and knockback to
		-- every enemy within Radius of the arrival point. Damage 0
		-- turns it off.
		Strike = {
			Damage = 35,
			Radius = 11,
			Knockback = 40,
			Falloff = 0.6,
		},
		-- Seconds the anti cheat is told to expect the jump in
		-- position, through AntiCheat.Teleport.
		AntiCheatGrace = 1,
	},

	-- Buffs damage and speed for a time, paid for with energy and a
	-- slice of current health.
	Rage = {
		Enabled = true,
		-- Shown filling its cooldown slot on the HUD.
		Emoji = "",
		DisplayName = "Rage",
		Description = "Trade a little health for more damage and speed. Your hits heal you while it lasts.",
		Icon = "rbxassetid://96284078466719",
		EnergyCost = 40,
		Cooldown = 18,
		CastTime = 0.2,
		Animation = "Rage",
		Sound = "Rage",
		CameraShake = { Intensity = 0.3, Duration = 0.2 },

		-- Seconds the buff lasts.
		Duration = 10,
		-- Multiplier on all outgoing damage, applied through the
		-- Damage status effect so it shows on the HUD.
		DamageMultiplier = 1.5,
		-- Multiplier on walk speed for the duration. 1.25 is a quarter
		-- faster. Goes through PlayerStats so the anti cheat is told.
		SpeedMultiplier = 1.3,
		-- Multiplier on every weapon and ability cooldown started while
		-- raging. 0.6 means they recharge 40% faster.
		CooldownMultiplier = 0.6,
		-- Fraction of current health taken on use.
		HealthCostPercent = 0.1,
		-- Fraction of all damage dealt while raging that comes back as
		-- health, so the health cost is won back by fighting.
		Lifesteal = 0.25,
		-- The cost can never take the player below this.
		MinHealthAfterCost = 1,
		-- true lets Rage be used again while it is already active,
		-- refreshing the timer and paying the cost again. false makes
		-- the key do nothing until it wears off.
		AllowRefresh = false,
	},

	-- Heals the player and any teammate close by, then leaves
	-- Regeneration ticking on all of them.
	HealBurst = {
		Enabled = true,
		-- Shown filling its cooldown slot on the HUD.
		Emoji = "",
		DisplayName = "Heal Burst",
		Description = "Heal yourself and nearby teammates, then keep healing. Revives teammates who are down.",
		Icon = "rbxassetid://1032918680",
		EnergyCost = 45,
		Cooldown = 20,
		CastTime = 0.3,
		Animation = "HealBurst",
		Sound = "HealBurst",
		CameraShake = nil,

		-- Flat health given instantly to everyone it reaches. Clamped
		-- to max health by PlayerStats.
		HealAmount = 30,
		-- Teammates within this many studs of the player are healed
		-- too. 0 makes it self only.
		Radius = 25,
		-- Teammates who are down (spectating) inside the radius come
		-- back with this fraction of their max health. 0 turns it off.
		ReviveHealthPercent = 0.35,
		-- true means the player who used it is healed as well.
		IncludeSelf = true,
		-- The Regeneration effect left behind. Amount nil uses the
		-- default per tick from StatusEffectData.
		Regen = {
			Enabled = true,
			Duration = 5,
			AmountPerTick = nil,
		},
		-- true lets it be used at full health, which is mostly a way to
		-- give teammates Regeneration. false blocks it and refunds
		-- nothing, so the client should grey it out too.
		AllowAtFullHealth = true,
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks an ability up by name and warns rather than erroring if the
-- name is wrong or the ability is switched off, so a stale save does
-- not break the run. Loadout decides what to fall back to.
function AbilityData.Get(AbilityName: string)
	local Ability = AbilityData.Abilities[AbilityName]
	if not Ability then
		warn("[AbilityData] no ability called " .. tostring(AbilityName))
		return nil
	end
	if not Ability.Enabled then
		warn("[AbilityData] ability " .. AbilityName .. " is disabled")
		return nil
	end
	return Ability
end

-- The names the character creation screen should offer, in a fixed
-- order so the buttons do not shuffle between sessions.
function AbilityData.GetEnabledNames(): { string }
	local Names = {}
	for _, Name in ipairs({ "StunSlam", "Teleport", "Rage", "HealBurst" }) do
		local Ability = AbilityData.Abilities[Name]
		if Ability and Ability.Enabled then
			table.insert(Names, Name)
		end
	end
	return Names
end

return AbilityData
