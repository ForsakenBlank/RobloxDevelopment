--[[
	EnemyData

	Base stats for the 5 normal enemy types and the boss, before any
	scaling is applied. Each entry holds health, walk speed, damage,
	attack range, attack cooldown, how far it can see a player, how much
	money it drops on death, and the name of the model to clone out of
	ServerStorage.Assets.Enemies.

	Noob is the basic one that runs up and swings, lunging the last few
	studs so it cannot be kited by walking backwards. Bob is slow with a
	lot of health, heavy melee damage and a thrown rock. Necromancer
	hangs back, fires bolts, stuns you if you get close and summons
	Noobs. Dasher is fast and fragile and charges in a straight line
	(shown by a red line on the floor first). Bomber runs at you and
	blows itself up, but if it is killed first its bomb goes off on the
	other enemies instead. The Boss has an attack for each range band, a
	charge, and an enraged phase.
]]

--[[
	What connects to this

	Server.Game.Enemies.EnemyBase reads an entry when it builds an enemy,
	but it must pass the health and damage through
	Game.Shared.StatFormulas first so the player count and difficulty
	scaling gets applied. The raw number in this table is never used
	directly for a spawned enemy.

	Server.Game.Enemies.EnemyAI runs every enemy's movement and attacks
	from these numbers. Server.Game.Enemies.Types holds the enemies that
	do something special (Bob, Necromancer, Bomber, Boss).

	Server.Game.Enemies.EnemySpawner reads the model name so it knows
	what to clone from ServerStorage.Assets.Enemies.

	Server.Game.Combat.DamageService reads the money reward on a kill and
	then applies the difficulty money multiplier.

	Client side, ClientGame.Controllers.EnemyAnimator reads DeathColour
	and the sound names for the hit flash and death effects, and
	ClientGame.Controllers.BossBarController gets the scaled boss health
	from the BossHealthChanged remote rather than reading this table.

	The keys in this table are the same strings used in
	Game.Data.WaveData and in Server.Game.Enemies.EnemyRegistry. If a
	name is changed it has to be changed in all three.
]]

-- Note on when changes take effect. An entry is read when an enemy is
-- spawned, so a change applies to the next wave without a restart.
-- Enemies already alive keep what they spawned with.

local EnemyData = {}

----------------------------------------------------------------------
-- SHARED
----------------------------------------------------------------------

-- Rules that apply to every enemy unless its own entry overrides.
EnemyData.Shared = {
	-- How often the AI picks a target and decides what to do.
	ThinkRate = 0.15,
	-- An enemy with no player in DetectRange does this: "Idle" stands
	-- still, "Wander" walks to random nearby points, "Hunt" heads for
	-- the nearest player anyway.
	NoTargetBehaviour = "Hunt",
	-- Seconds the body stays after death before it is removed.
	DespawnTime = 2.5,
	-- Being hit pulls the enemy onto the attacker even if someone else
	-- is closer.
	AggroOnHit = true,
	-- Seconds an enemy stays locked onto the player that hit it.
	AggroDuration = 3,
	-- Enemies use PathfindingService rather than walking straight at
	-- the target. false is cheaper but gets stuck on corners.
	UsePathfinding = true,
	-- Seconds between path recalculations while chasing.
	RepathRate = 0.5,
	-- Studs from the target counted as "arrived", so they do not shove
	-- into the player.
	StopDistance = 3,
	-- Multiplier on how long enemies stay stunned. 1 is the full stun.
	StunDurationMultiplier = 1,
	-- Show a health bar over every enemy. The boss has its own bar.
	ShowHealthBar = true,
	-- An enemy further than this from its target runs faster, by
	-- SprintMultiplier, so a player cannot just outrun a room. An
	-- entry can set its own SprintMultiplier (1 turns it off).
	SprintDistance = 30,
	SprintMultiplier = 1.35,
	-- In multiplayer each other enemy already chasing a player makes
	-- that player count as this many studs further away, so a crowd
	-- spreads over the team instead of all piling on one person.
	CrowdPenalty = 5,
}

