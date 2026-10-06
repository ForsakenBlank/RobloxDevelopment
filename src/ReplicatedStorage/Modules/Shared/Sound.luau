local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local Sounds = SoundService:WaitForChild("Sounds")

local Sound = {}
Sound.__index = Sound

type PlayOptions = {
	Looped: boolean?,
	Persist: boolean?,
	Volume: number?,
	PlaybackSpeed: number?,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
}

local ActiveSounds: { [Instance]: { [string]: Sound } } = {}

local function FindSoundByName(Name: string): Sound?
	local Descendants = Sounds:GetDescendants()

	for Index = 1, #Descendants do
		local Descendant = Descendants[Index]
		if Descendant:IsA("Sound") and Descendant.Name == Name then
			return Descendant
		end
	end

	return nil
end

local function GetSearchRoot(Object: Model | BasePart): Instance?
	if Object:IsA("BasePart") then
		return Object
	end

	return Object
end

local function GetPlaybackParent(Object: Model | BasePart): Instance?
	if Object:IsA("BasePart") then
		return Object
	end

	return Object.PrimaryPart or Object:FindFirstChild("HumanoidRootPart")
end

function Sound:Play(Name: string, Object: Model | BasePart, Options: PlayOptions?): Sound?
	local Template = FindSoundByName(Name)

	if not Template then
		warn("No sound found for:", Name)
		return nil
	end

	local Parent = GetPlaybackParent(Object)

	if not Parent then
		warn("No valid sound parent for:", Name)
		return nil
	end

	local SoundClone = Template:Clone()
	SoundClone.PlayOnRemove = false
	SoundClone.Looped = Options and Options.Looped == true or false
	SoundClone.Volume = Options and Options.Volume or SoundClone.Volume
	SoundClone.PlaybackSpeed = Options and Options.PlaybackSpeed or SoundClone.PlaybackSpeed
	SoundClone.RollOffMinDistance = Options and Options.RollOffMinDistance or SoundClone.RollOffMinDistance
	SoundClone.RollOffMaxDistance = Options and Options.RollOffMaxDistance or SoundClone.RollOffMaxDistance
	SoundClone.Parent = Parent

	local Persist = Options and Options.Persist == true or false

	if SoundClone.Looped or Persist then
		local SoundBucket = ActiveSounds[Parent]
		if not SoundBucket then
			SoundBucket = {}
			ActiveSounds[Parent] = SoundBucket
		end

		local Existing = SoundBucket[Name]
		if Existing then
			Existing:Stop()
			Existing:Destroy()
		end

		SoundBucket[Name] = SoundClone
	else
		local EndedConnection: RBXScriptConnection?
		EndedConnection = SoundClone.Ended:Connect(function()
			if EndedConnection then
				EndedConnection:Disconnect()
				EndedConnection = nil
			end

			SoundClone:Destroy()
		end)

		Debris:AddItem(SoundClone, math.max(SoundClone.TimeLength, 0.5) + 1)
	end

	SoundClone:Play()
	return SoundClone
end

function Sound:Stop(Name: string, Object: Model | BasePart, DestroySound: boolean?): boolean
	local ShouldDestroy = DestroySound ~= false

	local Parent = GetPlaybackParent(Object)
	if Parent then
		local SoundBucket = ActiveSounds[Parent]
		if SoundBucket and SoundBucket[Name] then
			local Active = SoundBucket[Name]
			Active:Stop()
			if ShouldDestroy then
				Active:Destroy()
				SoundBucket[Name] = nil
			end
			return true
		end
	end

	local SearchRoot = GetSearchRoot(Object)
	if not SearchRoot then
		return false
	end

	local Descendants = SearchRoot:GetDescendants()
	local Found = false

	for Index = 1, #Descendants do
		local Descendant = Descendants[Index]
		if Descendant:IsA("Sound") and Descendant.Name == Name then
			Found = true
			Descendant:Stop()
			if ShouldDestroy then
				Descendant:Destroy()
			end
		end
	end

	return Found
end

return Sound