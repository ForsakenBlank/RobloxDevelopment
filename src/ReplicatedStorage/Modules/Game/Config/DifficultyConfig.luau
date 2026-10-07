--[[
	DifficultyConfig

	One entry per difficulty, keyed by the difficulty name string. Each
	entry holds the multipliers that difficulty changes: enemy health,
	enemy damage, money earned per kill and shop prices.

	Easy, Normal and Hard are all switched on. The lobby's picker sends
	the name, and every system reads its multiplier from here.
]]

--[[
	What connects to this

	The difficulty name is chosen in the lobby place and arrives here
	through teleport data. Server.Game.Core.TeleportDataReader pulls the
	raw string out, Server.Game.Core.RunSetup looks it up in this table,
	and the result is stored on Game.Shared.RunConfig.

	Reads the looked up entry:
	  Game.Shared.StatFormulas applies the health and damage multipliers.
	  Server.Game.Enemies.EnemyBase for the stats it spawns an enemy with.
	  Server.Game.Shop.ShopManager for the price multiplier.
	  Server.Game.Combat.DamageService for the money multiplier on a kill.

	Important: the key strings in this table have to match exactly what
	the lobby place sends. If the lookup misses, RunSetup must fall back
	to "Normal" rather than error, because a player joining the place
	directly instead of through the lobby will have no teleport data.
]]

local DifficultyConfig = {}

-- The one used when the lookup misses or nothing was sent.
DifficultyConfig.Default = "Normal"

----------------------------------------------------------------------
-- DIFFICULTIES
----------------------------------------------------------------------

-- Every entry has the same shape:
--   Enabled            false hides it from the picker and makes Get
--                      fall back to the default
--   DisplayName        what the HUD and lobby show
--   Description        one line for the lobby picker
--   EnemyHealth        multiplier on every enemy's max health
--   EnemyDamage        multiplier on every enemy attack
--   Money              multiplier on every kill reward
--   ShopPrice          multiplier on every shop price
--   WaveDelay          multiplier on the delay between waves, so
--                      harder difficulties can send waves faster
--   PlayerRegen        multiplier on the player's energy regen
--   EnemyCount         multiplier on how many enemies each wave has
--                      (bosses are never doubled)
--   EnemySpeed         multiplier on enemy walk speed
--   EnemyWindUp        multiplier on enemy attack wind ups, lower is
--                      less time to dodge
--   EnemyCooldown      multiplier on enemy attack cooldowns
--   MeleeAttackers     how many enemies can swing at one player at once
--   Exp                multiplier on the EXP a run pays
DifficultyConfig.Difficulties = {
	Easy = {
		Enabled = true,
		DisplayName = "Easy",
		Description = "Fewer, weaker, slower enemies that give you more time to dodge. Good for learning a map.",
		EnemyHealth = 0.7,
		EnemyDamage = 0.6,
		Money = 1,
		ShopPrice = 0.8,
		WaveDelay = 1.3,
		PlayerRegen = 1.4,
		EnemyCount = 0.75,
		EnemySpeed = 0.9,
		EnemyWindUp = 1.25,
		EnemyCooldown = 1.2,
		MeleeAttackers = 1,
		Exp = 0.75,
	},
	Normal = {
		Enabled = true,
		DisplayName = "Normal",
		Description = "The game as designed. You will need to dodge.",
		EnemyHealth = 1.15,
		EnemyDamage = 1.2,
		Money = 1,
		ShopPrice = 1,
		WaveDelay = 0.9,
		PlayerRegen = 1,
		EnemyCount = 1.1,
		EnemySpeed = 1,
		EnemyWindUp = 1,
		EnemyCooldown = 0.95,
		MeleeAttackers = 2,
		Exp = 1,
	},
	-- meant to need good gear: base stats should not get through it
	Hard = {
		Enabled = true,
		DisplayName = "Hard",
		Description = "Far tougher, faster, angrier enemies in bigger waves. Bring your best gear.",
		EnemyHealth = 2.4,
		EnemyDamage = 2.2,
		Money = 1.3,
		ShopPrice = 1.35,
		WaveDelay = 0.6,
		PlayerRegen = 0.6,
		EnemyCount = 1.5,
		EnemySpeed = 1.15,
		EnemyWindUp = 0.8,
		EnemyCooldown = 0.75,
		MeleeAttackers = 3,
		Exp = 1.6,
	},
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Looks a difficulty up by name. A wrong name or a disabled entry
-- warns and returns the default rather than erroring, so a player
-- who joined without teleport data still gets a run.
function DifficultyConfig.Get(Name: string?)
	local Entry = Name and DifficultyConfig.Difficulties[Name]
	if not Entry or not Entry.Enabled then
		if Name ~= nil and Name ~= DifficultyConfig.Default then
			warn("[DifficultyConfig] no enabled difficulty called " .. tostring(Name) .. ", using " .. DifficultyConfig.Default)
		end
		Entry = DifficultyConfig.Difficulties[DifficultyConfig.Default]
	end
	return Entry
end

-- The names the lobby picker should offer, in a fixed order.
function DifficultyConfig.GetEnabledNames(): { string }
	local Names = {}
	for _, Name in ipairs({ "Easy", "Normal", "Hard" }) do
		local Entry = DifficultyConfig.Difficulties[Name]
		if Entry and Entry.Enabled then
			table.insert(Names, Name)
		end
	end
	return Names
end

return DifficultyConfig
