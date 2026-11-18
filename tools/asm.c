/*
 * rvasm — a small two-pass RV32I assembler.
 *
 * Pass 1: scan the source, recording the address of every label (PC starts
 * at 0, +4 per real instruction; directives/comments/blank lines don't
 * consume an address; a label on its own line takes the address of the
 * next real instruction).
 *
 * Pass 2: scan again, this time actually encoding each instruction into a
 * 32-bit word. Label references are resolved against the symbol table
 * built in pass 1 -- this two-pass structure exists specifically so a
 * branch or jump can reference a label defined later in the file.
 *
 * Output: one 32-bit word per line, as 8 hex digits, no "0x" prefix --
 * matches what a $readmemh-style VHDL/Verilog ROM loader expects.
 *
 * Supported: the full RV32I integer instruction set (R/I/S/B/U/J formats,
 * including the shift-immediate instructions which use a distinct encoding),
 * comments ('#' or ';' to end of line), labels ("name:"), and a .word
 * directive for raw data.
 *
 * NOT supported (known gaps, not silently wrong -- these just aren't
 * recognized): pseudo-instructions (li, mv, nop as a real mnemonic works
 * since it's literally addi x0,x0,0, but ret/call/j-as-alias don't exist
 * yet), %hi/%lo relocations for LUI+ADDI address pairs (LUI's operand is
 * a raw 20-bit value you compute yourself), FENCE/ECALL/EBREAK/CSR
 * instructions (the CPU doesn't implement these either, so this is
 * consistent), and multiple source files / a linker.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <stdarg.h>

#define MAX_LINE 512
#define MAX_SYMS 4096
#define MAX_LINES 65536

typedef enum {
    FMT_R, FMT_I, FMT_I_SHIFT, FMT_I_LOAD, FMT_I_JALR,
    FMT_S, FMT_B, FMT_U, FMT_J, FMT_WORD
} fmt_t;

typedef struct {
    const char *mnemonic;
    fmt_t fmt;
    uint32_t opcode;
    uint32_t funct3;
    uint32_t funct7; /* only meaningful for FMT_R and FMT_I_SHIFT */
} instr_def_t;

static const instr_def_t INSTR_TABLE[] = {
    /* R-type */
    {"add",  FMT_R, 0x33, 0x0, 0x00},
    {"sub",  FMT_R, 0x33, 0x0, 0x20},
    {"sll",  FMT_R, 0x33, 0x1, 0x00},
    {"slt",  FMT_R, 0x33, 0x2, 0x00},
    {"sltu", FMT_R, 0x33, 0x3, 0x00},
    {"xor",  FMT_R, 0x33, 0x4, 0x00},
    {"srl",  FMT_R, 0x33, 0x5, 0x00},
    {"sra",  FMT_R, 0x33, 0x5, 0x20},
    {"or",   FMT_R, 0x33, 0x6, 0x00},
    {"and",  FMT_R, 0x33, 0x7, 0x00},

    /* I-type arithmetic */
    {"addi",  FMT_I, 0x13, 0x0, 0},
    {"slti",  FMT_I, 0x13, 0x2, 0},
    {"sltiu", FMT_I, 0x13, 0x3, 0},
    {"xori",  FMT_I, 0x13, 0x4, 0},
    {"ori",   FMT_I, 0x13, 0x6, 0},
    {"andi",  FMT_I, 0x13, 0x7, 0},

    /* I-type shift-immediate (distinct encoding: shamt + funct7-like field) */
    {"slli", FMT_I_SHIFT, 0x13, 0x1, 0x00},
    {"srli", FMT_I_SHIFT, 0x13, 0x5, 0x00},
    {"srai", FMT_I_SHIFT, 0x13, 0x5, 0x20},

    /* I-type loads: "rd, imm(rs1)" */
    {"lb",  FMT_I_LOAD, 0x03, 0x0, 0},
    {"lh",  FMT_I_LOAD, 0x03, 0x1, 0},
    {"lw",  FMT_I_LOAD, 0x03, 0x2, 0},
    {"lbu", FMT_I_LOAD, 0x03, 0x4, 0},
    {"lhu", FMT_I_LOAD, 0x03, 0x5, 0},

    /* JALR: "rd, rs1, imm" */
    {"jalr", FMT_I_JALR, 0x67, 0x0, 0},

    /* S-type: "rs2, imm(rs1)" */
    {"sb", FMT_S, 0x23, 0x0, 0},
    {"sh", FMT_S, 0x23, 0x1, 0},
    {"sw", FMT_S, 0x23, 0x2, 0},

    /* B-type: "rs1, rs2, label" */
    {"beq",  FMT_B, 0x63, 0x0, 0},
    {"bne",  FMT_B, 0x63, 0x1, 0},
    {"blt",  FMT_B, 0x63, 0x4, 0},
    {"bge",  FMT_B, 0x63, 0x5, 0},
    {"bltu", FMT_B, 0x63, 0x6, 0},
    {"bgeu", FMT_B, 0x63, 0x7, 0},

    /* U-type: "rd, imm20" */
    {"lui",   FMT_U, 0x37, 0, 0},
    {"auipc", FMT_U, 0x17, 0, 0},

    /* J-type: "rd, label" */
    {"jal", FMT_J, 0x6F, 0, 0},

    /* directive */
    {".word", FMT_WORD, 0, 0, 0},

    {NULL, FMT_R, 0, 0, 0}
};

