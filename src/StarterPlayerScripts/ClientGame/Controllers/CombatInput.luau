--[[
	CombatInput

	Watches for left click and right click and turns them into attack
	requests. It works out which weapon the player currently has out,
	which attack the click maps to, where the cursor is pointing, and
	sends that up. It also handles swapping between the player's two
	weapons (R, or the mouse wheel if Settings.WheelSwap is on). A swap is instant, a held trigger
	keeps firing with the new weapon, and hits just after a swap get
	the quick swap bonus (GameConfig.Loadout.QuickSwap), so firing one
	weapon then the other is the fastest way to deal damage. A swap
	never skips a cooldown though: the weapon swapped to waits out half
	of what the old one had left (GameConfig.Loadout.SwapCooldownShare).

	It keeps its own copy of the weapon cooldowns from WeaponData, but
	only so it can stop sending requests the server would reject anyway
	and so the hotbar can grey out instantly. The client copy is never
	the authority.

	It also plays the swing or fire animation locally the moment the
	click happens rather than waiting for the server to reply, or the
	weapons would feel slow on any connection. The damage still only
	happens when the server says so.
]]

--[[
	What connects to this

	Sends to:
	  ReplicatedStorage.Remotes.Events.WeaponAttack with
	  (Button, AimPosition, WeaponName), received by
	  Server.Game.Combat.CombatService. The server fires the same
	  remote back with (Button, Accepted, Cooldown).

	Listens on:
	  ReplicatedStorage.Remotes.Events.LoadoutChanged for the player's
	  two weapons, two abilities and the cooldown left on each weapon,
	  sent by Server.Game.Core.Loadout.

	Reads:
	  Game.Data.WeaponData for the keybinds, cooldowns and animations.
	  ReplicatedStorage.Remotes.Events.LoadoutSwap with ("Weapon", nil)
	  for the swap, which CombatService passes to Server.Game.Core.
	  Loadout.
	  Game.Config.GameConfig for the hold to attack rule.

	Sends up the cursor position:
	  Needed for the Pistol and the RPG. It comes from a ray through
	  the mouse from the camera. The server clamps it, so sending a
	  wrong one only wastes the attack.

	Started by:
	  ClientGame.ClientMain, which also hands it every new character
	  through OnCharacter.

	Uses:
	  ReplicatedStorage.Modules.Shared.HelperFunctions playAnim for the
	  local animation, the same as the movement modules do.
	  ClientGame.Controllers.HUDController for the slot contents, which
	  slot is active and the cooldown sweeps, so this never touches the
	  HUD instances itself.

	The movement keys come from MovementSettings.Keybinds and the
	weapon keys from WeaponData.Keybinds, so a clash is a one line fix
	in either table rather than a hunt through the input code.

	Swapping cancels any attack in progress locally as well as on the
	server, so the animation of the old weapon does not keep playing on
	the new one.

	A melee swing turns the character to face the cursor first, so the
	arc goes where the player is looking.

	Clicks are ignored while a proximity prompt is on screen or while
	the player has the UIOpen attribute set, which the shop sets, so
	buying something does not also swing the sword.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local WeaponData = require(ReplicatedStorage.Modules.Game.Data.WeaponData)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)
local HelperFunctions = require(ReplicatedStorage.Modules.Shared.HelperFunctions)
local HUDController = require(script.Parent.HUDController)
local AbilityInput = require(script.Parent.AbilityInput)
local InventoryController = require(script.Parent.InventoryController)
local Keybinds = require(ReplicatedStorage.Modules.Shared.Keybinds)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Events = Remotes:WaitForChild("Events")

local Player = Players.LocalPlayer

local CombatInput = {}

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

CombatInput.Settings = {
	-- How far the aim ray reaches before giving up and aiming at a
	-- point in the distance.
	AimRayLength = 1000,
	-- Play the attack animation as soon as the button is pressed.
	LocalAnimations = true,
	-- Attacks are blocked while a proximity prompt is on screen.
	BlockWhilePrompt = true,
	-- Attacks are blocked while this attribute on the LocalPlayer is
	-- true. The shop UI sets it while it is open.
	UIOpenAttribute = "UIOpen",
	-- Animation names in WeaponData are looked up under this folder.
	AnimationFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"),
	-- Shortest gap between two swaps, just inside the rate the server
	-- accepts them at (CombatService.Settings.SwapRate), so no swap is
	-- ever dropped on the way.
	MinSwapGap = 0.13,
	-- true makes the mouse wheel swap weapons too. Off because the wheel
	-- also zooms the camera.
	WheelSwap = false,
	-- Shortest gap between two swaps from the mouse wheel, so one flick
	-- of the wheel is one swap.
	WheelSwapGap = 0.15,
}

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------

local Character: Model? = nil
local Snapshot = nil
local Held: { [string]: boolean } = {}
-- The weapon slot each attack request still waiting on a reply came
-- from, oldest first, per button.
local PendingSlots: { [string]: { number } } = { MB1 = {}, MB2 = {} }
local PromptShown = false
local CurrentTrack: AnimationTrack? = nil

-- Cooldown end times, indexed [SlotIndex][Button], on the local clock.
local CooldownEndsAt = { { MB1 = 0, MB2 = 0 }, { MB1 = 0, MB2 = 0 } }
local CooldownLength = { { MB1 = 0, MB2 = 0 }, { MB1 = 0, MB2 = 0 } }
-- Charges left in the current burst, mirroring WeaponBase. nil means
-- full.
local ChargesLeft = { { MB1 = nil, MB2 = nil }, { MB1 = nil, MB2 = nil } }

-- Spends a local charge and returns the cooldown to predict: the gap
-- between charges while some remain, the full recharge on the last.
local function SpendCharge(SlotIndex: number, Button: string, Attack): number
	local Max = Attack.Charges or 1
	local Left = ChargesLeft[SlotIndex][Button]
	if Left == nil or (Left <= 0 and os.clock() >= CooldownEndsAt[SlotIndex][Button]) then
		Left = Max
	end
	Left = math.max(0, Left - 1)
	ChargesLeft[SlotIndex][Button] = Left
	if Left > 0 then
		return math.max(Attack.ChargeInterval or 0, 0.05)
	end
	return math.max(Attack.Cooldown, 0.05)
end

local AnimationCache: { [string]: Animation? } = {}
local WarnedAnimations: { [string]: boolean } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- The weapon slot the player has out.
local function HeldSlot(): number?
	return Snapshot and Snapshot.ActiveWeapon or nil
end

local function ActiveWeaponName(): string?
	local Slot = HeldSlot()
	return Snapshot and Slot and Snapshot.Weapons[Slot] or nil
end

local function ActiveWeaponData()
	local Name = ActiveWeaponName()
	return Name and WeaponData.Weapons[Name] or nil
end

local function FindAnimation(Name: string?): Animation?
	if not Name or Name == "" then
		return nil
	end
	if AnimationCache[Name] ~= nil then
		return AnimationCache[Name] or nil
	end
	local Found = CombatInput.Settings.AnimationFolder:FindFirstChild(Name, true)
	if Found and Found:IsA("Animation") then
		AnimationCache[Name] = Found
		return Found
	end
	AnimationCache[Name] = false :: any
	if not WarnedAnimations[Name] and not CombatFX.Has(Name) then
		WarnedAnimations[Name] = true
		warn("[CombatInput] no animation called " .. Name .. " under Assets.Animations and no CombatFX stand in")
	end
	return nil
end

local function StopAnimation()
	if CurrentTrack then
		CurrentTrack:Stop(0.1)
		CurrentTrack = nil
	end
end

-- Plays the uploaded Animation asset with this name if there is one,
-- otherwise the procedural stand in from CombatFX with the same name.
local function PlayAnimation(Name: string?, Data: any?)
	if not CombatInput.Settings.LocalAnimations or not Character or not Name then
		return
	end
	local Animation = FindAnimation(Name)
	if not Animation then
		CombatFX.Play(Name, Character, Data)
		return
	end
	StopAnimation()
	CurrentTrack = HelperFunctions.playAnim(Character, Animation, true)
	if CurrentTrack then
		CurrentTrack.Priority = Enum.AnimationPriority.Action
	end
end

-- Where the cursor is pointing in the world.
local function GetAimPosition(): Vector3
	local Camera = workspace.CurrentCamera
	local Mouse = UserInputService:GetMouseLocation()
	local Ray = Camera:ViewportPointToRay(Mouse.X, Mouse.Y)

	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = { Character or Camera }

	local Length = CombatInput.Settings.AimRayLength
	local Result = workspace:Raycast(Ray.Origin, Ray.Direction * Length, Params)
	return Result and Result.Position or (Ray.Origin + Ray.Direction * Length)
end

-- Pushes the longest running cooldown of a weapon slot to the HUD.
local function RefreshSlotSweep(SlotIndex: number)
	local SlotName = SlotIndex == 1 and WeaponData.Hotbar.Slot1 or WeaponData.Hotbar.Slot2
	local Now = os.clock()
	local BestRemaining, BestLength = 0, 0
	for _, Button in ipairs({ "MB1", "MB2" }) do
		local Remaining = CooldownEndsAt[SlotIndex][Button] - Now
		if Remaining > BestRemaining then
			BestRemaining = Remaining
			BestLength = CooldownLength[SlotIndex][Button]
		end
	end
	if BestRemaining > 0 then
		HUDController.StartCooldown(SlotName, BestLength, BestRemaining)
	else
		HUDController.ClearCooldown(SlotName)
	end
end

local function SetCooldown(SlotIndex: number, Button: string, Length: number, Remaining: number?)
	CooldownLength[SlotIndex][Button] = Length
	CooldownEndsAt[SlotIndex][Button] = os.clock() + (Remaining or Length)
	RefreshSlotSweep(SlotIndex)
end

local function CanAttackNow(Button: string): boolean
	if not Snapshot or not Character then
		return false
	end
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Humanoid.Health <= 0 then
		return false
	end
	if CombatInput.Settings.BlockWhilePrompt and PromptShown then
		return false
	end
	if Player:GetAttribute(CombatInput.Settings.UIOpenAttribute) then
		return false
	end
	if Character:GetAttribute("Stunned") or Character:GetAttribute("Spectating") then
		return false
	end
	local Data = ActiveWeaponData()
	if not Data or not Data[Button] then
		return false
	end
	if not GameConfig.Debug.FreeAbilities and os.clock() < CooldownEndsAt[HeldSlot()][Button] then
		return false
	end
	return true
end

local function TryAttack(Button: string)
	if not CanAttackNow(Button) then
		return
	end
	local Data = ActiveWeaponData()
	local Attack = Data[Button]
	local SlotIndex = HeldSlot()

	local Aim = GetAimPosition()
	local Root = Character:FindFirstChild("HumanoidRootPart")
	local AimFlat = Root and (Aim - Root.Position) * Vector3.new(1, 0, 1) or Vector3.zero

	-- A melee swing turns the character to face the cursor first, so
	-- the arc goes where the player is looking.
	if Root and Attack.Kind == "Melee" and AimFlat.Magnitude > 0.5 then
		Root.CFrame = CFrame.lookAt(Root.Position, Root.Position + AimFlat)
	end

	-- Optimistic cooldown and animation, corrected when the server
	-- replies. The combo index tells the animation which swing this
	-- is in a burst.
	SetCooldown(SlotIndex, Button, SpendCharge(SlotIndex, Button, Attack))
	local Max = Attack.Charges or 1
	local Combo = Max - (ChargesLeft[SlotIndex][Button] or 0)
	PlayAnimation(Attack.Animation, {
		Combo = Combo,
		Charges = Max,
		Shots = Attack.Shots,
		Gap = Attack.ShotInterval,
		Sound = Attack.Sound,
		Direction = AimFlat.Magnitude > 0.5 and AimFlat.Unit or nil,
	})

	-- Recoil: thrown away from where the shot went.
	if Root and (Attack.SelfLaunch or 0) > 0 then
		local Back = Root.Position - Aim
		Back = Back.Magnitude > 0.01 and Back.Unit or -Root.CFrame.LookVector
		local Launch = (Back + Vector3.new(0, Attack.SelfLaunchUp or 0, 0)).Unit * Attack.SelfLaunch
		HelperFunctions.velocity(Root, Launch, Attack.SelfLaunchTime or 0.18)
	end

	local Pending = PendingSlots[Button]
	table.insert(Pending, SlotIndex)
	if #Pending > 8 then
		table.remove(Pending, 1)
	end
	Events.WeaponAttack:FireServer(Button, Aim, ActiveWeaponName())
end

----------------------------------------------------------------------
-- REMOTES
----------------------------------------------------------------------

local function OnLoadoutChanged(NewSnapshot)
	if not NewSnapshot then
		return
	end
	local Swapped = Snapshot ~= nil and Snapshot.ActiveWeapon ~= NewSnapshot.ActiveWeapon
	Snapshot = NewSnapshot

	HUDController.SetLoadout(Snapshot.Weapons, Snapshot.Abilities)
	HUDController.SetActiveSlots(Snapshot.ActiveWeapon, Snapshot.ActiveAbility)

	-- The server sends how long each attack has left, so a swap to a
	-- weapon that was still cooling shows the right sweep.
	for SlotIndex = 1, 2 do
		local Remaining = Snapshot.WeaponCooldowns and Snapshot.WeaponCooldowns[SlotIndex]
		local Data = WeaponData.Weapons[Snapshot.Weapons[SlotIndex]]
		if Remaining and Data then
			for _, Button in ipairs({ "MB1", "MB2" }) do
				local Left = Remaining[Button] or 0
				if Left > 0 then
					CooldownLength[SlotIndex][Button] = math.max(Data[Button].Cooldown, 0.05)
					CooldownEndsAt[SlotIndex][Button] = os.clock() + Left
					-- Mid recharge as far as this client knows, the
					-- charges come back when it ends.
					ChargesLeft[SlotIndex][Button] = 0
				else
					ChargesLeft[SlotIndex][Button] = nil
				end
			end
		end
		RefreshSlotSweep(SlotIndex)
	end

	if Swapped then
		StopAnimation()
	end
end

local function OnAttackReply(Button: string, Accepted: boolean, Cooldown: number)
	if not Snapshot then
		return
	end
	-- Replies come back in the order the requests went, so the oldest
	-- waiting request is the one this answers, even if the player has
	-- swapped weapons since.
	local SlotIndex = table.remove(PendingSlots[Button] or {}, 1) or HeldSlot() or Snapshot.ActiveWeapon
	if Accepted then
		SetCooldown(SlotIndex, Button, Cooldown)
	else
		-- Rejected. Take the server's remaining time if it gave one.
		-- Otherwise the optimistic cooldown stays: clearing it let a
		-- client that had fallen out of step swing again and again.
		if Cooldown and Cooldown > 0 then
			SetCooldown(SlotIndex, Button, CooldownLength[SlotIndex][Button], Cooldown)
		end
		StopAnimation()
	end
end

----------------------------------------------------------------------
-- INPUT
----------------------------------------------------------------------

local function ButtonFor(Input: InputObject): string?
	local Keys = WeaponData.Keybinds
	-- the player's own keys from the lobby, these can be keys and not just mouse buttons
	if Keybinds.Is("Attack", Input) then
		return "MB1"
	elseif Keybinds.Is("AltAttack", Input) then
		return "MB2"
	elseif Input.UserInputType == Enum.UserInputType.Gamepad1 then
		if Input.KeyCode == Keys.Gamepad.MB1 then
			return "MB1"
		elseif Input.KeyCode == Keys.Gamepad.MB2 then
			return "MB2"
		end
	end
	return nil
end

local function OnInputBegan(Input: InputObject, GameProcessed: boolean)
	if GameProcessed or Keybinds.IsCapturing() then
		return
	end

	local Button = ButtonFor(Input)
	if Button then
		-- A click that confirms a teleport ghost is not a swing.
		if AbilityInput.ShouldBlockClick() or InventoryController.IsAiming() then
			return
		end
		Held[Button] = true
		TryAttack(Button)
		return
	end

	local Keys = WeaponData.Keybinds
	if Keybinds.Is("SwapWeapon", Input) or Input.KeyCode == Keys.Gamepad.SwapWeapon then
		CombatInput.Swap()
	end
end

-- The mouse wheel swaps too, a notch at a time.
local LastWheelSwap = 0
local function OnInputChanged(Input: InputObject, GameProcessed: boolean)
	if GameProcessed or not CombatInput.Settings.WheelSwap or Input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end
	if os.clock() - LastWheelSwap < CombatInput.Settings.WheelSwapGap then
		return
	end
	LastWheelSwap = os.clock()
	CombatInput.Swap()
end

local function OnInputEnded(Input: InputObject)
	local Button = ButtonFor(Input)
	if Button then
		Held[Button] = nil
	end
end

----------------------------------------------------------------------
-- PUBLIC
----------------------------------------------------------------------

-- ClientMain calls this with every new character.
function CombatInput.OnCharacter(NewCharacter: Model)
	Character = NewCharacter
	StopAnimation()
	Held = {}
end

-- The current loadout snapshot, for AbilityInput and the shop.
function CombatInput.GetLoadout()
	return Snapshot
end

-- Swaps to the other weapon. Shown straight away and the server is
-- told, and the two arrive in order, so a click right after the swap
-- already fires the new weapon. A held trigger carries on firing.
-- The server is sent the slot to swap to rather than "the other one",
-- so if a message were ever lost the next swap still lines them up.
local LastSwapAt = 0
function CombatInput.Swap()
	if not Snapshot then
		return
	end
	if os.clock() - LastSwapAt < CombatInput.Settings.MinSwapGap then
		return
	end
	LastSwapAt = os.clock()
	StopAnimation()
	-- Swapping never skips a cooldown: the same share of the old
	-- weapon's longest cooldown the server carries over
	-- (GameConfig.Loadout.SwapCooldownShare) is put on the new one.
	local From = Snapshot.ActiveWeapon
	local To = From == 1 and 2 or 1
	local Now = os.clock()
	local Longest = math.max(CooldownEndsAt[From].MB1 - Now, CooldownEndsAt[From].MB2 - Now, 0)
	local Carry = Longest * (GameConfig.Loadout.SwapCooldownShare or 0)
	if Carry > 0 then
		for _, Button in ipairs({ "MB1", "MB2" }) do
			if CooldownEndsAt[To][Button] < Now + Carry then
				CooldownLength[To][Button] = math.max(CooldownLength[To][Button], Carry)
				CooldownEndsAt[To][Button] = Now + Carry
			end
		end
		RefreshSlotSweep(To)
	end
	Snapshot.ActiveWeapon = To
	HUDController.SetActiveSlots(Snapshot.ActiveWeapon, nil)
	HUDController.PulseSlot(Snapshot.ActiveWeapon == 1 and WeaponData.Hotbar.Slot1 or WeaponData.Hotbar.Slot2)
	CombatFX.PlaySound("UIClick", nil, 0.6, 1.3)
	Events.LoadoutSwap:FireServer("Weapon", Snapshot.ActiveWeapon)
end

function CombatInput.Init()
	Character = Player.Character

	Events:WaitForChild("LoadoutChanged").OnClientEvent:Connect(OnLoadoutChanged)
	Events:WaitForChild("WeaponAttack").OnClientEvent:Connect(OnAttackReply)
	Events:WaitForChild("LoadoutSwap")

	UserInputService.InputBegan:Connect(OnInputBegan)
	UserInputService.InputEnded:Connect(OnInputEnded)
	UserInputService.InputChanged:Connect(OnInputChanged)

	ProximityPromptService.PromptShown:Connect(function()
		PromptShown = true
	end)
	ProximityPromptService.PromptHidden:Connect(function()
		PromptShown = false
	end)

	-- A held button keeps attacking at the cooldown rate, for the
	-- buttons WeaponData says can be held.
	RunService.Heartbeat:Connect(function()
		local Hold = WeaponData.Shared.HoldToAttack
		for Button in pairs(Held) do
			local Allowed = type(Hold) == "table" and Hold[Button] or Hold == true
			if Allowed then
				TryAttack(Button)
			end
		end
	end)
end

return CombatInput
