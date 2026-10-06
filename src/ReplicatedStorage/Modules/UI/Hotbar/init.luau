local Hotbar = {}
Hotbar.__index = Hotbar

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

function Hotbar:GradientTween(Parent : string, Time : number)
	for _, Frame in PlayerGui:GetDescendants() do

		if Frame.Name == Parent then

			if not Frame:IsA("Frame") then
				return
			end

			self.Frame = script.Cooldown:Clone()

			self.Frame.BackgroundColor3 = Color3.new(1,1,1)
			self.Frame.Size = UDim2.fromScale(1,-1)
			self.Frame.Parent = Frame

			TweenService:Create(
				self.Frame,
				TweenInfo.new(Time, Enum.EasingStyle.Linear),
				{ BackgroundTransparency = 1 }
			):Play()

			Debris:AddItem(self.Frame, Time)
		end
	end
end

return Hotbar