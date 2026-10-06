-- README
-- This script is disabled on purpose, it never runs. It is just
-- notes on how this template is put together and how to use it.
-- Delete it once your team doesn't need it anymore.


-- FOLDER OVERVIEW

-- ReplicatedStorage
--   Remotes/Events        RemoteEvents, includes DataUpdated
--   Remotes/Functions     RemoteFunctions
--   Modules/Shared        Modules used by both server and client
--   Assets                Models, Effects, Sounds, UI, drag stuff here to use it anywhere

-- ServerScriptService/Server
--   Core/Main             The only Script that actually runs on the server
--   Modules               DataManager, PlayerManager, AntiCheat, GameManager, LeaderstatsManager
--   Services              Copy ExampleService here for new systems like a shop or quests

-- ServerStorage
--   Modules               Server only modules that should never reach the client
--   Assets                Server only models, things you clone in but never want a client to see

-- StarterPlayer/StarterPlayerScripts/Client
--   Core/Main             The only LocalScript that actually runs on the client
--   Modules               UIManager, InputManager, PlayerData

-- Workspace
--   Map                   Put your level geometry here
--   Effects                Put spawned VFX parts here so they don't clutter Map

-- StarterGui/MainUI        Your ScreenGui, ResetOnSpawn is off so it survives respawning


-- WHY ONLY TWO SCRIPTS

-- Everything else in this template is a ModuleScript, and a
-- ModuleScript does nothing on its own, it only runs when
-- something requires it. Server.Core.Main and Client.Core.Main
-- are the only two Scripts that Roblox actually starts by
-- itself. They require every module and call its Init function.
-- If you add a new module and never require it from one of these
-- two, it will never run.


-- HOW TO ADD A NEW SAVED VARIABLE

-- 1. Open ReplicatedStorage.Modules.Shared.PlayerDataTemplate
-- 2. Add a line, for example:
--        Gems = 0,
-- 3. That's it. DataManager saves and loads it automatically, and
--    fills it in for players who already had a save from before
--    that variable existed. You do not need to touch DataManager.


-- HOW TO READ OR CHANGE A VARIABLE FROM A SERVER SCRIPT

-- require DataManager from wherever your script lives, for
-- example from a script inside Server.Modules or Server.Services:

--     local DataManager = require(script.Parent.DataManager)

-- then:

--     local cash = DataManager.Get(player, "Cash")

--     DataManager.Set(player, "Cash", 500)

--     DataManager.Increment(player, "Cash", 50)   -- adds 50
--     DataManager.Increment(player, "Cash", -50)  -- removes 50

--     local allData = DataManager.GetAll(player)  -- the whole table

-- Set and Increment both push the new value to that player's
-- client automatically, you never need to fire a remote yourself
-- for stat changes.

-- Data saves automatically every 2 minutes and when a player
-- leaves. You never need to call DataManager.Save yourself unless
-- you want to force an extra save at a specific moment, like
-- right after a purchase.


-- HOW TO READ A VARIABLE FROM A LOCAL SCRIPT

-- require PlayerData from Client.Modules:

--     local PlayerData = require(script.Parent.PlayerData)

-- to read the current value:

--     local cash = PlayerData.Get("Cash")

-- to react whenever it changes, for example to update a UI label:

--     PlayerData.Changed.Event:Connect(function(variableName, value)
--         if variableName == "Cash" then
--             cashLabel.Text = tostring(value)
--         end
--     end)

-- PlayerData.Get can return nil for a split second right when a
-- player joins, before the first sync arrives from the server.
-- Use the Changed event to update your UI instead of only reading
-- once at the top of a script.


-- REMOTES

-- ReplicatedStorage.Remotes.Events and .Functions start empty
-- except for DataUpdated, which DataManager uses internally. Add
-- your own RemoteEvents and RemoteFunctions here for anything a
-- player does that the server needs to know about, buying an
-- item, opening a door, and so on.

-- Always check and validate input on the server side of a remote.
-- Never trust anything a client sends you.


-- ANTI CHEAT

-- Server.Modules.AntiCheat is server only, on purpose. You cannot
-- detect an injected script from inside the game, because an
-- exploiter's executor runs above your LocalScripts and can edit
-- or delete anything you put there. So instead of trying to catch
-- the cheat, the server checks the result: it watches where every
-- player actually ends up and refuses anything impossible.

