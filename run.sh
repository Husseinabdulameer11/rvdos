#!/usr/bin/env bash
# run.sh -- run RVDOS in the emulator window at the FPGA's 25 MHz, with
# drive A: kept in rvdos.disk between runs. Builds the emulator (needs SDL2)
# and, if os/rvdos_text.hex is missing, the OS itself.
#   ./run.sh            normal speed
#   ./run.sh --fast     unthrottled
set -e
cd "$(dirname "$0")"
EXE=""; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=".exe";; esac
[ -f os/rvdos_text.hex ] || os/build_os.sh
# rebuild the emulator whenever its source is newer than the binary
EMU="tools/rvemu$EXE"
[ "$EMU" -nt tools/rvemu.c ] || gcc -O2 -Ios -o "$EMU" tools/rvemu.c os/font.c $(sdl2-config --cflags --libs)
MHZ=--mhz=25; [ "$1" = "--fast" ] && MHZ=
exec "$EMU" os/rvdos_text.hex os/rvdos_rodata.hex --disk=rvdos.disk $MHZ
