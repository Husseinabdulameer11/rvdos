#include "text.h"
#include "font.h"
#include "gfx.h"

/* scale=1 draws the raw 5x7 glyph; scale=N draws each font pixel as an
   NxN block, since a single unscaled 5x7 glyph is tiny on a 320x200
   screen. */
void draw_char(int x, int y, char c, unsigned char color, int scale) {
    const unsigned char *rows = font_lookup(c);
    for (int row = 0; row < 7; row++) {
        unsigned char bits = rows[row];
        for (int col = 0; col < 5; col++) {
            if (bits & (1 << (4 - col))) {
                fill_rect(x + col * scale, y + row * scale, scale, scale, color);
            }
        }
    }
}

void draw_string(int x, int y, const char *s, unsigned char color, int scale) {
    int cursor_x = x;
    while (*s) {
        draw_char(cursor_x, y, *s, color, scale);
        cursor_x += (5 + 1) * scale; /* glyph width + 1px spacing, scaled */
        s++;
    }
}
