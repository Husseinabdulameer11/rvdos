#include "kbd.h"

#define KBD_STATUS (*(volatile unsigned int *)0x00040000)
#define KBD_DATA   (*(volatile unsigned int *)0x00040004)

int kbd_available(void) {
    return KBD_STATUS & 1;
}

char kbd_getchar(void) {
    while (!kbd_available()) {
        /* busy-wait -- no interrupts on this CPU yet, so polling is the
           only option */
    }
    return (char)(KBD_DATA & 0xFF);
}
