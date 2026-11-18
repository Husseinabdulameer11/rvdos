#ifndef APPLIB_H
#define APPLIB_H
/* Helpers every transient uses, layered strictly on top of the syscall
   ABI -- no hardware access anywhere in here. Included by the games only,
   not by the OS. */
#include "syscall.h"

/* --- thin, readable wrappers over the raw syscall vector --------------- */
static inline void con_clear(void)                 { sys(SYS_CLEAR, 0, 0, 0); }
static inline void con_putc(char c)                { sys(SYS_PUTC, (int)(unsigned char)c, 0, 0); }
static inline void con_puts(const char *s)         { sys(SYS_PUTS, (long)s, 0, 0); }
static inline void con_gotoxy(int col, int row)    { sys(SYS_GOTOXY, col, row, 0); }
static inline void con_fill(int col, int row, int color) { sys(SYS_FILLCELL, col, row, color); }
static inline void con_setcolor(int color)         { sys(SYS_SETCOLOR, color, 0, 0); }
static inline void con_setpal(int idx, int rgb)    { sys(SYS_SETPAL, idx, rgb, 0); }
static inline int  con_poll(void)                  { return (int)sys(SYS_POLL, 0, 0, 0); }
static inline int  con_getc(void)                  { return (int)sys(SYS_GETC, 0, 0, 0); }
static inline int  con_break(void)                 { return (int)sys(SYS_BREAK, 0, 0, 0); }
static inline void con_colors(int fg, int bg)      { sys(SYS_SETCOLOR, fg, bg, 0); }
static inline void con_putcell(int col, int row, int ch, int fg, int bg) {
    sys(SYS_PUTCELL, col | (row << 8), (int)(unsigned char)ch, fg | (bg << 8));
}
static inline int  con_getline(char *buf, int size) { return (int)sys(SYS_GETLINE, (long)buf, size, 0); }
static inline const char *os_args(void)            { return (const char *)sys(SYS_ARGS, 0, 0, 0); }
static inline unsigned char *os_tpa(void)          { return (unsigned char *)sys(SYS_TPA, 0, 0, 0); }
static inline unsigned int   os_tpa_size(void)     { return (unsigned int)sys(SYS_TPA, 1, 0, 0); }
static inline unsigned int   os_random(void)       { return (unsigned int)sys(SYS_RANDOM, 0, 0, 0); }

/* --- files on drive A: (the RAM disk) ---------------------------------- */
static inline int  f_find(const char *name)        { return (int)sys(SYS_FFIND, (long)name, 0, 0); }
static inline int  f_size(int id)                  { return (int)sys(SYS_FSIZE, id, 0, 0); }
static inline const char *f_data(int id)           { return (const char *)sys(SYS_FDATA, id, 0, 0); }
static inline int  f_write(const char *name, const void *p, int n) { return (int)sys(SYS_FWRITE, (long)name, (long)p, n); }
static inline int  f_delete(const char *name)      { return (int)sys(SYS_FDELETE, (long)name, 0, 0); }
static inline int  f_free(void)                    { return (int)sys(SYS_FFREE, 0, 0, 0); }

/* --- pixels ------------------------------------------------------------ */
static inline void g_pixel(int x, int y, int c)    { sys(SYS_PIXEL, x, y, c); }
static inline void g_rect(int x, int y, int w, int h, int c) {
    sys(SYS_RECT, (x & 0xFFFF) | (y << 16), (w & 0xFFFF) | (h << 16), c);
}
static inline int  g_getpix(int x, int y)          { return (int)sys(SYS_GETPIX, x, y, 0); }

/* print an unsigned int at the cursor. No `% 10` / `/ 10`: gcc compiles
   those to divu/remu on RV32IM, and this core has no divider. Subtracting
   powers of ten needs only compares and subtracts. */
static inline void con_putu(unsigned int v) {
    static const unsigned int p10[] = { 1000000000u, 100000000u, 10000000u, 1000000u,
                                        100000u, 10000u, 1000u, 100u, 10u, 1u };
    int i, started = 0;
    for (i = 0; i < 10; i++) {
        int d = 0;
        while (v >= p10[i]) { v -= p10[i]; d++; }
        if (d || started || i == 9) { con_putc((char)('0' + d)); started = 1; }
    }
}

/* --- timing: no timer peripheral exists, so burn cycles. Pure CPU loop,
   touches nothing -- a transient is allowed to spend its own time slice.
   Tune the call sites ONCE on real hardware: bigger = slower. -------- */
static inline void gdelay(volatile int n) { while (n > 0) n--; }

/* --- RNG: LCG; rng_range uses mulhu (high half of a 64-bit multiply)
   instead of a modulo, since this core has mul but no divide. --------- */
static unsigned int rng_state __attribute__((unused));   /* zero-init (.bss); seeded at runtime */
static inline unsigned int rng_next(void) {
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state;
}
static inline unsigned int rng_range(unsigned int n) {
    unsigned long long p = (unsigned long long)rng_next() * (unsigned long long)n;
    return (unsigned int)(p >> 32);
}
/* seed from how long the player takes to press the start key -- the only
   entropy on a machine with no RTC. Returns the key pressed. */
static inline int seed_and_wait(void) {
    unsigned int spins = 0;
    int k;
    while ((k = con_poll()) == 0) spins++;
    rng_state = 2463534242u ^ (spins * 2654435761u);
    rng_next();
    return k;
}

/* the games' exit keys: Q (either case), ESC, or Ctrl+C. Ctrl+C never
   reaches con_poll -- the OS keeps it as a break flag -- so ask for that
   too. Call once per polled key. */
static inline int quit_key(int k) {
    return k == 'Q' || k == 'q' || k == 27 || con_break();
}

/* after GAME OVER / a win: forget keys pressed during the animation, then
   wait for one. Returns 1 to quit, 0 to play again. */
static inline int quit_or_again(void) {
    int k;
    while (con_poll()) {}
    con_break();
    while ((k = con_poll()) == 0 && !con_break()) {}
    return k == 0 || k == 'Q' || k == 'q' || k == 27;
}

#endif
