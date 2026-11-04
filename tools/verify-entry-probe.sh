#!/bin/bash
# Disassemble and verify the entry-probe patch sites in the payload kernel copy
# (the patched one) - entry branch, cave 1..4 content, MMU site, panic site.
set -e
K=/home/yang/unixnu-work/UniXNU/out/socrates/payload/stage/EFI/UniXNU/Payloads/kernel.macho
TC=/home/yang/unixnu-work/UniXNU/out/socrates/toolchain
NM=/usr/bin/llvm-nm
OD=/usr/bin/llvm-objdump
echo "=== kernel in payload: $(sha256sum "$K" | cut -c1-16)"
echo "=== unixthread entry (LC_UNIXTHREAD pc):"
python3 - <<'EOF'
import struct, sys
sys.path.insert(0, '/home/yang/unixnu-work/UniXNU/out/socrates/tree/kits/XnuPrelink')
from native_prelink import macho, backed_offset
data = open('/home/yang/unixnu-work/UniXNU/out/socrates/payload/stage/EFI/UniXNU/Payloads/kernel.macho','rb').read()
meta = macho(data)
print('segments:')
for seg in meta['segments']:
    print(f"  {seg['name']:16s} va={seg['va']:#x} vmsize={seg['vmsize']:#x} fileoff={seg['fileoff']:#x} filesize={seg['filesize']:#x}")
# LC_UNIXTHREAD (cmd 5)
for cmd, at, _ in meta['commands']:
    if cmd == 5:
        pc = struct.unpack_from('<Q', data, at + 16)[0]
        print(f'LC_UNIXTHREAD pc = {pc:#x}')
def read(va, size):
    off = backed_offset(meta['segments'], va, size, len(data))
    return data[off:off+size]
e = read(pc, 16)
print(f'entry bytes @ {pc:#x}: {e.hex()}')
w = struct.unpack_from('<I', e, 0)[0]
if (w & 0xFC000000) == 0x14000000:
    target = pc + ((w & 0x3FFFFFF) << 2 if not (w & 0x2000000) else ((w & 0x3FFFFFF) - (1 << 26)) * 4)
    target = pc + (((w & 0x3FFFFFF) ^ 0x2000000) - 0x2000000 if (w & 0x2000000) else (w & 0x3FFFFFF)) * 4
    print(f'entry branches to {target:#x}')
    cave = read(target, 0x40)
    print(f'cave/branch-target first 16 bytes: {cave[:16].hex()}')
    if all(b == 0 for b in cave[:16]):
        print('!! BRANCH TARGET IS ZERO PADDING - the probe did not land here')
EOF
echo
echo "=== objdump entry region:"
"$OD" -d --start-address=0xFFFFFFF00B9D0400 --stop-address=0xFFFFFFF00B9D0700 "$K" 2>/dev/null | head -40 || echo "(objdump range needs the real entry VA - see above)"
