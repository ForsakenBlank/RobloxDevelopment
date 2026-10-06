local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SharedModules = ReplicatedStorage.Modules.Shared

local HelperFunctions = require(SharedModules.HelperFunctions)

local dashSmoke = script.DashSmoke

local Sounds = SoundService.Sounds

local MovementVisuals = {}

-- Effects welded to the character must add no weight and never be hit,
-- or they drag and tip the player (the dash smoke under the feet once
-- made ground dashes stall).
local function Weightless(Model: Instance)
	local Parts = Model:GetDescendants()
	table.insert(Parts, Model)
	for _, Part in ipairs(Parts) do
		if Part:IsA("BasePart") then
			Part.Massless = true
			Part.CanCollide = false
			Part.CanQuery = false
			Part.CanTouch = false
		end
	end
end

function MovementVisuals.dashsmoke(player : Player, msg : string, animLength : number)
	local character = player.Character
	local rootPart = character.HumanoidRootPart

	local direction = msg

	if not HelperFunctions.isAir(character.Humanoid) then
		local SmokeClone = dashSmoke:Clone()
		Weightless(SmokeClone)
		SmokeClone.Parent = workspace.ClientFX[character.Name]
		SmokeClone.CFrame = rootPart.CFrame * CFrame.new(0, -3, 0)
		SmokeClone.WeldConstraint.Part1 = rootPart

		task.delay(animLength / 2, function()
			HelperFunctions.disableVfx(SmokeClone)
		end)
		
		Debris:AddItem(SmokeClone, animLength + 1)
	end

	if direction == "Back" then
		return
	end

end

function MovementVisuals.frontdash(player : Player, msg : string, animLength : number)
	local character = player.Character
	local rootPart = character:WaitForChild("HumanoidRootPart")

	local FrontDashVFX = script.FrontDashVFX:Clone()
	FrontDashVFX.Anchored = true
	FrontDashVFX.Parent = workspace.ClientFX[character.Name]

	local vfxPosition = rootPart.CFrame * CFrame.new(0, 0, -5)
	local vfxRotation = CFrame.Angles(math.rad(90), math.rad(-90), 0)

	FrontDashVFX.CFrame = vfxPosition * vfxRotation

	task.wait(0.01)

	HelperFunctions.emit(FrontDashVFX)
	Debris:AddItem(FrontDashVFX, .5)
end

function MovementVisuals.doublejump(player : Player, msg : string, animLength : number)
	local character = player.Character
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	local footOffset = -(humanoid.HipHeight + (rootPart.Size.Y / 2))

	local DoubleJumpVFX = script.JumpVFX:Clone()
	DoubleJumpVFX.Anchored = true
	DoubleJumpVFX.Parent = workspace.ClientFX[character.Name]

	local AirsmokeVFX2 = script.AirsmokeVFX2:Clone()
	AirsmokeVFX2.Anchored = true
	AirsmokeVFX2.Parent = workspace.ClientFX[character.Name]

	DoubleJumpVFX.CFrame =
		rootPart.CFrame
		* CFrame.new(0, 5, 0)
		* CFrame.Angles(0, math.rad(50), math.rad(90))

	AirsmokeVFX2.CFrame =
		rootPart.CFrame
		* CFrame.new(0, footOffset - 0.5, 0)
		* CFrame.Angles(0, math.rad(90), 0)

	task.wait(0.01)

	HelperFunctions.emit(DoubleJumpVFX)
	HelperFunctions.emit(AirsmokeVFX2)

	Debris:AddItem(DoubleJumpVFX, .5)
	Debris:AddItem(AirsmokeVFX2, .5)
end

function MovementVisuals.landvfx(player: Player, msg: string, animLength: number)
	local character = player.Character

	local rootPart = character:WaitForChild("HumanoidRootPart")

	local landVFX = script.LandVFX.krk:Clone()
	landVFX.Parent = rootPart
	
	task.wait(0.01)

	HelperFunctions.emit(landVFX)

	game:GetService("Debris"):AddItem(landVFX, 0.5)
