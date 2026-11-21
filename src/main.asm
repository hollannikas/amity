; ===========================================================================
; THREADS OF AMITY (Game Boy Original DMG JRPG Demo)
; ===========================================================================

INCLUDE "src/hardware.inc"
INCLUDE "src/assets.inc"

; Game States
DEF STATE_SPLASH      EQU 0
DEF STATE_CHAR_SELECT EQU 1
DEF STATE_OVERWORLD   EQU 2
DEF STATE_DIALOGUE    EQU 3
DEF STATE_BATTLE      EQU 4
DEF STATE_GAME_OVER   EQU 5
DEF STATE_INVENTORY   EQU 6

; Inventory Item IDs & Grid Constants
DEF ITEM_NONE         EQU 0
DEF ITEM_SILK_DRESS   EQU 1
DEF INV_SLOTS         EQU 8 ; 4 columns x 2 rows grid of 16x16 items

; Character Classes / Genders
DEF CHAR_MALE         EQU 0
DEF CHAR_FEMALE       EQU 1
DEF CHAR_NONBINARY    EQU 2

; ===========================================================================
; Interrupt Vectors & Header
; ===========================================================================
SECTION "VBlank Interrupt", ROM0[$0040]
    reti

SECTION "LCD STAT Interrupt", ROM0[$0048]
    reti

SECTION "Timer Interrupt", ROM0[$0050]
    reti

SECTION "Serial Interrupt", ROM0[$0058]
    reti

SECTION "Joypad Interrupt", ROM0[$0060]
    reti

SECTION "Header", ROM0[$0100]
    nop
    jp EntryPoint

    ; Nintendo Logo + Header reserved space ($0104 - $014F), filled by rgbfix
    ds $0150 - @, 0

; ===========================================================================
; Main Code Section
; ===========================================================================
SECTION "Main", ROM0[$0150]

EntryPoint:
    di
    ld sp, $FFFE

    ; Initialize Audio Hardware for SFX
    ld a, $80
    ld [rNR52], a
    ld a, $77
    ld [rNR50], a
    ld a, $FF
    ld [rNR51], a

    ; Turn off LCD safely
    call DisableLCD

    ; Copy OAM DMA routine to HRAM
    call InitDMARoutine

    ; Clear WRAM and Shadow OAM
    call ClearShadowOAM

    ; Load Tileset into VRAM ($8000)
    ld hl, TilesetData
    ld de, _VRAM
    ld bc, TilesetDataEnd - TilesetData
    call CopyData

    ; Set Default Palettes (BGP = %11100100, OBP0 = %11010000 so sprites have 0=Trans, 1=White, 2=LightGray, 3=Black!)
    ld a, %11100100
    ld [rBGP], a
    ld a, %11010000
    ld [rOBP0], a
    ld a, %11100000
    ld [rOBP1], a

    xor a
    ld [rSCX], a
    ld [rSCY], a
    ld [wFrameCounter], a
    ld [wJoyHeld], a
    ld [wJoyPressed], a
    ld [wSelectedChar], a

    ; Start at Splash Screen
    call InitSplashScreen

MainLoop:
    ; If the previous state's update finished before VBlank ended (e.g. Dialogue),
    ; wait for active display (LY < 144) first so MainLoop runs strictly once per frame (60 Hz)
.waitFrameEnd:
    ld a, [rLY]
    cp 144
    jr nc, .waitFrameEnd
    call WaitVBlank
    ; Run OAM DMA during VBlank
    call hOAMDMA

    ; Increment global frame counter
    ld hl, wFrameCounter
    inc [hl]

    ; Read Joypad
    call ReadJoypad

    ; Update background music sequencer
    call UpdateMusic

    ; Dispatch based on current Game State
    ld a, [wGameState]
    cp STATE_SPLASH
    jr z, .doSplash
    cp STATE_CHAR_SELECT
    jr z, .doCharSelect
    cp STATE_OVERWORLD
    jr z, .doOverworld
    cp STATE_DIALOGUE
    jr z, .doDialogue
    cp STATE_BATTLE
    jr z, .doBattle
    cp STATE_GAME_OVER
    jr z, .doGameOver
    cp STATE_INVENTORY
    jr z, .doInventory
    jr MainLoop

.doSplash:
    call UpdateSplashScreen
    jr MainLoop

.doCharSelect:
    call UpdateCharSelect
    jr MainLoop

.doOverworld:
    call UpdateOverworld
    jr MainLoop

.doDialogue:
    call UpdateNPCDialogue
    jr MainLoop

.doBattle:
    call UpdateBattle
    jr MainLoop

.doGameOver:
    call UpdateGameOver
    jr MainLoop

.doInventory:
    call UpdateInventory
    jr MainLoop

; ===========================================================================
; Splash Screen State
; ===========================================================================
InitSplashScreen:
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    ; Draw outer ornamental frame (20x18)
    ld b, 0
    ld c, 0
    ld d, 20
    ld e, 18
    call DrawDialogBox

    ; Draw inner title plaque (16x6 at x=2, y=2)
    ld b, 2
    ld c, 2
    ld d, 16
    ld e, 6
    call DrawDialogBox

    ; Print Title Text
    ld hl, _SCRN0 + (3 * 32) + 3
    ld de, StrSplashTitle1
    call PrintString

    ld hl, _SCRN0 + (5 * 32) + 3
    ld de, StrSplashTitle2
    call PrintString

    ld hl, _SCRN0 + (6 * 32) + 4
    ld de, StrSplashTitle3
    call PrintString

    ; Draw Materia Portrait Preview on Splash Screen or Sword / Stars?
    ; Let's place the 3 Hero Sprites standing on the splash screen!
    ; And print "PRESS START" + credits
    ld hl, _SCRN0 + (12 * 32) + 4
    ld de, StrPressStart
    call PrintString

    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrCopyright
    call PrintString

    ; Place the 3 playable heroes on the splash screen (y=80, x=56, 80, 104)
    ; Hero M at OAM 0..3
    ld a, 80
    ld [wSpriteY], a
    ld a, 52
    ld [wSpriteX], a
    ld a, $D0
    ld [wSpriteTile], a
    ld a, 0
    call SetMetaSprite16x16

    ; Hero F at OAM 4..7
    ld a, 80
    ld [wSpriteY], a
    ld a, 80
    ld [wSpriteX], a
    ld a, $D8
    ld [wSpriteTile], a
    ld a, 4
    call SetMetaSprite16x16

    ; Hero NB at OAM 8..11
    ld a, 80
    ld [wSpriteY], a
    ld a, 108
    ld [wSpriteX], a
    ld a, $E0
    ld [wSpriteTile], a
    ld a, 8
    call SetMetaSprite16x16

    ld a, STATE_SPLASH
    ld [wGameState], a

    call InitIntroMusic

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

UpdateSplashScreen:
    ; Animate the 3 heroes walking in place on splash screen
    ld a, [wFrameCounter]
    and %00010000
    jr z, .frame0
    ld b, 4
    jr .applyAnim
.frame0:
    ld b, 0
.applyAnim:
    ; Hero M
    ld a, 80
    ld [wSpriteY], a
    ld a, 52
    ld [wSpriteX], a
    ld a, $D0
    add b
    ld [wSpriteTile], a
    ld a, 0
    call SetMetaSprite16x16

    ; Hero F
    ld a, 80
    ld [wSpriteY], a
    ld a, 80
    ld [wSpriteX], a
    ld a, $D8
    add b
    ld [wSpriteTile], a
    ld a, 4
    call SetMetaSprite16x16

    ; Hero NB
    ld a, 80
    ld [wSpriteY], a
    ld a, 108
    ld [wSpriteX], a
    ld a, $E0
    add b
    ld [wSpriteTile], a
    ld a, 8
    call SetMetaSprite16x16

    ; Check START or A button
    ld a, [wJoyPressed]
    and PADF_START | PADF_A
    ret z

    call PlaySFXConfirm
    call InitCharSelect
    ret

; ===========================================================================
; Character Selection State (M / F / NB)
; ===========================================================================
InitCharSelect:
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    ; Restore all 3 characters' front-facing sprite tiles ($D0..$E7) to VRAM $8D00
    ld hl, SelectScreenHeroSprites
    ld de, $8D00
    ld bc, 24 * 16
    call CopyData

    ; Top Header Box (20x4 at 0,0)
    ld b, 0
    ld c, 0
    ld d, 20
    ld e, 4
    call DrawDialogBox

    ld hl, _SCRN0 + (1 * 32) + 2
    ld de, StrSelectHeader1
    call PrintString
    ld hl, _SCRN0 + (2 * 32) + 3
    ld de, StrSelectHeader2
    call PrintString

    ; Options Box (20x8 at 0,4)
    ld b, 0
    ld c, 4
    ld d, 20
    ld e, 8
    call DrawDialogBox

    ld hl, _SCRN0 + (5 * 32) + 6
    ld de, StrOptMale
    call PrintString

    ld hl, _SCRN0 + (7 * 32) + 6
    ld de, StrOptFemale
    call PrintString

    ld hl, _SCRN0 + (9 * 32) + 6
    ld de, StrOptNB
    call PrintString

    ; Bottom Profile Description Box (20x6 at 0,12)
    ld b, 0
    ld c, 12
    ld d, 20
    ld e, 6
    call DrawDialogBox

    call DrawCharSelectDetails

    ld a, STATE_CHAR_SELECT
    ld [wGameState], a

    ld a, [wMusicPlaying]
    cp TRACK_INTRO
    call nz, InitIntroMusic

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

UpdateCharSelect:
    ; Animate sprites
    ld a, [wFrameCounter]
    and %00010000
    jr z, .f0
    ld b, 4
    jr .drawSprites
.f0:
    ld b, 0
.drawSprites:
    ; Draw M sprite next to option 0 (x=32, y=52)
    ld a, 52
    ld [wSpriteY], a
    ld a, 32
    ld [wSpriteX], a
    ld a, $D0
    add b
    ld [wSpriteTile], a
    ld a, 0
    call SetMetaSprite16x16

    ; Draw F sprite next to option 1 (x=32, y=68)
    ld a, 68
    ld [wSpriteY], a
    ld a, 32
    ld [wSpriteX], a
    ld a, $D8
    add b
    ld [wSpriteTile], a
    ld a, 4
    call SetMetaSprite16x16

    ; Draw NB sprite next to option 2 (x=32, y=84)
    ld a, 84
    ld [wSpriteY], a
    ld a, 32
    ld [wSpriteX], a
    ld a, $E0
    add b
    ld [wSpriteTile], a
    ld a, 8
    call SetMetaSprite16x16

    ; Draw Cursor Sprite at selected option
    ld a, [wSelectedChar]
    sla a
    sla a
    sla a
    sla a ; * 16 pixels per option
    add 56
    ld [wOAMBuffer + (12 * 4) + 0], a ; Y
    ld a, 20
    ld [wOAMBuffer + (12 * 4) + 1], a ; X
    ld a, $0A ; Cursor '>' tile
    ld [wOAMBuffer + (12 * 4) + 2], a
    xor a
    ld [wOAMBuffer + (12 * 4) + 3], a

    ; Input handling
    ld a, [wJoyPressed]
    bit 7, a ; PADF_DOWN
    jr nz, .moveDown
    bit 6, a ; PADF_UP
    jr nz, .moveUp
    and PADF_A | PADF_START
    jr nz, .confirmChar
    ret

.moveDown:
    call PlaySFXCursor
    ld a, [wSelectedChar]
    inc a
    cp 3
    jr c, .storeSel
    xor a
    jr .storeSel

.moveUp:
    call PlaySFXCursor
    ld a, [wSelectedChar]
    or a
    jr nz, .decSel
    ld a, 2
    jr .storeSel
.decSel:
    dec a
.storeSel:
    ld [wSelectedChar], a
    call DrawCharSelectDetails
    ret

.confirmChar:
    call PlaySFXConfirm
    call InitOverworld
    ret

; Clear 17 characters (cols 2..18) on row HL in _SCRN0 cleanly during VBlank/HBlank
ClearSelectDescLine:
    ld b, 17
.csdLoop:
    ld a, [rSTAT]
    and %00000010
    jr nz, .csdLoop
    xor a
    ld [hl+], a
    dec b
    jr nz, .csdLoop
    ret

DrawCharSelectDetails:
    ; Wait for a fresh VBlank start (if LCD is ON) so all 3 lines clear & print inside VBlank without PPU VRAM lock!
    ld a, [rLCDC]
    rlca
    jr nc, .lcdOffReady
.waitNotVBlank:
    ld a, [rLY]
    cp 144
    jr nc, .waitNotVBlank
    call WaitVBlank
.lcdOffReady:
    ld hl, _SCRN0 + (13 * 32) + 2
    call ClearSelectDescLine
    ld hl, _SCRN0 + (14 * 32) + 2
    call ClearSelectDescLine
    ld hl, _SCRN0 + (15 * 32) + 2
    call ClearSelectDescLine

    ld a, [wSelectedChar]
    cp CHAR_MALE
    jr z, .male
    cp CHAR_FEMALE
    jr z, .female
    ; Non-Binary
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrDescNB1
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrDescNB2
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrDescNB3
    call PrintString
    ret
.male:
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrDescM1
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrDescM2
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrDescM3
    call PrintString
    ret
.female:
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrDescF1
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrDescF2
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrDescF3
    call PrintString
    ret

; ===========================================================================
; Iteration 2: Scrolling 2.5D Overworld Map State
; ===========================================================================
InitOverworld:
    call InitGameMusic
    call DisableLCD
    call ClearShadowOAM

    ; Initialize Player World Position (centered on village road: X=112, Y=112)
    ld a, 112
    ld [wPlayerWorldX], a
    ld [wPlayerWorldY], a
    xor a ; 0 = Down, 1 = Up, 2 = Left, 3 = Right
    ld [wPlayerDir], a
    ld [wWalkDistance], a

    ; Initialize Hero Level 1 Stats (MaxHP, HP, ATK, DEF, XP, NextXP) based on wSelectedChar:
    ; - M  (ARIA   - Knight): HP=34, ATK=10, DEF=5 (+4 HP, +2 ATK, +1 DEF per Lv)
    ; - F  (SAKURA - Mage):   HP=28, ATK=8,  DEF=3 (+3 HP, +2 ATK, +1 DEF per Lv)
    ; - NB (ORION  - Ranger): HP=30, ATK=9,  DEF=4 (+3 HP, +2 ATK, +1 DEF per Lv)
    ld a, 1
    ld [wHeroLevel], a
    xor a
    ld [wHeroXP], a
    ld a, 20
    ld [wHeroNextXP], a

    ld a, [wSelectedChar]
    cp CHAR_MALE
    jr z, .initStatsM
    cp CHAR_FEMALE
    jr z, .initStatsF
    ; NB: Orion
    ld a, 30
    ld [wHeroMaxHP], a
    ld [wHeroHP], a
    ld a, 9
    ld [wHeroATK], a
    ld a, 4
    ld [wHeroDEF], a
    jr .doneStatsInit
.initStatsM:
    ld a, 34
    ld [wHeroMaxHP], a
    ld [wHeroHP], a
    ld a, 10
    ld [wHeroATK], a
    ld a, 5
    ld [wHeroDEF], a
    jr .doneStatsInit
.initStatsF:
    ld a, 28
    ld [wHeroMaxHP], a
    ld [wHeroHP], a
    ld a, 8
    ld [wHeroATK], a
    ld a, 3
    ld [wHeroDEF], a
.doneStatsInit:

    ; Reset NPC & Enemy World Positions
    ; NPC Gaius stands near the Northern Shrine (X=120, Y=72)
    ld a, 120
    ld [wNPCWorldX], a
    ld a, 72
    ld [wNPCWorldY], a

    ; Quest Giver NPC Bob stands in Upper Village Plaza near the East House (X=152, Y=72)
    ld a, 152
    ld [wBobWorldX], a
    ld a, 72
    ld [wBobWorldY], a
    xor a
    ld [wBobQuestState], a ; 0 = Bearded man waiting for dress, 2 = Freed woman in dress!
    ld [wHasDress], a      ; 0 = Dress in chest, 1 = In inventory, 2 = Given to Bob
    ld [wInvCursor], a
    ld hl, wInventory
    ld b, INV_SLOTS
.clearInvLoop:
    ld [hl+], a
    dec b
    jr nz, .clearInvLoop

    ; Initialize 9 Overworld Enemies:
    ; Index 0 = EVIL TERF (slow, high-HP, high-ATK boss mob at X=64, Y=144)
    ; Indices 1..8 = 8 SHADOW FIENDS patrolling across the 256x256 map!
    ld hl, InitialEnemyX
    ld de, wEnemyX
    ld bc, 9
    call CopyData

    ld hl, InitialEnemyY
    ld de, wEnemyY
    ld bc, 9
    call CopyData

    ld hl, wEnemyAlive
    ld b, 9
    ld a, 1
.initAliveLoop:
    ld [hl+], a
    dec b
    jr nz, .initAliveLoop

    call EnterOverworldMap
    ret

InitialEnemyX:
    db 64  ; 0: EVIL TERF (Southwest Clearing)
    db 168 ; 1: Shadow Fiend #1 (East Town Plaza)
    db 120 ; 2: Shadow Fiend #2 (Southern Road before Bridge)
    db 56  ; 3: Shadow Fiend #3 (Southwest Riverbank)
    db 48  ; 4: Shadow Fiend #4 (Western Crossroad)
    db 192 ; 5: Shadow Fiend #5 (Eastern Crossroad)
    db 40  ; 6: Shadow Fiend #6 (Northwest Forest Grove)
    db 208 ; 7: Shadow Fiend #7 (Northeast Forest Grove)
    db 204 ; 8: Shadow Fiend #8 (Southeast Riverbank)

InitialEnemyY:
    db 144 ; 0: EVIL TERF
    db 112 ; 1: Shadow Fiend #1
    db 160 ; 2: Shadow Fiend #2
    db 212 ; 3: Shadow Fiend #3
    db 96  ; 4: Shadow Fiend #4
    db 96  ; 5: Shadow Fiend #5
    db 36  ; 6: Shadow Fiend #6
    db 36  ; 7: Shadow Fiend #7
    db 212 ; 8: Shadow Fiend #8

