# Minimal startup code for a freestanding RV32IM program on this core.
# Sets up the stack pointer, calls main, then halts (infinite loop --
# there's no ecall/exit mechanism on this CPU yet).

    .section .text
    .global _start
_start:
    li sp, 1008        # near top of the 1KB (256-word) default data RAM,
                        # 16-byte aligned per the RV32 calling convention
    call main
halt:
    j halt              # main's return value stays in a0 (x10) forever here