end

function MovementVisuals.cloudvfx(player: Player, msg: string, animLength: number)
	local character = player.Character

	local rootPart = character:WaitForChild("HumanoidRootPart")

	local VFX = script.Cloud.VFX:Clone()
	VFX.Parent = rootPart

	task.wait(0.01)

	HelperFunctions.emit(VFX)

	game:GetService("Debris"):AddItem(VFX, 0.5)
end

function MovementVisuals.glidevfx(player: Player, msg: string, animLength: number)
	local character = player.Character

	local rootPart = character:WaitForChild("HumanoidRootPart")

	local VFX = script.GlideVFX.VFX:Clone()
	VFX.Parent = rootPart

	task.wait(0.01)

	HelperFunctions.emit(VFX)

	game:GetService("Debris"):AddItem(VFX, 0.5)
end

function MovementVisuals.backdash(player: Player, msg: string, animLength: number)
	local character = player.Character

	local rootPart = character:WaitForChild("HumanoidRootPart")

	local VFX = script.BackDashVFX:Clone()
	VFX.CFrame = rootPart.CFrame * CFrame.Angles(0, 0, 0)
	VFX.Parent = rootPart

	task.wait(0.01)

	HelperFunctions.emit(VFX)

	game:GetService("Debris"):AddItem(VFX, 0.5)
end

function MovementVisuals.sidedash(player: Player, msg: string, animLength: number)
	local Character = player.Character
	if not Character then
		return
	end

	local RootPart = Character:WaitForChild("HumanoidRootPart")
	local Vfx = script.SideDashVFX:Clone()

	local SideOffset = 7
	local Direction = 0
	if msg == "Left" then
		Direction = -1
	elseif msg == "Right" then
		Direction = 1
	else
		Direction = 0
	end

	local SidePosition = RootPart.Position + RootPart.CFrame.RightVector * (SideOffset * Direction)
	local Forward = RootPart.CFrame.LookVector
	Vfx.CFrame = CFrame.lookAt(SidePosition, SidePosition + Forward)

	Vfx.Parent = RootPart

	task.wait(0.01)
	HelperFunctions.emit(Vfx)
	game:GetService("Debris"):AddItem(Vfx, 0.5)
end

function MovementVisuals.runvfx(player : Player, msg : string, animLength : number)
	local character = player.Character
	local rootPart = character:WaitForChild("HumanoidRootPart")
	
	if msg == "start" then
		local RunVFX = script.RunVFX:Clone()
		Weightless(RunVFX)
		local Weld = RunVFX.Weld

		Weld.Part0 = RunVFX
		Weld.Part1 = rootPart

		RunVFX.Parent = character
	else
		if character:FindFirstChild("RunVFX") then
			character.RunVFX:Destroy()
		end
	end
end

function MovementVisuals.ziplinestart(player : Player, msg : string, animLength : number)
	local character = player.Character
	
	local VFX = script.Ziplining.ZiplineVFX
	local SFX = Sounds.Zipline:Clone() :: Sound
	
	SFX.Parent = character.HumanoidRootPart
	
	SFX.Looped = true
	SFX:Play()
	
	VFX:Clone().Parent = character["Left Arm"]
end

function MovementVisuals.ziplinestop(player : Player, msg : string, animLength : number)
	local character = player.Character
	local LeftArm = character["Left Arm"]
	local RootPart = character.HumanoidRootPart :: Part
	
	if LeftArm:FindFirstChild("ZiplineVFX") then
		LeftArm:FindFirstChild("ZiplineVFX"):Destroy()
	end
	
	if RootPart:FindFirstChild("Zipline") then
		RootPart:FindFirstChild("Zipline"):Destroy()
	end
	
end

return MovementVisuals