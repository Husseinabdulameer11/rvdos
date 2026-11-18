#ifndef KBD_H
#define KBD_H

/* Memory-mapped keyboard, matching cpu_top.vhd's address map:
   KBD_BASE = 0x00040000, status register at +0, data register at +4. */

int kbd_available(void);   /* nonzero if a key is waiting */
char kbd_getchar(void);    /* blocks until a key arrives, then returns it */

#endif
