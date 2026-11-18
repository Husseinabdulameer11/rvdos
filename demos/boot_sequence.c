#include "boot_logo.h"
#include "../gfx/gfx.h"
#include "../text/console.h"
#include "../kbd/kbd.h"

/* Logo -> delay -> transition into an interactive console. This is a
   crude busy-wait delay, not a real timed pause -- there's no timer
   peripheral on this CPU yet, so "how long the logo shows" is really
   "how many loop iterations happen to take," which will feel
   completely different in wall-clock terms on real hardware, in this
   emulator (native speed), and under GHDL (slow simulated speed). A
   real timer would be the honest fix; this is a placeholder that at
   least demonstrates the boot-sequence STRUCTURE. */
static void delay(long iterations) {
    for (volatile long i = 0; i < iterations; i++) {
        /* nothing -- just burning cycles */
    }
}

int main(void) {
    draw_boot_logo();
    delay(3000000);

    clear_screen(0);
    set_palette(5, 255, 255, 255); /* console text color, a fresh
                                       palette index separate from the
                                       logo's -- the logo's indices
                                       (1-4) are still technically set
                                       but no longer visible once the
                                       screen is cleared */
    console_init(5);
    console_puts("RISC-V SYSTEM READY\n");
    console_puts("TYPE SOMETHING:\n");

    while (1) {
        char c = kbd_getchar();
        console_putc(c);
    }

    return 0; /* unreachable */
}