----------------------------------------------------------------------
-- ENEMIES
----------------------------------------------------------------------

-- Every enemy has these:
--   Enabled        false makes the spawner skip it and warn
--   DisplayName    shown on the health bar
--   ModelName      model in ServerStorage.Assets.Enemies
--   Health         base max health, before scaling
--   WalkSpeed      studs per second
--   DetectRange    studs it can notice a player from
--   LoseRange      studs past which it gives up on its target
--   MoneyReward    base money on death, before multipliers
--   IsBoss         true routes it to the boss bar and blocks Stun if
--                  StatusEffectData says so
--   DirectChaseOnly  true never pathfinds, it always walks straight
--   DeathColour    the colour it dissolves into when it dies
--   Sounds         Hurt, Death sound names under SoundService.Sounds
--   Attacks        one table per attack, see below
--
-- Every attack table has:
--   Damage         base damage, before scaling and multipliers
--   Range          studs the target has to be within to use it
--   MinRange       studs the target has to be further than, for
--                  ranged attacks so they are not used point blank
--   Cooldown       seconds before this attack can be used again
--   WindUp         seconds between choosing the attack and it landing,
--                  which is the window to dodge it
--   Priority       when more than one attack is in range the highest
--                  number wins
--   Sound          played when the attack lands
--   StatusEffect   nil, or { Name, Duration } applied to the player
--   Knockback      studs per second the player is pushed
-- and one of these to decide what kind of attack it is:
--   (nothing)      melee: a box in front of the enemy. Lunge =
--                  { Speed, Time } makes it jump forward as it swings
--   Radius         area: hits every player in the sphere. AtTarget
--                  true centres it under where the target stood when
--                  the wind up began, with a red circle as the tell
--   Projectile     ranged: { Speed, ModelName, Gravity, Radius,
--                  Count, Spread }. Radius is the hit radius in studs
--   Charge         a dash in a straight line, shown by a red line on
--                  the floor during the wind up: { Speed, Distance,
--                  Width }. Everyone the dash passes through is hit
--   Explode        blows the enemy up: { Radius, Falloff }. Only the
--                  Bomber uses it, see Types.Bomber
--   Rain           meteors on every player in range: { PerPlayer,
--                  Spread, Radius, Delay, Stagger }, each shown by a
--                  red circle first
--   Shockwave      rings that spread across the floor from the enemy
--                  and hit anyone on the ground where they pass:
--                  { Speed, MaxRadius, Width, Height, Rings, RingGap }
-- A Projectile table can also have Homing = { TurnRate, Duration }, so
-- the projectile curves after its target (radians a second).
--   SummonType     spawns more enemies, see Types.Necromancer

