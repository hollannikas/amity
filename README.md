# Threads of Amity (Game Boy Original DMG JRPG)

**Threads of Amity** is a homebrew 2.5D top-down JRPG for the original Nintendo Game Boy (DMG), written in RGBDS Z80/SM83 assembly ([`src/main.asm`](src/main.asm), [`src/hardware.inc`](src/hardware.inc), [`src/assets.inc`](src/assets.inc)) and accompanied by a standalone Kotlin/Swing 2bpp Sprite, Portrait & Map Tile Editor ([`tools/SpriteEditor.kt`](tools/SpriteEditor.kt)).

---

## Building & Running

Requires [RGBDS](https://rgbds.gbdev.io/) (`rgbasm`, `rgblink`, `rgbfix`) for building the Game Boy ROM, and Kotlin + OpenJDK for the visual asset editor:

```sh
# Assemble and link threads_of_amity.gb (and aretha2_demo.gb)
make

# Launch the interactive 2bpp Sprite, Portrait & Map Metatile Editor
make editor
```

---

## 1. Main Game Loop, Scenes, and Music Engine

### Boot & Hardware Initialization (`EntryPoint`)

At power-on (`$0100` -> `EntryPoint` at `$0150`), the engine performs a deterministic hardware setup:
1. **Interrupts & Stack**: Disables hardware interrupts (`di`) and initializes the stack pointer at the top of High RAM (`ld sp, $FFFE`).
2. **APU Master Enable**: Powers on the Game Boy sound controller (`rNR52 = $80`), sets master left/right volume (`rNR50 = $77`), and routes all four audio channels to stereo L+R (`rNR51 = $FF`).
3. **Safe LCD Shutdown (`DisableLCD`)**: Waits for VBlank (`rLY >= 144`) before clearing `rLCDC` bit 7 so the PPU is never halted mid-scanline.
4. **HRAM OAM DMA (`InitDMARoutine`)**: Copies a 10-byte OAM DMA routine into High RAM (`hOAMDMA` at `$FF80`), which triggers a 160-byte transfer from `wOAMBuffer` (`$C000..$C09F`) to hardware `_OAMRAM` (`$FE00..$FE9F`).
5. **Base VRAM & DMG Palettes**: Loads the 256-tile base `TilesetData` (4,096 bytes: UI box borders, bitmap font, icons, and default sprites) into `_VRAM` (`$8000..$8FFF`) and configures DMG monochrome palettes:
   - `rBGP = %11100100` (`0`=White, `1`=Light Gray, `2`=Dark Gray, `3`=Black)
   - `rOBP0 = %11010000` (`0`=Transparent, `1`=Opaque White, `2`=Light Gray, `3`=Black — allowing sprites to have opaque white interiors while color `0` masks the background)

### 60 Hz Synchronized Main Game Loop (`MainLoop`)

The Game Boy VBlank period lasts 10 scanlines (`rLY = 144..153`, or 1,140 M-cycles). Because lightweight game states (such as NPC dialogue or menu cursor updates) complete in far fewer than 1,140 M-cycles, a naive `rLY >= 144` check would execute multiple loop iterations inside a single VBlank.

To guarantee a locked **60.0 Hz (1 tick per frame)** across all scenes, `MainLoop` uses a two-stage barrier:

```asm
MainLoop:
.waitFrameEnd:
    ld a, [rLY]
    cp 144
    jr nc, .waitFrameEnd ; 1. If still inside previous VBlank, wait for active display (LY < 144)
    call WaitVBlank      ; 2. Wait for the start of the next VBlank (LY == 144)
    call hOAMDMA         ; 3. Transfer wOAMBuffer ($C000) to OAM ($FE00) inside VBlank
```

On every 60 Hz tick, `MainLoop` then:
1. Increments the global frame counter (`wFrameCounter`) used for sprite walk-cycle animation and enemy patrol timing.
2. Polls the two-line joypad matrix (`ReadJoypad`), debouncing and computing both currently held buttons (`wJoyHeld`) and newly pressed rising edges (`wJoyPressed = (old ^ new) & new`).
3. Advances the 4-channel background music sequencer (`call UpdateMusic`).
4. Dispatches to the active scene handler based on `wGameState`.

### Scenes & State Machine (`wGameState`)

| State Constant | ID | Scene Handler | Description |
| :--- | :-: | :--- | :--- |
| `STATE_SPLASH` | `0` | `InitSplashScreen` / `UpdateSplashScreen` | Draws the ornamental title plaque, animates the playable heroes walking in place, and starts the intro overture (`TRACK_INTRO`). Pressing `START` or `A` transitions to character selection. |
| `STATE_CHAR_SELECT` | `1` | `InitCharSelect` / `UpdateCharSelect` | Presents a **4-row scrolling selection window** (`wSelectScroll`, `wSelectedChar`) across 5 playable heroes (**M: Aria**, **F: Sakura**, **NB: Orion**, **NB: Ruusu**, **GF: Mara**). Uses `CopyDataVRAM` (polling `rSTAT` bit 1 for HBlank/VBlank access) so scrolling the list updates sprite tiles (`$8D00..$8EFF`) and text rows without ever turning off the LCD or blinking the screen. |
| `STATE_OVERWORLD` | `2` | `InitOverworld` / `EnterOverworldMap` / `UpdateOverworld` | Renders the scrolling 256×256 pixel (16×16 metatile) world map on `_SCRN0` (`$9800`) and pins a **4-row rounded-border HUD** to the bottom of the screen (`WY=112, WX=7`) using the hardware Window Layer `_SCRN1` (`$9C00`). |
| `STATE_DIALOGUE` | `3` | `InitNPCDialogue` / `UpdateNPCDialogue` | Displays an 80×64 pixel (10×8 tile) character or NPC portrait in the upper half of the screen (`$8800..$8CFF` mapped to rows `0..7`) and a double-bordered dialogue box in rows `8..17`, stepped via `wDialogPage`. |
| `STATE_BATTLE` | `4` | `InitBattle` / `UpdateBattle` | Turn-based battle scene with a 32×32 Shadow Fiend (`$8700..$87FF`) or 64×48 Boss Terf (`$8800..$8AFF`) arena, hero/monster stats, and a `FIGHT` / `RING MAGIC` / `RUN` command menu. |
| `STATE_GAME_OVER` | `5` | `InitGameOver` / `UpdateGameOver` | Displays the defeat screen, plays the one-shot Game Over dirge (`TRACK_GAMEOVER`), and returns to Character Selection on button press. |
| `STATE_INVENTORY` | `6` | `InitInventory` / `UpdateInventory` | Renders a 4×2 grid of rounded-edge item cells (`4×4` tiles each) around 16×16 OAM item sprites, a single-row bottom item name bar, D-Pad cursor navigation, and `A`-button item activation. |

### 4-Channel DMG Music & SFX Engine (`UpdateMusic`)

The audio engine drives all four native Game Boy sound channels simultaneously from a pointer-driven 16th-note step sequencer:

- **Sequencer State**:
  - `wMusicPlaying`: Active track ID (`TRACK_NONE = 0`, `TRACK_INTRO = 1`, `TRACK_GAME = 2`, `TRACK_BATTLE = 3`, `TRACK_VICTORY = 4`, `TRACK_GAMEOVER = 5`).
  - `wMusicTempo`: Frames per 16th-note step (`6` frames/step ≈ 125 BPM for the Intro Overture; `9` frames/step ≈ 83 BPM for the relaxed Overworld BGM; `5` frames/step ≈ 150 BPM for the MSX tactical-alert style Battle BGM and Victory Fanfare; `7` frames/step for the Game Over Dirge).
  - `wMusicStep` & `wMusicStepMask`: Current step index masked by `$7F` (128-step / 8-bar looping tracks) or `$1F` (32-step / 2-bar jingles).
  - `wMusicLoop`: `1` for looping background tracks; `0` for one-shot jingles (automatically calls `StopMusic` when `wMusicStep` wraps to `0`).
  - `wMusicCh2Ptr`, `wMusicCh1Ptr`, `wMusicCh3Ptr`, `wMusicCh4Ptr`: 16-bit pointers to the active track's per-step note tables (`0 = NOTE_HOLD`, `$FF = NOTE_REST`, `1..37 = N_C3..N_C6` into `MusicFreqTable`).
- **Channel Roles**:
  - **Channel 2 (Pulse 2 — `rNR21..rNR24`)**: 50% duty cycle (`$80`) lead melody with per-track volume envelope decay (`$E3` for fast tracks, `$D4` for warm overworld sustain).
  - **Channel 1 (Pulse 1 — `rNR10..rNR14`)**: 25% duty cycle (`$40`) baroque arpeggios, counter-melodies, and 3rd/4th/6th harmonies.
  - **Channel 3 (Wave — `rNR30..rNR34`, `_AUD3WAVERAM`)**: Loads a 16-byte (32-sample) asymmetric resonant bass waveform (`CustomWaveBass`) into `$FF30..$FF3F` while the DAC is disabled (`rNR30 = 0`), then plays octave-jumping and walking basslines one octave below the pulse table.
  - **Channel 4 (Noise — `rNR41..rNR44`)**: Synthesizes a 4-piece drum kit (`D_KICK`, `D_SNARE`, `D_HAT`, `D_OHAT`) via polynomial counter and envelope presets.
- **Non-Destructive SFX Multiplexing**:
  - UI and gameplay sound effects (`PlaySFXCursor`, `PlaySFXConfirm`, `PlaySFXEncounter`, `PlaySFXLevelUp` on Channel 1; `PlaySFXAttack`, `PlaySFXHit` on Channel 4) set lock timers (`wSFXLockTimer` / `wSFXLockCh4`). While a lock timer is non-zero, `UpdateMusic` yields that hardware channel to the sound effect while the remaining music channels keep playing in sync.

---

## 2. Map, NPCs, Quests, and Inventory Engine

### 2.5D Overworld Map & Window HUD Engine

- **Metatile Compression (`OverworldMapData` & `LoadOverworldMap`)**:
  - The 256×256 pixel overworld is defined as a 16×16 grid of 16×16 pixel metatiles (`OverworldMapData`, 256 bytes).
  - Each metatile ID (`0..7`) maps to four contiguous 8×8 tiles (`Top-Left`, `Top-Right`, `Bottom-Left`, `Bottom-Right`) loaded from `MapMetatilesData` into VRAM `$8800..$89FF` (`base_tile = $80 + metatile_id * 4`).
  -Metatile IDs: `0` = Grass (passable), `1` = Cobblestone Road (passable), `2` = 2.5D Forest Tree (solid), `3` = Stone Pillar Wall (solid), `4` = River Water (solid), `5` = Shrine/House Roof (solid), `6` = Closed Treasure Chest (solid), `7` = Opened Treasure Chest (solid).
- **Collision & Camera (`CheckMapCollision` & `UpdateCameraScroll`)**:
  - Movement along X and Y is resolved independently per frame so the player slides smoothly along walls. `CheckMapCollision` probes the metatile under the player's feet (`(PlayerWorldX + 7) >> 4`, `(PlayerWorldY + 12) >> 4`) and blocks movement when `metatile_id >= 2`.
  - `UpdateCameraScroll` centers the camera on the player (`rSCX = clamp(PlayerWorldX - 72, 0, 96)`, `rSCY = clamp(PlayerWorldY - 48, 0, 144)`) within the 160×112 pixel map viewport above the bottom HUD.
- **4-Row Rounded-Border Bottom HUD (`DrawOverworldHUD`)**:
  - Reuses the 8 rounded-edge border tiles from `InvGridBorderTiles` (loaded into free overworld VRAM `$8A00..$8A7F`, tiles `$A0..$A7`) on the Game Boy Window Layer (`_SCRN1` at `$9C00`, `WY=112, WX=7`).
  - Inside the rounded frame, two 8-tile (32-sub-step) proportional gauges (`DrawHudBar8Tiles`, using 0/4..4/4 fill tiles `$6B..$6F`) display:
    - **Row 1**: `♥HP:[████████]34/34` (`(wHeroHP * 32) / wHeroMaxHP`)
    - **Row 2**: `★XP:[████░░░░]50%L01` (percentage `(wHeroXP * 100) / wHeroNextXP` towards the next level)

### NPCs & Quest Engine (Gaius, Bob's Dress Quest, & Hidden Treasure Chest)

- **Entity Rendering & OAM Allocation (`RenderOverworldSprites`)**:
  - Hardware OAM (`40` sprites total = ten 16×16 metasprites) is partitioned each frame:
    - `OAM 0..3`: Player's 4-directional walking metasprite (`$D0..$EF`, alternating Frame 0 and Frame 1 every 8 steps via `wWalkDistance`).
    - `OAM 4..7`: Shrine guide **NPC Gaius** (`$F8..$FB`) at `(120, 72)`.
    - `OAM 8..11`: Quest giver **NPC Bob** (`$F0..$F3`) at `(152, 72)`.
    - `OAM 12..39`: Up to 7 visible patrolling enemies (`Index 0` = **Boss Terf** at `$F4..$F7`; `Indices 1..8` = **Shadow Fiends** at `$FC..$FF`).
  - Entities with `WorldY - CameraY >= 100` are clipped so OAM sprites never draw over the bottom Window HUD.
- **Bob's Silk Dress Quest (`CheckBobInteraction` & `CheckChestInteraction`)**:
  - Tracked via `wBobQuestState` (`0` = bearded man bound by the weave, `2` = freed woman in dress) and `wHasDress` (`0` = dress in chest, `1` = dress in inventory, `2` = given to Bob).
  - **Before Finding the Dress (`wBobQuestState == 0, wHasDress == 0`)**:
    - `EnterOverworldMap` loads Bob's bearded 16×16 sprite (`CustomSpritesTiles + 0`) into `$8F00` (`$F0..$F3`).
    - Talking to Bob (`wDialogPage = 3`) loads `PortraitBobBeardedTiles` into `$8800` and prompts the player to find the **Silk Dress** hidden in a chest past the southern bridge.
  - **Finding the Silk Dress (`CheckChestInteraction` at `X=160, Y=208`, Row 13 Col 10)**:
    - Walking up to or pressing `A` at the closed chest sets `wHasDress = 1`, adds `ITEM_SILK_DRESS` (`1`) to `wInventory` via `AddItemToInventory`, plays the victory fanfare (`InitVictoryJingle`), and opens `wDialogPage = 6`.
    - When `LoadOverworldMap` redraws the map, it checks `wHasDress != 0` whenever it encounters Metatile `6` and substitutes Metatile `7` (Opened Treasure Chest).
  - **Freeing Bob from the Weave (`wHasDress == 1` -> `wDialogPage = 4` -> `.transformBobToShe` -> `wDialogPage = 5`)**:
    - Talking to Bob with the dress opens `wDialogPage = 4` (`PortraitBobBeardedTiles`). Pressing `A` invokes `.transformBobToShe`, which removes `ITEM_SILK_DRESS` from `wInventory` (`RemoveItemFromInventory`), sets `wBobQuestState = 2` and `wHasDress = 2`, plays the victory fanfare, loads `PortraitBobFemTiles` (`♦BOB (SHE/HER)♦`), heals the hero, and updates Bob's overworld sprite in `$8F00` to `CustomSpritesTiles + 64` (woman wearing the dress).

### Inventory & Equippable Item Engine (`STATE_INVENTORY`)

- **Storage & Compaction (`wInventory`, `AddItemToInventory`, `RemoveItemFromInventory`)**:
  - `wInventory` is an 8-byte array in WRAM representing a 4×2 grid of slots (`0 = ITEM_NONE`, `1 = ITEM_SILK_DRESS`, `2 = ITEM_BINDER`).
  - `AddItemToInventory` inserts an item ID into the first empty (`0`) slot.
  - `RemoveItemFromInventory` locates the first matching item ID, removes it, and shifts subsequent slots left so no empty gaps remain.
- **Grid Rendering & 16×16 Item Sprites (`InitInventory`, `DrawInventoryGrid`, `RenderInventorySprites`)**:
  - Pressing `A` (or `SELECT`) on the overworld when not adjacent to an NPC or chest opens the inventory.
  - Loads `InvGridBorderTiles` into `$8800..$88FF` (`$80..$87` = unselected rounded-edge cell border; `$88..$8F` = thick double-rounded highlight border for the active `wInvCursor` cell) and `ItemSpritesTiles` into `$8D00..` (`$D0 + (item_id - 1) * 4`).
  - Draws eight `4×4`-tile rounded cells on `_SCRN0` and centers each occupied slot's 16×16 item metasprite inside its cell (`OAM 0..31`), while printing the selected item's name on the single bottom text row (Row 16).
- **Equippable Binder for `GF: MARA` (`wBinderEquipped`)**:
  - When starting the game as **Mara (`GF: MARA`)**, `InitOverworld` seeds `wInventory` with `ITEM_BINDER` (`2`).
  - Selecting the Binder in the inventory and pressing `A` toggles `wBinderEquipped` (`0 <-> 1`), plays a chime, and switches the bottom status label between `"BINDER: MARA F"` and `"BINDER: MARA M"`.
  - Returning to the overworld (`LoadSelectedPlayerSprites`) inspects `wBinderEquipped` when `wSelectedChar == CHAR_MARA` and loads either `SpritesMaraFTiles` (`MaraF` female expression) or `SpritesMaraMTiles` (`MaraM` male expression) into `$8D00..$8EFF`.

---

### Side Note: Current Architecture & Space Optimization Opportunities

> **Note**: The map, NPC, quest, and inventory systems above are intentionally written in a **straightforward, naive style** to keep the assembly easy to read, debug, and edit directly alongside [`tools/SpriteEditor.kt`](tools/SpriteEditor.kt). They are **not yet optimized for ROM or VRAM space**, and currently nearly fill the 32 KB (2-bank) cartridge (`ROM0` + `ROMX[1]`).

Key areas where space and structure can be optimized in future iterations:
1. **Uncompressed 2bpp Portraits & Sprites**:
   - Each 80×64 dialogue portrait (`PortraitAriaTiles`, `PortraitSakuraTiles`, `PortraitOrionTiles`, `PortraitRuusuTiles`, `PortraitMaraTiles`, `PortraitGaiusTiles`, `PortraitTerfTiles`, `PortraitBobBeardedTiles`, `PortraitBobFemTiles`) is stored as a raw, uncompressed 80-tile block (`1,280` bytes each = `11,520` bytes total), including blank corner/margin tiles. Applying RLE/LZ compression or storing bounding-box sub-tilemaps would reclaim 50–65% of portrait ROM space.
   - Left and Right walking animations (`Sprites*Tiles`) are stored as separate 8-tile blocks rather than horizontally flipping the Left tiles in hardware via the OAM `OAMF_XFLIP` attribute bit, which would save 128 bytes per character (`768` bytes across the 6 hero sprite banks).
2. **Duplicate Tiles Across Asset Sections**:
   - For convenience in the visual Sprite Editor, `TilesetData` (`$8000..$8FFF`) still contains legacy copies of map metatiles (`$10..$27`), the Shadow Fiend battle graphic (`$70..$7F`), and hero/portrait tiles (`$80..$EF`) that are also stored in `MapMetatilesData`, `BattleFiendTiles`, and `PortraitSakuraTiles`.
3. **Hardcoded NPC & Dialogue Dispatch**:
   - `CheckNPCInteraction`, `CheckBobInteraction`, and `CheckChestInteraction` each have their own proximity routine, and `DrawNPCDialoguePage` uses explicit per-page `PrintString` calls (`wDialogPage = 0..7`) rather than a unified data-driven entity table (`{x, y, sprite_tile, portrait_ptr, dialog_script_ptr}`) and inline newline control codes (`\n`) inside strings.
4. **Linear 128-Byte Step Tables in the Music Engine**:
   - Each song channel is stored as a flat 128-byte step array (`4 × 128 = 512` bytes per BGM track) where held notes occupy `0` bytes per 16th-note step, rather than `(note, duration)` pairs or pattern-order tables.
