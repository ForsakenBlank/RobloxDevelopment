--[[
	ScreenEffects

	The whole screen reacting to what the player is doing, on top of the
	HUD feedback in HUDEffects (speed FOV, hit markers, hurt edges):

	  Speed lines     white streaks round the edges of the screen when the
	                  player moves fast (sprinting, dashing, sliding,
	                  gliding), more of them and longer the faster they
	                  go. The middle of the screen stays clear for aiming.
	  Colour grading  one ColorCorrectionEffect blending a few looks: a
	                  red kick when hurt, a green one when healed, warm
	                  and punchy while the Damage effect is on (Rage, the
	                  damage potion), cold and grey while stunned, and the
	                  colour draining away as health gets low, and a
	                  pale blue wash while the player has i-frames
	                  (can not be hurt).
	  Dash blur       a very short, light blur as a dash starts, kept
	                  small so it never gets in the way of aiming.
	  Kill pop        a faint white flash and contrast pop on a kill.

	All of it is local to this client and only visual.
]]

--[[
	What connects to this

	Drives (built in the editor):
	  Lighting.ScreenFX, a ColorCorrectionEffect left neutral in the
	  place, and Lighting.ScreenFXBlur, a BlurEffect of size 0.
	  StarterGui.ScreenEffects > SpeedLines > LineTemplate, cloned for
	  each streak, and ScreenEffects > Flash for the kill pop.

	Reads:
	  The Health, MaxHealth and IsAlive attributes that
	  Server.Game.Core.PlayerStats mirrors onto the Player.
	  The "dashing" attribute Movement.Dash sets on the character.

	Listens on:
	  ReplicatedStorage.Remotes.Events.EffectChanged from
	  Server.Game.Effects.StatusEffectService, for the Damage and Stun
	  effects on this player.
	  ReplicatedStorage.Remotes.Events.HitConfirmed from
	  Server.Game.Combat.DamageService, for kills.

	Started by:
	  ClientGame.ClientMain.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events")

local Player = Players.LocalPlayer

local ScreenEffects = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

ScreenEffects.Settings = {
	SpeedLines = {
		Enabled = true,
		-- Horizontal studs a second where the lines start, and where
		-- they are at their strongest. Walking is 16, sprinting 36 to
		-- 52, and a dash is well over 100.
		StartSpeed = 40,
		FullSpeed = 110,
		-- Lines a second at full strength, and the most on screen.
		Rate = 120,
		MaxLines = 70,
		-- Seconds each line lasts.
		Life = 0.22,
		-- Where a line starts, as a share of the distance from the
		-- middle of the screen to a corner, and how many pixels it
		-- travels outwards.
		StartRadius = { 0.5, 0.85 },
		Travel = 160,
		-- Pixels long and thick, from weakest to strongest.
		Length = { 70, 260 },
		Thickness = { 1, 3 },
		-- How see through a line is at weakest and strongest.
		Transparency = { 0.75, 0.25 },
	},
	Grade = {
		Enabled = true,
		-- A hit this big a share of max health gives the full kick.
		HurtFullAt = 0.2,
		HurtTint = Color3.fromRGB(255, 140, 140),
		HurtContrast = 0.15,
		HurtTime = 0.35,
		HealTint = Color3.fromRGB(170, 255, 190),
		HealBrightness = 0.05,
		HealTime = 0.5,
		-- Heals smaller than this share of max health (the regen) do not
		-- flash.
		HealMinShare = 0.05,
		-- While the Damage effect is on.
		EmpoweredEffect = "Damage",
		EmpoweredTint = Color3.fromRGB(255, 220, 200),
		EmpoweredContrast = 0.12,
		EmpoweredSaturation = 0.2,
		-- While stunned.
		StunnedEffect = "Stun",
		StunnedTint = Color3.fromRGB(205, 220, 255),
		StunnedSaturation = -0.4,
		-- While the player has i-frames (the IFramesUntil attribute
		-- Server.Game.Core.PlayerStats writes on the character).
		IFramesTint = Color3.fromRGB(200, 230, 255),
		IFramesBrightness = 0.06,
		-- Health share where the colour starts to drain, and how much is
		-- gone at zero.
		LowHealthAt = 0.35,
		LowHealthSaturation = -0.55,
		-- How fast the lasting looks blend in and out.
		Smoothing = 8,
	},
	DashBlur = {
		Enabled = true,
		Size = 3,
		Time = 0.16,
	},
	KillPop = {
		Enabled = true,
		-- Flash transparency at its brightest (1 is none).
		Transparency = 0.92,
		Contrast = 0.12,
		Time = 0.18,
	},
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local Correction: ColorCorrectionEffect? = nil
local Blur: BlurEffect? = nil
local LineHolder: Frame? = nil
local LineTemplate: Frame? = nil
local Flash: Frame? = nil

-- Lines on screen, and spare ones to reuse.
local ActiveLines = {}
local SpareLines: { Frame } = {}
local SpawnCarry = 0

-- Kicks that fade out on their own, 1 down to 0.
local Hurt = 0
local Heal = 0
local DashKick = 0
local KillKick = 0

-- Lasting looks, and how far each is blended in.
local ActiveUntil: { [string]: number } = {}
local Empowered = 0
local Stunned = 0
local LowHealth = 0
local IFrames = 0

local LastHealth: number? = nil
local Rng = Random.new()

----------------------------------------------------------------------
-- SPEED LINES
----------------------------------------------------------------------

local function Lerp(A: number, B: number, T: number): number
	return A + (B - A) * T
end

local function TakeLine(): Frame?
	local Line = table.remove(SpareLines)
	if Line then
		return Line
	end
	if not LineTemplate or not LineHolder then
		return nil
	end
	local New = LineTemplate:Clone()
	New.Name = "Line"
	New.Parent = LineHolder
	return New
end

local function SpawnLine(Strength: number, Viewport: Vector2)
	local S = ScreenEffects.Settings.SpeedLines
	local Line = TakeLine()
	if not Line then
		return
	end
	local Angle = Rng:NextNumber(0, math.pi * 2)
	local Direction = Vector2.new(math.cos(Angle), math.sin(Angle))
	local Corner = Viewport.Magnitude / 2
	local Length = Lerp(S.Length[1], S.Length[2], Strength * Rng:NextNumber(0.6, 1))
	local Thickness = math.floor(Lerp(S.Thickness[1], S.Thickness[2], Strength * Rng:NextNumber()) + 0.5)
	Line.Size = UDim2.fromOffset(Length, math.max(Thickness, 1))
	Line.Rotation = math.deg(Angle)
	Line.Visible = true
	table.insert(ActiveLines, {
		Frame = Line,
		Born = os.clock(),
		Direction = Direction,
		From = Corner * Rng:NextNumber(S.StartRadius[1], S.StartRadius[2]) + Length / 2,
		Transparency = Lerp(S.Transparency[1], S.Transparency[2], Strength),
	})
end

local function StepLines(DeltaTime: number, Speed: number)
	local S = ScreenEffects.Settings.SpeedLines
	local Camera = workspace.CurrentCamera
	if not Camera or not LineHolder then
		return
	end
	local Viewport = Camera.ViewportSize
	local Middle = Viewport / 2

	local Strength = S.Enabled and math.clamp((Speed - S.StartSpeed) / (S.FullSpeed - S.StartSpeed), 0, 1) or 0
	SpawnCarry += S.Rate * Strength * DeltaTime
	while SpawnCarry >= 1 do
		SpawnCarry -= 1
		if #ActiveLines < S.MaxLines then
			SpawnLine(Strength, Viewport)
		end
	end

	local Now = os.clock()
	for Index = #ActiveLines, 1, -1 do
		local Entry = ActiveLines[Index]
		local Alpha = (Now - Entry.Born) / S.Life
		if Alpha >= 1 then
			Entry.Frame.Visible = false
			table.insert(SpareLines, Entry.Frame)
			table.remove(ActiveLines, Index)
		else
			local Distance = Entry.From + S.Travel * Alpha
			local Position = Middle + Entry.Direction * Distance
			Entry.Frame.Position = UDim2.fromOffset(Position.X, Position.Y)
			Entry.Frame.BackgroundTransparency = Lerp(Entry.Transparency, 1, Alpha * Alpha)
		end
	end
end

----------------------------------------------------------------------
-- GRADING
----------------------------------------------------------------------

local function Approach(Current: number, Target: number, DeltaTime: number): number
	return Current + (Target - Current) * math.min(1, DeltaTime * ScreenEffects.Settings.Grade.Smoothing)
end

local function EffectOn(Name: string): boolean
	local Until = ActiveUntil[Name]
	return Until ~= nil and os.clock() < Until
end

local function StepGrade(DeltaTime: number)
	local G = ScreenEffects.Settings.Grade
	if not Correction then
		return
	end
	if not G.Enabled then
		Correction.TintColor = Color3.new(1, 1, 1)
		Correction.Saturation = 0
		Correction.Contrast = 0
		Correction.Brightness = 0
		return
	end

	-- Lasting looks blend in and out smoothly.
	Empowered = Approach(Empowered, EffectOn(G.EmpoweredEffect) and 1 or 0, DeltaTime)
	Stunned = Approach(Stunned, EffectOn(G.StunnedEffect) and 1 or 0, DeltaTime)
	local Character = Player.Character
	local IFramesUntil = Character and Character:GetAttribute("IFramesUntil")
	local Covered = type(IFramesUntil) == "number" and workspace:GetServerTimeNow() < IFramesUntil
	IFrames = Approach(IFrames, Covered and 1 or 0, DeltaTime * 2)
	local Health = Player:GetAttribute("Health")
	local MaxHealth = Player:GetAttribute("MaxHealth")
	local LowTarget = 0
	if type(Health) == "number" and type(MaxHealth) == "number" and MaxHealth > 0 then
		LowTarget = math.clamp((G.LowHealthAt - Health / MaxHealth) / G.LowHealthAt, 0, 1)
	end
	LowHealth = Approach(LowHealth, LowTarget, DeltaTime)

	-- Kicks fade on their own.
	Hurt = math.max(0, Hurt - DeltaTime / G.HurtTime)
	Heal = math.max(0, Heal - DeltaTime / G.HealTime)
	KillKick = math.max(0, KillKick - DeltaTime / ScreenEffects.Settings.KillPop.Time)

	local Tint = Color3.new(1, 1, 1)
	Tint = Tint:Lerp(G.EmpoweredTint, Empowered)
	Tint = Tint:Lerp(G.StunnedTint, Stunned)
	Tint = Tint:Lerp(G.IFramesTint, IFrames)
	Tint = Tint:Lerp(G.HealTint, Heal)
	Tint = Tint:Lerp(G.HurtTint, Hurt)

	Correction.TintColor = Tint
	Correction.Saturation = G.EmpoweredSaturation * Empowered + G.StunnedSaturation * Stunned + G.LowHealthSaturation * LowHealth
	Correction.Contrast = G.EmpoweredContrast * Empowered + G.HurtContrast * Hurt + ScreenEffects.Settings.KillPop.Contrast * KillKick
	Correction.Brightness = G.HealBrightness * Heal + G.IFramesBrightness * IFrames
end

local function OnHealth()
	local G = ScreenEffects.Settings.Grade
	local Health = Player:GetAttribute("Health")
	local MaxHealth = Player:GetAttribute("MaxHealth")
	if type(Health) ~= "number" or type(MaxHealth) ~= "number" or MaxHealth <= 0 then
		return
	end
	if LastHealth and Player:GetAttribute("IsAlive") ~= false then
		local Change = (Health - LastHealth) / MaxHealth
		if Change < 0 then
			Hurt = math.max(Hurt, math.clamp(-Change / G.HurtFullAt, 0.35, 1))
		elseif Change >= G.HealMinShare then
			Heal = 1
		end
	end
	LastHealth = Health
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

local CharacterConnection: RBXScriptConnection? = nil

function ScreenEffects.OnCharacter(Character: Model)
	if CharacterConnection then
		CharacterConnection:Disconnect()
	end
	ActiveUntil = {}
	LastHealth = nil
	CharacterConnection = Character:GetAttributeChangedSignal("dashing"):Connect(function()
		if Character:GetAttribute("dashing") == true and ScreenEffects.Settings.DashBlur.Enabled then
			DashKick = 1
		end
	end)
end

function ScreenEffects.Init()
	Correction = Lighting:FindFirstChild("ScreenFX") :: ColorCorrectionEffect?
	Blur = Lighting:FindFirstChild("ScreenFXBlur") :: BlurEffect?
	if not Correction or not Blur then
		warn("[ScreenEffects] Lighting needs ScreenFX (ColorCorrectionEffect) and ScreenFXBlur (BlurEffect)")
	end

	local Gui = Player:WaitForChild("PlayerGui"):WaitForChild("ScreenEffects", 10)
	if Gui then
		LineHolder = Gui:FindFirstChild("SpeedLines") :: Frame?
		LineTemplate = LineHolder and LineHolder:FindFirstChild("LineTemplate") :: Frame?
		Flash = Gui:FindFirstChild("Flash") :: Frame?
		if LineTemplate then
			LineTemplate.Visible = false
		end
	else
		warn("[ScreenEffects] no ScreenEffects ScreenGui in StarterGui")
	end

	Player:GetAttributeChangedSignal("Health"):Connect(OnHealth)

	Events:WaitForChild("EffectChanged").OnClientEvent:Connect(function(EffectName: string, Duration: number?)
		if type(EffectName) ~= "string" then
			return
		end
		ActiveUntil[EffectName] = Duration and os.clock() + Duration or nil
	end)

	Events:WaitForChild("HitConfirmed").OnClientEvent:Connect(function(Killed)
		if Killed == true and ScreenEffects.Settings.KillPop.Enabled then
			KillKick = 1
		end
	end)

	RunService.RenderStepped:Connect(function(DeltaTime)
		local Character = Player.Character
		local Root = Character and Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local Speed = 0
		if Root then
			local Velocity = Root.AssemblyLinearVelocity
			Speed = Vector3.new(Velocity.X, 0, Velocity.Z).Magnitude
		end
		StepLines(DeltaTime, Speed)
		StepGrade(DeltaTime)

		local DashSettings = ScreenEffects.Settings.DashBlur
		DashKick = math.max(0, DashKick - DeltaTime / DashSettings.Time)
		if Blur then
			Blur.Size = DashSettings.Size * DashKick
		end
		if Flash then
			Flash.BackgroundTransparency = Lerp(1, ScreenEffects.Settings.KillPop.Transparency, KillKick)
		end
	end)
end

return ScreenEffects
