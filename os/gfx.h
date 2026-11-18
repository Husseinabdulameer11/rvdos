#ifndef GFX_H
#define GFX_H

/* Memory-mapped framebuffer + palette, matching cpu_top.vhd's address map:
   FB_BASE  = 0x00010000, 320x200 bytes, one byte = one pixel (palette index)
   PAL_BASE = 0x00020000, 256 entries, 32-bit each (low 24 bits = R:G:B) */

#define FB_WIDTH  320
#define FB_HEIGHT 200

#define FB_BASE  ((volatile unsigned char *)0x00010000)
#define PAL_BASE ((volatile unsigned int  *)0x00020000)

void set_palette(unsigned char index, unsigned char r, unsigned char g, unsigned char b);
void draw_pixel(int x, int y, unsigned char color);
void fill_rect(int x, int y, int w, int h, unsigned char color);
void draw_hline(int x, int y, int w, unsigned char color);
void draw_vline(int x, int y, int h, unsigned char color);
void draw_rect(int x, int y, int w, int h, unsigned char color); /* outline only */
void clear_screen(unsigned char color); /* touches all 64000 pixels -- slow in simulation, see gfx.c */

#endif
