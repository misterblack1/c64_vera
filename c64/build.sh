#!/bin/bash
# build.sh -- assemble a C64 .asm into a valid .prg
#
# ACME's built-in "cbm" output format is broken in assembler/acme.exe
# (this fork's build emits Intel-hex text instead of a raw PRG, even though
# it's listed as a supported format -- confirmed by diffing against the
# explicit "hex" format, which is byte-identical apart from the headi).
# Workaround: assemble with "plain" format (verified to emit correct raw
# bytes) and prepend the 2-byte little-endian load address ourselves.
#
# Usage: c64/build.sh <source.asm> <output.prg> [load_addr_hex, default 0801]
set -e

SRC="$1"
OUT="$2"
LOADADDR="${3:-0801}"

if [ -z "$SRC" ] || [ -z "$OUT" ]; then
    echo "Usage: $0 <source.asm> <output.prg> [load_addr_hex]" >&2
    exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACME="$DIR/../assembler/acme.exe"
TMP="${OUT}.body.tmp"

"$ACME" -f plain -o "$TMP" "$SRC"

LO="${LOADADDR:2:2}"
HI="${LOADADDR:0:2}"
printf "\\x${LO}\\x${HI}" > "$OUT"
cat "$TMP" >> "$OUT"
rm -f "$TMP"

echo "Wrote $OUT ($(wc -c < "$OUT") bytes, load addr \$${LOADADDR})"
