--[[
	WeaponData

	Stats for the 4 weapons. Each weapon is one entry holding a display
	name, the model name to pull out of ServerStorage.Assets.Weapons, and
	two attack tables, MB1 and MB2, one for left click and one for right
	click.

	Each attack table holds its damage, range, cooldown, hitbox size or
	radius, how many projectiles it fires, the spread on those
	projectiles, the animation to play and the sound name to use.

	Every weapon has a job, so no one weapon is simply the best:
	  Sword    crowd control with real reach. MB1 Cleave is a huge arc
	           that shoves the crowd back and knocks enemy projectiles
	           back at whoever threw them. MB2 Crescent Cannon fires a
	           high powered blade of energy that tears through a whole
	           line of enemies and stuns them.
	  Pistol   precise single target damage at any range, with a
	           headshot bonus. MB2 fans the hammer for a burst.
	  RPG      ranged crowd control. MB1 is a rocket whose blast
	           staggers everything it catches (and rocket jumps you),
	           MB2 a barrage of three smaller rockets.
	  Shotgun  close range burst. MB1 a pellet blast, MB2 a slug whose
	           recoil launches the player, doubling as movement.

	All 4 exist in the game, but a player only brings 2 of them into a
	run and only has 1 of those out at a time, so this table is the full
	list to pick from rather than the player's loadout.
]]

--[[
	What connects to this

	Server.Game.Core.Loadout reads two entries per player, one for each
	weapon slot, and checks the names from the player's saved data are
	real entries in here.

	Server.Game.Combat.Weapons.WeaponBase reads the whole entry when a
	weapon object is created, then Sword, Pistol, RPG and Shotgun each
	read their own MB1 and MB2 tables for their attack behaviour.

	Server.Game.Combat.DamageService takes the base damage from here and
	then applies the damage multipliers from any active effects, so the
	number in this table is always the unmodified base.

	Server.Game.Combat.ProjectileService reads projectile count, speed
	and spread for the Pistol, RPG and Shotgun attacks.

	Client side, ClientGame.Controllers.CombatInput reads the cooldowns
	so it can sweep the HUD without waiting on the server, and
	ClientGame.UI.HUD reads the display names for both of the player's
	weapon slots.

	The lobby place reads the same list for its character creation
	screen, so the keys in here are what end up in the player's save.
	Renaming a weapon breaks every save that already picked it, so
	Server.Game.Core.Loadout has to cope with a name it does not
	recognise rather than erroring.

	Animation names are either real Animation instances under
	ReplicatedStorage.Assets.Animations or procedural stand ins in
	Game.Shared.CombatFX. Sound names must match a Sound somewhere under
	SoundService.Sounds, which CombatFX plays on the clients.

	The client cooldown here is only for showing the UI. The real check
	stays on the server in WeaponBase, otherwise an exploiter can just
	ignore it. Each of the player's two weapons keeps its own cooldowns
	while it is put away.
]]

-- Note on when changes take effect. Keybinds and Enabled are read live.
-- The attack numbers are read when a weapon object is built at the
-- start of a run, so those need the run restarting.

local WeaponData = {}

----------------------------------------------------------------------
-- KEYBINDS
----------------------------------------------------------------------

-- Movement already uses LeftShift, Q, C, V, X, M, F and LeftControl,
-- abilities use E and G, prompts use Z, and the number keys are the
-- Roblox Backpack (the shop items), so the weapon keys stay clear of
-- those. Check ReplicatedStorage.Modules.Shared.MovementSettings before
-- changing these so two systems do not fight over one key.
WeaponData.Keybinds = {
	Keyboard = {
		MB1 = Enum.UserInputType.MouseButton1,
		MB2 = Enum.UserInputType.MouseButton2,
		-- Swaps to the other weapon.
		SwapWeapon = Enum.KeyCode.R,
	},

	-- MovementSettings puts Jump on ButtonR2, so attacks are on the
	-- bumpers.
	Gamepad = {
		MB1 = Enum.KeyCode.ButtonR1,
		MB2 = Enum.KeyCode.ButtonL1,
		SwapWeapon = Enum.KeyCode.DPadUp,
	},
}

----------------------------------------------------------------------
-- HOTBAR
----------------------------------------------------------------------

-- Frame names the HUD's cooldown panel uses for the two weapon slots.
WeaponData.Hotbar = {
	Slot1 = "WeaponSlot1",
	Slot2 = "WeaponSlot2",
	MB1 = "WeaponMB1",
	MB2 = "WeaponMB2",
}

