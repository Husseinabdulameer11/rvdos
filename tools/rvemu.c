/* rvemu -- a plain software emulator of this project's RV32IM core.
 *
 * This is a genuinely different kind of tool from the GHDL/VHDL
 * simulation used everywhere else in this project. GHDL simulates the
 * actual hardware -- every register, every wire, every clock edge,
 * bit-for-bit matching real silicon. That fidelity is the whole point
 * for verifying the *hardware design* is correct, but it makes it
 * inherently, unavoidably slow -- hundreds of thousands of simulated
 * clock cycles per video frame, each one doing real gate-level work.
 *
 * A real 6502/NES/etc. emulator doesn't do any of that. It just directly
 * says "opcode 0xA9 means: put the next byte into register A" and runs
 * at native machine speed, with zero hardware fidelity -- no pipeline,
 * no hazards, no clock cycles at all, just "what does this instruction
 * do." That's what this file is: the software-emulation equivalent of
 * this project's CPU, for testing whether *programs* work, at real
 * interactive speed. It is NOT a substitute for the VHDL -- it doesn't
 * prove the hardware design is correct (only GHDL simulation and,
 * eventually, real silicon can do that), and its correctness rests on
 * matching the ISA documented in README.md, not on being derived from
 * the VHDL -- the two can drift out of sync if not checked carefully.
 *
 * Memory map matches cpu_top.vhd exactly:
 *   0x00000000+           instructions (ROM contents)
 *   0x00010000 (64000B)   framebuffer, one byte = one pixel = palette index
 *   0x00020000 (1024B)    palette, 256 entries x 4 bytes (low 24 bits = RGB)
 *   0x00030000+           rodata (const data)
 *   0x00040000 (8B)       keyboard: +0 status (bit0=available), +4 data
 *
 * Unlike the real hardware (Harvard architecture: instr_rom and data_ram
 * are physically separate, which is why .rodata/.bss needed real
 * architectural work earlier in this project), this emulator uses ONE
 * flat memory array for everything -- a real simplification that doesn't
 * exist on the actual CPU. Mutable/initialized globals (.data) that
 * still don't work on real hardware WOULD "just work" here, which is a
 * genuine difference between this tool and the real thing, not a bug --
 * worth remembering if a program passes here but wouldn't on hardware.
 */

#ifndef RVEMU_HEADLESS
#include <SDL2/SDL.h>
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "font.h"

#define MEM_SIZE   0x100000u /* 1MB flat memory */
#define FB_BASE    0x00010000u
#define PAL_BASE   0x00020000u
#define RODATA_BASE 0x00030000u
#define KBD_BASE   0x00040000u
#define KBD_STATUS (KBD_BASE + 0)
#define KBD_DATA   (KBD_BASE + 4)

static uint8_t imem[MEM_SIZE]; /* instruction fetch only -- mirrors instr_rom */
static uint8_t dmem[MEM_SIZE]; /* everything else -- mirrors data_ram/framebuffer/palette/rodata/keyboard */
static uint32_t regs[32];
static uint32_t pc;
static int halted = 0;

/* ---------- memory access ---------- */
/* data_ram on the FPGA decodes `addr mod RAM_WORDS` for every address that
   is not a peripheral, so a stray pointer past the end of RAM wraps around
   instead of landing in fresh memory. map() reproduces that (--ram=BYTES,
   default 32 KB = RVDOS's RAM_WORDS 8192); everything else is untouched. */
static uint32_t ram_size = 32768;
static uint32_t map(uint32_t addr) {
    addr &= (MEM_SIZE - 1);
    if (addr >= FB_BASE && addr < KBD_BASE + 8) return addr;   /* fb, palette, rodata, kbd */
    return ram_size ? (addr & (ram_size - 1)) : addr;
}
/* All of these operate on dmem -- the data-side memory. Instruction
   fetch is handled separately in step(), reading imem instead. This
   split is not a simplification for its own sake -- it's what makes
   crt0.s's "li sp, 1008" (a real address chosen for data_ram's actual
   1KB size on the real hardware) safe here too: the stack and the
   program's own code genuinely cannot collide, the same way they
   cannot on the real Harvard-architecture CPU, because they're
   different arrays entirely -- not because addresses happen to avoid
   each other. */

