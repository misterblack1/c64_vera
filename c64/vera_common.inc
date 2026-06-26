; vera_common.inc -- Shared VERA + KERNAL helpers for C64 VERA programs
; --- VERA registers ($DE00 = standard C64 cartridge I/O1 block) -------------

VERA_BASE        = $DE00
VERA_ADDR0_L     = VERA_BASE+$00
VERA_ADDR0_M     = VERA_BASE+$01
VERA_ADDR0_H     = VERA_BASE+$02
VERA_DATA0       = VERA_BASE+$03
VERA_CTRL        = VERA_BASE+$05

; DCSEL=0 bank
VERA_DC_VIDEO    = VERA_BASE+$09
VERA_DC_HSCALE   = VERA_BASE+$0A
VERA_DC_VSCALE   = VERA_BASE+$0B
VERA_DC_BORDER   = VERA_BASE+$0C

; DCSEL=1 bank -- same addresses as above, different meaning
VERA_DC_HSTART   = VERA_BASE+$09
VERA_DC_HSTOP    = VERA_BASE+$0A
VERA_DC_VSTART   = VERA_BASE+$0B
VERA_DC_VSTOP    = VERA_BASE+$0C

VERA_L0_CONFIG     = VERA_BASE+$0D
VERA_L0_MAPBASE    = VERA_BASE+$0E
VERA_L0_TILEBASE   = VERA_BASE+$0F
VERA_L0_HSCROLL_L  = VERA_BASE+$10
VERA_L0_HSCROLL_H  = VERA_BASE+$11
VERA_L0_VSCROLL_L  = VERA_BASE+$12
VERA_L0_VSCROLL_H  = VERA_BASE+$13

; --- Zero page ----------------------------------------------------------------

ZP_PTR    = $FB   ; 2 bytes: indirect-addressing pointer (copy/print/fade)
ZP_PTR2   = $FD   ; 2 bytes: second indirect pointer, used only by fade_up

; =============================================================================
; VERA_RESET -- soft reset (CTRL bit7 pulse), settle delay either side
; =============================================================================
!zone vera_reset
vera_reset:
        lda #$80
        sta VERA_CTRL
        jsr vc_delay
        lda #$00
        sta VERA_CTRL
        jsr vc_delay
        rts

; Busy-wait only -- for the VERA reset settle time. NOT for animation
; pacing; use the KERNAL jiffy clock (RDTIM, $FFDE) for that instead.
!zone vc_delay
vc_delay:
        ldx #$00
        ldy #$00
.dloop: iny
        bne .dloop
        inx
        bne .dloop
        rts

; =============================================================================
; VERA_VIDEO_SETUP -- DCSEL=0 video/scale/border, DCSEL=1 full active area
; Hardcoded 640x480 VGA / 80x30 text grid (documented AGFA factory default).
; =============================================================================
!zone vera_video_setup
vera_video_setup:
        lda #$00
        sta VERA_CTRL           ; DCSEL=0, ADDRSEL=0
        lda #$80
        sta VERA_DC_HSCALE      ; 128 = 1:1 horizontal
        lda #$40
        sta VERA_DC_VSCALE      ; 64 = 2x vertical -> 80x30 text grid
        lda #$00
        sta VERA_DC_BORDER
        lda #$91                ; documented AGFA VGA preset (nvram_config.inc:37)
        sta VERA_DC_VIDEO

        lda #$02
        sta VERA_CTRL           ; DCSEL=1
        lda #$00
        sta VERA_DC_HSTART
        lda #160
        sta VERA_DC_HSTOP       ; 160*4 = 640px
        lda #$00
        sta VERA_DC_VSTART
        lda #240
        sta VERA_DC_VSTOP       ; 240*2 = 480px

        lda #$00
        sta VERA_CTRL           ; back to DCSEL=0/ADDRSEL=0 for everything else
        rts

; =============================================================================
; COPY_PAGES_TO_VERA -- copies (X * 256) bytes from ZP_PTR to VERA_DATA0
; ZP_PTR auto-advances. Caller must set VERA_ADDR0_L/M/H first.
; =============================================================================
!zone copy_pages_to_vera
copy_pages_to_vera:
        ldy #$00
