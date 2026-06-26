; vera_color_cycle.asm -- 256-color grid with palette cycling, on C64+VERA
;
; Port of examples/vera_color_cycle.m68 (AGFA 68k, internally named
; vera_colorgrid.m68) to 6502 for the C64+VERA cartridge setup. Draws a
; 16x16 grid of 256 filled boxes -- one per palette index 0-255 -- on an
; 8bpp 320x240 bitmap (VERA Layer 0), fades it in, then continuously
; cycles every palette entry's 12-bit RGB value (+1 per step, wrapping)
; for a rotating-rainbow effect until a key is pressed.

!cpu 6510

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
        lda #<c64_msg
        sta ZP_PTR
        lda #>c64_msg
        sta ZP_PTR+1
        jsr kernal_print

        jsr vera_reset
        jsr vera_video_setup
        jsr vera_upload_palette
        jsr save_pal_orig
        jsr fade_to_black

        jsr enter_bitmap_mode
        jsr clear_bitmap
        jsr draw_grid

        jsr fade_up

        lda #<c64_msg_cycle
        sta ZP_PTR
        lda #>c64_msg_cycle
        sta ZP_PTR+1
        jsr kernal_print

        jsr color_cycle_loop

        jsr fade_to_black

        lda #<c64_msg_stopped
        sta ZP_PTR
        lda #>c64_msg_stopped
        sta ZP_PTR+1
        jsr kernal_print

        rts             ; SYS called us like a JSR -- RTS returns to BASIC

; =============================================================================
; ENTER_BITMAP_MODE -- Layer 0: 320x240, 8bpp, bitmap base at VRAM $00000
; =============================================================================
!zone enter_bitmap_mode
enter_bitmap_mode:
        lda #$00
        sta VERA_CTRL           ; DCSEL=0
        lda #$40
        sta VERA_DC_HSCALE      ; 320px wide (vera_video_setup left this at $80=640px)
        lda #$07
        sta VERA_L0_CONFIG
        lda #$00
        sta VERA_L0_MAPBASE
        sta VERA_L0_TILEBASE
        sta VERA_L0_HSCROLL_L
        sta VERA_L0_HSCROLL_H
        sta VERA_L0_VSCROLL_L
        sta VERA_L0_VSCROLL_H
        rts

; =============================================================================
; CLEAR_BITMAP -- zero-fill 76800 bytes (320x240, 1bpp/pixel) from VRAM $00000
; 76800 = 300 * 256: outer loop counts pages (300), inner loop counts bytes
; within a page (256, via 8-bit Y wraparound).
; =============================================================================
!zone clear_bitmap
clear_bitmap:
        lda #$00
        sta VERA_ADDR0_L
        sta VERA_ADDR0_M
        lda #$10                ; bit16=0, stride=+1
        sta VERA_ADDR0_H

        lda #<300
        sta cb_pages
        lda #>300
        sta cb_pages+1
.page:  ldy #$00
.byte:  lda #$00
        sta VERA_DATA0
        iny
        bne .byte

        lda cb_pages
        bne .dec_lo
        dec cb_pages+1
.dec_lo:
        dec cb_pages
        lda cb_pages
        ora cb_pages+1
        bne .page
        rts

; =============================================================================
; DRAW_GRID -- 16x16 grid of filled boxes, one per palette index 0-255.
; col = index & 15, row = index >> 4 (16 is a power of 2 -- no divide needed)
; x1 = 8 + col*19 (lookup table), x2 = x1+17
; y1 = row*15 (lookup table), y2 = y1+13
; =============================================================================
!zone draw_grid
draw_grid:
        lda #$00
        sta grid_index
.box_loop:
        lda grid_index
        and #$0F                 ; col = index mod 16
        tax
        lda col_x1_lo,x
        sta box_x1
        lda col_x1_hi,x
        sta box_x1+1
        lda col_x2_lo,x
        sta box_x2
        lda col_x2_hi,x
        sta box_x2+1

        lda grid_index
        lsr
        lsr
        lsr
        lsr                       ; row = index / 16
        tax
        lda row_y1,x
        sta box_y1
        clc
        adc #13
        sta box_y2

        lda grid_index
        sta box_color

        jsr fill_box

        inc grid_index
        bne .box_loop             ; wraps to 0 after 255 -> loop exits
        rts

