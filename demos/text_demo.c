#include "gfx.h"
#include "text.h"

int main(void) {
    set_palette(1, 255, 255, 255); /* white */
    draw_string(20, 20, "RISC-V", 1, 3); /* scale=3: each font pixel -> 3x3 block */
    return 0;
}