----------------------------------------------------------------------
-- SHARED
----------------------------------------------------------------------

-- Rules that apply to every weapon unless its own entry overrides them.
WeaponData.Shared = {
	-- true lets the player hold the button to keep attacking at the
	-- cooldown rate. false needs a click per attack. Left click holds,
	-- right click is one attack per click.
	HoldToAttack = { MB1 = true, MB2 = false },
	-- Attacks can be started while sliding, wall running and so on.
	AllowWhileMoving = true,
	-- The icon shown for any weapon or ability without its own Icon.
	PlaceholderIcon = "rbxassetid://6937742258",
	-- Weapons never cost energy in the design, but the knob is here.
	DefaultEnergyCost = 0,
}

----------------------------------------------------------------------
-- WEAPONS
----------------------------------------------------------------------

-- Every attack table has these no matter what kind it is:
--   Name          shown on the hotbar tooltip
--   Kind          "Melee"      a wide arc in front of the player
--                 "Projectile" something that travels and can be dodged
--                 "Hitscan"    instant ray to the cursor, no travel
--   Damage        base damage per hit, before any multipliers
--   Cooldown      seconds before this attack can be used again. With
--                 Charges set, this is the recharge after the last
--                 charge is spent
--   Charges       nil or 1 is one use per cooldown
--   ChargeInterval  shortest gap between two charges of a burst
--   WindUp        seconds between the click and the hit landing, so
--                 the animation gets to play. 0 is instant.
--   MaxTargets    how many enemies one attack can hit. math.huge is
--                 everyone in reach
--   Knockback     studs per second pushed away from the player. 0 is
--                 none. Negative pulls towards the player
--   CritMultiplier  nil, or the damage multiplier for hitting an
--                 enemy's Head part (a headshot)
--   Animation     procedural stand in in CombatFX, or an Animation
--   Sound         played on every client when the attack fires
--   HitSound      played for the attacker on each enemy hit
--   StatusEffect  nil, or { Name, Duration, Amount } to apply on hit
--
-- Melee adds:  Range, Arc (degrees of the cone in front), Parry
-- Hitscan adds: Range, Radius (thickness of the shot)
-- Projectile adds a Projectile table:
--   Count         how many are fired at once
--   Spread        total cone angle in degrees they are spread over
--   Speed         studs per second
--   Lifetime      seconds before it disappears
--   Gravity       studs per second squared pulling it down. 0 flies
--                 straight
--   ModelName     look from CombatFX.Settings.ProjectileVisuals
--   Pierce        how many enemies it passes through before stopping.
--                 0 stops on the first
--   Radius        hit radius in studs, bigger than the visible
--                 projectile so near misses still land. 0 is a thin ray
--   Explosion     nil, or { Radius, Falloff, Stun } where Falloff is the
--                 damage fraction at the edge of the radius and Stun is
--                 seconds of stagger on everything caught