.byteloop:
        lda (ZP_PTR),y
        sta VERA_DATA0
        iny
        bne .byteloop
        inc ZP_PTR+1
        dex
        bne copy_pages_to_vera
        rts

; =============================================================================
; VERA_UPLOAD_PALETTE -- 512 bytes (palette_data below) to VRAM $1FA00
; =============================================================================
!zone vera_upload_palette
vera_upload_palette:
        lda #$00
        sta VERA_ADDR0_L
        lda #$FA
        sta VERA_ADDR0_M
        lda #$11                ; bit0=addr bit16, stride=+1
        sta VERA_ADDR0_H
        lda #<palette_data
        sta ZP_PTR
        lda #>palette_data
        sta ZP_PTR+1
        ldx #2                   ; 2 pages = 512 bytes
        jsr copy_pages_to_vera
        rts

; =============================================================================
; SAVE_PAL_ORIG -- copy palette_data -> pal_orig (call once before fading,
; so fade_up has an undamaged target to fade back up to).
; =============================================================================
!zone save_pal_orig
save_pal_orig:
        lda #<palette_data
        sta ZP_PTR
        lda #>palette_data
        sta ZP_PTR+1
        lda #<pal_orig
        sta ZP_PTR2
        lda #>pal_orig
        sta ZP_PTR2+1
        ldx #2                   ; 2 pages = 512 bytes
.page:  ldy #$00
.byte:  lda (ZP_PTR),y
        sta (ZP_PTR2),y          ; use indirect so dest page advances too
        iny
        bne .byte
        inc ZP_PTR+1
        inc ZP_PTR2+1
        dex
        bne .page
        rts

; =============================================================================
; FADE_TO_BLACK / FADE_UP -- 16 steps, mutating palette_data in place and
; uploading it to VERA after every step. 
;
; The outer 16-step counter uses a memory byte (fade_steps_left), not X --
; fade_to_black_1/fade_up_1 (and copy_pages_to_vera, which they call into
; via vera_upload_palette) always return with X=0, since their own inner
; loops only exit when X hits 0. An earlier version used `ldx #16` here
; and decremented X after the JSR, which never worked: X was always 0 on
; return, so `dex` always produced $FF, and the loop never terminated.
; If you add another routine with an outer "call this N times" loop
; around something that uses X internally, use a memory counter, not X.
; =============================================================================
!zone fade_to_black
fade_to_black:
        lda #16
        sta fade_steps_left
.fb_step:
        jsr fade_to_black_1
        dec fade_steps_left
        bne .fb_step
        rts

fade_to_black_1:
        lda #<(palette_data+2)
        sta ZP_PTR
        lda #>(palette_data+2)
        sta ZP_PTR+1
        ldx #255                 ; entries 1..255
.fb_entry:
        ldy #$00
        lda (ZP_PTR),y          ; byte0 = [G|B]
        sta pal_tmp0
        ldy #$01
        lda (ZP_PTR),y          ; byte1 = [-|R]
        sta pal_tmp1

        lda pal_tmp0
        and #$0F                ; blue
        beq .b_done
        sec
        sbc #1
.b_done: sta pal_tmp2

        lda pal_tmp0
        lsr
        lsr
        lsr
        lsr                     ; green
        beq .g_done
        sec
        sbc #1
.g_done: sta pal_tmp3

        lda pal_tmp1
        and #$0F                ; red
        beq .r_done
        sec
        sbc #1
.r_done: sta pal_tmp4

        lda pal_tmp3
        asl
        asl
        asl
        asl
        ora pal_tmp2
        ldy #$00
        sta (ZP_PTR),y
        lda pal_tmp4
        ldy #$01
        sta (ZP_PTR),y

        lda ZP_PTR
        clc
        adc #2
        sta ZP_PTR
        bcc .noof
        inc ZP_PTR+1
.noof:
        dex
        bne .fb_entry

        jsr vera_upload_palette
        rts

!zone fade_up
fade_up:
        lda #16
        sta fade_steps_left
