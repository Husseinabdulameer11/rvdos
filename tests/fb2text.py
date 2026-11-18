#!/usr/bin/env python3
"""fb2text.py FB.txt -- decode a framebuffer dump (64000 lines, one palette
index each, as tb_rvdos.vhd writes it) into the 53x25 text screen, the
same way rvemu --screen does. Lets the GHDL run and the emulator be diffed."""
import re, sys, os
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, '..', 'os', 'font.c')).read()
font = {}
for m in re.finditer(r"\{'(\\.|.)', \{([^}]*)\}\}", src):
    ch = m.group(1)[-1]
    font[tuple(int(x, 16) for x in m.group(2).split(','))] = ch
DESC = set('gjpqy')
fb = [int(l) for l in open(sys.argv[1])]
for row in range(25):
    out = ''
    for col in range(53):
        base = row * 8 * 320 + col * 6
        bg = fb[base + 7 * 320 + 5]
        def rows(off):
            return tuple(sum(0x10 >> k for k in range(5) if fb[base + (r + off) * 320 + k] != bg) for r in range(7))
        bits = rows(0)
        ch = ' ' if not any(bits) else font.get(bits, '#')
        if ch == ' ' and bits != (0,) * 7: ch = '#'
        if ch == '#':
            c2 = font.get(rows(1))
            if c2 in DESC: ch = c2
        out += ch
    print('|' + out.rstrip())
