#include "gfx.h"

void set_palette(unsigned char index, unsigned char r, unsigned char g, unsigned char b) {
    PAL_BASE[index] = ((unsigned int)r << 16) | ((unsigned int)g << 8) | (unsigned int)b;
}

void draw_pixel(int x, int y, unsigned char color) {
    if (x < 0 || x >= FB_WIDTH || y < 0 || y >= FB_HEIGHT) return;
    FB_BASE[y * FB_WIDTH + x] = color;
}

void fill_rect(int x, int y, int w, int h, unsigned char color) {
    for (int j = 0; j < h; j++) {
        for (int i = 0; i < w; i++) {
            draw_pixel(x + i, y + j, color);
        }
    }
}

void draw_hline(int x, int y, int w, unsigned char color) {
    for (int i = 0; i < w; i++) {
        draw_pixel(x + i, y, color);
    }
}

void draw_vline(int x, int y, int h, unsigned char color) {
    for (int j = 0; j < h; j++) {
        draw_pixel(x, y + j, color);
    }
}

void draw_rect(int x, int y, int w, int h, unsigned char color) {
    draw_hline(x, y, w, color);
    draw_hline(x, y + h - 1, w, color);
    draw_vline(x, y, h, color);
    draw_vline(x + w - 1, y, h, color);
}

/* Every one of these 64000 writes is a real store instruction executed by
   the simulated CPU -- at roughly 5-10 cycles per pixel (loop overhead,
   address calc, bounds check), a full clear_screen() is ~400,000-600,000
   simulated cycles on its own, before the video scan even starts. Fine on
   real hardware; expensive in RTL simulation. The demo program below
   deliberately avoids calling this, to keep the testbench's simulated
   time reasonable -- draws a handful of small shapes instead. */
void clear_screen(unsigned char color) {
    fill_rect(0, 0, FB_WIDTH, FB_HEIGHT, color);
}
