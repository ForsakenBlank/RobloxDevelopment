--[[
	HUDConfig

	Every tuning value for how the HUD behaves, in one place. Colours,
	tween times, number formats, the low health warning, what the
	cooldown sweep looks like, and which Roblox core UI gets hidden.

	The positions and sizes of the HUD elements are not here. Those live
	on the actual Frames in StarterGui.HUD, so they can be dragged around
	and styled in the editor. This module is about behaviour, and the
	names it uses to find those Frames.
]]

--[[
	What connects to this

	Read by:
	  ClientGame.UI.HUD for everything visual, and for the Frame names
	  it looks up under StarterGui.HUD.
	  ClientGame.Controllers.HUDController for the core UI toggles.

	The names in Names must match the instances in StarterGui.HUD. If
	one is renamed in the editor, rename it here too, or HUD warns and
	that element stays blank.

	The weapon and ability slot names come from Game.Data.WeaponData.
	Hotbar and Game.Data.AbilityData.Hotbar rather than being repeated
	here, because ReplicatedStorage.Modules.UI.Hotbar sweeps cooldowns
	by those same names.
]]

-- Note on when changes take effect. Everything here is read when the
-- HUD is built at the start of a session, so a change needs the
-- playtest restarting.

local HUDConfig = {}

----------------------------------------------------------------------
-- NAMES
----------------------------------------------------------------------

-- Instance names under StarterGui.HUD. The structure is:
--   HUD (ScreenGui)
--     Stats (Frame)
--       HealthBar (Frame) > Meter > Track > Fill (Frame), Value (TextLabel)
--       EnergyBar (Frame) > Meter > Track > Fill (Frame), Value (TextLabel)
--       Money, Level, PlayerName (TextLabel), Portrait (ImageLabel)
--     Cooldowns (Frame)
--       Weapons (Frame) > Swap (TextLabel, the heading above the slots)
--                       > Slots > WeaponSlot1, WeaponSlot2 (Frame)
--       Abilities (Frame) > Swap > Slots > AbilitySlot1, AbilitySlot2
--         each slot > Key (TextLabel, top left badge)
--                   > Base (Frame) > Icon (ImageLabel), Sweep (Frame),
--                                    Timer (TextLabel)
--                   > Name (TextLabel, bottom right badge)
--     Effects (Frame) > EffectTemplate (Frame, hidden)
--     TopInfo (Frame) > WaveInfo, RoomInfo, Difficulty, EnemiesLeft
--                       (TextLabel), WaveBar > Track > Fill (Frame)
--     Party (Frame) > MemberTemplate, driven by PartyController
-- The slanted panel shapes are plain Frames named Back, Rim, Inside and
-- so on. Nothing looks them up.
HUDConfig.Names = {
	ScreenGui = "HUD",

	Stats = "Stats",
	HealthBar = "HealthBar",
	EnergyBar = "EnergyBar",
	BarFill = "Fill",
	BarValue = "Value",
	Money = "Money",
	Level = "Level",

	Cooldowns = "Cooldowns",
	WeaponGroup = "Weapons",
	AbilityGroup = "Abilities",
	SwapKey = "Swap",
	SlotBase = "Base",
	SlotIcon = "Icon",
	SlotSweep = "Sweep",
	SlotKey = "Key",
	SlotName = "Name",
	SlotTimer = "Timer",

	Effects = "Effects",
	EffectTemplate = "EffectTemplate",
	EffectIcon = "Icon",
	EffectTimer = "Timer",

	WaveInfo = "WaveInfo",
	Difficulty = "Difficulty",
}

----------------------------------------------------------------------
-- BARS
----------------------------------------------------------------------

HUDConfig.Bars = {
	-- Seconds the fill takes to slide to a new value. 0 snaps.
	TweenTime = 0.2,
	EasingStyle = Enum.EasingStyle.Quad,
	EasingDirection = Enum.EasingDirection.Out,

	-- "%d / %d" shows "85 / 100". "%d" alone shows just the current.
	-- The first %d is the current value, the second the max.
	ValueFormat = "%d / %d",
	-- Numbers are rounded for display only. "Floor" so 0.4 shows as 0
	-- rather than a dead player reading 1, "Round" for nearest.
	Rounding = "Floor",

	-- The fill colours themselves are the UIGradient on each bar's Fill
	-- in StarterGui.HUD (red for health, yellow for energy), so edit
	-- them there. Colour here tints that gradient, white leaves it as
	-- designed.
	Health = {
		Colour = Color3.fromRGB(255, 255, 255),
		-- Below this fraction of max the bar turns LowColour and, if
		-- Flash is on, pulses.
		LowPercent = 0.25,
		LowColour = Color3.fromRGB(255, 190, 190),
		Flash = true,
		-- Seconds for one pulse.
		FlashRate = 0.6,
		-- Transparency the pulse dips to.
		FlashTransparency = 0.5,
		-- A brief white flash of the whole bar when damage is taken.
		DamageFlash = true,
		DamageFlashTime = 0.12,
	},

	Energy = {
		Colour = Color3.fromRGB(255, 255, 255),
		-- Below this fraction the bar dims, to hint an ability is out
		-- of reach.
		LowPercent = 0,
		LowColour = Color3.fromRGB(255, 255, 255),
		Flash = false,
		FlashRate = 0.6,
		FlashTransparency = 0.5,
		DamageFlash = false,
		DamageFlashTime = 0.12,
	},
}

