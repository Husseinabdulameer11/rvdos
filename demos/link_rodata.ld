/* Two separate memory regions now, matching cpu_top's Harvard-style
   memories: .text goes to ROM (instr_rom, fetched via PC), .rodata goes
   to its own RODATA region (rodata_rom, reachable by lw/lb) at
   0x00030000, matching cpu_top's RODATA_BASE. These get extracted into
   two SEPARATE hex files below -- one ELF, two ROM images. */
MEMORY
{
    ROM    (rx) : ORIGIN = 0x00000000, LENGTH = 4K
    RODATA (r)  : ORIGIN = 0x00030000, LENGTH = 4K
}

SECTIONS
{
    .text   : { *(.text*) }                    > ROM
    .rodata : { *(.rodata*) *(.srodata*) }     > RODATA
    /DISCARD/ : { *(.data*) *(.sdata*) *(.bss*) *(.sbss*) *(.comment) *(.riscv.attributes) *(.eh_frame) }
}