static uint32_t load32(uint32_t addr) {
    addr = map(addr);
    uint32_t v = dmem[addr] | (dmem[addr+1]<<8) | (dmem[addr+2]<<16) | (dmem[addr+3]<<24);
    if (addr == KBD_DATA) {
        dmem[KBD_STATUS] = 0; /* reading the data register consumes the key -- matches keyboard.vhd */
    }
    return v;
}
static uint16_t load16(uint32_t addr) {
    addr = map(addr);
    return dmem[addr] | (dmem[addr+1]<<8);
}
static uint8_t load8(uint32_t addr) {
    return dmem[map(addr)];
}
static void store32(uint32_t addr, uint32_t v) {
    addr = map(addr);
    dmem[addr] = v & 0xFF; dmem[addr+1] = (v>>8)&0xFF; dmem[addr+2] = (v>>16)&0xFF; dmem[addr+3] = (v>>24)&0xFF;
}
static void store16(uint32_t addr, uint16_t v) {
    addr = map(addr);
    dmem[addr] = v & 0xFF; dmem[addr+1] = (v>>8)&0xFF;
}
static void store8(uint32_t addr, uint8_t v) {
    dmem[map(addr)] = v;
}

/* ---------- loading hex files (same format rvasm.c / bin2hex.c emit) ---------- */

static void load_hex_into(uint8_t *bank, const char *path, uint32_t base) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    char line[32];
    uint32_t addr = base;
    while (fgets(line, sizeof(line), f)) {
        uint32_t word;
        if (sscanf(line, "%x", &word) == 1) {
            bank[(addr) & (MEM_SIZE-1)]   = word & 0xFF;
            bank[(addr+1) & (MEM_SIZE-1)] = (word>>8) & 0xFF;
            bank[(addr+2) & (MEM_SIZE-1)] = (word>>16) & 0xFF;
            bank[(addr+3) & (MEM_SIZE-1)] = (word>>24) & 0xFF;
            addr += 4;
        }
    }
    fclose(f);
    fprintf(stderr, "loaded %s at 0x%08x (%u words)\n", path, base, (addr - base) / 4);
}

/* ---------- RV32IM execution ---------- */

static int32_t sext(uint32_t v, int bits) {
    int shift = 32 - bits;
    return ((int32_t)(v << shift)) >> shift;
}

