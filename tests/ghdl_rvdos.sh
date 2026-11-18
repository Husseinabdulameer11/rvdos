#!/usr/bin/env bash
# ghdl_rvdos.sh -- boot RVDOS on the VHDL CPU in GHDL, type DIR and HELLO,
# and check the screen matches rvemu's for the same keys. Slow: ~10 min.
#   tests/ghdl_rvdos.sh        (after build_os.sh, from the project folder)
set -e
cd "$(dirname "$0")/.."
W=$(mktemp -d)
for f in mem_pkg alu control_unit data_ram ex_mem_reg forward_unit framebuffer_ram \
         hazard_detect id_ex_reg if_id_reg imm_mux instr_decoder instr_rom instr_rom_hex \
         keyboard load_extend mem_wb_reg palette_ram pc_reg register_file rodata_rom \
         store_align video_scanout cpu_top sim/tb_rvdos; do
    (cd "$W" && ghdl -a --std=08 -fsynopsys "$OLDPWD/hw/$f.vhd")
done
cp os/rvdos_text.hex os/rvdos_rodata.hex "$W"
(cd "$W" && ghdl -e --std=08 -fsynopsys tb_rvdos && ghdl -r --std=08 -fsynopsys tb_rvdos -gCYCLES=2200000 2>&1 | grep tb_rvdos)
python3 tests/fb2text.py "$W/tb_rvdos_fb.txt" > "$W/ghdl.txt"
[ -x tools/rvemu_headless ] || gcc -O2 -DRVEMU_HEADLESS -Ios -o tools/rvemu_headless tools/rvemu.c os/font.c
tools/rvemu_headless os/rvdos_text.hex os/rvdos_rodata.hex --steps=3000000 --screen --keys='DIR\nHELLO\n' 2>/dev/null > "$W/emu.txt"
if diff "$W/ghdl.txt" "$W/emu.txt"; then echo "PASS: VHDL CPU screen == rvemu screen"; cat "$W/ghdl.txt"; else echo "FAIL: screens differ"; exit 1; fi
