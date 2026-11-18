/* snake.c -- Snake as an RVDOS transient. Grid is the console cell grid;
 * body cells are stored in two small arrays and self-collision is found by
 * scanning them (no 1000-byte occupancy grid -- keeps .bss tiny). W/A/S/D
 * steer, Q, ESC or Ctrl+C returns to the shell.
 */
#include "applib.h"

/* play interior: cols 1..CON_COLS-2, rows 1..CON_ROWS-2 (border all round) */
#define X0 1
#define Y0 1
#define X1 (CON_COLS - 2)
#define Y1 (CON_ROWS - 2)
#define MAX_LEN 96

/* Per-step pace: the snake advances one cell every 8 * STEP_TICK delay
   units. Raise to slow the snake, lower to speed it up. Tuned to match
   Tetris's feel on rvemu; scale all three games' constants together when
   you move to 25 MHz hardware. */
#define STEP_TICK 40000

#define C_BG   0
#define C_SNK  6
#define C_HEAD 9
#define C_FOOD 7
#define C_WALL 8

static unsigned char sx[MAX_LEN], sy[MAX_LEN];
static int len, dx, dy;
static unsigned char fx, fy;

static int on_snake(int x, int y) {
    int i; for (i = 0; i < len; i++) if (sx[i] == x && sy[i] == y) return 1;
    return 0;
}
static void place_food(void) {
    do {
        fx = (unsigned char)(X0 + rng_range(X1 - X0 + 1));
        fy = (unsigned char)(Y0 + rng_range(Y1 - Y0 + 1));
    } while (on_snake(fx, fy));
    con_fill(fx, fy, C_FOOD);
}

static void new_game(void) {
    int i;
    con_clear();
    for (i = X0 - 1; i <= X1 + 1; i++) { con_fill(i, Y0 - 1, C_WALL); con_fill(i, Y1 + 1, C_WALL); }
    for (i = Y0 - 1; i <= Y1 + 1; i++) { con_fill(X0 - 1, i, C_WALL); con_fill(X1 + 1, i, C_WALL); }
    con_setcolor(1);
    con_gotoxy(2, 0); con_puts("SNAKE");

    len = 4;
    for (i = 0; i < len; i++) { sx[i] = (unsigned char)(10 - i); sy[i] = 12; }
    dx = 1; dy = 0;
    for (i = 0; i < len; i++) con_fill(sx[i], sy[i], i == 0 ? C_HEAD : C_SNK);
    place_food();
}

int snake_main(void) {
    con_setpal(C_BG,   0x000000);
    con_setpal(C_SNK,  0x00C000);
    con_setpal(C_HEAD, 0x80FF80);
    con_setpal(C_FOOD, 0xE03030);
    con_setpal(C_WALL, 0x4040A0);

    con_clear();
    con_setcolor(1);
    con_gotoxy(14, 10); con_puts("SNAKE   WASD   Q/ESC QUIT");
    con_gotoxy(14, 12); con_puts("PRESS ANY KEY");
    if (quit_key(seed_and_wait())) return 0;
    new_game();

    for (;;) {
        int nx, ny, i, grew = 0, s;

        for (s = 0; s < 8; s++) {
            int k = con_poll();
            if (quit_key(k)) return 0;
            if ((k == 'W' || k == 'w') && dy == 0) { dx = 0; dy = -1; }
            else if ((k == 'S' || k == 's') && dy == 0) { dx = 0; dy = 1; }
            else if ((k == 'A' || k == 'a') && dx == 0) { dx = -1; dy = 0; }
            else if ((k == 'D' || k == 'd') && dx == 0) { dx = 1; dy = 0; }
            gdelay(STEP_TICK);
        }

        nx = sx[0] + dx; ny = sy[0] + dy;

        if (nx < X0 || nx > X1 || ny < Y0 || ny > Y1 || on_snake(nx, ny)) {
            int f;
            for (f = 0; f < 6; f++) {
                for (i = 0; i < len; i++) con_fill(sx[i], sy[i], (f & 1) ? C_FOOD : C_SNK);
                gdelay(150000);
            }
            con_setcolor(2);
            con_gotoxy(20, 12); con_puts("GAME OVER");
            con_gotoxy(14, 14); con_puts("Q QUIT   ANY KEY AGAIN");
            gdelay(600000);
            if (quit_or_again()) return 0;
            new_game();
            continue;
        }

        if (nx == fx && ny == fy && len < MAX_LEN) grew = 1;
        if (!grew) con_fill(sx[len - 1], sy[len - 1], C_BG);   /* erase tail */

        if (grew) len++;
        for (i = len - 1; i > 0; i--) { sx[i] = sx[i - 1]; sy[i] = sy[i - 1]; }
        sx[0] = (unsigned char)nx; sy[0] = (unsigned char)ny;

        con_fill(sx[1], sy[1], C_SNK);     /* old head -> body */
        con_fill(sx[0], sy[0], C_HEAD);
        if (grew) place_food();
    }
}