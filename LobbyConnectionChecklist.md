# Lobby connection checklist

Taken from VelocityGameConnection.md. We go through it one step at a time, top to bottom. Section 1 protects player data, so it comes first.

Steps marked **(needs lobby files)** copy code from the lobby place, which is not in this repo yet. Bring those files in first (Save to File from the lobby, or paste them in).

## 1. Save safety
- [ ] 1.1 Copy the lobby's `Server.Modules.DataManager` over the game's (adds `SaveVersion` and the double load guard) **(needs lobby files)**
- [ ] 1.2 `LobbyLink.SendToLobby`: after `DataManager.Save(Player)`, set `Payload.SaveVersion = DataManager.Get(Player, "SaveVersion")`
- [ ] 1.3 Check `PlayerManager.Init` can no longer load a player twice (comes with 1.1)
- [ ] 1.4 Later, in both places at once: session locked saves (ProfileStore or `UpdateAsync` with a lock)

## 2. One save template
- [ ] 2.1 Copy the lobby's `PlayerDataTemplate` over the game's so both have the same keys **(needs lobby files)**

## 3. Shared modules (copy whole from the lobby) **(needs lobby files)**
- [ ] 3.1 `GameText` (with all children) and `UIIcons`
- [ ] 3.2 `CoreData`
- [ ] 3.3 `EquipmentData`
- [ ] 3.4 `CharacterStats`
- [ ] 3.5 `Keybinds`
- [ ] 3.6 `SkinData`, `SkinBuilder`, `CoreTag`, `GemIcon`
- [ ] 3.7 `Leveling`
- [ ] 3.8 `StarterCharacterScripts.Client` and `MOVEMENT_INPUTS`
- [ ] 3.9 Give the shared modules one folder in the Rojo project so both places sync from it

## 4. Gear and core stats in a run
- [ ] 4.1 `RunStats(Player)` helper on the server using `CharacterStats.Compute` and `ForRun`
- [ ] 4.2 `MaxHealth`, `MaxEnergy` into `PlayerStats.new` overrides in `RunSetup`
- [ ] 4.3 Health and energy regen per player in `EnergyService` (plus Ruby's no regen in combat)
- [ ] 4.4 Weapon and ability damage multipliers in `DamageService`
- [ ] 4.5 Crits in `DamageService`
- [ ] 4.6 Damage taken multipliers (overall and melee, fire, magic)
- [ ] 4.7 Knockback multiplier and ignore knockback chance
- [ ] 4.8 Split cooldown multiplier into weapon and ability
- [ ] 4.9 `SpeedMultiplier` through `SetSpeedMultiplier("Gear", ...)`
- [ ] 4.10 `Lifesteal` through `SetLifesteal("Gear", ...)`
- [ ] 4.11 `HealingMultiplier` on Heal Burst
- [ ] 4.12 `CoinMultiplier` on kill money
- [ ] 4.13 `ExpMultiplier`, `CashMultiplier` at the end of a run

## 5. Keys in the game
- [ ] 5.1 Load `Keybinds` on the client from `DataUpdated` (first listener)
- [ ] 5.2 `CombatInput` attack, alt attack and swap use `Keybinds.Is`
- [ ] 5.3 `AbilityInput` use and swap use `Keybinds.Is`
- [ ] 5.4 HUD key labels use `Keybinds.Label` and refresh on change
- [ ] 5.5 Prompt key (gates and shop) set on the client from `Keybinds.Get("Interact")`
- [ ] 5.6 Movement binds from `Keybinds` (comes with 3.8)
- [ ] 5.7 Core ultimate bound to `Keybinds.Get("Ultimate")`
- [ ] 5.8 Ignore keys while `Keybinds.IsCapturing()`

## 6. Gear drops
- [ ] 6.1 Server side `Grant` (GUID id, `MaxItems` cap turns extras into Scrap, `DataManager.Set`)
- [ ] 6.2 Drop tables per map and difficulty, following the gameplan
- [ ] 6.3 Tell the player (toast or results screen)

## 7. Teleport data
- [ ] 7.1 Check `TeleportDataReader` against the lobby's payload (no `Armor` or `Accessories`, gear comes from the save)
- [ ] 7.2 Game to lobby payload carries `SaveVersion` (same as 1.2)

## 8. End of a run
- [ ] 8.1 `Deaths`, `Parries`, `PerfectParries`
- [ ] 8.2 `MapBest[Map][Difficulty]`, `MapRuns[Map]`
- [ ] 8.3 `CoreTime`, `CoreRuns`, `Cores[Core]`
- [ ] 8.4 `WeaponKills`, `AbilityUses`
- [ ] 8.5 `PlayTime` and Timebux for time in the game place
- [ ] 8.6 `OwnedSkins.Noob` / `OwnedSkins.Guest` for beating the Guest in Retroscity

## 9. Testing the whole loop
- [ ] 9.1 Fresh save: character screen, run, back to lobby, everything kept
- [ ] 9.2 Max Health on the lobby Stats screen matches the HUD in a run
- [ ] 9.3 Changed keys work in a run and show on the HUD
- [ ] 9.4 Quit right after a run, rejoin the lobby, nothing missing
- [ ] 9.5 Two player squad with different keys and gear

## Other
- [x] Move the area banner and toasts down a little (`RoomBannerController.Settings.PopupDrop`)
