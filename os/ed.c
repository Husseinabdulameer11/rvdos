/* ed.c -- ED, RVDOS's full-screen text editor (a transient, like PONG).
 *
 *   A>ED GAME.FLT
 *
 * Keys (arrows send WordStar's control codes, so a plain terminal works):
 *   arrows / ^E ^X ^S ^D   move          Home/End  ^A / ^F   line start/end
 *   PgUp / PgDn  ^R / ^^   page          Enter     new line, keeps indent
 *   Backspace / Del        delete        Tab       two spaces
 *   ^Y                     delete line   ESC       menu: Save, eXit, Quit
 *
 * The whole file sits in one array in the TPA; inserting slides the rest
 * of the text along. With files capped by the 9 KB disk that costs well
 * under a millisecond per key, and keeps the editor small.
 * In .FLT files, # comments and "strings" are coloured.
 */
#include "applib.h"
#include "mini.h"

#define ROWS (CON_ROWS - 1)          /* text rows; the last row is status */
#define COLS CON_COLS
#define C_TEXT 1
#define C_STR  2
#define C_CMT  3
#define C_BAR  3

struct ed {
    char name[16];
    char *buf;
    int len, cap;
    int cur;                         /* cursor: byte offset             */
    int top;                         /* first visible line (its offset) */
    int hscroll;
    int want_col;                    /* column kept across up/down      */
    int modified, flint;
    const char *msg;                 /* one-shot status message         */
};
static struct ed *E;

/* ---- text helpers ------------------------------------------------------ */
static int line_start(int p) { while (p > 0 && E->buf[p - 1] != '\n') p--; return p; }
static int line_end(int p)   { while (p < E->len && E->buf[p] != '\n') p++; return p; }
static int next_line(int p)  { int e = line_end(p); return e < E->len ? e + 1 : -1; }
static int prev_line(int p)  { int s = line_start(p); return s == 0 ? -1 : line_start(s - 1); }
static int col_of(int p)     { return p - line_start(p); }
static int line_no(int p)    { int n = 1, i; for (i = 0; i < p; i++) n += E->buf[i] == '\n'; return n; }

static int insert(const char *s, int n) {
    if (E->len + n > E->cap) { E->msg = "BUFFER FULL"; return 0; }
    mem_move(E->buf + E->cur + n, E->buf + E->cur, (unsigned)(E->len - E->cur));
    mem_move(E->buf + E->cur, s, (unsigned)n);
    E->len += n; E->cur += n; E->modified = 1;
    return 1;
}
static void delete_at(int p, int n) {
    if (p < 0 || n <= 0 || p + n > E->len) return;
    mem_move(E->buf + p, E->buf + p + n, (unsigned)(E->len - p - n));
    E->len -= n; E->modified = 1;
    if (E->cur > p) E->cur = E->cur >= p + n ? E->cur - n : p;
}

/* ---- drawing ----------------------------------------------------------- */
static void put(int col, int row, int ch, int fg, int bg) { con_putcell(col, row, ch, fg, bg); }

static void draw_line(int row, int p) {
    int i, end, col = 0, state = 0, esc = 0;     /* state: 0 code, 1 string, 2 comment */
    if (p < 0) {                                  /* past the end of the file */
        for (col = 0; col < COLS; col++) put(col, row, col == 0 ? '~' : ' ', C_CMT, 0);
        return;
    }
    end = line_end(p);
    for (i = p; col < COLS; i++) {
        int ch = ' ', fg = C_TEXT, vis = i - p - E->hscroll;
        if (i < end) {
            ch = (unsigned char)E->buf[i];
            if (E->flint) {
                if (state == 2) fg = C_CMT;
                else if (state == 1) {
                    fg = C_STR;
                    if (esc) esc = 0;
                    else if (ch == '\\') esc = 1;
                    else if (ch == '"') state = 0;
                }
                else if (ch == '"') { state = 1; fg = C_STR; }
                else if (ch == '#') { state = 2; fg = C_CMT; }
            }
        }
        if (vis < 0) continue;                    /* scrolled off to the left */
        if (i == E->cur && i <= end) put(vis, row, ch, 0, fg == C_TEXT ? 1 : fg);   /* block cursor */
        else put(vis, row, ch, fg, 0);
        col = vis + 1;
    }
}

