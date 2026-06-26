# Demo Source

Source files for the VERA demos. All programs share vera_common.inc (VERA equates, init routines, palette data, KERNAL helpers). Build from the repo root with:

```sh
bash c64/build.sh c64/<source>.asm <output>.prg
```

## Programs

**vera_init_test.asm** -- VERA text mode: reset, VGA composer setup, CP437 font uploaded to VRAM, Layer 0 configured as a 128x64 tilemap, all 256 characters dumped to the display. Exits automatically. Good reference for the startup sequence.

**vera_color_cycle.asm** -- 8bpp 320x240 bitmap. Draws a 16x16 grid of 256 solid color boxes, then continuously cycles every palette entry's hue until a key is pressed.

**vera_circles.asm** -- 8bpp 320x240 bitmap. Draws random filled circles using the midpoint algorithm. PRNG is xorshift32 seeded from the KERNAL jiffy clock. Press any key to stop.

**bach_inv13.asm** -- PSG audio only. Bach Invention No. 13 (BWV 784) on VERA's PSG. Two voices on channels 0 and 1 (L/R stereo), doubled an octave down on channels 2 and 3. Timing uses CIA #1 Timer B at roughly 100 Hz -- the KERNAL jiffy clock turned out unreliable on this hardware with VERA active. Shows a title banner on the VERA text display. Press any key to stop.

## Shared files

**vera_common.inc** -- included via `!source "c64/vera_common.inc"` at the end of each program (after your own code, not before it -- if you source it before start:, it shifts start: away from $0810 and breaks the BASIC SYS stub). Provides VERA register equates, vera_reset, vera_video_setup, font/palette upload routines, the AGFA 256-color palette buffer, fade routines, and thin KERNAL wrappers.

**build.sh** -- takes source and output paths relative to wherever you run it from (the repo root). Assembles with -f plain and prepends the 2-byte PRG load address header manually, because ACME's cbm output is broken in this build.

# 
