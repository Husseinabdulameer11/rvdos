#!/usr/bin/env python3
"""rvdisk.py -- look inside and change an RVDOS drive A: image (the file
rvemu keeps with --disk=FILE), from the host PC.

    python3 rvdisk.py rvdos.disk ls
    python3 rvdisk.py rvdos.disk put GAME.FLT [MORE.FLT ...]   # copy in
    python3 rvdisk.py rvdos.disk get GAME.FLT [DEST]            # copy out
    python3 rvdisk.py rvdos.disk rm GAME.FLT
    python3 rvdisk.py rvdos.disk format        # empty disk (no samples:
                                              # RVDOS adds those itself only
                                              # when the image is invalid)

The layout must match os.c (struct disk) and link_os.ld (DISK_SIZE).
"""
import os, struct, sys

DISK_SIZE = 10 * 1024
NDIR = 48
MAGIC = 0x31445652          # "RVD1"
HDR = 16 + NDIR * 24        # magic, sum, used, nfiles + directory
DATA = DISK_SIZE - HDR

def checksum(img, used):
    n = (HDR + used + 3) // 4
    words = struct.unpack_from('<%dI' % n, img + b'\0' * 4)
    s = 0x5A5A1234
    for w in words[2:n]:
        s = (((s << 1) | (s >> 31)) & 0xFFFFFFFF) ^ w
    return s

def load(path):
    if not os.path.exists(path):
        return []
    img = open(path, 'rb').read().ljust(DISK_SIZE, b'\0')
    magic, s, used, nfiles = struct.unpack_from('<4I', img)
    if magic != MAGIC or nfiles > NDIR or used > DATA or checksum(img, used) != s:
        sys.exit(f"{path}: not a valid RVDOS disk (RVDOS formats it at the next cold start)")
    files = []
    for i in range(nfiles):
        name, size, off = struct.unpack_from('<16sII', img, 16 + i * 24)
        files.append((name.split(b'\0')[0].decode(), img[HDR + off:HDR + off + size]))
    return files

def save(path, files):
    used = sum(len(d) for _, d in files)
    if len(files) > NDIR: sys.exit("directory full")
    if used > DATA: sys.exit(f"disk full: {used} bytes, room for {DATA}")
    img = bytearray(DISK_SIZE)
    off = 0
    for i, (name, data) in enumerate(files):
        struct.pack_into('<16sII', img, 16 + i * 24, name.encode(), len(data), off)
        img[HDR + off:HDR + off + len(data)] = data
        off += len(data)
    struct.pack_into('<4I', img, 0, MAGIC, 0, used, len(files))
    struct.pack_into('<I', img, 4, checksum(bytes(img), used))
    open(path, 'wb').write(img)

def cpm_name(path):
    name = os.path.basename(path).upper()
    base, _, ext = name.partition('.')
    ok = set('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-$')
    if not (1 <= len(base) <= 8 and len(ext) <= 3 and set(base + ext) <= ok):
        sys.exit(f"{path}: needs an 8.3 name (A-Z 0-9 _ - $)")
    return name

def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    path, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3:]
    if cmd == 'format':
        save(path, []); return
    files = load(path)
    if cmd == 'ls':
        for name, data in files:
            print(f"{len(data):7d}  {name}")
        print(f"{DATA - sum(len(d) for _, d in files)} bytes free")
    elif cmd == 'put':
        for src in args:
            name = cpm_name(src)
            data = open(src, 'rb').read().replace(b'\r\n', b'\n')
            files = [f for f in files if f[0] != name] + [(name, data)]
        save(path, files)
    elif cmd == 'get':
        name = args[0].upper()
        hit = [d for n, d in files if n == name]
        if not hit: sys.exit(f"{name}: no such file")
        open(args[1] if len(args) > 1 else name, 'wb').write(hit[0])
    elif cmd == 'rm':
        names = {a.upper() for a in args}
        save(path, [f for f in files if f[0] not in names])
    else:
        sys.exit(__doc__)

if __name__ == '__main__':
    main()
