-- The four cores. The numbers (stat values, milestone levels, colours)
-- are in Shared.CoreData; the keys must match it.
return {
	-- The tag on each milestone.
	Kinds = {
		PASSIVE = "PASSIVE",
		ULTIMATE = "ULTIMATE",
		CRITS = "CRITS",
		STAT = "STAT",
	},
	Ruby = {
		Name = "Ruby",
		Class = "Berserker",
		Focus = "Attack",
		Tagline = "Raw damage",
		Description = "High-risk, high-reward. Close-range attacker built around execution.",
		Stats = {
			Speed = "Speed",
			WeaponDamage = "Weapon damage",
			OverallDamage = "Overall damage",
			WeaponCooldown = "Weapon cooldown",
		},
		Milestones = {
			Crits = { Name = "Critical hits", Description = "Ruby can land critical hits from the start but Sapphire and Amethyst only unlock them at LV 8." },
			LowHealth = { Name = "Low HP Damage Scaling", Description = "The lower your health, the more damage you deal." },
			Ultimate = { Name = "Frenzy Surge", Description = "Unlocks your core ultimate ability!" },
			Bloodlust = { Name = "Bloodlust Stacks", Description = "Dealing damage builds stacks which gives more melee and move speed, but you take a little more damage,  the max stack increase with level." },
			Executioner = { Name = "Executioner", Description = "Bonus true damage against enemies below 25% health." },
			Cooldown = { Name = "Weapon cooldown -10%", Description = "Faster weapon cooldown." },
		},
		Ultimate = {
			Name = "Frenzy Surge",
			Description = "A 45 second damaging aura that drains nearby enemies. You get life steal on physical hits and every hit is a guaranteed critical. Howver, it drains stamina fast and ends stops when at 0 stamina.",
			Charge = "Charges while in combat and charges faster from kills.",
		},
		Aura = {
			Name = "Slaughter Aura",
			Description = "Nearby teammates get a damage bonus that scales with your Bloodlust. Howver, the range and bonus use each teammates own core level.",
		},
		Drawbacks = { "-20% max health", "No health regen in combat (15 s after atacking or being hit)", "Much longer cooldowns for abilities" },
	},
	Sapphire = {
		Name = "Sapphire",
		Class = "Arcanist",
		Focus = "Magic",
		Tagline = "Ability power",
		Description = "A more ranged, ability focused class with increased stamina.",
		Stats = {
			Energy = "Energy",
			MagicDamage = "Magic damage",
			AbilityCooldown = "Ability cooldown",
		},
		Milestones = {
			CastOverflow = { Name = "Cast Overflow", Description = "Small chance for an ability to cost no energy. Which scales with level, with a max of 10%." },
			Ultimate = { Name = "Arcane Overload", Description = "Unlocks your core ultimate!" },
			Crits = { Name = "Critical hits", Description = "Your attacks can turn to critical hits." },
			SpellWeaving = { Name = "Spell Weaving", Description = "Ability hits overheal you past max HP, up to double. However, overheal fades over time." },
			ShatterFreeze = { Name = "Shatter & Freeze", Description = "Ability hits apply Frostbite, which at max stacks enemies freeze and also take bonus magic damage." },
			Cooldown = { Name = "Ability cooldown -10%", Description = "A fast cooldown for abilities." },
		},
		Ultimate = {
			Name = "Arcane Overload",
			Description = "Resets all ability cooldowns and gives a 30 second icy aura that halves cooldowns. Each kill during this time adds a Sapphire Focus stack for +1 second and increased damage.",
			Charge = "Charges while in combat, faster when you use up energy.",
		},
		Aura = {
			Name = "Energy Resonance",
			Description = "Nearby teammates regen stamina faster. At core LV 10, all players also get +10% max energy and +10% magic damage.",
		},
		Drawbacks = { "+50% cooldowns to weapons", "Take 15% more damage from enemies", "-10% movement speed" },
	},
	Amethyst = {
		Name = "Amethyst",
		Class = "Weaponmaster",
		Focus = "Weapons",
		Tagline = "Weapon mastery",
		Description = "A weapons class, which focuses on weapons. (pretty straigh forward)",
		Favoured = "Fists",
		Stats = {
			Health = "Health",
			WeaponDamage = "Weapon damage",
			ParryDamage = "Parry damage",
			WeaponCooldown = "Weapon cooldown",
		},
		Milestones = {
			ComboMeter = { Name = "Combo Meter", Description = "Each hit in a row adds +2% attack speed, up to 20 hits (+40%). However, it resets if you are hit or stop for 3 seconds." },
			Ultimate = { Name = "Ascension", Description = "Unlocks your core ultimate. It cycles in with your abilities." },
			Crits = { Name = "Critical hits", Description = "Your attacks can turn to critical hits." },
			ParryFlow = { Name = "Parry Flow", Description = "A perfect parry refunds 50% of its stamina and makes your next attack a critical hit." },
			ParryDamage = { Name = "Parry damage +25%", Description = "Parries hit harder." },
			ArmorShredder = { Name = "Armor Shredder", Description = "10% chance to weaken an enemy: it takes 15% more damage from everything for 10 s." },
			Cooldown = { Name = "Weapon cooldown -15%", Description = "Weapons recover faster." },
		},
		Ultimate = {
			Name = "Ascension",
			Description = "A 60 second aura with +25% damage and a live damage counter. Parries instantly kill non-boss enemies. When it ends you get a damage buff based on your total damage dealt within the time, up to 3x for 60 seconds at 5,000+ damage, plus 0.1x per extra 1,000 damage.",
			Charge = "Charges from damaging enemies but takes longer to charge than other ultimates.",
		},
		Aura = {
			Name = "Tactical Stance",
			Description = "All teammates get 5% lower energy costs and +20% weapon damage.",
		},
		Drawbacks = { "-25% max stamina", "Abilities deal 20% less damage and have 10% longer cooldowns", "Natural regen is halved" },
	},
	Diamond = {
		Name = "Diamond",
		Class = "Guardian",
		Focus = "Tank / Heal",
		Tagline = "Healing and defence",
		Description = "A tank and healer class in one, absorb damage for your teammates.",
		Stats = {
			Health = "Health",
			Healing = "Healing",
			DamageTaken = "Damage taken",
		},
		Milestones = {
			Taunt = { Name = "Forcefield Taunt", Description = "Enemies near you are more likely to target you." },
			Ultimate = { Name = "Sanctuary Barrier", Description = "Unlocks your core ultimate!" },
			Lifeline = { Name = "Lifeline Link", Description = "Stay right next to a teammate for 3 seconds to link with them to heal them rapidly." },
			Reflective = { Name = "Reflective Coating", Description = "10% chance to reflect damage back to the enemy. Reflects 50% to 100% of the damage and scales with level." },
			DamageTaken = { Name = "Damage taken -10%", Description = "Take 10% less damage from enemies." },
		},
		Ultimate = {
			Name = "Sanctuary Barrier",
			Description = "Put down a 45 second massive bubble shield where you stand that heals teammates inside and anyone outside the bubble gets an extra +5 HP/s.",
			Charge = "Charges from taking more damage and healing other players (not yourself).",
		},
		Aura = {
			Name = "Prism Aegis",
			Description = "All players get +15% max health and 20% of damage taken by nearby teammates is redirected to you. Radius grows with level.",
		},
		Drawbacks = { "-25% damage from weapons and abilities", "+10% longer cooldowns for weapons and abilities" },
	},
}
