/* flint.c -- Flint, a small structured language for RVDOS, built on gram.
 *
 *   A>FLINT              interactive: type statements, they run at once
 *   A>FLINT GAME.FLT     run a program
 *   A>GAME               same thing -- the CCP finds GAME.FLT
 *
 * How it works. Each source line is parsed on its own with gram (using
 * the precompiled tables in gen/flint_grammar.c) and compiled straight to
 * bytecode; the parse tree is thrown away after every line, so the parser
 * only ever needs ~1 KB. Blocks (if/while/for/func ... end) span lines, so
 * the compiler keeps a small block stack and back-patches jumps when it
 * reaches `end`. Then a stack VM runs the bytecode.
 *
 * Values are 32-bit integers. Arrays are integers too: a handle into the
 * array heap. Strings exist as literals for print. Division is done in
 * software (mini.c) because the CPU has no divide instruction.
 *
 * Everything lives in the TPA (SYS_TPA), the RAM the OS lends to whichever
 * transient is running; nothing here uses static RAM.
 */
#include "applib.h"
#include "mini.h"
#include "gram.h"
#include "flint_grammar.h"

/* ---------------------------------------------------------------------- *
 *  Limits                                                                *
 * ---------------------------------------------------------------------- */
#define MAX_CODE     4096   /* bytecode bytes                   */
#define MAX_LINEMAP  256    /* code offset -> source line marks  */
#define MAX_NAMES    768    /* identifier text                  */
#define MAX_STRS     1024   /* string literals                  */
#define MAX_GLOBALS  128
#define MAX_FUNCS    40
#define MAX_LOCALS   32     /* per function, params included    */
#define MAX_BLOCKS   12     /* nesting of if/while/for/func     */
#define ARENA_SIZE   4096   /* gram parse tree for one line: a busy
                               160-char line peaks around 3 KB    */
#define VSTACK       256    /* VM value stack (ints)            */
#define CSTACK       32     /* call depth                       */
#define LINE_MAX     160

/* ---------------------------------------------------------------------- *
 *  Bytecode                                                              *
 * ---------------------------------------------------------------------- */
enum {
    OP_HALT, OP_PUSH8, OP_PUSH16, OP_PUSH32,
    OP_GLOAD, OP_GSTORE, OP_LLOAD, OP_LSTORE,
    OP_IDXLOAD, OP_IDXSTORE, OP_NEWARR, OP_DUP, OP_DUP2, OP_POP,
    OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
    OP_AND, OP_OR, OP_XOR, OP_SHL, OP_SHR,
    OP_EQ, OP_NE, OP_LT, OP_LE, OP_GT, OP_GE,
    OP_NOT, OP_NEG, OP_BNOT,
    OP_JMP, OP_JZ, OP_JNZ,
    OP_CALL, OP_RET, OP_RET0, OP_BUILTIN,
    OP_PRINTI, OP_PRINTS, OP_PRINTNL,
    OP_FORTEST
};

/* built-in functions: name, fewest and most arguments */
enum {
    B_KEY, B_GETKEY, B_INPUT, B_RND, B_ABS, B_MIN, B_MAX, B_LEN,
    B_CLS, B_AT, B_COLOR, B_PUTCH, B_FILL, B_PIXEL, B_RECT, B_GETPIXEL,
    B_PALETTE, B_WAIT, B_COUNT
};
struct builtin { const char *name; unsigned char min, max; };
static const struct builtin BUILTINS[B_COUNT] = {
    { "key", 0, 0 },     { "getkey", 0, 0 },  { "input", 0, 0 },
    { "rnd", 1, 1 },     { "abs", 1, 1 },     { "min", 2, 2 },
    { "max", 2, 2 },     { "len", 1, 1 },     { "cls", 0, 0 },
    { "at", 2, 2 },      { "color", 1, 2 },   { "putch", 1, 1 },
    { "fill", 3, 3 },    { "pixel", 3, 3 },   { "rect", 5, 5 },
    { "getpixel", 2, 2 },{ "palette", 2, 2 }, { "wait", 1, 1 },
};

/* ---------------------------------------------------------------------- *
 *  State -- one struct at the bottom of the TPA, array heap above it     *
 * ---------------------------------------------------------------------- */
struct func  { unsigned short name, addr, first_use; unsigned char nparams, nlocals, defined, returns; };
struct block { unsigned char kind; unsigned short line, a, b, brk, cont; short var, end, step; unsigned char local; };
enum { BK_IF, BK_ELSE, BK_WHILE, BK_FOR, BK_FUNC };
struct frame { unsigned short ret, fp, heap; unsigned char func; };

struct flint {
    unsigned char code[MAX_CODE];
    unsigned int ncode;
    unsigned short linemap[MAX_LINEMAP][2];
    unsigned int nlinemap;
    char names[MAX_NAMES];
    unsigned int nnames;
    char strs[MAX_STRS];
    unsigned int nstrs;
    unsigned short gname[MAX_GLOBALS];       /* 0xFFFF = hidden for-loop temp */
    int gval[MAX_GLOBALS];
    unsigned int nglobals;
    struct func funcs[MAX_FUNCS];
    unsigned int nfuncs;

    /* compiler */
    int cur_func;                            /* -1 at top level */
    unsigned short lname[MAX_LOCALS];
    unsigned int nlocals;
    struct block blocks[MAX_BLOCKS];
    unsigned int nblocks;
    int line;                                /* source line being compiled */
    int failed, quiet, repl;
    short hid_g[MAX_BLOCKS][2];              /* reused top-level for-loop temps */
    gram_arena arena;
    unsigned char *arena_mem;                /* top ARENA_SIZE bytes of the TPA */

    /* VM */
    int vs[VSTACK];
    struct frame cs[CSTACK];
    unsigned int heap_top, heap_cap;         /* in ints */
    unsigned int rng;
    unsigned int ops;
    int stop;                                /* ^C seen inside a builtin */
    int heap[1];                             /* runs to the end of the TPA */
};
static struct flint *F;                      /* .bss: just this pointer */

/* ---------------------------------------------------------------------- *
 *  Output helpers                                                        *
 * ---------------------------------------------------------------------- */
