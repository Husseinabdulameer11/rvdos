#!/usr/bin/env bash
# make_asm.sh -- dump the OS + programs' assembly into an ./asm subfolder.
#
#   asm/<file>.s             per-file compiler assembly (pre-link, symbolic),
#                            same flags as build_os.sh. boot.s is copied.
#   asm/rvdos.dis            full linked disassembly at real ROM addresses --
#                            this is what actually runs; check the top two
#                            words are `j _start` @ 0x0 and `j bdos_dispatch`
#                            @ 0x4.
#   asm/rvdos_annotated.dis  same, with the C source interleaved.
#
# Run build_os.sh first (it generates gen/ and needs gram, see there).
set -e
cd "$(dirname "$0")"          # runs in os/
CC=riscv64-unknown-elf-gcc
OD=riscv64-unknown-elf-objdump
GRAM_DIR=${GRAM_DIR:-../gram}
CFLAGS="-march=rv32im -mabi=ilp32 -Os -ffreestanding -nostdlib -fno-pic \
        -fno-builtin -fno-tree-loop-distribute-patterns"
GRAMFLAGS="-I$GRAM_DIR -Igen -DGRAM_NO_COMPILER -DGRAM_MAX_DEPTH=40"
OUT=asm
[ -f gen/flint_grammar.c ] || { echo "run build_os.sh first"; exit 1; }
mkdir -p "$OUT"

for f in os mini flint ed pong snake tetris gfx text font kbd; do
    $CC $CFLAGS $GRAMFLAGS -fverbose-asm -S "$f.c" -o "$OUT/$f.s"
    echo "  asm/$f.s"
done
cp boot.s "$OUT/boot.s"
echo "  asm/boot.s (hand-written, copied)"

$CC $CFLAGS $GRAMFLAGS -g -T link_os.ld -Wl,--no-check-sections -o "$OUT/rvdos_dbg.elf" \
    boot.s os.c mini.c flint.c ed.c pong.c snake.c tetris.c gfx.c text.c font.c kbd.c \
    "$GRAM_DIR/gram.c" gen/flint_grammar.c gen/samples.c
$OD -d  "$OUT/rvdos_dbg.elf" > "$OUT/rvdos.dis"
$OD -dS "$OUT/rvdos_dbg.elf" > "$OUT/rvdos_annotated.dis"
echo "  asm/rvdos.dis"
echo "  asm/rvdos_annotated.dis"
echo
echo "done -> ./$OUT/"
