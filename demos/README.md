# demos

The bare-metal programs this CPU ran before RVDOS existed. Each was a
milestone: pixels (`demo.c`), text (`text_demo.c`), a scrolling console
(`console_demo.c`), the keyboard (`echo_demo.c`). Their ROM images live in
`hw/sim/`, where the testbenches load them.

They share the graphics, text, font and keyboard code with the OS, so build
one with `-I../os`, for example:

```
riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -Os -ffreestanding -nostdlib \
    -I../os -T link_console.ld -o echo_demo.elf crt0.s echo_demo.c \
    ../os/gfx.c ../os/text.c ../os/font.c ../os/kbd.c console.c
```

See `docs/CPU.md` for how each one was built and tested.
