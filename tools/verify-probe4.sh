#!/bin/bash
# Direct verification of the patched kernel: entry branch -> stage1 cave ->
# back-jump to start_first_cpu. No rebase needed - read the patched bytes.
set -e
python3 - <<'EOF'
import struct, importlib.util
spec = importlib.util.spec_from_file_location(
    'probe', '/home/yang/unixnu-work/UniXNU/out/socrates/tree/scripts/patch-xnu-entry-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)

data = bytearray(open('/tmp/payload-kernel.macho', 'rb').read())
probe.load_segments(data)
pc = probe.unixthread_pc(data)
print(f'entry pc: {pc:#x}')

def word(va):
    return struct.unpack_from('<I', data, probe.file_offset(va))[0]

def btarget(from_va, w):
    imm = (w & 0x3FFFFFF) - (1 << 26) if (w & 0x2000000) else (w & 0x3FFFFFF)
    return from_va + imm * 4

w = word(pc)
print(f'entry word: {w:#010x}')
t1 = btarget(pc, w)
print(f'entry branches to: {t1:#x}')
start = probe.file_offset(t1)
blob = bytes(data[start:start + 0x80])
print(f'stage1 cave first 32 bytes: {blob[:32].hex()}')
if all(b == 0 for b in blob[:32]):
    print('!!! STAGE1 CAVE ALL-ZERO - entry jumps into empty padding. BROKEN.')
else:
    iw = struct.unpack('<32I', blob)
    print('cave instructions:')
    for i, ins in enumerate(iw):
        if ins == 0:
            print(f'  +{i*4:#04x} end of code')
            break
        line = f'  +{i*4:#04x} {ins:#010x}'
        if (ins & 0xFC000000) == 0x14000000:
            line += f'  b {btarget(t1 + i*4, ins):#x}'
        print(line)
# also verify the source kernel's entry region for comparison (what the original looks like)
raw = bytearray(open('/home/yang/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho', 'rb').read())
probe.load_segments(raw)
raw_pc = probe.unixthread_pc(raw)
print(f'source kernel entry pc: {raw_pc:#x}')
print(f'source entry word: {struct.unpack_from("<I", raw, probe.file_offset(raw_pc))[0]:#010x}')
names = probe.rebase('/home/yang/unixnu-work/UniXNU/out/socrates/kernel/kernel.macho', raw)
print(f'rebased START_FIRST_CPU: {probe.START_FIRST_CPU:#x}, MMU: {probe.MMU_ENABLE_VA:#x}, caves: {[hex(v) for v in probe.CAVES.values()]}')
print(f'source cave1 free (all zero)? {not any(raw[probe.file_offset(probe.CAVES[1]):probe.file_offset(probe.CAVES[1]) + probe.CAVE_SIZE])}')
EOF
