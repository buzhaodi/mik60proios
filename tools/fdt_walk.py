#!/usr/bin/env python3
"""Walk Android DTBO images and raw DTBs, dump a text tree.

Read-only byte parser: FDT v17 struct tokens only; never executes anything.
Usage:
  fdt_walk.py dtbo <file.img> [entry_index]
  fdt_walk.py dtb   <file.dtb>
"""
import struct
import sys

FDT_MAGIC = 0xD00DFEED
DTBO_MAGIC = 0xD7B7AB1E
BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


def parse_fdt_header(blob):
    (magic, totalsize, off_struct, off_strings, off_memrsv,
     version, last_comp, boot_cpu, size_strings, size_struct) = struct.unpack_from('>10I', blob, 0)
    if magic != FDT_MAGIC:
        raise ValueError(f'not an FDT (magic {magic:#x})')
    return dict(totalsize=totalsize, off_struct=off_struct, off_strings=off_strings,
                off_memrsv=off_memrsv, version=version)


def get_string(blob, off_strings, offset):
    end = blob.index(b'\0', off_strings + offset)
    return blob[off_strings + offset:end].decode('ascii', 'replace')


def printable(data):
    if not data:
        return ''
    if all(32 <= b < 127 or b in (0,) for b in data) and data[-1] == 0 and len(data) > 1:
        s = data[:-1].decode('ascii')
        if s and all(32 <= ord(c) < 127 for c in s):
            return f'"{s}"'
    return data.hex()


def walk(blob, out):
    h = parse_fdt_header(blob)
    pos = h['off_struct']
    end_pos = h['off_struct'] + (h.get('size_struct') or (len(blob) - h['off_struct']))
    depth = 0
    path = []
    while pos < end_pos:
        (token,) = struct.unpack_from('>I', blob, pos)
        pos += 4
        if token == BEGIN_NODE:
            nul = blob.index(b'\0', pos)
            name = blob[pos:nul].decode('ascii', 'replace')
            pos = (nul + 4) & ~3
            path.append(name)
            out.append('  ' * depth + '/ ' + name)
            depth += 1
        elif token == END_NODE:
            depth -= 1
            path.pop()
        elif token == PROP:
            (length, nameoff) = struct.unpack_from('>II', blob, pos)
            pos += 8
            data = blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
            name = get_string(blob, h['off_strings'], nameoff)
            out.append('  ' * depth + f'{name} = {printable(data)}')
        elif token == NOP:
            continue
        elif token == END:
            break
        else:
            raise ValueError(f'bad token {token:#x} at {pos:#x}')


def parse_dtbo(blob, out):
    (magic, total, header_size, entry_size, entry_count,
     page_size, version) = struct.unpack_from('>7I', blob, 0)
    if magic != DTBO_MAGIC:
        raise ValueError(f'not a DTBO (magic {magic:#x})')
    out.append(f'# DTBO: {entry_count} entries, entry_size {header_size if header_size == 0 else entry_size}')
    width = entry_size // 4
    entries = []
    for i in range(entry_count):
        off = header_size + i * entry_size
        if version == 0:
            (dt_size, dt_offset, eid, rev, c0, c1, c2, c3) = struct.unpack_from('>8I', blob, off)
            entries.append((dt_size, dt_offset, eid, rev, (c0, c1, c2, c3)))
        else:
            fields = struct.unpack_from(f'>{width}I', blob, off)
            entries.append((fields[0], fields[1], fields[2], fields[3], fields[4:]))
    return entries


def main():
    mode, path = sys.argv[1], sys.argv[2]
    blob = open(path, 'rb').read()
    out = []
    if mode == 'dtb':
        walk(blob, out)
    elif mode == 'dtbo':
        entries = parse_dtbo(blob, out)
        want = int(sys.argv[3]) if len(sys.argv) > 3 else None
        for i, (size, offset, eid, rev, custom) in enumerate(entries):
            out.append(f'# entry {i}: size {size} @{offset:#x} id {eid:#x} rev {rev:#x} custom {[hex(c) for c in custom]}')
            if want is None or i == want:
                walk(blob[offset:offset + size], out)
    else:
        raise SystemExit(f'unknown mode {mode}')
    print('\n'.join(out))


if __name__ == '__main__':
    main()
