-- The Info tab in Settings: one page per topic, picked from the list on
-- the left. Each page has a Title and Blocks, shown top to bottom:
--
--   "Some text."                          a paragraph
--   { Heading = "STARS" }                 a heading
--   { Bullets = { "One", "Two" } }        a bullet list
--   { Title = "City Set", Icons = { "city_cap", "city_jacket" },
--     Text = "2 pieces: ..." }            a box with pictures (names from
--                                         Shared.UIIcons) and a line
--
-- Add, remove or reorder pages and blocks freely. {TimebuxMinutes} is
-- filled in from GameConfig.
return {
	Pages = {
		{
			Key = "Game",
			Tab = "THE GAME",
			Title = "WELCOME TO VELOCITY",
			Blocks = {
				"Fight your way through each map room by room, alone or in a squad of up to four, and take down the boss at the end.",
				{ Heading = "BEFORE A RUN" },
				{ Bullets = {
					"Pick a core: your class. It decides how you fight and what you bring to the team.",
					"Pick 2 weapons and 2 abilities on the Loadout screen.",
					"Wear armour and accessories for extra stats.",
					"Press PLAY, pick a map and a difficulty, and start alone or open a squad.",
				} },
				{ Heading = "LEVELS" },
				"Every run earns EXP and cash. Your player level unlocks weapons, abilities, gear and skins. Your core levels up on its own as you play with it.",
				{ Heading = "THE LOBBY" },
				{ Bullets = {
					"B opens and closes the menu, 1 to 6 press its buttons.",
					"Walk around with B, or stay in the menu.",
					"The cog next to SHOP opens these settings.",
					"Change any key on the CONTROLS tab. Your keys are saved and work in runs too.",
				} },
			},
		},
		{
			Key = "Cores",
			Tab = "CORES",
			Title = "CORES",
			Blocks = {
				"Your core is your class. There are four: Ruby, Sapphire, Amethyst and Diamond. Only one is active at a time.",
				{ Bullets = {
					"Ruby, the Berserker: raw damage up close, built around finishing enemies off.",
					"Sapphire, the Arcanist: ability power, area denial and freezing enemies.",
					"Amethyst, the Weaponmaster: weapons, combos and parrying.",
					"Diamond, the Guardian: tanking hits and healing the team.",
				} },
				{ Heading = "ENLIGHTENMENT" },
				"Playing with a core enlightens it. Enough Enlightenment levels it up, which raises its stat bonuses and unlocks milestones: passives, critical hits and more.",
				"At core level 5 you unlock its ultimate, which cycles in with your abilities. Ultimates charge while you're in combat, faster when you play the way the core wants.",
				{ Heading = "TEAM AURAS" },
				"Every core also gives the team an aura. A squad with all four cores covers each other's weaknesses.",
				{ Heading = "SWAPPING" },
				"Swap cores any time on the Core screen. The old core's bonuses switch off, but nothing is lost: swap back and its level and milestones are all still there.",
			},
		},
		{
			Key = "Equipment",
			Tab = "EQUIPMENT",
			Title = "EQUIPMENT",
			Blocks = {
				{ Title = "SLOTS", Icons = { "armour_helmet", "armour_chest", "armour_boots", "acc_charm" }, Text = "1 helmet, 1 chestplate and 1 pair of boots. Accessories: 1 slot to start, a 2nd at level 10, a 3rd at level 25, and 2 more with the +2 Accessory Slots gamepass." },
				"Armour is the main source of power. Accessories give small utility bonuses.",
				"Gear drops in runs. Every piece is its own item with its own rarity, stars and stats, so you can find the same piece more than once.",
				{ Heading = "LIMITS" },
				"Gear can help a lot, but it can't break the game:",
				{ Bullets = {
					"Armour adds about 15-20% defensive power at most.",
					"Accessories add about 5-8% at most.",
					"Cooldown reduction from gear is capped at 5%, and at 30% from everything together.",
					"Crit chance from gear is capped at 8%, and does nothing until your core can land crits.",
					"Gear health can never cancel out Ruby's -20% max health.",
					"The same stat can only be on 2 of your equipped accessories.",
					"Gear bonuses are added together, then multiplied with your core's bonuses.",
				} },
			},
		},
		{
			Key = "Rarity",
			Tab = "RARITY & STARS",
			Title = "RARITY & STARS",
			Blocks = {
				{ Heading = "RARITY" },
				"Every item has a rarity. Rarer items have stronger stats and more stat lines.",
				{ Bullets = {
					"Common (grey): x1.00 stats, 1 line",
					"Good (green): x1.15, 2 lines",
					"Rare (blue): x1.30, 2 lines",
					"Epic (purple): x1.50, 3 lines",
					"Legendary (gold): x1.75, 3 lines",
				} },
				"Accessories have fewer lines: Common to Rare get 1, Epic and Legendary get 2.",
				{ Title = "STARS", Icons = { "star", "star", "star", "star", "star" }, Text = "Every item rolls 1 to 5 stars when it drops or is bought. Stars never change." },
				"Stars make the numbers bigger, never change which stats roll:",
				{ Bullets = {
					"1 star: x1.00 (40% of drops)",
					"2 stars: x1.10 (30%)",
					"3 stars: x1.20 (18%)",
					"4 stars: x1.35 (9%)",
					"5 stars: x1.50 (3%)",
				} },
				"A stat's value is its base value x the rarity multiplier x the star multiplier, so a 5 star Legendary is the best roll there is.",
			},
		},
		{
			Key = "Stats",
			Tab = "GEAR STATS",
			Title = "GEAR STATS",
			Blocks = {
				"Each stat has its own rarity too, and every stat line shows its colour. Rarer stats are stronger and roll less often. The same stat can't roll twice on one item.",
				{ Heading = "COMMON" },
				{ Bullets = { "Max Health", "Health Regen (out of combat)", "Stamina Regen", "Coin Gain", "Pickup Range" } },
				{ Heading = "GOOD" },
				{ Bullets = { "Energy Regen", "Melee Resist", "Fire Resist", "Magic Resist", "Knockback Resist" } },
				{ Heading = "RARE" },
				{ Bullets = { "Damage Reduction", "Movement Speed", "Weapon Damage", "Ability Damage", "Cooldown Reduction (small, capped)" } },
				{ Heading = "EPIC" },
				{ Bullets = { "Crit Chance", "Crit Damage", "Parry Window (slightly longer parry timing)" } },
				{ Heading = "LEGENDARY" },
				"Only on Legendary items, and only 1 line:",
				{ Bullets = { "Tiny Lifesteal", "Revive Boost (revive teammates faster)", "Core Charge (your ultimate charges a little faster)" } },
			},
		},
		{
			Key = "Rerolls",
			Tab = "REROLLS",
			Title = "REROLLS & SCRAP",
			Blocks = {
				{ Title = "DISMANTLE", Icons = { "dismantle", "scrap" }, Text = "Break down gear you don't want for Scrap. Higher rarity and more stars give more." },
				{ Title = "REROLL", Icons = { "reroll" }, Text = "Spend Scrap and coins to chase better stats without starting over." },
				{ Bullets = {
					"Reroll One Stat: pick a line and reroll it. The cheapest.",
					"Reroll All Stats: rerolls every line. Costs more.",
					"Reroll Values Only: keeps the stats and rerolls the numbers a little. Cheap.",
				} },
				{ Heading = "RULES" },
				{ Bullets = {
					"Rarity and stars never change.",
					"A reroll never gives the same stat back on that line.",
					"Lock a stat (for extra Scrap) to keep it while rerolling the rest. Legendary items can lock 2.",
					"Each reroll on an item costs a bit more, up to 3x. Every item keeps its own count, so a fresh item starts cheap.",
					"An accessory's own stat (its first line) always stays; only its value can be rerolled.",
					"Rerolls only use Scrap and coins, never Timebux or Robux.",
				} },
			},
		},
		{
			Key = "Sets",
			Tab = "ARMOUR SETS",
			Title = "ARMOUR SETS",
			Blocks = {
				"Wear 2 or 3 pieces of a set for a bonus. Pieces can be any rarity, but the bonus goes by the lowest rarity you wear.",
				{ Title = "CITY SET", Icons = { "city_cap", "city_jacket", "city_sneakers" }, Text = "Map 1, light. 2 pieces: +2% stamina regen. 3 pieces: +3% movement speed and +5% pickup range." },
				{ Title = "STREET SET", Icons = { "street_hood", "street_hoodie", "street_boots" }, Text = "Map 1 rare drop, tougher. 2 pieces: +3% melee resist. 3 pieces: +4% knockback resist, -2% movement speed." },
				{ Title = "RETRO SET", Icons = { "retro_helmet", "retro_torso", "retro_boots" }, Text = "Map 2, classic bricks. 2 pieces: +3% max health. 3 pieces: +3% damage reduction and +5% knockback resist, -2% movement speed." },
				{ Title = "NOOB SET", Icons = { "noob_cap", "noob_shirt", "noob_shoes" }, Text = "Map 2 early drops. 2 pieces: +2% coin gain. 3 pieces: +1% weapon damage and +2% health regen." },
				{ Title = "GUEST SET", Icons = { "guest_mask", "guest_jacket", "guest_boots" }, Text = "Retroscity Impossible only. 2 pieces: +2% crit chance. 3 pieces: +3% damage reduction, +2% weapon damage and a small chance to ignore knockback." },
			},
		},
		{
			Key = "Accessories",
			Tab = "ACCESSORIES",
			Title = "ACCESSORIES",
			Blocks = {
				"Any accessory goes in any open slot. Types are face, head, neck, back, hand, pin and charm. You can own as many of a type as you like, but only wear one of each type at a time.",
				"Each accessory has its own stat. Epic and Legendary ones roll a second stat too.",
				{ Title = "CITY", Icons = { "city_delivery_bag", "city_courier_watch", "city_sunglasses", "city_lanyard", "city_wristband", "city_metro_card" }, Text = "Delivery Bag, Courier Watch, Sunglasses, ID Lanyard, Wristband, Metro Card." },
				{ Title = "RETRO", Icons = { "retro_cola", "retro_brick_badge", "retro_tix_coin", "retro_visor", "retro_tool_belt", "retro_obby_medal", "retro_cursor_pin", "retro_orange_shades", "retro_studs_chain", "retro_guest_pin" }, Text = "Classic Cola, Brick Badge, Tix Coin, Old School Visor, Builder Tool Belt, Obby Medal, Cursor Pin, Orange Shades, Studs Chain, Guest Pin." },
				{ Title = "CORE CHARMS", Icons = { "charm_ruby", "charm_sapphire", "charm_amethyst", "charm_diamond" }, Text = "A small stat, plus a tiny bonus while its core is active. Only 1 charm at a time." },
				{ Bullets = {
					"Ruby Charm: weapon damage, +1% bloodlust gain",
					"Sapphire Charm: energy regen, +1% ability damage",
					"Amethyst Charm: stamina regen, +1% parry damage",
					"Diamond Charm: max health, +1% healing",
				} },
				{ Heading = "MAP BONUSES" },
				{ Bullets = {
					"2 City accessories: +1% movement speed. 3: +2% coin gain.",
					"2 Retro accessories: +1% max health. 3: +1% crit chance.",
				} },
				{ Title = "COSMETICS", Icons = { "cos_party_hat", "cos_traffic_cone", "cos_bunny_ears", "cos_pizza_pin", "cos_paper_crown" }, Text = "They look great and have one small Common stat." },
			},
		},
		{
			Key = "Drops",
			Tab = "GETTING GEAR",
			Title = "GETTING GEAR",
			Blocks = {
				{ Bullets = {
					"Enemies: mostly Common and Good, sometimes Rare.",
					"Chests and map events: Good to Epic.",
					"Bosses: Rare to Legendary.",
					"The shop: Common and Good, with random stars.",
				} },
				"Each map has its own armour set, so new gear never makes old maps pointless.",
				{ Heading = "RETROSCITY" },
				{ Bullets = {
					"Easy: no Epic or Legendary drops.",
					"Normal and Hard: Epic can drop.",
					"Impossible: the best Legendary odds, and the only place the Retro set drops at 5 stars more often.",
				} },
				"Old maps stay a challenge: the next map's enemies are balanced around the last map's full set, and hard modes scale enemy health and damage.",
			},
		},
		{
			Key = "Timebux",
			Tab = "TIMEBUX",
			Title = "TIMEBUX & GAMEPASSES",
			Blocks = {
				{ Title = "TIMEBUX", Icons = { "timebux" }, Text = "You earn 1 Timebux for every {TimebuxMinutes} minutes in game. 1 Timebux = 1 Robux, so any gamepass can be bought with either." },
				{ Title = "GAMEPASSES", Icons = { "gp_slots", "gp_exp", "gp_customise", "gp_vip" }, Text = "In the Shop, on the GAMEPASSES tab." },
				{ Bullets = {
					"+2 Accessory Slots: two more accessory slots.",
					"2x EXP: double EXP.",
					"Customise!: change your character's face and body colours.",
					"VIP: 1.25x EXP and coins, the 1x1x1x1 skin, a golden tag above your head, and $750 plus 5 Timebux every day you log in.",
				} },
			},
		},
	},
}