typedef struct {
    char name[128];
    uint32_t address;
} symbol_t;

static symbol_t symtab[MAX_SYMS];
static int nsyms = 0;

static char *lines[MAX_LINES];
static int nlines = 0;

static uint32_t output[MAX_LINES];
static int nwords = 0;

static int had_error = 0;

static void asm_error(int lineno, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "line %d: ", lineno);
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
    had_error = 1;
}

/* ---------- register name parsing ---------- */

static const char *ABI_NAMES[32] = {
    "zero","ra","sp","gp","tp","t0","t1","t2",
    "s0","s1","a0","a1","a2","a3","a4","a5",
    "a6","a7","s2","s3","s4","s5","s6","s7",
    "s8","s9","s10","s11","t3","t4","t5","t6"
};

static int parse_reg(const char *tok) {
    if (tok[0] == 'x' && isdigit((unsigned char)tok[1])) {
        int n = atoi(tok + 1);
        if (n >= 0 && n <= 31) return n;
    }
    for (int i = 0; i < 32; i++) {
        if (strcmp(tok, ABI_NAMES[i]) == 0) return i;
        if (strcmp(tok, "fp") == 0) return 8; /* s0/fp alias */
    }
    return -1;
}

/* ---------- tokenizing helpers ---------- */

static void strip_comment(char *line) {
    for (char *p = line; *p; p++) {
        if (*p == '#' || *p == ';') { *p = '\0'; break; }
    }
}

static void trim(char *s) {
    char *start = s;
    while (isspace((unsigned char)*start)) start++;
    memmove(s, start, strlen(start) + 1);
    int len = (int)strlen(s);
    while (len > 0 && isspace((unsigned char)s[len - 1])) { s[len - 1] = '\0'; len--; }
}

/* splits "  a , b , c  " into trimmed operand strings */
static int split_operands(char *s, char *out[], int max) {
    int n = 0;
    char *tok = strtok(s, ",");
    while (tok && n < max) {
        trim(tok);
        out[n++] = tok;
        tok = strtok(NULL, ",");
    }
    return n;
}

/* parses "imm(reg)" -> imm value and reg number */
static int parse_offset_reg(const char *s, int *imm_out, int *reg_out) {
    char imm_str[64], reg_str[32];
    const char *paren = strchr(s, '(');
    if (!paren) return 0;
    size_t imm_len = paren - s;
    if (imm_len >= sizeof(imm_str)) return 0;
    strncpy(imm_str, s, imm_len);
    imm_str[imm_len] = '\0';
    trim(imm_str);

    const char *close = strchr(paren, ')');
    if (!close) return 0;
    size_t reg_len = close - paren - 1;
    if (reg_len >= sizeof(reg_str)) return 0;
    strncpy(reg_str, paren + 1, reg_len);
    reg_str[reg_len] = '\0';
    trim(reg_str);

    *imm_out = (int)strtol(imm_str, NULL, 0);
    *reg_out = parse_reg(reg_str);
    return *reg_out >= 0;
}

/* looks up a label; returns 1 and sets *addr if found */
static int lookup_symbol(const char *name, uint32_t *addr) {
    for (int i = 0; i < nsyms; i++) {
        if (strcmp(symtab[i].name, name) == 0) { *addr = symtab[i].address; return 1; }
    }
    return 0;
}

/* an operand is either a decimal/hex literal or a label name */
static int resolve_imm_or_label(const char *tok, uint32_t cur_addr, int pc_relative, int *out) {
    if (isdigit((unsigned char)tok[0]) || (tok[0] == '-' && isdigit((unsigned char)tok[1]))) {
        *out = (int)strtol(tok, NULL, 0);
        return 1;
    }
    uint32_t addr;
    if (lookup_symbol(tok, &addr)) {
        *out = pc_relative ? (int)(addr - cur_addr) : (int)addr;
        return 1;
    }
    return 0;
}

