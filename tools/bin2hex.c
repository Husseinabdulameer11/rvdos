/* bin2hex — converts a raw little-endian binary (as produced by
 * `objcopy -O binary`) into one 32-bit word per line, 8 hex digits, no
 * "0x" prefix -- the same format rvasm.c emits and instr_rom_hex.vhd's
 * textio-based loader reads. RISC-V is little-endian, so byte 0 of the
 * input file is bits [7:0] of the first word, not the top byte -- getting
 * this backwards produces a byte-swapped, completely non-functional
 * instruction stream that still "looks like" plausible hex if you don't
 * check closely, so this conversion direction matters.
 */
#include <stdio.h>
#include <stdint.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s input.bin output.hex\n", argv[0]);
        return 1;
    }
    FILE *fin = fopen(argv[1], "rb");
    if (!fin) { perror("open input"); return 1; }
    FILE *fout = fopen(argv[2], "w");
    if (!fout) { perror("open output"); return 1; }

    int b0, b1, b2, b3;
    int nwords = 0;
    while ((b0 = fgetc(fin)) != EOF) {
        b1 = fgetc(fin); if (b1 == EOF) b1 = 0;
        b2 = fgetc(fin); if (b2 == EOF) b2 = 0;
        b3 = fgetc(fin); if (b3 == EOF) b3 = 0;
        uint32_t word = (uint32_t)b0 | ((uint32_t)b1 << 8) |
                         ((uint32_t)b2 << 16) | ((uint32_t)b3 << 24);
        fprintf(fout, "%08x\n", word);
        nwords++;
    }
    fclose(fin);
    fclose(fout);
    fprintf(stderr, "%d words -> %s\n", nwords, argv[2]);
    return 0;
}