static void step(void) {
    uint32_t fetch_addr = pc & (MEM_SIZE - 1);
    uint32_t instr = imem[fetch_addr] | (imem[fetch_addr+1]<<8) | (imem[fetch_addr+2]<<16) | (imem[fetch_addr+3]<<24);
    uint32_t opcode = instr & 0x7F;
    uint32_t rd     = (instr >> 7) & 0x1F;
    uint32_t funct3 = (instr >> 12) & 0x7;
    uint32_t rs1    = (instr >> 15) & 0x1F;
    uint32_t rs2    = (instr >> 20) & 0x1F;
    uint32_t funct7 = (instr >> 25) & 0x7F;

    int32_t imm_i = sext(instr >> 20, 12);
    int32_t imm_s = sext(((instr >> 25) << 5) | ((instr >> 7) & 0x1F), 12);
    int32_t imm_b = sext((((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11) |
                          (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1), 13);
    int32_t imm_u = instr & 0xFFFFF000;
    int32_t imm_j = sext((((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12) |
                          (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1), 21);

    uint32_t a = regs[rs1], b = regs[rs2];
    uint32_t next_pc = pc + 4;
    uint32_t result = 0;
    int write_rd = 0;

    switch (opcode) {
        case 0x33: /* R-type */
            write_rd = 1;
            if (funct7 == 0x01) { /* RV32M */
                int32_t as = (int32_t)a, bs = (int32_t)b;
                uint32_t au = a, bu = b;
                switch (funct3) {
                    case 0: result = (uint32_t)(as * bs); break;              /* MUL */
                    case 1: result = (uint32_t)(((int64_t)as * (int64_t)bs) >> 32); break; /* MULH */
                    case 2: result = (uint32_t)(((int64_t)as * (int64_t)bu) >> 32); break; /* MULHSU */
                    case 3: result = (uint32_t)(((uint64_t)au * (uint64_t)bu) >> 32); break; /* MULHU */
                    default: fprintf(stderr, "unimplemented M-ext funct3=%u at pc=0x%x (DIV/REM not supported)\n", funct3, pc); halted = 1; break;
                }
            } else {
                switch (funct3) {
                    case 0: result = (funct7 & 0x20) ? a - b : a + b; break; /* ADD/SUB */
                    case 1: result = a << (b & 0x1F); break;                /* SLL */
                    case 2: result = ((int32_t)a < (int32_t)b) ? 1 : 0; break; /* SLT */
                    case 3: result = (a < b) ? 1 : 0; break;                 /* SLTU */
                    case 4: result = a ^ b; break;                          /* XOR */
                    case 5: result = (funct7 & 0x20) ? (uint32_t)((int32_t)a >> (b & 0x1F)) : a >> (b & 0x1F); break; /* SRL/SRA */
                    case 6: result = a | b; break;                          /* OR */
                    case 7: result = a & b; break;                         /* AND */
                }
            }
            break;

        case 0x13: /* I-type ALU */
            write_rd = 1;
            switch (funct3) {
                case 0: result = a + imm_i; break;                          /* ADDI */
                case 1: result = a << (imm_i & 0x1F); break;                /* SLLI */
                case 2: result = ((int32_t)a < imm_i) ? 1 : 0; break;       /* SLTI */
                case 3: result = (a < (uint32_t)imm_i) ? 1 : 0; break;      /* SLTIU */
                case 4: result = a ^ imm_i; break;                          /* XORI */
                case 5: result = (funct7 & 0x20) ? (uint32_t)((int32_t)a >> (imm_i & 0x1F)) : a >> (imm_i & 0x1F); break; /* SRLI/SRAI */
                case 6: result = a | imm_i; break;                          /* ORI */
                case 7: result = a & imm_i; break;                         /* ANDI */
            }
            break;

        case 0x03: /* loads */
            write_rd = 1;
            { uint32_t addr = a + imm_i;
              switch (funct3) {
                case 0: result = (uint32_t)sext(load8(addr), 8); break;    /* LB */
                case 1: result = (uint32_t)sext(load16(addr), 16); break;  /* LH */
                case 2: result = load32(addr); break;                     /* LW */
                case 4: result = load8(addr); break;                      /* LBU */
                case 5: result = load16(addr); break;                     /* LHU */
              }
            }
            break;

        case 0x23: /* stores */
            { uint32_t addr = a + imm_s;
              switch (funct3) {
                case 0: store8(addr, (uint8_t)b); break;   /* SB */
                case 1: store16(addr, (uint16_t)b); break; /* SH */
                case 2: store32(addr, b); break;           /* SW */
              }
            }
            break;

        case 0x63: /* branches */
            { int taken = 0;
              switch (funct3) {
                case 0: taken = (a == b); break;                       /* BEQ */
                case 1: taken = (a != b); break;                       /* BNE */
                case 4: taken = ((int32_t)a < (int32_t)b); break;      /* BLT */
                case 5: taken = ((int32_t)a >= (int32_t)b); break;     /* BGE */
                case 6: taken = (a < b); break;                        /* BLTU */
                case 7: taken = (a >= b); break;                       /* BGEU */
              }
              if (taken) next_pc = pc + imm_b;
            }
            break;

        case 0x6F: /* JAL */
            write_rd = 1; result = pc + 4;
            next_pc = pc + imm_j;
            break;

        case 0x67: /* JALR */
            write_rd = 1; result = pc + 4;
            next_pc = (a + imm_i) & ~1u;
            break;

        case 0x37: /* LUI */
            write_rd = 1; result = imm_u;
            break;

        case 0x17: /* AUIPC */
            write_rd = 1; result = pc + imm_u;
            break;

        default:
            fprintf(stderr, "illegal opcode 0x%02x at pc=0x%08x (instr=0x%08x)\n", opcode, pc, instr);
            halted = 1;
            return;
    }

    if (write_rd && rd != 0) regs[rd] = result;
    regs[0] = 0;
    pc = next_pc;
}

/* ---------- SDL2 display + keyboard ---------- */

#define WIN_W 640
#define WIN_H 480

/* ---------- display, keyboard, test harness ---------- */

#define WIN_W 640
#define WIN_H 480

static void dump_regs(void) {
    fprintf(stdout, "pc=0x%08x\n", pc);
    for (int i = 0; i < 32; i++) fprintf(stdout, "x%d=0x%08x\n", i, regs[i]);
}

/* Read the 53x25 text screen back out of the framebuffer by matching each
   6x8 cell against the font -- lets a headless test check what a person
   would see. A pixel counts as lit if it differs from the cell's gap
   pixel (bottom-right, always background). Unrecognised cells print '#'. */
static void dump_screen(FILE *out) {
    for (int row = 0; row < 25; row++) {
        char line[64];
        int n = 0;
        for (int col = 0; col < 53; col++) {
            uint32_t base = FB_BASE + row * 8 * 320 + col * 6;
            uint8_t bg = dmem[base + 7 * 320 + 5];
            unsigned char bits[7];
            int any = 0;
            for (int r = 0; r < 7; r++) {
                bits[r] = 0;
                for (int k = 0; k < 5; k++)
                    if (dmem[base + r * 320 + k] != bg) bits[r] |= (unsigned char)(0x10 >> k);
                any |= bits[r];
            }
            char ch = any ? '#' : ' ';
            for (int g = 0; any && g < FONT_SIZE; g++)
                if (memcmp(FONT[g].rows, bits, 7) == 0 && FONT[g].ch != ' ') { ch = FONT[g].ch; break; }
            if (ch == '#') {
                /* a descender glyph (g j p q y) is drawn one row lower */
                unsigned char low[7];
                for (int r = 0; r < 7; r++) {
                    low[r] = 0;
                    for (int k = 0; k < 5; k++)
                        if (dmem[base + (r + 1) * 320 + k] != bg) low[r] |= (unsigned char)(0x10 >> k);
                }
                for (int g = 0; g < FONT_SIZE; g++)
                    if (FONT_DESCENDER(FONT[g].ch) && memcmp(FONT[g].rows, low, 7) == 0) { ch = FONT[g].ch; break; }
            }
            line[n++] = ch;
        }
        while (n > 0 && line[n - 1] == ' ') n--;
        line[n] = 0;
        fprintf(out, "|%s\n", line);
    }
}

/* --- scripted keys (headless) ----------------------------------------
   Escapes: \n enter, \b backspace, \e ESC, \t tab, \\ backslash,
   \^X control-X (\^C = break), \xHH any byte, \w wait 2M instructions,
   \W wait 20M. Arrow keys are WordStar controls: \^E up, \^X down,
   \^S left, \^D right. Keys go in one per 40k instructions (~1.6 ms at
   25 MHz), and only once the previous one was read. */
static size_t keyq_len, keyq_pos;
static long key_wait_until;
#define KEY_WAIT_SHORT 0x100
#define KEY_WAIT_LONG  0x101
static unsigned short keyq16[65536];

static void parse_keys(const char *src) {
    while (*src && keyq_len < 65535) {
        unsigned short k;
        if (src[0] == '\\' && src[1]) {
            char e = src[1];
            src += 2;
            if (e == 'n') k = '\n';
            else if (e == 'b') k = 8;
            else if (e == 'e') k = 27;
            else if (e == 't') k = 9;
            else if (e == 'w') k = KEY_WAIT_SHORT;
            else if (e == 'W') k = KEY_WAIT_LONG;
            else if (e == '^' && *src) { k = (unsigned short)(*src & 0x1F); src++; }
            else if (e == 'x' && src[0] && src[1]) {
                char hex[3] = { src[0], src[1], 0 };
                k = (unsigned short)strtoul(hex, NULL, 16); src += 2;
            }
            else k = (unsigned char)e;
        } else {
            k = (unsigned char)*src++;
        }
        keyq16[keyq_len++] = k;
    }
}
static void feed_keys(long step) {
    if (keyq_pos >= keyq_len || step < key_wait_until || dmem[KBD_STATUS]) return;
    unsigned short k = keyq16[keyq_pos++];
    if (k == KEY_WAIT_SHORT) { key_wait_until = step + 2000000; return; }
    if (k == KEY_WAIT_LONG)  { key_wait_until = step + 20000000; return; }
    dmem[KBD_DATA] = (uint8_t)k;
    dmem[KBD_STATUS] = 1;
    /* pace like a (very fast) typist: the OS keeps a 16-key type-ahead
       buffer, and keys arriving every few instructions would overflow it */
    key_wait_until = step + 40000;
}

/* --- RAM disk image: --disk=FILE loads RVDOS's drive A: at start and
   saves it at exit, so files survive between emulator runs. On the FPGA
   the disk lives in BRAM and survives the reset button the same way. */
static uint32_t disk_base = 0x5800, disk_size = 0x2800;   /* link_os.ld */
static void disk_load(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "disk %s: new (cold start)\n", path); return; }
    size_t n = fread(dmem + disk_base, 1, disk_size, f);
    fclose(f);
    fprintf(stderr, "disk %s: loaded %zu bytes\n", path, n);
}
static void disk_save(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "disk %s: cannot write\n", path); return; }
    fwrite(dmem + disk_base, 1, disk_size, f);
    fclose(f);
    fprintf(stderr, "disk %s: saved\n", path);
}

