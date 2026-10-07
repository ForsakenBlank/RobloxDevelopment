--[[
	RoomBannerController

	Shows the short message that appears when the players move into a new
	area, then fades it away after a few seconds. The design calls these
	the temporary HUD elements, separate from the constantly visible HUD.

	It also shows the entry countdown. When the first player crosses into
	the next area, RoomManager starts a short countdown before the area
	begins and everyone is pulled forward, and the player needs to see
	that number ticking down or being teleported will feel like a bug.

	On top of the banner it owns the other temporary messages:
	  toasts        short lines from the Notify remote ("Bought Health
	                Potion", "Waiting for 1 more player at the gate")
	  spectating    a line telling a dead player they will be revived
	  end screen    VICTORY or DEFEAT, the EXP and cash this player
	                earned, every player's kills, and the Replay and
	                Back to Lobby buttons

	The end screen's buttons are the only input here. Replay is a vote:
	the run restarts once half the players (rounded up) have pressed it.
	Back to Lobby sends just this player back. Both go to the server,
	which decides.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.RoomEntered, fired by
	  Server.Game.Rooms.RoomManager with { Area, Kind, Banner, Phase,
	  Countdown, EndsAt }. Phase is "Countdown", "Start" or "Cleared".
	  ReplicatedStorage.Remotes.Events.RunStateChanged for the run
	  starting and the win or loss at the end, sent by
	  Server.Game.Core.RunManager.
	  ReplicatedStorage.Remotes.Events.Notify for toasts.

	Drives (all designed in the editor under StarterGui.RoomBanner, this
	only changes text and visibility):
	  Banner > Title, Sub           the area banner
	  Toasts > ToastTemplate > Text cloned for each message
	  Spectate                      the "you are down" line
	  EndScreen > Panel > Result, RewardsCaption, Rewards (Exp, Cash),
	  Body, Buttons (Replay, Lobby), Status

	Sends:
	  ReplicatedStorage.Remotes.Events.RunVote with "Replay" or "Lobby",
	  handled by Server.Game.Core.RunManager.

	Uses ClientGame.UI.UIFade to fade the banner and toasts, so they go
	back to exactly the look set in the editor.

	Started by:
	  ClientGame.ClientMain.

	The countdown is worked out from the EndsAt server time sent once,
	using workspace:GetServerTimeNow, rather than the server sending a
	tick every second. That way it stays smooth, does not drift, and
	costs one remote call.

	Two banners can be triggered close together, for example an area
	clearing and the next one being entered. Each new banner cancels the
	one before it, which UIFade handles with its fade token.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local UIFade = require(script.Parent.Parent.UI.UIFade)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")
local Functions = Remotes:WaitForChild("Functions")

local Player = Players.LocalPlayer

local RoomBannerController = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

RoomBannerController.Settings = {
	-- Colour of the line under the title, by area kind.
	KindColours = {
		Spawn = Color3.fromRGB(180, 220, 255),
		Combat = Color3.fromRGB(255, 120, 100),
		Shop = Color3.fromRGB(255, 220, 90),
		Boss = Color3.fromRGB(255, 60, 60),
	},
	-- The line under the title when an area starts, by kind.
	StartLines = {
		Spawn = "Press L to pick your loadout, then hold Z at the yellow gate",
		Combat = "Clear every wave!",
		Shop = "Spend your money, then hold Z at the gate",
		Boss = "Defeat the boss!",
	},
	ClearedTitle = "CLEARED!",
	ClearedLine = "Head through the yellow gate",
	FadeTime = 0.3,
	ToastTime = 2.5,
	MaxToasts = 4,
	WinColour = Color3.fromRGB(255, 215, 80),
	LoseColour = Color3.fromRGB(255, 70, 70),
	-- Sounds for the banner coming in, an area being cleared, and the
	-- countdown ticking.
	BannerSound = "Whoosh",
	ClearedSound = "Ding",
	TickSound = "UIClick",
	-- Areas where the "Back to lobby" button shows mid run. The end
	-- screen has its own.
	LeaveAreas = { Spawn = true, Shop = true },
	-- Seconds the earned EXP and cash take to count up.
	RewardCountTime = 1.2,
	ExpFormat = "+%d EXP",
	CashFormat = "+$%d",
	PlayerLineFormat = "%s   %d kills   +%d EXP   +$%d",
	ReplayText = "Replay",
	ReplayVotedText = "Waiting...",
	LobbyText = "Back to Lobby",
	VoteFormat = "Replay votes: %d / %d",
	-- Faded when the place was not opened from the lobby.
	NoLobbyTransparency = 0.5,
	-- pushes the area banner and toasts down from where they sit in the editor (fraction of screen height)
	PopupDrop = 0.04,
}

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------

local Gui: ScreenGui? = nil
local Banner: Frame? = nil
local Title: TextLabel? = nil
local Sub: TextLabel? = nil
local Toasts: Frame? = nil
local ToastTemplate: GuiObject? = nil
local Spectate: GuiObject? = nil
local EndScreen: Frame? = nil

local BannerToken = 0
local CountdownEndsAt: number? = nil
local LastTick: number? = nil
local EndRestartAt: number? = nil
local EndToLobby = false
local HasLobby = false
local AreaKind: string? = nil
local LeaveButton: GuiButton? = nil

-- End screen state.
local AfterRun = "Vote"
local Voted = false
local VoteCount, VotesNeeded = 0, 1
local RewardTargets = { Exp = 0, Cash = 0 }
local RewardShownAt = 0

----------------------------------------------------------------------
-- BANNER
----------------------------------------------------------------------

-- Shows a title and a line under it. Hold nil keeps it up until the
-- next banner replaces it.
function RoomBannerController.Show(TitleText: string, SubText: string?, Colour: Color3?, Hold: number?)
	if not Banner then
		return
	end
	BannerToken += 1
	local Token = BannerToken
	Title.Text = string.upper(TitleText)
	Sub.Text = SubText or ""
	if Colour then
		Sub.TextColor3 = Colour
	end
	UIFade.Fade(Banner, true, RoomBannerController.Settings.FadeTime)
	CombatFX.PlaySound(RoomBannerController.Settings.BannerSound, nil, 0.8)
	if Hold then
		task.delay(Hold, function()
			if BannerToken == Token then
				UIFade.Fade(Banner, false, RoomBannerController.Settings.FadeTime)
			end
		end)
	end
end

local function OnRoomEntered(Info)
	if type(Info) ~= "table" then
		return
	end
	local Settings = RoomBannerController.Settings
	local Colour = Settings.KindColours[Info.Kind]
	local Text = Info.Banner or Info.Area or ""
	AreaKind = Info.Kind

	if Info.Phase == "Countdown" then
		CountdownEndsAt = (Info.Countdown or 0) > 0 and Info.EndsAt or nil
		RoomBannerController.Show(Text, "Starting...", Colour, nil)
	elseif Info.Phase == "Start" then
		CountdownEndsAt = nil
		RoomBannerController.Show(Text, Settings.StartLines[Info.Kind] or "", Colour, GameConfig.Rooms.BannerDuration)
	elseif Info.Phase == "Cleared" then
		CountdownEndsAt = nil
		if Info.Kind == "Combat" or Info.Kind == "Boss" then
			RoomBannerController.Show(Settings.ClearedTitle, Settings.ClearedLine, Settings.KindColours.Shop, GameConfig.Rooms.BannerDuration)
			CombatFX.PlaySound(Settings.ClearedSound, nil, 1)
		end
	end
end

----------------------------------------------------------------------
-- TOASTS
----------------------------------------------------------------------

function RoomBannerController.Toast(Text: string)
	if not Toasts or not ToastTemplate or type(Text) ~= "string" then
		return
	end
	local Settings = RoomBannerController.Settings
	local Toast = ToastTemplate:Clone()
	Toast.Name = "Toast"
	Toast.LayoutOrder = math.floor(os.clock() * 100)
	local Label = Toast:FindFirstChild("Text", true)
	if Label then
		Label.Text = Text
	end
	Toast.Parent = Toasts
	UIFade.Fade(Toast, true, 0.15)

	local List = {}
	for _, Child in ipairs(Toasts:GetChildren()) do
		if Child.Name == "Toast" then
			table.insert(List, Child)
		end
	end
	if #List > Settings.MaxToasts then
		table.sort(List, function(A, B)
			return A.LayoutOrder < B.LayoutOrder
		end)
		List[1]:Destroy()
	end
	task.delay(Settings.ToastTime, function()
		if Toast.Parent then
			UIFade.Fade(Toast, false, 0.35)
			task.delay(0.4, function()
				Toast:Destroy()
			end)
		end
	end)
end

----------------------------------------------------------------------
-- RUN STATE
----------------------------------------------------------------------

local function OnRunState(Run)
	if type(Run) ~= "table" or not EndScreen then
		return
	end
	local Settings = RoomBannerController.Settings
	local Result = EndScreen:FindFirstChild("Result", true)
	local Body = EndScreen:FindFirstChild("Body", true)
	HasLobby = Run.HasLobby == true
	if Run.AreaKind then
		AreaKind = Run.AreaKind
	end
	if Run.State == "Won" or Run.State == "Lost" then
		local Won = Run.State == "Won"
		if Result then
			Result.Text = Won and "VICTORY" or "DEFEAT"
			Result.TextColor3 = Won and Settings.WinColour or Settings.LoseColour
		end
		local Lines = {}
		local Summary = Run.Summary
		local Mine = nil
		if Summary then
			if not Won and Summary.ReachedArea then
				table.insert(Lines, "Reached: " .. tostring(Summary.ReachedArea))
				table.insert(Lines, "")
			end
			for _, Entry in ipairs(Summary.Players or {}) do
				if Entry.UserId == Player.UserId then
					Mine = Entry
				end
				table.insert(Lines, string.format(Settings.PlayerLineFormat, Entry.Name, Entry.Kills or 0, Entry.Exp or 0, Entry.Cash or 0))
			end
		end
		if Body then
			Body.Text = table.concat(Lines, "\n")
		end

		AfterRun = Run.AfterRun or GameConfig.Run.AfterRun
		VoteCount, VotesNeeded = Run.Votes or 0, Run.VotesNeeded or 1
		if not EndScreen.Visible then
			-- Just ended: count the rewards up from zero.
			Voted = false
			RewardTargets.Exp = Mine and Mine.Exp or 0
			RewardTargets.Cash = Mine and Mine.Cash or 0
			RewardShownAt = os.clock()
			local LobbyButton = EndScreen:FindFirstChild("Lobby", true)
			if LobbyButton and LobbyButton:IsA("TextButton") then
				LobbyButton.Text = Settings.LobbyText
			end
			EndRestartAt = os.clock() + (Summary and Summary.EndDelay or GameConfig.Run.EndDelay)
			CombatFX.PlaySound(Won and Settings.ClearedSound or Settings.BannerSound, nil, 0.8)
		end
		EndToLobby = Summary ~= nil and Summary.ToLobby == true
		EndScreen.Visible = true
		CountdownEndsAt = nil
		RoomBannerController._RefreshEndButtons()
	else
		EndScreen.Visible = false
		EndRestartAt = nil
		Voted = false
	end
	if Run.State == "Resetting" then
		RoomBannerController.Show("New Run", "Get ready...", Settings.KindColours.Spawn, 2)
	end
end

-- Updates the Replay and Lobby buttons and the line under them.
function RoomBannerController._RefreshEndButtons()
	if not EndScreen then
		return
	end
	local Settings = RoomBannerController.Settings
	local Buttons = EndScreen:FindFirstChild("Buttons", true)
	local Status = EndScreen:FindFirstChild("Status", true)
	local Voting = AfterRun == "Vote"
	if Buttons then
		Buttons.Visible = Voting
		local Replay = Buttons:FindFirstChild("Replay")
		if Replay then
			Replay.Text = (Voted and Settings.ReplayVotedText or Settings.ReplayText) .. string.format(" (%d/%d)", VoteCount, VotesNeeded)
			Replay.AutoButtonColor = not Voted
			Replay.BackgroundTransparency = Voted and 0.4 or 0
		end
		local Lobby = Buttons:FindFirstChild("Lobby")
		if Lobby then
			Lobby.BackgroundTransparency = HasLobby and 0 or Settings.NoLobbyTransparency
			Lobby.TextTransparency = HasLobby and 0 or Settings.NoLobbyTransparency
		end
	end
	if Status and Voting then
		Status.Text = string.format(Settings.VoteFormat, VoteCount, VotesNeeded)
	end
end

-- Counts the earned EXP and cash up, eased out.
local function UpdateRewards()
	if not EndScreen or not EndScreen.Visible then
		return
	end
	local Settings = RoomBannerController.Settings
	local Rewards = EndScreen:FindFirstChild("Rewards", true)
	if not Rewards then
		return
	end
	local Alpha = math.clamp((os.clock() - RewardShownAt) / Settings.RewardCountTime, 0, 1)
	Alpha = 1 - (1 - Alpha) ^ 3
	local Exp = Rewards:FindFirstChild("Exp")
	local Cash = Rewards:FindFirstChild("Cash")
	if Exp and Exp:FindFirstChild("Value") then
		Exp.Value.Text = string.format(Settings.ExpFormat, math.floor(RewardTargets.Exp * Alpha + 0.5))
	end
	if Cash and Cash:FindFirstChild("Value") then
		Cash.Value.Text = string.format(Settings.CashFormat, math.floor(RewardTargets.Cash * Alpha + 0.5))
	end
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function RoomBannerController.Init()
	local PlayerGui = Player:WaitForChild("PlayerGui")
	Gui = PlayerGui:WaitForChild("RoomBanner", 10)
	if not Gui then
		warn("[RoomBannerController] no RoomBanner ScreenGui in StarterGui")
		return
	end
	Banner = Gui:WaitForChild("Banner")
	Title = Banner:WaitForChild("Title")
	Sub = Banner:WaitForChild("Sub")
	Toasts = Gui:WaitForChild("Toasts")
	ToastTemplate = Toasts:WaitForChild("ToastTemplate")
	Spectate = Gui:WaitForChild("Spectate")
	EndScreen = Gui:WaitForChild("EndScreen")

	-- nudge the popups down a bit so they clear the top of the hud
	local Drop = UDim2.fromScale(0, RoomBannerController.Settings.PopupDrop)
	Banner.Position += Drop
	Toasts.Position += Drop

	-- Remember the designed look, then start hidden.
	UIFade.Record(Banner)
	UIFade.Record(ToastTemplate)
	UIFade.Fade(Banner, false, 0)
	ToastTemplate.Visible = false
	Spectate.Visible = false
	EndScreen.Visible = false

	Events:WaitForChild("RoomEntered").OnClientEvent:Connect(OnRoomEntered)
	Events:WaitForChild("Notify").OnClientEvent:Connect(RoomBannerController.Toast)
	Events:WaitForChild("RunStateChanged").OnClientEvent:Connect(OnRunState)

	local Settings = RoomBannerController.Settings

	-- The way back to the lobby, shown only when there is one.
	LeaveButton = Gui:FindFirstChild("LeaveButton")
	if LeaveButton then
		LeaveButton.Visible = false
		LeaveButton.Activated:Connect(function()
			local Remote = Events:FindFirstChild("ReturnToLobby")
			if Remote then
				Remote:FireServer()
				LeaveButton.Text = "Leaving..."
				CombatFX.PlaySound("UIClick", nil, 1)
			end
		end)
	end

	-- The end screen's buttons. The server counts the votes and sends
	-- the new count back, which relabels the button.
	local EndButtons = EndScreen:FindFirstChild("Buttons", true)
	local RunVote = Events:WaitForChild("RunVote", 10)
	if EndButtons and RunVote then
		local Replay = EndButtons:FindFirstChild("Replay")
		if Replay then
			Replay.Activated:Connect(function()
				if Voted or not EndScreen.Visible then
					return
				end
				Voted = true
				CombatFX.PlaySound(Settings.TickSound, nil, 1, 1.2)
				RunVote:FireServer("Replay")
				RoomBannerController._RefreshEndButtons()
			end)
		end
		local Lobby = EndButtons:FindFirstChild("Lobby")
		if Lobby then
			Lobby.Activated:Connect(function()
				if not EndScreen.Visible then
					return
				end
				CombatFX.PlaySound(Settings.TickSound, nil, 1)
				if HasLobby then
					Lobby.Text = "Leaving..."
				end
				RunVote:FireServer("Lobby")
			end)
		end
	end

	-- Countdown, end screen timer and the spectating line, every frame.
	RunService.RenderStepped:Connect(function()
		if CountdownEndsAt then
			local Left = CountdownEndsAt - workspace:GetServerTimeNow()
			if Left > 0 then
				local Whole = math.ceil(Left)
				Sub.Text = string.format("Starting in %d", Whole)
				if Whole ~= LastTick then
					LastTick = Whole
					CombatFX.PlaySound(Settings.TickSound, nil, 0.7, 1 + (3 - math.min(Whole, 3)) * 0.15)
				end
			else
				CountdownEndsAt = nil
				LastTick = nil
			end
		end
		if LeaveButton then
			-- The end screen has its own lobby button.
			LeaveButton.Visible = HasLobby and GameConfig.Lobby.AllowEarlyLeave and not EndScreen.Visible
				and AreaKind ~= nil and Settings.LeaveAreas[AreaKind] == true
		end
		UpdateRewards()
		-- Without voting the run restarts on its own after a countdown.
		if EndRestartAt and AfterRun ~= "Vote" then
			local Status = EndScreen:FindFirstChild("Status", true)
			if Status then
				local Left = math.max(0, math.ceil(EndRestartAt - os.clock()))
				Status.Text = EndToLobby and string.format("Back to the lobby in %d", Left) or string.format("New run in %d", Left)
			end
		end
		local Character = Player.Character
		Spectate.Visible = Character ~= nil and Character:GetAttribute("Spectating") == true and not EndScreen.Visible
	end)

	-- A client that loaded late still gets the current area's banner.
	task.spawn(function()
		local GetRunState = Functions:WaitForChild("GetRunState", 10)
		if not GetRunState then
			return
		end
		local Ok, Run = pcall(GetRunState.InvokeServer, GetRunState)
		if Ok and type(Run) == "table" then
			HasLobby = Run.HasLobby == true
			OnRunState(Run)
			if Run.Area and Run.State == "Playing" then
				OnRoomEntered({ Area = Run.Area, Kind = Run.AreaKind, Banner = Run.Area, Phase = "Start" })
			end
		end
	end)
end

return RoomBannerController
