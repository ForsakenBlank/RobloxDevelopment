--[[
	WeaponBase

	The base class the four weapons inherit from. It holds the parts
	every weapon has: which player owns it, the entry it was built from
	in WeaponData, its two attack cooldown timers, and the model welded
	to the character.

	It also does the shared work of an attack: check the cooldown, start
	the cooldown, play the sound, wait the wind up, then call the
	subclass for the part that is actually different. Sword, Pistol, RPG
	and Shotgun then only have to write what their MB1 and MB2 do.

	Both cooldown timers live here rather than in the subclasses, so MB1
	and MB2 can be on separate cooldowns without every weapon writing
	that logic again.

	A player carries 2 weapons and has 1 out at a time, so there are two
	of these objects per player. The one that is put away keeps its
	cooldowns running, which stops a player swapping to dodge a cooldown.
	That means the cooldown belongs to the weapon object, not to the
	player.
]]

--[[
	What connects to this

	Reads:
	  Game.Data.WeaponData for the entry of whichever weapon is being
	  built, including both attack tables.

	Subclassed by:
	  Server.Game.Combat.Weapons.Sword, Pistol, RPG and Shotgun. Each
	  defines OnMB1(Context, Attack) and OnMB2(Context, Attack). A
	  subclass that is still a stub falls back to this base, which
	  warns and does nothing on attack.

	Created by:
	  Server.Game.Core.Loadout, which builds one of these for each of the
	  player's two weapon slots at the start of the run and owns which
	  one is equipped. This module does not need to know about swapping,
	  it only needs to know it might not be the active weapon.

	Called by:
	  Server.Game.Combat.CombatService, which is the only thing allowed
	  to trigger an attack. It has already checked the request is legal
	  and that this weapon is the one the player currently has out.

	Uses:
	  Game.Shared.CombatFX to show the swing and play the attack sound on
	  every other client (the attacker's own client already did both the
	  moment they clicked).
	  ServerStorage.Assets.Weapons for the weapon model to weld on. Only
	  the equipped weapon's model is shown, Loadout calls SetShown on a
	  swap.

	Cooldowns are kept as os.clock timestamps on the object rather than
	through Modules.Shared.Cooldown, because that module is one global
	map with no remaining time, and the HUD needs the remaining time to
	show the right sweep after a swap.

	Animations are played on the client by ClientGame.Controllers.
	CombatInput the moment the button is pressed, so they feel instant.
	They replicate from there. The server only plays the sound and
	does the damage.

	The cooldown check here is the real one. The copy in
	ClientGame.Controllers.CombatInput exists so the hotbar can grey out
	instantly, and the two can disagree on a laggy connection, in which
	case the server is right.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local WeaponData = require(ReplicatedStorage.Modules.Game.Data.WeaponData)
local CombatFX = require(ReplicatedStorage.Modules.Game.Shared.CombatFX)

local WeaponBase = {}
WeaponBase.__index = WeaponBase

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------

WeaponBase.Settings = {
	-- The limb the weapon model welds to, and the attachment inside it
	-- to line up on if the rig has one.
	GripLimb = "Right Arm",
	GripAttachment = "RightGripAttachment",
	-- A held button re-fires at the cooldown rate, this is the shortest
	-- gap allowed between two attack requests even if the data says 0.
	MinCooldown = 0.05,
}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

-- Finds the subclass module for a weapon name, or nil if it is still
-- a stub with no code.
local function FindClass(WeaponName: string)
	local Module = script.Parent:FindFirstChild(WeaponName)
	if not Module or Module == script then
		return nil
	end
	local Ok, Result = pcall(require, Module)
	if Ok and type(Result) == "table" and Result.__index then
		return Result
	end
	return nil
end

----------------------------------------------------------------------
-- CONSTRUCTION
----------------------------------------------------------------------

function WeaponBase.new(Player: Player, WeaponName: string)
	local Data = WeaponData.Get(WeaponName)
	if not Data then
		Data = WeaponData.Get(GameConfig.Loadout.FallbackWeapon)
		WeaponName = GameConfig.Loadout.FallbackWeapon
	end

	local Class = FindClass(WeaponName)
	if not Class then
		warn("[WeaponBase] " .. WeaponName .. " has no weapon class yet, it will not attack")
		Class = WeaponBase
	end

	local self = setmetatable({}, Class)
	self.Player = Player
	self.Name = WeaponName
	self.Data = Data
	self.CooldownEndsAt = { MB1 = 0, MB2 = 0 }
	self.CooldownLength = { MB1 = 0, MB2 = 0 }
	-- Charges left in the current burst, refilled when the cooldown
	-- ends. Attacks without Charges in their data have one.
	self.ChargesLeft = {
		MB1 = Data.MB1 and (Data.MB1.Charges or 1) or 1,
		MB2 = Data.MB2 and (Data.MB2.Charges or 1) or 1,
	}
	self.LastUseAt = { MB1 = 0, MB2 = 0 }
	-- Set by a swap, see LockFor.
	self.LockedUntil = 0
	self.Model = nil
	self.Character = nil
	self.Shown = false
	self.AttackThread = nil
	self.Destroyed = false
	return self
end

function WeaponBase:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self:CancelAttack()
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

----------------------------------------------------------------------
-- MODEL
----------------------------------------------------------------------

-- Clones the weapon model onto a character, welded to the grip limb.
-- Shown decides whether it is visible straight away.
function WeaponBase:Attach(Character: Model, Shown: boolean)
	self:DetachModel()
	self.Character = Character

	local Template = ServerStorage.Assets.Weapons:FindFirstChild(self.Data.ModelName)
	if not Template then
		warn("[WeaponBase] no model called " .. self.Data.ModelName .. " in ServerStorage.Assets.Weapons")
		return
	end

	local Limb = Character:FindFirstChild(WeaponBase.Settings.GripLimb)
	if not Limb then
		warn("[WeaponBase] character has no " .. WeaponBase.Settings.GripLimb .. " to hold a weapon")
		return
	end

	local Model = Template:Clone()
	local Handle = Model.PrimaryPart or Model:FindFirstChild("Handle")
	if not Handle then
		warn("[WeaponBase] " .. self.Data.ModelName .. " has no Handle part")
		Model:Destroy()
		return
	end

	for _, Part in ipairs(Model:GetDescendants()) do
		if Part:IsA("BasePart") then
			Part.Anchored = false
			Part.CanCollide = false
			Part.CanQuery = false
			Part.CanTouch = false
			Part.Massless = true
		end
	end

	-- Hand position: the grip attachment if the rig has one, otherwise
	-- the bottom of the limb. Then the weapon's own grip offset.
	local Grip = self.Data.Grip or { Offset = CFrame.new() }
	local Attachment = Limb:FindFirstChild(WeaponBase.Settings.GripAttachment)
	local HandCFrame = Attachment and Attachment.CFrame or CFrame.new(0, -Limb.Size.Y / 2, 0)

	local Weld = Instance.new("Weld")
	Weld.Name = "GripWeld"
	Weld.Part0 = Limb
	Weld.Part1 = Handle
	Weld.C0 = HandCFrame * Grip.Offset
	Weld.Parent = Handle

	Model.Name = self.Name
	self.Model = Model
	self:SetShown(Shown)
end

function WeaponBase:DetachModel()
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

-- Shows or hides the model. The put away weapon is parented to nil
-- rather than made transparent, so it costs nothing while hidden.
function WeaponBase:SetShown(Shown: boolean)
	self.Shown = Shown
	if not self.Model then
		return
	end
	if Shown and self.Character and self.Character.Parent then
		self.Model.Parent = self.Character
	else
		self.Model.Parent = nil
	end
end

----------------------------------------------------------------------
-- COOLDOWNS
----------------------------------------------------------------------

-- Gives the charges back once the recharge has finished.
function WeaponBase:_RefillIfReady(Button: string)
	local Attack = self.Data[Button]
	if not Attack then
		return
	end
	local Max = Attack.Charges or 1
	if self.ChargesLeft[Button] <= 0 and os.clock() >= self.CooldownEndsAt[Button] then
		self.ChargesLeft[Button] = Max
		self.LastUseAt[Button] = 0
	end
end

-- Seconds until this attack can be used again. While a burst still
-- has charges that is the gap between charges, otherwise it is the
-- recharge.
function WeaponBase:GetCooldownRemaining(Button: string): number
	self:_RefillIfReady(Button)
	local Attack = self.Data[Button]
	if not Attack then
		return 0
	end
	local Locked = math.max(0, (self.LockedUntil or 0) - os.clock())
	if self.ChargesLeft[Button] > 0 then
		local Interval = Attack.ChargeInterval or 0
		return math.max(Locked, self.LastUseAt[Button] + Interval - os.clock())
	end
	return math.max(Locked, self.CooldownEndsAt[Button] - os.clock())
end

-- The longest cooldown still running on either attack, for the swap
-- carry-over in Loadout.
function WeaponBase:GetLongestCooldown(): number
	return math.max(self:GetCooldownRemaining("MB1"), self:GetCooldownRemaining("MB2"))
end

-- Stops both attacks for Seconds, on top of their own cooldowns. A
-- swap uses it so swapping never skips a cooldown.
function WeaponBase:LockFor(Seconds: number)
	self.LockedUntil = math.max(self.LockedUntil or 0, os.clock() + Seconds)
end

function WeaponBase:GetChargesLeft(Button: string): number
	self:_RefillIfReady(Button)
	return self.ChargesLeft[Button] or 0
end

function WeaponBase:CanAttack(Button: string): (boolean, string?)
	local Attack = self.Data[Button]
	if not Attack then
		return false, "no such attack"
	end
	if self.Destroyed then
		return false, "destroyed"
	end
	if not GameConfig.Debug.FreeAbilities and self:GetCooldownRemaining(Button) > 0 then
		return false, "on cooldown"
	end
	return true, nil
end

-- Spends a charge. Returns the cooldown the client should show: the
-- short charge gap while charges remain, the full recharge once the
-- last one is spent.
function WeaponBase:StartCooldown(Button: string): number
	local Attack = self.Data[Button]
	local Now = os.clock()
	self:_RefillIfReady(Button)
	self.LastUseAt[Button] = Now
	self.ChargesLeft[Button] = math.max(0, self.ChargesLeft[Button] - 1)

	-- Rage and anything else that speeds cooldowns up.
	local Multiplier = 1
	local PlayerStats = require(script.Parent.Parent.Parent.Core.PlayerStats)
	local Stats = PlayerStats.Get(self.Player)
	if Stats then
		Multiplier = Stats:GetCooldownMultiplier()
	end

	local Length
	if self.ChargesLeft[Button] > 0 then
		Length = math.max(Attack.ChargeInterval or 0, WeaponBase.Settings.MinCooldown)
	else
		Length = math.max(Attack.Cooldown * Multiplier, WeaponBase.Settings.MinCooldown)
		if GameConfig.Debug.FreeAbilities then
			Length = WeaponBase.Settings.MinCooldown
		end
		self.CooldownLength[Button] = Length
		self.CooldownEndsAt[Button] = Now + Length
	end
	return Length
end

----------------------------------------------------------------------
-- ATTACKING
----------------------------------------------------------------------

-- Cancels a wind up that has not landed yet. Loadout calls this on a
-- swap.
function WeaponBase:CancelAttack()
	if self.AttackThread then
		task.cancel(self.AttackThread)
		self.AttackThread = nil
	end
end

-- The shared attack path. Returns whether the attack started and the
-- cooldown length, or false and a reason. AimPosition is where the
-- client's cursor was, already range checked by CombatService.
function WeaponBase:Attack(Button: string, AimPosition: Vector3?): (boolean, any)
	local Allowed, Reason = self:CanAttack(Button)
	if not Allowed then
		return false, Reason
	end

	local Character = self.Player.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
	if not Root or not Humanoid or Humanoid.Health <= 0 then
		return false, "no character"
	end

	local Attack = self.Data[Button]
	local Length = self:StartCooldown(Button)

	-- Other players see the swing and hear it. The attacker's own
	-- client already did both on the click.
	local Max = Attack.Charges or 1
	CombatFX.Broadcast(Attack.Animation, Character, {
		Combo = Max - self.ChargesLeft[Button],
		Charges = Max,
		Shots = Attack.Shots,
		Gap = Attack.ShotInterval,
		Sound = Attack.Sound,
	}, self.Player)

	-- Everything the attack needs, worked out now rather than after
	-- the wind up so a fast moving player's swing lands where they
	-- were looking.
	local Aim = AimPosition or (Root.Position + Root.CFrame.LookVector * 50)
	local Context = {
		Player = self.Player,
		Character = Character,
		Root = Root,
		Origin = Root.Position,
		Facing = Root.CFrame,
		AimPosition = Aim,
		AimDirection = (Aim - Root.Position).Magnitude > 0.01 and (Aim - Root.Position).Unit or Root.CFrame.LookVector,
		Button = Button,
		-- Which swing of a burst this is, 1 for the first. The Sword
		-- uses it to know the last swing is the finisher.
		Combo = Max - self.ChargesLeft[Button],
		Charges = Max,
	}

	local Handler = Button == "MB1" and self.OnMB1 or self.OnMB2

	local function Fire()
		self.AttackThread = nil
		if self.Destroyed then
			return
		end
		if type(Handler) ~= "function" then
			warn("[WeaponBase] " .. self.Name .. " has no " .. Button .. " handler")
			return
		end
		Handler(self, Context, Attack)
	end

	-- Only a wind up still pending is cancelled here. A subclass's own
	-- CancelAttack also stops things like the Pistol's fan or the
	-- Sword's spin, and those should keep going through the other
	-- button's attacks. They are only stopped by a weapon swap.
	WeaponBase.CancelAttack(self)
	if Attack.WindUp and Attack.WindUp > 0 then
		self.AttackThread = task.delay(Attack.WindUp, Fire)
	else
		Fire()
	end

	if GameConfig.Debug.LogCombat then
		print(string.format("[WeaponBase] %s used %s %s (%s), cooldown %.2f", self.Player.Name, self.Name, Button, Attack.Name, Length))
	end

	return true, Length
end

-- Hit sounds are played for the attacker by DamageService's hit
-- confirm, so this is only kept for anything that still calls it.
function WeaponBase:PlayHitSound(Attack, Target: Instance?) end

return WeaponBase
