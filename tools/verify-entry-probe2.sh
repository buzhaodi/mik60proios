#!/bin/bash
# Reproduce the payload's entry-probe patch on a copy of the bridge kernel
# (28a9c998) and verify every patch site disassembles to sane code.
set -e
K=/home/yang/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho
T=/tmp/probe-verify
rm -rf "$T"; mkdir -p "$T"
cp "$K" "$T/kernel.macho"
cd /home/yang/unixnu-work/UniXNU/out/socrates/tree
echo "=== run the probe exactly as the payload build does:"
python3 scripts/patch-xnu-entry-probe.py "$T/kernel.macho" --panic-screen --no-reset
echo
echo "=== parse the patched kernel:"
python3 - "$T/kernel.macho" <<'EOF'
import struct, sys
sys.path.insert(0, '/home/yang/unixnu-work/UniXNU/out/socrates/tree/kits/XnuPrelink')
from native_prelink import macho, backed_offset
data = open(sys.argv[1], 'rb').read()
meta = macho(data)
def read(va, size):
    off = backed_offset(meta['segments'], va, size, len(data))
    return data[off:off+size]
for cmd, at, _ in meta['commands']:
    if cmd == 5:
        pc = struct.unpack_from('<Q', data, at + 16)[0]
print(f'entry pc: {pc:#x}')
words = struct.unpack_from('<2I', read(pc, 8))
w = words[0]
if (w & 0xFC000000) == 0x14000000:
    imm = (w & 0x3FFFFFF) - (1 << 26) if (w & 0x2000000) else (w & 0x3FFFFFF)
    target = pc + imm * 4
    print(f'entry: b {target:#x} (offset {imm*4:#x})')
    blob = read(target, 0x50)
    print(f'target bytes: {blob[:20].hex()}')
    if all(b == 0 for b in blob[:20]):
        print('!!! TARGET IS ALL-ZERO: probe branch lands on empty padding')
    # crude check: ARM64 instructions should not be all zeros
    iw = struct.unpack_from('<5I', blob)
    print('target instructions:', [f'{i:#010x}' for i in iw])
else:
    print(f'entry is NOT a branch: {w:#010x}')
EOF