static const instr_def_t *find_instr(const char *mnemonic) {
    for (int i = 0; INSTR_TABLE[i].mnemonic; i++) {
        if (strcmp(INSTR_TABLE[i].mnemonic, mnemonic) == 0) return &INSTR_TABLE[i];
    }
    return NULL;
}

/* ---------- pass 1: build symbol table, compute addresses ---------- */

static void pass1(void) {
    uint32_t addr = 0;
    for (int i = 0; i < nlines; i++) {
        char buf[MAX_LINE];
        strncpy(buf, lines[i], MAX_LINE - 1);
        buf[MAX_LINE - 1] = '\0';
        strip_comment(buf);
        trim(buf);
        if (buf[0] == '\0') continue;

        /* a line may be "label:" alone, or "label: instr ..." */
        char *colon = strchr(buf, ':');
        if (colon) {
            *colon = '\0';
            char label[128];
            strncpy(label, buf, sizeof(label) - 1);
            label[sizeof(label) - 1] = '\0';
            trim(label);
            if (nsyms >= MAX_SYMS) { asm_error(i + 1, "too many labels"); continue; }
            strncpy(symtab[nsyms].name, label, sizeof(symtab[nsyms].name) - 1);
            symtab[nsyms].address = addr;
            nsyms++;
            memmove(buf, colon + 1, strlen(colon + 1) + 1);
            trim(buf);
            if (buf[0] == '\0') continue; /* label-only line, no instruction after it */
        }
        addr += 4; /* every remaining line is one instruction or one .word */
    }
}

/* ---------- pass 2: encode ---------- */

