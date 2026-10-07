-- The lobby menu (on join and with B) and the HUD (walking around).
return {
	Logo = "VELOCITY",
	Buttons = {
		Play = "PLAY",
		Loadout = "LOADOUT",
		Core = "CORE",
		Squad = "SQUAD",
		Stats = "STATS",
		Character = "CHARACTER",
	},
	WalkAround = "WALK AROUND",
	-- The small HUD panels.
	MenuTitle = "M E N U",
	SquadTitle = "S Q U A D",
	-- The name plate in the HUD.
	CoreLine = "{Core} · {Class}",
	NoCore = "NO CORE YET",
	-- The developer switch (developers only).
	DevOn = "DEV: UNLOCK ALL ON",
	DevOff = "DEV: UNLOCK ALL OFF",
	DevUnlocked = "Everything unlocked",
	DevLocked = "Unlock all off",
	DevFailed = "Couldn't change it",
	LevelUp = "Level up! You're now level {Level}",
}
