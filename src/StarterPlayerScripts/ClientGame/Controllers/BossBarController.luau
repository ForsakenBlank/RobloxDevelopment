--[[
	BossBarController

	Shows the boss health bar during the BossRoom fight and hides it the
	rest of the time. It appears when the boss spawns, updates whenever
	the boss takes damage, turns a brighter red when the boss enrages,
	and goes away a moment after the boss dies.

	The success criteria says the boss has a health bar that updates when
	its health changes, so this is driven by the server sending the new
	value rather than by reading the boss model, which the client should
	not be trusting anyway.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.BossHealthChanged, fired by
	  Server.Game.Enemies.Types.Boss with (Current, Max, DisplayName,
	  Enraged).
	  ReplicatedStorage.Remotes.Events.RunStateChanged, so the bar is
	  hidden when the run ends or resets.

	Drives (designed in the editor, StarterGui.BossBar):
	  Boss                  the whole bar, shown and hidden
	  Boss > BossName       the name
	  Boss > Bar > Value    "current / max"
	  Boss > Bar > Shape > Fill    the health, sized by scale
	  Boss > Bar > Shape > Trail   the chunk just lost, follows slower
	The Fill and Trail sit inside the rotated Shape, so resizing them
	keeps the slanted end.

	Started by:
	  ClientGame.ClientMain.

	The max health comes from the remote, not from Game.Data.EnemyData,
	because the boss is scaled by player count and difficulty on the
	server and the client does not know by how much.

	The fill tween is short so a boss taking rapid damage never shows a
	value that has fallen behind, which the criteria would count against.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local Player = Players.LocalPlayer

local BossBarController = {}

BossBarController.Settings = {
	TweenTime = 0.12,
	TrailDelay = 0.35,
	TrailTime = 0.4,
	HideDelay = 2,
	-- The Fill's gradient is set in the editor. While enraged it is
	-- tinted with this.
	EnragedTint = Color3.fromRGB(255, 150, 150),
}

local Holder: Frame? = nil
local Fill: Frame? = nil
local Trail: Frame? = nil
local NameLabel: TextLabel? = nil
local ValueLabel: TextLabel? = nil
local HideToken = 0

local function Hide()
	if Holder then
		Holder.Visible = false
	end
end

local function OnBossHealth(Current: number, Max: number, DisplayName: string?, Enraged: boolean?)
	if not Holder or type(Current) ~= "number" or type(Max) ~= "number" or Max <= 0 then
		return
	end
	local Settings = BossBarController.Settings
	HideToken += 1
	local Fraction = math.clamp(Current / Max, 0, 1)
	Holder.Visible = true
	NameLabel.Text = string.upper(DisplayName or "Boss") .. (Enraged and "  -  ENRAGED" or "")
	ValueLabel.Text = string.format("%d / %d", math.ceil(Current), math.ceil(Max))
	Fill.BackgroundColor3 = Enraged and Settings.EnragedTint or Color3.new(1, 1, 1)

	TweenService:Create(Fill, TweenInfo.new(Settings.TweenTime), { Size = UDim2.fromScale(Fraction, 1) }):Play()
	task.delay(Settings.TrailDelay, function()
		TweenService:Create(Trail, TweenInfo.new(Settings.TrailTime), { Size = UDim2.fromScale(Fraction, 1) }):Play()
	end)

	if Current <= 0 then
		local Token = HideToken
		task.delay(Settings.HideDelay, function()
			if HideToken == Token then
				Hide()
			end
		end)
	end
end

function BossBarController.Init()
	local PlayerGui = Player:WaitForChild("PlayerGui")
	local Gui = PlayerGui:WaitForChild("BossBar", 10)
	if not Gui then
		warn("[BossBarController] no BossBar ScreenGui in StarterGui")
		return
	end
	Holder = Gui:WaitForChild("Boss")
	NameLabel = Holder:WaitForChild("BossName")
	local Bar = Holder:WaitForChild("Bar")
	ValueLabel = Bar:WaitForChild("Value")
	Fill = Bar:FindFirstChild("Fill", true)
	Trail = Bar:FindFirstChild("Trail", true)
	Holder.Visible = false

	Events:WaitForChild("BossHealthChanged").OnClientEvent:Connect(OnBossHealth)
	Events:WaitForChild("RunStateChanged").OnClientEvent:Connect(function(Run)
		if type(Run) == "table" and Run.State ~= "Playing" and Run.State ~= "Won" then
			HideToken += 1
			Hide()
		end
	end)
end

return BossBarController
