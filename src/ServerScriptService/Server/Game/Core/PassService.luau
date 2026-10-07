--[[
	PassService

	Which gamepasses a player owns, the same way the lobby counts them: a
	pass bought with Timebux is in the save's Passes, and one bought with
	Robux is checked with Roblox (only once its GamePassId is set in
	Shared.SkinData). Worked out once per player and kept, since a pass
	can't be bought in this place.
]]

--[[
	What connects to this

	Read by:
	  Server.Game.Core.RunStats for CharacterStats (2x EXP, VIP, the extra
	  accessory slots).
	  Server.Game.Core.CoreTagService for the VIP tag.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SkinData = require(ReplicatedStorage.Modules.Shared.SkinData)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)

local PassService = {}

local Cache: { [Player]: { [string]: boolean } } = {}

-- every pass this player owns as { [PassKey] = true }. Yields the first time while Roblox is asked
function PassService.Owned(Player: Player): { [string]: boolean }
	if Cache[Player] then
		return Cache[Player]
	end
	local Owned = {}
	local Saved = DataManager.Get(Player, "Passes")
	for Key, Pass in pairs(SkinData.Passes) do
		if type(Saved) == "table" and Saved[Key] then
			Owned[Key] = true
		elseif (Pass.GamePassId or 0) > 0 then
			local Ok, Has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, Player.UserId, Pass.GamePassId)
			if Ok and Has then
				Owned[Key] = true
			end
		end
	end
	-- only cached once the save is in, so an early call does not miss Timebux passes
	if DataManager.IsLoaded(Player) then
		Cache[Player] = Owned
	end
	return Owned
end

function PassService.Has(Player: Player, Key: string): boolean
	return PassService.Owned(Player)[Key] == true
end

-- the developer's UNLOCK ALL switch, only for the developers in SkinData
function PassService.DevAll(Player: Player): boolean
	return SkinData.IsDev(Player.UserId) and DataManager.Get(Player, "DevUnlockAll") == true
end

Players.PlayerRemoving:Connect(function(Player)
	Cache[Player] = nil
end)

return PassService