-- It is split into:
--   AntiCheat            scoring, grace windows, responses
--   AntiCheat.Config     every threshold, all in one place
--   AntiCheat.Detectors  Movement, Noclip and Physics
--   AntiCheat.RemoteGuard rate limiting for your remotes

-- Nothing gets kicked for one bad reading. Flags add to a score
-- that bleeds away over time, a sustained problem pulls the
-- player back to their last believable position, and only someone
-- who keeps at it is removed.

-- THE PART THAT MATTERS FOR YOU: if your own code moves a player
-- or changes their speed, it has to say so, or the anti cheat
-- will treat your own feature as an exploit.

--     AntiCheat.Teleport(player, position)     not root.CFrame = ...
--     AntiCheat.SetSpeedLimit(player, 32)      not Humanoid.WalkSpeed = ...
--     AntiCheat.ResetSpeedLimit(player)
--     AntiCheat.SetJumpLimit(player, power, height)
--     AntiCheat.GrantException(player, 3)      launch pads, knockback, cutscenes
--     AntiCheat.Sanction(bodyVelocity)         before parenting it to a character
--     AntiCheat.IgnoreInstance(part)           things players pass through on purpose

-- Every flag also fires AntiCheat.Reported, so you can log them:

--     AntiCheat.Reported.Event:Connect(function(player, check, severity, detail, score)
--         print(player.Name, check, detail)
--     end)

-- Leave Config.Response.KickEnabled off for the first few days of
-- a live game and read the flag log instead. If your own systems
-- show up there, that means they should be using the API above,
-- not that the thresholds are wrong.


-- SEEING WHAT GOT DETECTED

-- The output log is per server and disappears when that server
-- shuts down, which happens every time it empties. So flags are
-- also written to a DataStore by AntiCheat.FlagLog, which starts
-- itself, you do not need to wire it up.

-- To read them, open Studio and run this in the command bar:

--     require(game.ServerScriptService.Server.Modules.AntiCheat.FlagLog).PrintReport()

-- That prints who was flagged most recently across every server,
-- what for, and how many times. Studio needs access to API
-- services for this, in Game Settings under Security.

-- The other calls, if you want to build your own view:

--     FlagLog.GetRecentlyFlagged(20)   most recent first
--     FlagLog.GetWorstOffenders(20)    most flags first
--     FlagLog.GetRecord(userId)        one player's full record

-- Flags are batched and written every 30 seconds rather than one
-- at a time, because someone actually cheating produces a flag
-- roughly every second and writing each one would be throttled
-- immediately.

-- On a place that has not been published yet, DataStores are not
-- available at all. Detection still works and still corrects and
-- kicks, you just get the output log only, and a warning saying
-- so. The same applies to DataManager and player saves.


-- REMOTE SPAM

-- Bind remotes through RemoteGuard rather than connecting
-- OnServerEvent yourself. Firing a remote thousands of times a
-- second is the cheapest exploit there is and no movement check
-- will catch it.

--     local RemoteGuard = require(AntiCheatFolder.RemoteGuard)
--
--     RemoteGuard.BindEvent(buyRemote, { Rate = 5 }, function(player, itemName)
--         -- runs at most 5 times a second per player
--     end)

-- Rate limiting is not validation. It stops someone calling
-- BuyItem a thousand times a second, it does not stop them
-- calling it once with a negative price. Check the arguments too.


-- LEADERSTATS

-- Server.Modules.LeaderstatsManager mirrors whichever stats you
-- list in its TRACKED_STATS table onto the Roblox leaderboard.
-- The names must match variables in PlayerDataTemplate and must
-- be numbers. Add or remove names from that list to change what
-- shows up.


-- ADDING A NEW SYSTEM, LIKE A SHOP OR QUESTS

-- 1. Copy Server.Services.ExampleService
-- 2. Rename it and write your logic in its Init function
-- 3. Require it and call its Init from Server.Core.Main, next to
--    the other services

-- Keep the same pattern on the client, add new modules under
-- Client.Modules and wire them up from Client.Core.Main.


-- GENERAL RULES FOR THIS TEMPLATE

-- Server scripts and modules are the only things allowed to
-- change player data or anything else that matters for fairness.
-- The client can ask, through a remote, but the server always
-- decides and validates.

-- Keep shared constants like game settings in GameConfig so you
-- are not retyping the same numbers in multiple scripts.

-- One ModuleScript, one job. If a module is doing two unrelated
-- things, it is probably time to split it into two modules.
