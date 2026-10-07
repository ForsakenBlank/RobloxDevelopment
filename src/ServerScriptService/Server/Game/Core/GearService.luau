--[[
	GearService

	Gear drops in runs. Everyone starts with none: enemies have a small
	chance to drop a piece for the player who killed them, and the boss
	drops one for every player still in the run. Items are made with the
	lobby's Shared.EquipmentData and written into the shared save, where
	the lobby's EQUIPMENT tab shows them straight away.

	Which pieces drop where follows the gameplan: each map has its own
	pool (GameConfig.Gear.Pools), Easy never drops Epic or Legendary,
	and a player already holding EquipmentData.Rules.MaxItems pieces gets
	Scrap instead, the same as the lobby's EquipmentService.Grant.

	Gear only changes here through Grant. Armor and Accessories (what is
	worn) are never touched in this place, the lobby checks them on join.
]]

--[[
	What connects to this

	Started by Server.Game.GameInit.

	Listens on:
	  Server.Game.Combat.DamageService.EnemyKilled

	Writes Gear and Scrap through
	ServerScriptService.Server.Modules.DataManager, and tells the player
	on ReplicatedStorage.Remotes.Events.Notify.
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.Game.Config.GameConfig)
local MapData = require(ReplicatedStorage.Modules.Game.Data.MapData)
local RunConfig = require(ReplicatedStorage.Modules.Game.Shared.RunConfig)
local EquipmentData = require(ReplicatedStorage.Modules.Shared.EquipmentData)
local DataManager = require(ServerScriptService.Server.Modules.DataManager)

local Notify = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Events"):WaitForChild("Notify")

local GearService = {}

GearService.Settings = {
	FoundFormat = "Found gear: %s %s",
	ScrapFormat = "Gear full! %s %s became %d Scrap",
}

local Rng = Random.new()
-- what each player found this run, as "Rare Courier Cap", for the end screen
local Found: { [Player]: { string } } = {}

local function Remember(Player: Player, Text: string)
	local List = Found[Player] or {}
	table.insert(List, Text)
	Found[Player] = List
end

-- the gear one player found this run, and forgets it
function GearService.TakeFound(Player: Player): { string }
	local List = Found[Player] or {}
	Found[Player] = nil
	return List
end

-- forgets everything found, for a new run
function GearService.ClearFound()
	Found = {}
end

-- the map this run is on, for the drop pool
local function CurrentMap(): string
	return MapData.Current()
end

-- the highest rarity this difficulty can drop, or nil for no cap
local function MaxRarity(): string?
	local Run = RunConfig.IsSet() and RunConfig.Get() or nil
	local Name = Run and Run.DifficultyName or GameConfig.Run.DefaultDifficulty
	return GameConfig.Gear.MaxRarity[Name]
end

-- Gives one player a new item. Source is "Enemy", "Chest", "Boss" or
-- "Shop" (EquipmentData.DropOdds). Returns the item, or nil if their
-- save is not loaded.
function GearService.Grant(Player: Player, ItemId: string, Source: string?)
	if not DataManager.IsLoaded(Player) or not EquipmentData.Get(ItemId) then
		return nil
	end
	local Item = EquipmentData.NewItem(ItemId, Rng, {
		Source = Source or "Enemy",
		MaxRarity = MaxRarity(),
	})
	local Def = EquipmentData.Get(ItemId)
	local RarityName = EquipmentData.RarityName(Item.Rarity)

	local Gear = DataManager.Get(Player, "Gear")
	Gear = type(Gear) == "table" and table.clone(Gear) or {}
	local Count = 0
	for _ in pairs(Gear) do
		Count += 1
	end

	-- past the cap the piece goes straight to Scrap
	if Count >= EquipmentData.Rules.MaxItems then
		local Scrap = EquipmentData.ScrapValue(Item)
		DataManager.Increment(Player, "Scrap", Scrap)
		Remember(Player, string.format("%d Scrap", Scrap))
		Notify:FireClient(Player, string.format(GearService.Settings.ScrapFormat, RarityName, Def.DisplayName, Scrap))
		return Item
	end

	Gear[HttpService:GenerateGUID(false)] = Item
	DataManager.Set(Player, "Gear", Gear)
	Remember(Player, RarityName .. " " .. Def.DisplayName)
	Notify:FireClient(Player, string.format(GearService.Settings.FoundFormat, RarityName, Def.DisplayName))
	return Item
end

-- a random piece from this map's pool for Source, or nil if there is none
local function PickFrom(Source: string): string?
	local Pools = GameConfig.Gear.Pools[CurrentMap()]
	local Pool = Pools and Pools[Source]
	if not Pool or #Pool == 0 then
		return nil
	end
	return Pool[Rng:NextInteger(1, #Pool)]
end

-- the enemy drop chance, with the Studio test override
local function DropChance(): number
	local Override = GameConfig.Debug.StudioGearDropChance
	if type(Override) == "number" and RunService:IsStudio() then
		return Override
	end
	return GameConfig.Gear.EnemyDropChance or 0
end

function GearService.Init()
	Players.PlayerRemoving:Connect(function(Player)
		Found[Player] = nil
	end)

	local DamageService = require(script.Parent.Parent.Combat.DamageService)
	DamageService.EnemyKilled.Event:Connect(function(Enemy, Killer)
		local Config = GameConfig.Gear
		if not Config.Enabled then
			return
		end
		local IsBoss = Enemy and Enemy.Data and Enemy.Data.IsBoss
		if IsBoss then
			-- every player still here gets one from the boss
			for _, Player in ipairs(Players:GetPlayers()) do
				local ItemId = PickFrom("Boss")
				if ItemId then
					GearService.Grant(Player, ItemId, "Boss")
				end
			end
		elseif Killer and Rng:NextNumber() < DropChance() * (Enemy.RewardMultiplier or 1) then
			local ItemId = PickFrom("Enemy")
			if ItemId then
				GearService.Grant(Killer, ItemId, "Enemy")
			end
		end
	end)
end

return GearService