; Re-enter Overworld Map preserving player & entity positions
EnterOverworldMap:
    ld a, [wMusicPlaying]
    cp TRACK_GAME
    call nz, InitGameMusic
    call DisableLCD
    call ClearShadowOAM

    ; Load Selected Character's 4-Directional Sprite Bank (32 tiles = $D0..$EF) into VRAM $8D00
    call LoadSelectedPlayerSprites

    ; Load NPC Bob's Overworld Sprite ($F0..$F3) into VRAM $8F00:
    ; - Before dress (wBobQuestState < 2): CustomSpritesTiles + 0  (Bearded man sprite)
    ; - After dress  (wBobQuestState == 2): CustomSpritesTiles + 64 (Woman in dress sprite)
    ld hl, CustomSpritesTiles
    ld a, [wBobQuestState]
    cp 2
    jr nz, .copyBobSprite
    ld hl, CustomSpritesTiles + (4 * 16)
.copyBobSprite:
    ld de, $8F00
    ld bc, 4 * 16
    call CopyData

    ld hl, MapMetatilesData
    ld de, $8800
    ld bc, MapMetatilesDataEnd - MapMetatilesData
    call CopyData

    ; Render 16x16 Metatile Map (256x256px) into _SCRN0 ($9800)
    call LoadOverworldMap

    ; Update Camera Scroll registers (rSCX, rSCY) from Player position
    call UpdateCameraScroll
    call RenderOverworldSprites

    ld a, STATE_OVERWORLD
    ld [wGameState], a

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; Copy 32 tiles (512 bytes) of 4-directional walking sprites for wSelectedChar into VRAM $8D00 ($D0..$EF)
LoadSelectedPlayerSprites:
    ld a, [wSelectedChar]
    cp CHAR_MALE
    jr z, .loadSprAria
    cp CHAR_FEMALE
    jr z, .loadSprSakura
    ld hl, SpritesOrionTiles
    jr .copySpr
.loadSprAria:
    ld hl, SpritesAriaTiles
    jr .copySpr
.loadSprSakura:
    ld hl, SpritesSakuraTiles
.copySpr:
    ld de, $8D00
    ld bc, 32 * 16
    call CopyData
    ret

; Render 16x16 Metatile Map into 32x32 BG Map (_SCRN0)
; Each metatile ID (0..19) maps to 4 8x8 tiles in VRAM $8800..$8CFF (loaded from MapMetatilesData):
;   base = $80 + (metatile_id * 4)
;   Top-Left = base+0, Top-Right = base+1
;   Bot-Left = base+2, Bot-Right = base+3
LoadOverworldMap:
    ld de, OverworldMapData ; 16x16 bytes
    ld hl, _SCRN0           ; $9800
    ld c, 16                ; 16 metatile rows
.rowLoop:
    ld b, 16                ; 16 metatile cols
    push hl
.colLoop:
    ld a, [de]
    inc de
    ; If metatile 6 (Treasure Chest) and chest has already been opened (wHasDress != 0), use metatile 7 (Open Chest)
    cp 6
    jr nz, .notOpenedChest
    ld a, [wHasDress]
    or a
    ld a, 6
    jr z, .notOpenedChest
    ld a, 7
.notOpenedChest:
    ; Calculate base tile = $80 + a*4
    sla a
    sla a
    add $80
    ; Write TL and TR at hl, hl+1
    ld [hl+], a
    inc a
    ld [hl], a
    inc a
    ; Write BL and BR at hl+31, hl+32
    push bc ; Preserve metatile row/col counters (b and c)!
    push hl
    ld bc, 31
    add hl, bc
    ld [hl+], a
    inc a
    ld [hl], a
    pop hl
    pop bc
    inc hl ; Advance to next metatile column (hl was at TR, now at next TL)
    dec b
    jr nz, .colLoop

    ; Advance hl to next metatile row (2 BG rows = 64 bytes)
    pop hl
    push bc ; Preserve row counter c!
    ld bc, 64
    add hl, bc
    pop bc
    dec c
    jr nz, .rowLoop
    ret

UpdateOverworld:
    ; Save current position in case of collision
    ld a, [wPlayerWorldX]
    ld d, a
    ld a, [wPlayerWorldY]
    ld e, a

    ld a, [wJoyHeld]
    ld c, 0 ; movement flag

    bit 4, a ; PADF_RIGHT
    jr z, .notRight
    ld a, 3 ; Dir 3 = Right
    ld [wPlayerDir], a
    ld a, [wPlayerWorldX]
    cp 224
    jr nc, .notRight
    inc a
    ld [wPlayerWorldX], a
    ld c, 1
.notRight:
    ld a, [wJoyHeld]
    bit 5, a ; PADF_LEFT
    jr z, .notLeft
    ld a, 2 ; Dir 2 = Left
    ld [wPlayerDir], a
    ld a, [wPlayerWorldX]
    cp 16
    jr c, .notLeft
    dec a
    ld [wPlayerWorldX], a
    ld c, 1
.notLeft:
    ; Check X collision with solid metatiles (2=Tree, 3=Wall, 4=Water, 5=Shrine roof)
    push de
    call CheckMapCollision
    pop de
    jr z, .xOk
    ; Revert X
    ld a, d
    ld [wPlayerWorldX], a
.xOk:

    ld a, [wJoyHeld]
    bit 7, a ; PADF_DOWN
    jr z, .notDown
    xor a ; Dir 0 = Down
    ld [wPlayerDir], a
    ld a, [wPlayerWorldY]
    cp 224
    jr nc, .notDown
    inc a
    ld [wPlayerWorldY], a
    ld c, 1
.notDown:
    ld a, [wJoyHeld]
    bit 6, a ; PADF_UP
    jr z, .notUp
    ld a, 1 ; Dir 1 = Up
    ld [wPlayerDir], a
    ld a, [wPlayerWorldY]
    cp 16
    jr c, .notUp
    dec a
    ld [wPlayerWorldY], a
    ld c, 1
.notUp:
    ; Check Y collision
    push de
    call CheckMapCollision
    pop de
    jr z, .yOk
    ; Revert Y
    ld a, e
    ld [wPlayerWorldY], a
.yOk:
    ; Increment walk step counter whenever D-pad is held
    ld a, [wJoyHeld]
    and PADF_UP | PADF_DOWN | PADF_LEFT | PADF_RIGHT
    jr z, .noWalkStep
    ld hl, wWalkDistance
    inc [hl]
.noWalkStep:

    ; Patrol 8 Shadow Fiends (indices 1..8, every 4 frames) & EVIL TERF (index 0, every 8 frames)
    ld a, [wFrameCounter]
    and %00000011
    jr nz, .skipEnemyPatrol

    ; Determine base direction for Shadow Fiends from bit 6 of wFrameCounter
    ld a, [wFrameCounter]
    bit 6, a
    ld c, 1
    jr nz, .fiendDirSet
    ld c, $FF ; -1
.fiendDirSet:
    ld hl, wEnemyX + 1 ; Start at Shadow Fiend #1 (index 1)
    ld b, 8            ; 8 Shadow Fiends
.patrolFiendsLoop:
    ld a, [hl]
    add c
    ld [hl+], a
    ; Flip sign of c so odd/even Fiends patrol in opposite directions
    ld a, c
    cpl
    inc a
    ld c, a
    dec b
    jr nz, .patrolFiendsLoop

    ; EVIL TERF (index 0) moves at half speed (every 8 frames)
    ld a, [wFrameCounter]
    and %00000111
    jr nz, .skipEnemyPatrol
    ld a, [wFrameCounter]
    bit 7, a
    jr z, .terfLeft
    ld hl, wEnemyX
    inc [hl]
    jr .skipEnemyPatrol
.terfLeft:
    ld hl, wEnemyX
    dec [hl]
.skipEnemyPatrol:

    call UpdateCameraScroll
    call RenderOverworldSprites

    ; Check Enemy Sprite Touch Encounter (FF Mystic Quest / Aretha style)
    call CheckEnemyEncounter
    ld a, [wGameState]
    cp STATE_BATTLE
    ret z

    ; Check NPC & Quest Interactions (Gaius, Bob, and the hidden Treasure Chest)
    call CheckNPCInteraction
    ld a, [wGameState]
    cp STATE_DIALOGUE
    ret z
    call CheckBobInteraction
    ld a, [wGameState]
    cp STATE_DIALOGUE
    ret z
    call CheckChestInteraction
    ld a, [wGameState]
    cp STATE_DIALOGUE
    ret z

    ; If A (or SELECT) was pressed and no NPC/chest interaction triggered, open the Inventory Screen!
    ld a, [wJoyPressed]
    and PADF_A | PADF_SELECT
    ret z
    call PlaySFXConfirm
    call InitInventory
    ret

; Check proximity to NPC Materia and trigger popup portrait & text box
CheckNPCInteraction:
    ld a, [wPlayerWorldX]
    ld b, a
    ld a, [wNPCWorldX]
    sub b
    jr nc, .absXOk
    cpl
    inc a
.absXOk:
    cp 20
    ret nc

    ld a, [wPlayerWorldY]
    ld b, a
    ld a, [wNPCWorldY]
    sub b
    jr nc, .absYOk
    cpl
    inc a
.absYOk:
    cp 20
    ret nc

    ; Within 20px interaction zone! Show prompt or check A button / direct touch (< 12px)
    cp 12
    jr c, .touchCheckX
    ; Check A button press
    ld a, [wJoyPressed]
    and PADF_A
    ret z
    jr .triggerDialogue

.touchCheckX:
    ld a, [wPlayerWorldX]
    ld b, a
    ld a, [wNPCWorldX]
    sub b
    jr nc, .absX2
    cpl
    inc a
.absX2:
    cp 12
    jr c, .PushBackAndTalk
    ld a, [wJoyPressed]
    and PADF_A
    ret z
    jr .triggerDialogue

.PushBackAndTalk:
    ; Step player down slightly so they don't immediately re-trigger upon closing dialogue
    ld a, [wPlayerWorldY]
    add 8
    ld [wPlayerWorldY], a
.triggerDialogue:
    call PlaySFXConfirm
    call InitNPCDialogue
    ret

; ===========================================================================
; Iteration 3: NPC & Player Dialogue Scene with Chibi Anime Portraits
; Uses the 3 character portraits & lines from the second uploaded image:
; - Page 0: Selected Player Character Portrait (M=ARIA, F=SAKURA, NB=ORION)
;           + Katakana & English Name Header + Character's dialogue lines!
; - Page 1: NPC Materia Portrait & quest guidance!
; ===========================================================================
InitNPCDialogue:
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    ; Reset scroll registers so the 20x18 screen aligns to (0,0)
    xor a
    ld [rSCX], a
    ld [rSCY], a
    ld [wDialogPage], a

    ; Copy 20x8 PortraitTilemap into rows 0..7 of _SCRN0 ($9800)
    ; (Columns 5..14 map to tiles $80..$CF at VRAM $8800..$8CFF)
    ld de, PortraitTilemap
    ld hl, _SCRN0
    ld c, 8 ; 8 rows
.pRowLoop:
    ld b, 20 ; 20 columns
    push hl
.pColLoop:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .pColLoop
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .pRowLoop

    ; Draw Double-Bordered Dialogue Box at X=0, Y=8, Width=20, Height=10 (rows 8..17)
    ld b, 0
    ld c, 8
    ld d, 20
    ld e, 10
    call DrawDialogBox

    ; Load Selected Player Portrait tiles into VRAM $8800 and render Page 0 text
    call LoadPlayerPortraitTiles
    call DrawNPCDialoguePage

    ld a, STATE_DIALOGUE
    ld [wGameState], a

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; Load 80 tiles (1280 bytes) of the selected character's portrait into VRAM $8800
LoadPlayerPortraitTiles:
    ld a, [wSelectedChar]
    cp CHAR_MALE
    jr z, .loadAria
    cp CHAR_FEMALE
    jr z, .loadSakura
    ld hl, PortraitOrionTiles
    jr .doCopyPortrait
.loadAria:
    ld hl, PortraitAriaTiles
    jr .doCopyPortrait
.loadSakura:
    ld hl, PortraitSakuraTiles
.doCopyPortrait:
    ld de, $8800
    ld bc, 80 * 16
    call CopyData
    ret

