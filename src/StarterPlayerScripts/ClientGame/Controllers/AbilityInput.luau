--[[
	AbilityInput

	Handles the key press for the player's equipped ability (E) and sends
	the request up, plus the key that swaps between their two abilities
	(G). It also drives the cooldown sweeps on the HUD and dims an
	ability when the player does not have the energy for it, so the
	player can see why nothing happened.

	Like CombatInput it does a local check first, but only to avoid
	sending a request the server would reject. The real energy and
	cooldown checks are in Server.Game.Combat.Abilities.AbilityBase.

	For Teleport it also has to send the cursor position, since that is
	the whole input for the ability.

	For Stun Slam it also moves the character, because the character is
	owned by this client and moving it here is instant. The server
	sends the numbers back with its acceptance and watches for the
	landing itself.
]]

--[[
	What connects to this

	Sends to:
	  ReplicatedStorage.Remotes.Events.AbilityUsed with
	  (AbilityName, AimPosition), received by
	  Server.Game.Combat.CombatService.
	  ReplicatedStorage.Remotes.Events.LoadoutSwap with ("Ability",
	  nil), passed on to Server.Game.Core.Loadout.

	Listens on:
	  AbilityUsed coming back down with (AbilityName, Accepted,
	  Cooldown, ClientData), which is how AbilityBase confirms the
	  ability fired or tells the client it was rejected so the sweep
	  can be cancelled.
	  ReplicatedStorage.Remotes.Events.LoadoutChanged for which ability
	  is equipped and the cooldown left on each.

	Reads:
	  Game.Data.AbilityData for the energy costs and cooldowns of both
	  of the player's abilities.
	  The player's Energy attribute, mirrored by PlayerStats, for the
	  local affordability check.

	Uses:
	  ClientGame.Controllers.HUDController for the sweeps and slot
	  state.
	  Game.Shared.CombatFX for the local animation.
	  ReplicatedStorage.Modules.Shared.HelperFunctions for the slam
	  movement, the same helpers the dash uses.

	Started by:
	  ClientGame.ClientMain, which also hands it every new character.

	The keybinds live in Game.Data.AbilityData.Keybinds. Mobile buttons
	are not wired yet, StarterGui.MOBILE_BUTTONS has the pattern for
	when they are.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local AbilityData = require(ReplicatedStorage.Modules.Game.Data.AbilityData)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local HUDController = require(script.Parent.HUDController)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local Player = Players.LocalPlayer

local AbilityInput = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

AbilityInput.Settings = {
	AimRayLength = 1000,
	UIOpenAttribute = "UIOpen",
	StunnedAttribute = "Stunned",
	-- Shortest gap between two ability swaps, inside the rate the
	-- server accepts them at (CombatService.Settings.SwapRate).
	MinSwapGap = 0.13,
	-- Attribute the movement framework checks before letting the
	-- player jump. Set while slamming.
	BusyAttribute = "busy",
	-- The slam: how long the hop pushes up before the drive down
	-- starts, and how long after landing the player is held still.
	StunSlam = {
		HopTime = 0.12,
		-- Seconds the downward push can last at most, in case the
		-- landing is never seen.
		MaxDriveTime = 4,
		-- Seconds between landing checks.
		PollRate = 0.03,
	},
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local Character: Model? = nil
local Snapshot = nil
local CooldownEndsAt = { 0, 0 }
local CooldownLength = { 0, 0 }
local SlamActive = false

-- Targeting mode for abilities with Targeting = true (Teleport): the
-- ghost following the cursor, and when the click that used it
-- happened so CombatInput can ignore that same click.
local Targeting: { Index: number, Name: string, Data: any, Ghost: Model, Position: Vector3, Valid: boolean }? = nil
local TargetingConnection: RBXScriptConnection? = nil
local LastConsumedClick = 0

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function NameOf(Index: number): string?
	return Snapshot and Snapshot.Abilities[Index] or nil
end

local function DataOf(Index: number)
	local Name = NameOf(Index)
	return Name and AbilityData.Abilities[Name] or nil
end

local function SlotName(Index: number): string
	return Index == 1 and AbilityData.Hotbar.Slot1 or AbilityData.Hotbar.Slot2
end

local function RefreshSweep(Index: number)
	local Remaining = CooldownEndsAt[Index] - os.clock()
	if Remaining > 0 then
		HUDController.StartCooldown(SlotName(Index), CooldownLength[Index], Remaining)
	else
		HUDController.ClearCooldown(SlotName(Index))
	end
end

local function SetCooldown(Index: number, Length: number, Remaining: number?)
	CooldownLength[Index] = Length
	CooldownEndsAt[Index] = os.clock() + (Remaining or Length)
	RefreshSweep(Index)
end

-- The cursor ray passes through every character, enemy and effect, so
-- pointing at a player or a Noob aims at the floor behind them rather
-- than stopping on their body.
local function AimExclusions(): { Instance }
	local List: { Instance } = { workspace.CurrentCamera }
	for _, Name in ipairs({ "Effects", "Runtime", "ClientFX" }) do
		local Folder = workspace:FindFirstChild(Name)
		if Folder then
			table.insert(List, Folder)
		end
	end
	for _, Other in ipairs(Players:GetPlayers()) do
		if Other.Character then
			table.insert(List, Other.Character)
		end
	end
	return List
end

local function GetAimPosition(): Vector3
	local Camera = workspace.CurrentCamera
	local Mouse = UserInputService:GetMouseLocation()
	local Ray = Camera:ViewportPointToRay(Mouse.X, Mouse.Y)
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = AimExclusions()
	local Length = AbilityInput.Settings.AimRayLength
	local Result = workspace:Raycast(Ray.Origin, Ray.Direction * Length, Params)
	return Result and Result.Position or (Ray.Origin + Ray.Direction * Length)
end

local function CanUseNow(Index: number): boolean
	if not Snapshot or not Character then
		return false
	end
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Humanoid.Health <= 0 then
		return false
	end
	if Player:GetAttribute(AbilityInput.Settings.UIOpenAttribute) then
		return false
	end
	if Character:GetAttribute(AbilityInput.Settings.StunnedAttribute) or Character:GetAttribute("Spectating") then
		return false
	end
	local Data = DataOf(Index)
	if not Data then
		return false
	end
	if not GameConfig.Debug.FreeAbilities then
		if os.clock() < CooldownEndsAt[Index] then
			return false
		end
		local Energy = Player:GetAttribute("Energy")
		if type(Energy) == "number" and Energy < Data.EnergyCost then
			return false
		end
	end
	if not AbilityData.Shared.AllowInAir and Humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	return true
end

-- Sends the request for an ability at a position. The optimistic
-- sweep and wind up pose happen here, the effect itself waits for the
-- server.
local function Send(Index: number, Name: string, Data, Position: Vector3)
	SetCooldown(Index, math.max(Data.Cooldown, 0.1))
	if Name == "StunSlam" then
		CombatFX.Play("StunSlam_Jump", Character, nil)
	end
	Events.AbilityUsed:FireServer(Name, Position)
end

----------------------------------------------------------------------
-- TARGETING
----------------------------------------------------------------------

local function CancelTargeting()
	if TargetingConnection then
		TargetingConnection:Disconnect()
		TargetingConnection = nil
	end
	if Targeting then
		if Targeting.Ghost then
			Targeting.Ghost:Destroy()
		end
		Targeting = nil
	end
end

-- A see through copy of the character to show where it will land.
local function BuildGhost(Data): Model?
	if not Character then
		return nil
	end
	local WasArchivable = Character.Archivable
	Character.Archivable = true
	local Ghost = Character:Clone()
	Character.Archivable = WasArchivable
	if not Ghost then
		return nil
	end
	Ghost.Name = "TeleportGhost"
	for _, Item in ipairs(Ghost:GetDescendants()) do
		if Item:IsA("BaseScript") or Item:IsA("Sound") or Item:IsA("BillboardGui") or Item:IsA("ParticleEmitter") or Item:IsA("Trail") or Item:IsA("Decal") then
			Item:Destroy()
		elseif Item:IsA("BasePart") then
			Item.Anchored = true
			Item.CanCollide = false
			Item.CanQuery = false
			Item.CanTouch = false
			Item.CastShadow = false
			Item.Material = Enum.Material.Neon
			Item.Color = Data.GhostColour
			-- The root is an invisible box on a real character, keep it so.
			Item.Transparency = Item.Name == "HumanoidRootPart" and 1 or Data.GhostTransparency
		end
	end
	-- An outline round the whole body, so it reads clearly against
	-- anything behind it.
	local Outline = Instance.new("Highlight")
	Outline.Name = "GhostOutline"
	Outline.FillColor = Data.GhostColour
	Outline.FillTransparency = Data.GhostFillTransparency or 0.7
	Outline.OutlineColor = Data.GhostColour
	Outline.OutlineTransparency = 0
	Outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	Outline.Parent = Ghost
	local Humanoid = Ghost:FindFirstChildOfClass("Humanoid")
	if Humanoid then
		Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	Ghost.Parent = workspace:FindFirstChild("Effects") or workspace
	return Ghost
end

-- Where the ghost should stand for the current cursor, and whether
-- the map is in the way. Mirrors the server's clamp so what you see
-- is where you go.
local function TargetPosition(Data): (Vector3, boolean)
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	if not Root then
		return Vector3.zero, false
	end
	local Aim = GetAimPosition()
	local Offset = Aim - Root.Position
	if Offset.Magnitude > Data.MaxDistance then
		Offset = Offset.Unit * Data.MaxDistance
	end
	local Destination = Root.Position + Offset
	local Valid = true
	if Data.RequireLineOfSight then
		local Params = RaycastParams.new()
		Params.FilterType = Enum.RaycastFilterType.Exclude
		local Exclude = { Character, workspace:FindFirstChild("Effects"), workspace:FindFirstChild("Runtime"), workspace.CurrentCamera }
		for _, Other in ipairs(Players:GetPlayers()) do
			if Other.Character then
				table.insert(Exclude, Other.Character)
			end
		end
		Params.FilterDescendantsInstances = Exclude
		local Result = workspace:Raycast(Root.Position, Destination - Root.Position, Params)
		if Result then
			Valid = false
			local Back = Root.Position - Result.Position
			Back = Back.Magnitude > 0.01 and Back.Unit or Vector3.zero
			Destination = Result.Position + Back * 2
		end
	end
	return Destination + Vector3.new(0, Data.ArrivalHeightOffset or 0, 0), Valid
end

local function StartTargeting(Index: number, Name: string, Data)
	CancelTargeting()
	local Ghost = BuildGhost(Data)
	if not Ghost then
		return
	end
	Targeting = { Index = Index, Name = Name, Data = Data, Ghost = Ghost, Position = Vector3.zero, Valid = true }

	local RunService = game:GetService("RunService")
	TargetingConnection = RunService.RenderStepped:Connect(function()
		if not Targeting or not Character or not Character.Parent then
			CancelTargeting()
			return
		end
		local Root = Character:FindFirstChild("HumanoidRootPart")
		if not Root then
			return
		end
		local Position, Valid = TargetPosition(Data)
		Targeting.Position = Position
		if Valid ~= Targeting.Valid then
			Targeting.Valid = Valid
			local Colour = Valid and Data.GhostColour or Data.GhostBlockedColour
			for _, Item in ipairs(Ghost:GetDescendants()) do
				if Item:IsA("BasePart") then
					Item.Color = Colour
				elseif Item:IsA("Highlight") then
					Item.FillColor = Colour
					Item.OutlineColor = Colour
				end
			end
		end
		Ghost:PivotTo(Root.CFrame.Rotation + Position)
	end)
end

-- The click that confirms a targeted ability.
local function ConfirmTargeting()
	if not Targeting then
		return
	end
	local Index, Name, Data, Position = Targeting.Index, Targeting.Name, Targeting.Data, Targeting.Position
	LastConsumedClick = os.clock()
	CancelTargeting()
	if not CanUseNow(Index) then
		return
	end
	Send(Index, Name, Data, Position)
end

-- Casts the ability in a slot (1 or 2), the equipped one. A targeted
-- ability (Teleport) shows its ghost instead, and the click fires it.
-- Pressing the key again puts the ghost away with nothing spent.
local function TryUse(Index: number)
	local Data = DataOf(Index)
	local Name = NameOf(Index)
	if not Data or not Name then
		return
	end

	if Data.Targeting then
		if Targeting then
			local Same = Targeting.Index == Index
			CancelTargeting()
			if Same then
				return
			end
		end
		if not CanUseNow(Index) then
			CombatFX.PlaySound("UIClick", nil, 0.4, 0.7)
			return
		end
		StartTargeting(Index, Name, Data)
		return
	end

	if not CanUseNow(Index) then
		-- A dull click, so a press that did nothing is still noticed.
		CombatFX.PlaySound("UIClick", nil, 0.4, 0.7)
		return
	end
	CancelTargeting()
	Send(Index, Name, Data, GetAimPosition())
end

----------------------------------------------------------------------
-- STUN SLAM MOVEMENT
----------------------------------------------------------------------

-- Hops the character up, then drives it down until it lands. The
-- numbers come from the server's acceptance so a modified client
-- cannot change the ability by editing this file.
local function PerformStunSlam(Data)
	if SlamActive or not Character then
		return
	end
	local Root = Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Root or not Humanoid then
		return
	end
	SlamActive = true
	local Settings = AbilityInput.Settings.StunSlam
	Character:SetAttribute(AbilityInput.Settings.BusyAttribute, true)

	task.spawn(function()
		local HopHeight = Data.GroundHopHeight or 0
		local SlamSpeed = Data.SlamSpeed or 120
		local YForce = Vector3.new(0, 1e6, 0)

		if HopHeight > 0 and Humanoid.FloorMaterial ~= Enum.Material.Air then
			-- Speed needed to reach the hop height under gravity.
			local HopSpeed = math.sqrt(2 * workspace.Gravity * HopHeight)
			HelperFunctions.clearVelocity(Root)
			HelperFunctions.dashVelocity(Root, Vector3.new(0, HopSpeed, 0), Settings.HopTime, YForce)
			task.wait(Settings.HopTime)
			-- Let the hop carry to its peak before the drive down.
			task.wait(HopSpeed / workspace.Gravity * 0.6)
		end

		HelperFunctions.clearVelocity(Root)
		HelperFunctions.dashVelocity(Root, Vector3.new(0, -SlamSpeed, 0), Settings.MaxDriveTime, YForce)

		local Deadline = os.clock() + math.min(Settings.MaxDriveTime, Data.MaxAirTime or Settings.MaxDriveTime)
		-- A frame for the push to lift off, then wait for the ground.
		task.wait(Settings.PollRate)
		while os.clock() < Deadline and Humanoid.FloorMaterial == Enum.Material.Air do
			task.wait(Settings.PollRate)
		end

		HelperFunctions.clearVelocity(Root)
		task.wait(Data.LandingRecovery or 0)
		Character:SetAttribute(AbilityInput.Settings.BusyAttribute, nil)
		SlamActive = false
	end)
end

----------------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------------

local function OnLoadoutChanged(NewSnapshot)
	if not NewSnapshot then
		return
	end
	if Snapshot and Snapshot.ActiveAbility ~= NewSnapshot.ActiveAbility then
		CancelTargeting()
	end
	Snapshot = NewSnapshot
	for Index = 1, 2 do
		local Left = Snapshot.AbilityCooldowns and Snapshot.AbilityCooldowns[Index] or 0
		local Data = AbilityData.Abilities[Snapshot.Abilities[Index]]
		if Left > 0 and Data then
			CooldownLength[Index] = math.max(Data.Cooldown, 0.1)
			CooldownEndsAt[Index] = os.clock() + Left
		end
		RefreshSweep(Index)
	end
end

local function OnAbilityReply(Name: string, Accepted: boolean, Cooldown: number, ClientData: any)
	if not Snapshot then
		return
	end
	local Index = table.find(Snapshot.Abilities, Name) or Snapshot.ActiveAbility
	if Accepted then
		SetCooldown(Index, Cooldown)
		if Name == "StunSlam" and ClientData then
			PerformStunSlam(ClientData)
		end
		-- The client owns its character's physics, so it moves itself
		-- to the destination the server worked out. The server has
		-- already told the anti cheat, so this is not flagged.
		if Name == "Teleport" and type(ClientData) == "table" and typeof(ClientData.Destination) == "Vector3" and Character then
			local Root = Character:FindFirstChild("HumanoidRootPart")
			if Root then
				HelperFunctions.clearVelocity(Root)
				Root.CFrame = Root.CFrame.Rotation + ClientData.Destination
			end
		end
	else
		if Cooldown and Cooldown > 0 then
			SetCooldown(Index, CooldownLength[Index], Cooldown)
		else
			CooldownEndsAt[Index] = 0
			RefreshSweep(Index)
		end
	end
end

----------------------------------------------------------------------
-- INPUT
----------------------------------------------------------------------

local LastSwapAt = 0

local function OnInputBegan(Input: InputObject, GameProcessed: boolean)
	if GameProcessed then
		return
	end

	-- A click while a ghost is showing confirms it.
	if Targeting and (Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.KeyCode == Enum.KeyCode.ButtonR1) then
		ConfirmTargeting()
		return
	end

	local Keys = AbilityData.Keybinds
	local Keyboard, Gamepad = Keys.Keyboard, Keys.Gamepad
	local Code = Input.KeyCode

	if Code == Keyboard.Use or Code == Gamepad.Use then
		if Snapshot then
			TryUse(Snapshot.ActiveAbility)
		end
	elseif Code == Keyboard.SwapAbility or Code == Gamepad.SwapAbility then
		if not Snapshot then
			return
		end
		-- Shown straight away, the server is told which slot, so a lost
		-- message is put right by the next swap.
		if os.clock() - LastSwapAt < AbilityInput.Settings.MinSwapGap then
			return
		end
		LastSwapAt = os.clock()
		CancelTargeting()
		Snapshot.ActiveAbility = Snapshot.ActiveAbility == 1 and 2 or 1
		HUDController.SetActiveSlots(nil, Snapshot.ActiveAbility)
		HUDController.PulseSlot(Snapshot.ActiveAbility == 1 and AbilityData.Hotbar.Slot1 or AbilityData.Hotbar.Slot2)
		CombatFX.PlaySound("UIClick", nil, 0.5, 1.2)
		Events.LoadoutSwap:FireServer("Ability", Snapshot.ActiveAbility)
	end
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

function AbilityInput.OnCharacter(NewCharacter: Model)
	CancelTargeting()
	Character = NewCharacter
	SlamActive = false
end

-- True while a ghost is showing, or for a moment after the click that
-- confirmed one, so CombatInput does not also swing on that click.
function AbilityInput.ShouldBlockClick(): boolean
	return Targeting ~= nil or (os.clock() - LastConsumedClick) < 0.15
end

function AbilityInput.IsTargeting(): boolean
	return Targeting ~= nil
end

function AbilityInput.Init()
	Character = Player.Character
	Events:WaitForChild("LoadoutChanged").OnClientEvent:Connect(OnLoadoutChanged)
	Events:WaitForChild("AbilityUsed").OnClientEvent:Connect(OnAbilityReply)
	Events:WaitForChild("LoadoutSwap")
	UserInputService.InputBegan:Connect(OnInputBegan)
end

return AbilityInput
