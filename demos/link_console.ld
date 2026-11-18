/* Adds a RAM region for .bss (mutable, zero-initialized globals) on top
   of link_rodata.ld's ROM/RODATA split. RAM's address range (0x0-0x3FF)
   numerically overlaps ROM's -- that's expected and correct here, not a
   bug: they're genuinely different physical memories in cpu_top
   (instr_rom vs data_ram), the same Harvard-architecture split that's
   been true of this whole address map from the start. The linker
   doesn't cross-check for overlap between separately-named MEMORY
   regions, only within a single region's own section placement.
   .bss needs no separate hex-extraction step: data_ram already
   zero-initializes on its own, which is exactly what .bss semantically
   requires, so simply placing it at the right address is sufficient --
   unlike .rodata, which needed real initial content extracted and
   loaded. True .data (non-zero-initialized mutable globals) still isn't
   supported -- that WOULD need an extraction step, deliberately not
   built here since nothing needs it yet. */
MEMORY
{
    ROM    (rx) : ORIGIN = 0x00000000, LENGTH = 4K
    RODATA (r)  : ORIGIN = 0x00030000, LENGTH = 4K
    RAM    (rw) : ORIGIN = 0x00000000, LENGTH = 1K
}

SECTIONS
{
    .text   : { *(.text*) }                > ROM
    .rodata : { *(.rodata*) *(.srodata*) } > RODATA
    .bss    : { *(.bss*) *(.sbss*) }       > RAM
    /DISCARD/ : { *(.data*) *(.sdata*) *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
