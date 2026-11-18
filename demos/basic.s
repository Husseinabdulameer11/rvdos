# Same program as tb_cpu_top.vhd's hand-assembled PROGRAM constant, but
# written as real assembly with labels instead of manually computed
# branch/jump offsets -- this is the whole point of having an assembler.

    addi x1, x0, 5          # x1 = 5
    addi x2, x0, 10          # x2 = 10
    add  x3, x1, x2           # x3 = 15 (needs EX/MEM forwarding)
    sw   x3, 0(x0)              # mem[0] = 15
    lw   x4, 0(x0)                # x4 = 15 (load)
    add  x5, x4, x4                 # x5 = 30 (load-use hazard, forces a stall)
    beq  x3, x4, skip1                # 15 == 15, taken
    addi x6, x0, 999                    # SKIPPED
skip1:
    addi x7, x0, 111
    jal  x8, skip2                        # link = addr of next instr, jump forward
    addi x9, x0, 888                        # SKIPPED
skip2:
    addi x10, x0, 222
    jal  x0, skip2                            # halt (infinite self-loop)
