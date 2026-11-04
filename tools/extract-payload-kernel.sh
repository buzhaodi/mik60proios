#!/bin/bash
# Extract the patched payload kernel from the FAT volume and verify the
# entry-probe patch sites (entry branch target, cave contents).
set -e
P=/home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img
M=/tmp/payload-mnt
K=/tmp/payload-kernel.macho
rm -f "$K"
mkdir -p "$M"
mount -o loop,ro "$P" "$M" 2>/dev/null || { echo "mount failed"; exit 1; }
trap 'umount "$M"' EXIT
ls "$M/EFI/UniXNU/Payloads/" | head -5
cp "$M/EFI/UniXNU/Payloads/kernel.macho" "$K"
echo "extracted: $(sha256sum "$K")"
python3 - "$K" <<'EOF'
import struct, sys
sys.path.insert(0, '/home/yang/unixnu-work/UniXNU/out/socrates/tree/kits/XnuPrelink')
from native_prelink import macho, backed_offset
data = open(sys.argv[1], 'rb').read()
meta = macho(data)
print('segments:')
for seg in meta['segments']:
    print(f"  {seg['name']:16s} va={seg['va']:#x} size={seg['size']:#x} keys={sorted(seg.keys())}")
def read(va, size):
    off = backed_offset(meta['segments'], va, size, len(data))
    return data[off:off+size]
pc = None
for cmd, at, _ in meta['commands']:
    if cmd == 5:
        pc = struct.unpack_from('<Q', data, at + 16 + 0x110)[0]
print(f'entry pc: {pc:#x}')
w = struct.unpack_from('<I', read(pc, 4))[0]
print(f'entry word: {w:#010x}')
if (w & 0xFC000000) == 0x14000000:
    imm = (w & 0x3FFFFFF) - (1 << 26) if (w & 0x2000000) else (w & 0x3FFFFFF)
    target = pc + imm * 4
    print(f'entry: b {target:#x} (offset {imm*4:+d})')
    blob = read(target, 0x50)
    iw = struct.unpack_from('<5I', blob)
    print('branch target instructions:', ' '.join(f'{i:#010x}' for i in iw))
    if all(i == 0 for i in iw):
        print('!!! TARGET ALL-ZERO: probe branch lands on empty padding - KERNEL BROKEN AT ENTRY')
    else:
        print('branch target has code (probe present)')
# also dump the first 32 bytes of __TEXT after the entry
print('entry region:', read(pc - 0x20, 0x40).hex())
EOF
