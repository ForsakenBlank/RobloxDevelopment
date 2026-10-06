--[[
	DifficultyConfig

	One entry per difficulty, keyed by the difficulty name string. Each
	entry holds the multipliers that difficulty changes: enemy health,
	enemy damage, money earned per kill and shop prices.

	"Normal" is the only one switched on, with every multiplier at 1.
	Easy and Hard are written in but Enabled = false, so the lobby's
	difficulty picker can turn them on later without anything else in
	the game needing to change, because every system already reads its
	multiplier from here.
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
DifficultyConfig.Difficulties = {

	Easy = {
		Enabled = false,
		DisplayName = "Easy",
		Description = "Weaker enemies and cheaper shops.",
		EnemyHealth = 0.75,
		EnemyDamage = 0.75,
		Money = 0.8,
		ShopPrice = 0.8,
		WaveDelay = 1.25,
		PlayerRegen = 1.25,
	},

	Normal = {
		Enabled = true,
		DisplayName = "Normal",
		Description = "The game as designed.",
		EnemyHealth = 1,
		EnemyDamage = 1,
		Money = 1,
		ShopPrice = 1,
		WaveDelay = 1,
		PlayerRegen = 1,
	},

	Hard = {
		Enabled = false,
		DisplayName = "Hard",
		Description = "Tougher enemies, faster waves, pricier shops.",
		EnemyHealth = 1.5,
		EnemyDamage = 1.5,
		Money = 1.25,
		ShopPrice = 1.25,
		WaveDelay = 0.75,
		PlayerRegen = 1,
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
