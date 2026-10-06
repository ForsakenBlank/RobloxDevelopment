# Velocity build plan

Built from `Velocity/VelocityGameplan.md` and the `Velocity UI v6` design. One round at a time, PC first.

## Round 1: done (2026-10-04, lobby place)

- **Menu** (on join): VELOCITY logo, six stair-stepped buttons (PLAY, LOADOUT, CORE, SQUAD, STATS, CHARACTER, keys 1-6), cash and SHOP, black bars with the level bar. The camera faces your character, which stands on the right of the screen.
- **HUD mode** (walking around): name plate with your core, small cash and SHOP, the MENU grid, the squad list top right. **B** switches between menu and HUD through a fade to black. (M was taken: it's the Sit key.)
- **Character screen**:
  - First join: Custom Character with a cape tick box, or your Roblox Avatar; then a core, 2 weapons, 2 abilities, and BEGIN.
  - Later visits (CHARACTER button): a skin base row with a SKINS popup, and the Customise box (face plus a colour picker for each body part), locked behind the gamepass.
  - Your character previews live on a pedestal on the left; drag it to turn it.
- **Skins**:
  - The models in `ReplicatedStorage.Assets.Models.Characters` are now used, through `Shared.SkinData` (list, prices, unlocks) and `Shared.SkinBuilder`.
  - SkinBuilder fixes missing root parts and joints, converts BusinessMan from R15 to R6, and strips every script.
  - Players spawn in their saved look (`CharacterService`).
  - Buying skins with Cash works.
  - Gamepass prompt: Robux needs the pass IDs; Timebux works.
- **Dev mode**: ForsakenBlank gets a `DEV: UNLOCK ALL` switch on the top bar. While it's on you own every skin and gamepass and every level-locked weapon/ability (saved, so it stays on until switched off).
- **Security**: the PizzaGuy model had a hidden backdoor script (`require(<asset id>)`), now removed. SkinBuilder strips scripts from every skin it builds, so a future infected model can't run.
- **Old UI**:
  - The old side menu and XP bar are hidden.
  - The old character creation module and GUI were moved to `ServerStorage._OldLobby`.
  - PLAY/LOADOUT/CORE/SQUAD/STATS still open the old panels until they're redesigned.

## Round 2 and 3: done (2026-10-04)

- The UI now lives in StarterGui (LobbyMenu, CharacterUI, PlayUI, VelocityOverlay), built by `ServerStorage.Tools.LobbyUIBuilder`. The screens are switched off in the editor; the game turns them on.
- **Play screen** replaces the old GameEntry:
  - map card (from `GameConfig.Lobby.Maps`)
  - difficulty
  - modifiers (none yet)
  - squad slots you click to open or close
  - START / OPEN SQUAD / JOIN SQUAD / START NOW
  - a 3-2-1 GET READY with CANCEL before every run
- Hover cards on cores, weapons, abilities and equipment.
- Bigger small text and key letters.
- **Timebux** earned: 1 every 2.5 minutes in the lobby.
- `Shared.UIIcons` is ready for the design's icons. Paste the image ids in, or send them over.

## Round 5: done (2026-10-04)

- **Loadout screen** (`StarterGui.LoadoutUI`, `Client.Modules.LoadoutUI`):
  - WEAPONS / ABILITIES: details on the left with segment stats and EQUIP · SLOT 1 / SLOT 2; the two equipped and every item on the right.
  - EQUIPMENT: armour and accessory slots and the bonuses they add up to on the left; filter chips, the picked item and its EQUIP / TAKE OFF, and every item on the right.
  - Equipment uses its icons (`eq_boots`, `eq_helmet`, `eq_legs`, `eq_acc`). Chestplates have no icon yet and keep their emoji.
- **Core screen** (`StarterGui.CoreUI`, `Client.Modules.CoreUI`):
  - the four cores, the big gem, Enlightenment (level, bar, next milestone)
  - stats now / next level, milestones, ultimate, team aura, drawbacks
  - ATTUNE (press twice)
  - `Shared.CoreData` was rewritten to the gameplan's core system (max core level 30).
- **Stats screen** (`StarterGui.StatsUI`, `Client.Modules.StatsUI`): OVERVIEW, MAPS, CRYSTALS, GEAR. New save keys: `PlayTime` (counted in the lobby), `Deaths`, `Parries`, `PerfectParries`, `MapBest`, `MapRuns`, `CoreTime`, `CoreRuns`, `WeaponKills`, `AbilityUses`.
- **Shop** (`StarterGui.ShopUI`, `Client.Modules.ShopUI`), from the SHOP buttons:
  - CHARACTERS: buy cash skins. EQUIP opens the character screen with that skin picked.
  - GAMEPASSES: Robux or Timebux.
- Overhead core tag redone: gem, name and level each have their own space, so long names no longer run into the level.
- The menu background text moves 20% slower.
- Scrolling lists inside the tilted panels each sit in their own CanvasGroup (`<Name>Clip`), since Roblox doesn't clip a rotated ScrollingFrame. This also fixes the Squad screen's lists.
- The old Loadout and Cores GUIs and modules were moved to `ServerStorage._OldLobby`.

## Round 6: done (2026-10-04)

- **All text in one place: `ReplicatedStorage.Modules.Shared.GameText`**, with a child module per area:
  - Common, Menu, Play, Squad, Character, Buy, Loadout, CoreMenu, Stats, Shop, Settings, Info, Messages, Items, Cores, Characters, Maps, Results.
  - It holds every menu label, button, pop-up message and server reply, plus the item, core, skin, gamepass and map descriptions and the Info pages.
  - `{Name}` blanks are filled in by the game.
  - The data modules (LoadoutData, EquipmentData, CoreData, SkinData, GameConfig) now only hold numbers and keys.
  - Each built label keeps its key (the `TextKey` attribute) and gets its text from GameText when the game runs, so editing GameText needs no rebuild.
- **Settings** (grey cog next to SHOP), with four tabs:
  - SOUND: master, music and effects volume; menu click sounds.
  - GAME: camera shake (saved for runs), moving backgrounds, hover info, other players' core tags.
  - CONTROLS: the key list.
  - INFO: 10 pages on the game, cores and the equipment system, with the gear icons.
  - Saved in `Settings` through `Server.Services.SettingsService`. The list and defaults are in `Shared.SettingsData`.
- **Head tag**: no tilt. VIPs get a gold tag with a shine that sweeps across it (`Client.Modules.CoreTags`).
- All the new gear icons are in `Shared.UIIcons`.
  - Armour slots use `armour_helmet` / `armour_chest` / `armour_boots`.
  - `retro_boots` and `city_wristband` have IDs that Roblox can't find; they need re-sending.

## You need to do

1. **Playtest round 1** (the MCP can't drive a live playtest). Check:
   - Your first join with a fresh save (set `CharacterCreated` false), then BEGIN.
   - Rejoin: you should land on the menu.
   - Press B to walk around, then B to come back.
   - CHARACTER: try SKINS with UNLOCK ALL on, equip each skin, SAVE, and check that you respawn in it.
   - Try Roblox Avatar.
   - Customise colours.
2. **Upload images** (Creator Dashboard or Studio's Asset Manager). Put the **image** id (not the decal id) in the right place:
   - `icons/png/face_grin.png`, `face_focused.png`, `face_smug.png`, `face_chill.png`, `face_angry.png`, and optionally `face_smile.png`: put the ids in `ReplicatedStorage.Modules.Shared.SkinData` under `Faces`, in each `Image = ""`.
   - Later rounds: `gp_*.png` (shop), `cash.png` / `timebux.png`, the new weapon/ability icons (`w_spear`, `w_fists`, `w_partygun`, `a_zap`, `a_fireball`, `a_potion`, `a_lunge`).
3. **Create the gamepasses** on the website (+2 Accessory Slots 299, 2x Exp 349, Customise 99, VIP 499) and paste each id into `SkinData.Passes[...].GamePassId`.
4. Share animation `121606719249688` (Swing) with the experience; it still fails to load.

## Next rounds (one at a time)

1. **Polish round 1** from your playtest notes.
2. ~~Play screen~~ done. Still needed: real map pictures, and modifiers once the game place supports them.
3. ~~Squad screen~~ done:
   - password with show/hide/new
   - privacy (public / friends / password)
   - invites, kick
   - ready-up; the leader starts, or it starts when everyone is ready
   - Still needed: proper head-face textures for Customise faces (the face icons are menu tiles).
4. ~~Loadout screen~~ done. Still needed: a chestplate icon (`eq_chest` in `Shared.UIIcons`, then add `Chestplate = "eq_chest"` to `SLOT_ICONS` in `Shared.EquipmentData`).
5. ~~Core screen~~ done. The core passives, ultimates and auras still need making in the game place (round 12).
6. ~~Stats screen~~ done. The game place has to write the new stat keys at the end of a run (round 11).
7. ~~Shop screen~~ done. Still needed: the gamepass ids (see "You need to do" step 3).
7b. **Equipment system** (gameplan "Velocity Equipment System"):
    - Gear as owned items: rarity, 1-5 stars and rolled stat lines.
    - Armour sets and accessory types, core charms and cosmetics.
    - Dismantle for Scrap, then reroll.
    - The icons are already in UIIcons. The current 14 starter items in EquipmentData get replaced.
8. **Timebux and gamepass effects**:
   - Timebux earning is done in the lobby (1 per 2.5 minutes); the game place still needs the same.
   - VIP: daily $750 + 5 Timebux, golden lobby header, 1.25x EXP and coins.
   - 2x EXP.
   - +2 accessory slots.
9. **Console**: focus arrow, A/B prompts, LB/RB tabs, D-pad navigation.
10. **Mobile**: landscape layout, 44pt touch targets, keep the thumbstick and jump corners free.
11. **Game place**:
    - Copy `SkinData`, `SkinBuilder` and the spawn code so skins show in runs.
    - Add the new save keys to its `PlayerDataTemplate`: `Skin`, `OwnedSkins`, `Face`, `BodyColours`, `CustomiseOn`, `Timebux`, `Passes`, `DevUnlockAll`, and the stats ones (`PlayTime`, `Deaths`, `Parries`, `PerfectParries`, `MapBest`, `MapRuns`, `CoreTime`, `CoreRuns`, `WeaponKills`, `AbilityUses`). Then add to them at the end of each run.
    - Read `Map` from the teleport data (VeloCITY or RetroCity).
    - Copy the new `Shared.CoreData`, `CoreTag`, `UIIcons` and `GemIcon` so the core tag and core levels match.
    - Grant `OwnedSkins.Noob` / `OwnedSkins.Guest` for beating Guest in Retroscity.
    - Build the **in-game HUD** (GameHUD design).
12. **Game content** from the gameplan:
    - Weapons: spear, fists, party gun.
    - Abilities: Zap, Fireball, Potion.
    - Core passives, ultimates and auras in combat.
13. **Cleanup**: delete `ServerStorage._OldLobby` and the hidden old MainUI pieces once nothing needs them.
