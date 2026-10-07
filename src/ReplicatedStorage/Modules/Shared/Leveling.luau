-- Leveling
-- Turns a player's total XP into their level and how far they are
-- through it. The save only holds total XP (the game adds to it at the
-- end of every run), and the level is always worked out from that, so
-- the two can never disagree.
--
-- Used by the server (LevelService, for the Level stat and the
-- leaderboard) and the client (UIManager, for the XP bar).

local Leveling = {}

Leveling.Settings = {
	-- XP from level 1 to level 2, and how much more each level after
	-- needs than the one before.
	FirstLevel = 100,
	PerLevel = 50,
	MaxLevel = 100,
}

-- XP needed to go from Level to Level + 1.
function Leveling.XPForLevel(Level: number): number
	local S = Leveling.Settings
	return S.FirstLevel + (Level - 1) * S.PerLevel
end

-- Returns the level for TotalXP, the XP into that level, and the XP
-- that level needs.
function Leveling.FromXP(TotalXP: number): (number, number, number)
	local Level = 1
	local Left = math.max(0, math.floor(TotalXP or 0))
	while Level < Leveling.Settings.MaxLevel and Left >= Leveling.XPForLevel(Level) do
		Left -= Leveling.XPForLevel(Level)
		Level += 1
	end
	return Level, Left, Leveling.XPForLevel(Level)
end

return Leveling
