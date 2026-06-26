# C64 VERA Test Code

Four crude C64 programs that drive a VERA module wired into the cartridge port at $DE00. These are ports of test programs I wrote for an AGFA Compugraphic 9000PS.

## Hardware needed

- C64 with VERA on the I/O1 expansion at $DE00-$DE1F
- VGA monitor connected to VERA (hard coded to use VGA)
- VERA audio output for bach_inv13

## Programs

| PRG                     | Description                                |
| ----------------------- | ------------------------------------------ |
| vera_init_test_v2.prg   | text mode, font upload, character dump     |
| vera_color_cycle_v2.prg | 320x240 8bpp bitmap, palette animation     |
| vera_circles_v2.prg     | 320x240 8bpp bitmap, random filled circles |
| bach_inv13_v2.prg       | PSG audio, Bach Invention No. 13 (BWV 784) |

## Building from source

Requires bash (Git Bash on Windows works). Run from this directory:

```sh
bash c64/build.sh c64/vera_circles.asm vera_circles_v2.prg
```

The assembler (ACME 0.97.1) is used to build. The build script works around a bug in ACME's cbm output format -- don't call ACME directly, use build.sh.

## Loading on the C64

Copy the .prg to a floppy or SD card, then from BASIC:

```
LOAD"FILENAME",8,1
RUN
```

# 