static void put_int(int v) {
    if (v < 0) { con_putc('-'); con_putu(0u - (unsigned)v); }
    else con_putu((unsigned)v);
}
static void err_head(void) {
    con_colors(2, 0);
    con_puts("Error");
    if (F->line > 0 && !F->repl) { con_puts(" in line "); put_int(F->line); }
    con_puts(": ");
}
static void err_tail(void) { con_putc('\n'); con_colors(1, 0); }
static void cerror(const char *msg, const char *detail, unsigned int dlen) {
    unsigned int i;
    if (F->failed) return;
    F->failed = 1;
    if (F->quiet) return;
    err_head();
    con_puts(msg);
    for (i = 0; detail && i < dlen; i++) con_putc(detail[i]);
    err_tail();
}

/* ---------------------------------------------------------------------- *
 *  Code emission                                                         *
 * ---------------------------------------------------------------------- */
static void emit(int b) {
    if (F->ncode >= MAX_CODE) { cerror("program too big", 0, 0); return; }
    F->code[F->ncode++] = (unsigned char)b;
}
static void emit16(int v) { emit(v & 0xFF); emit((v >> 8) & 0xFF); }
static unsigned int here(void) { return F->ncode; }
static unsigned int rd16(unsigned int at) { return F->code[at] | (F->code[at + 1] << 8); }
static void wr16(unsigned int at, unsigned int v) {
    if (at + 1 < MAX_CODE) { F->code[at] = (unsigned char)v; F->code[at + 1] = (unsigned char)(v >> 8); }
}
/* emit a jump; returns where its operand is, for patching */
static unsigned int emit_jump(int op, unsigned int target) {
    unsigned int at;
    emit(op);
    at = here();
    emit16((int)target);
    return at;
}
/* forward jumps that all go to one not-yet-known place are kept as a
   chain threaded through their own operands (0 ends it) */
static void chain_add(unsigned short *chain, int op) {
    unsigned int at = emit_jump(op, *chain);
    *chain = (unsigned short)at;
}
static void chain_patch(unsigned short chain, unsigned int target) {
    while (chain) {
        unsigned int next = rd16(chain);
        wr16(chain, target);
        chain = (unsigned short)next;
    }
}
static void emit_push(int v) {
    if (v >= -128 && v <= 127) { emit(OP_PUSH8); emit(v & 0xFF); }
    else if (v >= -32768 && v <= 32767) { emit(OP_PUSH16); emit16(v); }
    else { emit(OP_PUSH32); emit16(v & 0xFFFF); emit16((v >> 16) & 0xFFFF); }
}
static void mark_line(void) {
    unsigned int n = F->nlinemap;
    if (n && F->linemap[n - 1][1] == F->line) return;
    if (n && F->linemap[n - 1][0] == here()) { F->linemap[n - 1][1] = (unsigned short)F->line; return; }
    if (n < MAX_LINEMAP) {
        F->linemap[n][0] = (unsigned short)here();
        F->linemap[n][1] = (unsigned short)F->line;
        F->nlinemap++;
    }
}

/* ---------------------------------------------------------------------- *
 *  Names: identifiers are copied into F->names, since source lines (and  *
 *  interactive input) do not outlive compilation.                        *
 * ---------------------------------------------------------------------- */
static int name_eq(unsigned short off, const char *s, unsigned int len) {
    const char *n = F->names + off;
    unsigned int i;
    for (i = 0; i < len; i++) if (n[i] != s[i]) return 0;
    return n[len] == 0;
}
static int name_add(const char *s, unsigned int len) {
    unsigned int off = F->nnames, i;
    if (off + len + 1 > MAX_NAMES) { cerror("too many names", 0, 0); return 0; }
    for (i = 0; i < len; i++) F->names[off + i] = s[i];
    F->names[off + len] = 0;
    F->nnames += len + 1;
    return (int)off;
}
static int find_local(const gram_node *id) {
    unsigned int i;
    if (F->cur_func < 0) return -1;
    for (i = 0; i < F->nlocals; i++)
        if (F->lname[i] != 0xFFFF && name_eq(F->lname[i], id->text, id->len)) return (int)i;
    return -1;
}
static int add_local(const char *s, unsigned int len) {
    if (F->nlocals >= MAX_LOCALS) { cerror("too many local variables", 0, 0); return 0; }
    F->lname[F->nlocals] = s ? (unsigned short)name_add(s, len) : 0xFFFF;
    return (int)F->nlocals++;
}
static int find_global(const char *s, unsigned int len) {
    unsigned int i;
    for (i = 0; i < F->nglobals; i++)
        if (F->gname[i] != 0xFFFF && name_eq(F->gname[i], s, len)) return (int)i;
    return -1;
}
static int add_global(const char *s, unsigned int len) {
    if (F->nglobals >= MAX_GLOBALS) { cerror("too many global variables", 0, 0); return 0; }
    F->gname[F->nglobals] = s ? (unsigned short)name_add(s, len) : 0xFFFF;
    F->gval[F->nglobals] = 0;
    return (int)F->nglobals++;
}
static int global_slot(const gram_node *id) {
    int g = find_global(id->text, id->len);
    return g >= 0 ? g : add_global(id->text, id->len);
}
static int find_builtin(const gram_node *id) {
    int i;
    for (i = 0; i < B_COUNT; i++) {
        const char *b = BUILTINS[i].name;
        unsigned int k;
        for (k = 0; k < id->len && b[k] == id->text[k]; k++) {}
        if (k == id->len && b[k] == 0) return i;
    }
    return -1;
}
static int func_slot(const gram_node *id) {
    unsigned int i;
    for (i = 0; i < F->nfuncs; i++) if (name_eq(F->funcs[i].name, id->text, id->len)) return (int)i;
    if (F->nfuncs >= MAX_FUNCS) { cerror("too many functions", 0, 0); return 0; }
    mem_set(&F->funcs[F->nfuncs], 0, sizeof(struct func));
    F->funcs[F->nfuncs].name = (unsigned short)name_add(id->text, id->len);
    F->funcs[F->nfuncs].first_use = (unsigned short)F->line;
    return (int)F->nfuncs++;
}

