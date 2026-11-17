; ===========================================================================
; Game Boy Hardware Definitions (DMG)
; ===========================================================================

DEF rJOYP       EQU $FF00 ; Joypad (R/W)
DEF rSB         EQU $FF01 ; Serial transfer data (R/W)
DEF rSC         EQU $FF02 ; Serial Transfer Control (R/W)
DEF rDIV        EQU $FF04 ; Divider Register (R/W)
DEF rTIMA       EQU $FF05 ; Timer counter (R/W)
DEF rTMA        EQU $FF06 ; Timer Modulo (R/W)
DEF rTAC        EQU $FF07 ; Timer Control (R/W)
DEF rIF         EQU $FF0F ; Interrupt Flag (R/W)

DEF rNR10       EQU $FF10 ; Channel 1 Sweep
DEF rNR11       EQU $FF11 ; Channel 1 Sound length/Wave pattern duty
DEF rNR12       EQU $FF12 ; Channel 1 Volume Envelope
DEF rNR13       EQU $FF13 ; Channel 1 Frequency lo
DEF rNR14       EQU $FF14 ; Channel 1 Frequency hi

DEF rNR21       EQU $FF16 ; Channel 2 Sound Length/Wave Pattern Duty
DEF rNR22       EQU $FF17 ; Channel 2 Volume Envelope
DEF rNR23       EQU $FF18 ; Channel 2 Frequency lo data
DEF rNR24       EQU $FF19 ; Channel 2 Frequency hi data

DEF rNR41       EQU $FF20 ; Channel 4 Sound Length
DEF rNR42       EQU $FF21 ; Channel 4 Volume Envelope
DEF rNR43       EQU $FF22 ; Channel 4 Polynomial Counter
DEF rNR44       EQU $FF23 ; Channel 4 Counter/consecutive; Inital

DEF rNR50       EQU $FF24 ; Channel control / ON-OFF / Volume (R/W)
DEF rNR51       EQU $FF25 ; Selection of Sound output terminal (R/W)
DEF rNR52       EQU $FF26 ; Sound on/off

DEF rLCDC       EQU $FF40 ; LCD Control (R/W)
DEF rSTAT       EQU $FF41 ; LCDC Status (R/W)
DEF rSCY        EQU $FF42 ; Scroll Y (R/W)
DEF rSCX        EQU $FF43 ; Scroll X (R/W)
DEF rLY         EQU $FF44 ; LCDC Y-Coordinate (R)
DEF rLYC        EQU $FF45 ; LY Compare (R/W)
DEF rDMA        EQU $FF46 ; DMA Transfer and Start Address (W)
DEF rBGP        EQU $FF47 ; BG Palette Data (R/W) - Non CGB Mode Only
DEF rOBP0       EQU $FF48 ; Object Palette 0 Data (R/W) - Non CGB Mode Only
DEF rOBP1       EQU $FF49 ; Object Palette 1 Data (R/W) - Non CGB Mode Only
DEF rWY         EQU $FF4A ; Window Y Position (R/W)
DEF rWX         EQU $FF4B ; Window X Position minus 7 (R/W)
DEF rIE         EQU $FFFF ; Interrupt Enable (R/W)

; LCDC Flags
DEF LCDCF_OFF       EQU %00000000
DEF LCDCF_ON        EQU %10000000
DEF LCDCF_WIN9800   EQU %00000000
DEF LCDCF_WIN9C00   EQU %01000000
DEF LCDCF_WINOFF    EQU %00000000
DEF LCDCF_WINON     EQU %00100000
DEF LCDCF_BG8800    EQU %00000000
DEF LCDCF_BG8000    EQU %00010000
DEF LCDCF_BG9800    EQU %00000000
DEF LCDCF_BG9C00    EQU %00001000
DEF LCDCF_OBJ8      EQU %00000000
DEF LCDCF_OBJ16     EQU %00000100
DEF LCDCF_OBJOFF    EQU %00000000
DEF LCDCF_OBJON     EQU %00000010
DEF LCDCF_BGOFF     EQU %00000000
DEF LCDCF_BGON      EQU %00000001

; Joypad Bit Masks (1 = pressed after active-low inversion)
DEF PADF_DOWN       EQU $80
DEF PADF_UP         EQU $40
DEF PADF_LEFT       EQU $20
DEF PADF_RIGHT      EQU $10
DEF PADF_START      EQU $08
DEF PADF_SELECT     EQU $04
DEF PADF_B          EQU $02
DEF PADF_A          EQU $01

; VRAM & OAM Addresses
DEF _VRAM           EQU $8000
DEF _SCRN0          EQU $9800
DEF _SCRN1          EQU $9C00
DEF _OAMRAM         EQU $FE00
DEF _HRAM           EQU $FF80
