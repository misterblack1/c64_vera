; vera_init_test.asm -- VERA-on-C64 first hardware test
;
; Initializes VERA (at $DE00) in VGA mode at 640x480 / 80x30 text 
; uploads palette + font, configures Layer 0 as a 128x64 1bpp tile
; console, clears it, prints a white-on-black banner, then dumps all 256
; characters of the font.
;

!cpu 6510

; --- Layout constants --------------------------------------------------------

TEXT_ATTR       = $01   ; fg=1 (white) / bg=0 (black) -- palette_data in vera_common.inc
BANNER_ROW      = 2
BANNER_COL      = 8
CHAR_ROW_START  = 5
CHAR_COL_START  = 8
CHAR_PER_ROW    = 64
CHAR_ROWS       = 4     ; 64*4 = 256 = full character set

* = $0801

; BASIC line: 10 SYS2064
!byte $0b, $08          ; pointer to next BASIC line
!byte $0a, $00          ; line number 10
!byte $9e               ; SYS token
!byte $20               ; ' '
!text "2064"            ; ascii digits for the SYS target
!byte $00               ; end of line
!byte $00, $00          ; end of program (next-line pointer = 0)
!byte $00, $00          ; pad up to $0810

start:                  ; = $0810, matches "SYS2064" above
        ldx #$00        ; print status message on the C64's screen first
.msg_loop:
        lda c64_msg,x
        beq .msg_done
        jsr $ffd2       ; KERNAL CHROUT
        inx
        bne .msg_loop
.msg_done:

        sei             ; VERA owns the display now; no KERNAL IRQ needed

        jsr vera_reset
        jsr vera_video_setup
        jsr vera_upload_palette
        jsr vera_upload_font
        jsr vera_layer0_setup
        jsr vera_clear_tilemap

        lda #BANNER_ROW
        ldx #BANNER_COL
        jsr vera_gotoxy
        lda #<str_banner
        sta ZP_PTR
        lda #>str_banner
        sta ZP_PTR+1
        jsr print_str

        jsr char_dump

        cli             ; restore IRQ before handing back to BASIC
        rts             ; SYS called us like a JSR -- RTS returns to BASIC

; =============================================================================
; VERA_UPLOAD_FONT -- 2048 bytes to VRAM $0F000
; =============================================================================
vera_upload_font:
        lda #$00
        sta VERA_ADDR0_L
        lda #$F0
        sta VERA_ADDR0_M
        lda #$10                ; bit16=0, stride=+1
        sta VERA_ADDR0_H
        lda #<font_data
        sta ZP_PTR
        lda #>font_data
        sta ZP_PTR+1
        ldx #8                   ; 8 pages = 2048 bytes
        jsr copy_pages_to_vera
        rts

; =============================================================================
; VERA_LAYER0_SETUP -- 128x64 1bpp tile map @ $00000, tiles @ $0F000
; =============================================================================
vera_layer0_setup:
        lda #$60
        sta VERA_L0_CONFIG
        lda #$00
        sta VERA_L0_MAPBASE
        lda #$78
        sta VERA_L0_TILEBASE
        rts

; =============================================================================
; VERA_CLEAR_TILEMAP -- 8192 (space, attr) entries = 16384 bytes from $00000
; =============================================================================
vera_clear_tilemap:
        lda #$00
        sta VERA_ADDR0_L
        sta VERA_ADDR0_M
        lda #$10
        sta VERA_ADDR0_H
        ldx #32                  ; 32 * 256 = 8192 entries
.outer:
        ldy #$00
.inner: lda #$20                 ; space
        sta VERA_DATA0
        lda #TEXT_ATTR
        sta VERA_DATA0
        iny
        bne .inner
        dex
        bne .outer
        rts

; =============================================================================
; VERA_GOTOXY -- set VERA_ADDR0 to tilemap (row,col), stride=+1
; In: A=row (0-63), X=col (0-127)
; =============================================================================
vera_gotoxy:
        sta VERA_ADDR0_M         ; row*256 -> high byte
        txa
        asl                      ; col*2 -> low byte
        sta VERA_ADDR0_L
        lda #$10
        sta VERA_ADDR0_H
        rts

; =============================================================================
; PRINT_STR -- print NUL-terminated string (ZP_PTR) at current VERA_ADDR0
; =============================================================================
print_str:
        ldy #$00
.loop:  lda (ZP_PTR),y
        beq .done
        sta VERA_DATA0
        lda #TEXT_ATTR
        sta VERA_DATA0
        iny
        bne .loop
.done:  rts

; =============================================================================
; CHAR_DUMP -- print all 256 characters, CHAR_PER_ROW per row, CHAR_ROWS rows
; =============================================================================
char_dump:
        lda #$00
        sta charval
        lda #CHAR_ROW_START
        sta currow
        lda #CHAR_ROWS
        sta rowsleft
.rowloop:
        lda currow
        ldx #CHAR_COL_START
        jsr vera_gotoxy
        ldy #CHAR_PER_ROW
.charloop:
        lda charval
        sta VERA_DATA0
        lda #TEXT_ATTR
        sta VERA_DATA0
        inc charval
        dey
        bne .charloop
        inc currow
        dec rowsleft
        bne .rowloop
        rts

!source "c64/vera_common.inc"

; =============================================================================
; Data
; =============================================================================

; Printed on the C64's screen via KERNAL CHROUT, before VERA setup
; starts -- this is the only part of the program visible in VICE.
c64_msg:
        !text "INITIALIZING THE VERA TO VGA."
        !byte 13
        !text "YOU SHOULD NOW SEE A BLACK SCREEN WITH WHITE TEXT ON THE VERA."
        !byte 13, 0

str_banner:
        !text "VERA on C64 Initialized!"
        !byte 0

charval:  !byte 0   ; current character value during the char dump
currow:   !byte 0   ; current tilemap row during the char dump
rowsleft: !byte 0   ; rows remaining during the char dump

; Font: 2048 bytes (256 chars x 8 bytes, 1bpp), pulled straight from the
; existing AGFA asset -- same VERA font format regardless of host CPU.
font_data:
        !bin "agfa-monitor/vera/font_code437_8x8.bin"
