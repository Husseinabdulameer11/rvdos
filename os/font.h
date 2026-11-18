#ifndef FONT_H
#define FONT_H

/* 5x7 bitmap font: A-Z, 0-9, space, and common punctuation (51 glyphs
   total). Each glyph is 7 bytes, one per row; each byte's low 5 bits
   are that row's pixels, bit 4 = leftmost column. Every glyph was
   rendered as ASCII art and visually checked before being generated
   into this table -- not typed directly into C and trusted blind (the
   same discipline as the original 7-character font, just scaled up).
   Lowercase is not included -- same technique, straightforward to add
   later, just more glyphs to design and verify. */

typedef struct {
    char ch;
    unsigned char rows[7];
} glyph_t;

extern const glyph_t FONT[];
extern const int FONT_SIZE;

const unsigned char *font_lookup(char c);

/* g j p q y have tails: the console's 6x8 cell draws them one row lower,
   using the spare 8th row, so they sit on the baseline like the rest */
#define FONT_DESCENDER(c) ((c) == 'g' || (c) == 'j' || (c) == 'p' || (c) == 'q' || (c) == 'y')

#endif
