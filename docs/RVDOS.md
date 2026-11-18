# RVDOS 2.0 — a CP/M-style OS for the RV32IM core

RVDOS boots to an `A>` prompt. You type commands and program names, files
live on drive A: (a RAM disk), and there's a built-in language,
[Flint](FLINT.md), plus a full-screen editor to write programs in. Nothing
runs on bare metal except the OS: every program reaches the system through
one syscall vector, as CP/M programs went through `CALL 5`.

```
RVDOS 2.0  RV32IM  32K RAM
Cold start: samples on A:, 7 files
Type HELP for commands.

A>DIR
A: ED       COM : FLINT    COM : PONG     COM
A: SNAKE    COM : TETRIS   COM : DODGE    FLT
A: GUESS    FLT : HELLO    FLT : HUSSEIN  FLT
A: MANDEL   FLT : PRIMES   FLT : README   TXT
A>HELLO
Hello from Flint!
1 squared is 1
...
A>FOO
FOO?
```

## Using it

| Command | |
|---|---|
| `DIR [pat]` | list files, three to a line like CP/M (`DIR *.FLT`, `DIR H*`) |
| `STAT [pat]` | sizes, free space, TPA size |
| `TYPE file` | show a text file, a screen at a time |
| `ERA pat` | erase files; `ERA *.*` asks first |
| `REN new=old` | rename (CP/M order; `REN old new` works too) |
| `PIP new=old` | copy a file |
| `ED file` | full-screen editor |
| `FLINT [file]` | run a Flint program, or the interactive prompt |
| `NAME` | run `NAME.COM` (a ROM program) or `NAME.FLT` |
| `CLS` `HELP` `VER` `FORMAT` `HALT` | |

Line input: Backspace edits, ESC clears the line, **Up** brings back the
previous line, `^C` cancels. An unknown name gets CP/M's reply, `NAME?`.

**ED** — arrows move (or WordStar's `^E ^X ^S ^D`), Home/End (`^A ^F`),
PgUp/PgDn, `^Y` deletes a line, Tab inserts two spaces. In `.FLT` files Enter
indents after `if`/`while`/`for`/`func`/`else`/`elif`, and lines up
`end`/`else`/`elif` with their block. Comments and strings are coloured.
ESC opens the menu: **S**ave, e**X**it (save and leave), **Q**uit.

**Games** — `PONG` (`W`/`S`), `SNAKE` (`WASD`), `TETRIS` (`A`/`D`, `W`
rotate, `S` drop, space slam). `Q` returns to `A>`.

## Files survive reset

Drive A: is 10 KB of RAM (`.noinit` in `link_os.ld`) that `boot.s` does not
clear, guarded by a checksum. Press the reset button and RVDOS says *Warm
start: files kept*. Power off, or a damaged disk, gives a cold start: an
empty disk with the sample programs copied in from ROM.

In the emulator, `--disk=rvdos.disk` keeps drive A: in a file between runs.
`tools/rvdisk.py` copies files in and out of that image, so you can write `.FLT`
files on your PC:

```
python3 tools/rvdisk.py rvdos.disk put MYGAME.FLT
python3 tools/rvdisk.py rvdos.disk ls
python3 tools/rvdisk.py rvdos.disk get MYGAME.FLT
```

## The three layers (CP/M's own names)

- **BIOS** (`os.c`) — the only code that touches hardware: the console
  (direct 6×8 cell renderer, scrolling by copying the framebuffer up, a
  blinking underline cursor in the gap row), the keyboard (a 16-key
  type-ahead ring drained from the one-key hardware register; `^C` sets a
  break flag instead) and the RAM disk.
- **BDOS** — `bdos_dispatch()`, reached through the fixed vector at
  **0x0004**. Function number in `a0`, arguments in `a1..a3`, result in `a0`.
- **CCP** — `ccp_main()`, the `A>` prompt: built-in commands, else run a
  transient.

## The syscall ABI (`syscall.h`)

| # | Name | Args → result |
|---|------|---------------|
| 0 | EXIT | — |
| 1 | GETC | → key (waits, shows the cursor) |
| 2 | PUTC | a1 = char (`\n \r \b \t` handled, scrolls) |
| 3 | POLL | → key or 0 |
| 4 | BREAK | → 1 if `^C` was pressed since last asked |
| 9 | PUTS | a1 = string |
| 10 | CLEAR | — |
| 11 | GOTOXY | a1 = col, a2 = row |
| 12 | FILLCELL | a1 = col, a2 = row, a3 = colour |
| 13 | SETCOLOR | a1 = text colour, a2 = background |
| 14 | SETPAL | a1 = index, a2 = 0xRRGGBB |
| 15 | GETXY | → col \| row << 8 |
| 16 | PUTCELL | a1 = col \| row << 8, a2 = char, a3 = fg \| bg << 8 |
| 17 | GETLINE | a1 = buffer, a2 = size → length, or -1 on `^C` |
| 20 | FFIND | a1 = name → file id or -1 |
| 21 | FSIZE | a1 = id → bytes |
| 22 | FDATA | a1 = id → pointer to the contents |
| 23 | FWRITE | a1 = name, a2 = data, a3 = length → `FS_*` |
| 24 | FDELETE | a1 = name → `FS_*` |
| 25 | FRENAME | a1 = old, a2 = new → `FS_*` |
| 26 | FNAME | a1 = id, a2 = 13-byte buffer → 0, or -1 past the end |
| 27 | FFREE | → free bytes |
| 30 | PIXEL | a1 = x, a2 = y, a3 = colour |
| 31 | RECT | a1 = x \| y << 16, a2 = w \| h << 16, a3 = colour |
| 32 | GETPIX | a1 = x, a2 = y → colour |
| 34 | ARGS | → the command tail (`ED FOO.FLT` → `"FOO.FLT"`) |
| 35 | VERSION | → 0x0200 |
| 36 | TPA | a1 = 0 → base, 1 → size |
| 37 | RANDOM | → 32 bits from keypress timing |

Numbers up to 9 deliberately echo CP/M's BDOS. Existing programs keep
working: calls 0–14 are unchanged, and SETCOLOR's new background argument is
0 when an old program passes nothing.

## Memory

| | |
|---|---|
| ROM 0x0000 | vectors, OS, Flint, ED, gram, games: ~40 KB (`-Os`) |
| RODATA 0x30000 | font, Flint's parser tables, sample files: ~20 KB |
| RAM 0x0010 | `.bss` (~700 bytes), zeroed at boot |
| | **TPA** ~15 KB: the running program's scratch RAM |
| | stack 6 KB |
| RAM 0x5800–0x7FFF | drive A:, 10 KB, never cleared by boot |

All of it is set in `link_os.ld`. It also refuses to link if any initialised
non-const global appears: nothing copies ROM to RAM on this machine, so such
a variable would silently start as garbage.

**Why 32 KB of RAM:** the Basys3's XC7A35T has 50 block RAMs (RAMB36, 4 KB
each). The framebuffer takes 16, a 48 KB ROM 12, 24 KB of rodata 6, the
palette 1, so 32 KB of RAM (8) totals 43. 64 KB of RAM would need 16 and push
it over 50.

