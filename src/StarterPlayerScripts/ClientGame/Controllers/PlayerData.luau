--[[
	PlayerData

	The client's copy of the player's save. The server sends each value
	on the DataUpdated remote (Server.Modules.DataManager, every value
	once when the save loads and again whenever one changes), and this
	keeps the latest of each.

	Remote events are only queued for the first listener, so this is the
	one listener for DataUpdated: ClientMain starts it before anything
	else, and other controllers read Get and Changed instead of the
	remote.
]]

--[[
	What connects to this

	Read by:
	  ClientGame.Controllers.KeybindController for Keybinds.
	  ClientGame.Controllers.SettingsController for Settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Events = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events")

local PlayerData = {}

-- fired with (Name, Value) whenever a value arrives
PlayerData.Changed = Instance.new("BindableEvent")

local Values: { [string]: any } = {}

-- the latest value of one saved variable, or nil before it arrives
function PlayerData.Get(Name: string): any
	return Values[Name]
end

-- calls Callback with the value now (if it has arrived) and every time it changes
function PlayerData.Watch(Name: string, Callback: (any) -> ())
	PlayerData.Changed.Event:Connect(function(Changed, Value)
		if Changed == Name then
			Callback(Value)
		end
	end)
	if Values[Name] ~= nil then
		task.spawn(Callback, Values[Name])
	end
end

function PlayerData.Init()
	Events:WaitForChild("DataUpdated").OnClientEvent:Connect(function(Name, Value)
		if type(Name) ~= "string" then
			return
		end
		Values[Name] = Value
		PlayerData.Changed:Fire(Name, Value)
	end)
end

return PlayerData