/* write the framebuffer through the palette as a 640x400 PPM image */
static void dump_ppm(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) { fprintf(stderr, "cannot write %s\n", path); return; }
    fprintf(f, "P6 640 400 255\n");
    for (int y = 0; y < 400; y++)
        for (int x = 0; x < 640; x++) {
            uint8_t idx = dmem[FB_BASE + (y / 2) * 320 + x / 2];
            uint32_t rgb = dmem[PAL_BASE + idx * 4] | dmem[PAL_BASE + idx * 4 + 1] << 8 | dmem[PAL_BASE + idx * 4 + 2] << 16;
            fputc((rgb >> 16) & 0xFF, f); fputc((rgb >> 8) & 0xFF, f); fputc(rgb & 0xFF, f);
        }
    fclose(f);
}

static void usage(const char *argv0) {
    fprintf(stderr,
        "usage: %s text.hex [rodata.hex] [options]\n"
        "  --mhz=N          pace to N MHz (25 = the FPGA core)\n"
        "  --disk=FILE      keep RVDOS's RAM disk in FILE between runs\n"
        "  --ram=BYTES      data_ram size for address wrap-around (default 32768, 0 = none)\n"
        "headless (no window):\n"
        "  --steps=N        run N instructions, then print registers\n"
        "  --keys=STR       type STR (escapes: \\n \\b \\e \\^C \\xHH \\w=pause)\n"
        "  --keyfile=FILE   type the contents of FILE (same escapes)\n"
        "  --screen         print the text screen instead of the registers\n"
        "  --ppm=FILE       also save a screenshot (640x400 PPM)\n"
        "  --peek=ADDR      also print one byte of memory\n", argv0);
}