## Building and running

```
git submodule update --init   # once: fetches gram into gram/
os/build_os.sh                # or GRAM_DIR=/path/to/gram os/build_os.sh
./run.sh                      # emulator window at 25 MHz, drive A: in rvdos.disk
```

`build_os.sh` builds gram's `gramgen` if needed and regenerates Flint's
parser tables from `flint.gram` every time, because the tables must match the
`gram.c` they run with. gram stays its own project; nothing is copied in.
The script also fails the build if gcc ever emits a divide instruction (see
below).

For the FPGA, `hw/basys3_top.vhd`'s generics already point at the result:

- `HEX_FILE` = `os/rvdos_text.hex`, `ROM_WORDS` = 12288 (48 KB; the image is ~40 KB)
- `RODATA_HEX_FILE` = `os/rvdos_rodata.hex`, `RODATA_WORDS` = 6144 (24 KB; ~21 KB used)
- `RAM_WORDS` = **8192** (32 KB)

`build_os.sh` stops with an error if the image outgrows those ROM sizes.
Then `vivado -mode batch -source hw/build.tcl` builds the bitstream and
programs the board.

## Testing

| | |
|---|---|
| `tests/smoke.sh` | boots RVDOS in the emulator and checks every shell command and program |
| `tests/run_flint_tests.sh` | 14 Flint programs: output compared with `.OUT` files |
| `tests/run_vhdl_tests.sh` | every self-checking VHDL testbench in `hw/sim` (GHDL, ~4 min) |
| `tests/ghdl_rvdos.sh` | boots RVDOS on the **VHDL CPU** in GHDL, types `DIR` and `HELLO`, and checks the screen is identical to the emulator's (~10 min) |
| `tools/rvemu_headless … --screen --keys=…` | any scripted session; `--ppm=` saves a screenshot |

The emulator gained: arrow/Home/End/PgUp/PgDn/ESC/Ctrl keys (sent as
WordStar control codes), `--disk`, `--screen` (reads the text back out of the
framebuffer), `--ppm`, paced scripted keys with `\w` pauses, and `--ram`,
which makes addresses wrap at the end of RAM like `data_ram` does on the FPGA.
`hosttest.c` is gone: it mocked the drawing calls, and the OS now draws into
the framebuffer directly, so the tests run the real binary in the emulator
instead.

## Fixed along the way

- **No divider, but gcc emitted divides.** `con_putu`'s `% 10` / `/ 10`
  compiled to `remu`/`divu` (gcc's RV32 tuning prefers them even for
  constants). In the old build Pong halted the CPU the first time someone
  scored. Numbers are now printed by subtracting powers of ten, `mini.c`
  has a software `udiv32`/`sdiv32`, and `build_os.sh` checks the
  disassembly for any divide.
- **RAM size.** `cpu_top` never passed a size to `data_ram`, so hardware had
  1 KB while RVDOS 1 assumed 8 KB. Its stack would have wrapped onto its
  variables.
- **The font** now covers all of printable ASCII: lowercase and `" # < > [ ]
  { } _ |` and more, generated by `mkfont.py` from ASCII art in
  `font_new_glyphs.txt`. The original 51 glyphs are kept exactly. `g j p q y`
  use the cell's spare 8th row for their tails.

## Still co-resident

The CPU is still Harvard, so code can't be loaded into RAM and run. ED,
FLINT and the games are compiled into the one ROM image, and the CCP
launches them with a direct call. That is the only part that isn't CP/M
yet. Everything else is ready for a loader: programs use only the syscall
ABI and the TPA, and Flint programs are already ordinary files on disk.
Once instruction and data memory are unified, `.COM` files can move onto
drive A: and the CCP changes from "call" to "load into the TPA, then jump".
