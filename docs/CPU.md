# RV32I core — ISA reference

This document describes the instruction set implemented by this CPU: every
supported instruction, its encoding, what it does, and the parts of RV32I
that are deliberately left out. It's a reference for writing assembly by
hand or extending `rvasm.c`.

## Register file

32 general-purpose registers, `x0`–`x31`, each 32 bits. `x0` is hardwired
to zero — reads always return 0, writes are silently discarded.

| Register | ABI name | Convention |
|---|---|---|
| x0  | zero | always 0 |
| x1  | ra   | return address |
| x2  | sp   | stack pointer |
| x3  | gp   | global pointer |
| x4  | tp   | thread pointer |
| x5–x7 | t0–t2 | temporaries |
| x8  | s0/fp | saved / frame pointer |
| x9  | s1   | saved |
| x10–x17 | a0–a7 | function args / return values |
| x18–x27 | s2–s11 | saved |
| x28–x31 | t3–t6 | temporaries |

These are software conventions (a calling convention), not enforced by the
hardware — the CPU treats all 31 non-zero registers identically. `rvasm`
accepts both the `xN` and ABI names.

## Instruction formats

RV32I instructions are always 32 bits, and the immediate encoding is
deliberately scrambled per format so that `opcode`, `rd`, `funct3`, `rs1`,
`rs2` always sit at the same bit positions regardless of instruction type —
that's what lets the register file and ALU be fed by fixed wiring instead
of a format-dependent mux upstream of them.

```
R-type: funct7[31:25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7]  opcode[6:0]
I-type: imm[31:20]               rs1[19:15] funct3[14:12] rd[11:7]  opcode[6:0]
S-type: imm[31:25]     rs2[24:20] rs1[19:15] funct3[14:12] imm[11:7] opcode[6:0]
B-type: imm[31,7,30:25,11:8]  rs2[24:20] rs1[19:15] funct3[14:12]     opcode[6:0]
U-type: imm[31:12]                                          rd[11:7]  opcode[6:0]
J-type: imm[31,19:12,20,30:21]                               rd[11:7]  opcode[6:0]
```

B-type and J-type immediates always have bit 0 = 0 (branch/jump targets
are 2-byte aligned) and aren't stored — the LSB is implicit.

## Instructions

### R-type — register/register ALU ops
`rd = rs1 OP rs2`

| Mnemonic | opcode | funct3 | funct7 | Operation |
|---|---|---|---|---|
| add  | 0110011 | 000 | 0000000 | rd = rs1 + rs2 |
| sub  | 0110011 | 000 | 0100000 | rd = rs1 - rs2 |
| sll  | 0110011 | 001 | 0000000 | rd = rs1 << rs2[4:0] |
| slt  | 0110011 | 010 | 0000000 | rd = (rs1 < rs2), signed |
| sltu | 0110011 | 011 | 0000000 | rd = (rs1 < rs2), unsigned |
| xor  | 0110011 | 100 | 0000000 | rd = rs1 ^ rs2 |
| srl  | 0110011 | 101 | 0000000 | rd = rs1 >> rs2[4:0], logical |
| sra  | 0110011 | 101 | 0100000 | rd = rs1 >> rs2[4:0], arithmetic (sign-extending) |
| or   | 0110011 | 110 | 0000000 | rd = rs1 \| rs2 |
| and  | 0110011 | 111 | 0000000 | rd = rs1 & rs2 |

### R-type — RV32M multiply (funct7 = 0000001)
`rd = high or low 32 bits of the 64-bit product rs1 * rs2`

| Mnemonic | opcode | funct3 | Operation |
|---|---|---|---|
| mul    | 0110011 | 000 | rd = (rs1 * rs2)[31:0] |
| mulh   | 0110011 | 001 | rd = (signed(rs1) * signed(rs2))[63:32] |
| mulhsu | 0110011 | 010 | rd = (signed(rs1) * unsigned(rs2))[63:32] |
| mulhu  | 0110011 | 011 | rd = (unsigned(rs1) * unsigned(rs2))[63:32] |