/* status-bar number (subtracting powers of ten: this CPU has no divide) */
static void put_num(int col, int row, int v) {
    static const int P[] = { 100000, 10000, 1000, 100, 10, 1 };
    int k, started = 0;
    for (k = 0; k < 6; k++) {
        int d = 0;
        while (v >= P[k]) { v -= P[k]; d++; }
        if (d || started || k == 5) { put(col++, row, '0' + d, 0, C_BAR); started = 1; }
    }
}
static int put_str(int col, int row, const char *s) {
    while (*s && col < COLS) put(col++, row, *s++, 0, C_BAR);
    return col;
}
static void draw_status(void) {
    int col = 0, i;
    for (i = 0; i < COLS; i++) put(i, ROWS, ' ', 0, C_BAR);
    col = put_str(1, ROWS, E->name);
    if (E->modified) col = put_str(col, ROWS, "*");
    if (E->msg) {
        put_str(col + 2, ROWS, E->msg);
        E->msg = 0;
    } else {
        col = put_str(col + 2, ROWS, "L");
        put_num(col, ROWS, line_no(E->cur));
        col = put_str(col + 6, ROWS, "C");
        put_num(col, ROWS, col_of(E->cur) + 1);
        put_str(COLS - 9, ROWS, "ESC=MENU");
    }
}
static void draw_all(void) {
    int row, p = E->top;
    for (row = 0; row < ROWS; row++) {
        draw_line(row, p);
        if (p >= 0) p = next_line(p);
    }
    draw_status();
}

/* keep the cursor on screen; returns 1 if the view moved */
static int scroll_to_cursor(void) {
    int moved = 0, row = 0, p, ls = line_start(E->cur), c = col_of(E->cur);
    if (ls < E->top) { E->top = ls; moved = 1; }
    for (p = E->top; p >= 0 && p < ls; p = next_line(p)) row++;
    while (row >= ROWS) { E->top = next_line(E->top); row--; moved = 1; }
    if (c < E->hscroll) { E->hscroll = c < 20 ? 0 : c - 20; moved = 1; }
    if (c >= E->hscroll + COLS) { E->hscroll = c - COLS + 20; moved = 1; }
    return moved;
}

/* Enter: start the new line at the same indentation. In .FLT files also
   indent after a block opener, and pull `end` / `else` / `elif` back out
   to the level of the block they close. */
static int indent_of(int ls) { int n = 0; while (ls + n < E->len && E->buf[ls + n] == ' ') n++; return n; }
static int word_is(int p, const char *w) {
    int n = str_len(w), i;
    for (i = 0; i < n; i++) if (p + i >= E->len || E->buf[p + i] != w[i]) return 0;
    p += n;
    return p >= E->len || !((E->buf[p] >= 'a' && E->buf[p] <= 'z') || (E->buf[p] >= 'A' && E->buf[p] <= 'Z') ||
                            (E->buf[p] >= '0' && E->buf[p] <= '9') || E->buf[p] == '_');
}
static void smart_enter(void) {
    char ind[42];
    int ls = line_start(E->cur), n = indent_of(ls), w = ls + n, k;
    if (n > E->cur - ls) n = E->cur - ls;
    if (E->flint) {
        int closer = word_is(w, "end") || word_is(w, "else") || word_is(w, "elif");
        int pl = prev_line(ls);
        while (pl >= 0 && line_end(pl) == pl + indent_of(pl)) pl = prev_line(pl);   /* skip blank lines */
        if (closer && pl >= 0) {
            /* a closer lines up with its opener: the previous line's level
               if that line opened the block (empty body), else one less */
            int pi = indent_of(pl), pw = pl + pi, target;
            int opener = word_is(pw, "if") || word_is(pw, "elif") || word_is(pw, "else") ||
                         word_is(pw, "while") || word_is(pw, "for") || word_is(pw, "func");
            target = opener ? pi : pi - 2;
            if (target < 0) target = 0;
            if (n > target) { delete_at(ls, n - target); w -= n - target; n = target; }
        }
        if (word_is(w, "if") || word_is(w, "elif") || word_is(w, "else") ||
            word_is(w, "while") || word_is(w, "for") || word_is(w, "func")) n += 2;
    }
    if (n > 40) n = 40;
    ind[0] = '\n';
    for (k = 1; k <= n; k++) ind[k] = ' ';
    insert(ind, n + 1);
}

