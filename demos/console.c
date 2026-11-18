#include "console.h"
#include "text.h"
#include "gfx.h"

/* Cursor position -- genuinely mutable state, persisting across calls.
   This is real .bss: zero-initialized globals, living in data_ram via
   link_console.ld's RAM region. data_ram already starts at all-zero on
   its own, which is exactly what .bss needs -- no separate loading step
   was required to make this work, unlike .rodata's font table. */
static int cursor_col;
static int cursor_row;
static unsigned char console_color;

void console_init(unsigned char fg_color) {
    cursor_col = 0;
    cursor_row = 0;
    console_color = fg_color;
}

static void newline(void) {
    cursor_col = 0;
    cursor_row++;
    if (cursor_row >= CONSOLE_ROWS) {
        /* No scrolling yet -- wrap back to the top rather than shifting
           the framebuffer (a real scroll means redrawing/shifting up to
           64000 pixels, the same simulation-time cost flagged for
           clear_screen() in gfx.c). Wrapping is a placeholder, not the
           real behavior a finished console would want. */
        cursor_row = 0;
    }
}

void console_putc(char c) {
    if (c == '\n') {
        newline();
        return;
    }

    if (c == 8) { /* backspace: move back one cell and blank it out,
                     rather than drawing-and-advancing like an ordinary
                     unrecognized character (which is what was happening
                     before -- backspace silently ate a cell without
                     erasing anything, looking like keys were being
                     "swallowed" rather than deleted). Doesn't handle
                     backspacing across a line boundary onto the
                     previous line -- clamped at column 0 for now.
                     Uses an explicit fill_rect, not draw_char(' ', ...)
                     -- draw_char only draws pixels where a glyph has
                     bits SET, so "drawing a space" draws nothing at
                     all and leaves the previous character's pixels
                     exactly as they were; an explicit fill is what
                     actually erases the cell. */
        if (cursor_col > 0) {
            cursor_col--;
            fill_rect(cursor_col * CONSOLE_CELL_W, cursor_row * CONSOLE_CELL_H,
                      CONSOLE_CELL_W, CONSOLE_CELL_H, 0);
        }
        return;
    }

    draw_char(cursor_col * CONSOLE_CELL_W, cursor_row * CONSOLE_CELL_H,
              c, console_color, 1);

    cursor_col++;
    if (cursor_col >= CONSOLE_COLS) {
        newline();
    }
}

void console_puts(const char *s) {
    while (*s) {
        console_putc(*s);
        s++;
    }
}

void console_clear(void) {
    clear_screen(0);
    cursor_col = 0;
    cursor_row = 0;
}