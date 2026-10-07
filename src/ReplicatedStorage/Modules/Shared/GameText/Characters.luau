-- Skins, faces, body parts and gamepasses. Prices, unlock levels and
-- gamepass ids are in Shared.SkinData; the keys must match it.
return {
	Skins = {
		Cape = { Name = "Cape" },
		Plain = { Name = "Plain" },
		Noob = { Name = "Noob", Unlock = "Beat Guest in Retroscity on Easy" },
		Guest = { Name = "Guest", Unlock = "Beat Guest in Retroscity on Impossible" },
		OriginalCharacter = { Name = "Original Character" },
		Monkey = { Name = "Monkey" },
		PizzaGuy = { Name = "Pizza Guy" },
		BusinessMan = { Name = "Business Man" },
		HighschoolBoy = { Name = "Highschool Boy" },
		StrangeDetective = { Name = "Strange Detective" },
		Guy = { Name = "Guy" },
		["1x1x1x1"] = { Name = "1x1x1x1" },
		Hacker = { Name = "Hacker" },
	},
	-- What a skin card says about it.
	Status = {
		Equipped = "EQUIPPED",
		Owned = "OWNED",
		Level = "LV {Level}",
		LevelOrPass = "LV {Level} OR {Pass}",
		Cash = "${Price}",
		Locked = "LOCKED",
	},
	Faces = {
		Smile = "SMILE",
		Grin = "GRIN",
		Focused = "FOCUSED",
		Smug = "SMUG",
		Chill = "CHILL",
		Angry = "ANGRY",
	},
	BodyParts = {
		Head = "HEAD",
		Torso = "TORSO",
		LeftArm = "LEFT ARM",
		RightArm = "RIGHT ARM",
		LeftLeg = "LEFT LEG",
		RightLeg = "RIGHT LEG",
	},
	Passes = {
		AccessorySlots = { Name = "+2 ACCESSORY SLOTS", Description = "Opens accessory slots 4 and 5 in your loadout, on top of the ones you unlock at levels 10 and 25." },
		DoubleExp = { Name = "2X EXP", Description = "Earn double EXP." },
		Customise = { Name = "CUSTOMISE!", Description = "Change the face and the colour of each body part on your Custom Character." },
		VIP = { Name = "VIP", Description = "1.25x EXP, 1.25x coins, the 1x1x1x1 skin, a golden lobby header, and $750 plus 5 Timebux every day you log in." },
	},
}
