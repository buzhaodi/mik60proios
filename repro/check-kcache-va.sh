#!/bin/bash
# Are the audit's fixed kext VAs backed in the ORIGINAL kernelcache, and do the
# audited instruction contracts hold there? If yes, the kernelcache is a valid
# first-build reference candidate.
python3 - <<'EOF'
import struct, sys
sys.path.insert(0, '/home/yang/unixnu-work/UniXNU/out/socrates/tree/kits/XnuPrelink')
from native_prelink import macho, backed_offset
data = open('/home/yang/unixnu-work/UniXNU/out/ipsw/21H461/kernelcache.decompressed','rb').read()
meta = macho(data)
def read(va, size):
    at = backed_offset(meta['segments'], va, size, len(data))
    return data[at:at+size]
# the audit's instruction contracts:
contracts = [
    (0xfffffff004aaeb40, (0x94006c46, 0x321e0015, 0xaa1403e0, 0xaa1503e1, 0x94006c45)),
    (0xfffffff004a24adc, (0xf9404400, 0xb4000080, 0xf9400008, 0xf9450101, 0xd61f0020, 0x12800000, 0xd65f03c0)),
    (0xfffffff004a230ec, (0xf9404400, 0xb4000080, 0xf9400008, 0xf9450502, 0xd61f0040, 0xd65f03c0)),
    (0xfffffff004a20fbc, (0x12800000, 0xd65f03c0, 0xd65f03c0)),
]
ok = True
for va, expected in contracts:
    try:
        got = struct.unpack('<' + 'I'*len(expected), read(va, 4*len(expected)))
        match = got == tuple(expected)
    except ValueError:
        got, match = None, False
    print(f'{va:#x}: {"MATCH" if match else "DIFF/unbacked"}  got={got}')
    ok = ok and match
try:
    name = read(0xfffffff0042dde02, 13)
    print('ApplePMGRNub string:', name)
except ValueError:
    print('ApplePMGRNub VA unbacked in kernelcache')
print('VERDICT:', 'kernelcache is a valid reference' if ok else 'addresses differ - slide needed')
EOF
