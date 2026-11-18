#include "gfx.h"
#include "text.h"

/* Same font, three sizes, to show the scale parameter genuinely controls
   density -- scale=1 is the font's native 5x7 pixels (dense enough for
   a real text-mode console: at 320x200 with 1px glyph spacing, that's a
   6x8 character cell, giving 53 columns x 25 rows on screen). scale=3
   (the loading-screen size from before) is shown for comparison. */

int main(void) {
    set_palette(1, 255, 255, 255);

    draw_string(4, 4,  "RISC-V", 1, 1); /* native size: 6px tall per line */
    draw_string(4, 16, "RISC-V", 1, 2); /* 12px tall per line */
    draw_string(4, 32, "RISC-V", 1, 3); /* the loading-screen size */

    return 0;
}