/* ---- commands ---------------------------------------------------------- */
static void move_vert(int dir) {
    int target = dir < 0 ? prev_line(E->cur) : next_line(E->cur), e;
    if (target < 0) return;
    e = line_end(target);
    E->cur = target + E->want_col < e ? target + E->want_col : e;
}
static int save(void) {
    int r = f_write(E->name, E->buf, E->len);
    if (r == FS_OK) { E->modified = 0; E->msg = "SAVED"; return 1; }
    E->msg = r == FS_FULL ? "DISK FULL - NOT SAVED" : r == FS_DIRFULL ? "DIRECTORY FULL" : "CANNOT SAVE";
    return 0;
}
static int ask(const char *q) {
    int i, c;
    for (i = 0; i < COLS; i++) put(i, ROWS, ' ', 0, C_BAR);
    put_str(1, ROWS, q);
    c = con_getc();
    return c;
}
/* returns 1 to leave the editor */
static int menu(void) {
    int c = ask("S=SAVE  X=SAVE+EXIT  Q=QUIT  ESC=BACK");
    if (c == 's' || c == 'S') { save(); return 0; }
    if (c == 'x' || c == 'X') return save();
    if (c == 'q' || c == 'Q') {
        if (!E->modified) return 1;
        c = ask("QUIT WITHOUT SAVING? Y/N");
        return c == 'y' || c == 'Y';
    }
    return 0;
}

int ed_main(void) {
    const char *args = os_args();
    unsigned char *tpa = os_tpa();
    int i = 0, id;

    E = (struct ed *)tpa;
    mem_set(E, 0, sizeof *E);
    E->buf = (char *)tpa + sizeof *E;
    E->cap = (int)os_tpa_size() - (int)sizeof *E;

    while (*args == ' ') args++;
    while (args[i] && args[i] != ' ' && i < 15) {
        char c = args[i];
        E->name[i++] = (char)(c >= 'a' && c <= 'z' ? c - 32 : c);
    }
    E->name[i] = 0;
    if (i == 0) { con_puts("USE: ED FILENAME\n"); return 1; }
    if (i > 4 && str_eq(E->name + i - 4, ".FLT")) E->flint = 1;

    id = f_find(E->name);
    if (id >= 0) {
        E->len = f_size(id);
        if (E->len > E->cap) { con_puts("FILE TOO BIG\n"); return 1; }
        mem_move(E->buf, f_data(id), (unsigned)E->len);
    } else {
        E->msg = "NEW FILE";
    }

    con_colors(C_TEXT, 0);
    con_clear();
    draw_all();
    for (;;) {
        int c = con_getc(), full = 0, old_line = line_start(E->cur), keep_col = 0;
        switch (c) {
        case KEY_ESC:
            if (menu()) { con_clear(); return 0; }
            full = 1;
            break;
        case KEY_LEFT:  if (E->cur > 0) E->cur--; break;
        case KEY_RIGHT: if (E->cur < E->len) E->cur++; break;
        case KEY_UP:    move_vert(-1); keep_col = 1; break;
        case KEY_DOWN:  move_vert(1);  keep_col = 1; break;
        case KEY_HOME:  E->cur = line_start(E->cur); break;
        case KEY_END:   E->cur = line_end(E->cur); break;
        case KEY_PGUP:  for (i = 0; i < ROWS - 1; i++) move_vert(-1); keep_col = 1; break;
        case KEY_PGDN:  for (i = 0; i < ROWS - 1; i++) move_vert(1);  keep_col = 1; break;
        case KEY_ENTER: smart_enter(); full = 1; break;
        case KEY_TAB:   insert("  ", 2); break;
        case KEY_BS:
            if (E->cur > 0) { if (E->buf[E->cur - 1] == '\n') full = 1; delete_at(E->cur - 1, 1); }
            break;
        case KEY_DEL:
            if (E->cur < E->len) { if (E->buf[E->cur] == '\n') full = 1; delete_at(E->cur, 1); }
            break;
        case 25: {                                     /* ^Y: delete line */
            int s = line_start(E->cur), e = line_end(E->cur);
            delete_at(s, (e < E->len ? e + 1 : e) - s);
            E->cur = s;
            full = 1;
            break;
        }
        default:
            if (c >= 32 && c < 127) { char ch = (char)c; insert(&ch, 1); }
            break;
        }
        if (!keep_col) E->want_col = col_of(E->cur);
        if (scroll_to_cursor()) full = 1;
        if (full) draw_all();
        else {
            /* only the cursor's old and new lines can have changed */
            int row = 0, p, ls = line_start(E->cur);
            for (p = E->top; p >= 0; p = next_line(p), row++) {
                if (p == ls || p == old_line) draw_line(row, p);
                if (row >= ROWS - 1) break;
            }
            draw_status();
        }
    }
}
