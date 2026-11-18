#ifndef BOOT_LOGO_H
#define BOOT_LOGO_H

/* Palette indices used by the boot logo -- exposed so a caller (like
   boot_sequence.c) knows which indices are "taken" before setting up
   its own palette entries for whatever comes after the logo. */
#define LOGO_BG_COLOR   1
#define LOGO_CHIP_COLOR 2
#define LOGO_PIN_COLOR  3
#define LOGO_TEXT_COLOR 4

void draw_boot_logo(void);

#endif
