local Crawling = {}
Crawling.__index = Crawling

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = ReplicatedStorage.Assets
local Animations = Assets.Animations.Crawling
local Modules = ReplicatedStorage.Modules
local SharedModules = Modules.Shared

local HelperFunctions = require(SharedModules.HelperFunctions)
local Pocket = require(SharedModules.Pocket)
local Sound = require(SharedModules.Sound)
local MovementSettings = require(ReplicatedStorage.Modules.Shared.MovementSettings)

Crawling.Settings = {
	IdleFadeTime = MovementSettings.Abilities.Crawl.IdleFadeTime,
	WalkFadeTime = MovementSettings.Abilities.Crawl.WalkFadeTime,
	StateAttributeCrawling = "crawling",
	StateAttributeNeutral = "neutral",
	SpeedThreshold = MovementSettings.Abilities.Crawl.SpeedThreshold,
}

Crawling.CrawlIdleAnimation = Animations["Crawl Idle"]
Crawling.CrawlWalkAnimation = Animations.Crawling
Crawling.CharacterStates = {}

function Crawling:GetState(Character: Model)
	return self.CharacterStates[Character]
end

function Crawling:SetState(Character: Model, State)
	self.CharacterStates[Character] = State
end

function Crawling:ClearState(Character: Model)
	self.CurrentState = self:GetState(Character)
	if not self.CurrentState then
		return
	end

	if self.CurrentState.Cleaner then
		self.CurrentState.Cleaner:destroy()
	end

	self.CharacterStates[Character] = nil
end

function Crawling:Start(Character: Model)
	self.Humanoid = Character:FindFirstChildOfClass("Humanoid")
	self.RootPart = Character:FindFirstChild("HumanoidRootPart")

	if not self.Humanoid or not self.RootPart then
		return
	end

	HelperFunctions.stopAll(Character)
	Character:SetAttribute("state", self.Settings.StateAttributeCrawling)

	self.IdleTrack = HelperFunctions.playAnim(Character, self.CrawlIdleAnimation, true)
	self.IdleTrack.Priority = Enum.AnimationPriority.Action4
	self.IdleTrack.Looped = true

	Sound:Play("Crouch", Character)

	self.WalkTrack = HelperFunctions.playAnim(Character, self.CrawlWalkAnimation, true)
	self.WalkTrack.Priority = Enum.AnimationPriority.Action4
	self.WalkTrack.Looped = true
	self.WalkTrack:Stop(0)

	self:ClearState(Character)

	self.Cleaner = Pocket.new()

	self.NewState = {
		Humanoid = self.Humanoid,
		IdleTrack = self.IdleTrack,
		WalkTrack = self.WalkTrack,
		IsCrawling = true,
		Cleaner = self.Cleaner,
	}

	self:SetState(Character, self.NewState)

	self.RunningConnection = self.Humanoid.Running:Connect(function(Speed)
		self.CurrentState = self:GetState(Character)
		if not self.CurrentState or not self.CurrentState.IsCrawling then
			return
		end

		if Speed > self.Settings.SpeedThreshold then
			if self.CurrentState.IdleTrack and self.CurrentState.IdleTrack.IsPlaying then
				self.CurrentState.IdleTrack:Stop(self.Settings.IdleFadeTime)
			end
			if self.CurrentState.WalkTrack and not self.CurrentState.WalkTrack.IsPlaying then
				self.CurrentState.WalkTrack:Play(self.Settings.WalkFadeTime)
			end
		else
			if self.CurrentState.WalkTrack and self.CurrentState.WalkTrack.IsPlaying then
				self.CurrentState.WalkTrack:Stop(self.Settings.WalkFadeTime)
			end
			if self.CurrentState.IdleTrack and not self.CurrentState.IdleTrack.IsPlaying then
				self.CurrentState.IdleTrack:Play(self.Settings.IdleFadeTime)
			end
		end
	end)

	self.Cleaner:add(self.RunningConnection)

	self.JumpingConnection = self.Humanoid.Jumping:Connect(function(IsActive: boolean)
		if IsActive then
			self:Stop(Character)
		end
	end)

	self.Cleaner:add(self.JumpingConnection)

	if self.IdleTrack then
		self.Cleaner:add(function()
			self.IdleTrack:Stop(self.Settings.IdleFadeTime)
		end)
	end

	if self.WalkTrack then
		self.Cleaner:add(function()
			self.WalkTrack:Stop(self.Settings.WalkFadeTime)
		end)
	end
end

function Crawling:Stop(Character: Model)
	self.CurrentState = self:GetState(Character)

	if self.CurrentState then
		self.CurrentState.IsCrawling = false
	end

	self:ClearState(Character)

	Character:SetAttribute("state", self.Settings.StateAttributeNeutral)
	HelperFunctions.stopAll(Character)
end

return Crawling