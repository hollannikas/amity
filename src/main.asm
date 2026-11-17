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
    call WaitVBlank
    ; Run OAM DMA during VBlank
    call hOAMDMA

    ; Increment global frame counter
    ld hl, wFrameCounter
    inc [hl]

    ; Read Joypad
    call ReadJoypad

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
    db 184 ; 8: Shadow Fiend #8 (Southeast Riverbank)

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
    call DisableLCD
    call ClearShadowOAM

    ; Load Selected Character's 4-Directional Sprite Bank (32 tiles = $D0..$EF) into VRAM $8D00
    call LoadSelectedPlayerSprites

    ; Load Custom Sprite 0 ($F0..$F3) into VRAM $8F00 and extensible MapMetatilesData into VRAM $8800 ($80..$CF)
    ld hl, CustomSpritesTiles
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

    ; Check NPC Interaction:
    ; If player is near NPC Materia (|PlayerX - NPCX| < 20 and |PlayerY - NPCY| < 20)
    ; and presses A (or touches NPC directly within 12px), open the Aretha II Portrait Dialogue!
    call CheckNPCInteraction
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

.startTerfBattleFromDialog:
    call StartBattleTransition
    ret

.closeDialog:
    ; Return to scrolling 2.5D Overworld Map
    call EnterOverworldMap
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
    call PlaySFXConfirm
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

    call PlaySFXLevelUp
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

    ; Play sad descending Game Over tone
    call PlaySFXGameOver

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
    jr nc, .renderEnemies
    add 16
    ld [wSpriteY], a

    ld a, [wCameraX]
    ld c, a
    ld a, [wNPCWorldX]
    sub c
    cp 160
    jr nc, .renderEnemies
    add 8
    ld [wSpriteX], a

    ld a, $F8 ; NPC Gaius Overworld tile
    ld [wSpriteTile], a
    ld a, 4
    call SetMetaSprite16x16

.renderEnemies:
    ; Render up to 8 visible Enemies into OAM slots 8..39 (4 OAM entries per 16x16 enemy)
    ; Index 0 = EVIL TERF ($F4), Indices 1..8 = 8 SHADOW FIENDS ($FC)
    ld c, 0 ; Enemy index 0..8
    ld b, 8 ; Next OAM slot (8, 12, 16, 20, 24, 28, 32, 36)
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
    db 2,0,0,0, 0,0,0,1, 1,0,0,0, 0,0,0,2 ; Row 13: South Bank
    db 2,2,0,2, 0,0,1,1, 1,1,0,0, 2,0,2,2 ; Row 14: Southern Woods
    db 2,2,2,2, 2,2,2,2, 2,2,2,2, 2,2,2,2 ; Row 15: Southern Border Trees


; ===========================================================================
; Sound Effects (DMG Pulse Channel 1)
; ===========================================================================
PlaySFXCursor:
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

SECTION "HRAM DMA", HRAM[$FF80]
hOAMDMA:
    ds 16
