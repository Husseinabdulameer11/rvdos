#ifndef CONSOLE_H
#define CONSOLE_H

/* Fixed-grid text-mode console, CP/M/DOS-terminal style, on top of the
   pixel-level text.c/gfx.c. At scale=1 (6x8 pixel cells: 5x7 glyph + 1px
   spacing each direction), the 320x200 framebuffer gives a 53-column x
   25-row grid. */

#define CONSOLE_COLS 53
#define CONSOLE_ROWS 25
#define CONSOLE_CELL_W 6
#define CONSOLE_CELL_H 8

void console_init(unsigned char fg_color);
void console_putc(char c);
void console_puts(const char *s);
void console_clear(void);

#endif