DrawNPCDialoguePage:
    ; Clear interior rows 9..16 (cols 1..18)
    ld hl, _SCRN0 + (9 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (10 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (11 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (12 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (13 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (14 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (15 * 32) + 1
    call ClearDialogLine
    ld hl, _SCRN0 + (16 * 32) + 1
    call ClearDialogLine

    ld a, [wDialogPage]
    or a
    jp nz, .page1

    ; Page 0: Show Selected Player Character's Portrait & Dialogue from second reference image!
    ld a, [wSelectedChar]
    cp CHAR_MALE
    jr z, .dialogAria
    cp CHAR_FEMALE
    jp z, .dialogSakura

    ; --- NON-BINARY: ORION (♦オリオン♦ / ORION) ---
    ld hl, _SCRN0 + (9 * 32) + 6
    ld de, StrHeaderOrionJP
    call PrintString
    ld hl, _SCRN0 + (10 * 32) + 7
    ld de, StrHeaderOrionEN
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrOrionL1
    call PrintString
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrOrionL2
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrOrionL3
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrOrionL4
    call PrintString
    ld hl, _SCRN0 + (16 * 32) + 2
    ld de, StrOrionL5
    call PrintString
    ret

.dialogAria:
    ; --- MALE: ARIA (♦アリア♦ / ARIA) ---
    ld hl, _SCRN0 + (9 * 32) + 7
    ld de, StrHeaderAriaJP
    call PrintString
    ld hl, _SCRN0 + (10 * 32) + 8
    ld de, StrHeaderAriaEN
    call PrintString
    ld hl, _SCRN0 + (11 * 32) + 2
    ld de, StrAriaL1
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrAriaL2
    call PrintString
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrAriaL3
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrAriaL4
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrAriaL5
    call PrintString
    ld hl, _SCRN0 + (16 * 32) + 2
    ld de, StrAriaL6
    call PrintString
    ret

.dialogSakura:
    ; --- FEMALE: SAKURA (♦サクラ♦ / SAKURA) ---
    ld hl, _SCRN0 + (9 * 32) + 7
    ld de, StrHeaderSakuraJP
    call PrintString
    ld hl, _SCRN0 + (10 * 32) + 7
    ld de, StrHeaderSakuraEN
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrSakuraL1
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrSakuraL2
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrSakuraL3
    call PrintString
    ld hl, _SCRN0 + (16 * 32) + 2
    ld de, StrSakuraL4
    call PrintString
    ret

.page1:
    cp 2
    jr z, .pageTerf
    cp 3
    jr z, .pageBobRequest
    cp 4
    jp z, .pageBobTryDress
    cp 5
    jp z, .pageBobFreed
    cp 6
    jp z, .pageChestFound
    cp 7
    jp z, .pageChestEmpty

    ; Page 1: NPC GAIUS (♦ガイア♦ / GAIUS) portrait & guidance from uploaded image!
    ld hl, _SCRN0 + (9 * 32) + 7
    ld de, StrHeaderGaiusJP
    call PrintString

    ld hl, _SCRN0 + (10 * 32) + 7
    ld de, StrHeaderGaiusEN
    call PrintString

    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrNPCDialogP2L1
    call PrintString

    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrNPCDialogP2L2
    call PrintString

    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrNPCDialogP2L3
    call PrintString

    ld hl, _SCRN0 + (16 * 32) + 2
    ld de, StrNPCDialogP2L4
    call PrintString
    ret

.pageTerf:
    ; Page 2: BOSS TERF Pre-Battle Portrait & Taunt from uploaded image!
    ld hl, _SCRN0 + (10 * 32) + 2
    ld de, StrTerfDialogL1
    call PrintString

    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrTerfDialogL2
    call PrintString

    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrTerfDialogL3
    call PrintString

    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrTerfDialogL4
    call PrintString
    ret

.pageBobRequest:
    ; Page 3: Bearded Bob asking for the Silk Dress hidden in a treasure chest
    ld hl, _SCRN0 + (9 * 32) + 4
    ld de, StrHeaderBobBeard
    call PrintString
    ld hl, _SCRN0 + (11 * 32) + 2
    ld de, StrBobReqL1
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrBobReqL2
    call PrintString
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrBobReqL3
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrBobReqL4
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrBobReqL5
    call PrintString
    ld hl, _SCRN0 + (16 * 32) + 2
    ld de, StrBobReqL6
    call PrintString
    ret

.pageBobTryDress:
    ; Page 4: Bearded Bob receiving the Silk Dress and trying it on
    ld hl, _SCRN0 + (9 * 32) + 4
    ld de, StrHeaderBobBeard
    call PrintString
    ld hl, _SCRN0 + (11 * 32) + 2
    ld de, StrBobTryL1
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrBobTryL2
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrBobTryL3
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrBobTryL4
    call PrintString
    ret

.pageBobFreed:
    ; Page 5: Bob freed from the weave — she is now a woman!
    ld hl, _SCRN0 + (9 * 32) + 3
    ld de, StrHeaderBobFem
    call PrintString
    ld hl, _SCRN0 + (11 * 32) + 2
    ld de, StrBobFreeL1
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrBobFreeL2
    call PrintString
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrBobFreeL3
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrBobFreeL4
    call PrintString
    ld hl, _SCRN0 + (16 * 32) + 2
    ld de, StrBobFreeL5
    call PrintString
    ret

.pageChestFound:
    ; Page 6: Found the Silk Dress in the Treasure Chest!
    ld hl, _SCRN0 + (9 * 32) + 2
    ld de, StrHeaderChest
    call PrintString
    ld hl, _SCRN0 + (11 * 32) + 2
    ld de, StrChestFoundL1
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrChestFoundL2
    call PrintString
    ld hl, _SCRN0 + (14 * 32) + 2
    ld de, StrChestFoundL3
    call PrintString
    ld hl, _SCRN0 + (15 * 32) + 2
    ld de, StrChestFoundL4
    call PrintString
    ret

.pageChestEmpty:
    ; Page 7: Treasure Chest already opened
    ld hl, _SCRN0 + (9 * 32) + 2
    ld de, StrHeaderChest
    call PrintString
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrChestEmptyL1
    call PrintString
    ld hl, _SCRN0 + (13 * 32) + 2
    ld de, StrChestEmptyL2
    call PrintString
    ret

ClearDialogLine:
    ld b, 18
    xor a
.clLoop:
    ld [hl+], a
    dec b
    jr nz, .clLoop
    ret

UpdateNPCDialogue:
    ; Blink advance indicator cursor at bottom-right of text box (X=148, Y=140)
    ld a, [wFrameCounter]
    and %00010000
    jr z, .hidePrompt
    ld a, 140
    ld [wOAMBuffer + 0], a ; Y
    ld a, 148
    ld [wOAMBuffer + 1], a ; X
    ld a, $09 ; Diamond tile ♦
    ld [wOAMBuffer + 2], a
    xor a
    ld [wOAMBuffer + 3], a
    jr .checkBtn
.hidePrompt:
    xor a
    ld [wOAMBuffer + 0], a
.checkBtn:
    ld a, [wJoyPressed]
    and PADF_A | PADF_B | PADF_START
    ret z

    call PlaySFXCursor
    ld a, [wDialogPage]
    cp 2
    jr z, .startTerfBattleFromDialog
    cp 4
    jr z, .transformBobToShe
    or a
    jr nz, .closeDialog

    ; Advance to Page 1 (Switch portrait to NPC Gaius + Quest Prompt + Heal Hero to MaxHP & Respawn all 8 Fiends!)
    ld a, [wHeroMaxHP]
    ld [wHeroHP], a
    ld hl, wEnemyAlive + 1
    ld b, 8
    ld a, 1
.respawnFiendsLoop:
    ld [hl+], a
    dec b
    jr nz, .respawnFiendsLoop
    ld [wDialogPage], a
    call DisableLCD
    ld hl, PortraitGaiusTiles
    ld de, $8800
    ld bc, 80 * 16
    call CopyData
    call DrawNPCDialoguePage
    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

.transformBobToShe:
    ; Bob puts on the Silk Dress, breaking the weave and becoming a she!
    ; Remove the Silk Dress from the player's inventory
    ld a, ITEM_SILK_DRESS
    call RemoveItemFromInventory
    ld a, 2
    ld [wBobQuestState], a
    ld [wHasDress], a
    ld a, [wHeroMaxHP]
    ld [wHeroHP], a ; Blessing of Amity full heal
    ld a, 5 ; Page 5 = Bob Freed (She/Her)
    ld [wDialogPage], a
    call InitVictoryJingle
    call DisableLCD
    call LoadBobFemPortrait
    call DrawNPCDialoguePage
    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

.startTerfBattleFromDialog:
    call StartBattleTransition
    ret

.closeDialog:
    ; Return to scrolling 2.5D Overworld Map
    call EnterOverworldMap
    ret

; ===========================================================================
; Quest Giver NPC Bob & Hidden Dress Treasure Chest Interactions
; ===========================================================================
CheckBobInteraction:
    ld a, [wPlayerWorldX]
    ld b, a
    ld a, [wBobWorldX]
    sub b
    jr nc, .absXOk
    cpl
    inc a
.absXOk:
    cp 20
    ret nc

    ld a, [wPlayerWorldY]
    ld b, a
    ld a, [wBobWorldY]
    sub b
    jr nc, .absYOk
    cpl
    inc a
.absYOk:
    cp 20
    ret nc

    cp 12
    jr c, .touchCheckX
    ld a, [wJoyPressed]
    and PADF_A
    ret z
    jr .triggerBob

.touchCheckX:
    ld a, [wPlayerWorldX]
    ld b, a
    ld a, [wBobWorldX]
    sub b
    jr nc, .absX2
    cpl
    inc a
.absX2:
    cp 12
    jr c, .pushBackBob
    ld a, [wJoyPressed]
    and PADF_A
    ret z
    jr .triggerBob

.pushBackBob:
    ld a, [wPlayerWorldY]
    add 8
    ld [wPlayerWorldY], a
.triggerBob:
    call PlaySFXConfirm
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM
    xor a
    ld [rSCX], a
    ld [rSCY], a

    ; Copy 20x8 PortraitTilemap into rows 0..7 of _SCRN0
    ld de, PortraitTilemap
    ld hl, _SCRN0
    ld c, 8
.bRowLoop:
    ld b, 20
    push hl
.bColLoop:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .bColLoop
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .bRowLoop

    ld b, 0
    ld c, 8
    ld d, 20
    ld e, 10
    call DrawDialogBox

    ; Choose Bob dialogue state & portrait:
    ; - wBobQuestState == 2 -> Page 5 (Freed feminine Bob portrait)
    ; - wHasDress == 1      -> Page 4 (Bearded Bob receiving the dress -> transforms to Page 5!)
    ; - Otherwise           -> Page 3 (Bearded Bob asking for the dress in the chest)
    ld a, [wBobQuestState]
    cp 2
    jr z, .bobAlreadyFreed
    ld a, [wHasDress]
    cp 1
    jr z, .bobGiveDress

    ld a, 3
    ld [wDialogPage], a
    call LoadBobBeardedPortrait
    jr .finishBobInit

.bobGiveDress:
    ld a, 4
    ld [wDialogPage], a
    call LoadBobBeardedPortrait
    jr .finishBobInit

.bobAlreadyFreed:
    ld a, 5
    ld [wDialogPage], a
    call LoadBobFemPortrait

.finishBobInit:
    call DrawNPCDialoguePage
    ld a, STATE_DIALOGUE
    ld [wGameState], a
    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; Load Bearded Bob's dedicated 80-tile portrait (PortraitBobBeardedTiles) into VRAM $8800
LoadBobBeardedPortrait:
    ld hl, PortraitBobBeardedTiles
    ld de, $8800
    ld bc, 80 * 16
    call CopyData
    ret

; Load Freed Feminine Bob's dedicated 80-tile portrait (PortraitBobFemTiles) into VRAM $8800
LoadBobFemPortrait:
    ld hl, PortraitBobFemTiles
    ld de, $8800
    ld bc, 80 * 16
    call CopyData
    ret

; Check proximity to the Hidden Treasure Chest at Row 13, Col 10 (World X=160, Y=208)
CheckChestInteraction:
    ld a, [wPlayerWorldX]
    sub 160
    jr nc, .absXOk
    cpl
    inc a
.absXOk:
    cp 20
    ret nc

    ld a, [wPlayerWorldY]
    sub 208
    jr nc, .absYOk
    cpl
    inc a
.absYOk:
    cp 20
    ret nc

    ; Within 20px of Treasure Chest (160, 208)! Open on A press, or auto-open on close touch if closed
    ld a, [wJoyPressed]
    and PADF_A
    jr nz, .openChestDialog

    ; Also allow touching the closed chest directly (< 16px) to discover the dress immediately!
    ld a, [wHasDress]
    or a
    ret nz
    ld a, [wPlayerWorldX]
    sub 160
    jr nc, .tX
    cpl
    inc a
.tX:
    cp 16
    ret nc
    ld a, [wPlayerWorldY]
    sub 208
    jr nc, .tY
    cpl
    inc a
.tY:
    cp 18
    ret nc

.openChestDialog:
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM
    xor a
    ld [rSCX], a
    ld [rSCY], a

    ; Copy 20x8 PortraitTilemap into rows 0..7 of _SCRN0
    ld de, PortraitTilemap
    ld hl, _SCRN0
    ld c, 8
.cRowLoop:
    ld b, 20
    push hl
.cColLoop:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .cColLoop
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .cRowLoop

    ld b, 0
    ld c, 8
    ld d, 20
    ld e, 10
    call DrawDialogBox

    call LoadPlayerPortraitTiles

    ld a, [wHasDress]
    or a
    jr nz, .alreadyOpened
    ld a, 1
    ld [wHasDress], a
    ; Add the Silk Dress to the player's inventory!
    ld a, ITEM_SILK_DRESS
    call AddItemToInventory
    ld a, 6 ; Page 6 = Found the Silk Dress!
    ld [wDialogPage], a
    call InitVictoryJingle
    jr .showChestPage

.alreadyOpened:
    call PlaySFXConfirm
    ld a, 7 ; Page 7 = Chest is empty
    ld [wDialogPage], a

.showChestPage:
    call DrawNPCDialoguePage
    ld a, STATE_DIALOGUE
    ld [wGameState], a
    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; ===========================================================================
; Inventory System (4x2 Rounded-Edge Grid of 16x16 Item Sprites)
; ===========================================================================

; Add item ID in A (1..N) to first empty slot in wInventory (0..7)
AddItemToInventory:
    ld b, a
    ld hl, wInventory
    ld c, INV_SLOTS
.findEmpty:
    ld a, [hl]
    or a
    jr z, .storeItem
    inc hl
    dec c
    jr nz, .findEmpty
    ret
.storeItem:
    ld [hl], b
    ret

; Remove first occurrence of item ID in A from wInventory (0..7) and shift remaining items left
RemoveItemFromInventory:
    ld b, a
    ld hl, wInventory
    ld c, INV_SLOTS
.findMatch:
    ld a, [hl]
    cp b
    jr z, .shiftLeft
    inc hl
    dec c
    jr nz, .findMatch
    ret
.shiftLeft:
    dec c
    jr z, .clearLast
    ld d, h
    ld e, l
    inc de
    ld a, [de]
    ld [hl+], a
    jr .shiftLeft
.clearLast:
    xor a
    ld [hl], a
    ret

InitInventory:
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    xor a
    ld [rSCX], a
    ld [rSCY], a

    ; Load Rounded-Edge Grid Cell Border Tiles ($80..$8F) into VRAM $8800
    ld hl, InvGridBorderTiles
    ld de, $8800
    ld bc, InvGridBorderTilesEnd - InvGridBorderTiles
    call CopyData

    ; Load 16x16 Inventory Item Sprites ($D0..) into VRAM $8D00
    ld hl, ItemSpritesTiles
    ld de, $8D00
    ld bc, ItemSpritesTilesEnd - ItemSpritesTiles
    call CopyData

    ; Top Header Box (X=0, Y=0, W=20, H=3)
    ld b, 0
    ld c, 0
    ld d, 20
    ld e, 3
    call DrawDialogBox
    ld hl, _SCRN0 + (1 * 32) + 3
    ld de, StrInvTitle
    call PrintString

    ; Bottom Single-Row Item Name Box (X=0, Y=15, W=20, H=3 -> single text row on Row 16!)
    ld b, 0
    ld c, 15
    ld d, 20
    ld e, 3
    call DrawDialogBox

    ; Draw the 4x2 Rounded-Edge Grid, 16x16 Item Sprites, and Selected Item Name
    call DrawInventoryGrid
    call RenderInventorySprites
    call DrawSelectedItemName

    ld a, STATE_INVENTORY
    ld [wGameState], a

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

UpdateInventory:
    ; D-Pad navigation across the 4x2 grid (slots 0..7)
    ld a, [wJoyPressed]
    bit 4, a ; PADF_RIGHT
    jr nz, .moveRight
    bit 5, a ; PADF_LEFT
    jr nz, .moveLeft
    bit 7, a ; PADF_DOWN
    jr nz, .moveUpDown
    bit 6, a ; PADF_UP
    jr nz, .moveUpDown

    ; Close Inventory on B, A, START, or SELECT (no item action button yet)
    and PADF_B | PADF_A | PADF_START | PADF_SELECT
    ret z
    call PlaySFXConfirm
    call EnterOverworldMap
    ret

.moveRight:
    ld a, [wInvCursor]
    inc a
    and 7
    jr .updateCursor

.moveLeft:
    ld a, [wInvCursor]
    dec a
    and 7
    jr .updateCursor

.moveUpDown:
    ld a, [wInvCursor]
    xor 4 ; Toggle between Row 0 (0..3) and Row 1 (4..7)

.updateCursor:
    ld [wInvCursor], a
    call PlaySFXCursor
    ; Redraw rounded grid cells & bottom item name safely inside VBlank
    call DisableLCD
    call DrawInventoryGrid
    call DrawSelectedItemName
    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; Draw all 8 Rounded-Edge 4x4 Grid Cells (4 columns x 2 rows)
; Row 0 (slots 0..3) at Y=4, X=2, 6, 10, 14
; Row 1 (slots 4..7) at Y=9, X=2, 6, 10, 14
DrawInventoryGrid:
    ld c, 0 ; Slot index 0..7
.slotLoop:
    push bc
    ; Compute X = 2 + ((c & 3) * 4)
    ld a, c
    and 3
    add a
    add a
    add 2
    ld b, a ; b = Tile X

    ; Compute Y = 4 for Row 0 (c < 4), or 9 for Row 1 (c >= 4)
    ld a, c
    bit 2, a
    ld a, 4
    jr z, .gotY
    ld a, 9
.gotY:
    ld d, a ; d = Tile Y

    ; Choose rounded border tile base: $88 if selected (c == wInvCursor), else $80
    ld a, [wInvCursor]
    cp c
    ld e, $80
    jr nz, .drawCell
    ld e, $88
.drawCell:
    call DrawRoundedGridCell
    pop bc
    inc c
    ld a, c
    cp INV_SLOTS
    jr c, .slotLoop
    ret

; Draw a 4x4 Rounded-Edge Cell at Tile X = b, Tile Y = d, Base Tile = e ($80 or $88)
; Base+0=TL, Base+1=T, Base+2=TR, Base+3=L, Base+4=R, Base+5=BL, Base+6=B, Base+7=BR
DrawRoundedGridCell:
    ; Compute HL = _SCRN0 + d*32 + b
    ld l, d
    ld h, 0
    add hl, hl ; *2
    add hl, hl ; *4
    add hl, hl ; *8
    add hl, hl ; *16
    add hl, hl ; *32
    ld a, b
    add l
    ld l, a
    ld a, h
    adc $98
    ld h, a

    ; Row 0 of cell: TL, T, T, TR
    ld a, e
    ld [hl+], a ; TL
    inc a
    ld [hl+], a ; T
    ld [hl+], a ; T
    inc a
    ld [hl], a  ; TR

    ; Row 1 of cell: L, Blank, Blank, R
    ld bc, 29
    add hl, bc
    ld a, e
    add 3
    ld [hl+], a ; L
    xor a
    ld [hl+], a ; Interior (0,0)
    ld [hl+], a ; Interior (1,0)
    ld a, e
    add 4
    ld [hl], a  ; R

    ; Row 2 of cell: L, Blank, Blank, R
    ld bc, 29
    add hl, bc
    ld a, e
    add 3
    ld [hl+], a ; L
    xor a
    ld [hl+], a ; Interior (0,1)
    ld [hl+], a ; Interior (1,1)
    ld a, e
    add 4
    ld [hl], a  ; R

    ; Row 3 of cell: BL, B, B, BR
    ld bc, 29
    add hl, bc
    ld a, e
    add 5
    ld [hl+], a ; BL
    inc a
    ld [hl+], a ; B
    ld [hl+], a ; B
    inc a
    ld [hl], a  ; BR
    ret

; Render 16x16 Item Sprites inside their corresponding 4x4 Rounded Grid Cells
RenderInventorySprites:
    call ClearShadowOAM
    ld c, 0 ; Slot index 0..7
.sprLoop:
    ld b, 0
    ld hl, wInventory
    add hl, bc
    ld a, [hl]
    or a
    jr z, .nextSlot ; Empty slot

    ; Compute Sprite Tile = $D0 + ((item_id - 1) * 4)
    dec a
    add a
    add a
    add $D0
    ld [wSpriteTile], a

    ; Compute Screen X = ((2 + (c & 3)*4 + 1) * 8) + 8 = 32 + (c & 3)*32
    ld a, c
    and 3
    swap a ; *16
    add a  ; *32
    add 32
    ld [wSpriteX], a

    ; Compute Screen Y = 56 for Row 0 (Y=4+1 -> 5*8+16=56), or 96 for Row 1 (Y=9+1 -> 10*8+16=96)
    ld a, c
    bit 2, a
    ld a, 56
    jr z, .gotSprY
    ld a, 96
.gotSprY:
    ld [wSpriteY], a

    ; Place 16x16 metasprite at OAM slot (c * 4)
    push bc
    ld a, c
    add a
    add a
    call SetMetaSprite16x16
    pop bc

.nextSlot:
    inc c
    ld a, c
    cp INV_SLOTS
    jr c, .sprLoop
    ret

; Print the name of the currently selected item on the single bottom row (Row 16)
DrawSelectedItemName:
    ld hl, _SCRN0 + (16 * 32) + 1
    call ClearDialogLine

    ld a, [wInvCursor]
    ld c, a
    ld b, 0
    ld hl, wInventory
    add hl, bc
    ld a, [hl]
    cp ITEM_SILK_DRESS
    jr z, .nameSilkDress

    ; Empty slot
    ld hl, _SCRN0 + (16 * 32) + 5
    ld de, StrItemEmpty
    call PrintString
    ret

.nameSilkDress:
    ld hl, _SCRN0 + (16 * 32) + 5
    ld de, StrItemSilkDress
    call PrintString
    ret

; Show Boss TERF 80x64 Portrait & Taunt Dialogue before starting Boss Battle!
InitTerfTauntDialogue:
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    xor a
    ld [rSCX], a
    ld [rSCY], a
    ld a, 2 ; Page 2 = Terf Boss Taunt
    ld [wDialogPage], a

    ; Copy 20x8 PortraitTilemap into rows 0..7 of _SCRN0 ($9800)
    ld de, PortraitTilemap
    ld hl, _SCRN0
    ld c, 8
.tRowLoop:
    ld b, 20
    push hl
.tColLoop:
    ld a, [de]
    inc de
    ld [hl+], a
    dec b
    jr nz, .tColLoop
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .tRowLoop

    ; Draw Double-Bordered Dialogue Box at X=0, Y=8, Width=20, Height=10 (rows 8..17)
    ld b, 0
    ld c, 8
    ld d, 20
    ld e, 10
    call DrawDialogBox

    ; Load Boss TERF 80-tile Portrait into VRAM $8800 and render Page 2 text
    ld hl, PortraitTerfTiles
    ld de, $8800
    ld bc, 80 * 16
    call CopyData
    call DrawNPCDialoguePage

    ld a, STATE_DIALOGUE
    ld [wGameState], a

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; ===========================================================================
; Iteration 4: Enemy Touch Encounter & Turn-Based Battle System
; Fight pops up immediately once an overworld enemy sprite is touched!
; ===========================================================================
CheckEnemyEncounter:
    ld c, 0 ; Enemy index 0..8 (0 = Evil Terf, 1..8 = 8 Shadow Fiends)
.loopCheckEnemy:
    ld b, 0
    ld hl, wEnemyAlive
    add hl, bc
    ld a, [hl]
    or a
    jr z, .nextEnemy

    ; Check |PlayerWorldX - wEnemyX[c]| < 14
    ld hl, wEnemyX
    add hl, bc
    ld a, [wPlayerWorldX]
    ld d, a
    ld a, [hl]
    sub d
    jr nc, .absXOk
    cpl
    inc a
.absXOk:
    cp 14
    jr nc, .nextEnemy

    ; Check |PlayerWorldY - wEnemyY[c]| < 14
    ld hl, wEnemyY
    add hl, bc
    ld a, [wPlayerWorldY]
    ld d, a
    ld a, [hl]
    sub d
    jr nc, .absYOk
    cpl
    inc a
.absYOk:
    cp 14
    jr nc, .nextEnemy

    ; Touched Enemy c!
    ld a, c
    ld [wActiveEnemyID], a
    or a
    jr z, .touchedBossTerf
    call StartBattleTransition
    ret
.touchedBossTerf:
    call PlaySFXEncounter
    call InitTerfTauntDialogue
    ret

.nextEnemy:
    inc c
    ld a, c
    cp 9
    jr c, .loopCheckEnemy
    ret

; Classic JRPG Screen Flash & Siren SFX when touching an enemy sprite
StartBattleTransition:
    call PlaySFXEncounter
    ld c, 6 ; 6 palette flashes
.flashLoop:
    ld a, %00011011 ; Inverted palette
    ld [rBGP], a
    ld b, 4
    call WaitFramesB
    ld a, %11100100 ; Normal palette
    ld [rBGP], a
    ld b, 4
    call WaitFramesB
    dec c
    jr nz, .flashLoop

    call InitBattle
    ret

WaitFramesB:
    call WaitVBlank
    dec b
    jr nz, WaitFramesB
    ret

InitBattle:
    call InitBattleMusic
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    xor a
    ld [rSCX], a
    ld [rSCY], a
    ld [wBattleCursor], a
    ld [wBattlePhase], a ; 0 = Command Select, 2 = Victory

    ; Configure Enemy stats (HP, ATK, DEF), name, and 32x32 battle graphic based on wActiveEnemyID
    ; Enemy 0    = EVIL TERF    (HP: 64, ATK: 23, DEF: 7 - requires killing 8 Shadow Fiends [Lv 5] to beat!)
    ; Enemy 1..8 = SHADOW FIEND (HP: 22, ATK: 9,  DEF: 2 - +10 XP each, 2 kills per Level Up!)
    ld a, [wActiveEnemyID]
    or a
    jr z, .setupEvilTerf

    ; Setup Shadow Fiend (indices 1..8)
    ld a, 22
    ld [wMonsterHP], a
    ld a, 9
    ld [wMonsterATK], a
    ld a, 2
    ld [wMonsterDEF], a
    ld hl, BattleFiendTiles
    ld de, $8700
    ld bc, 16 * 16
    call CopyData
    jr .drawBattleArena

.setupEvilTerf:
    ld a, 64
    ld [wMonsterHP], a
    ld a, 23
    ld [wMonsterATK], a
    ld a, 7
    ld [wMonsterDEF], a
    ; Load 48 tiles (8x6 = 64x48px) of Large Boss Terf graphic into VRAM $8800 ($80..$AF)
    ld hl, BattleTerfTiles
    ld de, $8800
    ld bc, 48 * 16
    call CopyData

.drawBattleArena:
    ; Top Monster Status & Arena Box (20x10 at 0,0)
    ld b, 0
    ld c, 0
    ld d, 20
    ld e, 10
    call DrawDialogBox

    ; Print Enemy Name at top-left
    ld hl, _SCRN0 + (1 * 32) + 2
    ld a, [wActiveEnemyID]
    or a
    jr z, .nameTerf
    ld de, StrEnemyName
    jr .printEnemyTitle
.nameTerf:
    ld de, StrTerfName
.printEnemyTitle:
    call PrintString

    ; Draw Monster Graphic in arena:
    ; - Shadow Fiend (wActiveEnemyID != 0): 4x4 (32x32px) at Cols 8..11, Rows 3..6 (Tiles $70..$7F)
    ; - BOSS TERF    (wActiveEnemyID == 0): 8x6 (64x48px) at Cols 4..11, Rows 3..8 (Tiles $80..$AF)
    ld a, [wActiveEnemyID]
    or a
    jr z, .drawLargeTerfArena

    ld a, $70
    ld hl, _SCRN0 + (3 * 32) + 8
    ld c, 4
.mRow:
    ld b, 4
    push hl
.mCol:
    ld [hl+], a
    inc a
    dec b
    jr nz, .mCol
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .mRow
    jr .drawBattleHeroSprite

.drawLargeTerfArena:
    ld a, $80
    ld hl, _SCRN0 + (3 * 32) + 4
    ld c, 6 ; 6 rows (48px tall)
.tArenaRow:
    ld b, 8 ; 8 cols (64px wide)
    push hl
.tArenaCol:
    ld [hl+], a
    inc a
    dec b
    jr nz, .tArenaCol
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .tArenaRow

.drawBattleHeroSprite:

    ; Draw Hero Battle Sprite facing monster (Left-facing sprite at $E0!) on right side of arena (X=128, Y=56)
    ld a, $E0
    ld [wSpriteTile], a
    ld a, 56
    ld [wSpriteY], a
    ld a, 128
    ld [wSpriteX], a
    xor a
    call SetMetaSprite16x16

    ; Bottom Battle Command & Message Window (20x8 at 0,10)
    ld b, 0
    ld c, 10
    ld d, 20
    ld e, 8
    call DrawDialogBox

    call DrawBattleHUD
    ld a, [wActiveEnemyID]
    or a
    jr z, .msgTerfAppear
    ld de, StrBattleAppear
    jr .printAppearMsg
.msgTerfAppear:
    ld de, StrTerfAppear
.printAppearMsg:
    call DrawBattleMessage

    ld a, STATE_BATTLE
    ld [wGameState], a

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

; Render Hero HP/ATK/DEF, Enemy HP/ATK/DEF, and Command Menu (FIGHT / MAGIC / RUN)
DrawBattleHUD:
    ; Row 2: Enemy HP, ATK, DEF ("HP:22 AT:09 DF:02")
    ld hl, _SCRN0 + (2 * 32) + 2
    ld de, StrHPLabel
    call PrintString
    ld a, [wMonsterHP]
    ld hl, _SCRN0 + (2 * 32) + 5
    call PrintNumber2Digit

    ld hl, _SCRN0 + (2 * 32) + 8
    ld de, StrATKLabel
    call PrintString
    ld a, [wMonsterATK]
    ld hl, _SCRN0 + (2 * 32) + 11
    call PrintNumber2Digit

    ld hl, _SCRN0 + (2 * 32) + 14
    ld de, StrDEFLabel
    call PrintString
    ld a, [wMonsterDEF]
    ld hl, _SCRN0 + (2 * 32) + 17
    call PrintNumber2Digit

    ; Row 11: Hero Name & HP ("M: ARIA    HP:34")
    ld hl, _SCRN0 + (11 * 32) + 2
    ld a, [wSelectedChar]
    cp CHAR_MALE
    jr z, .hudM
    cp CHAR_FEMALE
    jr z, .hudF
    ld de, StrOptNB
    jr .printHudHero
.hudM:
    ld de, StrOptMale
    jr .printHudHero
.hudF:
    ld de, StrOptFemale
.printHudHero:
    call PrintString

    ld hl, _SCRN0 + (11 * 32) + 13
    ld de, StrHPLabel
    call PrintString
    ld a, [wHeroHP]
    ld hl, _SCRN0 + (11 * 32) + 16
    call PrintNumber2Digit

    ; Row 12: Hero Level, ATK, DEF ("LV:01 AT:10 DF:05")
    ld hl, _SCRN0 + (12 * 32) + 2
    ld de, StrLVLabel
    call PrintString
    ld a, [wHeroLevel]
    ld hl, _SCRN0 + (12 * 32) + 5
    call PrintNumber2Digit

    ld hl, _SCRN0 + (12 * 32) + 8
    ld de, StrATKLabel
    call PrintString
    ld a, [wHeroATK]
    ld hl, _SCRN0 + (12 * 32) + 11
    call PrintNumber2Digit

    ld hl, _SCRN0 + (12 * 32) + 14
    ld de, StrDEFLabel
    call PrintString
    ld a, [wHeroDEF]
    ld hl, _SCRN0 + (12 * 32) + 17
    call PrintNumber2Digit

    ; Draw Commands on Rows 13, 14, 15 (Cols 3..12) & XP Status on Row 13 Col 13 ("XP:00")
    ld hl, _SCRN0 + (13 * 32) + 3
    ld de, StrCmdFight
    call PrintString

    ld hl, _SCRN0 + (13 * 32) + 13
    ld de, StrXPLabel
    call PrintString
    ld a, [wHeroXP]
    ld hl, _SCRN0 + (13 * 32) + 16
    call PrintNumber2Digit

    ld hl, _SCRN0 + (14 * 32) + 3
    ld de, StrCmdMagic
    call PrintString

    ld hl, _SCRN0 + (14 * 32) + 13
    ld de, StrNextLabel
    call PrintString
    ld a, [wHeroNextXP]
    ld hl, _SCRN0 + (14 * 32) + 16
    call PrintNumber2Digit

    ld hl, _SCRN0 + (15 * 32) + 3
    ld de, StrCmdRun
    call PrintString
    ret

; Print a 2-digit number (0..99) in A at VRAM HL
PrintNumber2Digit:
    ld b, 0
.div10:
    cp 10
    jr c, .doneDiv
    sub 10
    inc b
    jr .div10
.doneDiv:
    ld c, a ; ones
    ld a, b ; tens
    add $40 ; '0' is at $40 in our CHARMAP (ASCII 48 - 32 + $30 = $40)
    ld [hl+], a
    ld a, c
    add $40
    ld [hl], a
    ret

; Print status message on Row 16 inside bottom battle box
DrawBattleMessage:
    push de
    ld hl, _SCRN0 + (16 * 32) + 1
    call ClearDialogLine
    pop de
    ld hl, _SCRN0 + (16 * 32) + 2
    call PrintString
    ret

UpdateBattle:
    ; Check if in Victory Phase (2)
    ld a, [wBattlePhase]
    cp 2
    jp z, .waitVictoryExit

    ; Position Battle Command Cursor Sprite (OAM 4)
    ld a, [wBattleCursor]
    sla a
    sla a
    sla a ; * 8px per row
    add 120 ; Row 13 Y = 104 + 16 = 120
    ld [wOAMBuffer + (4 * 4) + 0], a ; Y
    ld a, 24 ; Col 2 X = 16 + 8 = 24
    ld [wOAMBuffer + (4 * 4) + 1], a ; X
    ld a, $0A ; '>' cursor tile
    ld [wOAMBuffer + (4 * 4) + 2], a
    xor a
    ld [wOAMBuffer + (4 * 4) + 3], a

    ; Input handling for Command Menu
    ld a, [wJoyPressed]
    bit 7, a ; DOWN
    jr nz, .cmdDown
    bit 6, a ; UP
    jr nz, .cmdUp
    and PADF_A | PADF_START
    jr nz, .executeCmd
    ret

.cmdDown:
    call PlaySFXCursor
    ld a, [wBattleCursor]
    inc a
    cp 3
    jr c, .setCmdCur
    xor a
.setCmdCur:
    ld [wBattleCursor], a
    ret

.cmdUp:
    call PlaySFXCursor
    ld a, [wBattleCursor]
    or a
    jr nz, .decCmdCur
    ld a, 2
    jr .setCmdCur
.decCmdCur:
    dec a
    jr .setCmdCur

.executeCmd:
    ld a, [wBattleCursor]
    cp 0
    jr z, .doFight
    cp 1
    jr z, .doMagic
    ; Cmd 2 = RUN!
    call PlaySFXConfirm
    ; Push player back slightly to avoid instant re-encounter
    ld a, [wPlayerWorldX]
    sub 16
    ld [wPlayerWorldX], a
    call EnterOverworldMap
    ret

.doFight:
    call PlaySFXAttack
    ; Physical Damage = max(1, wHeroATK - wMonsterDEF)
    ld a, [wMonsterDEF]
    ld b, a
    ld a, [wHeroATK]
    sub b
    jr c, .minDmgFight
    jr nz, .gotFightDmg
.minDmgFight:
    ld a, 1
.gotFightDmg:
    ld [wLastDamage], a
    ld b, a
    ld a, [wMonsterHP]
    sub b
    jr nc, .storeMHP1
    xor a
.storeMHP1:
    ld [wMonsterHP], a
    call WaitVBlank
    ld de, StrBattleSlash
    call DrawBattleMessage
    ld a, [wLastDamage]
    ld hl, _SCRN0 + (16 * 32) + 14
    call PrintNumber2Digit
    call FlashMonsterHit
    jr .afterPlayerAttack

.doMagic:
    call PlaySFXConfirm
    ; Ring Magic Damage = max(1, (wHeroATK + 5) - (wMonsterDEF / 2))
    ld a, [wMonsterDEF]
    srl a ; MonsterDEF / 2
    ld b, a
    ld a, [wHeroATK]
    add 5
    sub b
    jr c, .minDmgMagic
    jr nz, .gotMagicDmg
.minDmgMagic:
    ld a, 1
.gotMagicDmg:
    ld [wLastDamage], a
    ld b, a
    ld a, [wMonsterHP]
    sub b
    jr nc, .storeMHP2
    xor a
.storeMHP2:
    ld [wMonsterHP], a
    call WaitVBlank
    ld de, StrBattleMagic
    call DrawBattleMessage
    ld a, [wLastDamage]
    ld hl, _SCRN0 + (16 * 32) + 14
    call PrintNumber2Digit
    call FlashMonsterHit

.afterPlayerAttack:
    call WaitVBlank
    call DrawBattleHUD

    ; Check if Monster HP == 0
    ld a, [wMonsterHP]
    or a
    jr z, .monsterDefeated

    ; Pause so player can read their attack message
    ld b, 28
    call WaitFramesB

    ; Enemy counter-attack!
    ; Enemy Damage = max(1, wMonsterATK - wHeroDEF)
    ld a, [wHeroDEF]
    ld b, a
    ld a, [wMonsterATK]
    sub b
    jr c, .minEnemyDmg
    jr nz, .gotEnemyDmg
.minEnemyDmg:
    ld a, 1
.gotEnemyDmg:
    ld [wLastDamage], a

    call PlaySFXHit
    call FlashMonsterHit

    ; Display Enemy Counter-Attack Message + actual damage dealt
    call WaitVBlank
    ld a, [wActiveEnemyID]
    or a
    jr z, .msgTerfHit
    ld de, StrFiendAttackMsg
    jr .drawEnemyHitMsg
.msgTerfHit:
    ld de, StrTerfAttackMsg
.drawEnemyHitMsg:
    call DrawBattleMessage
    ld a, [wLastDamage]
    ld hl, _SCRN0 + (16 * 32) + 14
    call PrintNumber2Digit

    ; Subtract wLastDamage from wHeroHP (with real Game Over when HP reaches 0!)
    ld a, [wLastDamage]
    ld b, a
    ld a, [wHeroHP]
    sub b
    jr c, .heroZeroHP
    jr z, .heroZeroHP
    ld [wHeroHP], a
    call WaitVBlank
    call DrawBattleHUD
    ret

.heroZeroHP:
    xor a
    ld [wHeroHP], a
    call WaitVBlank
    call DrawBattleHUD
    ld b, 35
    call WaitFramesB
    call InitGameOver
    ret

.monsterDefeated:
    call InitVictoryJingle
    ; Hide cursor sprite
    xor a
    ld [wOAMBuffer + (4 * 4) + 0], a

    ; Award XP: +10 XP for Shadow Fiend (indices 1..8), +40 XP for Evil Terf (index 0)
    ld a, [wActiveEnemyID]
    or a
    jr z, .xpTerf
    ld b, 10
    jr .addXP
.xpTerf:
    ld b, 40
.addXP:
    ld a, b
    ld [wLastDamage], a ; Reuse to print XP gained
    ld a, [wHeroXP]
    add b
    cp 99
    jr c, .storeXP
    ld a, 99
.storeXP:
    ld [wHeroXP], a

    ; Check if HeroXP >= HeroNextXP (20 XP = every 2 Shadow Fiends!) for Level Up!
    ld b, a
    ld a, [wHeroNextXP]
    cp b
    jr z, .doLevelUp
    jr nc, .noLevelUp

.doLevelUp:
    ; Subtract NextXP from HeroXP
    ld a, [wHeroXP]
    ld b, a
    ld a, [wHeroNextXP]
    ld c, a
    ld a, b
    sub c
    ld [wHeroXP], a

    ; Keep NextXP at 20 XP per level so 8 Shadow Fiends (80 XP) = 4 Level-Ups (Level 5)!
    ld a, 20
    ld [wHeroNextXP], a

    ; Increment Hero Level!
    ld a, [wHeroLevel]
    inc a
    ld [wHeroLevel], a

    ; Boost Hero Stats (+6 MaxHP, +3 ATK, +2 DEF per level) and full heal!
    ; At Level 5 (after killing 8 Shadow Fiends), all 3 classes reach the exact threshold to defeat Evil Terf!
    ld a, [wHeroMaxHP]
    add 6
    ld [wHeroMaxHP], a
    ld [wHeroHP], a ; Full heal on Level Up!

    ld a, [wHeroATK]
    add 3
    ld [wHeroATK], a

    ld a, [wHeroDEF]
    add 2
    ld [wHeroDEF], a

    call WaitVBlank
    call DrawBattleHUD
    ld de, StrBattleLevelUp
    call DrawBattleMessage
    ld a, [wHeroLevel]
    ld hl, _SCRN0 + (16 * 32) + 15
    call PrintNumber2Digit
    ld a, 2
    ld [wBattlePhase], a
    ret

.noLevelUp:
    call WaitVBlank
    call DrawBattleHUD
    ld de, StrBattleVictory
    call DrawBattleMessage
    ld a, [wLastDamage]
    ld hl, _SCRN0 + (16 * 32) + 12
    call PrintNumber2Digit
    ld a, 2
    ld [wBattlePhase], a
    ret

.waitVictoryExit:
    ld a, [wJoyPressed]
    and PADF_A | PADF_B | PADF_START
    ret z
    call PlaySFXConfirm
    ; Mark defeated overworld enemy (wEnemyAlive[wActiveEnemyID]) as dead (0)
    ld a, [wActiveEnemyID]
    ld c, a
    ld b, 0
    ld hl, wEnemyAlive
    add hl, bc
    xor a
    ld [hl], a
    call EnterOverworldMap
    ret

PlaySFXLevelUp:
    ld a, 24
    ld [wSFXLockTimer], a
    ld a, $24 ; Upward arpeggio sweep!
    ld [rNR10], a
    ld a, $80
    ld [rNR11], a
    ld a, $F4
    ld [rNR12], a
    ld a, $70
    ld [rNR13], a
    ld a, $87
    ld [rNR14], a
    ret

; ===========================================================================
; Game Over Screen State
; ===========================================================================
InitGameOver:
    call InitGameOverJingle
    call DisableLCD
    call ClearBGMap0
    call ClearShadowOAM

    xor a
    ld [rSCX], a
    ld [rSCY], a

    ; Outer Frame (20x18)
    ld b, 0
    ld c, 0
    ld d, 20
    ld e, 18
    call DrawDialogBox

    ; Inner Tombstone / Defeat Box (16x8 at X=2, Y=3)
    ld b, 2
    ld c, 3
    ld d, 16
    ld e, 8
    call DrawDialogBox

    ld hl, _SCRN0 + (5 * 32) + 4
    ld de, StrGameOverTitle
    call PrintString

    ld hl, _SCRN0 + (7 * 32) + 4
    ld de, StrGameOverSub1
    call PrintString

    ld hl, _SCRN0 + (8 * 32) + 4
    ld de, StrGameOverSub2
    call PrintString

    ld hl, _SCRN0 + (14 * 32) + 3
    ld de, StrGameOverRetry
    call PrintString

    ld a, STATE_GAME_OVER
    ld [wGameState], a

    ld a, LCDCF_ON | LCDCF_BG8000 | LCDCF_BG9800 | LCDCF_OBJON | LCDCF_BGON
    ld [rLCDC], a
    ret

UpdateGameOver:
    ld a, [wJoyPressed]
    and PADF_A | PADF_START | PADF_B | PADF_SELECT
    ret z
    call PlaySFXConfirm
    call InitCharSelect
    ret

PlaySFXGameOver:
    ld a, $7F ; Slow downward pitch sweep
    ld [rNR10], a
    ld a, $80
    ld [rNR11], a
    ld a, $F7
    ld [rNR12], a
    ld a, $70
    ld [rNR13], a
    ld a, $86
    ld [rNR14], a
    ret

FlashMonsterHit:
    ld a, %00011011
    ld [rBGP], a
    ld b, 5
    call WaitFramesB
    ld a, %11100100
    ld [rBGP], a
    ret

PlaySFXEncounter:
    ld a, 20
    ld [wSFXLockTimer], a
    ld a, $37
    ld [rNR10], a
    ld a, $80
    ld [rNR11], a
    ld a, $F4
    ld [rNR12], a
    ld a, $90
    ld [rNR13], a
    ld a, $87
    ld [rNR14], a
    ret

PlaySFXAttack:
    ld a, 14
    ld [wSFXLockCh4], a
    ld a, $08
    ld [rNR41], a
    ld a, $F2
    ld [rNR42], a
    ld a, $55
    ld [rNR43], a
    ld a, $80
    ld [rNR44], a
    ret

PlaySFXHit:
    ld a, 14
    ld [wSFXLockCh4], a
    ld a, $10
    ld [rNR41], a
    ld a, $F1
    ld [rNR42], a
    ld a, $67
    ld [rNR43], a
    ld a, $80
    ld [rNR44], a
    ret

; Check if player's feet (PlayerWorldX + 7, PlayerWorldY + 12) hit a solid metatile
; Returns Z=1 if passable (metatile 0=Grass or 1=Road), Z=0 if solid (>= 2)
CheckMapCollision:
    ld a, [wPlayerWorldY]
    add 12
    and $F0 ; (Y // 16) * 16
    ld l, a
    ld h, 0
    ld a, [wPlayerWorldX]
    add 7
    swap a
    and $0F ; X // 16
    or l    ; offset = (Y_tile * 16) + X_tile
    ld l, a
    ld de, OverworldMapData
    add hl, de
    ld a, [hl]
    cp 2
    jr c, .passable
    or 1 ; Z=0 (solid)
    ret
.passable:
    xor a ; Z=1 (passable)
    ret

; Compute camera scroll (rSCX, rSCY) clamped to 256x256 map (0..96, 0..112)
UpdateCameraScroll:
    ; Camera X = clamp(PlayerWorldX - 72, 0, 96)
    ld a, [wPlayerWorldX]
    sub 72
    jr nc, .checkMaxX
    xor a
    jr .setCamX
.checkMaxX:
    cp 96
    jr c, .setCamX
    ld a, 96
.setCamX:
    ld [wCameraX], a
    ld [rSCX], a

    ; Camera Y = clamp(PlayerWorldY - 64, 0, 112)
    ld a, [wPlayerWorldY]
    sub 64
    jr nc, .checkMaxY
    xor a
    jr .setCamY
.checkMaxY:
    cp 112
    jr c, .setCamY
    ld a, 112
.setCamY:
    ld [wCameraY], a
    ld [rSCY], a
    ret

; Render Player, NPC Gaius, and visible Enemies (Evil Terf + 8 Shadow Fiends) relative to Camera
RenderOverworldSprites:
    call ClearShadowOAM

    ; Player's 4-directional sprites are loaded at $D0..$EF:
    ;   Dir 0 (Down):  $D0 (F0), $D4 (F1)
    ;   Dir 1 (Up):    $D8 (F0), $DC (F1)
    ;   Dir 2 (Left):  $E0 (F0), $E4 (F1)
    ;   Dir 3 (Right): $E8 (F0), $EC (F1)
    ld a, [wPlayerDir]
    sla a
    sla a
    sla a ; * 8 tiles per direction
    add $D0
    ld b, a

    ; Alternate Frame 0 / Frame 1 (+4 tiles) every 8 steps while walking
    ld a, [wJoyHeld]
    and PADF_UP | PADF_DOWN | PADF_LEFT | PADF_RIGHT
    jr z, .setPlayerSprite
    ld a, [wWalkDistance]
    and %00001000
    jr z, .setPlayerSprite
    ld a, b
    add 4
    ld b, a
.setPlayerSprite:
    ; Screen Y = PlayerWorldY - CameraY + 16 (OAM Y offset)
    ld a, [wCameraY]
    ld c, a
    ld a, [wPlayerWorldY]
    sub c
    add 16
    ld [wSpriteY], a

    ; Screen X = PlayerWorldX - CameraX + 8 (OAM X offset)
    ld a, [wCameraX]
    ld c, a
    ld a, [wPlayerWorldX]
    sub c
    add 8
    ld [wSpriteX], a

    ld a, b
    ld [wSpriteTile], a
    xor a ; OAM 0..3
    call SetMetaSprite16x16

    ; Render NPC Gaius (OAM 4..7) at Tile $F8 if within camera viewport
    ld a, [wCameraY]
    ld c, a
    ld a, [wNPCWorldY]
    sub c
    cp 144
    jr nc, .renderBob
    add 16
    ld [wSpriteY], a

    ld a, [wCameraX]
    ld c, a
    ld a, [wNPCWorldX]
    sub c
    cp 160
    jr nc, .renderBob
    add 8
    ld [wSpriteX], a

    ld a, $F8 ; NPC Gaius Overworld tile
    ld [wSpriteTile], a
    ld a, 4
    call SetMetaSprite16x16

.renderBob:
    ; Render Quest Giver NPC Bob (OAM 8..11) at Tile $F0 if within camera viewport
    ld a, [wCameraY]
    ld c, a
    ld a, [wBobWorldY]
    sub c
    cp 144
    jr nc, .renderEnemies
    add 16
    ld [wSpriteY], a

    ld a, [wCameraX]
    ld c, a
    ld a, [wBobWorldX]
    sub c
    cp 160
    jr nc, .renderEnemies
    add 8
    ld [wSpriteX], a

    ld a, $F0 ; NPC Bob Overworld tile ($F0..$F3: Bearded before quest, Dress after quest!)
    ld [wSpriteTile], a
    ld a, 8
    call SetMetaSprite16x16

.renderEnemies:
    ; Render up to 7 visible Enemies into OAM slots 12..39 (4 OAM entries per 16x16 enemy)
    ; Index 0 = EVIL TERF ($F4), Indices 1..8 = 8 SHADOW FIENDS ($FC)
    ld c, 0  ; Enemy index 0..8
    ld b, 12 ; Next OAM slot (12, 16, 20, 24, 28, 32, 36)
.enemyLoop:
    push bc
    ld d, 0
    ld e, c

    ; Check if alive
    ld hl, wEnemyAlive
    add hl, de
    ld a, [hl]
    or a
    jr z, .skipThisEnemy

    ; Check Y within camera viewport (WorldY - CameraY < 144)
    ld hl, wEnemyY
    add hl, de
    ld a, [wCameraY]
    ld d, a
    ld a, [hl]
    sub d
    cp 144
    jr nc, .skipThisEnemy
    add 16
    ld [wSpriteY], a

    ; Check X within camera viewport (WorldX - CameraX < 160)
    ld d, 0
    ld e, c
    ld hl, wEnemyX
    add hl, de
    ld a, [wCameraX]
    ld d, a
    ld a, [hl]
    sub d
    cp 160
    jr nc, .skipThisEnemy
    add 8
    ld [wSpriteX], a

    ; Choose tile: $F4 for Evil Terf (index 0), $FC for Shadow Fiend (indices 1..8)
    ld a, c
    or a
    jr z, .useTerfTile
    ld a, $FC
    jr .setEnemyTile
.useTerfTile:
    ld a, $F4
.setEnemyTile:
    ld [wSpriteTile], a

    ; Render at OAM slot b, then advance b by 4
    pop bc
    ld a, b
    cp 40
    ret nc
    push bc
    call SetMetaSprite16x16
    pop bc
    ld a, b
    add 4
    ld b, a
    jr .nextEnemySlot

.skipThisEnemy:
    pop bc
.nextEnemySlot:
    inc c
    ld a, c
    cp 9
    jr c, .enemyLoop
    ret

; 16x16 Metatile Overworld Map (256x256 pixels)
; 0 = Grass, 1 = Cobblestone Road, 2 = 2.5D Tree, 3 = 2.5D Stone Pillar Wall,
; 4 = River Water, 5 = Shrine Roof/Building
OverworldMapData:
    db 2,2,2,2, 3,3,3,3, 3,3,3,3, 2,2,2,2 ; Row 0: Northern Mountains/Walls & Forest
    db 2,2,0,0, 3,0,0,5, 5,0,0,3, 0,0,2,2 ; Row 1: Northern Shrine Courtyard
    db 2,0,0,0, 3,0,0,1, 1,0,0,3, 0,0,0,2 ; Row 2: Shrine Entrance
    db 2,0,2,0, 3,3,0,1, 1,0,3,3, 0,2,0,2 ; Row 3: Temple Gate
    db 2,0,0,0, 0,0,0,1, 1,0,0,0, 0,0,0,2 ; Row 4: Upper Village Plaza
    db 2,0,5,5, 0,0,1,1, 1,1,0,0, 5,5,0,2 ; Row 5: Village Houses (2.5D Roofs)
    db 2,0,0,1, 1,1,1,1, 1,1,1,1, 1,0,0,2 ; Row 6: Main Crossroad
    db 2,0,0,1, 0,0,1,1, 1,1,0,0, 1,0,0,2 ; Row 7: Town Center (Player Spawn)
    db 2,0,0,1, 0,0,1,1, 1,1,0,0, 1,1,0,2 ; Row 8: Eastern Patrol Road
    db 2,0,2,0, 0,0,0,1, 1,0,0,0, 0,1,0,2 ; Row 9: Southern Path
    db 2,0,0,0, 2,0,0,1, 1,0,0,2, 0,0,0,2 ; Row 10: Forest Clearing
    db 2,4,4,4, 4,4,0,1, 1,0,4,4, 4,4,4,2 ; Row 11: River & Stone Bridge
    db 2,4,4,4, 4,4,0,1, 1,0,4,4, 4,4,4,2 ; Row 12: River & Stone Bridge
    db 2,0,0,0, 0,0,0,1, 1,0,6,0, 0,0,0,2 ; Row 13: South Bank (6 = Treasure Chest with Dress at Col 10!)
    db 2,2,0,2, 0,0,1,1, 1,1,0,0, 2,0,2,2 ; Row 14: Southern Woods
    db 2,2,2,2, 2,2,2,2, 2,2,2,2, 2,2,2,2 ; Row 15: Southern Border Trees


; ===========================================================================
; 4-Channel DMG Music Engine (Intro, Overworld, Battle, Victory & Game Over)
; ===========================================================================
DEF TRACK_NONE         EQU 0
DEF TRACK_INTRO        EQU 1
DEF TRACK_GAME         EQU 2
DEF TRACK_BATTLE       EQU 3
DEF TRACK_VICTORY      EQU 4
DEF TRACK_GAMEOVER     EQU 5

DEF MUSIC_TEMPO_INTRO    EQU 6 ; 6 frames per 16th-note step (~125 BPM, driving intro)
DEF MUSIC_TEMPO_GAME     EQU 9 ; 9 frames per 16th-note step (~83 BPM, slow upbeat BGM)
DEF MUSIC_TEMPO_BATTLE   EQU 5 ; 5 frames per 16th-note step (~150 BPM, urgent tactical alarm)
DEF MUSIC_TEMPO_VICTORY  EQU 5 ; 5 frames per 16th-note step (triumphant fanfare)
DEF MUSIC_TEMPO_GAMEOVER EQU 7 ; 7 frames per 16th-note step (solemn dirge)

DEF NOTE_HOLD          EQU 0   ; Sustain current note
DEF NOTE_REST          EQU $FF ; Silence channel

; Note indices into MusicFreqTable (1..37 = C3..C6; 1 octave lower on Wave CH3)
DEF N_C3  EQU 1
DEF N_CS3 EQU 2
DEF N_D3  EQU 3
DEF N_DS3 EQU 4
DEF N_E3  EQU 5
DEF N_F3  EQU 6
DEF N_FS3 EQU 7
DEF N_G3  EQU 8
DEF N_GS3 EQU 9
DEF N_A3  EQU 10
DEF N_AS3 EQU 11
DEF N_B3  EQU 12

DEF N_C4  EQU 13
DEF N_CS4 EQU 14
DEF N_D4  EQU 15
DEF N_DS4 EQU 16
DEF N_E4  EQU 17
DEF N_F4  EQU 18
DEF N_FS4 EQU 19
DEF N_G4  EQU 20
DEF N_GS4 EQU 21
DEF N_A4  EQU 22
DEF N_AS4 EQU 23
DEF N_B4  EQU 24

DEF N_C5  EQU 25
DEF N_CS5 EQU 26
DEF N_D5  EQU 27
DEF N_DS5 EQU 28
DEF N_E5  EQU 29
DEF N_F5  EQU 30
DEF N_FS5 EQU 31
DEF N_G5  EQU 32
DEF N_GS5 EQU 33
DEF N_A5  EQU 34
DEF N_AS5 EQU 35
DEF N_B5  EQU 36
DEF N_C6  EQU 37

; Drum indices for Channel 4 (Noise)
DEF D_NONE  EQU 0
DEF D_KICK  EQU 1
DEF D_SNARE EQU 2
DEF D_HAT   EQU 3
DEF D_OHAT  EQU 4

InitIntroMusic:
    ld a, MUSIC_TEMPO_INTRO
    ld [wMusicTempo], a
    ld a, $7F
    ld [wMusicStepMask], a
    ld a, 1
    ld [wMusicLoop], a
    ld hl, IntroSongCh2Lead
    ld de, IntroSongCh1Harm
    ld bc, IntroSongCh3Bass
    call SetMusicPointers
    ld hl, IntroSongCh4Drums
    ld a, TRACK_INTRO
    jp StartMusicTrack

InitGameMusic:
    ld a, MUSIC_TEMPO_GAME
    ld [wMusicTempo], a
    ld a, $7F
    ld [wMusicStepMask], a
    ld a, 1
    ld [wMusicLoop], a
    ld hl, GameSongCh2Lead
    ld de, GameSongCh1Harm
    ld bc, GameSongCh3Bass
    call SetMusicPointers
    ld hl, GameSongCh4Drums
    ld a, TRACK_GAME
    jp StartMusicTrack

InitBattleMusic:
    ld a, MUSIC_TEMPO_BATTLE
    ld [wMusicTempo], a
    ld a, $7F
    ld [wMusicStepMask], a
    ld a, 1
    ld [wMusicLoop], a
    ld hl, BattleSongCh2Lead
    ld de, BattleSongCh1Harm
    ld bc, BattleSongCh3Bass
    call SetMusicPointers
    ld hl, BattleSongCh4Drums
    ld a, TRACK_BATTLE
    jr StartMusicTrack

InitVictoryJingle:
    ld a, MUSIC_TEMPO_VICTORY
    ld [wMusicTempo], a
    ld a, $1F ; 32 steps
    ld [wMusicStepMask], a
    xor a ; One-shot jingle (no loop)
    ld [wMusicLoop], a
    ld hl, VictoryJingleCh2Lead
    ld de, VictoryJingleCh1Harm
    ld bc, VictoryJingleCh3Bass
    call SetMusicPointers
    ld hl, VictoryJingleCh4Drums
    ld a, TRACK_VICTORY
    jr StartMusicTrack

InitGameOverJingle:
    ld a, MUSIC_TEMPO_GAMEOVER
    ld [wMusicTempo], a
    ld a, $1F ; 32 steps
    ld [wMusicStepMask], a
    xor a ; One-shot jingle (no loop)
    ld [wMusicLoop], a
    ld hl, GameOverJingleCh2Lead
    ld de, GameOverJingleCh1Harm
    ld bc, GameOverJingleCh3Bass
    call SetMusicPointers
    ld hl, GameOverJingleCh4Drums
    ld a, TRACK_GAMEOVER
    ; Fall through to StartMusicTrack

StartMusicTrack:
    ld [wMusicPlaying], a
    ld a, l
    ld [wMusicCh4Ptr], a
    ld a, h
    ld [wMusicCh4Ptr + 1], a

    ; Ensure master sound is enabled and routed to L+R
    ld a, $80
    ld [rNR52], a
    ld a, $77
    ld [rNR50], a
    ld a, $FF
    ld [rNR51], a

    ; Load resonant bass waveform into Channel 3 Wave RAM ($FF30-$FF3F)
    xor a
    ld [rNR30], a ; Disable CH3 DAC before writing Wave RAM
    ld hl, CustomWaveBass
    ld de, _AUD3WAVERAM
    ld b, 16
.loadWave:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .loadWave

    ld a, $80
    ld [rNR30], a ; Enable CH3 DAC
    xor a
    ld [rNR32], a ; Start muted until first bass note

    ; Initialize sequencer state
    xor a
    ld [wMusicStep], a
    ld [wSFXLockTimer], a
    ld [wSFXLockCh4], a
    ld a, 1
    ld [wMusicTick], a
    ret

; Store HL -> wMusicCh2Ptr, DE -> wMusicCh1Ptr, BC -> wMusicCh3Ptr
SetMusicPointers:
    ld a, l
    ld [wMusicCh2Ptr], a
    ld a, h
    ld [wMusicCh2Ptr + 1], a
    ld a, e
    ld [wMusicCh1Ptr], a
    ld a, d
    ld [wMusicCh1Ptr + 1], a
    ld a, c
    ld [wMusicCh3Ptr], a
    ld a, b
    ld [wMusicCh3Ptr + 1], a
    ret

StopMusic:
    xor a
    ld [wMusicPlaying], a
    ld [wSFXLockTimer], a
    ld [wSFXLockCh4], a
    ld [rNR12], a
    ld [rNR22], a
    ld [rNR30], a
    ld [rNR32], a
    ld [rNR42], a
    ld a, $80
    ld [rNR14], a
    ld [rNR24], a
    ld [rNR44], a
    ret

UpdateMusic:
    ; Decrement Channel 1 SFX lock timer if active
    ld a, [wSFXLockTimer]
    or a
    jr z, .checkCh4Lock
    dec a
    ld [wSFXLockTimer], a

.checkCh4Lock:
    ; Decrement Channel 4 SFX lock timer if active
    ld a, [wSFXLockCh4]
    or a
    jr z, .checkPlaying
    dec a
    ld [wSFXLockCh4], a

.checkPlaying:
    ld a, [wMusicPlaying]
    or a
    ret z

    ; Tick frame counter down to 0
    ld hl, wMusicTick
    dec [hl]
    ret nz
    ld a, [wMusicTempo]
    ld [hl], a

    ; Current step index in BC
    ld a, [wMusicStep]
    ld c, a
    ld b, 0

    ; --- Channel 2: Lead Melody (50% Duty Pulse) ---
    ld a, [wMusicCh2Ptr]
    ld l, a
    ld a, [wMusicCh2Ptr + 1]
    ld h, a
    add hl, bc
    ld a, [hl]
    or a
    jr z, .doneCh2 ; NOTE_HOLD
    cp NOTE_REST
    jr nz, .playCh2
    xor a
    ld [rNR22], a
    ld a, $80
    ld [rNR24], a
    jr .doneCh2
.playCh2:
    call GetNoteFreqDE
    ld a, $80 ; 50% duty cycle (classic warm lead)
    ld [rNR21], a
    ld a, [wMusicPlaying]
    cp TRACK_GAME
    ld a, $E3 ; Volume 14, decay 3 for energetic themes & jingles
    jr nz, .setCh2Env
    ld a, $D4 ; Volume 13, warm sustain decay 4 for slow upbeat BGM
.setCh2Env:
    ld [rNR22], a
    ld a, e
    ld [rNR23], a
    ld a, d
    or $80
    ld [rNR24], a
.doneCh2:

    ; --- Channel 1: Harmony & Arpeggios (25% Duty Pulse) ---
    ld a, [wSFXLockTimer]
    or a
    jr nz, .doneCh1 ; Yield Channel 1 while UI/Battle SFX is playing
    ld a, [wMusicCh1Ptr]
    ld l, a
    ld a, [wMusicCh1Ptr + 1]
    ld h, a
    add hl, bc
    ld a, [hl]
    or a
    jr z, .doneCh1 ; NOTE_HOLD
    cp NOTE_REST
    jr nz, .playCh1
    xor a
    ld [rNR12], a
    ld a, $80
    ld [rNR14], a
    jr .doneCh1
.playCh1:
    call GetNoteFreqDE
    xor a
    ld [rNR10], a ; No sweep
    ld a, $40 ; 25% duty cycle (bright counterpoint/arpeggio timbre)
    ld [rNR11], a
    ld a, [wMusicPlaying]
    cp TRACK_GAME
    ld a, $B2 ; Volume 11, crisp decay 2
    jr nz, .setCh1Env
    ld a, $93 ; Volume 9, gentle bell decay 3 for game BGM
.setCh1Env:
    ld [rNR12], a
    ld a, e
    ld [rNR13], a
    ld a, d
    or $80
    ld [rNR14], a
.doneCh1:

    ; --- Channel 3: Wave Bass ---
    ld a, [wMusicCh3Ptr]
    ld l, a
    ld a, [wMusicCh3Ptr + 1]
    ld h, a
    add hl, bc
    ld a, [hl]
    or a
    jr z, .doneCh3 ; NOTE_HOLD
    cp NOTE_REST
    jr nz, .playCh3
    xor a
    ld [rNR32], a
    jr .doneCh3
.playCh3:
    call GetNoteFreqDE
    xor a
    ld [rNR30], a
    ld a, $80
    ld [rNR30], a
    ld a, $20 ; 100% Wave output level
    ld [rNR32], a
    ld a, e
    ld [rNR33], a
    ld a, d
    or $80
    ld [rNR34], a
.doneCh3:

    ; --- Channel 4: Percussion (Kick / Snare / Hi-Hat) ---
    ld a, [wSFXLockCh4]
    or a
    jr nz, .doneCh4 ; Yield Channel 4 while attack/hit SFX is playing
    ld a, [wMusicCh4Ptr]
    ld l, a
    ld a, [wMusicCh4Ptr + 1]
    ld h, a
    add hl, bc
    ld a, [hl]
    or a
    jr z, .doneCh4
    cp D_KICK
    jr z, .drumKick
    cp D_SNARE
    jr z, .drumSnare
    cp D_OHAT
    jr z, .drumOpenHat
    ; Default: D_HAT (Closed crisp hi-hat)
    ld a, $3C
    ld [rNR41], a
    ld a, $61
    ld [rNR42], a
    ld a, $11
    ld [rNR43], a
    ld a, $C0
    ld [rNR44], a
    jr .doneCh4
.drumKick:
    ld a, $30
    ld [rNR41], a
    ld a, $C1
    ld [rNR42], a
    ld a, $55
    ld [rNR43], a
    ld a, $80
    ld [rNR44], a
    jr .doneCh4
.drumSnare:
    ld a, $20
    ld [rNR41], a
    ld a, $D1
    ld [rNR42], a
    ld a, $34
    ld [rNR43], a
    ld a, $80
    ld [rNR44], a
    jr .doneCh4
.drumOpenHat:
    ld a, $10
    ld [rNR41], a
    ld a, $82
    ld [rNR42], a
    ld a, $12
    ld [rNR43], a
    ld a, $80
    ld [rNR44], a
.doneCh4:

    ; Advance step and wrap by wMusicStepMask ($7F or $1F)
    ld a, [wMusicStep]
    inc a
    ld hl, wMusicStepMask
    and [hl]
    ld [wMusicStep], a
    ret nz

    ; Step wrapped to 0: check if track loops or stops (one-shot jingle)
    ld a, [wMusicLoop]
    or a
    ret nz
    jp StopMusic

; Look up 11-bit period for note index A (1..37) into DE (E = low, D = high)
; Preserves BC
GetNoteFreqDE:
    dec a
    add a
    ld e, a
    ld d, 0
    ld hl, MusicFreqTable
    add hl, de
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ret

; 16-byte (32-sample) punchy asymmetric bass/synth waveform
CustomWaveBass:
    db $FF, $EE, $DD, $CC, $BB, $AA, $99, $88
    db $66, $44, $22, $00, $11, $33, $77, $BB

; Standard DMG 11-bit period table from C3 (index 1) to C6 (index 37)
MusicFreqTable:
    dw $0416, $044E, $0483, $04B5, $04E5, $0511, $053B, $0563, $0589, $05AC, $05CE, $05ED ; C3..B3
    dw $060B, $0627, $0642, $065B, $0672, $0689, $069E, $06B2, $06C4, $06D6, $06E7, $06F7 ; C4..B4
    dw $0706, $0714, $0721, $072D, $0739, $0744, $074F, $0759, $0762, $076B, $0773, $077B ; C5..B5
    dw $0783 ; C6

; ---------------------------------------------------------------------------
; Intro Theme ("Amity Overture" - 8 Bars, 128 Steps)
; Key: E Minor / G Major, 16th-note resolution
; ---------------------------------------------------------------------------

; Channel 2: Heroic Gothic/Baroque Lead Melody
IntroSongCh2Lead:
    ; Bar 1 (Em): Heroic theme entry
    db N_E5, 0, 0, N_B4,  N_C5, N_B4, N_A4, N_G4,  N_FS4, N_G4, N_A4, N_B4,  N_G4, 0, N_E4, 0
    ; Bar 2 (C -> D): Rising sequence
    db N_C5, 0, 0, N_G4,  N_A4, N_G4, N_FS4, N_E4, N_D5, 0, 0, N_A4,         N_B4, N_C5, N_D5, N_FS5
    ; Bar 3 (Em -> Bm): High soaring phrase
    db N_E5, 0, 0, N_B4,  N_G5, 0, N_FS5, N_E5,    N_D5, 0, 0, N_B4,         N_FS4, N_G4, N_A4, N_B4
    ; Bar 4 (C -> B7): Harmonic minor baroque cadence
    db N_C5, N_B4, N_A4, N_G4,  N_FS4, N_G4, N_A4, N_C5,  N_B4, 0, N_A4, N_G4,  N_FS4, 0, N_DS4, 0
    ; Bar 5 (G -> D/F#): Triumphant relative-major B-section
    db N_B4, 0, N_D5, 0,  N_G5, 0, N_FS5, N_G5,    N_A5, 0, N_FS5, 0,        N_D5, 0, N_A4, N_B4
    ; Bar 6 (Em -> C): Dual-lead counterpoint phrase
    db N_G5, 0, N_E5, 0,  N_B4, 0, N_C5, N_B4,     N_A4, 0, N_B4, N_C5,      N_D5, 0, N_B4, N_G4
    ; Bar 7 (Am -> Bm -> C -> D): Fast 16th-note baroque run!
    db N_C5, N_B4, N_C5, N_D5,  N_E5, N_D5, N_E5, N_FS5,  N_G5, N_FS5, N_G5, N_A5,  N_B5, N_A5, N_G5, N_FS5
    ; Bar 8 (Em -> B7 turnaround back to loop)
    db N_E5, 0, N_B4, N_G4,  N_E4, N_G4, N_B4, N_E5,  N_DS5, 0, N_B4, N_FS4,  N_B4, 0, N_FS5, N_DS5

; Channel 1: Baroque Arpeggios & Harmony in 3rds/6ths
IntroSongCh1Harm:
    ; Bar 1 (Em arpeggios & harmony)
    db N_G4, N_E4, N_B3, N_E4,  N_A4, N_G4, N_FS4, N_E4,  N_D4, N_E4, N_FS4, N_G4,  N_E4, N_B3, N_G3, N_B3
    ; Bar 2 (C -> D arpeggios)
    db N_E4, N_C4, N_G3, N_C4,  N_E4, N_C4, N_A3, N_C4,   N_FS4, N_D4, N_A3, N_D4,  N_G4, N_A4, N_B4, N_D5
    ; Bar 3 (Em -> Bm harmony)
    db N_G4, N_E4, N_B3, N_G4,  N_B4, N_E4, N_A4, N_G4,   N_FS4, N_D4, N_B3, N_FS4, N_D4, N_E4, N_FS4, N_D4
    ; Bar 4 (C -> B7 harmonic minor turnaround)
    db N_E4, N_D4, N_C4, N_B3,  N_A3, N_B3, N_C4, N_E4,   N_DS4, N_B3, N_FS4, N_DS4, N_B3, N_FS3, N_B3, N_DS4
    ; Bar 5 (G -> D/F# shimmering 16th arpeggios)
    db N_D4, N_G4, N_B4, N_G4,  N_B4, N_G4, N_A4, N_B4,   N_FS4, N_A4, N_D5, N_A4,  N_FS4, N_D4, N_FS4, N_G4
    ; Bar 6 (Em -> C arpeggio drive)
    db N_B4, N_G4, N_E4, N_G4,  N_G4, N_E4, N_A4, N_G4,   N_E4, N_C4, N_G4, N_E4,   N_FS4, N_D4, N_G4, N_B3
    ; Bar 7 (Harmonized 16th-note baroque run in 3rds!)
    db N_A4, N_G4, N_A4, N_B4,  N_C5, N_B4, N_C5, N_D5,   N_E5, N_D5, N_E5, N_FS5,  N_G5, N_FS5, N_E5, N_D5
    ; Bar 8 (Em -> B7 turnaround harmony)
    db N_G4, N_E4, N_G4, N_E4,  N_B3, N_E4, N_G4, N_G4,   N_FS4, N_DS4, N_FS4, N_DS4, N_FS4, N_B3, N_B4, N_A4

; Channel 3: Driving Octave-Jumping Wave Bass (sounds 1 octave lower)
IntroSongCh3Bass:
    ; Bar 1 (Em octave bass)
    db N_E3, N_E4, N_E3, N_E4,  N_E3, N_E4, N_E3, N_E4,   N_E3, N_E4, N_E3, N_E4,   N_E3, N_G3, N_B3, N_D4
    ; Bar 2 (C -> D octave bass)
    db N_C3, N_C4, N_C3, N_C4,  N_C3, N_C4, N_C3, N_C4,   N_D3, N_D4, N_D3, N_D4,   N_D3, N_E3, N_FS3, N_A3
    ; Bar 3 (Em -> Bm octave bass)
    db N_E3, N_E4, N_E3, N_E4,  N_E3, N_E4, N_E3, N_D4,   N_B3, N_B4, N_B3, N_B4,   N_B3, N_A3, N_G3, N_FS3
    ; Bar 4 (C -> B7 bass)
    db N_C3, N_C4, N_C3, N_C4,  N_A3, N_A4, N_A3, N_A4,   N_B3, N_B4, N_B3, N_B4,   N_B3, N_FS3, N_A3, N_B3
    ; Bar 5 (G -> D/F# bass)
    db N_G3, N_G4, N_G3, N_G4,  N_G3, N_G4, N_B3, N_D4,   N_FS3, N_FS4, N_FS3, N_FS4, N_D3, N_D4, N_E3, N_FS3
    ; Bar 6 (Em -> C -> G bass)
    db N_E3, N_E4, N_E3, N_E4,  N_E3, N_E4, N_D3, N_D4,   N_C3, N_C4, N_C3, N_C4,   N_G3, N_G4, N_G3, N_B3
    ; Bar 7 (Am -> Bm -> C -> D rising bass)
    db N_A3, N_A4, N_A3, N_A4,  N_B3, N_B4, N_B3, N_B4,   N_C3, N_C4, N_C3, N_C4,   N_D3, N_D4, N_D3, N_FS3
    ; Bar 8 (Em -> B7 cadence bass)
    db N_E3, N_E4, N_E3, N_E4,  N_G3, N_G4, N_E3, N_E4,   N_B3, N_B4, N_FS3, N_FS4, N_B3, N_A3, N_G3, N_FS3

; Channel 4: Crisp Drum Kit (Kick, Snare, Closed/Open Hats)
IntroSongCh4Drums:
    ; Bar 1
    db D_KICK, D_HAT, D_HAT, D_HAT,   D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_HAT, D_OHAT, D_HAT
    ; Bar 2
    db D_KICK, D_HAT, D_HAT, D_HAT,   D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_SNARE, D_OHAT, D_SNARE
    ; Bar 3
    db D_KICK, D_HAT, D_HAT, D_HAT,   D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_HAT, D_OHAT, D_HAT
    ; Bar 4 (Turnaround snare fill)
    db D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_HAT, D_KICK, D_SNARE, D_KICK, D_SNARE, D_SNARE, D_HAT, D_SNARE, D_SNARE, D_OHAT, D_SNARE
    ; Bar 5
    db D_KICK, D_HAT, D_HAT, D_KICK,  D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_HAT, D_KICK,  D_SNARE, D_HAT, D_OHAT, D_HAT
    ; Bar 6
    db D_KICK, D_HAT, D_HAT, D_KICK,  D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_SNARE, D_OHAT, D_HAT
    ; Bar 7 (Driving double-kick under 16th run)
    db D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_SNARE, D_SNARE, D_OHAT
    ; Bar 8 (Dramatic loop fill)
    db D_KICK, D_HAT, D_KICK, D_HAT,  D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_SNARE, D_KICK, D_SNARE, D_SNARE, D_SNARE, D_OHAT, D_SNARE

; ---------------------------------------------------------------------------
; Game Screen BGM ("Sunlight in Amity Village" - 8 Bars, 128 Steps)
; Key: G Major / E Minor, Slow Upbeat Strolling Groove (~83 BPM)
; ---------------------------------------------------------------------------

; Channel 2: Warm Upbeat Overworld Melody
GameSongCh2Lead:
    ; Bar 1 (G -> D/F#): Sunny bouncy opening motif
    db N_D5, 0, N_B4, N_D5,  N_G5, 0, 0, N_FS5,   N_E5, 0, N_D5, 0,         N_A4, 0, N_B4, N_C5
    ; Bar 2 (Em7 -> Bm7): Gentle strolling response
    db N_B4, 0, N_G4, N_A4,  N_B4, 0, N_D5, 0,    N_E5, 0, N_D5, N_B4,      N_A4, 0, 0, 0
    ; Bar 3 (C -> G/B): Bright rising hook
    db N_E5, 0, N_G5, 0,     N_FS5, N_E5, N_D5, 0, N_D5, 0, N_B4, N_D5,     N_G5, 0, N_D5, 0
    ; Bar 4 (Am7 -> D7): Upbeat half-cadence turnaround
    db N_C5, 0, N_B4, N_A4,  N_G4, 0, N_A4, N_B4,  N_A4, 0, 0, N_D5,        N_E5, 0, N_FS5, 0
    ; Bar 5 (C -> D7): Soaring B-section melody
    db N_G5, 0, 0, N_FS5,    N_E5, 0, N_G5, 0,     N_FS5, 0, 0, N_E5,       N_D5, 0, N_FS5, N_A5
    ; Bar 6 (Bm7 -> Em7): Expressive melodic cascade
    db N_G5, 0, N_FS5, N_D5, N_B4, 0, 0, N_D5,     N_E5, 0, N_D5, N_B4,     N_G4, 0, N_A4, N_B4
    ; Bar 7 (Am7 -> Bm7 -> C -> D7): Cheerful syncopated climb
    db N_C5, 0, N_A4, N_C5,  N_D5, 0, N_B4, N_D5,  N_E5, 0, N_G5, N_E5,     N_FS5, 0, N_A5, N_FS5
    ; Bar 8 (G -> D7 turnaround): Warm resolution & upbeat pickup into Bar 1
    db N_G5, 0, 0, N_D5,     N_B4, 0, N_G4, 0,     N_A4, 0, N_B4, N_C5,     N_D5, 0, N_E5, N_FS5

; Channel 1: Sparkling Bell Arpeggios & Sweet 3rd/6th Counter-Melody
GameSongCh1Harm:
    ; Bar 1 (G -> D/F#)
    db N_B4, N_G4, N_D4, N_G4,  N_B4, N_D5, N_B4, N_A4,   N_A4, N_FS4, N_D4, N_FS4,  N_D4, N_FS4, N_G4, N_A4
    ; Bar 2 (Em7 -> Bm7)
    db N_G4, N_E4, N_B3, N_E4,  N_G4, N_B4, N_G4, N_B4,   N_B4, N_FS4, N_D4, N_FS4,  N_FS4, N_D4, N_E4, N_FS4
    ; Bar 3 (C -> G/B)
    db N_C5, N_G4, N_E4, N_G4,  N_C5, N_G4, N_FS4, N_G4,  N_B4, N_G4, N_D4, N_G4,    N_B4, N_D5, N_B4, N_G4
    ; Bar 4 (Am7 -> D7)
    db N_A4, N_E4, N_C4, N_E4,  N_E4, N_C4, N_E4, N_G4,   N_FS4, N_D4, N_A3, N_FS4,  N_G4, N_A4, N_B4, N_C5
    ; Bar 5 (C -> D7)
    db N_E5, N_C5, N_G4, N_C5,  N_C5, N_G4, N_E5, N_C5,   N_D5, N_A4, N_FS4, N_A4,   N_A4, N_FS4, N_A4, N_D5
    ; Bar 6 (Bm7 -> Em7)
    db N_D5, N_B4, N_FS4, N_B4, N_F4, N_D4, N_FS4, N_B4,  N_B4, N_G4, N_E4, N_G4,    N_E4, N_B3, N_E4, N_G4
    ; Bar 7 (Am7 -> Bm7 -> C -> D7 harmonized climb)
    db N_E4, N_C4, N_E4, N_A4,  N_FS4, N_D4, N_FS4, N_B4, N_G4, N_E4, N_C5, N_G4,    N_A4, N_FS4, N_D5, N_C5
    ; Bar 8 (G -> D7 turnaround)
    db N_B4, N_D5, N_B4, N_B4,  N_G4, N_D4, N_B3, N_D4,   N_FS4, N_D4, N_G4, N_A4,   N_B4, N_A4, N_C5, N_A4

; Channel 3: Bouncy Syncopated Walking Wave Bass (sounds 1 octave lower)
GameSongCh3Bass:
    ; Bar 1 (G -> D/F#)
    db N_G3, 0, NOTE_REST, N_G4,  N_G3, 0, N_D3, N_E3,   N_FS3, 0, NOTE_REST, N_FS4, N_D3, 0, N_E3, N_FS3
    ; Bar 2 (Em7 -> Bm7)
    db N_E3, 0, NOTE_REST, N_E4,  N_E3, 0, N_G3, N_A3,   N_B3, 0, NOTE_REST, N_B4,   N_B3, 0, N_D4, N_CS4
    ; Bar 3 (C -> G/B)
    db N_C3, 0, NOTE_REST, N_C4,  N_C3, 0, N_E3, N_G3,   N_B3, 0, NOTE_REST, N_B4,   N_G3, 0, N_D3, N_B3
    ; Bar 4 (Am7 -> D7)
    db N_A3, 0, NOTE_REST, N_A4,  N_E3, 0, N_G3, N_A3,   N_D3, 0, NOTE_REST, N_D4,   N_D3, 0, N_E3, N_FS3
    ; Bar 5 (C -> D7)
    db N_C3, 0, NOTE_REST, N_C4,  N_G3, 0, N_E3, N_C3,   N_D3, 0, NOTE_REST, N_D4,   N_A3, 0, N_FS3, N_D3
    ; Bar 6 (Bm7 -> Em7)
    db N_B3, 0, NOTE_REST, N_B4,  N_FS3, 0, N_D3, N_B3,  N_E3, 0, NOTE_REST, N_E4,   N_E3, 0, N_G3, N_B3
    ; Bar 7 (Am7 -> Bm7 -> C -> D7 walking bass)
    db N_A3, 0, N_A4, 0,          N_B3, 0, N_B4, 0,      N_C3, 0, N_C4, 0,           N_D3, 0, N_E3, N_FS3
    ; Bar 8 (G -> D7 turnaround)
    db N_G3, 0, NOTE_REST, N_G4,  N_D3, 0, N_B3, N_G3,   N_D3, 0, N_D4, 0,           N_D3, 0, N_E3, N_FS3

; Channel 4: Relaxed Upbeat Overworld Percussion Groove
GameSongCh4Drums:
    ; Bar 1
    db D_KICK, 0, D_HAT, 0,        D_SNARE, 0, D_HAT, D_KICK,  0, D_HAT, D_KICK, 0,       D_SNARE, 0, D_OHAT, 0
    ; Bar 2
    db D_KICK, 0, D_HAT, 0,        D_SNARE, 0, D_HAT, D_KICK,  0, D_HAT, D_KICK, 0,       D_SNARE, 0, D_HAT, D_SNARE
    ; Bar 3
    db D_KICK, 0, D_HAT, 0,        D_SNARE, 0, D_HAT, D_KICK,  0, D_HAT, D_KICK, 0,       D_SNARE, 0, D_OHAT, 0
    ; Bar 4
    db D_KICK, 0, D_HAT, D_KICK,   D_SNARE, 0, D_HAT, 0,       D_KICK, 0, D_SNARE, D_HAT, D_SNARE, 0, D_OHAT, D_HAT
    ; Bar 5
    db D_KICK, 0, D_HAT, 0,        D_SNARE, 0, D_HAT, D_KICK,  0, D_HAT, D_KICK, 0,       D_SNARE, 0, D_OHAT, 0
    ; Bar 6
    db D_KICK, 0, D_HAT, 0,        D_SNARE, 0, D_HAT, D_KICK,  0, D_HAT, D_KICK, 0,       D_SNARE, D_HAT, D_OHAT, 0
    ; Bar 7
    db D_KICK, 0, D_HAT, D_KICK,   D_SNARE, 0, D_HAT, D_KICK,  D_KICK, 0, D_HAT, D_KICK,  D_SNARE, 0, D_OHAT, D_HAT
    ; Bar 8
    db D_KICK, 0, D_HAT, 0,        D_SNARE, 0, D_HAT, D_KICK,  D_KICK, 0, D_SNARE, 0,     D_SNARE, D_HAT, D_OHAT, D_SNARE

; ---------------------------------------------------------------------------
; Fight Scene BGM ("Red Alert Encounter" - 8 Bars, 128 Steps)
; MSX Tactical Espionage Alarm Style: Driving E Minor / Phrygian Ostinato (~150 BPM)
; ---------------------------------------------------------------------------

; Channel 2: Urgent Brass Alarm Stabs & Tactical Pursuit Lead
BattleSongCh2Lead:
    ; Bar 1 (Em/Bb): Iconic Red Alert syncopated brass stabs!
    db N_B4, 0, NOTE_REST, N_B4,  0, NOTE_REST, N_C5, 0,       NOTE_REST, N_B4, 0, N_E5,  0, N_D5, N_C5, N_B4
    ; Bar 2 (Em/Bb): Second alarm stab phrase with chromatic tension
    db N_B4, 0, NOTE_REST, N_B4,  0, NOTE_REST, N_C5, 0,       NOTE_REST, N_D5, 0, N_F5,  0, N_E5, N_D5, N_C5
    ; Bar 3 (Em -> C): High urgent pursuit motif
    db N_E5, 0, 0, N_G5,          N_FS5, N_E5, N_D5, N_E5,     N_C5, 0, 0, N_E5,          N_D5, N_C5, N_B4, N_A4
    ; Bar 4 (Am -> B7): Tense ascending tactical brass
    db N_B4, 0, N_E5, 0,          N_FS5, 0, N_G5, 0,           N_A5, N_G5, N_FS5, N_E5,   N_DS5, 0, N_FS5, 0
    ; Bar 5 (Em -> Dm): Infiltration crisis call-and-response
    db N_G5, 0, N_FS5, N_G5,      N_E5, 0, N_B4, 0,            N_F5, 0, N_E5, N_F5,       N_D5, 0, N_A4, 0
    ; Bar 6 (Cmaj7 -> B7): Chromatic spy-thriller sequence
    db N_E5, 0, N_DS5, N_E5,      N_C5, 0, N_A4, 0,            N_B4, N_C5, N_DS5, N_E5,   N_FS5, 0, N_B4, 0
    ; Bar 7 (Chromatic Siren Climb!): Urgent 16th-note alarm escalation
    db N_E4, N_F4, N_FS4, N_G4,   N_GS4, N_A4, N_AS4, N_B4,    N_C5, N_CS5, N_D5, N_DS5,  N_E5, 0, N_G5, 0
    ; Bar 8 (B7 Alert Turnaround): Dramatic double-stab cadence back to Bar 1
    db N_FS5, 0, N_DS5, N_B4,     N_C5, 0, N_A4, N_FS4,        N_B4, NOTE_REST, N_B4, NOTE_REST, N_B4, N_FS4, N_G4, N_A4

; Channel 1: Tense 4th/Tritone Alarm Harmony & Rapid 16th-Note Alert Pulse
BattleSongCh1Harm:
    ; Bar 1 (Harmonized stabs + rapid E4/B3 alert pulse)
    db N_FS4, 0, NOTE_REST, N_FS4, 0, NOTE_REST, N_G4, 0,      NOTE_REST, N_FS4, 0, N_B4, 0, N_A4, N_G4, N_FS4
    ; Bar 2
    db N_FS4, 0, NOTE_REST, N_FS4, 0, NOTE_REST, N_G4, 0,      NOTE_REST, N_A4, 0, N_C5,  0, N_B4, N_A4, N_G4
    ; Bar 3 (Rapid 16th-note MSX PSG tension ostinato)
    db N_B4, N_E4, N_B4, N_E4,    N_A4, N_E4, N_G4, N_E4,      N_G4, N_C4, N_G4, N_C4,    N_FS4, N_C4, N_E4, N_C4
    ; Bar 4
    db N_G4, N_E4, N_B4, N_E4,    N_A4, N_FS4, N_B4, N_G4,     N_C5, N_B4, N_A4, N_G4,    N_FS4, N_DS4, N_B3, N_DS4
    ; Bar 5
    db N_B4, N_E4, N_A4, N_B4,    N_G4, N_E4, N_G4, N_E4,      N_A4, N_D4, N_G4, N_A4,    N_F4, N_D4, N_F4, N_D4
    ; Bar 6
    db N_G4, N_C4, N_FS4, N_G4,   N_E4, N_C4, N_E4, N_C4,      N_FS4, N_G4, N_A4, N_B4,   N_DS5, N_B4, N_FS4, N_DS4
    ; Bar 7 (Harmonized chromatic siren climb in 3rds/4ths)
    db N_B3, N_C4, N_CS4, N_D4,   N_DS4, N_E4, N_F4, N_FS4,    N_G4, N_GS4, N_A4, N_AS4,  N_B4, N_E4, N_B4, N_E5
    ; Bar 8
    db N_DS5, N_B4, N_FS4, N_DS4, N_E4, N_C4, N_E4, N_C4,      N_FS4, NOTE_REST, N_FS4, NOTE_REST, N_FS4, N_DS4, N_E4, N_FS4

; Channel 3: Relentless MSX Red Alert Syncopated Ostinato Wave Bass
BattleSongCh3Bass:
    ; Bar 1 (Signature E - E - G - A - Bb - A - G - E ostinato!)
    db N_E3, N_E3, N_G3, N_A3,    N_AS3, N_A3, N_G3, N_E3,     N_E3, N_E3, N_G3, N_A3,    N_AS3, N_A3, N_G3, N_E3
    ; Bar 2
    db N_E3, N_E3, N_G3, N_A3,    N_AS3, N_A3, N_G3, N_E3,     N_D3, N_D3, N_F3, N_G3,    N_A3, N_G3, N_F3, N_D3
    ; Bar 3
    db N_E3, N_E4, N_E3, N_E4,    N_E3, N_G3, N_A3, N_B3,      N_C3, N_C4, N_C3, N_C4,    N_C3, N_E3, N_G3, N_A3
    ; Bar 4
    db N_E3, N_E4, N_G3, N_G4,    N_FS3, N_FS4, N_E3, N_E4,    N_A3, N_A4, N_A3, N_G3,    N_B3, N_FS3, N_DS3, N_B3
    ; Bar 5
    db N_E3, N_E4, N_E3, N_G3,    N_A3, N_G3, N_E3, N_D3,      N_D3, N_D4, N_D3, N_F3,    N_G3, N_F3, N_D3, N_C3
    ; Bar 6
    db N_C3, N_C4, N_C3, N_E3,    N_G3, N_E3, N_C3, N_B3,      N_B3, N_B4, N_B3, N_B4,    N_B3, N_A3, N_G3, N_FS3
    ; Bar 7 (Rising bass pulse under siren climb)
    db N_E3, N_E3, N_F3, N_FS3,   N_G3, N_GS3, N_A3, N_AS3,    N_B3, N_C4, N_CS4, N_D4,   N_E4, N_B3, N_G3, N_E3
    ; Bar 8
    db N_B3, N_B4, N_B3, N_B4,    N_A3, N_A4, N_FS3, N_FS4,    N_B3, NOTE_REST, N_B3, NOTE_REST, N_B3, N_A3, N_G3, N_FS3

; Channel 4: Tactical Military Snare & Kick Drive
BattleSongCh4Drums:
    ; Bar 1
    db D_KICK, D_SNARE, D_HAT, D_SNARE,  D_KICK, D_HAT, D_SNARE, D_HAT,  D_KICK, D_HAT, D_SNARE, D_KICK, D_SNARE, D_HAT, D_OHAT, D_SNARE
    ; Bar 2
    db D_KICK, D_SNARE, D_HAT, D_SNARE,  D_KICK, D_HAT, D_SNARE, D_HAT,  D_KICK, D_HAT, D_SNARE, D_KICK, D_SNARE, D_SNARE, D_OHAT, D_SNARE
    ; Bar 3
    db D_KICK, D_HAT, D_KICK, D_HAT,     D_SNARE, D_HAT, D_KICK, D_HAT,  D_KICK, D_HAT, D_KICK, D_HAT,   D_SNARE, D_HAT, D_OHAT, D_HAT
    ; Bar 4
    db D_KICK, D_HAT, D_KICK, D_HAT,     D_SNARE, D_HAT, D_KICK, D_SNARE, D_KICK, D_SNARE, D_KICK, D_SNARE, D_SNARE, D_SNARE, D_OHAT, D_SNARE
    ; Bar 5
    db D_KICK, D_HAT, D_SNARE, D_HAT,    D_KICK, D_KICK, D_SNARE, D_HAT, D_KICK, D_HAT, D_SNARE, D_HAT,  D_KICK, D_SNARE, D_OHAT, D_HAT
    ; Bar 6
    db D_KICK, D_HAT, D_SNARE, D_HAT,    D_KICK, D_KICK, D_SNARE, D_HAT, D_KICK, D_SNARE, D_KICK, D_SNARE, D_SNARE, D_SNARE, D_OHAT, D_SNARE
    ; Bar 7 (Military snare roll escalation)
    db D_KICK, D_SNARE, D_KICK, D_SNARE, D_KICK, D_SNARE, D_KICK, D_SNARE, D_KICK, D_SNARE, D_SNARE, D_SNARE, D_KICK, D_SNARE, D_OHAT, D_SNARE
    ; Bar 8 (Alert stab punctuation)
    db D_KICK, D_HAT, D_SNARE, D_HAT,    D_KICK, D_HAT, D_SNARE, D_HAT,  D_SNARE, 0, D_SNARE, 0,         D_SNARE, D_SNARE, D_OHAT, D_SNARE

; ---------------------------------------------------------------------------
; Win Battle Jingle ("Threads of Victory" - 32 Steps, One-Shot Fanfare)
; Key: G Major, Triumphant 8-Bit RPG Victory Fanfare
; ---------------------------------------------------------------------------
VictoryJingleCh2Lead:
    ; Rapid fanfare pickup (D5-D5-D5-G5! - D5-G5!) -> bVI-bVII-I climb (Eb5 -> F5 -> G5!)
    db N_D5, N_D5, N_D5, N_G5,  0, N_D5, N_G5, 0,          N_DS5, 0, 0, N_F5,         0, 0, N_G5, 0
    db N_A5, 0, N_FS5, N_D5,    N_G5, 0, 0, 0,             0, 0, 0, 0,                NOTE_REST, 0, 0, 0

VictoryJingleCh1Harm:
    db N_B4, N_B4, N_B4, N_D5,  0, N_B4, N_D5, 0,          N_C5, 0, 0, N_D5,          0, 0, N_D5, 0
    db N_E5, 0, N_C5, N_A4,     N_B4, 0, 0, 0,             0, 0, 0, 0,                NOTE_REST, 0, 0, 0

VictoryJingleCh3Bass:
    db N_G3, N_G3, N_G3, N_G4,  0, N_D3, N_G3, 0,          N_DS3, 0, N_AS3, N_F3,     0, N_C4, N_G3, 0
    db N_C3, 0, N_D3, 0,        N_G3, 0, N_D3, N_G3,       0, 0, 0, 0,                NOTE_REST, 0, 0, 0

VictoryJingleCh4Drums:
    db D_SNARE, D_SNARE, D_SNARE, D_KICK, D_HAT, D_SNARE, D_KICK, D_HAT, D_KICK, D_HAT, D_SNARE, D_KICK, D_HAT, D_SNARE, D_KICK, D_OHAT
    db D_KICK, D_SNARE, D_KICK, D_SNARE,  D_OHAT, 0, 0, 0,               0, 0, 0, 0,                     0, 0, 0, 0

; ---------------------------------------------------------------------------
; Game Over Jingle ("Severed Thread" - 32 Steps, One-Shot Dirge)
; Key: E Minor, Solemn Descending Lament
; ---------------------------------------------------------------------------
GameOverJingleCh2Lead:
    db N_E5, 0, N_D5, N_C5,     N_B4, 0, N_A4, N_G4,       N_FS4, 0, N_G4, N_A4,      N_FS4, 0, N_DS4, 0
    db N_E4, 0, 0, 0,           0, 0, 0, 0,                0, 0, 0, 0,                NOTE_REST, 0, 0, 0

GameOverJingleCh1Harm:
    db N_C5, 0, N_B4, N_A4,     N_G4, 0, N_FS4, N_E4,      N_DS4, 0, N_E4, N_FS4,     N_DS4, 0, N_B3, 0
    db N_G3, 0, 0, 0,           0, 0, 0, 0,                0, 0, 0, 0,                NOTE_REST, 0, 0, 0

GameOverJingleCh3Bass:
    db N_E3, 0, 0, N_D3,        N_C3, 0, 0, N_B3,          N_A3, 0, 0, N_FS3,         N_B3, 0, N_B3, 0
    db N_E3, 0, 0, 0,           0, 0, 0, 0,                0, 0, 0, 0,                NOTE_REST, 0, 0, 0

GameOverJingleCh4Drums:
    db D_KICK, 0, 0, D_HAT,     D_SNARE, 0, 0, D_HAT,      D_KICK, 0, 0, D_HAT,       D_SNARE, 0, D_SNARE, 0
    db D_OHAT, 0, 0, 0,         0, 0, 0, 0,                0, 0, 0, 0,                0, 0, 0, 0

; ===========================================================================
; Sound Effects (DMG Pulse Channel 1)
; ===========================================================================
PlaySFXCursor:
    ld a, 10
    ld [wSFXLockTimer], a
    ld a, $00
    ld [rNR10], a
    ld a, $81
    ld [rNR11], a
    ld a, $A1
    ld [rNR12], a
    ld a, $50
    ld [rNR13], a
    ld a, $87
    ld [rNR14], a
    ret

PlaySFXConfirm:
    ld a, 14
    ld [wSFXLockTimer], a
    ld a, $15
    ld [rNR10], a
    ld a, $80
    ld [rNR11], a
    ld a, $F2
    ld [rNR12], a
    ld a, $60
    ld [rNR13], a
    ld a, $87
    ld [rNR14], a
    ret

; ===========================================================================
; Utility Routines
; ===========================================================================
WaitVBlank:
    ld a, [rLY]
    cp 144
    jr c, WaitVBlank
    ret

DisableLCD:
    ld a, [rLCDC]
    rlca
    ret nc ; Already off
    call WaitVBlank
    xor a
    ld [rLCDC], a
    ret

CopyData:
    ; hl = source, de = dest, bc = length
    ld a, b
    or c
    ret z
    ld a, [hl+]
    ld [de], a
    inc de
    dec bc
    jr CopyData

ClearBGMap0:
    ld hl, _SCRN0
    ld bc, 32 * 32
.loop:
    xor a
    ld [hl+], a
    dec bc
    ld a, b
    or c
    jr nz, .loop
    ret

ClearShadowOAM:
    ld hl, wOAMBuffer
    ld b, 160
    xor a
.loop:
    ld [hl+], a
    dec b
    jr nz, .loop
    ret

; Place a 16x16 metasprite (4 8x8 OAM entries)
; Input: a = starting OAM index (0..36), [wSpriteY], [wSpriteX], [wSpriteTile]
SetMetaSprite16x16:
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl ; * 4 bytes per OAM entry
    ld de, wOAMBuffer
    add hl, de

    ; Top-Left
    ld a, [wSpriteY]
    ld [hl+], a
    ld a, [wSpriteX]
    ld [hl+], a
    ld a, [wSpriteTile]
    ld [hl+], a
    xor a
    ld [hl+], a

    ; Top-Right
    ld a, [wSpriteY]
    ld [hl+], a
    ld a, [wSpriteX]
    add 8
    ld [hl+], a
    ld a, [wSpriteTile]
    inc a
    ld [hl+], a
    xor a
    ld [hl+], a

    ; Bottom-Left
    ld a, [wSpriteY]
    add 8
    ld [hl+], a
    ld a, [wSpriteX]
    ld [hl+], a
    ld a, [wSpriteTile]
    add 2
    ld [hl+], a
    xor a
    ld [hl+], a

    ; Bottom-Right
    ld a, [wSpriteY]
    add 8
    ld [hl+], a
    ld a, [wSpriteX]
    add 8
    ld [hl+], a
    ld a, [wSpriteTile]
    add 3
    ld [hl+], a
    xor a
    ld [hl+], a
    ret

; Draw Aretha II Double-Bordered Window Box on _SCRN0
; Input: b = X (0..19), c = Y (0..17), d = Width (2..20), e = Height (2..18)
DrawDialogBox:
    ; Compute top-left address in _SCRN0: hl = $9800 + c*32 + b
    ld l, c
    ld h, 0
    add hl, hl ; *2
    add hl, hl ; *4
    add hl, hl ; *8
    add hl, hl ; *16
    add hl, hl ; *32
    ld a, b
    add l
    ld l, a
    ld a, h
    adc $98
    ld h, a

    ; Top Row: Tile $01 (TL), d-2 of Tile $02 (T), Tile $03 (TR)
    push hl
    ld a, $01
    ld [hl+], a
    ld a, d
    sub 2
    ld b, a
    ld a, $02
.topLoop:
    ld [hl+], a
    dec b
    jr nz, .topLoop
    ld a, $03
    ld [hl], a
    pop hl

    ; Advance to next row
    ld bc, 32
    add hl, bc

    ; Middle Rows (e - 2 rows): Tile $04 (L), d-2 of Tile $00 (Blank), Tile $05 (R)
    ld a, e
    sub 2
    ld c, a
.midRowLoop:
    push hl
    ld a, $04
    ld [hl+], a
    ld a, d
    sub 2
    ld b, a
    xor a ; Tile $00
.midColLoop:
    ld [hl+], a
    dec b
    jr nz, .midColLoop
    ld a, $05
    ld [hl], a
    pop hl
    push bc
    ld bc, 32
    add hl, bc
    pop bc
    dec c
    jr nz, .midRowLoop

    ; Bottom Row: Tile $06 (BL), d-2 of Tile $07 (B), Tile $08 (BR)
    ld a, $06
    ld [hl+], a
    ld a, d
    sub 2
    ld b, a
    ld a, $07
.botLoop:
    ld [hl+], a
    dec b
    jr nz, .botLoop
    ld a, $08
    ld [hl], a
    ret

; Print null-terminated string at DE to VRAM address HL (waits for VBlank/HBlank if LCD is on)
PrintString:
.waitVRAM:
    ld a, [rSTAT]
    and %00000010
    jr nz, .waitVRAM
    ld a, [de]
    or a
    ret z
    ld [hl+], a
    inc de
    jr PrintString

; Read Joypad into wJoyHeld and wJoyPressed
ReadJoypad:
    ld a, $20 ; Select D-Pad (P14=0)
    ld [rJOYP], a
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    cpl
    and $0F
    swap a
    ld b, a

    ld a, $30 ; Deselect both lines to let matrix settle before switching
    ld [rJOYP], a

    ld a, $10 ; Select Buttons (P15=0)
    ld [rJOYP], a
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    ld a, [rJOYP]
    cpl
    and $0F
    or b
    ld b, a ; b = current held buttons

    ld a, $30 ; Reset joypad lines
    ld [rJOYP], a

    ld a, [wJoyHeld]
    xor b
    and b
    ld [wJoyPressed], a
    ld a, b
    ld [wJoyHeld], a
    ret

; Copy OAM DMA routine to HRAM
InitDMARoutine:
    ld hl, DMARoutineROM
    ld de, hOAMDMA
    ld bc, DMARoutineROMEnd - DMARoutineROM
    call CopyData
    ret

DMARoutineROM:
    ld a, HIGH(wOAMBuffer)
    ld [rDMA], a
    ld a, 40
.wait:
    dec a
    jr nz, .wait
    ret
DMARoutineROMEnd:

; ===========================================================================
; Text Strings (Mapped via CHARMAP)
; ===========================================================================
StrSplashTitle1:
    db "* THREADS OF *", 0
StrSplashTitle2:
    db "  * AMITY *  ", 0
StrSplashTitle3:
    db "- 2.5D JRPG -", 0
StrPressStart:
    db "PRESS START!", 0
StrCopyright:
    db "1991-2026 DEMO", 0

StrSelectHeader1:
    db "CHOOSE YOUR HERO", 0
StrSelectHeader2:
    db "M / F / NB CLASS", 0

StrOptMale:
    db "M:  ARIA", 0
StrOptFemale:
    db "F:  SAKURA", 0
StrOptNB:
    db "NB: ORION", 0

StrDescM1:
    db "CLASS: KNIGHT (M)", 0
StrDescM2:
    db "HP:34 AT:10 DF:05", 0
StrDescM3:
    db "HEAVY BLADE HERO", 0

StrDescF1:
    db "CLASS: MAGE   (F)", 0
StrDescF2:
    db "HP:28 AT:08 DF:03", 0
StrDescF3:
    db "AMITY RING HERO ", 0

StrDescNB1:
    db "CLASS: RANGER(NB)", 0
StrDescNB2:
    db "HP:30 AT:09 DF:04", 0
StrDescNB3:
    db "ASTRAL HERO     ", 0

StrReady1:
    db "SELECTED HERO:", 0
StrReady2:
    db "B:CHANGE SELECT", 0

; Katakana & English headers + dialogue from the second uploaded image!
; Katakana tiles: $28=ア, $29=リ, $2A=サ, $2B=ク, $2C=ラ, $2D=オ, $2E=ン, $2F="
StrHeaderAriaJP:
    db $09, $28, $29, $28, $09, 0 ; ♦アリア♦
StrHeaderAriaEN:
    db "ARIA", 0
StrAriaL1:
    db "MY HEART", 0
StrAriaL2:
    db "IS READY...", 0
StrAriaL3:
    db "WITH OUR", 0
StrAriaL4:
    db "THREADS,", 0
StrAriaL5:
    db "I WILL", 0
StrAriaL6:
    db "PROTECT!", $2F, 0

StrHeaderSakuraJP:
    db $09, $2A, $2B, $2C, $09, 0 ; ♦サクラ♦
StrHeaderSakuraEN:
    db "SAKURA", 0
StrSakuraL1:
    db "REALLY?", 0
StrSakuraL2:
    db "THE THREADS", 0
StrSakuraL3:
    db "OF AMITY ARE", 0
StrSakuraL4:
    db "AWAKENING...!", 0

StrHeaderOrionJP:
    db $09, $2D, $29, $2D, $2E, $09, 0 ; ♦オリオン♦
StrHeaderOrionEN:
    db "ORION", 0
StrOrionL1:
    db "THE WORLD", 0
StrOrionL2:
    db "IS MANY", 0
StrOrionL3:
    db "COLORS...", 0
StrOrionL4:
    db "LET'S FIND", 0
StrOrionL5:
    db "OURS!", $2F, 0

StrHeaderGaiusJP:
    db $09, $0E, $0F, $28, $09, 0 ; ♦ガイア♦
StrHeaderGaiusEN:
    db "GAIUS", 0

StrNPCDialogP2L1:
    db "I WILL GUIDE YOUR", 0
StrNPCDialogP2L2:
    db "WAY THROUGH THE", 0
StrNPCDialogP2L3:
    db "WEFT AND WARP...", $09, 0
StrNPCDialogP2L4:
    db "(HEALED+RESPAWN)", 0

StrTerfDialogL1:
    db $09, "TERF", $09, " TERF", 0
StrTerfDialogL2:
    db "WARDEN OF THE CODE", 0
StrTerfDialogL3:
    db $2F, "YOU CANNOT CHANGE", 0
StrTerfDialogL4:
    db "WHAT YOU ARE!", $2F, $09, 0

StrHeaderBobBeard:
    db $09, "BOB (BEARDED)", $09, 0
StrBobReqL1:
    db $2F, "THE WEAVE BINDS", 0
StrBobReqL2:
    db "ME AS A MAN...", 0
StrBobReqL3:
    db "I LONG TO TRY ON", 0
StrBobReqL4:
    db "THE SILK DRESS", 0
StrBobReqL5:
    db "IN THE CHEST", 0
StrBobReqL6:
    db "PAST THE BRIDGE!", $2F, 0

StrBobTryL1:
    db $2F, "YOU BROUGHT THE", 0
StrBobTryL2:
    db "SILK DRESS!", 0
StrBobTryL3:
    db "LET ME TRY IT", 0
StrBobTryL4:
    db "ON RIGHT NOW...", $2F, 0

StrHeaderBobFem:
    db $09, "BOB (SHE/HER)", $09, 0
StrBobFreeL1:
    db $2F, "THE WEAVE'S HOLD", 0
StrBobFreeL2:
    db "IS BROKEN!", 0
StrBobFreeL3:
    db "I AM FINALLY A", 0
StrBobFreeL4:
    db "WOMAN! FREE AT", 0
StrBobFreeL5:
    db "LAST! THANK YOU!", $2F, 0

StrHeaderChest:
    db "* TREASURE CHEST *", 0
StrChestFoundL1:
    db "YOU OPENED THE", 0
StrChestFoundL2:
    db "WOODEN CHEST!", 0
StrChestFoundL3:
    db "FOUND THE LOVELY", 0
StrChestFoundL4:
    db $2F, "SILK DRESS", $2F, "!", 0

StrChestEmptyL1:
    db "THE TREASURE", 0
StrChestEmptyL2:
    db "CHEST IS EMPTY.", 0

StrInvTitle:
    db "* INVENTORY *", 0
StrItemEmpty:
    db "- EMPTY -", 0
StrItemSilkDress:
    db "SILK DRESS", 0

StrEnemyName:
    db "* SHADOW FIEND *", 0
StrTerfName:
    db "*  BOSS: TERF  *", 0
StrHPLabel:
    db "HP:", 0
StrATKLabel:
    db "AT:", 0
StrDEFLabel:
    db "DF:", 0
StrLVLabel:
    db "LV:", 0
StrXPLabel:
    db "XP:", 0
StrNextLabel:
    db "NX:", 0
StrCmdFight:
    db "FIGHT", 0
StrCmdMagic:
    db "RING MAGIC", 0
StrCmdRun:
    db "RUN", 0
StrBattleAppear:
    db "FIEND ATTACKS!", 0
StrTerfAppear:
    db "EVIL TERF RAGES!", 0
StrBattleSlash:
    db "SWORD HIT! -00HP", 0
StrBattleMagic:
    db "RING BLAST! -00H", 0
StrFiendAttackMsg:
    db "FIEND CLAW! -00H", 0
StrTerfAttackMsg:
    db "TERF RANT! -00HP", 0
StrBattleVictory:
    db "WIN! +00XP   (A)", 0
StrBattleLevelUp:
    db "LEVEL UP! LV:00!", 0

StrGameOverTitle:
    db "* GAME OVER *", 0
StrGameOverSub1:
    db "YOUR THREAD", 0
StrGameOverSub2:
    db "WAS SEVERED..", 0
StrGameOverRetry:
    db "PRESS A: RETRY", 0

; ===========================================================================
; Work RAM & High RAM Allocations
; ===========================================================================
SECTION "OAM Buffer", WRAM0[$C000]
wOAMBuffer:
    ds 160

SECTION "Game Variables", WRAM0[$C100]
wGameState:     ds 1
wFrameCounter:  ds 1
wJoyHeld:       ds 1
wJoyPressed:    ds 1
wSelectedChar:  ds 1
wSpriteY:       ds 1
wSpriteX:       ds 1
wSpriteTile:    ds 1
wPlayerWorldX:  ds 1
wPlayerWorldY:  ds 1
wPlayerDir:     ds 1
wWalkDistance:  ds 1
wCameraX:       ds 1
wCameraY:       ds 1
wNPCWorldX:     ds 1
wNPCWorldY:     ds 1
wBobWorldX:     ds 1
wBobWorldY:     ds 1
wBobQuestState: ds 1 ; 0 = Bearded man waiting for dress, 2 = Freed woman in dress!
wHasDress:      ds 1 ; 0 = Dress in chest, 1 = Found in chest, 2 = Given to Bob
wInvCursor:     ds 1 ; Selected inventory grid slot (0..7)
wInventory:     ds INV_SLOTS ; 8 inventory slots (0 = empty, 1 = Silk Dress, etc.)
wEnemyX:        ds 9 ; 0 = Evil Terf, 1..8 = 8 Shadow Fiends
wEnemyY:        ds 9
wEnemyAlive:    ds 9
wActiveEnemyID: ds 1
wDialogPage:    ds 1
wBattleCursor:  ds 1
wBattlePhase:   ds 1
wHeroLevel:     ds 1
wHeroXP:        ds 1
wHeroNextXP:    ds 1
wHeroMaxHP:     ds 1
wHeroHP:        ds 1
wHeroATK:       ds 1
wHeroDEF:       ds 1
wMonsterHP:     ds 1
wMonsterATK:    ds 1
wMonsterDEF:    ds 1
wLastDamage:    ds 1
wMusicPlaying:  ds 1
wMusicTempo:    ds 1
wMusicStep:     ds 1
wMusicStepMask: ds 1
wMusicLoop:     ds 1
wMusicTick:     ds 1
wSFXLockTimer:  ds 1
wSFXLockCh4:    ds 1
wMusicCh2Ptr:   ds 2
wMusicCh1Ptr:   ds 2
wMusicCh3Ptr:   ds 2
wMusicCh4Ptr:   ds 2

SECTION "HRAM DMA", HRAM[$FF80]
hOAMDMA:
    ds 16
