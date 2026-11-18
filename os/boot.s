# boot.s -- reset vector and the fixed BDOS entry vector for RVDOS.
#
# The .vectors section is placed first in ROM by link_os.ld, so:
#   0x0000: j _start          (CPU begins here at reset)
#   0x0004: j bdos_dispatch    (the fixed syscall entry -- CP/M's "CALL 5")
#
# A program reaches the OS with `jalr ra, 4`: it lands on the word at
# 0x0004, which jumps to the dispatcher with the caller's return address
# still in ra, so the dispatcher's ordinary `ret` returns to the program.

    .section .vectors, "ax"
    .global _reset
_reset:
    j _start                 # 0x0000  reset
    j bdos_dispatch          # 0x0004  BDOS entry vector (ABI address = 4)

    .section .text
    .global _start
_start:
    la   sp, _stack_top      # from link_os.ld, 16-byte aligned

    # Zero .bss. Pressing reset does not clear BRAM, so without this a
    # warm start would see the previous run's variables. The RAM disk is
    # deliberately in its own region (.noinit) and is left alone, so files
    # survive a reset.
    la   t0, _bss_start
    la   t1, _bss_end
1:  bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:
    call ccp_main            # enter the shell; returns only on HALT
_halt:
    j _halt