Implemented as a single-cycle combinational 64-bit multiply in the ALU —
correct, but not gate-efficient (a real implementation would right-size
the multiplier to 33x33 for the mixed-sign case rather than using full
64-bit operands throughout). `div`/`divu`/`rem`/`remu` (funct3 100–111
under this same funct7) are **not implemented** — flagged as an illegal
instruction rather than silently producing a wrong answer. Division isn't
single-cycle in real hardware the way this multiply is, so adding it
means an actual multi-cycle EX stage, not just another ALU case — a
deliberately deferred, separate piece of work.

### I-type — register/immediate ALU ops
`rd = rs1 OP sext(imm12)`

| Mnemonic | opcode | funct3 | Operation |
|---|---|---|---|
| addi  | 0010011 | 000 | rd = rs1 + imm |
| slti  | 0010011 | 010 | rd = (rs1 < imm), signed |
| sltiu | 0010011 | 011 | rd = (rs1 < imm), unsigned |
| xori  | 0010011 | 100 | rd = rs1 ^ imm |
| ori   | 0010011 | 110 | rd = rs1 \| imm |
| andi  | 0010011 | 111 | rd = rs1 & imm |

### Shift-immediate — distinct encoding (5-bit shamt, not a 12-bit immediate)
`rd = rs1 << / >> shamt`

| Mnemonic | opcode | funct3 | funct7 | Operation |
|---|---|---|---|---|
| slli | 0010011 | 001 | 0000000 | rd = rs1 << shamt |
| srli | 0010011 | 101 | 0000000 | rd = rs1 >> shamt, logical |
| srai | 0010011 | 101 | 0100000 | rd = rs1 >> shamt, arithmetic |

### Loads — `rd, imm(rs1)`
`rd = sext_or_zext(mem[rs1 + imm])`

| Mnemonic | opcode | funct3 | Width | Extension |
|---|---|---|---|---|
| lb  | 0000011 | 000 | byte | sign |
| lh  | 0000011 | 001 | halfword | sign |
| lw  | 0000011 | 010 | word | — |
| lbu | 0000011 | 100 | byte | zero |
| lhu | 0000011 | 101 | halfword | zero |

### Stores — `rs2, imm(rs1)`
`mem[rs1 + imm] = rs2 (truncated to width)`

| Mnemonic | opcode | funct3 | Width |
|---|---|---|---|
| sb | 0100011 | 000 | byte |
| sh | 0100011 | 001 | halfword |
| sw | 0100011 | 010 | word |

Stores/loads at any byte address are supported (not just word-aligned) —
`store_align.vhd` / `load_extend.vhd` handle positioning within the 32-bit
RAM word. Misaligned halfword access (odd address) is **not** checked or
trapped — a known gap, not a feature.

### Branches — `rs1, rs2, label`
Branch to `PC + imm` if the condition holds; otherwise fall through to `PC+4`.

| Mnemonic | funct3 | Condition |
|---|---|---|
| beq  | 000 | rs1 == rs2 |
| bne  | 001 | rs1 != rs2 |
| blt  | 100 | rs1 < rs2, signed |
| bge  | 101 | rs1 >= rs2, signed |
| bltu | 110 | rs1 < rs2, unsigned |
| bgeu | 111 | rs1 >= rs2, unsigned |

All opcode 1100011. Resolved in the EX stage; a taken branch flushes the
two instructions already fetched behind it.

### Jumps

| Mnemonic | opcode | Syntax | Operation |
|---|---|---|---|
| jal  | 1101111 | `rd, label` | rd = PC+4 (return address); PC = PC + imm (offset up to ±1 MiB) |
| jalr | 1100111 | `rd, rs1, imm` | rd = PC+4; PC = (rs1 + imm) & ~1 |

`jal x0, label` discards the link value — an unconditional jump.
`jalr x0, 0(ra)` is the standard "return from function" idiom (jump to the
saved return address, discard nothing since x0 discards writes anyway).

### Upper-immediate

| Mnemonic | opcode | Syntax | Operation |
|---|---|---|---|
| lui   | 0110111 | `rd, imm20` | rd = imm20 << 12 |
| auipc | 0010111 | `rd, imm20` | rd = PC + (imm20 << 12) |

`imm20` is the raw top 20 bits you supply — this core does **not**
implement `%hi`/`%lo` relocations, so building a full 32-bit address from
`lui`+`addi` currently means computing both halves by hand.

