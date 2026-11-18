#include "console.h"
#include "gfx.h"

int main(void) {
    set_palette(1, 255, 255, 255); /* white -- console_init only picks
                                       WHICH palette entry to use, it
                                       doesn't set what that entry IS */
    console_init(1);
    console_puts("RISC-V BOOT\n");
    console_puts("CPU: RV32IM\n");
    console_puts("MEM: 1024 BYTES\n");
    console_puts("READY.\n");
    return 0;
}
