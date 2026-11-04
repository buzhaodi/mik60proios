#!/bin/bash
# Content-level range diff of the working vs failing kernel binaries.
python3 - <<'EOF'
g = open('/tmp/kernel-compare/boot-pmgr-kernel.macho','rb').read()
b = open('/tmp/kernel-compare/boot-abtest-kernel.macho','rb').read()
assert len(g) == len(b)
runs, start = [], None
for i in range(len(g)):
    if g[i] != b[i]:
        if start is None:
            start = i
    else:
        if start is not None:
            # require 64 identical bytes to close a run (bridge gaps)
            if all(g[j] == b[j] for j in range(i, min(i + 64, len(g)))):
                runs.append((start, i))
                start = None
if start is not None:
    runs.append((start, len(g)))
total = sum(e - s for s, e in runs)
print(f'{len(runs)} differing regions, {total} bytes total (of {len(g)})')

# map to segments
import struct
segs = []
offset = 32
ncmds = struct.unpack_from('<I', g, 16)[0]
header_blob = g[:64]
cmd = g
for _ in range(ncmds):
    c, size = struct.unpack_from('<II', g, offset)
    if c == 0x19:
        name, vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<16sQQQQ', g, offset + 8)
        segs.append((name.rstrip(b'\0').decode(), fileoff, filesize, vmaddr))
    offset += size
def where(off):
    for name, fileoff, filesize, vmaddr in segs:
        if fileoff <= off < fileoff + filesize:
            return f'{name} (va {vmaddr + off - fileoff:#x})'
    return f'header/other'
for s, e in runs[:40]:
    print(f'  [{s:#010x}..{e:#010x}) len={e-s:6d}  -> {where(s)}')
EOF