EnemyData.Enemies = {

	-- The basic one. Runs up, lunges the last few studs and hits.
	Noob = {
		Enabled = true,
		DisplayName = "Noob",
		ModelName = "Noob",
		Health = 50,
		WalkSpeed = 21,
		DetectRange = 90,
		LoseRange = 160,
		MoneyReward = 10,
		IsBoss = false,
		DeathColour = Color3.fromRGB(255, 220, 90),
		Sounds = { Hurt = "HitFlesh", Death = "NoobDeath" },

		Attacks = {
			Melee = {
				Damage = 8,
				Range = 6,
				MinRange = 0,
				Cooldown = 1.1,
				WindUp = 0.32,
				Priority = 1,
				Sound = "EnemySwing",
				StatusEffect = nil,
				Knockback = 12,
				-- The step forward on the swing.
				Lunge = { Speed = 38, Time = 0.14 },
			},
		},
	},

	-- The juggernaut. Slow, lots of health, hits hard, and throws a
	-- rock from range so standing back is not safe.
	Bob = {
		Enabled = true,
		DisplayName = "Bob",
		ModelName = "Bob",
		Health = 260,
		WalkSpeed = 14,
		SprintMultiplier = 1.5,
		DetectRange = 90,
		LoseRange = 180,
		MoneyReward = 35,
		IsBoss = false,
		DeathColour = Color3.fromRGB(150, 110, 70),
		Sounds = { Hurt = "MetalHit", Death = "EnemyGrowl" },

		Attacks = {
			Melee = {
				Damage = 20,
				Range = 8,
				MinRange = 0,
				Cooldown = 2.2,
				WindUp = 0.55,
				Priority = 2,
				Sound = "SlamBoom",
				StatusEffect = nil,
				Knockback = 45,
				Lunge = { Speed = 30, Time = 0.2 },
			},
			Ranged = {
				Damage = 12,
				Range = 70,
				MinRange = 12,
				Cooldown = 3.2,
				WindUp = 0.65,
				Priority = 1,
				Sound = "EnemyThrow",
				StatusEffect = nil,
				Knockback = 18,
				Projectile = { Speed = 150, ModelName = "Rock", Gravity = 30, Radius = 2.4 },
			},
		},
	},

	-- Keeps its distance and strafes, fires bolts, stuns you if you get
	-- close, and summons Noobs to make the room messy.
	Necromancer = {
		Enabled = true,
		DisplayName = "Necromancer",
		ModelName = "Necromancer",
		Health = 120,
		WalkSpeed = 17,
		SprintMultiplier = 1.2,
		DetectRange = 100,
		LoseRange = 180,
		MoneyReward = 50,
		IsBoss = false,
		DeathColour = Color3.fromRGB(170, 80, 255),
		Sounds = { Hurt = "HitFlesh", Death = "EnemyDeath" },

		-- It tries to stay this far from its target rather than walking
		-- right up, and circles round them. 0 makes it behave like the
		-- others.
		PreferredDistance = 24,
		StrafeSpeed = 0.6,

		Attacks = {
			Melee = {
				Damage = 9,
				Range = 7,
				MinRange = 0,
				Cooldown = 2,
				WindUp = 0.35,
				Priority = 2,
				Sound = "MagicBolt",
				StatusEffect = { Name = "Stun", Duration = 1 },
				Knockback = 30,
			},
			-- Three purple bolts in a fan, so it is still a threat
			-- while it hangs back.
			Bolt = {
				Damage = 7,
				Range = 75,
				MinRange = 8,
				Cooldown = 2.4,
				WindUp = 0.45,
				Priority = 1,
				Sound = "MagicBolt",
				StatusEffect = nil,
				Knockback = 8,
				Projectile = { Speed = 115, ModelName = "NecroBolt", Gravity = 0, Radius = 1.8, Count = 3, Spread = 14 },
			},
			Summon = {
				-- Not a damage attack. Spawns SummonType next to the
				-- Necromancer, up to MaxAlive of its own summons at once.
				Damage = 0,
				Range = 60,
				MinRange = 0,
				Cooldown = 10,
				WindUp = 0.9,
				Priority = 3,
				Sound = "Summon",
				StatusEffect = nil,
				Knockback = 0,
				SummonType = "Noob",
				Count = 2,
				MaxAlive = 4,
				-- Summoned enemies drop this fraction of the normal
				-- reward, so summons are not a money farm.
				SummonRewardMultiplier = 0.5,
			},
		},
	},

	-- Fast and fragile. Circles in, then charges in a straight line
	-- through whoever is in the way. Keep moving sideways.
	Dasher = {
		Enabled = true,
		DisplayName = "Dasher",
		ModelName = "Dasher",
		Health = 40,
		WalkSpeed = 26,
		SprintMultiplier = 1.2,
		DetectRange = 110,
		LoseRange = 200,
		MoneyReward = 15,
		IsBoss = false,
		DeathColour = Color3.fromRGB(255, 60, 60),
		Sounds = { Hurt = "HitFlesh", Death = "EnemyDeath" },

		-- Hangs just outside charge range so it can line one up.
		PreferredDistance = 18,
		StrafeSpeed = 0.9,

		Attacks = {
			Charge = {
				Damage = 14,
				Range = 38,
				MinRange = 7,
				Cooldown = 2.6,
				WindUp = 0.5,
				Priority = 2,
				Sound = "DasherLunge",
				StatusEffect = nil,
				Knockback = 35,
				Charge = { Speed = 115, Distance = 44, Width = 5 },
			},
			Melee = {
				Damage = 6,
				Range = 5,
				MinRange = 0,
				Cooldown = 0.8,
				WindUp = 0.22,
				Priority = 1,
				Sound = "EnemySwing",
				StatusEffect = nil,
				Knockback = 10,
			},
		},
	},

	-- Runs straight at you and blows up. Shoot it first and its bomb
	-- goes off on the other enemies instead.
	Bomber = {
		Enabled = true,
		DisplayName = "Bomber",
		ModelName = "Bomber",
		Health = 35,
		WalkSpeed = 23,
		SprintMultiplier = 1.25,
		DetectRange = 110,
		LoseRange = 200,
		MoneyReward = 15,
		IsBoss = false,
		DeathColour = Color3.fromRGB(255, 140, 40),
		Sounds = { Hurt = "HitFlesh", Death = "Explosion" },

		Attacks = {
			Detonate = {
				Damage = 32,
				Range = 7,
				MinRange = 0,
				Cooldown = 99,
				-- The fuse: it flashes and beeps for this long before
				-- going off, which is the window to get away.
				WindUp = 0.75,
				Priority = 1,
				Sound = "Explosion",
				StatusEffect = nil,
				Knockback = 55,
				Explode = { Radius = 13, Falloff = 0.5 },
			},
		},
		-- When killed by a player it still explodes after this many
		-- seconds, hurting only enemies, with Damage times this.
		DeathExplosion = { Delay = 0.15, DamageMultiplier = 1.5 },
	},

	-- The last room, which is huge, so the boss fights at every range.
	-- Up close it cleaves, in the middle it slams and charges, and at
	-- range it rains meteors on every player, sends shockwave rings
	-- across the floor that have to be jumped, fires homing orbs and
	-- fans of bolts. Below half health it enrages and calls in help.
	Boss = {
		Enabled = true,
		DisplayName = "The Crimson Tyrant",
		ModelName = "Boss",
		Health = 2200,
		-- A giant (about 30 studs tall), so its steps cover ground fast.
		WalkSpeed = 24,
		SprintMultiplier = 1.4,
		DetectRange = 600,
		LoseRange = 900,
		MoneyReward = 300,
		IsBoss = true,
		-- It walks straight at its target instead of pathfinding, since
		-- the room is open and a path for something this size is rarely
		-- found.
		DirectChaseOnly = true,
		-- Seconds it stands still after every attack, a window to hit it
		-- back. Normal enemies use EnemyAI.Settings.AttackRecovery.
		AttackRecovery = 1.3,
		-- false: players pass through it. Something this big moving this
		-- fast flings anyone it touches, so its attacks do the hitting.
		CollideWithPlayers = false,
		DeathColour = Color3.fromRGB(255, 50, 50),
		Sounds = { Hurt = "MetalHit", Death = "BossRoar" },

		-- Below this fraction of health the boss speeds up, hits harder
		-- and calls in help. Enabled = false turns the phase off.
		Enrage = {
			Enabled = true,
			BelowHealthPercent = 0.5,
			SpeedMultiplier = 1.2,
			DamageMultiplier = 1.15,
			CooldownMultiplier = 0.8,
			-- The pause after each attack once enraged.
			AttackRecovery = 0.9,
			-- Enemies it summons the moment it enrages.
			Summon = { Type = "Dasher", Count = 3 },
		},

		Attacks = {
			Close = {
				Damage = 16,
				Range = 30,
				MinRange = 0,
				Cooldown = 2.2,
				WindUp = 0.55,
				Priority = 6,
				Sound = "SlamBoom",
				StatusEffect = nil,
				Knockback = 50,
				Lunge = { Speed = 55, Time = 0.25 },
			},
			Slam = {
				-- Ground slam. A red circle appears under the target
				-- for the wind up, then everyone inside Radius of it is
				-- hit, so it is dodged by getting out of the circle.
				AtTarget = true,
				Damage = 14,
				Range = 55,
				MinRange = 20,
				Cooldown = 4.5,
				WindUp = 1,
				Priority = 3,
				Sound = "StunSlam",
				StatusEffect = nil,
				Knockback = 50,
				Radius = 18,
			},
			Charge = {
				Damage = 18,
				Range = 120,
				MinRange = 30,
				Cooldown = 9,
				WindUp = 1,
				Priority = 4,
				Sound = "BossRoar",
				StatusEffect = nil,
				Knockback = 55,
				-- Width is wider than its body, so standing beside it
				-- is not safe.
				Charge = { Speed = 120, Distance = 120, Width = 26 },
			},
			Meteors = {
				-- Red circles appear on and around every player, and a
				-- moment later a meteor lands in each. Keep moving.
				Damage = 10,
				Range = 400,
				MinRange = 0,
				Cooldown = 9,
				WindUp = 0.6,
				Priority = 5,
				Sound = "MagicBolt",
				StatusEffect = { Name = "Fire", Duration = 2 },
				Knockback = 35,
				Rain = {
					-- Meteors per player: one right under them, the rest
					-- scattered round them within Spread studs.
					PerPlayer = 3,
					Spread = 26,
					Radius = 9,
					-- Seconds the circles show before the meteors land,
					-- and between each meteor landing.
					Delay = 1.5,
					Stagger = 0.12,
				},
			},
			Shockwave = {
				-- A ring of fire spreads out across the floor from the
				-- boss. Anyone on the ground where it passes is hit, so
				-- it is jumped over.
				Damage = 10,
				Range = 200,
				MinRange = 20,
				Cooldown = 8,
				WindUp = 0.8,
				Priority = 2,
				Sound = "SlamBoom",
				StatusEffect = nil,
				Knockback = 40,
				Shockwave = { Speed = 70, MaxRadius = 180, Width = 5, Height = 5, Rings = 2, RingGap = 1 },
			},
			Orbs = {
				-- Slow orbs that curve after their target.
				Damage = 8,
				Range = 300,
				MinRange = 25,
				Cooldown = 7,
				WindUp = 0.6,
				Priority = 1,
				Sound = "Summon",
				StatusEffect = nil,
				Knockback = 20,
				Projectile = {
					Speed = 70, ModelName = "BossOrb", Gravity = 0, Count = 3, Spread = 90, Radius = 5,
					Homing = { TurnRate = 1.5, Duration = 3 },
				},
			},
			Long = {
				-- A wide fan of fast bolts at the target.
				Damage = 7,
				Range = 260,
				MinRange = 30,
				Cooldown = 5.5,
				WindUp = 0.7,
				Priority = 1,
				Sound = "MagicBolt",
				StatusEffect = nil,
				Knockback = 12,
				Projectile = { Speed = 230, ModelName = "BossBolt", Gravity = 0, Count = 7, Spread = 50, Radius = 3.5 },
			},
		},
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks an enemy up by name and warns rather than erroring if the name
-- is wrong or the enemy is switched off, so a typo in WaveData skips
-- that enemy instead of stopping the wave.
function EnemyData.Get(EnemyName: string)
	local Enemy = EnemyData.Enemies[EnemyName]
	if not Enemy then
		warn("[EnemyData] no enemy called " .. tostring(EnemyName))
		return nil
	end
	if not Enemy.Enabled then
		warn("[EnemyData] enemy " .. EnemyName .. " is disabled")
		return nil
	end
	return Enemy
end

return EnemyData
