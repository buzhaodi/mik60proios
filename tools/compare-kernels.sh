#!/bin/bash
# Extract the kernel from every saved boot image and compare entry VA + layout
# across working and rebooting boots.
set -e
OUT=/mnt/d/gittest/unixnu-work/out
W=/tmp/kernel-compare
rm -rf "$W"; mkdir -p "$W"

for img in boot-instr boot-pmgr boot-pmgr2 boot-pmgr3 boot-wdtfix boot-abtest; do
  f="$OUT/$img/boot.img"
  [ -f "$f" ] || continue
  python3 - "$f" "$W/$img-payload.img" <<'EOF'
import struct, sys
data = open(sys.argv[1], 'rb').read()
page = struct.unpack_from('<I', data, 40)[0]
header_version = struct.unpack_from('<I', data, 40)[0]
# v0: kernel_size at 8, page size at 36
kernel_size = struct.unpack_from('<I', data, 8)[0]
page_size = struct.unpack_from('<I', data, 36)[0]
ramdisk_size = struct.unpack_from('<I', data, 16)[0]
kpages = (kernel_size + page_size - 1) // page_size
at = page_size * (1 + kpages)
open(sys.argv[2], 'wb').write(data[at:at + ramdisk_size])
print(f'{sys.argv[1].split("/")[-2]}: ramdisk {ramdisk_size} bytes extracted')
EOF
done

echo
mkdir -p /tmp/kc-mnt
for img in boot-instr boot-pmgr boot-pmgr2 boot-pmgr3 boot-wdtfix boot-abtest; do
  p="$W/$img-payload.img"
  [ -f "$p" ] || continue
  mount -o loop,ro "$p" /tmp/kc-mnt 2>/dev/null || { echo "$img: mount failed"; continue; }
  cp /tmp/kc-mnt/EFI/UniXNU/Payloads/kernel.macho "$W/$img-kernel.macho" 2>/dev/null
  cp /tmp/kc-mnt/EFI/UniXNU/unixnu.toml "$W/$img-unixnu.toml" 2>/dev/null
  umount /tmp/kc-mnt
  echo "$img: $(sha256sum "$W/$img-kernel.macho" 2>/dev/null | cut -c1-16)"
done

echo "=== entry VAs:"
python3 - <<'EOF'
import struct, importlib.util, glob
spec = importlib.util.spec_from_file_location(
    'probe', '/home/yang/unixnu-work/UniXNU/out/socrates/tree/scripts/patch-xnu-entry-probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
for path in sorted(glob.glob('/tmp/kernel-compare/*-kernel.macho')):
    data = bytearray(open(path, 'rb').read())
    probe.load_segments(data)
    pc = probe.unixthread_pc(data)
    text = [s for s in probe.SEGMENTS]
    segs = ', '.join(f"{s[0]}@{s[1]:#x}" for s in text[:3]) if text else '?'
    print(f'{path.split("/")[-1]:28s} entry={pc:#x}  size={len(data)>>20}MB  first-segs: {segs}')
EOF