## Memory map

| Range | Maps to | Notes |
|---|---|---|
| `0x00000000` – (varies) | `instr_rom` / `instr_rom_hex` | code only, fetched via PC — never touched by load/store |
| `0x00000000` – `0x000003FF` (1KB default) | `data_ram` | stack + general variables (`data_ram`'s size, `RAM_WORDS`, is a separate generic from the instruction ROM's `ROM_WORDS`) |
| `0x00010000` – `0x0001FA3F` | `framebuffer_ram` | 320×200 bytes, one byte = one pixel = a palette index |
| `0x00020000` – `0x000203FF` | `palette_ram` | 256 entries × 32-bit word, low 24 bits = R:G:B |
| everything else | `data_ram` (wraps via `mod RAM_WORDS`) | anything not in the two ranges above falls through unchanged |

Framebuffer and palette are true dual-port: the CPU writes through one
port (normal `sb`/`sw`), while `video_scanout` continuously reads through
a completely separate port every pixel clock — the two never contend.

## Video output

`video_scanout.vhd` generates standard 640×480@60Hz VGA timing (`hsync`,
`vsync`, `video_active`, 8-bit `red`/`green`/`blue`, all top-level ports
on `cpu_top`) and scans the 320×200 framebuffer through the palette,
pixel-doubled to 640×400 and letterboxed with a 40-line black bar top and
bottom. Every output is registered together (deliberately — see the
comments in `video_scanout.vhd`), so the whole picture sits a uniform one
clock cycle behind the internal counters. That delay matters if you're
writing a testbench that checks a specific pixel: a pixel at logical
column `C` reads back at `h_count` in `{2C+1, 2C+2}`, not `{2C, 2C+1}`.

**Watching it render live**: the GHDL+SDL2 cosimulation harness from
earlier in this project (`sdl_bridge.c` + VHPIDIRECT) works unchanged
against `cpu_top`'s `hsync`/`vsync`/`red`/`green`/`blue` — it was already
written for standard 640×480 timing.

## Graphics library (`gfx.c`/`gfx.h`)

Freestanding C, no libc, targeting the memory map above directly through
volatile pointers:

- `set_palette(index, r, g, b)`
- `draw_pixel(x, y, color)` — bounds-checked, silently no-ops out of range
- `fill_rect(x, y, w, h, color)`, `draw_hline`/`draw_vline`, `draw_rect` (outline)
- `clear_screen(color)` — implemented, but touches all 64,000 pixels: at
  roughly 5–10 simulated cycles per pixel via `fill_rect`, that's
  400,000–600,000 cycles on its own. Fine on real hardware, expensive to
  simulate — avoid calling it in anything you want GHDL to finish quickly.

Compile with the real `riscv64-unknown-elf-gcc` toolchain (see below),
same `crt0.s`/`link.ld` as any other freestanding program on this CPU.
Programs using only local variables and function arguments (no globals,
no string literals) work correctly today; anything with global/static
data doesn't yet have anywhere consistent to live, since `instr_rom` and
`data_ram` are separate physical memories (see "What's NOT implemented").

## FPGA bring-up (Basys3)

Everything above runs in GHDL simulation and on a real Basys3.
`hw/basys3_top.vhd` + `hw/basys3.xdc` add the board-specific plumbing;
build and program with `vivado -mode batch -source hw/build.tcl`. Vivado
2023.2 builds it with no errors and +8.9 ns of setup slack at 25 MHz, and
RVDOS boots on the board with VGA output and a USB keyboard.

