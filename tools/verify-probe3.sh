#!/bin/bash
# Verify the entry-probe sites in the PATCHED payload kernel using the probe
# tool's own parsing functions.
set -e
K=/tmp/payload-kernel.macho
test -f "$K" || { echo "patched kernel not extracted"; exit 1; }
python3 - "$K" <<'EOF'
import struct, sys, importlib.util
spec = importlib.util.spec_from_file_location(
    'probe', '/home/yang/unixnu-work/UniXNU/out/socrates/tree/scripts/patch-xnu-entry-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

data = bytearray(open(sys.argv[1], 'rb').read())
probe.load_segments(data)
pc = probe.unixthread_pc(data)
print(f'entry pc: {pc:#x}')

def word(va):
    return struct.unpack_from('<I', data, probe.file_offset(va))[0]

def branch_target(from_va, w):
    imm = (w & 0x3FFFFFF) - (1 << 26) if (w & 0x2000000) else (w & 0x3FFFFFF)
    return from_va + imm * 4

# where the tools symbols landed after rebase in the ORIGINAL (unpatched) kernel:
raw = open('/home/yang/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho','rb').read()
rawdata = bytearray(raw)
probe.load_segments(rawdata)
names = probe.rebase(sys.argv[1].replace('x','x'), rawdata) if False else None
# rebase mutates globals on rawdata - reload for patched data instead:
probe.load_segments(data)
probe.rebase('/tmp/payload-kernel.macho', data)
print(f'rebased: entry={probe.ENTRY_VA:#x} start_first_cpu={probe.START_FIRST_CPU:#x} '
      f'mmu={probe.MMU_ENABLE_VA:#x} caves={[hex(v) for v in probe.CAVES.values()]}')
print(f'_panic={probe.PANIC_VA:#x}')

w = word(pc)
print(f'entry word @ {pc:#x}: {w:#010x}')
t1 = branch_target(pc, w)
print(f'stage1 target: {t1:#x}')
blob = bytes(data[probe.file_offset(t1):probe.file_offset(t1) + 0x60])
print(f'stage1 cave bytes: {blob[:24].hex()}')
if all(b == 0 for b in blob[:24]):
    print('!!! STAGE1 CAVE IS ALL ZERO - entry branches into nothing')
else:
    # find the final branch back to start_first_cpu in the cave
    iw = struct.unpack('<24I', blob[:96])
    for i, ins in enumerate(iw):
        if (ins & 0xFC000000) == 0x14000000:
            tgt = branch_target(t1 + i * 4, ins)
            print(f'  cave branch at +{i*4:#x} -> {tgt:#x}' + ('  (= start_first_cpu, probe complete)' if tgt == probe.START_FIRST_CPU else ''))
# stage 2 site
w2 = word(probe.MMU_ENABLE_VA)
print(f'mmu site word: {w2:#010x} (original msr would be d5181000; patched = branch to cave2)')
EOF