; =============================================================================
; FILL_BOX -- fill rows box_y1..box_y2 (inclusive) over columns
; box_x1..box_x2 (inclusive) with box_color, one fill_span call per row.
; =============================================================================
!zone fill_box
fill_box:
        lda box_y1
        sta fb_row
.row_loop:
        lda fb_row
        sta span_y
        jsr fill_span

        lda fb_row
        cmp box_y2
        beq .done
        inc fb_row
        jmp .row_loop
.done:
        rts

; =============================================================================
; FILL_SPAN -- 8bpp linear fill: VERA_ADDR0 = span_y*320 + box_x1 (stride +1),
; write box_color (box_x2-box_x1+1) times.
; span_y*320 computed as (y<<8)+(y<<6) (shift+add, y ranges 0-239).
; Rows >= 205 have y*320 > 65535 so bit16 of the VRAM address must be set;
; fs_bit16 tracks the carry through both 16-bit additions.
; =============================================================================
!zone fill_span
fill_span:
        ; row_base (17-bit) = span_y * 320 = (span_y<<8) + (span_y<<6)
        lda #$00
        sta fs_addr               ; low byte of y<<8 contribution is always 0
        lda span_y
        sta fs_addr+1              ; fs_addr = y<<8

        lda span_y
        sta fs_tmp
        lda #$00
        sta fs_tmp+1
        asl fs_tmp                 ; fs_tmp = y<<1
        rol fs_tmp+1
        asl fs_tmp                 ; y<<2
        rol fs_tmp+1
        asl fs_tmp                 ; y<<3
        rol fs_tmp+1
        asl fs_tmp                 ; y<<4
        rol fs_tmp+1
        asl fs_tmp                 ; y<<5
        rol fs_tmp+1
        asl fs_tmp                 ; y<<6
        rol fs_tmp+1

        lda fs_addr
        clc
        adc fs_tmp
        sta fs_addr
        lda fs_addr+1
        adc fs_tmp+1
        sta fs_addr+1              ; fs_addr = y*320 (low 16 bits)
        lda #$00
        adc #$00
        sta fs_bit16               ; carry out = VRAM bit16 from y*320

        ; address = row_base + box_x1 (box_x1 is 16-bit, up to 310)
        lda fs_addr
        clc
        adc box_x1
        sta fs_addr
        lda fs_addr+1
        adc box_x1+1
        sta fs_addr+1
        lda fs_bit16
        adc #$00
        sta fs_bit16               ; propagate any carry from x1 add into bit16

        lda fs_addr
        sta VERA_ADDR0_L
        lda fs_addr+1
        sta VERA_ADDR0_M
        lda fs_bit16
        ora #$10                   ; stride=+1 in bits 7:4, bit16 in bit 0
        sta VERA_ADDR0_H

        ; count = box_x2 - box_x1 + 1 (fits in a byte: max width 18)
        lda box_x2
        sec
        sbc box_x1
        sta fs_count
        lda box_x2+1
        sbc box_x1+1
        ; high byte of the width difference is always 0 for our boxes;
        ; ignored deliberately (max width is 18, well under 256)
        inc fs_count

        lda box_color
.fill_loop:
        sta VERA_DATA0
        dec fs_count
        bne .fill_loop
        rts

; =============================================================================
; COLOR_CYCLE_LOOP -- until a key is pressed: bump palette_data entries
; 1-255 (12-bit RGB +1, wrapping), reupload via vera_upload_palette.
; Entry 0 (black) is left untouched, matching the AGFA original.
; =============================================================================
!zone color_cycle_loop
color_cycle_loop:
.loop:
        jsr kernal_getin
        cmp #$00
        bne .done

        jsr cycle_palette
        jsr vera_upload_palette

        jmp .loop
.done:
        rts