----------------------------------------------------------------------
-- MONEY AND LEVEL
----------------------------------------------------------------------

HUDConfig.Money = {
	-- %s is the formatted number.
	Format = "$%s",
	-- 1250 shows as 1,250.
	ThousandsSeparator = true,
	-- Seconds the number counts up or down over. 0 snaps.
	CountTime = 0.35,
	-- Pop the label up a little when money goes up.
	PopOnGain = true,
	PopScale = 1.15,
	PopTime = 0.15,
}

HUDConfig.Level = {
	Format = "LV %d",
}

----------------------------------------------------------------------
-- COOLDOWNS
----------------------------------------------------------------------

HUDConfig.Cooldowns = {
	-- The dark overlay that sweeps down as a cooldown runs.
	SweepColour = Color3.fromRGB(0, 0, 0),
	SweepTransparency = 0.5,
	-- Show the seconds left as a number over the slot.
	ShowSeconds = true,
	-- Format for the seconds. "%.1f" shows 3.2, "%d" shows 3.
	SecondsFormat = "%.1f",
	-- A quick brighten when a cooldown finishes.
	ReadyFlash = true,
	ReadyFlashTime = 0.15,
	-- The slot that is not currently equipped is faded to this.
	InactiveTransparency = 0.55,
	-- Slot outline for the equipped slot and the put away one.
	ActiveOutline = Color3.fromRGB(8, 8, 11),
	IdleOutline = Color3.fromRGB(190, 196, 208),
	-- Ability slots the player cannot afford dim to this.
	UnaffordableTransparency = 0.4,
	-- Show the keybind badge on each slot. Off: R and G swap, so the
	-- slots have no keys of their own (the headings say so).
	ShowKeys = false,
	-- Show the heading above each pair of slots, with its keys.
	ShowSwapKey = true,
	-- The first %s is the group (Weapons or Abilities), the second the
	-- keys.
	SwapFormat = "%s · %s",
	-- Show the weapon or ability name under each slot.
	ShowNames = true,
}

----------------------------------------------------------------------
-- EFFECTS
----------------------------------------------------------------------

HUDConfig.Effects = {
	-- Show the seconds left under each effect icon.
	ShowTimer = true,
	TimerFormat = "%d",
	-- Icons tint to the effect's colour from StatusEffectData.
	TintIcons = true,
	-- Harmful effects get this outline, good ones get GoodOutline.
	HarmfulOutline = Color3.fromRGB(255, 80, 80),
	GoodOutline = Color3.fromRGB(80, 255, 140),
	-- Seconds the icon takes to fade in and out.
	FadeTime = 0.15,
}

----------------------------------------------------------------------
-- WAVE AND DIFFICULTY
----------------------------------------------------------------------

HUDConfig.Wave = {
	-- %d are wave number, wave total, enemies left in that order.
	Format = "WAVE %d/%d",
	-- The line under it. %d is the enemies left.
	LeftFormat = "%d LEFT",
	-- What shows between fights.
	IdleText = "",
	-- Hide the label entirely when there is no wave running.
	HideWhenIdle = true,
	-- the line under the wave count while the next wave is on its way
	BetweenText = "NEXT WAVE INCOMING",
	-- what the top shows outside a fight, as { title, line under it }. {Interact} is the player's interact key
	Status = {
		Spawn = { "GET READY", "HOLD {Interact} AT THE YELLOW GATE" },
		Countdown = { "GET READY", "THE FIGHT IS ABOUT TO START" },
		Cleared = { "ALL DEFEATED", "0 LEFT - GO TO THE NEXT ROOM" },
		BossCleared = { "BOSS DEFEATED", "0 LEFT" },
		Shop = { "SHOP", "BUY, THEN HOLD {Interact} AT THE GATE" },
	},
}

HUDConfig.Difficulty = {
	Format = "%s",
	Show = true,
}

----------------------------------------------------------------------
-- CORE UI
----------------------------------------------------------------------

-- Roblox's own on screen elements. The default health bar is hidden
-- because the HUD has its own, and it would otherwise show the
-- humanoid health which is only a mirror of the real run value.
HUDConfig.CoreGui = {
	HideHealth = true,
	-- The shop items are Tools in the Roblox Backpack, so its hotbar
	-- stays on.
	HideBackpack = false,
	HidePlayerList = false,
	HideChat = false,
	HideEmotes = true,
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Formats a number with thousands separators, 1250 to "1,250".
function HUDConfig.FormatThousands(Value: number): string
	local Text = tostring(math.floor(Value))
	local Formatted = Text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if Formatted:sub(1, 1) == "," then
		Formatted = Formatted:sub(2)
	end
	return Formatted
end

-- Rounds for display using the rule in Bars.Rounding.
function HUDConfig.RoundForDisplay(Value: number): number
	if HUDConfig.Bars.Rounding == "Round" then
		return math.floor(Value + 0.5)
	end
	return math.floor(Value)
end

return HUDConfig
