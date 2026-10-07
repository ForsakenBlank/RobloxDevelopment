# Lobby connection checklist

Taken from VelocityGameConnection.md. Section 1 protects player data, so it came first.

## 1. Save safety
- [x] 1.1 The game's DataManager is now the lobby's (`SaveVersion`, the version wait, the double load guard) plus two fixes the lobby should copy back: a save that fails to load is never written over, and a player who leaves mid load keeps nothing
- [x] 1.2 `LobbyLink.SendToLobby` sends `SaveVersion` after saving
- [x] 1.3 `PlayerManager.Init` can no longer load a player twice
- [ ] 1.4 Session locking is built into DataManager behind `SESSION_LOCK` (off). Copy this DataManager to the lobby, then set `SESSION_LOCK = true` in both places at the same time. It relies on PlayerManager calling `Save` then `Release` when a player leaves, as both places do now

## 2. One save template
- [x] 2.1 The game's `PlayerDataTemplate` is now the lobby's

## 3. Shared modules (copied whole from the lobby)
- [x] 3.1 `GameText` (with all children) and `UIIcons`
- [x] 3.2 `CoreData`
- [x] 3.3 `EquipmentData`
- [x] 3.4 `CharacterStats`
- [x] 3.5 `Keybinds`
- [x] 3.6 `SkinData`, `SkinBuilder`, `CoreTag`, `GemIcon`
- [x] 3.7 `Leveling`
- [ ] 3.8 `StarterCharacterScripts.Client` and `MOVEMENT_INPUTS` (StarterCharacterScripts is not in the Rojo project, so this is a Studio copy, or add it to `default.project.json`)
- [ ] 3.9 Give the shared modules one folder in the Rojo project so both places sync from it