.fu_step:
        jsr fade_up_1
        dec fade_steps_left
        bne .fu_step
        rts

fade_up_1:
        lda #<(palette_data+2)
        sta ZP_PTR
        lda #>(palette_data+2)
        sta ZP_PTR+1
        lda #<(pal_orig+2)
        sta ZP_PTR2
        lda #>(pal_orig+2)
        sta ZP_PTR2+1
        ldx #255
.fu_entry:
        ldy #$00
        lda (ZP_PTR),y
        sta pal_tmp0             ; current byte0
        lda (ZP_PTR2),y
        sta pal_tmp1             ; target byte0
        ldy #$01
        lda (ZP_PTR),y
        sta pal_tmp5             ; current byte1
        lda (ZP_PTR2),y
        sta pal_tmp6             ; target byte1

        lda pal_tmp0
        and #$0F
        sta pal_tmp2             ; current blue
        lda pal_tmp1
        and #$0F
        cmp pal_tmp2
        beq .b_ok
        bcc .b_ok                ; target <= current -> already there
        inc pal_tmp2
.b_ok:

        lda pal_tmp0
        lsr
        lsr
        lsr
        lsr
        sta pal_tmp3             ; current green
        lda pal_tmp1
        lsr
        lsr
        lsr
        lsr
        cmp pal_tmp3
        beq .g_ok
        bcc .g_ok
        inc pal_tmp3
.g_ok:

        lda pal_tmp5
        and #$0F
        sta pal_tmp4             ; current red
        lda pal_tmp6
        and #$0F
        cmp pal_tmp4
        beq .r_ok
        bcc .r_ok
        inc pal_tmp4
.r_ok:

        lda pal_tmp3
        asl
        asl
        asl
        asl
        ora pal_tmp2
        ldy #$00
        sta (ZP_PTR),y
        lda pal_tmp4
        ldy #$01
        sta (ZP_PTR),y

        lda ZP_PTR
        clc
        adc #2
        sta ZP_PTR
        bcc .noof1
        inc ZP_PTR+1
.noof1:
        lda ZP_PTR2
        clc
        adc #2
        sta ZP_PTR2
        bcc .noof2
        inc ZP_PTR2+1
.noof2:
        dex
        beq .fu_loop_done
        jmp .fu_entry            ; BNE can't reach -- loop body > 127 bytes
.fu_loop_done:

        jsr vera_upload_palette
        rts

; =============================================================================
; KERNAL_PRINT -- print NUL-terminated string (ZP_PTR) via KERNAL CHROUT.
; Prints on the C64's screen (always visible, VICE included).
; Prints on the C64's screen (always visible, VICE included).
; =============================================================================
!zone kernal_print
kernal_print:
        ldy #$00
.loop:  lda (ZP_PTR),y
        beq .done
        jsr $ffd2               ; KERNAL CHROUT
        iny
        bne .loop
.done:  rts

