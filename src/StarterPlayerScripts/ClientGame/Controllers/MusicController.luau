--[[
	MusicController

	The soundtrack. It follows the run and crossfades between tracks so
	the music always matches what is happening:

	  Spawn and shops     a calm track
	  a fight starting    a combat track, a different one each room
	  the boss            the boss track, after a short sting
	  an area cleared     back to calm
	  the run won / lost  the music stops for a victory or defeat sting

	Every track is a Sound in SoundService.Music (built in the editor),
	played only on this client, so each player hears their own music
	and nothing is replicated.
]]

--[[
	What connects to this

	Listens on:
	  ReplicatedStorage.Remotes.Events.RoomEntered for the area and its
	  phase (Countdown, Start, Cleared), sent by
	  Server.Game.Rooms.RoomManager.
	  ReplicatedStorage.Remotes.Events.RunStateChanged for the run being
	  won, lost or reset, sent by Server.Game.Core.RunManager.

	Asks:
	  ReplicatedStorage.Remotes.Functions.GetRunState on start, so a
	  player who joins mid run hears the right track.

	Plays:
	  SoundService.Music.Calm, Combat1 to Combat4, Boss, BossIntro,
	  Victory and Defeat. Their volume in the editor is each track's
	  full volume, and SoundService.MusicGroup is the overall music
	  volume.

	Started by:
	  ClientGame.ClientMain.
]]

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")
local Functions = Remotes:WaitForChild("Functions")

local MusicController = {}

MusicController.Settings = {
	-- Seconds a crossfade takes.
	FadeTime = 1.5,
	-- Tracks for fights, cycled through one per room. All of them are
	-- loud and busy the whole way through (no quiet intros or breaks),
	-- so a fight never sounds like the shop.
	CombatTracks = { "Combat1", "Combat2", "Combat3", "Combat4" },
	CalmTrack = "Calm",
	BossTrack = "Boss",
	BossIntro = "BossIntro",
	VictorySting = "Victory",
	DefeatSting = "Defeat",
}

local Folder: Instance? = nil
local Current: Sound? = nil
local CurrentName: string? = nil
local BaseVolume: { [Sound]: number } = {}
local CombatIndex = 0
local LastCombatArea: string? = nil

----------------------------------------------------------------------
-- PLAYING
----------------------------------------------------------------------

local function Track(Name: string): Sound?
	local Sound = Folder and Folder:FindFirstChild(Name)
	if Sound and Sound:IsA("Sound") then
		if not BaseVolume[Sound] then
			BaseVolume[Sound] = Sound.Volume
		end
		-- music goes through MusicGroup so the player's music volume reaches it
		if not Sound.SoundGroup then
			Sound.SoundGroup = SoundService:FindFirstChild("MusicGroup")
		end
		return Sound
	end
	return nil
end

local function FadeOut(Sound: Sound)
	local Tween = TweenService:Create(Sound, TweenInfo.new(MusicController.Settings.FadeTime), { Volume = 0 })
	Tween:Play()
	Tween.Completed:Once(function()
		if Sound ~= Current then
			Sound:Stop()
		end
	end)
end

-- Crossfades to a looping track. Playing the one already on does
-- nothing, so the same track carries on through a room.
function MusicController.Play(Name: string?)
	if Name == CurrentName then
		return
	end
	local Old = Current
	local New = Name and Track(Name) or nil
	Current = New
	CurrentName = Name
	if Old then
		FadeOut(Old)
	end
	if New then
		New.Volume = 0
		if not New.IsPlaying then
			New.TimePosition = 0
			New:Play()
		end
		TweenService:Create(New, TweenInfo.new(MusicController.Settings.FadeTime), { Volume = BaseVolume[New] }):Play()
	end
end

-- Fades out any sting still playing, so a victory or defeat sting
-- does not carry on over the next run.
local ActiveSting: Sound? = nil
function MusicController.StopSting()
	local Sting = ActiveSting
	ActiveSting = nil
	if Sting and Sting.IsPlaying then
		local Tween = TweenService:Create(Sting, TweenInfo.new(MusicController.Settings.FadeTime / 2), { Volume = 0 })
		Tween:Play()
		Tween.Completed:Once(function()
			if Sting ~= ActiveSting then
				Sting:Stop()
			end
		end)
	end
end

