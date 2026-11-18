/* pong.c -- Pong as an RVDOS transient. No hardware access: everything is
 * a syscall (con_fill / con_gotoxy / con_puts / con_poll). You are the left
 * paddle (W/S); the right paddle is AI. Q, ESC or Ctrl+C returns to the shell. First to 7.
 */
#include "applib.h"

#define LCOL 2
#define RCOL 50
#define PH   4          /* paddle height in cells */
#define RTOP 2          /* top play row   */
#define RBOT 22         /* bottom play row */
#define WIN  7

/* Frame pace: the ball advances one cell per frame, so this sets ball
   speed. Raise to slow the game down. Tuned to match Tetris on rvemu. */
#define FRAME 150000

#define C_BG 0
#define C_FG 4          /* paddle + ball */
#define C_NET 5

static int lp, rp;              /* paddle top rows */
static int bx, by, bdx, bdy;    /* ball col/row + velocity */
static int sl, sr;              /* scores */

static void paddle(int col, int top, int color) {
    int i; for (i = 0; i < PH; i++) con_fill(col, top + i, color);
}
static void ball(int color) { con_fill(bx, by, color); }

static void show_score(void) {
    con_setcolor(C_NET);
    con_gotoxy(24, 0); con_putu((unsigned)sl);
    con_gotoxy(28, 0); con_putu((unsigned)sr);
}

static void serve(int to_right) {
    bx = 26; by = (RTOP + RBOT) / 2;
    bdx = to_right ? 1 : -1;
    bdy = rng_range(2) ? 1 : -1;
}

static void new_game(void) {
    int r;
    con_clear();
    lp = rp = (RTOP + RBOT) / 2 - PH / 2;
    sl = sr = 0;
    /* dashed net down the middle */
    con_setcolor(C_NET);
    for (r = RTOP; r <= RBOT; r += 2) con_fill(26, r, C_NET);
    paddle(LCOL, lp, C_FG);
    paddle(RCOL, rp, C_FG);
    show_score();
    serve(rng_range(2));
    ball(C_FG);
}

int pong_main(void) {
    con_setpal(C_BG, 0x000000);
    con_setpal(C_FG, 0xFFFFFF);
    con_setpal(C_NET, 0x3070A0);

    con_clear();
    con_setcolor(1);
    con_gotoxy(16, 10); con_puts("PONG   W/S MOVE   Q/ESC QUIT");
    con_gotoxy(16, 12); con_puts("PRESS ANY KEY");
    if (quit_key(seed_and_wait())) return 0;
    new_game();

    for (;;) {
        int k, old;

        k = con_poll();
        if (quit_key(k)) return 0;
        old = lp;
        if ((k == 'W' || k == 'w') && lp > RTOP) lp--;
        if ((k == 'S' || k == 's') && lp < RBOT - PH + 1) lp++;
        if (lp != old) { paddle(LCOL, old, C_BG); paddle(LCOL, lp, C_FG); }

        /* AI tracks the ball */
        old = rp;
        { int tgt = by - PH / 2;
          if (rp < tgt && rp < RBOT - PH + 1) rp++;
          else if (rp > tgt && rp > RTOP)     rp--; }
        if (rp != old) { paddle(RCOL, old, C_BG); paddle(RCOL, rp, C_FG); }

        ball(C_BG);                     /* erase */
        bx += bdx; by += bdy;
        if (by <= RTOP) { by = RTOP; bdy = -bdy; }
        if (by >= RBOT) { by = RBOT; bdy = -bdy; }

        if (bdx < 0 && bx <= LCOL + 1 && by >= lp && by <= lp + PH - 1) {
            bx = LCOL + 1; bdx = -bdx;
            if (by < lp + 1) bdy = -1; else if (by > lp + PH - 2) bdy = 1;
        }
        if (bdx > 0 && bx >= RCOL - 1 && by >= rp && by <= rp + PH - 1) {
            bx = RCOL - 1; bdx = -bdx;
            if (by < rp + 1) bdy = -1; else if (by > rp + PH - 2) bdy = 1;
        }

        if (bx < 1)  { sr++; show_score(); serve(0); }
        else if (bx > CON_COLS - 2) { sl++; show_score(); serve(1); }

        /* net cell the ball may have erased */
        if ((bx == 26) && (((by - RTOP) & 1) == 0)) {} /* leave; redrawn below */
        ball(C_FG);                     /* draw */

        if (sl >= WIN || sr >= WIN) {
            con_setcolor(2);
            con_gotoxy(20, 12);
            con_puts(sl >= WIN ? "LEFT WINS !" : "RIGHT WINS !");
            con_gotoxy(14, 14); con_puts("Q QUIT   ANY KEY AGAIN");
            gdelay(750000);
            if (quit_or_again()) return 0;
            new_game();
        }
        gdelay(FRAME);                  /* frame pace -- see FRAME above */
    }
}