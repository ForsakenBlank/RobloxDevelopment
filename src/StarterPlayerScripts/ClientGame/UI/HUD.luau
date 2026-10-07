--[[
	HUD

	A class that owns the on screen HUD elements. It builds or finds the
	health bar, energy bar, money label, wave counter and the status
	effect icon row, and gives HUDController simple methods to set each
	one.

	The point of splitting this from HUDController is that this module
	knows about the GUI objects and nothing else, and the controller
	knows about the remotes and nothing else. So if the HUD gets
	redesigned only this file changes, and if the remotes change only the
	controller does.

	It handles the bar fill, the number formatting and the tweening. It
	does not decide what the values are.
]]

--[[
	What connects to this

	Created and driven by:
	  ClientGame.Controllers.HUDController, which is the only thing that
	  should call its setters.

	Owns:
	  StarterGui.HUD. The Frames and labels in it are found by the names
	  in Game.Config.HUDConfig.Names, so they can be moved and restyled
	  in the editor freely as long as the names stay the same.

	Reads:
	  Game.Config.HUDConfig for colours, tween times and formats.
	  Game.Data.StatusEffectData for the icon and colour of each effect,
	  so the effect row does not need its own copy of that list.

	The bars need to handle max health and max energy changing mid run,
	because the shop artifacts raise both. A bar that assumes 100 is the
	maximum will show wrong after a health artifact is bought, so always
	work the fill out as current over max rather than current over 100.

	Money should be formatted rather than shown raw, and the health and
	energy numbers rounded, but round for display only and never round
	the value that gets sent back anywhere.

	Keep it working with the existing StarterGui.Hotbar, which is already
	on screen from the movement framework. The HUD needs to not sit on
	top of it.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HUDConfig = require(ReplicatedStorage.Modules.Game.Config.HUDConfig)
local StatusEffectData = require(ReplicatedStorage.Modules.Game.Data.StatusEffectData)

local Names = HUDConfig.Names

local HUD = {}
HUD.__index = HUD

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Finds a descendant by name and warns once if it is missing, so a
-- renamed Frame shows up in the output rather than silently doing
-- nothing.
local function Find(Root: Instance?, Name: string, Optional: boolean?): Instance?
	if not Root then
		return nil
	end
	local Found = Root:FindFirstChild(Name, true)
	if not Found and not Optional then
		warn("[HUD] could not find '" .. Name .. "' under " .. Root:GetFullName())
	end
	return Found
end

local function Tween(Object: Instance, Time: number, Goal: { [string]: any }, Style: Enum.EasingStyle?, Direction: Enum.EasingDirection?)
	if Time <= 0 then
		for Key, Value in pairs(Goal) do
			(Object :: any)[Key] = Value
		end
		return nil
	end
	local Info = TweenInfo.new(Time, Style or Enum.EasingStyle.Quad, Direction or Enum.EasingDirection.Out)
	local T = TweenService:Create(Object, Info, Goal)
	T:Play()
	return T
end

----------------------------------------------------------------------
-- CONSTRUCTION
----------------------------------------------------------------------

function HUD.new()
	local self = setmetatable({}, HUD)

	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Gui = PlayerGui:WaitForChild(Names.ScreenGui, 10)
	if not self.Gui then
		warn("[HUD] no ScreenGui called " .. Names.ScreenGui .. " in PlayerGui")
		return self
	end

	-- Bars.
	self.Bars = {}
	for _, Key in ipairs({ "Health", "Energy" }) do
		local BarFrame = Find(self.Gui, Names[Key .. "Bar"])
		self.Bars[Key] = {
			Frame = BarFrame,
			-- The slanted bars draw their background on a rotated Shape
			-- inside a clipping frame, so flashes go on that.
			Paint = BarFrame and BarFrame:FindFirstChild("Shape") or BarFrame,
			Fill = Find(BarFrame, Names.BarFill),
			Value = Find(BarFrame, Names.BarValue),
			Config = HUDConfig.Bars[Key],
			Current = 0,
			Max = 1,
			Low = false,
		}
		if self.Bars[Key].Fill then
			self.Bars[Key].Fill.BackgroundColor3 = HUDConfig.Bars[Key].Colour
		end
	end

	-- Labels.
	self.MoneyLabel = Find(self.Gui, Names.Money)
	self.LevelLabel = Find(self.Gui, Names.Level)
	self.WaveLabel = Find(self.Gui, Names.WaveInfo)
	self.RoomLabel = Find(self.Gui, "RoomInfo", true)
	self.DifficultyLabel = Find(self.Gui, Names.Difficulty)
	self.MoneyShown = 0
	self.MoneyTarget = 0

	-- The line under the wave number and its bar of enemies left.
	self.LeftLabel = Find(self.Gui, "EnemiesLeft", true)
	local WaveBar = Find(self.Gui, "WaveBar", true)
	self.WaveFill = WaveBar and WaveBar:FindFirstChild(Names.BarFill, true)
	self.WaveNumber = nil
	self.WaveSize = 1

	-- The player's own name and face on the stats panel.
	local StatsFrame = Find(self.Gui, Names.Stats)
	local Player = Players.LocalPlayer
	local NameLabel = Find(StatsFrame, "PlayerName", true)
	if NameLabel then
		NameLabel.Text = Player.DisplayName
	end
	local Portrait = Find(StatsFrame, "Portrait", true)
	if Portrait then
		Portrait.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", Player.UserId)
	end

	-- Cooldown slots, keyed by their frame name.
	self.Slots = {}
	self.SwapLabels = {}
	local CooldownsFrame = Find(self.Gui, Names.Cooldowns)
	if CooldownsFrame then
		for _, GroupName in ipairs({ Names.WeaponGroup, Names.AbilityGroup }) do
			local Group = Find(CooldownsFrame, GroupName, true)
			local Swap = Group and Group:FindFirstChild(Names.SwapKey)
			if Swap then
				self.SwapLabels[GroupName] = Swap
				Swap.Visible = HUDConfig.Cooldowns.ShowSwapKey
			end
		end

		for _, Descendant in ipairs(CooldownsFrame:GetDescendants()) do
			if Descendant:IsA("Frame") and Descendant:FindFirstChild(Names.SlotBase) then
				local Base = Descendant:FindFirstChild(Names.SlotBase)
				self.Slots[Descendant.Name] = {
					Frame = Descendant,
					Base = Base,
					-- Slanted slots paint a rotated Shape inside Base.
					Paint = Base:FindFirstChild("Shape") or Base,
					Icon = Find(Base, Names.SlotIcon, true),
					-- Optional emoji that fills the slot.
					Emoji = Find(Base, "Emoji", true),
					Sweep = Find(Base, Names.SlotSweep, true),
					Key = Find(Descendant, Names.SlotKey, true),
					Timer = Find(Base, Names.SlotTimer, true),
					Name = Find(Descendant, Names.SlotName, true),
					CooldownEndsAt = 0,
					CooldownLength = 0,
					Active = true,
					Affordable = true,
				}
				local Slot = self.Slots[Descendant.Name]
				if Slot.Sweep then
					Slot.Sweep.BackgroundColor3 = HUDConfig.Cooldowns.SweepColour
					Slot.Sweep.BackgroundTransparency = HUDConfig.Cooldowns.SweepTransparency
					Slot.Sweep.Size = UDim2.new(1, 0, 0, 0)
				end
				if Slot.Timer then
					Slot.Timer.Text = ""
				end
				if Slot.Key then
					Slot.Key.Visible = HUDConfig.Cooldowns.ShowKeys
				end
				if Slot.Name then
					Slot.Name.Visible = HUDConfig.Cooldowns.ShowNames
				end
			end
		end
	end

	-- Effects row.
	self.EffectsFrame = Find(self.Gui, Names.Effects)
	self.EffectTemplate = Find(self.EffectsFrame, Names.EffectTemplate)
	self.Effects = {}

	-- One loop for the things that tick: cooldown timers, effect
	-- timers, the low health pulse and the money count.
	self.Time = 0
	self.Connection = RunService.RenderStepped:Connect(function(DeltaTime)
		self.Time += DeltaTime
		self:_Update(DeltaTime)
	end)

	self:SetWave(nil)
	return self
end

function HUD:Destroy()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

----------------------------------------------------------------------
-- BARS
----------------------------------------------------------------------

function HUD:_SetBar(Key: string, Current: number, Max: number)
	local Bar = self.Bars[Key]
	if not Bar or not Bar.Frame then
		return
	end

	Max = math.max(Max, 1)
	local WasCurrent = Bar.Current
	Bar.Current = Current
	Bar.Max = Max

	local Fraction = math.clamp(Current / Max, 0, 1)
	local Config = HUDConfig.Bars

	if Bar.Fill then
		Tween(Bar.Fill, Config.TweenTime, { Size = UDim2.new(Fraction, 0, 1, 0) }, Config.EasingStyle, Config.EasingDirection)
	end

	if Bar.Value then
		Bar.Value.Text = string.format(Config.ValueFormat, HUDConfig.RoundForDisplay(Current), HUDConfig.RoundForDisplay(Max))
	end

	-- Low state colour.
	local Low = Fraction <= Bar.Config.LowPercent and Bar.Config.LowPercent > 0
	if Low ~= Bar.Low then
		Bar.Low = Low
		if Bar.Fill then
			Bar.Fill.BackgroundColor3 = Low and Bar.Config.LowColour or Bar.Config.Colour
			if not Low then
				Bar.Fill.BackgroundTransparency = 0
			end
		end
	end

	-- Damage flash on a drop.
	if Bar.Config.DamageFlash and Current < WasCurrent and Bar.Paint then
		local Original = Bar.OriginalPaint or Bar.Paint.BackgroundColor3
		Bar.OriginalPaint = Original
		Bar.Paint.BackgroundColor3 = Color3.new(1, 1, 1)
		Tween(Bar.Paint, Bar.Config.DamageFlashTime, { BackgroundColor3 = Original })
	end
end

function HUD:SetHealth(Current: number, Max: number)
	self:_SetBar("Health", Current, Max)
end

function HUD:SetEnergy(Current: number, Max: number)
	self:_SetBar("Energy", Current, Max)
end

----------------------------------------------------------------------
-- LABELS
----------------------------------------------------------------------

function HUD:SetMoney(Value: number)
	if not self.MoneyLabel then
		return
	end
	local Config = HUDConfig.Money
	local Gained = Value > self.MoneyTarget
	self.MoneyTarget = Value

	if Config.CountTime <= 0 then
		self.MoneyShown = Value
		self:_RenderMoney()
	end

	if Gained and Config.PopOnGain then
		local Label = self.MoneyLabel
		local Original = Label.TextSize
		Label.TextSize = math.floor(Original * Config.PopScale)
		Tween(Label, Config.PopTime, { TextSize = Original })
	end
end

function HUD:_RenderMoney()
	local Config = HUDConfig.Money
	local Number = Config.ThousandsSeparator and HUDConfig.FormatThousands(self.MoneyShown) or tostring(math.floor(self.MoneyShown))
	self.MoneyLabel.Text = string.format(Config.Format, Number)
end

function HUD:SetLevel(Value: number)
	if self.LevelLabel then
		self.LevelLabel.Text = string.format(HUDConfig.Level.Format, Value)
	end
end

function HUD:SetDifficulty(Name: string?)
	if not self.DifficultyLabel then
		return
	end
	self.DifficultyLabel.Visible = HUDConfig.Difficulty.Show and Name ~= nil
	if Name then
		self.DifficultyLabel.Text = string.format(HUDConfig.Difficulty.Format, Name)
	end
end

-- The room name at the top of the screen, from the room banner.
function HUD:SetRoom(Text: string?)
	if self.RoomLabel then
		self.RoomLabel.Text = Text and string.upper(Text) or ""
	end
end

-- nil clears the wave display.
function HUD:SetWave(Current: number?, Total: number?, EnemiesLeft: number?)
	if not self.WaveLabel then
		return
	end
	local Config = HUDConfig.Wave
	if Current == nil then
		self.WaveLabel.Text = Config.IdleText
		self.WaveLabel.Visible = not Config.HideWhenIdle
		self.WaveNumber = nil
		if self.LeftLabel then
			self.LeftLabel.Text = ""
		end
		if self.WaveFill then
			self.WaveFill.Size = UDim2.new(0, 0, 1, 0)
		end
		return
	end
	self.WaveLabel.Visible = true
	self.WaveLabel.Text = string.format(Config.Format, Current, Total or 0, EnemiesLeft or 0)

	-- The bar is enemies left over the most this wave has had.
	local Left = EnemiesLeft or 0
	if Current ~= self.WaveNumber then
		self.WaveNumber = Current
		self.WaveSize = 1
	end
	self.WaveSize = math.max(self.WaveSize, Left)
	if self.LeftLabel then
		self.LeftLabel.Text = string.format(Config.LeftFormat, Left)
	end
	if self.WaveFill then
		local Bars = HUDConfig.Bars
		Tween(self.WaveFill, Bars.TweenTime, { Size = UDim2.new(Left / self.WaveSize, 0, 1, 0) }, Bars.EasingStyle, Bars.EasingDirection)
	end
end

-- Sets everything from a PlayerStats snapshot in one go.
function HUD:SetStats(Snapshot)
	self:SetHealth(Snapshot.Health, Snapshot.MaxHealth)
	self:SetEnergy(Snapshot.Energy, Snapshot.MaxEnergy)
	self:SetMoney(Snapshot.Money)
	self:SetLevel(Snapshot.Level)
end

----------------------------------------------------------------------
-- COOLDOWN SLOTS
----------------------------------------------------------------------

-- Fills a slot with what it holds. Info is { DisplayName, Icon, Key }.
-- nil empties it.
function HUD:SetSlot(SlotName: string, Info: { DisplayName: string?, Icon: string?, Emoji: string?, Key: string? }?)
	local Slot = self.Slots[SlotName]
	if not Slot then
		warn("[HUD] no cooldown slot called " .. tostring(SlotName))
		return
	end
	if Slot.Icon then
		Slot.Icon.Image = Info and Info.Icon or ""
	end
	if Slot.Emoji then
		Slot.Emoji.Text = Info and Info.Emoji or ""
	end
	if Slot.Name then
		Slot.Name.Text = Info and Info.DisplayName or ""
	end
	if Slot.Key and Info and Info.Key then
		Slot.Key.Text = Info.Key
	end
	Slot.Frame.Visible = Info ~= nil
end

-- Sets the swap key shown above a pair of slots. GroupName is
-- HUDConfig.Names.WeaponGroup or AbilityGroup.
function HUD:SetSwapKey(GroupName: string, Key: string)
	local Label = self.SwapLabels[GroupName]
	if Label then
		Label.Text = string.upper(string.format(HUDConfig.Cooldowns.SwapFormat, GroupName, Key))
	end
end

function HUD:_ApplySlotTransparency(Slot)
	local Config = HUDConfig.Cooldowns
	local Transparency = 0
	if not Slot.Active then
		Transparency = Config.InactiveTransparency
	elseif not Slot.Affordable then
		Transparency = Config.UnaffordableTransparency
	end
	if Slot.Icon then
		Slot.Icon.ImageTransparency = Transparency
	end
	if Slot.Emoji then
		Slot.Emoji.TextTransparency = Transparency
	end
	if Slot.Name then
		Slot.Name.TextTransparency = Transparency
	end
	if Slot.Base then
		-- The equipped slot gets the gold outline, like a picked card
		-- on the character creation screen.
		local Stroke = Slot.Base:FindFirstChildOfClass("UIStroke")
		if Stroke then
			local Config2 = HUDConfig.Cooldowns
			Stroke.Transparency = Slot.Active and 0 or 0.4
			Stroke.Color = Slot.Active and Config2.ActiveOutline or Config2.IdleOutline
			Stroke.Thickness = Slot.Active and 2 or 1
		end
	end
	if Slot.Paint and Slot.Paint ~= Slot.Base then
		Slot.Paint.BackgroundTransparency = 0.05 + Transparency * 0.6
	end
end

-- Flashes a slot gold and pops it, for a weapon just swapped to.
function HUD:PulseSlot(SlotName: string)
	local Slot = self.Slots[SlotName]
	if not Slot or not Slot.Paint then
		return
	end
	local Original = Slot.OriginalPaint or Slot.Paint.BackgroundColor3
	Slot.OriginalPaint = Original
	Slot.Paint.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
	Tween(Slot.Paint, 0.25, { BackgroundColor3 = Original })
	local Scale = Slot.Frame:FindFirstChild("PulseScale")
	if not Scale then
		Scale = Instance.new("UIScale")
		Scale.Name = "PulseScale"
		Scale.Parent = Slot.Frame
	end
	Scale.Scale = 1.12
	Tween(Scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- The equipped slot of a pair is active, the put away one is faded.
function HUD:SetSlotActive(SlotName: string, Active: boolean)
	local Slot = self.Slots[SlotName]
	if not Slot then
		return
	end
	Slot.Active = Active
	self:_ApplySlotTransparency(Slot)
end

-- Ability slots the player cannot pay for are dimmed.
function HUD:SetSlotAffordable(SlotName: string, Affordable: boolean)
	local Slot = self.Slots[SlotName]
	if not Slot then
		return
	end
	Slot.Affordable = Affordable
	self:_ApplySlotTransparency(Slot)
end

-- Starts a sweep on a slot for Duration seconds. Remaining lets it
-- start part way through, for a swap to a weapon whose cooldown was
-- already running.
function HUD:StartCooldown(SlotName: string, Duration: number, Remaining: number?)
	local Slot = self.Slots[SlotName]
	if not Slot or Duration <= 0 then
		return
	end
	Slot.CooldownLength = Duration
	Slot.CooldownEndsAt = self.Time + (Remaining or Duration)
end

function HUD:ClearCooldown(SlotName: string)
	local Slot = self.Slots[SlotName]
	if not Slot then
		return
	end
	Slot.CooldownEndsAt = 0
	if Slot.Sweep then
		Slot.Sweep.Size = UDim2.new(1, 0, 0, 0)
	end
	if Slot.Timer then
		Slot.Timer.Text = ""
	end
end

function HUD:_UpdateSlot(Slot)
	if Slot.CooldownEndsAt <= 0 then
		return
	end
	local Remaining = Slot.CooldownEndsAt - self.Time
	local Config = HUDConfig.Cooldowns

	if Remaining <= 0 then
		Slot.CooldownEndsAt = 0
		if Slot.Sweep then
			Slot.Sweep.Size = UDim2.new(1, 0, 0, 0)
		end
		if Slot.Timer then
			Slot.Timer.Text = ""
		end
		if Config.ReadyFlash and Slot.Paint then
			local Original = Slot.OriginalPaint or Slot.Paint.BackgroundColor3
			Slot.OriginalPaint = Original
			Slot.Paint.BackgroundColor3 = Color3.new(1, 1, 1)
			Tween(Slot.Paint, Config.ReadyFlashTime, { BackgroundColor3 = Original })
		end
		return
	end

	local Fraction = math.clamp(Remaining / Slot.CooldownLength, 0, 1)
	if Slot.Sweep then
		Slot.Sweep.Size = UDim2.new(1, 0, Fraction, 0)
	end
	if Slot.Timer then
		Slot.Timer.Text = Config.ShowSeconds and string.format(Config.SecondsFormat, Remaining) or ""
	end
end

----------------------------------------------------------------------
-- EFFECTS
----------------------------------------------------------------------

-- Shows an effect icon until EndsAt (in the HUD's own clock, so pass
-- a duration through AddEffectFor instead if that is what you have).
function HUD:AddEffect(EffectName: string, Duration: number)
	if not self.EffectsFrame or not self.EffectTemplate then
		return
	end
	local Data = StatusEffectData.Effects[EffectName]
	if not Data or not Data.ShowOnHUD then
		return
	end

	local Entry = self.Effects[EffectName]
	if not Entry then
		local Frame = self.EffectTemplate:Clone()
		Frame.Name = EffectName
		Frame.Visible = true
		Frame.Parent = self.EffectsFrame
		Entry = {
			Frame = Frame,
			Icon = Find(Frame, Names.EffectIcon, true),
			Timer = Find(Frame, Names.EffectTimer, true),
		}
		self.Effects[EffectName] = Entry

		local Config = HUDConfig.Effects
		if Entry.Icon then
			Entry.Icon.Image = Data.Icon
			if Config.TintIcons then
				Entry.Icon.ImageColor3 = Data.Colour
			end
		end
		local Stroke = Frame:FindFirstChildOfClass("UIStroke")
		if Stroke then
			Stroke.Color = Data.IsHarmful and Config.HarmfulOutline or Config.GoodOutline
		end
		if Entry.Timer then
			Entry.Timer.Visible = Config.ShowTimer
		end
		Frame.BackgroundTransparency = 1
		Tween(Frame, Config.FadeTime, { BackgroundTransparency = self.EffectTemplate.BackgroundTransparency })
	end

	Entry.EndsAt = self.Time + Duration
end

function HUD:RemoveEffect(EffectName: string)
	local Entry = self.Effects[EffectName]
	if not Entry then
		return
	end
	self.Effects[EffectName] = nil
	local Frame = Entry.Frame
	local T = Tween(Frame, HUDConfig.Effects.FadeTime, { BackgroundTransparency = 1 })
	if T then
		T.Completed:Once(function()
			Frame:Destroy()
		end)
	else
		Frame:Destroy()
	end
end

function HUD:ClearEffects()
	for Name in pairs(self.Effects) do
		self:RemoveEffect(Name)
	end
end

----------------------------------------------------------------------
-- UPDATE LOOP
----------------------------------------------------------------------

function HUD:_Update(DeltaTime: number)
	-- Cooldowns.
	for _, Slot in pairs(self.Slots) do
		self:_UpdateSlot(Slot)
	end

	-- Effect timers.
	for Name, Entry in pairs(self.Effects) do
		local Remaining = Entry.EndsAt - self.Time
		if Remaining <= 0 then
			self:RemoveEffect(Name)
		elseif Entry.Timer then
			Entry.Timer.Text = string.format(HUDConfig.Effects.TimerFormat, math.ceil(Remaining))
		end
	end

	-- Low health pulse.
	local Health = self.Bars.Health
	if Health and Health.Fill then
		if Health.Low and Health.Config.Flash then
			local Phase = (math.sin(self.Time / Health.Config.FlashRate * math.pi * 2) + 1) / 2
			Health.Fill.BackgroundTransparency = Phase * Health.Config.FlashTransparency
		end
	end

	-- Money count.
	if self.MoneyLabel and self.MoneyShown ~= self.MoneyTarget then
		local Config = HUDConfig.Money
		if Config.CountTime <= 0 then
			self.MoneyShown = self.MoneyTarget
		else
			local Step = (self.MoneyTarget - self.MoneyShown) * math.min(DeltaTime / Config.CountTime * 4, 1)
			if math.abs(self.MoneyTarget - self.MoneyShown) < 1 then
				self.MoneyShown = self.MoneyTarget
			else
				self.MoneyShown += Step
			end
		end
		self:_RenderMoney()
	end
end

return HUD
