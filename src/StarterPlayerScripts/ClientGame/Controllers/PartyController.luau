--[[
	PartyController

	Keeps a co-op team aware of each other:

	  The party panel, top left under the difficulty, lists every
	  teammate with their health bar, and shows DOWN (in red) for a
	  teammate who is dead and waiting to be revived.

	  A tag over each teammate's head with their name and health, drawn
	  through walls, so the team can always find each other. It turns red
	  when they are down, which is the cue to go and revive them with a
	  Heal Burst.

	Both are designed in the editor (StarterGui.HUD.Party with its
	MemberTemplate, and ReplicatedStorage.Assets.UI.TeammateTag); this
	only clones them and fills them in. In a solo run the panel is
	empty and hidden.
]]

--[[
	What connects to this

	Reads:
	  Each Player's Health, MaxHealth and IsAlive attributes, which
	  Server.Game.Core.PlayerStats mirrors onto the Player, and the
	  Spectating attribute on their character. Attributes replicate to
	  every client, so no remote is needed.

	Started by:
	  ClientGame.ClientMain.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

local PartyController = {}

PartyController.Settings = {
	-- Seconds between refreshes of the bars.
	RefreshRate = 0.1,
	HealthyColour = Color3.fromRGB(90, 220, 110),
	HurtColour = Color3.fromRGB(255, 200, 60),
	LowColour = Color3.fromRGB(255, 70, 70),
	DownColour = Color3.fromRGB(255, 70, 70),
	-- Below these fractions the bar turns the hurt then the low colour.
	HurtBelow = 0.6,
	LowBelow = 0.3,
	TagTemplate = "TeammateTag",
}

local Panel: GuiObject? = nil
local MemberTemplate: GuiObject? = nil
-- Per teammate: { Row, Tag, Shown }
local Members: { [Player]: any } = {}

----------------------------------------------------------------------
-- INTERNAL
----------------------------------------------------------------------

local function ColourFor(Fraction: number, Down: boolean): Color3
	local Settings = PartyController.Settings
	if Down then
		return Settings.DownColour
	elseif Fraction <= Settings.LowBelow then
		return Settings.LowColour
	elseif Fraction <= Settings.HurtBelow then
		return Settings.HurtColour
	end
	return Settings.HealthyColour
end

-- Fills a row or a tag: name, bar and status.
local function Fill(Root: Instance?, Other: Player, Fraction: number, Down: boolean)
	if not Root then
		return
	end
	local Name = Root:FindFirstChild("PlayerName", true)
	if Name then
		Name.Text = Other.DisplayName
	end
	local Bar = Root:FindFirstChild("Fill", true)
	if Bar then
		TweenService:Create(Bar, TweenInfo.new(0.15), { Size = UDim2.new(Down and 0 or Fraction, 0, 1, 0) }):Play()
		Bar.BackgroundColor3 = ColourFor(Fraction, Down)
	end
	local Status = Root:FindFirstChild("Status", true)
	if Status then
		Status.Text = Down and "DOWN" or string.format("%d", math.floor((Other:GetAttribute("Health") or 0) + 0.5))
		Status.TextColor3 = Down and PartyController.Settings.DownColour or Color3.fromRGB(235, 235, 240)
	end
end

local function AddTag(Other: Player, Entry)
	local Character = Other.Character
	local Head = Character and Character:FindFirstChild("Head")
	if not Head then
		return
	end
	if Entry.Tag then
		Entry.Tag:Destroy()
		Entry.Tag = nil
	end
	local Folder = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("UI")
	local Template = Folder and Folder:FindFirstChild(PartyController.Settings.TagTemplate)
	if not Template then
		return
	end
	local Tag = Template:Clone()
	Tag.Adornee = Head
	-- Kept in the local PlayerGui so it is only on this screen and not
	-- inside the other player's character.
	Tag.Parent = Player:WaitForChild("PlayerGui")
	Entry.Tag = Tag
end

local function AddMember(Other: Player)
	if Other == Player or Members[Other] then
		return
	end
	local Entry = { Row = nil, Tag = nil }
	Members[Other] = Entry
	if Panel and MemberTemplate then
		local Row = MemberTemplate:Clone()
		Row.Name = "Member_" .. Other.UserId
		Row.Visible = true
		Row.Parent = Panel
		Entry.Row = Row
	end
	Entry.CharacterConnection = Other.CharacterAdded:Connect(function(Character)
		Character:WaitForChild("Head", 10)
		AddTag(Other, Entry)
	end)
	if Other.Character then
		task.spawn(AddTag, Other, Entry)
	end
end

local function RemoveMember(Other: Player)
	local Entry = Members[Other]
	if not Entry then
		return
	end
	Members[Other] = nil
	if Entry.Row then
		Entry.Row:Destroy()
	end
	if Entry.Tag then
		Entry.Tag:Destroy()
	end
	if Entry.CharacterConnection then
		Entry.CharacterConnection:Disconnect()
	end
end

local function Refresh()
	local Count = 0
	for Other, Entry in pairs(Members) do
		if Other.Parent ~= Players then
			RemoveMember(Other)
			continue
		end
		Count += 1
		local Max = math.max(Other:GetAttribute("MaxHealth") or 100, 1)
		local Fraction = math.clamp((Other:GetAttribute("Health") or 0) / Max, 0, 1)
		local Character = Other.Character
		local Down = Other:GetAttribute("IsAlive") == false or (Character ~= nil and Character:GetAttribute("Spectating") == true)
		Fill(Entry.Row, Other, Fraction, Down)
		Fill(Entry.Tag, Other, Fraction, Down)
		if Entry.Tag and (not Entry.Tag.Adornee or not Entry.Tag.Adornee.Parent) then
			AddTag(Other, Entry)
		end
	end
	if Panel then
		Panel.Visible = Count > 0
	end
end

----------------------------------------------------------------------
-- INIT
----------------------------------------------------------------------

function PartyController.Init()
	local PlayerGui = Player:WaitForChild("PlayerGui")
	local Hud = PlayerGui:WaitForChild("HUD", 10)
	Panel = Hud and Hud:FindFirstChild("Party")
	MemberTemplate = Panel and Panel:FindFirstChild("MemberTemplate")
	if MemberTemplate then
		MemberTemplate.Visible = false
	end
	if Panel then
		Panel.Visible = false
	end

	Players.PlayerAdded:Connect(AddMember)
	Players.PlayerRemoving:Connect(RemoveMember)
	for _, Other in ipairs(Players:GetPlayers()) do
		AddMember(Other)
	end

	local Accumulated = 0
	RunService.Heartbeat:Connect(function(DeltaTime)
		Accumulated += DeltaTime
		if Accumulated >= PartyController.Settings.RefreshRate then
			Accumulated = 0
			Refresh()
		end
	end)
end

return PartyController
