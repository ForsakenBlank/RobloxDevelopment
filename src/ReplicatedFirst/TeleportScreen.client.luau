--[[
	TeleportScreen

	Makes the trip between the lobby and a run look quick. Leaving this
	place, Roblox shows the screen set here (TeleportService
	SetTeleportGui) instead of a blank one while the lobby loads. Coming
	in from the lobby, the lobby's own screen (if it set one) stays up
	until this place has loaded and the character is in, then fades.

	The lobby can do the same with its own copy of this script, so the
	screen is the same in both directions.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer

local Settings = {
	Background = Color3.fromRGB(14, 17, 32),
	Accent = Color3.fromRGB(255, 205, 60),
	Text = "HEADING BACK TO THE LOBBY",
	-- seconds to wait for the character before taking the arriving screen down anyway
	CharacterWait = 15,
	FadeTime = 0.4,
}

-- the screen shown while leaving this place
local function Build(Text: string): ScreenGui
	local Gui = Instance.new("ScreenGui")
	Gui.Name = "TeleportScreen"
	Gui.IgnoreGuiInset = true
	Gui.ResetOnSpawn = false
	Gui.DisplayOrder = 1000

	local Back = Instance.new("Frame")
	Back.Name = "Back"
	Back.Size = UDim2.fromScale(1, 1)
	Back.BackgroundColor3 = Settings.Background
	Back.BorderSizePixel = 0
	Back.Parent = Gui

	local Bar = Instance.new("Frame")
	Bar.Name = "Bar"
	Bar.AnchorPoint = Vector2.new(0.5, 0.5)
	Bar.Position = UDim2.fromScale(0.5, 0.56)
	Bar.Size = UDim2.fromScale(0.22, 0.006)
	Bar.BackgroundColor3 = Settings.Accent
	Bar.BorderSizePixel = 0
	Bar.Parent = Back

	local Label = Instance.new("TextLabel")
	Label.Name = "Title"
	Label.AnchorPoint = Vector2.new(0.5, 0.5)
	Label.Position = UDim2.fromScale(0.5, 0.48)
	Label.Size = UDim2.fromScale(0.8, 0.07)
	Label.BackgroundTransparency = 1
	Label.Text = Text
	Label.TextColor3 = Color3.new(1, 1, 1)
	Label.TextScaled = true
	Label.Font = Enum.Font.GothamBlack
	Label.Parent = Back

	return Gui
end

pcall(TeleportService.SetTeleportGui, TeleportService, Build(Settings.Text))

-- the lobby's screen, kept up until this place is ready
local Ok, Arriving = pcall(TeleportService.GetArrivingTeleportGui, TeleportService)
if Ok and Arriving then
	pcall(ReplicatedFirst.RemoveDefaultLoadingScreen, ReplicatedFirst)
	Arriving.Parent = Player:WaitForChild("PlayerGui")

	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local Deadline = os.clock() + Settings.CharacterWait
	while not Player.Character and os.clock() < Deadline do
		task.wait(0.1)
	end
	task.wait(0.3)

	-- fade everything on it out, then remove it
	local Info = TweenInfo.new(Settings.FadeTime)
	for _, Item in ipairs(Arriving:GetDescendants()) do
		if Item:IsA("Frame") or Item:IsA("ImageLabel") then
			TweenService:Create(Item, Info, { BackgroundTransparency = 1 }):Play()
		end
		if Item:IsA("TextLabel") then
			TweenService:Create(Item, Info, { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
		if Item:IsA("ImageLabel") then
			TweenService:Create(Item, Info, { ImageTransparency = 1 }):Play()
		end
	end
	task.wait(Settings.FadeTime)
	Arriving:Destroy()
end