/* variable access: Lua's rule -- inside a function a name is local if it
   was declared there (a parameter, `var`, or a for variable), otherwise
   it is global. At the top level everything is global. */
static void load_var(const gram_node *id) {
    int l = find_local(id);
    if (l >= 0) { emit(OP_LLOAD); emit(l); return; }
    emit(OP_GLOAD); emit(global_slot(id));
}
static void store_var(const gram_node *id) {
    int l = find_local(id);
    if (l >= 0) { emit(OP_LSTORE); emit(l); return; }
    emit(OP_GSTORE); emit(global_slot(id));
}

/* ---------------------------------------------------------------------- *
 *  Expressions                                                           *
 * ---------------------------------------------------------------------- */
static void expr(const gram_node *n);

static int parse_int(const gram_node *n) {
    unsigned int v = 0, i;
    if (n->rule == FLINT_R_hexnum) {
        for (i = 2; i < n->len; i++) {
            int c = n->text[i];
            v = (v << 4) | (unsigned)(c <= '9' ? c - '0' : (c | 32) - 'a' + 10);
        }
    } else {
        for (i = 0; i < n->len; i++) v = v * 10u + (unsigned)(n->text[i] - '0');
    }
    return (int)v;
}
static int unescape(int c) {
    switch (c) {
        case 'n': return '\n';
        case 't': return '\t';
        case '0': return 0;
        case 'e': return 27;
        default:  return c;
    }
}

/* operator precedence for the flat `operand (binop operand)*` chain */
static int prec(const gram_node *op) {
    const char *t = op->text;
    switch (t[0]) {
        case 'o': return 1;                          /* or  */
        case 'a': return 2;                          /* and */
        case '=': case '!': return 3;
        case '<': case '>': return (op->len == 2 && t[1] == t[0]) ? 7 : 3;
        case '|': return 4;
        case '^': return 5;
        case '&': return 6;
        case '+': case '-': return 8;
        default:  return 9;                          /* * / % */
    }
}
static int binop_code(const gram_node *op) {
    const char *t = op->text;
    int two = op->len == 2;
    switch (t[0]) {
        case '+': return OP_ADD;  case '-': return OP_SUB;
        case '*': return OP_MUL;  case '/': return OP_DIV;
        case '%': return OP_MOD;  case '&': return OP_AND;
        case '|': return OP_OR;   case '^': return OP_XOR;
        case '=': return OP_EQ;   case '!': return OP_NE;
        case '<': return !two ? OP_LT : t[1] == '=' ? OP_LE : OP_SHL;
        case '>': return !two ? OP_GT : t[1] == '=' ? OP_GE : OP_SHR;
        default:  return OP_HALT;
    }
}
/* precedence climbing over the chain's children: operand op operand ... */
static const gram_node *climb(const gram_node *n, int min) {
    expr(n);
    n = n->next;
    while (n && prec(n) >= min) {
        const gram_node *op = n;
        int p = prec(op);
        if (op->text[0] == 'a' || op->text[0] == 'o') {
            /* short-circuit: `a and b` is a if a is false, else b */
            unsigned int j;
            emit(OP_DUP);
            j = emit_jump(op->text[0] == 'a' ? OP_JZ : OP_JNZ, 0);
            emit(OP_POP);
            n = climb(op->next, p + 1);
            wr16(j, here());
        } else {
            n = climb(op->next, p + 1);
            emit(binop_code(op));
        }
    }
    return n;
}

static void call(const gram_node *n, int as_statement);

static void expr(const gram_node *n) {
    if (F->failed) return;
    switch (n->rule) {
        case FLINT_R_number:
        case FLINT_R_hexnum:  emit_push(parse_int(n)); break;
        case FLINT_R_true:    emit_push(1); break;
        case FLINT_R_false:   emit_push(0); break;
        case FLINT_R_charlit: emit_push(n->text[1] == '\\' ? unescape(n->text[2]) : (unsigned char)n->text[1]); break;
        case FLINT_R_ident:
            if (find_builtin(n) >= 0) { cerror("missing () after ", n->text, n->len); break; }
            load_var(n);
            break;
        case FLINT_R_index:
            load_var(n->child);
            expr(n->child->next);
            emit(OP_IDXLOAD);
            break;
        case FLINT_R_call:   call(n, 0); break;
        case FLINT_R_notop:  expr(n->child); emit(OP_NOT); break;
        case FLINT_R_bnot:   expr(n->child); emit(OP_BNOT); break;
        case FLINT_R_neg:
            if (n->child->rule == FLINT_R_number || n->child->rule == FLINT_R_hexnum)
                emit_push(-parse_int(n->child));       /* fold -5 */
            else { expr(n->child); emit(OP_NEG); }
            break;
        case FLINT_R_expr:   climb(n->child, 1); break;
        default:             cerror("can't use this here: ", n->text, n->len); break;
    }
}

static void call(const gram_node *n, int as_statement) {
    const gram_node *id = n->child, *args = id->next, *a;
    int argc = 0, b;
    if (args) for (a = args->child; a; a = a->next) { expr(a); argc++; }
    b = find_builtin(id);
    if (b >= 0) {
        if (argc < BUILTINS[b].min || argc > BUILTINS[b].max) {
            cerror("wrong number of arguments to ", id->text, id->len);
            return;
        }
        emit(OP_BUILTIN); emit(b); emit(argc);
    } else {
        emit(OP_CALL); emit(func_slot(id)); emit(argc);
    }
    if (as_statement && !F->failed) {
        /* at the prompt, show what a function gave back (rnd(6), fib(10));
           procedures such as cls() stay quiet */
        int shows = b >= 0 ? (b <= B_LEN || b == B_GETPIXEL)
                           : F->funcs[F->code[F->ncode - 2]].returns;
        if (F->repl && shows) { emit(OP_PRINTI); emit(OP_PRINTNL); }
        else emit(OP_POP);
    }
}

/* ---------------------------------------------------------------------- *
 *  Statements                                                            *
 * ---------------------------------------------------------------------- */
