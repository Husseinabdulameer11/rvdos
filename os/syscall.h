#ifndef SYSCALL_H
#define SYSCALL_H
/* ------------------------------------------------------------------------
 * RVDOS -- the CP/M-style syscall ABI for this RV32IM core.
 *
 * Programs NEVER touch hardware. They reach the OS through a single fixed
 * entry vector at address 0x00000004 (the analog of CP/M's "CALL 5"),
 * passing a function number in a0 and up to three arguments in a1..a3.
 * boot.s places `j bdos_dispatch` at 0x0004, so a jalr to 0x4 lands in the
 * dispatcher with the caller's return address intact.
 *
 * Today the OS and its programs are co-resident in one ROM image (the CPU
 * is Harvard -- code can't be loaded into RAM and executed), so the CCP
 * "launches" a transient by calling its entry directly. Because every
 * program speaks only this ABI, they stay loadable without source changes
 * the day a real loader exists.
 * ---------------------------------------------------------------------- */

#define RVDOS_VERSION 0x0200   /* 2.0 */

/* console geometry (6x8 cells on the 320x200 framebuffer) */
#define CON_COLS 53
#define CON_ROWS 25

/* control keys as the keyboard delivers them (ASCII control codes; the
   arrow keys follow WordStar's "diamond", which CP/M software used) */
#define KEY_CTRL_C  3
#define KEY_BS      8
#define KEY_TAB     9
#define KEY_ENTER   '\n'
#define KEY_ESC     27
#define KEY_DEL     127
#define KEY_UP      5    /* ^E */
#define KEY_DOWN    24   /* ^X */
#define KEY_LEFT    19   /* ^S */
#define KEY_RIGHT   4    /* ^D */
#define KEY_HOME    1    /* ^A */
#define KEY_END     6    /* ^F */
#define KEY_PGUP    18   /* ^R */
#define KEY_PGDN    30   /* WordStar uses ^C, but ^C is break here */

/* --- syscall numbers (numbers <=9 deliberately echo CP/M's BDOS) ------- */
#define SYS_EXIT     0   /* transient finished; return to CCP            */
#define SYS_GETC     1   /* blocking key read (shows cursor) -> a0 = char */
#define SYS_PUTC     2   /* a1 = char  (\n, \r, \b handled; scrolls)     */
#define SYS_POLL     3   /* non-blocking key            -> a0 = char|0   */
#define SYS_BREAK    4   /* -> 1 if ^C was pressed since last call       */
#define SYS_PUTS     9   /* a1 = ptr to NUL-terminated string            */
#define SYS_CLEAR    10  /* clear screen, home cursor                    */
#define SYS_GOTOXY   11  /* a1 = col, a2 = row                           */
#define SYS_FILLCELL 12  /* a1 = col, a2 = row, a3 = palette color       */
#define SYS_SETCOLOR 13  /* a1 = text color, a2 = background color       */
#define SYS_SETPAL   14  /* a1 = index, a2 = 0xRRGGBB                    */
#define SYS_GETXY    15  /* -> col | row << 8                            */
#define SYS_PUTCELL  16  /* a1 = col|row<<8, a2 = char, a3 = fg|bg<<8;
                            draws one cell, cursor unchanged             */
#define SYS_GETLINE  17  /* a1 = buf, a2 = size -> length; line editor
                            with echo; -1 if ^C                          */

/* RAM disk (drive A:). Names are CP/M 8.3, case-insensitive.            */
#define SYS_FFIND    20  /* a1 = name           -> file id, or -1        */
#define SYS_FSIZE    21  /* a1 = id             -> size, or -1           */
#define SYS_FDATA    22  /* a1 = id             -> pointer to contents   */
#define SYS_FWRITE   23  /* a1 = name, a2 = ptr, a3 = len -> FS_* code   */
#define SYS_FDELETE  24  /* a1 = name           -> FS_* code             */
#define SYS_FRENAME  25  /* a1 = old, a2 = new  -> FS_* code             */
#define SYS_FNAME    26  /* a1 = id, a2 = buf[13] -> 0, or -1 past end   */
#define SYS_FFREE    27  /* -> free bytes on the disk                    */

/* pixel graphics on the same 320x200 framebuffer                       */
#define SYS_PIXEL    30  /* a1 = x, a2 = y, a3 = color                   */
#define SYS_RECT     31  /* a1 = x|y<<16, a2 = w|h<<16, a3 = color       */
#define SYS_GETPIX   32  /* a1 = x, a2 = y -> color                      */

#define SYS_ARGS     34  /* -> pointer to the command tail ("" if none)  */
#define SYS_VERSION  35  /* -> RVDOS_VERSION                             */
#define SYS_TPA      36  /* a1 = 0 -> TPA base address, 1 -> TPA size.
                            The Transient Program Area: scratch RAM every
                            transient may use freely while it runs.      */
#define SYS_RANDOM   37  /* -> 32 bits gathered from keypress timing (the
                            only entropy on a machine with no clock)     */

/* file-system result codes */
#define FS_OK        0
#define FS_NOTFOUND  -1
#define FS_FULL      -2   /* not enough free bytes */
#define FS_DIRFULL   -3   /* no free directory entry */
#define FS_BADNAME   -4
#define FS_EXISTS    -5
#define FS_READONLY  -6   /* a built-in .COM program */

/* Args are register-width (long == 32-bit under ilp32, so this is exactly
   the a0..a3 registers on the target; on a 64-bit host it keeps pointers
   from truncating during testing). */
#ifdef RVDOS_HOST_TEST
extern long bdos_dispatch(long fn, long a1, long a2, long a3);
static inline long sys(long fn, long a1, long a2, long a3) { return bdos_dispatch(fn, a1, a2, a3); }
#else
typedef long (*bdos_entry_t)(long fn, long a1, long a2, long a3);
#define BDOS ((bdos_entry_t)0x00000004)
static inline long sys(long fn, long a1, long a2, long a3) { return BDOS(fn, a1, a2, a3); }
#endif

#endif
