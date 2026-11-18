#include "gfx.h"

/* Small shapes, deliberately kept near the top-left of the screen so a
   testbench only needs to simulate a short prefix of one frame to see
   them all -- not a rendering-technique choice, purely to keep RTL
   simulation time reasonable (see gfx.c's note on clear_screen). */

int main(void) {
    set_palette(1, 255, 0, 0);   /* red */
    set_palette(2, 0, 255, 0);   /* green */
    set_palette(3, 0, 0, 255);   /* blue */

    fill_rect(2, 2, 10, 6, 1);   /* red block,  cols 2-11,  rows 2-7  */
    draw_pixel(20, 4, 2);        /* single green pixel at (20,4)      */
    fill_rect(25, 2, 5, 5, 3);   /* blue block, cols 25-29, rows 2-6  */

    return 0;
}