static struct block *push_block(int kind) {
    struct block *b;
    if (F->nblocks >= MAX_BLOCKS) { cerror("blocks nested too deeply", 0, 0); return 0; }
    b = &F->blocks[F->nblocks++];
    mem_set(b, 0, sizeof *b);
    b->kind = (unsigned char)kind;
    b->line = (unsigned short)F->line;
    return b;
}
static struct block *top_block(void) { return F->nblocks ? &F->blocks[F->nblocks - 1] : 0; }
static struct block *loop_block(void) {
    int i;
    for (i = (int)F->nblocks - 1; i >= 0; i--) {
        if (F->blocks[i].kind == BK_FUNC) return 0;
        if (F->blocks[i].kind == BK_WHILE || F->blocks[i].kind == BK_FOR) return &F->blocks[i];
    }
    return 0;
}

/* a hidden variable for a for loop's limit and step */
static short hidden_var(int which) {
    short *h;
    if (F->cur_func >= 0) return (short)add_local(0, 0);
    /* top level: one pair per nesting depth, reused by later loops */
    h = &F->hid_g[F->nblocks - 1][which];
    if (*h < 0) *h = (short)add_global(0, 0);
    return *h;
}
static void hv_load(struct block *b, short v)  { emit(b->local ? OP_LLOAD : OP_GLOAD); emit(v); }
static void hv_store(struct block *b, short v) { emit(b->local ? OP_LSTORE : OP_GSTORE); emit(v); }

static void do_assign(const gram_node *n) {
    const gram_node *target = n->child, *op = target->next, *value = op->next;
    int plain = op->text[0] == '=';
    int code = OP_ADD;
    if (!plain) {
        switch (op->text[0]) {
            case '+': code = OP_ADD; break; case '-': code = OP_SUB; break;
            case '*': code = OP_MUL; break; case '/': code = OP_DIV; break;
            default:  code = OP_MOD; break;
        }
    }
    if (target->rule == FLINT_R_index) {
        load_var(target->child);
        expr(target->child->next);
        if (!plain) { emit(OP_DUP2); emit(OP_IDXLOAD); }
        expr(value);
        if (!plain) emit(code);
        emit(OP_IDXSTORE);
    } else {
        if (find_builtin(target) >= 0) { cerror("can't assign to ", target->text, target->len); return; }
        if (!plain) load_var(target);
        expr(value);
        if (!plain) emit(code);
        store_var(target);
    }
}

static void declare(const gram_node *id) {
    if (F->cur_func >= 0) {
        if (find_local(id) >= 0) { cerror("already declared: ", id->text, id->len); return; }
        add_local(id->text, id->len);
    } else {
        global_slot(id);
    }
}
static void do_var(const gram_node *n) {
    const gram_node *v;
    for (v = n->child; v && !F->failed; v = v->next) {
        const gram_node *id = v->rule == FLINT_R_ident ? v : v->child;
        if (v->rule == FLINT_R_varinit)       expr(id->next);
        else if (v->rule == FLINT_R_vararray) { expr(id->next); emit(OP_NEWARR); }
        else                                  emit_push(0);
        declare(id);
        store_var(id);
    }
}

static void do_print(const gram_node *n) {
    const gram_node *p;
    int newline = 1;
    for (p = n->child; p && !F->failed; p = p->next) {
        if (p->rule == FLINT_R_semi) { newline = 0; break; }
        if (p->rule == FLINT_R_string) {
            unsigned int i, start = F->nstrs;
            if (start + p->len > MAX_STRS) { cerror("too much text in strings", 0, 0); return; }
            for (i = 1; i + 1 < p->len; i++) {
                int c = p->text[i];
                if (c == '\\' && i + 2 < p->len) c = unescape(p->text[++i]);
                F->strs[F->nstrs++] = (char)c;
            }
            F->strs[F->nstrs++] = 0;
            emit(OP_PRINTS); emit16((int)start);
        } else {
            expr(p);
            emit(OP_PRINTI);
        }
    }
    if (newline) emit(OP_PRINTNL);
}

static void do_func(const gram_node *n) {
    const gram_node *id = n->child, *params = id->next, *p;
    struct block *b;
    int f;
    if (F->cur_func >= 0 || F->nblocks) { cerror("func must be at the top level", 0, 0); return; }
    if (find_builtin(id) >= 0) { cerror("that's a built-in: ", id->text, id->len); return; }
    f = func_slot(id);
    if (F->funcs[f].defined) { cerror("defined twice: ", id->text, id->len); return; }
    b = push_block(BK_FUNC);
    if (!b) return;
    b->a = (unsigned short)emit_jump(OP_JMP, 0);       /* run-time skips the body */
    F->funcs[f].addr = (unsigned short)here();
    F->funcs[f].defined = 1;
    F->cur_func = f;
    F->nlocals = 0;
    if (params) for (p = params->child; p; p = p->next) {
        if (find_local(p) >= 0) { cerror("parameter used twice: ", p->text, p->len); return; }
        add_local(p->text, p->len);
    }
    F->funcs[f].nparams = (unsigned char)F->nlocals;
}

static void do_for(const gram_node *n) {
    const gram_node *id = n->child, *from = id->next, *to = from->next, *step = to->next;
    struct block *b = push_block(BK_FOR);
    int l;
    if (!b) return;
    b->local = F->cur_func >= 0;
    if (b->local) {
        l = find_local(id);
        if (l < 0) l = add_local(id->text, id->len);
    } else {
        l = global_slot(id);
    }
    b->var = (short)l;
    b->end = hidden_var(0);
    b->step = hidden_var(1);
    expr(from); hv_store(b, b->var);
    expr(to);   hv_store(b, b->end);
    if (step) expr(step); else emit_push(1);
    hv_store(b, b->step);
    b->a = (unsigned short)here();                    /* the test */
    hv_load(b, b->var); hv_load(b, b->end); hv_load(b, b->step);
    emit(OP_FORTEST);
    b->b = (unsigned short)emit_jump(OP_JZ, 0);
}

