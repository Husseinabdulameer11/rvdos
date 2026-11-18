#!/usr/bin/env bash
# build_os.sh -- build the RVDOS ROM image (OS + Flint + ED + games, all
# co-resident) into two hex files for cpu_top's HEX_FILE and
# RODATA_HEX_FILE generics.
#
# Needs:
#   riscv64-unknown-elf-gcc   the cross compiler (as before)
#   gcc                       a host compiler for the small build tools
#   gram                      https://github.com/Husseinabdulameer11/gram
#                             the repo's gram/ submodule (git submodule
#                             update --init), or anywhere with
#                             GRAM_DIR=/path/to/gram os/build_os.sh
#
# Flint's parser tables are regenerated from flint.gram on every build,
# because gram's precompiled tables must match the gram.c they run with.
set -e
# a GRAM_DIR given relative to where you ran this from still works after the cd
[ -n "$GRAM_DIR" ] && [ -d "$GRAM_DIR" ] && GRAM_DIR=$(cd "$GRAM_DIR" && pwd)
cd "$(dirname "$0")"          # everything below runs in os/
CC=riscv64-unknown-elf-gcc
OC=riscv64-unknown-elf-objcopy
HOSTCC=${HOSTCC:-gcc}
GRAM_DIR=${GRAM_DIR:-../gram}

if [ ! -f "$GRAM_DIR/gram.c" ]; then
    echo "gram not found in $GRAM_DIR"
    echo "  git submodule update --init      (from the repo root)"
    echo "  or run with GRAM_DIR=/path/to/gram $0"
    exit 1
fi

# --- host tools -----------------------------------------------------------
EXE=""; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=".exe";; esac
GRAMGEN="$GRAM_DIR/build/gramgen$EXE"
[ -x "$GRAMGEN" ] || make -C "$GRAM_DIR" "build/gramgen$EXE"
$HOSTCC -O2 -o bin2hex$EXE ../tools/bin2hex.c
$HOSTCC -O2 -o file2c$EXE  ../tools/file2c.c

# --- generated sources ----------------------------------------------------
mkdir -p gen
"$GRAMGEN" flint.gram flint gen > /dev/null
./file2c$EXE samples/* > gen/samples.c

# --- the ROM image --------------------------------------------------------
# -Os: the ROM is ~35 KB instead of ~60 KB at -O2, for ~8% less speed.
# -fno-builtin / -fno-tree-loop-distribute-patterns: mini.c implements
# memcpy & co, and gcc must not turn those loops back into calls to them.
CFLAGS="-march=rv32im -mabi=ilp32 -Os -ffreestanding -nostdlib -fno-pic \
        -fno-builtin -fno-tree-loop-distribute-patterns -Wall -Wextra"
# GRAM_MAX_DEPTH bounds gram's recursion: ~110 bytes of stack per rule level, and
# the 6 KB stack must also hold the OS and Flint. 40 levels ~ 10 nested ( ).
GRAMFLAGS="-I$GRAM_DIR -Igen -DGRAM_NO_COMPILER -DGRAM_MAX_DEPTH=40"

# boot.s must come first so .vectors lands at 0x0000. --no-check-sections:
# ROM, RODATA and RAM overlap numerically on purpose (separate memories).
$CC $CFLAGS $GRAMFLAGS -T link_os.ld -Wl,--no-check-sections -Wl,-Map=rvdos.map -o rvdos.elf \
    boot.s os.c mini.c flint.c ed.c pong.c snake.c tetris.c \
    gfx.c text.c font.c kbd.c \
    "$GRAM_DIR/gram.c" gen/flint_grammar.c gen/samples.c

# ROM image = vectors + text, contiguous from 0x0000.
$OC -O binary -j .vectors -j .text rvdos.elf rvdos_text.bin
# Read-only data (font, parser tables, samples, strings) at 0x30000.
$OC -O binary -j .rodata            rvdos.elf rvdos_rodata.bin

./bin2hex$EXE rvdos_text.bin   rvdos_text.hex
./bin2hex$EXE rvdos_rodata.bin rvdos_rodata.hex

# The core has no divide instruction; make sure gcc never emitted one.
if riscv64-unknown-elf-objdump -d rvdos.elf | grep -qE '\s(div|divu|rem|remu)\s'; then
    echo "error: the image contains a divide instruction (unsupported by this core)"
    exit 1
fi

echo
TW=$(($(wc -c < rvdos_text.bin)/4)); RW=$(($(wc -c < rvdos_rodata.bin)/4))
echo "  os/rvdos_text.hex    $TW words (the Basys3 ROM holds 12288)"
echo "  os/rvdos_rodata.hex  $RW words (the Basys3 rodata ROM holds 6144)"
[ $TW -le 12288 ] && [ $RW -le 6144 ] || { echo "error: too big for the Basys3 ROM sizes in hw/basys3_top.vhd"; exit 1; }
echo "  run it: ./run.sh    put it on the board: vivado -mode batch -source hw/build.tcl"