int main(int argc, char **argv) {
    if (argc < 2) { usage(argv[0]); return 1; }
    const char *text_path = argv[1];
    const char *rodata_path = NULL;
    const char *disk_path = NULL;
    long max_steps = -1; /* -1 = unbounded (interactive mode) */
    long peek_addr = -1;
    int want_screen = 0;
    const char *ppm_path = NULL;
    double target_hz = 0.0; /* 0 = unthrottled; --mhz=N paces to N MHz so
                               delay loops map to wall-clock time and match
                               the real 25 MHz core */

    for (int i = 2; i < argc; i++) {
        if (strncmp(argv[i], "--steps=", 8) == 0) {
            max_steps = atol(argv[i] + 8);
        } else if (strncmp(argv[i], "--peek=", 7) == 0) {
            peek_addr = strtoul(argv[i] + 7, NULL, 0);
        } else if (strncmp(argv[i], "--keys=", 7) == 0) {
            parse_keys(argv[i] + 7);
        } else if (strncmp(argv[i], "--keyfile=", 10) == 0) {
            FILE *f = fopen(argv[i] + 10, "rb");
            static char buf[65536];
            if (!f) { fprintf(stderr, "cannot open %s\n", argv[i] + 10); return 1; }
            size_t n = fread(buf, 1, sizeof buf - 1, f);
            buf[n] = 0;
            fclose(f);
            parse_keys(buf);
        } else if (strncmp(argv[i], "--ppm=", 6) == 0) {
            ppm_path = argv[i] + 6;
        } else if (strcmp(argv[i], "--screen") == 0) {
            want_screen = 1;
        } else if (strncmp(argv[i], "--disk=", 7) == 0) {
            disk_path = argv[i] + 7;
        } else if (strncmp(argv[i], "--ram=", 6) == 0) {
            ram_size = (uint32_t)strtoul(argv[i] + 6, NULL, 0);
        } else if (strncmp(argv[i], "--mhz=", 6) == 0) {
            target_hz = atof(argv[i] + 6) * 1e6;
        } else if (argv[i][0] == '-') {
            usage(argv[0]); return 1;
        } else if (!rodata_path) {
            rodata_path = argv[i];
        }
    }

    load_hex_into(imem, text_path, 0);
    if (rodata_path) load_hex_into(dmem, rodata_path, RODATA_BASE);
    if (disk_path) disk_load(disk_path);

    /* Headless test mode: no SDL at all, run exactly max_steps
       instructions (or until an illegal-instruction halt), then dump
       register state or the screen for automated verification -- the
       software-emulator equivalent of this project's VHDL testbenches. */
    if (max_steps >= 0) {
        long i;
        for (i = 0; i < max_steps && !halted; i++) {
            feed_keys(i);
            step();
        }
        if (want_screen) {
            dump_screen(stdout);
            if (keyq_pos < keyq_len)
                fprintf(stdout, "(%zu scripted keys not consumed)\n", keyq_len - keyq_pos);
        } else {
            dump_regs();
        }
        if (peek_addr >= 0) fprintf(stdout, "mem[0x%lx]=0x%02x\n", peek_addr, dmem[map((uint32_t)peek_addr)]);
        if (ppm_path) dump_ppm(ppm_path);
        if (disk_path) disk_save(disk_path);
        return halted ? 2 : 0;
    }

#ifdef RVEMU_HEADLESS
    (void)target_hz;
    fprintf(stderr, "built without SDL: use --steps=N\n");
    return 1;
#else
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Window *win = SDL_CreateWindow("rvemu - RV32IM software emulator",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIN_W, WIN_H, 0);
    SDL_Renderer *ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED);
    SDL_Texture *tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB888,
        SDL_TEXTUREACCESS_STREAMING, WIN_W, WIN_H);
    SDL_StartTextInput();

    static uint32_t framebuf[WIN_W * WIN_H];
    uint32_t last_present = SDL_GetTicks();
    uint32_t sim_start = SDL_GetTicks();
    uint64_t instr_count = 0;

    while (!halted) {
        step();
        instr_count++;

        /* Poll for input/quit every so often -- cheap here (this is
           native C, not a VHDL/C bridge), but still no need to check
           every single instruction. */
        if ((instr_count & 0xFFF) == 0) {
            SDL_Event e;
            while (SDL_PollEvent(&e)) {
                int key = -1;
                if (e.type == SDL_QUIT) { halted = 1; }
                else if (e.type == SDL_TEXTINPUT) {
                    key = (uint8_t)e.text.text[0];
                } else if (e.type == SDL_KEYDOWN) {
                    SDL_Keycode s = e.key.keysym.sym;
                    /* control keys arrive as ASCII control codes; the
                       arrows and paging keys as WordStar's controls, the
                       convention CP/M software used (see syscall.h) */
                    if (s == SDLK_RETURN || s == SDLK_KP_ENTER) key = '\n';
                    else if (s == SDLK_BACKSPACE) key = 8;
                    else if (s == SDLK_TAB)       key = 9;
                    else if (s == SDLK_ESCAPE)    key = 27;
                    else if (s == SDLK_DELETE)    key = 127;
                    else if (s == SDLK_UP)        key = 5;
                    else if (s == SDLK_DOWN)      key = 24;
                    else if (s == SDLK_LEFT)      key = 19;
                    else if (s == SDLK_RIGHT)     key = 4;
                    else if (s == SDLK_HOME)      key = 1;
                    else if (s == SDLK_END)       key = 6;
                    else if (s == SDLK_PAGEUP)    key = 18;
                    else if (s == SDLK_PAGEDOWN)  key = 30;
                    else if ((e.key.keysym.mod & KMOD_CTRL) && s >= SDLK_a && s <= SDLK_z)
                        key = (int)(s - SDLK_a + 1);
                }
                if (key >= 0) { dmem[KBD_DATA] = (uint8_t)key; dmem[KBD_STATUS] = 1; }
            }

            /* Pace to target_hz: sleep until wall-clock catches up to the
               simulated time this many instructions "should" have taken. */
            if (target_hz > 0.0) {
                double sim_ms  = (double)instr_count * 1000.0 / target_hz;
                double real_ms = (double)(SDL_GetTicks() - sim_start);
                if (sim_ms > real_ms + 1.0) SDL_Delay((Uint32)(sim_ms - real_ms));
            }
        }

        /* Redraw at a real ~60fps cap based on wall-clock time. */
        uint32_t now = SDL_GetTicks();
        if (now - last_present >= 16) {
            last_present = now;
            for (int y = 0; y < 200; y++) {
                for (int x = 0; x < 320; x++) {
                    uint8_t idx = dmem[FB_BASE + y*320 + x];
                    uint32_t rgb = load32(PAL_BASE + idx*4) & 0xFFFFFF;
                    int px = x*2, py = 40 + y*2;
                    framebuf[py*WIN_W+px] = rgb; framebuf[py*WIN_W+px+1] = rgb;
                    framebuf[(py+1)*WIN_W+px] = rgb; framebuf[(py+1)*WIN_W+px+1] = rgb;
                }
            }
            SDL_UpdateTexture(tex, NULL, framebuf, WIN_W * sizeof(uint32_t));
            SDL_RenderClear(ren);
            SDL_RenderCopy(ren, tex, NULL, NULL);
            SDL_RenderPresent(ren);
        }
    }

    fprintf(stderr, "halted after %llu instructions, pc=0x%08x\n",
            (unsigned long long)instr_count, pc);
    if (disk_path) disk_save(disk_path);

    SDL_DestroyTexture(tex);
    SDL_DestroyRenderer(ren);
    SDL_DestroyWindow(win);
    SDL_Quit();
    return 0;
#endif
}