static void do_end(void) {
    struct block *b = top_block();
    if (!b) { cerror("end without a block", 0, 0); return; }
    switch (b->kind) {
        case BK_IF:
        case BK_ELSE:
            if (b->a) wr16(b->a, here());
            chain_patch(b->b, here());
            break;
        case BK_WHILE:
            emit_jump(OP_JMP, b->a);
            wr16(b->b, here());
            chain_patch(b->brk, here());
            break;
        case BK_FOR:
            chain_patch(b->cont, here());
            hv_load(b, b->var); hv_load(b, b->step); emit(OP_ADD); hv_store(b, b->var);
            emit_jump(OP_JMP, b->a);
            wr16(b->b, here());
            chain_patch(b->brk, here());
            break;
        case BK_FUNC:
            emit(OP_RET0);
            F->funcs[F->cur_func].nlocals = (unsigned char)F->nlocals;
            wr16(b->a, here());
            F->cur_func = -1;
            F->nlocals = 0;
            break;
    }
    F->nblocks--;
}

static void stmt(const gram_node *n) {
    struct block *b;
    switch (n->rule) {
        case FLINT_R_assign:  do_assign(n); break;
        case FLINT_R_callst:  call(n->child, 1); break;
        case FLINT_R_printst: do_print(n); break;
        case FLINT_R_varst:   do_var(n); break;
        case FLINT_R_funcdef: do_func(n); break;
        case FLINT_R_forst:   do_for(n); break;
        case FLINT_R_endst:   do_end(); break;
        case FLINT_R_ifst:
            expr(n->child);
            b = push_block(BK_IF);
            if (b) b->a = (unsigned short)emit_jump(OP_JZ, 0);
            break;
        case FLINT_R_elifst:
            b = top_block();
            if (!b || b->kind != BK_IF) { cerror("elif without if", 0, 0); break; }
            chain_add(&b->b, OP_JMP);                  /* previous branch -> end */
            wr16(b->a, here());
            expr(n->child);
            b->a = (unsigned short)emit_jump(OP_JZ, 0);
            break;
        case FLINT_R_elsest:
            b = top_block();
            if (!b || b->kind != BK_IF) { cerror("else without if", 0, 0); break; }
            chain_add(&b->b, OP_JMP);
            wr16(b->a, here());
            b->a = 0;
            b->kind = BK_ELSE;
            break;
        case FLINT_R_whilest:
            b = push_block(BK_WHILE);
            if (!b) break;
            b->a = (unsigned short)here();
            expr(n->child);
            b->b = (unsigned short)emit_jump(OP_JZ, 0);
            break;
        case FLINT_R_breakst:
            b = loop_block();
            if (!b) { cerror("break outside a loop", 0, 0); break; }
            chain_add(&b->brk, OP_JMP);
            break;
        case FLINT_R_contst:
            b = loop_block();
            if (!b) { cerror("continue outside a loop", 0, 0); break; }
            if (b->kind == BK_WHILE) emit_jump(OP_JMP, b->a);
            else chain_add(&b->cont, OP_JMP);
            break;
        case FLINT_R_returnst:
            if (n->child) {
                expr(n->child);
                emit(F->cur_func >= 0 ? OP_RET : OP_POP);
                if (F->cur_func >= 0) F->funcs[F->cur_func].returns = 1;
            }
            if (F->cur_func >= 0) { if (!n->child) emit(OP_RET0); }
            else emit(OP_HALT);                         /* top-level return ends the program */
            break;
        default:
            cerror("can't compile this", 0, 0);
            break;
    }
}

/* gram reports what it expected as rule names (hexnum, NOT, ...). Say it
   in Flint terms instead: anything that can start an operand becomes
   "a value", keyword tokens become the keyword itself. */
static int starts_value(const char *e) {
    static const char *const v[] = { "NOT", "'-'", "'~'", "'('", "hexnum", "number",
                                     "charlit", "true", "false", "ident", "string", 0 };
    int i;
    for (i = 0; v[i]; i++) if (str_eq(e, v[i])) return 1;
    return 0;
}
static void put_expected(const char *e) {
    int i;
    if (str_eq(e, "binop"))    { con_puts("an operator"); return; }
    if (str_eq(e, "assignop")) { con_puts("'='"); return; }
    if (str_eq(e, "semi"))     { con_puts("';'"); return; }
    if (str_eq(e, "ident"))    { con_puts("a name"); return; }
    if (e[0] >= 'A' && e[0] <= 'Z') {           /* keyword rule: FUNC -> 'func' */
        con_putc('\'');
        for (i = 0; e[i]; i++) con_putc(e[i] >= 'A' && e[i] <= 'Z' ? e[i] + 32 : e[i]);
        con_putc('\'');
        return;
    }
    con_puts(e);
}
static void syntax_error(const char *src, unsigned int len, const gram_error *e) {
    unsigned int i, col = e->col ? (unsigned)e->col - 1 : 0, start = 0, n = 0;
    int value = 0;
    const char *list[GRAM_MAX_EXPECTED + 1];
    int need_op = 0;
    F->failed = 1;
    if (F->quiet) return;
    err_head();
    if (e->code == GRAM_E_DEPTH) con_puts("expression nested too deeply");
    else if (e->code == GRAM_E_NOMEM) con_puts("line too complicated");
    else {
        con_puts("syntax error");
        /* "a value" only when an operand really is what's missing */
        for (i = 0; i < e->nexpected; i++)
            if (str_eq(e->expected[i], "number")) value = 1;
        for (i = 0; i < e->nexpected; i++) {
            if (str_eq(e->expected[i], "binop")) need_op = 1;
            if (value && starts_value(e->expected[i])) continue;
            else if (str_eq(e->expected[i], "keyword") || str_eq(e->expected[i], "idchar")) continue;
            else list[n++] = e->expected[i];
        }
        if (value || n) {
            con_puts(", expected ");
            if (value) { con_puts("a value"); if (n) con_puts(n == 1 ? " or " : ", "); }
            for (i = 0; i < n; i++) {
                if (i) con_puts(i + 1 == n ? " or " : ", ");
                put_expected(list[i]);
            }
        }
        if (need_op && col < len && src[col] == '=') con_puts(" (== compares)");
    }
    err_tail();
    if (col > 40) start = col - 40;
    con_puts("  ");
    for (i = start; i < len && i < start + 48; i++) con_putc(src[i] == '\t' ? ' ' : src[i]);
    con_puts("\n  ");
    for (i = start; i < col; i++) con_putc(' ');
    con_puts("^\n");
}

