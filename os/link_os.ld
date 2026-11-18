/* link_os.ld -- RVDOS ROM image and RAM layout.
 *
 * Three physical memories on this Harvard core, so the regions below
 * overlap numerically but never collide:
 *   ROM    instr_rom   (fetch only)   .vectors + .text
 *   RODATA rodata_rom  (load only)    .rodata at 0x30000
 *   RAM    data_ram    (load/store)   everything that changes
 *
 * RAM (32 KB, cpu_top RAM_WORDS = 8192):
 *
 *   0x0000  .bss           OS + program variables, zeroed by boot.s
 *           TPA            Transient Program Area: scratch for whichever
 *                          program is running (Flint, ED). SYS_TPA.
 *   ...     stack          STACK_SIZE bytes, grows down from _stack_top
 *   DISK    .noinit        the RAM disk (drive A:); boot.s never clears
 *                          it, so files survive pressing reset
 *   0xFFFF
 *
 * Why 32 KB: the Basys3's XC7A35T has 50 BRAM36 blocks. The framebuffer
 * takes 16, the ROM ~12, rodata ~6; 64 KB of RAM would need 16 more and
 * not fit. On a bigger FPGA, raise RAM_SIZE (and the RAM/DISK lines in
 * MEMORY below, which ld wants as literals) and RAM_WORDS together; the
 * TPA grows to whatever is left.
 */
RAM_SIZE   = 32K;
DISK_SIZE  = 10K;
STACK_SIZE = 6K;

MEMORY
{
    ROM    (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    RODATA (r)  : ORIGIN = 0x00030000, LENGTH = 32K
    /* start at 0x10 so no variable lives at address 0 (== NULL) */
    RAM    (rw) : ORIGIN = 0x00000010, LENGTH = 32K - 10K - 0x10
    DISK   (rw) : ORIGIN = 32K - 10K,  LENGTH = 10K
}

SECTIONS
{
    .vectors : { KEEP(*(.vectors)) }        > ROM
    .text    : { *(.text*) }                > ROM
    .rodata  : { *(.rodata*) *(.srodata*) } > RODATA

    /* Initialised writable data has nowhere to come from on this machine
       (nothing copies ROM to RAM). Collect it so the ASSERT below can
       refuse the build, instead of silently discarding it. */
    .data    : { *(.data*) *(.sdata*) }     > RAM

    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(16);
        _bss_end = .;
    } > RAM

    _tpa_start = _bss_end;
    _stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
    _tpa_end   = ORIGIN(RAM) + LENGTH(RAM) - STACK_SIZE;

    .noinit (NOLOAD) : {
        _disk_start = .;
        . = . + DISK_SIZE;
        _disk_end = .;
    } > DISK

    /DISCARD/ : { *(.comment) *(.riscv.attributes) *(.eh_frame) *(.note*) }
}

ASSERT(SIZEOF(.data) == 0, "initialised non-const globals are not supported: make them const, or zero-init and set them at runtime")
ASSERT(_tpa_end > _tpa_start + 8K, "less than 8 KB left for the TPA")
ASSERT(_disk_end == RAM_SIZE, "the RAM disk must end at the top of RAM")
