/* Places everything into the 4KB instr_rom address range starting at 0.
   .data/.bss are discarded rather than silently mis-placed -- this
   linker script only supports programs with zero global/static data,
   consistent with this CPU's current Harvard-memory limitation. */
MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS
{
    .text : { *(.text*) } > ROM
    .rodata : { *(.rodata*) } > ROM
    /DISCARD/ : { *(.data*) *(.bss*) *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