/* compile one source line (no newline in it) */
static void compile_line(const char *src, unsigned int len, int lineno) {
    gram_error e;
    gram_node *ast;
    F->line = lineno;
    if (len > LINE_MAX) { cerror("line too long", 0, 0); return; }
    gram_arena_init(&F->arena, F->arena_mem, ARENA_SIZE);
    ast = gram_parse(&flint_grammar, 0, src, len, &F->arena, &e);
    if (!ast) { syntax_error(src, len, &e); return; }
    if (!ast->child) return;                           /* blank / comment */
    mark_line();
    stmt(ast->child);
}

/* after the last line: every block closed, every called function defined */
static void compile_finish(void) {
    unsigned int i;
    if (F->failed) return;
    if (F->nblocks) {
        static const char *const what[] = { "if", "else", "while", "for", "func" };
        struct block *b = top_block();
        F->line = b->line;
        cerror("missing end for ", what[b->kind], (unsigned)str_len(what[b->kind]));
        return;
    }
    for (i = 0; i < F->nfuncs; i++)
        if (!F->funcs[i].defined) {
            const char *nm = F->names + F->funcs[i].name;
            F->line = F->funcs[i].first_use;
            cerror("no such function: ", nm, (unsigned)str_len(nm));
            return;
        }
    emit(OP_HALT);
}

/* ---------------------------------------------------------------------- *
 *  The VM                                                                *
 * ---------------------------------------------------------------------- */
static int line_of(unsigned int pc) {
    unsigned int i;
    int line = 0;
    for (i = 0; i < F->nlinemap && F->linemap[i][0] <= pc; i++) line = F->linemap[i][1];
    return line;
}
static int rt_error(unsigned int pc, const char *msg) {
    F->line = line_of(pc);
    err_head();
    con_puts(msg);
    err_tail();
    return -1;
}

static unsigned int rng_next_f(void) {
    F->rng = F->rng * 1664525u + 1013904223u;
    return F->rng;
}
static int read_number(void) {
    char buf[16];
    int n = con_getline(buf, sizeof buf), i = 0, neg = 0, v = 0;
    if (n < 0) { F->stop = 1; return 0; }
    while (buf[i] == ' ') i++;
    if (buf[i] == '-') { neg = 1; i++; }
    for (; buf[i] >= '0' && buf[i] <= '9'; i++) v = v * 10 + (buf[i] - '0');
    return neg ? -v : v;
}
/* wait(ms). Calibrated like the games: 25,000 instructions per ms, which
   is exact in rvemu --mhz=25. On the FPGA a taken branch costs extra
   cycles, so real waits run longer; retune LOOPS_PER_MS once on the board. */
#define LOOPS_PER_MS 12500
static void delay_ms(int ms) {
    while (ms-- > 0 && !F->stop) {
        int i;
        for (i = LOOPS_PER_MS; i > 0; i--) __asm__ volatile ("");
        if ((ms & 15) == 0 && con_break()) F->stop = 1;
    }
}

/* returns the builtin's result; *stop set on ^C during wait */
static int builtin(int b, const int *a, int argc) {
    switch (b) {
        case B_KEY:    F->rng ^= F->ops; return con_poll();
        case B_GETKEY: {
            int c = con_getc();
            F->rng ^= F->ops;
            if (c == KEY_CTRL_C) F->stop = 1;
            return c;
        }
        case B_INPUT:  F->rng ^= F->ops; return read_number();
        case B_RND:
            if (a[0] <= 0) return 0;
            return (int)(((unsigned long long)rng_next_f() * (unsigned)a[0]) >> 32);
        case B_ABS:    return a[0] < 0 ? -a[0] : a[0];
        case B_MIN:    return a[0] < a[1] ? a[0] : a[1];
        case B_MAX:    return a[0] > a[1] ? a[0] : a[1];
        case B_CLS:    con_clear(); return 0;
        case B_AT:     con_gotoxy(a[0], a[1]); return 0;
        case B_COLOR:  con_colors(a[0], argc > 1 ? a[1] : 0); return 0;
        case B_PUTCH:  con_putc((char)a[0]); return 0;
        case B_FILL:   con_fill(a[0], a[1], a[2]); return 0;
        case B_PIXEL:  g_pixel(a[0], a[1], a[2]); return 0;
        case B_RECT:   g_rect(a[0], a[1], a[2], a[3], a[4]); return 0;
        case B_GETPIXEL: return g_getpix(a[0], a[1]);
        case B_PALETTE:  con_setpal(a[0], a[1]); return 0;
        case B_WAIT:   delay_ms(a[0]); return 0;
        default:       return 0;
    }
}

