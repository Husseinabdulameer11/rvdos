#include "boot_logo.h"
#include "../gfx/gfx.h"
#include "../text/text.h"

/* A simple procedural boot logo -- a stylized chip icon (body + pins,
   like a classic DIP package) plus a "RISC-V" wordmark underneath.
   Built entirely from gfx.c's existing primitives -- no external image
   file or converter needed, unlike a real photo/logo would require. */

static void draw_chip(int cx, int cy) {
    int w = 60, h = 40;
    int x = cx - w/2, y = cy - h/2;

    int pin_w = 4, pin_h = 3, gap = 8;
    for (int i = 0; i < 5; i++) {
        int py = y + 4 + i * gap;
        fill_rect(x - pin_w, py, pin_w, pin_h, LOGO_PIN_COLOR);
        fill_rect(x + w, py, pin_w, pin_h, LOGO_PIN_COLOR);
    }
    for (int i = 0; i < 5; i++) {
        int px = x + 4 + i * gap;
        fill_rect(px, y - pin_h, pin_h, pin_h, LOGO_PIN_COLOR);
        fill_rect(px, y + h, pin_h, pin_h, LOGO_PIN_COLOR);
    }

    fill_rect(x, y, w, h, LOGO_CHIP_COLOR);
    fill_rect(cx - 3, y - 1, 6, 3, LOGO_BG_COLOR); /* orientation notch */
}

void draw_boot_logo(void) {
    set_palette(LOGO_BG_COLOR, 10, 10, 40);
    set_palette(LOGO_CHIP_COLOR, 200, 200, 200);
    set_palette(LOGO_PIN_COLOR, 230, 190, 60);
    set_palette(LOGO_TEXT_COLOR, 255, 255, 255);

    clear_screen(LOGO_BG_COLOR);
    draw_chip(160, 80);
    draw_string(70, 140, "RISC-V", LOGO_TEXT_COLOR, 3);
}
