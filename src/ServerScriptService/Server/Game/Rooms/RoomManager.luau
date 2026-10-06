--[[
	RoomManager

	Runs the progression through the map, one area at a time. It walks
	the area order in Game.Data.RoomData, waits to be told a player has
	entered the next area, starts that area, and decides when the gate
	out of it opens.

	The entry flow is deliberately two stages, so nobody gets yanked out
	of a fight and nobody gets left behind a shut gate:

	  1. The area is cleared, so GateController opens the gate out of it
	     and turns it yellow.
	  2. RoomZones reports the first living player has entered the next
	     area. That starts a short countdown, shown on the banner.
	  3. When the countdown ends, any player still behind is placed at
	     the PlayerSpawns of the new area, the gate behind them is closed
	     and locked, the yellow highlight goes off, and wave 1 starts.

	The countdown is what makes this work in multiplayer. Starting the
	moment one player crosses would drag the other three out of whatever
	they were doing, and waiting for all four would let one player who is
	away from their keyboard stall the whole run. A fixed countdown gives
	stragglers a moment and cannot be stalled. It does not reset if the
	player who triggered it walks back out, because that would let one
	person hold the run up forever.

	This is also where CheckRoomClear from the function plan lives, in
	the form of WaveManager's cleared callback: an area is clear when the
	last wave of it is dead.

	Spawn and the shops have no waves. Their gate opens on a proximity
	prompt, so the players leave when they are ready.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.RoomData for the area order, the gates and which areas
	  are spawn, combat, shop or boss.
	  Game.Data.WaveData for the banner text of combat areas.
	  Game.Config.GameConfig.Rooms for the countdown and gate delay.

	Listens to:
	  Server.Game.Rooms.RoomZones.Entered, which tells it when a player
	  enters an area. This module never checks positions itself.

	Talks to:
	  Server.Game.Rooms.GateController to open, close, prompt and
	  highlight gates.
	  Server.Game.Rooms.WaveManager to run a combat area's waves and be
	  told when it is clear.
	  Server.Game.Shop.ShopManager to stock Shop1 or Shop2 when the run
	  reaches it.
	  Server.Game.Core.PlayerStats to check a player is alive before
	  counting them for the entry trigger, since a dead player waiting
	  for the team should not start the next room.

	Signals (BindableEvents), so RunManager can listen without the two
	modules requiring each other:
	  AreaStarted(AreaName, Area)   an area has begun
	  AreaCleared(AreaName, Area)   a combat area's last wave died
	  RunWon()                      the IsRunEnd area was cleared

	Placing players forward:
	  PlacePlayer uses workspace.MainGameObj.PlayerSpawns.<AreaName> and
	  spreads players across the pad rather than stacking them. It
	  clears their velocity with HelperFunctions.clearVelocity and moves
	  them through AntiCheat.Teleport, so a player who was dashing does
	  not arrive still moving and the anti cheat does not flag it.

	Sends:
	  ReplicatedStorage.Remotes.Events.RoomEntered with a table
	  { Area, Kind, Banner, Phase, Countdown, EndsAt } for
	  ClientGame.Controllers.RoomBannerController. Phase is "Countdown"
	  when the timer starts, "Start" when the area begins and "Cleared"
	  when its gate opens.
	  ReplicatedStorage.Remotes.Events.Notify for short messages, such as
	  a prompt gate waiting for the rest of the team.

	Each area only starts once. RoomZones reports every move, so the
	area is marked started and further reports for it are ignored.

	A player who dies during a countdown, or leaves the game, does not
	stop it finishing. Only living connected players can trigger it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local RoomData = require(ReplicatedStorage.Modules.Game.Data.RoomData)
local WaveData = require(ReplicatedStorage.Modules.Game.Data.WaveData)
local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local AntiCheat = require(ServerScriptService.Server.Modules.AntiCheat)
local PlayerStats = require(script.Parent.Parent.Core.PlayerStats)
local RoomZones = require(script.Parent.RoomZones)
local GateController = require(script.Parent.GateController)
local WaveManager = require(script.Parent.WaveManager)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoomEntered = Remotes.Events:WaitForChild("RoomEntered")
local Notify = Remotes.Events:WaitForChild("Notify")

local RoomManager = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

RoomManager.Settings = {
	-- Studs above a spawn pad players are placed at.
	PlaceHeight = 3,
	-- Studs between players placed on the same pad.
	PlaceSpacing = 6,
	-- Countdown used when entering a shop. Shops have nothing to get
	-- ready for, so this is shorter than the combat countdown.
	ShopCountdown = 1,
}

RoomManager.AreaStarted = Instance.new("BindableEvent")
RoomManager.AreaCleared = Instance.new("BindableEvent")
RoomManager.RunWon = Instance.new("BindableEvent")

-- The run's progress through the map.
local State = {
	Index = 0,
	-- "Idle" before a run, "Countdown" while entering an area, "Active"
	-- while it is being played, "Cleared" once its gate out is open.
	Phase = "Idle",
	-- The index of the area the open gate leads to, which a player
	-- entering will start.
	Armed = nil :: number?,
	Started = {} :: { [string]: boolean },
	Generation = 0,
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

local function IsLiving(Player: Player): boolean
	local Stats = PlayerStats.Get(Player)
	local Character = Player.Character
	return Stats ~= nil and Stats:IsAlive() and Character ~= nil and not Character:GetAttribute("Spectating")
end

local function BannerFor(Area): string
	if Area.Banner then
		return Area.Banner
	end
	local Waves = WaveData.Areas[Area.Name]
	return Waves and Waves.Banner or Area.Name
end

local function Send(Area, Phase: string, Extra: { [string]: any }?)
	local Payload = {
		Area = Area.Name,
		Kind = Area.Kind,
		Banner = BannerFor(Area),
		Phase = Phase,
	}
	if Extra then
		for Key, Value in pairs(Extra) do
			Payload[Key] = Value
		end
	end
	RoomEntered:FireAllClients(Payload)
end

-- Sends a short on screen message to one player, or everyone.
function RoomManager.Notify(Player: Player?, Text: string)
	if Player then
		Notify:FireClient(Player, Text)
	else
		Notify:FireAllClients(Text)
	end
end

-- The spawn pads for an area.
local function SpawnPads(AreaName: string): { BasePart }
	local Folder = RoomData.GetFolder("PlayerSpawns")
	local AreaFolder = Folder and Folder:FindFirstChild(AreaName)
	local Pads = {}
	if AreaFolder then
		for _, Child in ipairs(AreaFolder:GetDescendants()) do
			if Child:IsA("BasePart") then
				table.insert(Pads, Child)
			end
		end
	end
	return Pads
end

-- Moves a player to an area's spawn pad, facing the way out. Index
-- spreads several players across the pad.
function RoomManager.PlacePlayer(Player: Player, AreaName: string, Index: number?)
	local Character = Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	if not Root then
		return
	end
	local Pads = SpawnPads(AreaName)
	if #Pads == 0 then
		warn("[RoomManager] no PlayerSpawns for " .. AreaName)
		return
	end
	Index = Index or 1
	local Pad = Pads[(Index - 1) % #Pads + 1]
	local Spacing = RoomManager.Settings.PlaceSpacing
	local Slot = math.floor((Index - 1) / #Pads)
	local Offset = Vector3.new((Slot % 2) * Spacing - Spacing / 2, 0, math.floor(Slot / 2) * Spacing - Spacing / 2)
	if Slot == 0 then
		Offset = Vector3.zero
	end
	local Position = Pad.Position + Vector3.new(0, Pad.Size.Y / 2 + RoomManager.Settings.PlaceHeight, 0) + Offset

	-- Face the gate out if there is one, otherwise keep facing.
	local Area = RoomData.GetArea(AreaName)
	local Facing = Root.CFrame.LookVector
	local GatePosition = Area and Area.GateOut and GateController.GetPosition(Area.GateOut)
	if GatePosition then
		local Flat = (GatePosition - Position) * Vector3.new(1, 0, 1)
		if Flat.Magnitude > 1 then
			Facing = Flat.Unit
		end
	end

	local Target = CFrame.lookAt(Position, Position + Facing)
	HelperFunctions.clearVelocity(Root)
	-- The server move keeps the anti cheat's record right, but the
	-- player's client owns its character's physics and can overwrite a
	-- server set CFrame, so the client is told to move itself as well.
	AntiCheat.Teleport(Player, Target)
	CombatFX.SendTo(Player, "PlaceAt", nil, { CFrame = Target })
	RoomZones.SetArea(Player, AreaName)
end

----------------------------------------------------------------------
-- GATES OUT
----------------------------------------------------------------------

local function OpenExit(Index: number)
	local Area = RoomData.Areas[Index]
	if not Area or not Area.GateOut then
		return
	end
	GateController.Open(Area.GateOut, Area.Name)
	GateController.SetHighlight(Area.GateOut, true)
	State.Phase = "Cleared"
	State.Armed = Index + 1
	Send(Area, "Cleared")
end

-- The prompt callback for Spawn and the shops. Checks the run is in
-- this area and, if the setting says so, that the whole team is at
-- the gate.
local function OnPrompt(Index: number, Player: Player)
	local Area = RoomData.Areas[Index]
	if State.Index ~= Index or State.Phase ~= "Active" then
		return
	end
	if not IsLiving(Player) then
		return
	end
	local Settings = RoomData.GetGateSettings(Area.Name)
	if Settings.PromptNeedsEveryone then
		local GatePosition = GateController.GetPosition(Area.GateOut)
		local Missing = 0
		for _, Other in ipairs(Players:GetPlayers()) do
			local Root = Other.Character and Other.Character:FindFirstChild("HumanoidRootPart")
			if IsLiving(Other) and Root and GatePosition and (Root.Position - GatePosition).Magnitude > Settings.PromptRadius then
				Missing += 1
			end
		end
		if Missing > 0 then
			RoomManager.Notify(Player, string.format("Waiting for %d more player%s at the gate", Missing, Missing == 1 and "" or "s"))
			return
		end
	end
	OpenExit(Index)
end

-- Sets up how an area's gate out opens.
local function SetupExit(Index: number)
	local Area = RoomData.Areas[Index]
	if not Area.GateOut then
		return
	end
	if Area.OpenRule == "Prompt" then
		GateController.AddPrompt(Area.GateOut, Area.Name, function(Player)
			OnPrompt(Index, Player)
		end)
		GateController.SetHighlight(Area.GateOut, true)
	elseif Area.OpenRule == "Timer" then
		local Generation = State.Generation
		task.delay(Area.OpenAfter or 10, function()
			if State.Generation == Generation and State.Index == Index then
				OpenExit(Index)
			end
		end)
	end
	-- "Clear" opens from the WaveManager callback, "Never" stays shut.
end

----------------------------------------------------------------------
-- AREAS
----------------------------------------------------------------------

local function OnCleared(Index: number)
	local Area = RoomData.Areas[Index]
	local Generation = State.Generation
	RoomManager.AreaCleared:Fire(Area.Name, Area)
	if Area.IsRunEnd then
		State.Phase = "Cleared"
		RoomManager.RunWon:Fire()
		return
	end
	task.delay(GameConfig.Rooms.GateOpenDelay, function()
		if State.Generation == Generation and State.Index == Index then
			OpenExit(Index)
		end
	end)
end

-- Starts an area: waves for combat, stock for a shop, a prompt for
-- spawn.
local function BeginArea(Index: number)
	local Area = RoomData.Areas[Index]
	State.Index = Index
	State.Phase = "Active"
	State.Armed = nil
	State.Started[Area.Name] = true

	Send(Area, "Start")
	RoomManager.AreaStarted:Fire(Area.Name, Area)

	if Area.Kind == "Combat" or Area.Kind == "Boss" then
		WaveManager.Start(Area.Name, function()
			OnCleared(Index)
		end)
	elseif Area.Kind == "Shop" then
		local Ok, ShopManager = pcall(require, script.Parent.Parent.Shop.ShopManager)
		if Ok and type(ShopManager) == "table" and ShopManager.StockShop then
			ShopManager.StockShop(Area.Name)
		end
	end
	SetupExit(Index)
end

-- The first living player has walked into the next area.
local function StartCountdown(Index: number)
	local Area = RoomData.Areas[Index]
	if State.Started[Area.Name] then
		return
	end
	State.Started[Area.Name] = true
	State.Phase = "Countdown"
	State.Armed = nil
	local Generation = State.Generation

	local Countdown = GameConfig.Rooms.EntryCountdown
	if Area.Kind == "Shop" then
		Countdown = RoomManager.Settings.ShopCountdown
	end
	if GameConfig.Debug.SkipCountdown then
		Countdown = 0
	end
	Send(Area, "Countdown", { Countdown = Countdown, EndsAt = workspace:GetServerTimeNow() + Countdown })

	task.delay(Countdown, function()
		if State.Generation ~= Generation then
			return
		end
		-- Pull everyone still behind, living or spectating, forward.
		-- Where they actually stand right now is checked, not the last
		-- area they were seen in, so someone who stepped in and then
		-- ran straight back out is still brought through.
		local Placed = 0
		for _, Player in ipairs(Players:GetPlayers()) do
			local Root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
			local Inside = Root ~= nil and RoomZones.IsPointInArea(Root.Position, Area.Name)
			if not Inside then
				Placed += 1
				RoomManager.PlacePlayer(Player, Area.Name, Placed)
			end
		end
		if Area.GateIn then
			GateController.SetHighlight(Area.GateIn, false)
			if GameConfig.Rooms.CloseGateBehind then
				GateController.Close(Area.GateIn)
			end
		end
		BeginArea(Index)
	end)
end

local function OnPlayerEntered(Player: Player, AreaName: string, OldArea: string?)
	if not State.Armed then
		return
	end
	local Next = RoomData.Areas[State.Armed]
	if not Next or Next.Name ~= AreaName then
		return
	end
	if not IsLiving(Player) then
		return
	end
	StartCountdown(State.Armed)
end

----------------------------------------------------------------------
-- RUN
----------------------------------------------------------------------

-- Resets every gate and starts the progression from the first area.
-- Called by RunManager at the start of each run.
function RoomManager.Start()
	RoomManager.Reset()
	BeginArea(1)
end

-- Stops everything and shuts every gate, for a run ending.
function RoomManager.Reset()
	State.Generation += 1
	State.Index = 0
	State.Phase = "Idle"
	State.Armed = nil
	State.Started = {}
	WaveManager.Stop()
	GateController.ResetAll()
	local Ok, ShopManager = pcall(require, script.Parent.Parent.Shop.ShopManager)
	if Ok and type(ShopManager) == "table" and ShopManager.ClearAll then
		ShopManager.ClearAll()
	end
end

-- The area the run is in and what it is doing, for a late joiner.
function RoomManager.GetState()
	local Area = RoomData.Areas[State.Index]
	return {
		Area = Area and Area.Name or nil,
		Kind = Area and Area.Kind or nil,
		Banner = Area and BannerFor(Area) or nil,
		Phase = State.Phase,
		Index = State.Index,
	}
end

function RoomManager.GetCurrentArea(): string?
	local Area = RoomData.Areas[State.Index]
	return Area and Area.Name or nil
end

function RoomManager.GetCurrentIndex(): number
	return State.Index
end

function RoomManager.Init()
	RoomZones.Entered.Event:Connect(OnPlayerEntered)
end

return RoomManager
