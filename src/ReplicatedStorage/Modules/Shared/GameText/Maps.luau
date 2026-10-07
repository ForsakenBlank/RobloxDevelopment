-- Maps, their areas, and the difficulties. Place ids, colours and
-- levels are in Shared.GameConfig (Lobby.Maps); the keys must match it.
return {
	Maps = {
		VeloCITY = {
			Name = "VeloCITY",
			Description = "An empty and over growing city, very easy in difficulty tho!",
			Areas = { "Spawn", "Room 1", "Room 2", "Shop 1", "Room 3", "Room 4", "Shop 2", "Boss Room" },
		},
		RetroCity = {
			Name = "RETRO CITY",
			Description = "A retro slop city filled with a classic and nostalgic feel :)",
			Areas = { "Spawn", "Room 1", "Room 2", "Shop 1", "Room 3", "Room 4", "Shop 2", "Boss Room" },
		},
	},
	Difficulties = {
		Easy = { Name = "EASY", Text = "Fewer, weaker enemies. Good for learning a map." },
		Normal = { Name = "NORMAL", Text = "Standard enemy health and damage." },
		Hard = { Name = "HARD", Text = "Tougher enemies that hit harder." },
	},
}
