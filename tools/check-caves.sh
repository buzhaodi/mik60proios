#!/bin/bash
# Are the entry-probe caves still zero padding in the new kernel, or did the
# bridge archive force-load fill them with real content?
python3 - <<'EOF'
import struct, sys
sys.path.insert(0, '/home/yang/unixnu-work/UniXNU/out/socrates/tree/kits/XnuPrelink')
from native_prelink import macho, backed_offset
for label, path in (('NEW (28a9c998, reboots)', '/home/yang/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho'),
                    ('OLD (9e8a4a12? may be gone)', '/mnt/d/gittest/unixnu-work/out/SILICIUM_UEFI-fd-iortfix.bin')):
    pass
data = open('/home/yang/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho','rb').read()
meta = macho(data)
def read(va, size):
    at = backed_offset(meta['segments'], va, size, len(data))
    return data[at:at+size]
CAVES = {1: 0xFFFFFFF00B9D0500, 2: 0xFFFFFFF00B9D0560, 3: 0xFFFFFFF00B9D05C0, 4: 0xFFFFFFF00B9D0620}
for n, va in sorted(CAVES.items()):
    blob = read(va, 0x60)
    nonzero = sum(1 for b in blob if b)
    print(f'cave {n} @ {va:#x}: {nonzero}/96 nonzero bytes  first16={blob[:16].hex()}')
e = read(0xFFFFFFF00B9D0488, 16)
print('entry VA bytes:', e.hex(), '(expect 1e000014 little-endian b +0x78)')
s = read(0xFFFFFFF00B9D205C, 16)
print('start_first_cpu:', s.hex())
EOF
echo "=== does the tool check caves for zero?"
grep -n "cave\|CAVE\|zero\|b'\\\\x00" /home/yang/unixnu-work/UniXNU/out/socrates/tree/scripts/patch-xnu-entry-probe.py 2>/dev/null | grep -i "zero\|b'\|assert\|require" | head -8
grep -n "def.*cave\|PANIC_CAVE\|caves" /home/yang/unixnu-work/UniXNU/out/socrates/tree/scripts/patch-xnu-entry-probe.py | head -8