-- Plays a one off sting over nothing, then optionally a track after.
function MusicController.Sting(Name: string, After: string?)
	MusicController.Play(nil)
	MusicController.StopSting()
	local Sting = Track(Name)
	if not Sting then
		if After then
			MusicController.Play(After)
		end
		return
	end
	Sting.Volume = BaseVolume[Sting]
	Sting.TimePosition = 0
	Sting:Play()
	ActiveSting = Sting
	if After then
		local Length = Sting.TimeLength > 0 and Sting.TimeLength or 4
		task.delay(math.min(Length, 8) * 0.8, function()
			if CurrentName == nil then
				MusicController.Play(After)
			end
		end)
	end
end

----------------------------------------------------------------------
-- FOLLOWING THE RUN
----------------------------------------------------------------------

-- Every fight track in the Music folder: the listed ones plus any Sound
-- named Combat followed by a number (Combat5, Combat6...), so a new
-- track only has to be dropped in.
local function CombatTracks(): { string }
	local List = table.clone(MusicController.Settings.CombatTracks)
	if Folder then
		for _, Child in ipairs(Folder:GetChildren()) do
			if Child:IsA("Sound") and string.match(Child.Name, "^Combat%d+$") and not table.find(List, Child.Name) then
				table.insert(List, Child.Name)
			end
		end
	end
	return List
end

-- the fight tracks in a shuffled order, so a run does not always play them the same way round
local Order: { string } = {}

local function NextCombatTrack(Area: string?): string
	if Area ~= LastCombatArea then
		LastCombatArea = Area
		CombatIndex += 1
		if CombatIndex > #Order then
			local Last = Order[#Order]
			Order = CombatTracks()
			for Index = #Order, 2, -1 do
				local Swap = math.random(Index)
				Order[Index], Order[Swap] = Order[Swap], Order[Index]
			end
			-- never the same track twice in a row across a reshuffle
			if #Order > 1 and Order[1] == Last then
				Order[1], Order[2] = Order[2], Order[1]
			end
			CombatIndex = 1
		end
	end
	return Order[math.max(CombatIndex, 1)] or MusicController.Settings.CombatTracks[1]
end

local function OnRoomEntered(Info)
	if type(Info) ~= "table" then
		return
	end
	local Settings = MusicController.Settings
	local Kind = Info.Kind
	if Info.Phase == "Cleared" then
		MusicController.Play(Settings.CalmTrack)
	elseif Kind == "Boss" then
		if Info.Phase == "Countdown" then
			MusicController.Sting(Settings.BossIntro, Settings.BossTrack)
		elseif CurrentName ~= Settings.BossTrack then
			MusicController.Play(Settings.BossTrack)
		end
	elseif Kind == "Combat" then
		MusicController.Play(NextCombatTrack(Info.Area))
	else
		MusicController.Play(Settings.CalmTrack)
	end
end

local function OnRunState(Run)
	if type(Run) ~= "table" then
		return
	end
	local Settings = MusicController.Settings
	if Run.State == "Won" then
		MusicController.Sting(Settings.VictorySting, nil)
	elseif Run.State == "Lost" then
		MusicController.Sting(Settings.DefeatSting, nil)
	elseif Run.State == "Resetting" then
		LastCombatArea = nil
		MusicController.StopSting()
		MusicController.Play(Settings.CalmTrack)
	end
end

function MusicController.Init()
	Folder = SoundService:WaitForChild("Music", 10)
	if not Folder then
		warn("[MusicController] no SoundService.Music folder, there will be no music")
		return
	end
	Events:WaitForChild("RoomEntered").OnClientEvent:Connect(OnRoomEntered)
	Events:WaitForChild("RunStateChanged").OnClientEvent:Connect(OnRunState)

	-- Start on the right track for where the run is.
	task.spawn(function()
		local GetRunState = Functions:WaitForChild("GetRunState", 10)
		local Ok, Run = false, nil
		if GetRunState then
			Ok, Run = pcall(GetRunState.InvokeServer, GetRunState)
		end
		if CurrentName ~= nil then
			return
		end
		if Ok and type(Run) == "table" and Run.State == "Playing" and Run.Area then
			OnRoomEntered({ Area = Run.Area, Kind = Run.AreaKind, Phase = Run.AreaPhase == "Cleared" and "Cleared" or "Start" })
		else
			MusicController.Play(MusicController.Settings.CalmTrack)
		end
	end)
end

return MusicController