## 4. Gear and core stats in a run
- [x] 4.1 `Server.Game.Core.RunStats` uses `CharacterStats.Compute` and `ForRun`, with owned passes and the dev unlock from `PassService`
- [x] 4.2 `MaxHealth`, `MaxEnergy` into `PlayerStats.new` overrides in `RunSetup`
- [x] 4.3 Health and energy regen per player in `EnergyService` (plus Ruby's no regen in combat)
- [x] 4.4 Weapon and ability damage multipliers in `DamageService`
- [x] 4.5 Crits in `DamageService`
- [x] 4.6 Damage taken multipliers (overall and melee, fire, magic). Enemy melee is Melee, Burning is Fire, the Necromancer's bolts are Magic. Tag other attacks in EnemyData with `DamageType`
- [x] 4.7 Knockback multiplier and ignore knockback chance
- [x] 4.8 Split cooldown multiplier into weapon and ability
- [x] 4.9 `SpeedMultiplier` through `SetSpeedMultiplier("Gear", ...)`
- [x] 4.10 `Lifesteal` through `SetLifesteal("Gear", ...)`
- [x] 4.11 `HealingMultiplier` on Heal Burst
- [x] 4.12 `CoinMultiplier` on kill money
- [x] 4.13 `ExpMultiplier`, `CashMultiplier` at the end of a run

## 5. Keys in the game
- [x] 5.1 `KeybindController` loads `Keybinds` from `DataUpdated`, started first
- [x] 5.2 `CombatInput` attack, alt attack and swap use `Keybinds.Is`
- [x] 5.3 `AbilityInput` use and swap use `Keybinds.Is`
- [x] 5.4 HUD key labels and the area banner's "hold Z" use `Keybinds.Label` and refresh on change
- [x] 5.5 Prompt key (gates and shop) set on the client from `Keybinds.Get("Interact")`
- [ ] 5.6 Movement: the player's keys are written into `MovementSettings.Keybinds.Keyboard`, which works for any script that reads that table when it binds. The full fix comes with 3.8
- [ ] 5.7 Core ultimate bound to `Keybinds.Get("Ultimate")` (no ultimate in the game yet)
- [x] 5.8 Ignore keys while `Keybinds.IsCapturing()`

## 6. Gear drops
- [x] 6.1 `Server.Game.Core.GearService.Grant` (GUID id, `MaxItems` cap turns extras into Scrap)
- [x] 6.2 Drop pools per map and the Easy rarity cap in `GameConfig.Gear`. Enemies 2% for the killer, the boss one for everyone. Tune these to the gameplan
- [x] 6.3 A toast tells the player what they found

## 7. Teleport data
- [x] 7.1 `TeleportDataReader` reads `Map` (falls back to `GameConfig.Run.DefaultMap`)
- [x] 7.2 Game to lobby payload carries `SaveVersion`

## 8. End of a run
- [x] 8.1 `Deaths`, `Parries` (one per Sword swing that deflects something). `PerfectParries` waits until the game has a parry window
- [x] 8.2 `MapBest[Map][Difficulty]`, `MapRuns[Map]`
- [x] 8.3 `CoreTime`, `CoreRuns`, and `Cores[Core]` Enlightenment (1 per EXP earned, `GameConfig.Cores.EnlightenmentPerExp`)
- [x] 8.4 `WeaponKills`, `AbilityUses`
- [x] 8.5 `PlayTime` in seconds. Timebux is ready but off until `GameConfig.Timebux.SecondsPerTimebux` is set to the lobby's value
- [ ] 8.6 `OwnedSkins.Noob` / `OwnedSkins.Guest` for beating the Guest in Retroscity (the map loader is ready, needs the RetroCity map in `workspace.Maps` and the Guest boss)

## 9. Testing the whole loop

Before testing: `rojo serve` this branch into the game place, and turn on Studio access to API services (Game Settings > Security) so Studio uses your real save. In `GameConfig.Debug` you can set `LogRunStats = true`, `StudioGearDropChance = 1` and `StudioMap = ""` for testing, then put them back.

In Studio (game place, Play):
- [ ] 9.1 Output has no red errors, and shows `[MapLoader] map: VeloCITY`, `[GameInit] game systems started` and one `[RunStats]` warning only if CharacterStats failed
- [ ] 9.2 With `LogRunStats` on, the printed MaxHealth matches the lobby's Stats screen, and the HUD's max health matches too
- [ ] 9.3 Keys you changed in the lobby (Use Ability, Swap, Attack, Interact) work, and the HUD and the "hold Z" banner show them
- [ ] 9.4 Volume settings from the lobby apply, camera shake off stops shakes, your core tag is over your head
- [ ] 9.5 With `StudioGearDropChance = 1`, kills drop gear with a toast, and the end screen lists it with your core's Enlightenment
- [ ] 9.6 Banner and toasts sit a little lower than before

Live (published, lobby to game and back):
- [ ] 9.7 Fresh save: character screen, a run, back to the lobby. XP, Cash, Stats, gear and Enlightenment are all there
- [ ] 9.8 Quit the game mid run, rejoin the lobby: that run's (loss) rewards are there
- [ ] 9.9 Quit right after a run ends, rejoin the lobby: nothing missing
- [ ] 9.10 Two player squad with different keys and gear: each gets their own

## Other
- [x] One place for every map: `MapLoader` loads `workspace.Maps.<MapKey>` from the teleport data, `RoomData.MapAreas` and `WaveData.MapAreas` hold a map's own areas and waves
- [x] The lobby's Settings work in runs: volumes, music and effects on or off, camera shake, moving backgrounds, core tags
- [x] Core tags over heads in runs (gold for VIP)
- [x] The end screen shows the gear you found and your core's Enlightenment (and level ups)
- [ ] Skins in runs: needs the lobby's `ReplicatedStorage.Assets.Models.Characters` and its CharacterService
- [x] Quitting the game mid run now pays out like a loss (it used to save nothing)
- [x] `RunSetup.DataLoadTimeout` raised from 10 to 20 seconds so the version wait cannot run past it
- [x] Move the area banner and toasts down a little (`RoomBannerController.Settings.PopupDrop`)