/* run from pc until HALT. 0 = finished, -1 = error or ^C. */
static int run(unsigned int pc) {
    int *vs = F->vs;
    unsigned int sp = 0, fp = 0, csp = 0;
    const unsigned char *code = F->code;
#define NEED(n)  if (sp < (unsigned)(n)) return rt_error(pc, "internal: stack underflow")
#define ROOM(n)  if (sp + (n) > VSTACK) return rt_error(pc, "out of stack (recursion too deep?)")
    for (;;) {
        unsigned int at = pc;
        int op = code[pc++], x, y;
        if (((++F->ops & 1023) == 0 && con_break()) || F->stop) {
            F->stop = 0;
            F->line = line_of(at);
            con_colors(2, 0);
            con_puts("^C Break");
            if (F->line && !F->repl) { con_puts(" in line "); put_int(F->line); }
            err_tail();
            return -1;
        }
        switch (op) {
        case OP_HALT: return 0;
        case OP_PUSH8:  ROOM(1); vs[sp++] = (signed char)code[pc]; pc += 1; break;
        case OP_PUSH16: ROOM(1); vs[sp++] = (short)(code[pc] | code[pc + 1] << 8); pc += 2; break;
        case OP_PUSH32: ROOM(1); vs[sp++] = (int)(code[pc] | code[pc + 1] << 8 | code[pc + 2] << 16 | (unsigned)code[pc + 3] << 24); pc += 4; break;
        case OP_GLOAD:  ROOM(1); vs[sp++] = F->gval[code[pc++]]; break;
        case OP_GSTORE: NEED(1); F->gval[code[pc++]] = vs[--sp]; break;
        case OP_LLOAD:  ROOM(1); vs[sp] = vs[fp + code[pc++]]; sp++; break;
        case OP_LSTORE: NEED(1); vs[fp + code[pc++]] = vs[--sp]; break;
        case OP_DUP:    NEED(1); ROOM(1); vs[sp] = vs[sp - 1]; sp++; break;
        case OP_DUP2:   NEED(2); ROOM(2); vs[sp] = vs[sp - 2]; vs[sp + 1] = vs[sp - 1]; sp += 2; break;
        case OP_POP:    NEED(1); sp--; break;
        case OP_NEWARR: {
            unsigned int n;
            NEED(1);
            x = vs[sp - 1];
            if (x < 0) return rt_error(at, "negative array size");
            n = (unsigned)x;
            if (F->heap_top + n + 1 > F->heap_cap) return rt_error(at, "out of memory for arrays");
            F->heap[F->heap_top] = x;
            mem_set(&F->heap[F->heap_top + 1], 0, n * sizeof(int));
            vs[sp - 1] = (int)F->heap_top + 1;
            F->heap_top += n + 1;
            break;
        }
        case OP_IDXLOAD:
        case OP_IDXSTORE: {
            unsigned int h, i;
            int k = op == OP_IDXSTORE;
            NEED(2 + k);
            h = (unsigned)vs[sp - 2 - k];
            i = (unsigned)vs[sp - 1 - k];
            if (h == 0 || h > F->heap_top) return rt_error(at, "not an array (declare it with var a[size])");
            if (i >= (unsigned)F->heap[h - 1]) return rt_error(at, "index out of range");
            if (k) { F->heap[h + i] = vs[sp - 1]; sp -= 3; }
            else   { vs[sp - 2] = F->heap[h + i]; sp--; }
            break;
        }
        case OP_ADD: case OP_SUB: case OP_MUL: case OP_DIV: case OP_MOD:
        case OP_AND: case OP_OR: case OP_XOR: case OP_SHL: case OP_SHR:
        case OP_EQ: case OP_NE: case OP_LT: case OP_LE: case OP_GT: case OP_GE:
            NEED(2);
            y = vs[--sp]; x = vs[sp - 1];
            switch (op) {
                case OP_ADD: x = (int)((unsigned)x + (unsigned)y); break;
                case OP_SUB: x = (int)((unsigned)x - (unsigned)y); break;
                case OP_MUL: x = (int)((unsigned)x * (unsigned)y); break;
                case OP_DIV:
                case OP_MOD: {
                    int r;
                    if (y == 0) return rt_error(at, "division by zero");
                    x = sdiv32(x, y, &r);
                    if (op == OP_MOD) x = r;
                    break;
                }
                case OP_AND: x &= y; break;
                case OP_OR:  x |= y; break;
                case OP_XOR: x ^= y; break;
                case OP_SHL: x = (int)((unsigned)x << (y & 31)); break;
                case OP_SHR: x >>= (y & 31); break;
                case OP_EQ:  x = x == y; break;
                case OP_NE:  x = x != y; break;
                case OP_LT:  x = x < y; break;
                case OP_LE:  x = x <= y; break;
                case OP_GT:  x = x > y; break;
                default:     x = x >= y; break;
            }
            vs[sp - 1] = x;
            break;
        case OP_NOT:  NEED(1); vs[sp - 1] = !vs[sp - 1]; break;
        case OP_NEG:  NEED(1); vs[sp - 1] = (int)(0u - (unsigned)vs[sp - 1]); break;
        case OP_BNOT: NEED(1); vs[sp - 1] = ~vs[sp - 1]; break;
        case OP_JMP:  pc = code[pc] | code[pc + 1] << 8; break;
        case OP_JZ:   NEED(1); pc = vs[--sp] ? pc + 2 : (unsigned)(code[pc] | code[pc + 1] << 8); break;
        case OP_JNZ:  NEED(1); pc = vs[--sp] ? (unsigned)(code[pc] | code[pc + 1] << 8) : pc + 2; break;
        case OP_FORTEST:
            NEED(3);
            x = vs[sp - 3]; y = vs[sp - 2];
            vs[sp - 3] = vs[sp - 1] >= 0 ? x <= y : x >= y;
            sp -= 2;
            break;
        case OP_CALL: {
            struct func *f = &F->funcs[code[pc]];
            int argc = code[pc + 1], i;
            pc += 2;
            if (argc != f->nparams) return rt_error(at, "wrong number of arguments");
            if (csp >= CSTACK) return rt_error(at, "calls nested too deeply");
            ROOM(f->nlocals - f->nparams + 4);
            F->cs[csp].ret = (unsigned short)pc;
            F->cs[csp].fp = (unsigned short)fp;
            F->cs[csp].heap = (unsigned short)F->heap_top;
            csp++;
            fp = sp - (unsigned)argc;
            for (i = f->nparams; i < f->nlocals; i++) vs[sp++] = 0;
            pc = f->addr;
            break;
        }
        case OP_RET:
        case OP_RET0:
            x = op == OP_RET ? vs[--sp] : 0;
            if (csp == 0) return 0;
            csp--;
            sp = fp;
            pc = F->cs[csp].ret;
            fp = F->cs[csp].fp;
            F->heap_top = F->cs[csp].heap;     /* local arrays die here */
            vs[sp++] = x;
            break;
        case OP_BUILTIN: {
            int b = code[pc], argc = code[pc + 1], args[5] = { 0, 0, 0, 0, 0 }, i;
            pc += 2;
            NEED((unsigned)argc);
            for (i = argc - 1; i >= 0; i--) args[i] = vs[--sp];
            if (b == B_LEN) {
                unsigned int h = (unsigned)args[0];
                if (h == 0 || h > F->heap_top) return rt_error(at, "len() needs an array");
                vs[sp++] = F->heap[h - 1];
                break;
            }
            vs[sp++] = builtin(b, args, argc);
            break;
        }
        case OP_PRINTI:  NEED(1); put_int(vs[--sp]); break;
        case OP_PRINTS:  con_puts(F->strs + (code[pc] | code[pc + 1] << 8)); pc += 2; break;
        case OP_PRINTNL: con_putc('\n'); break;
        default:
            return rt_error(at, "internal: bad opcode");
        }
    }
#undef NEED
#undef ROOM
}

