/* mini.c -- see mini.h. Build with -fno-builtin and
   -fno-tree-loop-distribute-patterns, or gcc turns these loops back into
   calls to themselves. */
#include "mini.h"

void *memcpy(void *d, const void *s, size_t n) {
    unsigned char *dp = (unsigned char *)d;
    const unsigned char *sp = (const unsigned char *)s;
    if ((((size_t)dp | (size_t)sp) & 3) == 0) {
        for (; n >= 4; n -= 4, dp += 4, sp += 4)
            *(unsigned int *)dp = *(const unsigned int *)sp;
    }
    while (n--) *dp++ = *sp++;
    return d;
}

void *memmove(void *d, const void *s, size_t n) {
    unsigned char *dp = (unsigned char *)d;
    const unsigned char *sp = (const unsigned char *)s;
    if (dp == sp || n == 0) return d;
    if (dp < sp || dp >= sp + n) return memcpy(d, s, n);
    dp += n; sp += n;
    while (n--) *--dp = *--sp;
    return d;
}

void *memset(void *d, int c, size_t n) {
    unsigned char *p = (unsigned char *)d;
    unsigned int w = (unsigned char)c * 0x01010101u;
    while (n && ((size_t)p & 3)) { *p++ = (unsigned char)c; n--; }
    for (; n >= 4; n -= 4, p += 4) *(unsigned int *)p = w;
    while (n--) *p++ = (unsigned char)c;
    return d;
}

int memcmp(const void *a, const void *b, size_t n) {
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    for (; n; n--, x++, y++) if (*x != *y) return *x - *y;
    return 0;
}

int str_len(const char *s) { int n = 0; while (s[n]) n++; return n; }

int str_eq(const char *a, const char *b) {
    while (*a && *a == *b) { a++; b++; }
    return *a == *b;
}

void str_copy(char *d, const char *s, int size) {
    int i = 0;
    if (size <= 0) return;
    for (; s[i] && i < size - 1; i++) d[i] = s[i];
    d[i] = 0;
}

void str_cat(char *d, const char *s, int size) {
    int n = str_len(d);
    if (n < size) str_copy(d + n, s, size - n);
}

/* shift-subtract long division, one quotient bit per step */
unsigned int udiv32(unsigned int n, unsigned int d, unsigned int *rem) {
    unsigned int q = 0, r = 0;
    int i;
    if (d == 0) { if (rem) *rem = 0; return 0; }
    if (d > n) { if (rem) *rem = n; return 0; }
    for (i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1);
        if (r >= d) { r -= d; q |= 1u << i; }
    }
    if (rem) *rem = r;
    return q;
}

int sdiv32(int n, int d, int *rem) {
    unsigned int un = n < 0 ? 0u - (unsigned)n : (unsigned)n;
    unsigned int ud = d < 0 ? 0u - (unsigned)d : (unsigned)d;
    unsigned int r, q = udiv32(un, ud, &r);
    if (rem) *rem = n < 0 ? -(int)r : (int)r;
    return ((n < 0) != (d < 0)) ? -(int)q : (int)q;
}
