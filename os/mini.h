#ifndef MINI_H
#define MINI_H
/* mini.c -- the handful of C-library routines this freestanding build
   needs. memcpy/memset/memmove/memcmp exist under their standard names
   because gcc emits calls to them on its own (struct copies, zeroing
   arrays) even with -ffreestanding. */
#include <stddef.h>

void *memcpy(void *d, const void *s, size_t n);
void *memmove(void *d, const void *s, size_t n);
void *memset(void *d, int c, size_t n);
int   memcmp(const void *a, const void *b, size_t n);

#define mem_move(d, s, n) memmove((d), (s), (n))
#define mem_set(d, c, n)  memset((d), (c), (n))

int  str_len(const char *s);
int  str_eq(const char *a, const char *b);
void str_copy(char *d, const char *s, int size);   /* always terminates */
void str_cat(char *d, const char *s, int size);

/* 32-bit division in software: this core implements RV32M multiply but
   not divide. Both truncate toward zero like C; dividing by 0 gives 0. */
unsigned int udiv32(unsigned int n, unsigned int d, unsigned int *rem);
int          sdiv32(int n, int d, int *rem);

#endif
