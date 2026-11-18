/* tetris.c -- Tetris as an RVDOS transient. The 10x20 well is drawn in
 * console cells via con_fill; the piece table is const (.rodata). A/D move,
 * W rotate, S soft-drop, space hard-drop, Q, ESC or Ctrl+C returns to the shell.
 */
#include "applib.h"

#define BW 10
#define BH 20
#define WCOL0 21        /* well left column on the 53-wide console */
#define WROW0 2         /* well top row */

/* 7 pieces x 4 rotations x 4 cells x (dx,dy). Verified: every rotation has
   exactly 4 unique cells inside a 4x4 box. */
static const signed char shapes[7][4][4][2] = {
  {{{0,1},{1,1},{2,1},{3,1}},{{2,0},{2,1},{2,2},{2,3}},{{0,2},{1,2},{2,2},{3,2}},{{1,0},{1,1},{1,2},{1,3}}},
  {{{1,0},{2,0},{1,1},{2,1}},{{1,0},{2,0},{1,1},{2,1}},{{1,0},{2,0},{1,1},{2,1}},{{1,0},{2,0},{1,1},{2,1}}},
  {{{1,0},{0,1},{1,1},{2,1}},{{1,0},{1,1},{2,1},{1,2}},{{0,1},{1,1},{2,1},{1,2}},{{1,0},{0,1},{1,1},{1,2}}},
  {{{1,0},{2,0},{0,1},{1,1}},{{1,0},{1,1},{2,1},{2,2}},{{1,1},{2,1},{0,2},{1,2}},{{0,0},{0,1},{1,1},{1,2}}},
  {{{0,0},{1,0},{1,1},{2,1}},{{2,0},{1,1},{2,1},{1,2}},{{0,1},{1,1},{1,2},{2,2}},{{1,0},{0,1},{1,1},{0,2}}},
  {{{0,0},{0,1},{1,1},{2,1}},{{1,0},{2,0},{1,1},{1,2}},{{0,1},{1,1},{2,1},{2,2}},{{1,0},{1,1},{0,2},{1,2}}},
  {{{2,0},{0,1},{1,1},{2,1}},{{1,0},{1,1},{1,2},{2,2}},{{0,1},{1,1},{2,1},{0,2}},{{0,0},{1,0},{1,1},{1,2}}},
};

static unsigned char board[BH][BW];
static int cur, rot, px, py, level, lines;

static void cell(int x, int y, int color) { con_fill(WCOL0 + x, WROW0 + y, color); }

static int fits(int p, int r, int ox, int oy) {
    int i;
    for (i = 0; i < 4; i++) {
        int x = ox + shapes[p][r][i][0], y = oy + shapes[p][r][i][1];
        if (x < 0 || x >= BW || y >= BH) return 0;
        if (y >= 0 && board[y][x]) return 0;
    }
    return 1;
}

static void draw_field(void) {
    int x, y, i;
    for (y = 0; y < BH; y++)
        for (x = 0; x < BW; x++)
            cell(x, y, board[y][x]);                 /* 0 = bg, else colour */
    for (i = 0; i < 4; i++) {
        int cx = px + shapes[cur][rot][i][0], cy = py + shapes[cur][rot][i][1];
        if (cy >= 0) cell(cx, cy, cur + 1);
    }
}

static void lock_and_clear(void) {
    int i, x, y, w, dst;
    for (i = 0; i < 4; i++) {
        int cx = px + shapes[cur][rot][i][0], cy = py + shapes[cur][rot][i][1];
        if (cy >= 0) board[cy][cx] = (unsigned char)(cur + 1);
    }
    dst = BH - 1;
    for (y = BH - 1; y >= 0; y--) {
        int full = 1;
        for (x = 0; x < BW; x++) if (!board[y][x]) { full = 0; break; }
        if (!full) {
            if (dst != y) for (x = 0; x < BW; x++) board[dst][x] = board[y][x];
            dst--;
        } else {
            lines++;
            if (level < 18) level++;
        }
    }
    for (y = dst; y >= 0; y--) for (w = 0; w < BW; w++) board[y][w] = 0;
}

static void spawn(void) { cur = (int)rng_range(7); rot = 0; px = 3; py = 0; }

static void show_stats(void) {
    con_setcolor(1);
    con_gotoxy(2, 2);  con_puts("LINES");
    con_gotoxy(2, 3);  con_putu((unsigned)lines);
}

static void frame(void) {
    int y;
    con_setcolor(8);
    for (y = 0; y < BH; y++) { cell(-1, y, 8); cell(BW, y, 8); }
}

static void new_game(void) {
    int x, y;
    con_clear();
    for (y = 0; y < BH; y++) for (x = 0; x < BW; x++) board[y][x] = 0;
    level = 1; lines = 0;
    frame();
    show_stats();
    spawn();
    draw_field();
}

int tetris_main(void) {
    int grav = 0;
    con_setpal(0, 0x0A0A14);
    con_setpal(1, 0x00F0F0); con_setpal(2, 0xF0F000); con_setpal(3, 0xB000DC);
    con_setpal(4, 0x00DC00); con_setpal(5, 0xE60000); con_setpal(6, 0x0050F0);
    con_setpal(7, 0xF09600); con_setpal(8, 0xC8C8C8);

    con_clear();
    con_setcolor(1);
    con_gotoxy(12, 10); con_puts("TETRIS  A/D W S  SPACE=DROP  Q/ESC");
    con_gotoxy(12, 12); con_puts("PRESS ANY KEY");
    if (quit_key(seed_and_wait())) return 0;
    new_game();

    for (;;) {
        int changed = 0, sub;

        for (sub = 0; sub < 6; sub++) {
            int k = con_poll();
            if (quit_key(k)) return 0;
            if      ((k == 'A' || k == 'a') && fits(cur, rot, px - 1, py)) { px--; changed = 1; }
            else if ((k == 'D' || k == 'd') && fits(cur, rot, px + 1, py)) { px++; changed = 1; }
            else if  (k == 'W' || k == 'w') { int nr = (rot + 1) & 3; if (fits(cur, nr, px, py)) { rot = nr; changed = 1; } }
            else if ((k == 'S' || k == 's') && fits(cur, rot, px, py + 1)) { py++; changed = 1; }
            else if  (k == ' ') { while (fits(cur, rot, px, py + 1)) py++; changed = 1; grav = 1000; }
            gdelay(9000);
        }

        if (++grav >= 20 - level) {
            grav = 0;
            if (fits(cur, rot, px, py + 1)) py++;
            else {
                lock_and_clear();
                show_stats();
                spawn();
                if (!fits(cur, rot, px, py)) {           /* game over */
                    int f;
                    for (f = 0; f < 8; f++) {
                        int yy, xx;
                        for (yy = 0; yy < BH; yy++) for (xx = 0; xx < BW; xx++)
                            cell(xx, yy, (f & 1) ? 8 : 0);
                        gdelay(180000);
                    }
                    con_setcolor(2);
                    con_gotoxy(WCOL0, WROW0 + BH / 2); con_puts("GAME OVER");
                    con_gotoxy(WCOL0, WROW0 + BH / 2 + 2); con_puts("Q = QUIT");
                    con_gotoxy(WCOL0, WROW0 + BH / 2 + 3); con_puts("KEY=AGAIN");
                    gdelay(700000);
                    if (quit_or_again()) return 0;
                    new_game();
                    grav = 0;
                    continue;
                }
            }
            changed = 1;
        }
        if (changed) draw_field();
    }
}
