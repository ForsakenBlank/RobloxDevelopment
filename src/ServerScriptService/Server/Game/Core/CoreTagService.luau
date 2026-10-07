--[[
	CoreTagService

	Puts the lobby's core tag over every player's head in a run: their
	active core, its level and a gold plate for VIPs, built with
	Shared.CoreTag so it looks the same as in the lobby. Players with
	the CORE TAGS setting off don't see other players' tags (the client
	hides them, see ClientGame.Controllers.SettingsController).
]]

--[[
	What connects to this

	Started by Server.Game.GameInit.

	Reads Core and Cores from ServerScriptService.Server.Modules.DataManager,
	and VIP from Server.Game.Core.PassService.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CoreData = require(ReplicatedStorage.Modules.Shared.CoreData)
local CoreTag = require(ReplicatedStorage.Modules.Shared.CoreTag)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)
local PassService = require(script.Parent.PassService)

local CoreTagService = {}

CoreTagService.Settings = {
	-- seconds to wait for the save before giving up on a tag
	DataWait = 25,
}

-- puts (or replaces) the tag on one character
function CoreTagService.Apply(Player: Player, Character: Model?)
	Character = Character or Player.Character
	local Head = Character and Character:FindFirstChild("Head")
	if not Head then
		return
	end
	local Old = Head:FindFirstChild(CoreTag.Settings.Name)
	if Old then
		Old:Destroy()
	end

	local Core = DataManager.Get(Player, "Core")
	if type(Core) ~= "string" or not CoreData.Cores[Core] then
		return
	end
	local Cores = DataManager.Get(Player, "Cores")
	local Total = type(Cores) == "table" and tonumber(Cores[Core]) or 0
	local Level = CoreData.FromXP(Total)

	local Tag = CoreTag.Build(Core, Level, PassService.Has(Player, "VIP"))
	if Tag then
		Tag.Adornee = Head
		Tag.Parent = Head
	end
end

local function Watch(Player: Player)
	local function OnCharacter(Character: Model)
		local Deadline = os.clock() + CoreTagService.Settings.DataWait
		while not DataManager.IsLoaded(Player) and os.clock() < Deadline and Player.Parent == Players do
			task.wait(0.25)
		end
		if Player.Character ~= Character or not DataManager.IsLoaded(Player) then
			return
		end
		Character:WaitForChild("Head", 10)
		CoreTagService.Apply(Player, Character)
	end
	Player.CharacterAdded:Connect(OnCharacter)
	if Player.Character then
		task.spawn(OnCharacter, Player.Character)
	end
end

function CoreTagService.Init()
	Players.PlayerAdded:Connect(Watch)
	for _, Player in ipairs(Players:GetPlayers()) do
		Watch(Player)
	end
end

return CoreTagService
