#!/bin/bash
# Byte-level comparison of the WORKING kernel (9e8a4a12 from boot-pmgr) vs the
# FAILING relink (d39e9740 from boot-abtest): same source, same recipe. The
# difference IS the bug.
set -e
python3 - <<'EOF'
import struct, importlib.util
spec = importlib.util.spec_from_file_location(
    'probe', '/home/yang/unixnu-work/UniXNU/out/socrates/tree/scripts/patch-xnu-entry-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

def load(path):
    data = bytearray(open(path, 'rb').read())
    probe.load_segments(data)
    pc = probe.unixthread_pc(data)
    segs = []
    offset = 32
    ncmds = struct.unpack_from('<I', data, 16)[0]
    for _ in range(ncmds):
        cmd, size = struct.unpack_from('<II', data, offset)
        if cmd == 0x19:
            name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects = struct.unpack_from('<16sQQQQiiI', data, offset + 8)
            segs.append((name.rstrip(b'\0').decode(), vmaddr, vmsize, filesize, initprot))
        offset += size
    return data, pc, segs

good, gpc, gsegs = load('/tmp/kernel-compare/boot-pmgr-kernel.macho')
bad,  bpc, bsegs = load('/tmp/kernel-compare/boot-abtest-kernel.macho')
print(f'good (9e8a4a12-ish): {len(good)} bytes, entry {gpc:#x}')
print(f'bad  (d39e9740)    : {len(bad)} bytes, entry {bpc:#x}')
print()
print('segment comparison (name, va, vmsize, filesize):')
gmap = {s[0]: s for s in gsegs}
bmap = {s[0]: s for s in bsegs}
for name in sorted(set(gmap) | set(bmap)):
    g, b = gmap.get(name), bmap.get(name)
    same = '  ' if g == b else '**'
    print(f' {same} {name:16s} good={g and (hex(g[1]), hex(g[2]), hex(g[3]))} bad={b and (hex(b[1]), hex(b[2]), hex(b[3]))}')

def word(data, va):
    return struct.unpack_from('<I', data, probe.file_offset(va))[0]

print()
print('entry code (first 16 words) diff:')
for i in range(16):
    va = gpc + i * 4
    gw, bw = word(good, va), word(bad, va)
    if gw != bw:
        print(f'  DIFF @ entry+{i*4:#06x}: good {gw:#010x}  bad {bw:#010x}')
print('(done - only differences listed)')
EOF
echo
echo "=== ADT comparison:"
cmp -l /tmp/kernel-compare/boot-pmgr-payload/EFI/UniXNU/Payloads/kernel.macho.adt /tmp/kernel-compare/boot-abtest-payload/EFI/UniXNU/Payloads/kernel.macho.adt 2>/dev/null | head -5 || true
# extract both ADTs from the ramdisks
mkdir -p /tmp/kc2-mnt
for img in boot-pmgr boot-abtest; do
  mount -o loop,ro /tmp/kernel-compare/$img-payload.img /tmp/kc2-mnt 2>/dev/null || continue
  cp /tmp/kc2-mnt/EFI/UniXNU/Payloads/kernel.macho.adt /tmp/kernel-compare/$img.adt 2>/dev/null
  umount /tmp/kc2-mnt
done
ls -la /tmp/kernel-compare/*.adt 2>/dev/null
sha256sum /tmp/kernel-compare/*.adt 2>/dev/null
