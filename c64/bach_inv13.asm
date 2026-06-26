; bach_inv13.asm -- Bach Invention No. 13 (BWV 784) on VERA PSG, C64 port
;
!cpu 6510

; --- CIA #1 registers (note timing + keyboard scan) -------------------------
CIA1_PRA  = $DC00   ; Port A -- drive keyboard rows (write $00 = select all)
CIA1_PRB  = $DC01   ; Port B -- read keyboard columns ($FF = no key pressed)
CIA1_TBL  = $DC06   ; Timer B latch lo
CIA1_TBH  = $DC07   ; Timer B latch hi
CIA1_ICR  = $DC0D   ; ICR: read = latched flags (cleared on read), write = mask
CIA1_CRB  = $DC0F   ; Timer B control register

; Timer B tick value: ~100 Hz. C64 phi2 - 1 MHz (NTSC 1022727, PAL 985248).
; 10000 cycles - 10 ms - 100 Hz -- close enough to match AGFA's VIA timing.
CIA1_TB_LO = <10000
CIA1_TB_HI = >10000

; --- PSG ---------------------------------------------------------------------
PSG_VRAM_LO = <$1F9C0
PSG_VRAM_MI = >$1F9C0
; bit16 of $1F9C0 is set (it's > $10000) -- folded into ADDR0_H below.

VERA_AUDIO_CTRL = VERA_BASE+$1B   ; $DE1B

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
        lda #<str_banner
        sta ZP_PTR
        lda #>str_banner
        sta ZP_PTR+1
        jsr kernal_print

        jsr vera_reset
        jsr vera_video_setup

        ; --- VERA text mode: font upload, tilemap clear, banner ---------------
        lda #$00
        sta VERA_CTRL
        lda #$60
        sta VERA_L0_CONFIG      ; 128x64 tilemap, 1bpp tile mode (8x8 chars)
        lda #$00
        sta VERA_L0_MAPBASE     ; tilemap at VRAM $00000
        lda #$78
        sta VERA_L0_TILEBASE    ; font at VRAM $0F000 ($0F000>>11 = $1E, <<2 = $78)
        lda #$00
        sta VERA_L0_HSCROLL_L
        sta VERA_L0_HSCROLL_H
        sta VERA_L0_VSCROLL_L
        sta VERA_L0_VSCROLL_H
        ; upload font (2048 bytes = 8 pages) to VRAM $0F000
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
        ldx #8
        jsr copy_pages_to_vera
        ; clear visible tilemap: 30 rows x 256 bytes each (128 cols x 2 bytes)
        lda #$00
        sta VERA_ADDR0_L
        sta VERA_ADDR0_M
        lda #$10
        sta VERA_ADDR0_H
        jsr vera_clear_tilemap
        ; title: row 10 col 24 -> addr $0A30 (10*256+24*2)
        lda #$30
        sta VERA_ADDR0_L
        lda #$0A
        sta VERA_ADDR0_M
        lda #$10
        sta VERA_ADDR0_H
        lda #<vera_msg_title
        sta ZP_PTR
        lda #>vera_msg_title
        sta ZP_PTR+1
        jsr vera_puts_white
        ; "PLAYING ON VERA PSG": row 12 col 30 -> $0C3C
        lda #$3C
        sta VERA_ADDR0_L
        lda #$0C
        sta VERA_ADDR0_M
        lda #$10
        sta VERA_ADDR0_H
        lda #<vera_msg_playing
        sta ZP_PTR
        lda #>vera_msg_playing
        sta ZP_PTR+1
        jsr vera_puts_white
        ; "PRESS ANY KEY TO STOP": row 13 col 29 -> $0D3A
        lda #$3A
        sta VERA_ADDR0_L
        lda #$0D
        sta VERA_ADDR0_M
        lda #$10
        sta VERA_ADDR0_H
        lda #<vera_msg_stop
        sta ZP_PTR
        lda #>vera_msg_stop
        sta ZP_PTR+1
        jsr vera_puts_white

        ; Enable VERA master audio output. AGFA source: "$4F = FIFO reset +
        ; master vol 15. Without this PSG is silent." Preserved verbatim --
        ; do not simplify to a single write.
        lda #$00
        sta VERA_CTRL
        lda #$4F
        sta VERA_AUDIO_CTRL
        lda #$0F
        sta VERA_AUDIO_CTRL

        ; Init all 4 channels: ch 0,1 = pulse 50%, ch 2,3 = sawtooth
        ldx #$00
        jsr psg_channel_init
        ldx #$01
        jsr psg_channel_init
        ldx #$02
        jsr psg_channel_init
        ldx #$03
        jsr psg_channel_init

        lda #<str_playing
        sta ZP_PTR
        lda #>str_playing
        sta ZP_PTR+1
        jsr kernal_print

        ; Disable KERNAL IRQ for stable note timing. CIA #1 Timer B used
        ; instead of the jiffy clock. SEI here so banner printed above first.
        sei

        ; Configure CIA #1 Timer B: continuous, ~100 Hz, from phi2.
        lda #$00
        sta CIA1_CRB            ; stop Timer B
        lda #CIA1_TB_LO
        sta CIA1_TBL
        lda #CIA1_TB_HI
        sta CIA1_TBH
        lda #$11                ; force load + start, continuous, phi2 input
        sta CIA1_CRB
        lda CIA1_ICR            ; clear any stale underflow flags before first poll

        ; --- main playback loop --------------------------------------------
        ; ZP_PTR walks voice1_table, ZP_PTR2 walks voice2_table -- both are
        ; project zero page (vera_common.inc) since indirect (ZP),Y
        ; addressing requires a zero page pointer. Safe to reuse here: no
        ; kernal_print call happens between here and play_done/abort_play,
        ; where ZP_PTR gets reloaded with a string address before its next use.
        lda #<voice1_table
        sta ZP_PTR
        lda #>voice1_table
        sta ZP_PTR+1
        lda #<voice2_table
        sta ZP_PTR2
        lda #>voice2_table
        sta ZP_PTR2+1
        lda #$00
        sta v1_remain           ; 0 ticks remaining -> advance immediately
        sta v2_remain

!zone main_loop
main_loop:
        ; Direct CIA #1 keyboard scan (no KERNAL needed): write $00 to
        ; Port A (selects all rows), read Port B ($FF = no key pressed).
        lda #$00
        sta CIA1_PRA
        lda CIA1_PRB
        cmp #$FF
        beq .no_key
        jmp abort_play
.no_key:

        ; Voice 1 advance?
        lda v1_remain
        bne .v1_alive
        ldy #$00
        lda (ZP_PTR),y          ; freq hi
        sta v1_freq_hi
        iny
        lda (ZP_PTR),y          ; freq lo
        sta v1_freq_lo
        iny
        iny                     ; skip unused byte
        lda (ZP_PTR),y          ; duration
        sta v1_remain
        ; advance pointer by 4
        lda ZP_PTR
        clc
        adc #4
        sta ZP_PTR
        bcc .v1_noof
        inc ZP_PTR+1
.v1_noof:
        lda v1_remain
        beq .v1_done            ; duration 0 -> end of table, voice 1 stays silent
        ldx #$00
        lda v1_freq_hi
        ldy v1_freq_lo
        jsr psg_set_freq
        ldx #$02
        lda v1_freq_hi
        ldy v1_freq_lo
        jsr psg_set_freq
.v1_alive:
.v1_done:

        ; Voice 2 advance?
        lda v2_remain
        bne .v2_alive
        ldy #$00
        lda (ZP_PTR2),y         ; freq hi
        sta v2_freq_hi
        iny
        lda (ZP_PTR2),y         ; freq lo
        sta v2_freq_lo
        iny
        iny                     ; skip unused byte
        lda (ZP_PTR2),y         ; duration
        sta v2_remain
        lda ZP_PTR2
        clc
        adc #4
        sta ZP_PTR2
        bcc .v2_noof
        inc ZP_PTR2+1
.v2_noof:
        lda v2_remain
        beq .v2_done
        ldx #$01
        lda v2_freq_hi
        ldy v2_freq_lo
        jsr psg_set_freq
        ldx #$03
        lda v2_freq_hi
        ldy v2_freq_lo
        jsr psg_set_freq
.v2_alive:
.v2_done:

        ; Both voices reached end-of-table (duration latched 0) -> done.
        lda v1_remain
        bne .wait_tick
        lda v2_remain
        beq play_done

.wait_tick:
        ; Poll CIA #1 Timer B underflow: bit 1 of ICR ($DC0D). Reading
        ; ICR latches and clears all flags -- loop until bit 1 is set.
.poll:  lda CIA1_ICR
        and #$02
        beq .poll

        lda v1_remain
        beq .skip1
        dec v1_remain
.skip1:
        lda v2_remain
        beq .loop_again
        dec v2_remain
.loop_again:
        jmp main_loop

abort_play:
        jsr psg_mute_all
        lda #$00
        sta CIA1_CRB            ; stop Timer B
        lda #$FF
        sta CIA1_PRA            ; restore keyboard rows for KERNAL
        cli                     ; restore interrupts before returning to BASIC
        lda #<str_stopped
        sta ZP_PTR
        lda #>str_stopped
        sta ZP_PTR+1
        jsr kernal_print
        rts

play_done:
        jsr psg_mute_all
        lda #$00
        sta CIA1_CRB            ; stop Timer B
        lda #$FF
        sta CIA1_PRA            ; restore keyboard rows for KERNAL
        cli                     ; restore interrupts before returning to BASIC
        lda #<str_done
        sta ZP_PTR
        lda #>str_done
        sta ZP_PTR+1
        jsr kernal_print
        rts

; =============================================================================
; PSG_MUTE_ALL -- set freq=0 on channels 0-3 (matches AGFA done: path)
; =============================================================================
!zone psg_mute_all
psg_mute_all:
        ldx #$00
.loop:
        lda #$00
        ldy #$00
        jsr psg_set_freq
        inx
        cpx #$04
        bne .loop
        rts

; =============================================================================
; PSG_CHANNEL_INIT (X=channel 0-3) -- ch 0,1: pulse 50%, ch 2,3: sawtooth,
; freq=0, vol/pan=0 (silent until psg_set_freq turns it on).
; Address = $1F9C0 + channel*4. $1F9C0 already has addr-bit16 set, and
; channel*4 (max 12) never carries into bit 16, so ADDR0_H is always $11
; (bit0=addr-bit16, stride=+1) -- same constant the AGFA source ends up
; using despite computing a per-channel value (the computed value and the
; hardcoded $11 it actually writes are identical in every case that occurs
; here).
; =============================================================================
!zone psg_channel_init
psg_channel_init:
        txa
        asl                     ; channel*4 -- low byte; channel 0-3 so no
        asl                     ; carry out of the low byte is possible
        clc
        adc #PSG_VRAM_LO
        sta VERA_ADDR0_L
        lda #PSG_VRAM_MI
        sta VERA_ADDR0_M
        lda #$11
        sta VERA_ADDR0_H

        lda #$00
        sta VERA_DATA0          ; freq lo = 0
        sta VERA_DATA0          ; freq hi = 0
        sta VERA_DATA0          ; vol/pan = 0 (silent)

        txa
        and #$02
        bne .saw_init
        lda #$20                ; pulse, 50% duty
        sta VERA_DATA0
        rts
.saw_init:
        lda #$7F                ; sawtooth
        sta VERA_DATA0
        rts

; =============================================================================
; PSG_SET_FREQ (X=channel 0-3, A=freq hi, Y=freq lo) -- freq=0 mutes.
; ch 0,2 = left pan, ch 1,3 = right pan. ch 0,1 = pulse, ch 2,3 = sawtooth
; (also halved an octave, matching the AGFA bit-1 test on channel number).
; =============================================================================
!zone psg_set_freq
psg_set_freq:
        sta freq_hi
        sty freq_lo

        txa
        and #$02
        beq .no_octave
        ; halve the 16-bit frequency (octave down) via one right shift
        lsr freq_hi
        ror freq_lo
.no_octave:

        txa
        asl
        asl
        clc
        adc #PSG_VRAM_LO
        sta VERA_ADDR0_L
        lda #PSG_VRAM_MI
        sta VERA_ADDR0_M
        lda #$11
        sta VERA_ADDR0_H

        lda freq_lo
        sta VERA_DATA0
        lda freq_hi
        sta VERA_DATA0

        lda freq_lo
        ora freq_hi
        bne .play
        ; mute
        txa
        and #$01
        bne .right_mute
        lda #$40
        sta VERA_DATA0
        jmp .waveform
.right_mute:
        lda #$80
        sta VERA_DATA0
        jmp .waveform
.play:
        txa
        and #$01
        bne .right_play
        lda #$7F
        sta VERA_DATA0
        jmp .waveform
.right_play:
        lda #$BF
        sta VERA_DATA0
.waveform:
        txa
        and #$02
        bne .saw_pw
        lda #$20
        sta VERA_DATA0
        rts
.saw_pw:
        lda #$7F
        sta VERA_DATA0
        rts

; =============================================================================
; VERA_CLEAR_TILEMAP -- fill 30 rows x 256 bytes with space ($20) / white
; attr ($01) pairs. VERA_ADDR0_* must be set to $00000 stride+1 before calling.
; Inner loop: Y steps 0, 2, 4, ..., 254 (128 pairs = 256 bytes), wraps to 0.
; =============================================================================
!zone vera_clear_tilemap
vera_clear_tilemap:
        ldx #30                  ; 30 visible rows
.page:  ldy #$00
.pair:  lda #$20                 ; space character (CP437)
        sta VERA_DATA0
        lda #$01                 ; white on black attribute
        sta VERA_DATA0
        iny
        iny                      ; Y: 0->2->...->254->0 (128 pairs, then exits)
        bne .pair
        dex
        bne .page
        rts

; =============================================================================
; VERA_PUTS_WHITE -- write NUL-terminated string at ZP_PTR to current
; VERA_ADDR0 position as char+$01 (white on black) pairs.
; =============================================================================
!zone vera_puts_white
vera_puts_white:
        ldy #$00
.loop:  lda (ZP_PTR),y
        beq .done
        sta VERA_DATA0           ; character byte
        lda #$01                 ; white on black attribute
        sta VERA_DATA0
        iny
        bne .loop                ; all banner strings fit in 256 chars
.done:  rts

!source "c64/vera_common.inc"

; =============================================================================
; Data
; =============================================================================

str_banner:
        !text "BACH INVENTION NO. 13 (BWV 784) ON VERA PSG."
        !byte 13, 0

str_playing:
        !text "PLAYING ON VERA PSG (PULSE+SAWTOOTH, L/R STEREO)."
        !byte 13
        !text "PRESS ANY KEY TO STOP."
        !byte 13, 0

str_stopped:
        !byte 13
        !text "STOPPED."
        !byte 13, 0

str_done:
        !byte 13
        !text "PLAYBACK COMPLETE."
        !byte 13, 0

; --- voice playback state ---------------------------------------------------
; (ZP_PTR/ZP_PTR2 -- the table-walking pointers -- live in zero page, see
; vera_common.inc; not declared here.)
v1_remain:     !byte 0        ; jiffies left on voice 1's current note
v2_remain:     !byte 0        ; jiffies left on voice 2's current note
v1_freq_hi:    !byte 0
v1_freq_lo:    !byte 0
v2_freq_hi:    !byte 0
v2_freq_lo:    !byte 0
freq_hi:       !byte 0        ; psg_set_freq scratch
freq_lo:       !byte 0

; --- VERA banner strings (written to tilemap during startup) ------------------
; Row 10 col 24: centered title (31 chars on 80-col display)
vera_msg_title:
        !text "BACH INVENTION NO. 13 (BWV 784)", 0
; Row 12 col 30: 19 chars
vera_msg_playing:
        !text "PLAYING ON VERA PSG", 0
; Row 13 col 29: 21 chars
vera_msg_stop:
        !text "PRESS ANY KEY TO STOP", 0

; --- Code Page 437 font (2048 bytes) uploaded to VRAM $0F000 at startup ------
font_data:
        !bin "agfa-monitor/vera/font_code437_8x8.bin"

; --- voice note tables --------------------------------------------------------
; 4 bytes/note: freq hi, freq lo, unused, duration (in jiffies -- see timing
; note above). Pure data, copied byte-for-byte from the AGFA source.
voice1_table:
        !byte $00,$00,$00,$0f,$03,$75,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $05,$2e,$00,$0f,$03,$75,$00,$0f,$05,$2e,$00,$0f,$06,$29,$00,$0f
        !byte $05,$7d,$00,$1e,$06,$ea,$00,$1e,$04,$5b,$00,$1e,$06,$ea,$00,$1e
        !byte $04,$9d,$00,$0f,$03,$75,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $05,$2e,$00,$0f,$03,$75,$00,$0f,$05,$2e,$00,$0f,$06,$29,$00,$0f
        !byte $05,$7d,$00,$1e,$04,$9d,$00,$1e,$00,$00,$00,$3c,$00,$00,$00,$0f
        !byte $06,$ea,$00,$0f,$05,$7d,$00,$0f,$06,$ea,$00,$0f,$04,$9d,$00,$0f
        !byte $05,$7d,$00,$0f,$03,$75,$00,$0f,$04,$1c,$00,$0f,$03,$a9,$00,$1e
        !byte $04,$9d,$00,$1e,$06,$29,$00,$1e,$07,$53,$00,$2d,$06,$29,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$29,$00,$0f,$04,$1c,$00,$0f,$05,$2e,$00,$0f
        !byte $03,$14,$00,$0f,$03,$a9,$00,$0f,$03,$75,$00,$1e,$04,$1c,$00,$1e
        !byte $05,$7d,$00,$1e,$06,$ea,$00,$2d,$05,$7d,$00,$0f,$04,$9d,$00,$0f
        !byte $05,$7d,$00,$0f,$03,$a9,$00,$1e,$06,$29,$00,$2d,$05,$2e,$00,$0f
        !byte $04,$1c,$00,$0f,$05,$2e,$00,$0f,$03,$75,$00,$1e,$05,$7d,$00,$2d
        !byte $04,$9d,$00,$0f,$03,$a9,$00,$0f,$04,$9d,$00,$0f,$03,$14,$00,$1e
        !byte $05,$2e,$00,$1e,$05,$7d,$00,$1e,$00,$00,$00,$1e,$00,$00,$00,$3c
        !byte $00,$00,$00,$0f,$04,$1c,$00,$0f,$05,$7d,$00,$0f,$06,$ea,$00,$0f
        !byte $06,$29,$00,$0f,$04,$1c,$00,$0f,$06,$29,$00,$0f,$07,$53,$00,$0f
        !byte $06,$ea,$00,$1e,$08,$39,$00,$1e,$05,$2e,$00,$1e,$08,$39,$00,$1e
        !byte $05,$7d,$00,$0f,$04,$1c,$00,$0f,$05,$7d,$00,$0f,$06,$ea,$00,$0f
        !byte $06,$29,$00,$0f,$04,$1c,$00,$0f,$06,$29,$00,$0f,$07,$53,$00,$0f
        !byte $06,$ea,$00,$1e,$05,$7d,$00,$1e,$08,$39,$00,$1e,$06,$ea,$00,$1e
        !byte $0a,$f9,$00,$0f,$09,$3a,$00,$0f,$06,$ea,$00,$0f,$09,$3a,$00,$0f
        !byte $05,$7d,$00,$0f,$06,$ea,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $06,$29,$00,$1e,$07,$c2,$00,$1e,$09,$3a,$00,$1e,$0a,$f9,$00,$1e
        !byte $0a,$5c,$00,$0f,$08,$39,$00,$0f,$06,$29,$00,$0f,$08,$39,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$29,$00,$0f,$04,$1c,$00,$0f,$05,$2e,$00,$0f
        !byte $05,$7d,$00,$1e,$06,$ea,$00,$1e,$08,$39,$00,$1e,$0a,$5c,$00,$1e
        !byte $09,$3a,$00,$0f,$07,$c2,$00,$0f,$06,$86,$00,$0f,$07,$c2,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$86,$00,$0f,$03,$e1,$00,$0f,$04,$9d,$00,$0f
        !byte $04,$1c,$00,$1e,$08,$39,$00,$2d,$06,$ea,$00,$0f,$05,$7d,$00,$0f
        !byte $06,$ea,$00,$0f,$04,$9d,$00,$1e,$07,$c2,$00,$2d,$06,$29,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$29,$00,$0f,$04,$1c,$00,$1e,$06,$ea,$00,$2d
        !byte $05,$7d,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f,$03,$e1,$00,$0f
        !byte $08,$39,$00,$0f,$07,$c2,$00,$0f,$06,$ea,$00,$0f,$06,$86,$00,$0f
        !byte $07,$c2,$00,$0f,$05,$2e,$00,$0f,$06,$86,$00,$0f,$06,$ea,$00,$1e
        !byte $00,$00,$00,$1e,$00,$00,$00,$3c,$00,$00,$00,$0f,$08,$39,$00,$0f
        !byte $09,$c7,$00,$0f,$08,$39,$00,$0f,$06,$ea,$00,$0f,$08,$39,$00,$0f
        !byte $05,$d0,$00,$0f,$06,$ea,$00,$0f,$08,$39,$00,$0f,$06,$ea,$00,$0f
        !byte $05,$d0,$00,$0f,$06,$ea,$00,$0f,$04,$9d,$00,$0f,$00,$00,$00,$0f
        !byte $00,$00,$00,$1e,$00,$00,$00,$0f,$07,$53,$00,$0f,$09,$3a,$00,$0f
        !byte $07,$53,$00,$0f,$06,$29,$00,$0f,$07,$53,$00,$0f,$05,$2e,$00,$0f
        !byte $06,$29,$00,$0f,$07,$53,$00,$0f,$06,$29,$00,$0f,$05,$2e,$00,$0f
        !byte $06,$29,$00,$0f,$04,$1c,$00,$0f,$00,$00,$00,$0f,$00,$00,$00,$1e
        !byte $00,$00,$00,$0f,$06,$ea,$00,$0f,$08,$39,$00,$0f,$06,$ea,$00,$0f
        !byte $05,$7d,$00,$0f,$06,$ea,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $06,$86,$00,$0f,$05,$7d,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $03,$e1,$00,$0f,$00,$00,$00,$0f,$00,$00,$00,$1e,$00,$00,$00,$0f
        !byte $06,$29,$00,$0f,$07,$53,$00,$0f,$06,$29,$00,$0f,$05,$2e,$00,$0f
        !byte $06,$29,$00,$0f,$04,$5b,$00,$0f,$05,$2e,$00,$0f,$06,$29,$00,$0f
        !byte $05,$2e,$00,$0f,$04,$5b,$00,$0f,$05,$2e,$00,$0f,$03,$75,$00,$0f
        !byte $00,$00,$00,$0f,$00,$00,$00,$1e,$00,$00,$00,$0f,$03,$75,$00,$0f
        !byte $04,$9d,$00,$0f,$05,$7d,$00,$0f,$05,$2e,$00,$0f,$03,$75,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$29,$00,$0f,$05,$7d,$00,$1e,$04,$9d,$00,$1e
        !byte $04,$5b,$00,$1e,$03,$75,$00,$1e,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $06,$ea,$00,$0f,$05,$7d,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f
        !byte $03,$e1,$00,$0f,$04,$9d,$00,$0f,$05,$7d,$00,$0f,$04,$9d,$00,$0f
        !byte $03,$e1,$00,$0f,$04,$9d,$00,$0f,$03,$43,$00,$0f,$05,$7d,$00,$0f
        !byte $05,$2e,$00,$0f,$04,$9d,$00,$0f,$04,$5b,$00,$0f,$05,$2e,$00,$0f
        !byte $06,$29,$00,$0f,$05,$2e,$00,$0f,$04,$5b,$00,$0f,$05,$2e,$00,$0f
        !byte $03,$14,$00,$0f,$03,$a9,$00,$0f,$04,$5b,$00,$0f,$03,$a9,$00,$0f
        !byte $03,$14,$00,$0f,$03,$a9,$00,$0f,$02,$97,$00,$0f,$03,$a9,$00,$0f
        !byte $03,$75,$00,$0f,$03,$14,$00,$0f,$02,$be,$00,$0f,$03,$75,$00,$0f
        !byte $04,$9d,$00,$0f,$03,$75,$00,$0f,$02,$be,$00,$0f,$03,$75,$00,$0f
        !byte $02,$4f,$00,$0f,$02,$be,$00,$0f,$03,$43,$00,$0f,$02,$be,$00,$0f
        !byte $02,$4f,$00,$0f,$02,$be,$00,$0f,$01,$f1,$00,$0f,$02,$be,$00,$0f
        !byte $02,$97,$00,$0f,$02,$4f,$00,$0f,$02,$2d,$00,$1e,$05,$2e,$00,$1e
        !byte $04,$5b,$00,$1e,$03,$75,$00,$1e,$00,$00,$00,$0f,$03,$75,$00,$0f
        !byte $04,$9d,$00,$0f,$05,$7d,$00,$0f,$05,$2e,$00,$0f,$03,$75,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$29,$00,$0f,$05,$7d,$00,$0f,$04,$9d,$00,$0f
        !byte $05,$7d,$00,$0f,$06,$ea,$00,$0f,$06,$29,$00,$0f,$05,$2e,$00,$0f
        !byte $06,$29,$00,$0f,$07,$53,$00,$0f,$06,$ea,$00,$0f,$05,$7d,$00,$0f
        !byte $06,$ea,$00,$0f,$08,$39,$00,$0f,$07,$53,$00,$0f,$06,$ea,$00,$0f
        !byte $06,$29,$00,$0f,$05,$7d,$00,$0f,$05,$2e,$00,$0f,$05,$7d,$00,$0f
        !byte $06,$29,$00,$0f,$06,$ea,$00,$0f,$07,$53,$00,$0f,$06,$29,$00,$0f
        !byte $08,$b6,$00,$0f,$06,$29,$00,$0f,$0a,$5c,$00,$0f,$06,$29,$00,$0f
        !byte $05,$7d,$00,$0f,$09,$3a,$00,$0f,$07,$53,$00,$0f,$06,$29,$00,$0f
        !byte $05,$2e,$00,$0f,$06,$29,$00,$0f,$04,$5b,$00,$0f,$05,$2e,$00,$0f
        !byte $05,$7d,$00,$0f,$04,$9d,$00,$0f,$03,$75,$00,$0f,$04,$9d,$00,$0f
        !byte $05,$2e,$00,$0f,$04,$5b,$00,$0f,$04,$9d,$00,$0f,$03,$75,$00,$0f
        !byte $02,$be,$00,$0f,$03,$75,$00,$0f,$02,$4f,$00,$3c,$00,$00,$00,$00

voice2_table:
        !byte $01,$27,$00,$1e,$02,$4f,$00,$3c,$02,$2d,$00,$1e,$02,$4f,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$4f,$00,$0f,$02,$be,$00,$0f,$02,$97,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$97,$00,$0f,$03,$14,$00,$0f,$02,$be,$00,$1e
        !byte $02,$4f,$00,$1e,$02,$2d,$00,$1e,$01,$ba,$00,$1e,$02,$4f,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$4f,$00,$0f,$02,$be,$00,$0f,$02,$97,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$97,$00,$0f,$03,$14,$00,$0f,$02,$be,$00,$1e
        !byte $02,$4f,$00,$1e,$02,$be,$00,$1e,$02,$4f,$00,$1e,$03,$14,$00,$0f
        !byte $02,$4f,$00,$0f,$01,$d5,$00,$0f,$02,$4f,$00,$0f,$01,$8a,$00,$0f
        !byte $01,$d5,$00,$0f,$01,$27,$00,$0f,$01,$5f,$00,$0f,$01,$4b,$00,$1e
        !byte $01,$8a,$00,$1e,$02,$0e,$00,$1e,$02,$97,$00,$2d,$02,$0e,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$0e,$00,$0f,$01,$5f,$00,$0f,$01,$ba,$00,$0f
        !byte $01,$07,$00,$0f,$01,$4b,$00,$0f,$01,$27,$00,$1e,$01,$5f,$00,$1e
        !byte $01,$8a,$00,$0f,$01,$d5,$00,$0f,$01,$4b,$00,$0f,$01,$8a,$00,$0f
        !byte $01,$07,$00,$1e,$01,$4b,$00,$1e,$01,$5f,$00,$0f,$01,$ba,$00,$0f
        !byte $01,$27,$00,$0f,$01,$5f,$00,$0f,$00,$ea,$00,$1e,$00,$c5,$00,$1e
        !byte $01,$07,$00,$0f,$02,$0e,$00,$0f,$01,$d5,$00,$0f,$02,$0e,$00,$0f
        !byte $01,$5f,$00,$0f,$02,$0e,$00,$0f,$02,$be,$00,$0f,$03,$75,$00,$0f
        !byte $03,$14,$00,$0f,$02,$0e,$00,$0f,$03,$14,$00,$0f,$03,$a9,$00,$0f
        !byte $03,$75,$00,$1e,$02,$be,$00,$1e,$02,$97,$00,$1e,$02,$0e,$00,$1e
        !byte $02,$be,$00,$0f,$02,$0e,$00,$0f,$02,$be,$00,$0f,$03,$75,$00,$0f
        !byte $03,$14,$00,$0f,$02,$0e,$00,$0f,$03,$14,$00,$0f,$03,$a9,$00,$0f
        !byte $03,$75,$00,$1e,$02,$be,$00,$1e,$00,$00,$00,$3c,$00,$00,$00,$0f
        !byte $04,$1c,$00,$0f,$03,$75,$00,$0f,$04,$1c,$00,$0f,$02,$be,$00,$0f
        !byte $03,$75,$00,$0f,$02,$0e,$00,$0f,$02,$97,$00,$0f,$02,$4f,$00,$1e
        !byte $02,$be,$00,$1e,$03,$75,$00,$1e,$04,$1c,$00,$1e,$03,$e1,$00,$0f
        !byte $04,$9d,$00,$0f,$03,$14,$00,$0f,$03,$e1,$00,$0f,$02,$4f,$00,$0f
        !byte $03,$14,$00,$0f,$01,$f1,$00,$0f,$02,$4f,$00,$0f,$02,$0e,$00,$1e
        !byte $02,$97,$00,$1e,$03,$14,$00,$1e,$03,$e1,$00,$1e,$03,$75,$00,$0f
        !byte $04,$1c,$00,$0f,$02,$be,$00,$0f,$03,$75,$00,$0f,$02,$0e,$00,$0f
        !byte $02,$be,$00,$0f,$01,$ba,$00,$0f,$02,$0e,$00,$0f,$01,$f1,$00,$1e
        !byte $02,$4f,$00,$1e,$02,$97,$00,$1e,$03,$43,$00,$1e,$00,$00,$00,$0f
        !byte $03,$75,$00,$0f,$02,$be,$00,$0f,$03,$75,$00,$0f,$02,$4f,$00,$0f
        !byte $02,$be,$00,$0f,$03,$75,$00,$0f,$04,$1c,$00,$0f,$03,$e1,$00,$0f
        !byte $03,$14,$00,$0f,$02,$97,$00,$0f,$03,$14,$00,$0f,$02,$0e,$00,$0f
        !byte $02,$97,$00,$0f,$03,$14,$00,$0f,$03,$e1,$00,$0f,$03,$75,$00,$0f
        !byte $02,$be,$00,$0f,$02,$4f,$00,$0f,$02,$be,$00,$0f,$01,$f1,$00,$0f
        !byte $02,$4f,$00,$0f,$02,$be,$00,$2d,$02,$97,$00,$0f,$02,$be,$00,$0f
        !byte $02,$4f,$00,$0f,$02,$97,$00,$1e,$01,$4b,$00,$1e,$01,$ba,$00,$0f
        !byte $03,$75,$00,$0f,$02,$97,$00,$0f,$02,$0e,$00,$0f,$01,$ba,$00,$0f
        !byte $01,$4b,$00,$0f,$01,$07,$00,$0f,$01,$4b,$00,$0f,$00,$dd,$00,$1e
        !byte $01,$ba,$00,$1e,$02,$0e,$00,$1e,$02,$72,$00,$1e,$01,$74,$00,$1e
        !byte $00,$00,$00,$1e,$00,$00,$00,$0f,$04,$1c,$00,$0f,$03,$a9,$00,$0f
        !byte $03,$75,$00,$0f,$03,$14,$00,$1e,$01,$8a,$00,$1e,$01,$d5,$00,$1e
        !byte $02,$2d,$00,$1e,$01,$4b,$00,$1e,$00,$00,$00,$1e,$00,$00,$00,$0f
        !byte $03,$a9,$00,$0f,$03,$75,$00,$0f,$03,$14,$00,$0f,$02,$be,$00,$1e
        !byte $01,$5f,$00,$1e,$01,$ba,$00,$1e,$01,$f1,$00,$1e,$01,$27,$00,$1e
        !byte $00,$00,$00,$1e,$00,$00,$00,$0f,$03,$75,$00,$0f,$03,$43,$00,$0f
        !byte $02,$e8,$00,$0f,$02,$97,$00,$1e,$01,$4b,$00,$1e,$01,$8a,$00,$1e
        !byte $01,$d5,$00,$1e,$01,$17,$00,$1e,$00,$00,$00,$1e,$00,$00,$00,$0f
        !byte $03,$14,$00,$0f,$02,$be,$00,$0f,$02,$97,$00,$0f,$02,$be,$00,$1e
        !byte $02,$4f,$00,$1e,$02,$2d,$00,$1e,$01,$ba,$00,$1e,$02,$4f,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$4f,$00,$0f,$02,$be,$00,$0f,$02,$97,$00,$0f
        !byte $01,$ba,$00,$0f,$02,$97,$00,$0f,$03,$14,$00,$0f,$02,$be,$00,$0f
        !byte $03,$75,$00,$0f,$04,$9d,$00,$0f,$03,$75,$00,$0f,$02,$be,$00,$0f
        !byte $03,$75,$00,$0f,$02,$4f,$00,$0f,$02,$be,$00,$0f,$01,$f1,$00,$0f
        !byte $02,$4f,$00,$0f,$02,$be,$00,$0f,$02,$4f,$00,$0f,$01,$f1,$00,$0f
        !byte $02,$4f,$00,$0f,$01,$a2,$00,$0f,$01,$f1,$00,$0f,$01,$ba,$00,$1e
        !byte $02,$2d,$00,$1e,$02,$97,$00,$1e,$02,$2d,$00,$1e,$01,$ba,$00,$1e
        !byte $01,$4b,$00,$1e,$01,$17,$00,$1e,$00,$dd,$00,$1e,$01,$27,$00,$1e
        !byte $01,$5f,$00,$1e,$01,$ba,$00,$1e,$01,$5f,$00,$1e,$01,$27,$00,$1e
        !byte $01,$5f,$00,$1e,$00,$d1,$00,$1e,$00,$00,$00,$1e,$00,$00,$00,$0f
        !byte $02,$97,$00,$0f,$02,$2d,$00,$0f,$01,$ba,$00,$0f,$01,$8a,$00,$0f
        !byte $02,$97,$00,$0f,$02,$2d,$00,$0f,$01,$8a,$00,$0f,$01,$5f,$00,$1e
        !byte $01,$ba,$00,$1e,$01,$17,$00,$1e,$01,$ba,$00,$1e,$01,$27,$00,$1e
        !byte $01,$f1,$00,$1e,$01,$4b,$00,$1e,$02,$2d,$00,$1e,$01,$5f,$00,$1e
        !byte $02,$4f,$00,$1e,$01,$8a,$00,$1e,$02,$72,$00,$1e,$02,$2d,$00,$1e
        !byte $01,$d5,$00,$1e,$01,$8a,$00,$1e,$01,$4b,$00,$1e,$01,$17,$00,$1e
        !byte $01,$27,$00,$1e,$00,$c5,$00,$1e,$00,$dd,$00,$1e,$00,$ea,$00,$1e
        !byte $00,$d1,$00,$1e,$00,$dd,$00,$1e,$01,$ba,$00,$1e,$01,$27,$00,$78
        !byte $00,$00,$00,$00