; =============================================================================
; CYCLE_PALETTE -- entries 1-255: treat the 2 bytes as a 12-bit value
; (byte0 | ((byte1 & $0F) << 8)), add 1, mask to 12 bits, write back.
; =============================================================================
!zone cycle_palette
cycle_palette:
        lda #<(palette_data+2)
        sta ZP_PTR
        lda #>(palette_data+2)
        sta ZP_PTR+1
        ldx #255                  ; entries 1..255
.entry:
        ldy #$00
        lda (ZP_PTR),y            ; byte0
        sta cp_lo
        ldy #$01
        lda (ZP_PTR),y            ; byte1 (top nibble already always 0)
        sta cp_hi

        inc cp_lo
        bne .no_carry
        inc cp_hi
        and #$0F                  ; mask to 12 bits (top nibble stays 0)
        sta cp_hi
.no_carry:

        ldy #$00
        lda cp_lo
        sta (ZP_PTR),y
        ldy #$01
        lda cp_hi
        sta (ZP_PTR),y

        lda ZP_PTR
        clc
        adc #2
        sta ZP_PTR
        bcc .noof
        inc ZP_PTR+1
.noof:
        dex
        beq .done
        jmp .entry                ; loop body > 127 bytes -- BNE can't reach
.done:
        rts

!source "c64/vera_common.inc"

; =============================================================================
; Data
; =============================================================================

; Printed on the C64's screen via KERNAL CHROUT -- the only part of
; this program visible when sanity-testing in VICE.
c64_msg:
        !text "256-COLOR GRID WITH PALETTE CYCLING."
        !byte 13
        !text "SETTING UP VERA 8BPP BITMAP MODE (320X240)."
        !byte 13, 0

c64_msg_cycle:
        !text "256-COLOR GRID WITH PALETTE CYCLING."
        !byte 13
        !text "PRESS ANY KEY TO EXIT."
        !byte 13, 0

c64_msg_stopped:
        !text "STOPPED."
        !byte 13, 0

; --- Grid layout lookup tables (col/row range 0-15; avoids MULU) -----------
; col_x1 = 8 + col*19, col_x2 = col_x1 + 17, row_y1 = row*15
col_x1_lo:
        !byte <8, <27, <46, <65, <84, <103, <122, <141
        !byte <160, <179, <198, <217, <236, <255, <274, <293
col_x1_hi:
        !byte >8, >27, >46, >65, >84, >103, >122, >141
        !byte >160, >179, >198, >217, >236, >255, >274, >293
col_x2_lo:
        !byte <25, <44, <63, <82, <101, <120, <139, <158
        !byte <177, <196, <215, <234, <253, <272, <291, <310
col_x2_hi:
        !byte >25, >44, >63, >82, >101, >120, >139, >158
        !byte >177, >196, >215, >234, >253, >272, >291, >310
row_y1:
        !byte 0, 15, 30, 45, 60, 75, 90, 105
        !byte 120, 135, 150, 165, 180, 195, 210, 225

; --- Working storage ----------------------------------------------------

grid_index: !byte 0     ; 0-255, current box / palette index during draw_grid
box_x1:      !word 0    ; 16-bit: column lookups can exceed 255 (up to 310)
box_x2:      !word 0
box_y1:      !byte 0    ; rows only run 0-239, fits in a byte
box_y2:      !byte 0
box_color:   !byte 0

fb_row:      !byte 0    ; fill_box's current row counter

span_y:      !byte 0    ; fill_span's row argument
fs_addr:     !word 0    ; fill_span's computed VRAM byte address (low 16 bits)
fs_bit16:    !byte 0    ; fill_span's VRAM address bit 16 (rows >= 205 need this)
fs_tmp:      !word 0    ; fill_span's y<<6 scratch
fs_count:    !byte 0    ; fill_span's remaining-bytes counter

cb_pages:    !word 0    ; clear_bitmap's remaining-pages counter (300, 16-bit)

cp_lo:       !byte 0    ; cycle_palette scratch: 12-bit value low byte
cp_hi:       !byte 0    ; cycle_palette scratch: 12-bit value high nibble