/* ---------------------------------------------------------------------- *
 *  Entry: run a file, or the interactive prompt                          *
 * ---------------------------------------------------------------------- */
static int setup(void) {
    unsigned char *tpa = os_tpa();
    unsigned int size = os_tpa_size();
    if (size < sizeof(struct flint) + ARENA_SIZE + 1024) { con_puts("Flint: not enough memory\n"); return 0; }
    F = (struct flint *)tpa;
    mem_set(F, 0, sizeof *F);
    F->cur_func = -1;
    F->nnames = 1;                       /* offset 0 is never a real name */
    F->nstrs = 0;
    /* The parse arena sits at the very top of the TPA. Arrays grow up from
       the end of the struct and may not touch it while the program is
       still being compiled (always, at the interactive prompt); run_file
       hands the arena over to the heap once compiling is finished. */
    F->arena_mem = tpa + size - ARENA_SIZE;
    F->heap_cap = (size - ARENA_SIZE - (unsigned)sizeof(struct flint)) >> 2;   /* ints */
    F->ncode = 1;                        /* address 0 ends jump chains */
    F->code[0] = OP_HALT;
    F->rng = os_random() | 1;
    for (size = 0; size < MAX_BLOCKS; size++) F->hid_g[size][0] = F->hid_g[size][1] = -1;
    return 1;
}

static int run_file(const char *name) {
    int id = f_find(name), n, start = 0, i, lineno = 1;
    const char *src;
    if (id < 0) { con_puts(name); con_puts("?\n"); return 0; }
    src = f_data(id);
    n = f_size(id);
    for (i = 0; i <= n && !F->failed; i++) {
        if (i == n || src[i] == '\n') {
            if (i > start || i < n) compile_line(src + start, (unsigned)(i - start), lineno);
            lineno++;
            start = i + 1;
        }
    }
    F->line = lineno - 1;
    compile_finish();
    if (F->failed) return 0;
    F->line = 0;
    F->heap_cap += ARENA_SIZE >> 2;              /* done parsing: arena -> arrays */
    return run(1) == 0;
}

/* compile one interactive line. A bare expression such as 2+3 is
   treated as `print 2+3`, so the prompt doubles as a calculator. */
static void repl_compile(const char *buf, unsigned int n) {
    char pbuf[LINE_MAX + 8];
    unsigned int mark = F->ncode, lmark = F->nlinemap, fmark = F->nfuncs;
    int had_blocks = F->nblocks != 0;
    F->failed = 0; F->quiet = 1;
    compile_line(buf, n, 1);
    if (F->failed && !had_blocks && n + 6 < sizeof pbuf) {
        F->ncode = mark; F->nlinemap = lmark; F->nfuncs = fmark;
        str_copy(pbuf, "print ", sizeof pbuf);
        str_cat(pbuf, buf, sizeof pbuf);
        F->failed = 0;
        compile_line(pbuf, n + 6, 1);
        if (F->failed) { F->ncode = mark; F->nlinemap = lmark; F->nfuncs = fmark; }
    }
    F->quiet = 0;
    if (F->failed) { F->failed = 0; compile_line(buf, n, 1); }   /* again, out loud */
}

static void repl(void) {
    char buf[LINE_MAX + 1];
    unsigned int mark = 1, lmark = 0, fmark = 0;
    F->repl = 1;
    con_colors(3, 0); con_puts("Flint 1.0"); con_colors(1, 0);
    con_puts("  statements run at once; bye to exit\n");
    for (;;) {
        int n, i, missing = -1;
        con_puts(F->nblocks ? "...  " : "flint> ");
        n = con_getline(buf, sizeof buf);
        if (n >= 0 && (str_eq(buf, "bye") || str_eq(buf, "exit"))) return;
        if (F->nblocks == 0) { mark = F->ncode; lmark = F->nlinemap; fmark = F->nfuncs; }
        if (n >= 0) repl_compile(buf, (unsigned)n);
        if (n < 0 || F->failed) {
            /* drop the statement, and any half-typed block */
            F->ncode = mark; F->nlinemap = lmark; F->nfuncs = fmark;
            F->nblocks = 0; F->cur_func = -1; F->nlocals = 0; F->failed = 0;
            continue;
        }
        if (F->nblocks) continue;                    /* wait for `end` */
        for (i = 0; i < (int)F->nfuncs; i++) if (!F->funcs[i].defined) { missing = i; break; }
        if (missing >= 0) {
            err_head(); con_puts("no such function: "); con_puts(F->names + F->funcs[missing].name); err_tail();
            F->ncode = mark; F->nlinemap = lmark; F->nfuncs = fmark;
            continue;
        }
        emit(OP_HALT);
        if (F->failed) { F->ncode = mark; F->failed = 0; continue; }
        run(mark);
        F->ncode--;                                  /* the next statement overwrites HALT */
    }
}

int flint_main(void) {
    const char *args = os_args();
    char name[16];
    int i = 0;
    if (!setup()) return 1;
    while (*args == ' ') args++;
    while (args[i] && args[i] != ' ' && i < 15) { name[i] = args[i]; i++; }
    name[i] = 0;
    if (i == 0) { repl(); return 0; }
    /* FLINT GAME  ==  FLINT GAME.FLT */
    {
        int dot = 0, k;
        for (k = 0; name[k]; k++) if (name[k] == '.') dot = 1;
        if (!dot && i <= 8) str_cat(name, ".FLT", sizeof name);
    }
    return run_file(name) ? 0 : 1;
}