static void encode_line(const char *body, uint32_t addr, int lineno) {
    char buf[MAX_LINE];
    strncpy(buf, body, MAX_LINE - 1);
    buf[MAX_LINE - 1] = '\0';

    char *mnemonic = strtok(buf, " \t");
    if (!mnemonic) return;
    char *rest = strtok(NULL, "\n");
    char restbuf[MAX_LINE];
    restbuf[0] = '\0';
    if (rest) { strncpy(restbuf, rest, MAX_LINE - 1); restbuf[MAX_LINE-1]='\0'; }

    const instr_def_t *def = find_instr(mnemonic);
    if (!def) { asm_error(lineno, "unknown mnemonic '%s'", mnemonic); output[nwords++] = 0; return; }

    char *ops[8];
    int n;
    uint32_t word = 0;

    switch (def->fmt) {
        case FMT_R: {
            n = split_operands(restbuf, ops, 8);
            if (n != 3) { asm_error(lineno, "%s needs 3 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]), rs1 = parse_reg(ops[1]), rs2 = parse_reg(ops[2]);
            if (rd < 0 || rs1 < 0 || rs2 < 0) { asm_error(lineno, "bad register"); break; }
            word = (def->funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (def->funct3 << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_I: {
            n = split_operands(restbuf, ops, 8);
            if (n != 3) { asm_error(lineno, "%s needs 3 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]), rs1 = parse_reg(ops[1]);
            int imm;
            if (rd < 0 || rs1 < 0 || !resolve_imm_or_label(ops[2], addr, 0, &imm)) {
                asm_error(lineno, "bad operand"); break;
            }
            word = ((imm & 0xFFF) << 20) | (rs1 << 15) | (def->funct3 << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_I_SHIFT: {
            n = split_operands(restbuf, ops, 8);
            if (n != 3) { asm_error(lineno, "%s needs 3 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]), rs1 = parse_reg(ops[1]);
            int shamt = (int)strtol(ops[2], NULL, 0);
            if (rd < 0 || rs1 < 0 || shamt < 0 || shamt > 31) { asm_error(lineno, "bad operand"); break; }
            word = (def->funct7 << 25) | (shamt << 20) | (rs1 << 15) | (def->funct3 << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_I_LOAD: {
            n = split_operands(restbuf, ops, 8);
            if (n != 2) { asm_error(lineno, "%s needs 2 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]);
            int imm, rs1;
            if (rd < 0 || !parse_offset_reg(ops[1], &imm, &rs1)) { asm_error(lineno, "bad operand"); break; }
            word = ((imm & 0xFFF) << 20) | (rs1 << 15) | (def->funct3 << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_I_JALR: {
            n = split_operands(restbuf, ops, 8);
            if (n != 3) { asm_error(lineno, "%s needs 3 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]), rs1 = parse_reg(ops[1]);
            int imm;
            if (rd < 0 || rs1 < 0 || !resolve_imm_or_label(ops[2], addr, 0, &imm)) {
                asm_error(lineno, "bad operand"); break;
            }
            word = ((imm & 0xFFF) << 20) | (rs1 << 15) | (def->funct3 << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_S: {
            n = split_operands(restbuf, ops, 8);
            if (n != 2) { asm_error(lineno, "%s needs 2 operands", mnemonic); break; }
            int rs2 = parse_reg(ops[0]);
            int imm, rs1;
            if (rs2 < 0 || !parse_offset_reg(ops[1], &imm, &rs1)) { asm_error(lineno, "bad operand"); break; }
            uint32_t imm11_5 = (imm >> 5) & 0x7F, imm4_0 = imm & 0x1F;
            word = (imm11_5 << 25) | (rs2 << 20) | (rs1 << 15) | (def->funct3 << 12) | (imm4_0 << 7) | def->opcode;
            break;
        }
        case FMT_B: {
            n = split_operands(restbuf, ops, 8);
            if (n != 3) { asm_error(lineno, "%s needs 3 operands", mnemonic); break; }
            int rs1 = parse_reg(ops[0]), rs2 = parse_reg(ops[1]);
            int imm;
            if (rs1 < 0 || rs2 < 0 || !resolve_imm_or_label(ops[2], addr, 1, &imm)) {
                asm_error(lineno, "bad operand"); break;
            }
            uint32_t b12 = (imm >> 12) & 0x1, b11 = (imm >> 11) & 0x1;
            uint32_t b10_5 = (imm >> 5) & 0x3F, b4_1 = (imm >> 1) & 0xF;
            word = (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) |
                   (def->funct3 << 12) | (b4_1 << 8) | (b11 << 7) | def->opcode;
            break;
        }
        case FMT_U: {
            n = split_operands(restbuf, ops, 8);
            if (n != 2) { asm_error(lineno, "%s needs 2 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]);
            int imm;
            if (rd < 0 || !resolve_imm_or_label(ops[1], addr, 0, &imm)) { asm_error(lineno, "bad operand"); break; }
            word = ((uint32_t)imm << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_J: {
            n = split_operands(restbuf, ops, 8);
            if (n != 2) { asm_error(lineno, "%s needs 2 operands", mnemonic); break; }
            int rd = parse_reg(ops[0]);
            int imm;
            if (rd < 0 || !resolve_imm_or_label(ops[1], addr, 1, &imm)) { asm_error(lineno, "bad operand"); break; }
            uint32_t b20 = (imm >> 20) & 0x1, b19_12 = (imm >> 12) & 0xFF;
            uint32_t b11 = (imm >> 11) & 0x1, b10_1 = (imm >> 1) & 0x3FF;
            word = (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | def->opcode;
            break;
        }
        case FMT_WORD: {
            n = split_operands(restbuf, ops, 8);
            if (n != 1) { asm_error(lineno, ".word needs 1 operand"); break; }
            word = (uint32_t)strtoul(ops[0], NULL, 0);
            break;
        }
    }

    output[nwords++] = word;
}

static void pass2(void) {
    uint32_t addr = 0;
    for (int i = 0; i < nlines; i++) {
        char buf[MAX_LINE];
        strncpy(buf, lines[i], MAX_LINE - 1);
        buf[MAX_LINE - 1] = '\0';
        strip_comment(buf);
        trim(buf);
        if (buf[0] == '\0') continue;

        char *colon = strchr(buf, ':');
        if (colon) {
            memmove(buf, colon + 1, strlen(colon + 1) + 1);
            trim(buf);
            if (buf[0] == '\0') continue;
        }

        encode_line(buf, addr, i + 1);
        addr += 4;
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s input.s output.hex\n", argv[0]);
        return 1;
    }

    FILE *fin = fopen(argv[1], "r");
    if (!fin) { perror("open input"); return 1; }

    char linebuf[MAX_LINE];
    while (fgets(linebuf, sizeof(linebuf), fin) && nlines < MAX_LINES) {
        size_t len = strlen(linebuf);
        if (len > 0 && linebuf[len - 1] == '\n') linebuf[len - 1] = '\0';
        lines[nlines] = strdup(linebuf);
        nlines++;
    }
    fclose(fin);

    pass1();
    if (had_error) { fprintf(stderr, "pass 1 failed\n"); return 1; }

    pass2();
    if (had_error) { fprintf(stderr, "pass 2 failed\n"); return 1; }

    FILE *fout = fopen(argv[2], "w");
    if (!fout) { perror("open output"); return 1; }
    for (int i = 0; i < nwords; i++) {
        fprintf(fout, "%08x\n", output[i]);
    }
    fclose(fout);

    fprintf(stderr, "assembled %d instructions, %d symbols -> %s\n", nwords, nsyms, argv[2]);
    return 0;
}