- **Single clock domain, deliberately.** `clk_wiz_basys3.vhd` generates
  exactly 25MHz from the board's 100MHz oscillator (`VCO = 100MHz × 10.0
  ÷ 1 = 1000MHz`, then `÷ 40 = 25MHz`, zero frequency error) and that one
  clock drives the entire CPU — pipeline and video scanout together. The
  "correct" answer is separate CPU/pixel clock domains with proper
  crossing (the dual-port framebuffer/palette RAMs are already
  structured to support two clock domains on their two ports); single-
  domain is the simplest thing that could plausibly work for a first
  bring-up, not the final design.
- **Reset conditioning**: `reset_sync.vhd` (2-flop synchronizer, since a
  physical button has no relationship to any clock) feeds `debounce.vhd`
  (filters mechanical bounce), gated by the MMCM's `LOCKED` output so the
  CPU stays in reset until the clock is actually stable.
- **RGB truncation happens at the board boundary.** `cpu_top`/
  `video_scanout` keep full 8-bit color regardless of target; only
  `basys3_top.vhd` truncates to the Basys3 VGA connector's actual 4 bits
  per channel.
- **All big memories are block RAM.** Block RAM can only be read on a
  clock edge, so every large memory reads synchronously:
  `instr_rom_hex` is given the *next* PC (`fetch_addr` in `cpu_top`, which
  mirrors `pc_reg`'s reset/stall/next logic) so the instruction for the
  current PC is ready in IF; `data_ram`, `framebuffer_ram` and
  `rodata_rom` are addressed in MEM and their outputs land in WB, where
  `load_extend` now sits (the same timing the MEM/WB register gave the
  old combinational reads, so forwarding and the load-use stall are
  unchanged); `video_scanout` asks for each pixel one clock early. The
  framebuffer is stored as 16384 x 32-bit words. Every testbench gives the
  same results, at the same simulation times, as the combinational
  version. Yosys `synth_xilinx` maps RVDOS to about 41 of the 50 RAMB36
  and ~3,200 LUTs.
- **ROM loading**: `mem_pkg.load_hex` reads the hex files with plain
  `std.textio` character reads, which Vivado supports for memory
  initialisation. `hw/build.tcl` runs Vivado from the repo root so the
  relative file names (`os/rvdos_text.hex`, ...) resolve.
- **USB keyboard**: the Basys3's USB HOST port is served by a PIC24 that
  re-sends keys as PS/2; `ps2_keyboard.vhd` decodes them (Norwegian or US
  layout, `KBD_LAYOUT` generic) into the `keyboard` peripheral.
- **Known open item, not addressed here**: the 64-bit combinational
  multiply (see the M-extension section above) is a real timing-closure
  risk once actual clock constraints exist. Check Vivado's timing report
  on the ALU path specifically before assuming it meets 25MHz, let alone
  anything faster.

## Read-only C data (`.rodata`)

**This gap is closed.** `rodata_rom.vhd` gives constant C data (`static
const` arrays, string literals) somewhere the `lw`/`lb` load path can
actually reach — `instr_rom` never could, since it's only wired to PC
fetch, not the data-side address decode. Memory-mapped at `0x00030000`
(`RODATA_BASE`), same `textio`-hex-loading mechanism as `instr_rom_hex`,
read-only (a store to this range has nowhere to go — `data_ram`'s write
enable is gated off for it too, same as the framebuffer/palette ranges).

**This needs a two-region linker script**, not the single-`ROM` one used
everywhere else in this project — see `text/link_rodata.ld`:
```
MEMORY
{
    ROM    (rx) : ORIGIN = 0x00000000, LENGTH = 4K
    RODATA (r)  : ORIGIN = 0x00030000, LENGTH = 4K
}
SECTIONS
{
    .text   : { *(.text*) }                > ROM
    .rodata : { *(.rodata*) *(.srodata*) } > RODATA
    /DISCARD/ : { *(.data*) *(.sdata*) *(.bss*) *(.sbss*) *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
```
`.srodata` (RISC-V GCC's small-data optimization for compact constants)
has to be explicitly routed alongside `.rodata` — leaving it unmatched
happened to land it in the right place once by linker default-placement
luck, which is not something to rely on; route it explicitly.

**Build pipeline now extracts two hex files, not one**:
```bash
riscv64-unknown-elf-objcopy -O binary --only-section=.text   prog.elf prog_text.bin
riscv64-unknown-elf-objcopy -O binary --only-section=.rodata prog.elf prog_rodata.bin
./bin2hex prog_text.bin   prog_text.hex
./bin2hex prog_rodata.bin prog_rodata.hex
```
Load both via `cpu_top`'s `HEX_FILE`/`ROM_WORDS` (as before) and the new
`RODATA_HEX_FILE`/`RODATA_WORDS` generics. `RODATA_HEX_FILE` defaults
empty (no `.rodata` memory instantiated at all) for every existing
program that doesn't need it.

**Still not solved**: mutable global/static data (`.data`/`.bss`) — this
fix only covers *read-only* constants. A global variable that gets
written at runtime still has nowhere consistent to live.

## Text rendering (`font.c`/`text.c`)

A minimal 5×7 bitmap font (space, `-`, `C`, `I`, `R`, `S`, `V` — just
enough to spell "RISC-V", not full ASCII yet) lives in `font.c` as
genuine `const` data, the first real user of `rodata_rom`. `draw_char`/
`draw_string` build on `gfx.c`'s `fill_rect` to render each glyph at an
adjustable pixel scale. Verified two ways: a testbench checks basic
structure (a lit pixel where a glyph should start, a blank gap between
characters) — but confirming the text actually reads correctly, not just
"has plausible structure," is a job for the live SDL2 render
(`tb_live.vhd`), not a pixel-assertion testbench. Extending the font to
full ASCII is the same pattern repeated, not a new technique.

## Full character set + text-mode console

`font.c` now covers 51 glyphs — A–Z, 0–9, space, and common punctuation
(`. , : ; ! ? ' ( ) / = + * -`), generated directly from ASCII-art-
verified glyph data rather than typed by hand (each glyph was rendered
as `#`/`.` grid art and visually checked before ever becoming a byte
value — the same discipline as the original 7-glyph font, just scaled
up). Lowercase isn't included; adding it is the same technique repeated.

`console.c`/`console.h` build a real fixed-grid text console on top:
53×25 characters at scale=1 (6×8 pixel cells on the 320×200 screen),
with a genuinely persistent cursor position that survives across calls
— `console_putc`/`console_puts` track column/row, wrap at end of line,
and (currently) wrap back to row 0 at the bottom rather than scrolling
(a real scroll means shifting up to 64,000 pixels, the same simulation-
time cost flagged for `clear_screen()`).

**This needed one more architectural piece**: persistent cursor state is
*mutable* global data (`.bss`), not `const` like the font table —
`.rodata` alone didn't cover it. The fix turned out to be simpler than
`.rodata`'s: `data_ram` already zero-initializes on its own, which is
exactly what `.bss` requires, so `link_console.ld` just needs to place
`.bss` at a `data_ram` address (`0x0`, since nothing else was using low
addresses there) — no separate hex-extraction step needed, unlike
`.rodata`'s real initial content. Genuinely mutable `.data` (non-zero-
initialized globals) still isn't supported; nothing has needed it yet.

One thing worth internalizing from actually building this: the first
version of `console_demo.c` rendered *entirely correctly* — right
pixels, right addresses, right structure, confirmed by hand-computing
the exact expected pixel count (561) and matching it exactly — but
appeared as invisible black-on-black text, because `console_init()`
only *selects* a palette index, it doesn't *define* what color that
index is. `set_palette()` still has to be called separately first. A
demo that "does nothing visible" is not necessarily a hardware bug — it
can just as easily be forgetting to initialize a color.

## Keyboard input (`keyboard.vhd`)

The first genuinely interactive piece of hardware in this project.
Memory-mapped at `0x00040000`: a status register (bit 0 = key waiting)
and a data register (reading it returns the key and clears the status
bit). Deliberately minimal — **one pending key at a time, no buffering**;
a second keypress before the first is read just overwrites it. Injected
from outside via a one-cycle `key_valid`/`key_data` pulse, which
`cpu_top` exposes as top-level ports — the peripheral itself has no idea
whether that pulse comes from a synthetic testbench process
(`tb_keyboard.vhd`) or real SDL2 keyboard events (`tb_live.vhd`, via
`sdl_bridge.c`'s new `sdl_poll_key`).

`kbd.c`/`kbd.h` give C a `kbd_getchar()` (busy-waits — there's no
interrupt controller on this CPU, so polling is the only option) and
`kbd_available()`. `echo_demo.c` is the first program in this whole
project with no defined "finished" state — it loops forever reading and
echoing keys, verified by injecting a synthetic keypress mid-simulation
and confirming (via store tracing, not a full-frame scan) that the
correct pixel pattern for that character actually got drawn.

**What I could verify vs. what I couldn't**: the keyboard peripheral
itself and the C driver are fully tested here, synthetic-key-only, no
SDL2 involved. The `sdl_bridge.c` keyboard-capture additions
(`SDL_TEXTINPUT`, `sdl_poll_key`) can only be reviewed for correctness,
not run — same limitation as the bridge always had, since it needs a
real Windows DLL load that doesn't exist in this Linux sandbox.

## What's NOT implemented

- **RV32M divide/remainder** (`div`/`divu`/`rem`/`remu`) — the multiply
  half of the M extension is implemented (see above); division is not.
  GCC-compiled code using `/` or `%` will not run correctly without this.
- **FENCE, ECALL, EBREAK** — not recognized by `rvasm` or the control unit.
  No system calls, no software breakpoints.
- **CSR instructions** (`csrrw` etc.) — no privilege modes, no interrupts,
  no exception handling of any kind. An illegal opcode is detected
  internally (`control_unit`'s `illegal` output) but nothing acts on it.
- **Misaligned access trapping** — silently does the wrong thing rather
  than faulting.
- **Wishbone / real bus protocol** — instruction and data memory are
  direct-connected, fixed single-cycle access. Fine for simulation, not
  representative of a real memory-mapped peripheral bus yet.
- **Global/static C data** — read-only constants (`.rodata`) are solved.
  Mutable, *zero-initialized* globals (`.bss`) are now solved too (see
  "Full character set + text-mode console" above). Mutable globals with
  a real non-zero initial value (`.data`) are the one piece still
  missing — that needs an actual hex-extraction-and-load step, since
  `data_ram` can't magically start pre-loaded with arbitrary content the
  way `.bss`'s all-zero requirement gets for free.
- **Console scrolling** — wraps back to the top instead. A real
  implementation means shifting the framebuffer's content up one text
  row, which costs roughly as much simulated time as a full
  `clear_screen()` call per scroll.
- **`%hi`/`%lo` relocations** in `rvasm` — `lui`'s 20-bit immediate has to
  be a value you compute by hand, not derived from a label.

## Toolchain

- `rvasm.c` — hand-written two-pass assembler, source → `.hex` (one
  32-bit word per line, 8 hex digits). Build: `gcc -O2 -o rvasm asm.c`.
  Covers every instruction above except the M-extension multiplies
  (`mul`/`mulh`/`mulhsu`/`mulhu` are supported too) — no pseudo-ops
  (`li`/`mv`/`ret`), no relocations.
- **Real GCC** (`riscv64-unknown-elf-gcc`) — the actual path for anything
  beyond hand-written assembly. Target `-march=rv32im -mabi=ilp32
  -ffreestanding -nostdlib`, link with the provided `crt0.s` + `link.ld`
  (places everything in a 4KB ROM region starting at 0, discards
  `.data`/`.bss` — see the global-data limitation above), then
  `objcopy -O binary` and `bin2hex.c` to get a loadable `.hex`. Always
  check `objdump -d` for `div`/`rem`/`csr`/`fence`/`ecall`/`ebreak`
  before trusting new object code on this CPU — nothing here traps an
  illegal instruction cleanly yet.
- `instr_rom_hex.vhd` — loads a `.hex` file into simulation via VHDL
  `textio`. Wire it up through `cpu_top`'s `HEX_FILE` generic; `ROM_WORDS`
  must be large enough to hold the program (default 256 — a program that
  outgrows it wraps silently rather than erroring, which looks exactly
  like a control-flow bug until you check the size).
- `instr_rom.vhd` — the original array-based ROM, for hand-encoded test
  programs (still used by most of the existing testbenches).
- `bin2hex.c` — converts a raw little-endian binary (from `objcopy -O
  binary`) into the same `.hex` format `rvasm` emits.

## Pipeline notes (affects instruction *timing*, not the ISA above)

5-stage in-order pipeline (IF/ID/EX/MEM/WB). EX/MEM and MEM/WB forwarding
cover most data hazards combinationally; a load immediately followed by a
dependent instruction forces one stall cycle (the value doesn't exist
until MEM completes, so it can't be forwarded in time). Branches and jumps
both resolve in EX and flush the two speculatively-fetched instructions
behind them on a taken branch/jump.
