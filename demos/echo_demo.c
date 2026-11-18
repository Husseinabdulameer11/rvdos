#include "gfx.h"
#include "console.h"
#include "kbd.h"

/* The first genuinely interactive program in this project -- reads real
   keypresses and echoes them to the screen. main() never returns; there's
   no "finished" state, just an infinite read-and-echo loop. */

int main(void) {
    set_palette(1, 255, 255, 255);
    console_init(1);
    console_puts("TYPE SOMETHING:\n");

    while (1) {
        char c = kbd_getchar();
        console_putc(c);
    }

    return 0; /* unreachable */
}