WeaponData.Weapons = {

	-- Crowd control with reach. MB1 cleaves a huge arc, shoves the
	-- crowd back and parries projectiles. MB2 fires a high powered
	-- crescent that pierces a whole line of enemies and stuns them.
	Sword = {
		Enabled = true,
		-- Shown in its HUD slot.
		Emoji = "",
		DisplayName = "Sword",
		Description = "Cleave a huge arc and knock projectiles back. Fire a crescent that tears through a whole line.",
		ModelName = "Sword",
		Icon = "rbxassetid://856575323",
		-- Which hand the model welds to, and the offset of the Handle
		-- from the hand's grip attachment. The sword model points up
		-- along +Y, so it is turned to point forward out of the fist.
		Grip = { Hand = "Right", Offset = CFrame.Angles(math.rad(-90), 0, 0) },

		MB1 = {
			Name = "Cleave",
			Kind = "Melee",
			Damage = 34,
			Cooldown = 0.34,
			WindUp = 0.05,
			MaxTargets = math.huge,
			-- Pushes the crowd back so it cannot swarm the player.
			Knockback = 28,
			Range = 20,
			-- Degrees of the cone in front of the player that is hit.
			Arc = 180,
			-- Every slash knocks enemy projectiles in its arc back the
			-- way they came, as the player's own, hitting harder.
			Parry = {
				Enabled = true,
				-- Studs out from the player a projectile can be caught.
				Range = 21,
				DamageMultiplier = 2,
				SpeedMultiplier = 1.4,
			},
			Animation = "Sword_Cleave",
			Sound = "SwordSwing",
			HitSound = "SwordHit",
			StatusEffect = nil,
		},

		MB2 = {
			Name = "Crescent Cannon",
			Kind = "Projectile",
			Damage = 90,
			Cooldown = 3,
			-- A short wind up for the big swing it is fired from.
			WindUp = 0.12,
			MaxTargets = math.huge,
			Knockback = 55,
			Projectile = {
				Count = 1,
				Spread = 0,
				Speed = 240,
				-- About 210 studs of reach.
				Lifetime = 0.9,
				Gravity = 0,
				ModelName = "SwordCrescent",
				-- A huge hit radius to match the huge crescent.
				Radius = 6,
				-- It passes through every enemy it meets.
				Pierce = 99,
				Explosion = nil,
			},
			Animation = "Sword_Crescent",
			Sound = "SwordSwingHeavy",
			HitSound = "SwordHit",
			-- Everything it cuts through is stunned for a moment.
			StatusEffect = { Name = "Stun", Duration = 0.7 },
		},
	},

	-- Precision at any range. MB1 is a fast accurate shot you can hold
	-- down, MB2 fans the hammer for six quick, less accurate shots.
	-- Headshots do extra damage.
	Pistol = {
		Enabled = true,
		Emoji = "",
		DisplayName = "Pistol",
		Description = "Fast accurate shots with headshot bonus damage, or fan the hammer for a burst of six.",
		ModelName = "Pistol",
		Icon = "rbxassetid://7535975825",
		Grip = { Hand = "Right", Offset = CFrame.new(0, 0, 0) },

		MB1 = {
			Name = "Quick Shot",
			Kind = "Projectile",
			Damage = 14,
			Cooldown = 0.13,
			WindUp = 0,
			MaxTargets = 1,
			Knockback = 0,
			CritMultiplier = 1.75,
			Projectile = {
				Count = 1,
				Spread = 0,
				Speed = 380,
				Lifetime = 1.2,
				Gravity = 0,
				ModelName = "Bullet",
				-- Hit radius in studs. Bigger than the bullet you see,
				-- so shots that look like they hit do hit.
				Radius = 1.2,
				Pierce = 0,
				Explosion = nil,
			},
			Animation = "Pistol_Shoot",
			Sound = "PistolShot",
			HitSound = "BulletHit",
			StatusEffect = nil,
		},

		MB2 = {
			Name = "Fan the Hammer",
			Kind = "Projectile",
			Damage = 11,
			Cooldown = 1.5,
			WindUp = 0,
			MaxTargets = 1,
			Knockback = 4,
			CritMultiplier = 1.3,
			-- Shots fired one after another, ShotInterval seconds apart,
			-- each with up to Projectile.Spread degrees of random spread.
			Shots = 6,
			ShotInterval = 0.07,
			Projectile = {
				Count = 1,
				Spread = 7,
				Speed = 360,
				Lifetime = 1,
				Gravity = 0,
				ModelName = "Bullet",
				Radius = 1.3,
				Pierce = 0,
				Explosion = nil,
			},
			Animation = "Pistol_Fan",
			Sound = "PistolFan",
			HitSound = "BulletHit",
			StatusEffect = nil,
		},
	},

	-- Ranged crowd control. MB1 is one big rocket whose blast staggers
	-- a whole group, MB2 a barrage of three smaller ones.
	RPG = {
		Enabled = true,
		Emoji = "",
		DisplayName = "RPG",
		Description = "Rockets that blow up and stagger a crowd (and launch you if you're close), or a barrage of three.",
		ModelName = "RPG",
		Icon = "rbxassetid://103850386355908",
		Grip = { Hand = "Right", Offset = CFrame.new(0, 0, 0) },

		MB1 = {
			Name = "Rocket",
			Kind = "Projectile",
			Damage = 80,
			Cooldown = 3.6,
			WindUp = 0.12,
			MaxTargets = math.huge,
			Knockback = 40,
			-- Fraction of the rocket damage the player takes if they
			-- are inside their own explosion. 0 turns it off, and it
			-- is off so rocket jumping is a tool rather than a trap.
			SelfDamage = 0,
			-- true throws the player who fired it away from their own
			-- explosion. The launch speed is in CombatFX.Settings.
			RocketJump = true,
			Projectile = {
				Count = 1,
				Spread = 0,
				Speed = 140,
				Lifetime = 4,
				Gravity = 0,
				ModelName = "Rocket",
				Radius = 2,
				Pierce = 0,
				-- Stun is the stagger: every enemy caught in the blast
				-- stops for this long. This is what makes the RPG crowd
				-- control rather than just damage.
				Explosion = { Radius = 22, Falloff = 0.4, Stun = 0.8 },
			},
			Animation = "RPG_Fire",
			Sound = "RocketLaunch",
			HitSound = "Explosion",
			StatusEffect = nil,
		},

		MB2 = {
			Name = "Rocket Barrage",
			Kind = "Projectile",
			Damage = 50,
			Cooldown = 8,
			WindUp = 0.15,
			MaxTargets = math.huge,
			Knockback = 30,
			SelfDamage = 0,
			RocketJump = true,
			Projectile = {
				Count = 3,
				Spread = 18,
				Speed = 140,
				Lifetime = 4,
				Gravity = 0,
				ModelName = "Rocket",
				Radius = 2,
				Pierce = 0,
				Explosion = { Radius = 16, Falloff = 0.4, Stun = 0.5 },
			},
			Animation = "RPG_Fire",
			Sound = "RocketLaunch",
			HitSound = "Explosion",
			StatusEffect = nil,
		},
	},

	-- Close range burst. MB1 is the pellet blast that can hit a whole
	-- group, MB2 a slug whose recoil throws you backwards, for picking
	-- off a Bob or escaping.
	Shotgun = {
		Enabled = true,
		Emoji = "",
		DisplayName = "Shotgun",
		Description = "A wide close range blast, or a slug whose recoil launches you. Slug headshots hit extra hard.",
		ModelName = "Shotgun",
		Icon = "rbxassetid://12875586772",
		Grip = { Hand = "Right", Offset = CFrame.new(0, 0, 0) },

		MB1 = {
			Name = "Blast",
			Kind = "Projectile",
			Damage = 9,
			Cooldown = 0.7,
			WindUp = 0,
			MaxTargets = math.huge,
			Knockback = 14,
			Projectile = {
				Count = 8,
				Spread = 20,
				Speed = 260,
				Radius = 1.3,
				-- Short life is what keeps it to close range, about 52
				-- studs.
				Lifetime = 0.2,
				Gravity = 0,
				ModelName = "Pellet",
				Pierce = 0,
				Explosion = nil,
			},
			Animation = "Shotgun_Fire",
			Sound = "ShotgunFire",
			HitSound = "BulletHit",
			StatusEffect = nil,
		},

		MB2 = {
			Name = "Recoil Slug",
			Kind = "Hitscan",
			Damage = 60,
			Cooldown = 2.2,
			-- Thickness of the shot in studs, so it does not need a
			-- pixel perfect aim.
			Radius = 1.5,
			WindUp = 0,
			MaxTargets = 1,
			Knockback = 35,
			CritMultiplier = 1.5,
			Range = 80,
			-- Studs per second the shooter is thrown backwards, away
			-- from where they aimed, and how much of that is upward.
			-- Applied by the shooter's own client. 0 turns it off.
			SelfLaunch = 75,
			SelfLaunchUp = 0.35,
			SelfLaunchTime = 0.18,
			Animation = "Shotgun_Burst",
			Sound = "ShotgunSlug",
			HitSound = "BulletHit",
			StatusEffect = nil,
		},
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks a weapon up by name and warns rather than erroring if the name
-- is wrong or the weapon is switched off, so a stale save does not
-- break the run. Loadout decides what to fall back to.
function WeaponData.Get(WeaponName: string)
	local Weapon = WeaponData.Weapons[WeaponName]
	if not Weapon then
		warn("[WeaponData] no weapon called " .. tostring(WeaponName))
		return nil
	end
	if not Weapon.Enabled then
		warn("[WeaponData] weapon " .. WeaponName .. " is disabled")
		return nil
	end
	return Weapon
end

-- Returns an attack table for a weapon and a button ("MB1" or "MB2").
function WeaponData.GetAttack(WeaponName: string, Button: string)
	local Weapon = WeaponData.Get(WeaponName)
	if not Weapon then
		return nil
	end
	local Attack = Weapon[Button]
	if not Attack then
		warn("[WeaponData] " .. WeaponName .. " has no attack called " .. tostring(Button))
	end
	return Attack
end

-- The names the character creation screen should offer, in a fixed
-- order so the buttons do not shuffle between sessions.
function WeaponData.GetEnabledNames(): { string }
	local Names = {}
	for _, Name in ipairs({ "Sword", "Pistol", "RPG", "Shotgun" }) do
		local Weapon = WeaponData.Weapons[Name]
		if Weapon and Weapon.Enabled then
			table.insert(Names, Name)
		end
	end
	return Names
end

return WeaponData