; =============================================================================
; KERNAL_GETIN -- non-blocking keypress check. A=0 if no key waiting,
; else A=key code (and it's consumed from the keyboard buffer).
; =============================================================================
kernal_getin:
        jsr $ffe4               ; KERNAL GETIN
        rts

; =============================================================================
; Data
; =============================================================================

; Palette: 256 entries x 2 bytes, copied verbatim from
; agfa-monitor/vera/palette.inc (VI_PAL_DATA). Pure data -- CPU-independent.
; Entry 0 = black, entry 1 = white.
palette_data:
    !byte $00,$00,$FF,$0F,$00,$08,$FE,$0A,$4C,$0C,$C5,$00,$0A,$00,$E7,$0E,$85,$0D,$40,$06,$77,$0F,$33,$03,$77,$07,$F6,$0A,$8F,$00,$BB,$0B
    !byte $00,$00,$11,$01,$22,$02,$33,$03,$44,$04,$55,$05,$66,$06,$77,$07,$88,$08,$99,$09,$AA,$0A,$BB,$0B,$CC,$0C,$DD,$0D,$EE,$0E,$FF,$0F
    !byte $11,$02,$33,$04,$44,$06,$66,$08,$88,$0A,$99,$0C,$BB,$0F,$11,$02,$22,$04,$33,$06,$44,$08,$55,$0A,$66,$0C,$77,$0F,$00,$02,$11,$04
    !byte $11,$06,$22,$08,$22,$0A,$33,$0C,$33,$0F,$00,$02,$00,$04,$00,$06,$00,$08,$00,$0A,$00,$0C,$00,$0F,$21,$02,$43,$04,$64,$06,$86,$08
    !byte $A8,$0A,$C9,$0C,$EB,$0F,$11,$02,$32,$04,$53,$06,$74,$08,$95,$0A,$B6,$0C,$D7,$0F,$10,$02,$31,$04,$51,$06,$62,$08,$82,$0A,$A3,$0C
    !byte $C3,$0F,$10,$02,$30,$04,$40,$06,$60,$08,$80,$0A,$90,$0C,$B0,$0F,$21,$01,$43,$03,$64,$05,$86,$07,$A8,$09,$C9,$0B,$FB,$0D,$21,$01
    !byte $42,$03,$63,$04,$84,$06,$A5,$08,$C6,$09,$F7,$0B,$20,$01,$41,$02,$61,$04,$82,$05,$A2,$06,$C3,$08,$F3,$09,$20,$01,$40,$02,$60,$03
    !byte $80,$04,$A0,$05,$C0,$06,$F0,$07,$21,$01,$43,$03,$65,$04,$86,$06,$A8,$08,$CA,$09,$FC,$0B,$21,$01,$42,$02,$64,$03,$85,$04,$A6,$05
    !byte $C8,$06,$F9,$07,$20,$00,$41,$01,$62,$01,$83,$02,$A4,$02,$C5,$03,$F6,$03,$20,$00,$41,$00,$61,$00,$82,$00,$A2,$00,$C3,$00,$F3,$00
    !byte $22,$01,$44,$03,$66,$04,$88,$06,$AA,$08,$CC,$09,$FF,$0B,$22,$01,$44,$02,$66,$03,$88,$04,$AA,$05,$CC,$06,$FF,$07,$22,$00,$44,$01
    !byte $66,$01,$88,$02,$AA,$02,$CC,$03,$FF,$03,$22,$00,$44,$00,$66,$00,$88,$00,$AA,$00,$CC,$00,$FF,$00,$12,$01,$34,$03,$56,$04,$68,$06
    !byte $8A,$08,$AC,$09,$CF,$0B,$12,$01,$24,$02,$46,$03,$58,$04,$6A,$05,$8C,$06,$9F,$07,$02,$00,$14,$01,$26,$01,$38,$02,$4A,$02,$5C,$03
    !byte $6F,$03,$02,$00,$14,$00,$16,$00,$28,$00,$2A,$00,$3C,$00,$3F,$00,$12,$01,$34,$03,$46,$05,$68,$07,$8A,$09,$9C,$0B,$BF,$0D,$12,$01
    !byte $24,$03,$36,$04,$48,$06,$5A,$08,$6C,$09,$7F,$0B,$02,$01,$14,$02,$16,$04,$28,$05,$2A,$06,$3C,$08,$3F,$09,$02,$01,$04,$02,$06,$03
    !byte $08,$04,$0A,$05,$0C,$06,$0F,$07,$12,$02,$34,$04,$46,$06,$68,$08,$8A,$0A,$9C,$0C,$BE,$0F,$11,$02,$23,$04,$35,$06,$47,$08,$59,$0A
    !byte $6B,$0C,$7D,$0F,$01,$02,$13,$04,$15,$06,$26,$08,$28,$0A,$3A,$0C,$3C,$0F,$01,$02,$03,$04,$04,$06,$06,$08,$08,$0A,$09,$0C,$0B,$0F

pal_orig:
        !fill 512, 0

fade_steps_left: !byte 0
pal_tmp0: !byte 0
pal_tmp1: !byte 0
pal_tmp2: !byte 0
pal_tmp3: !byte 0
pal_tmp4: !byte 0
pal_tmp5: !byte 0
pal_tmp6: !byte 0

; -- End of vera_common.inc ---------------------------------------------------
