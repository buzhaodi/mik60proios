#!/bin/bash
# Build 6, part 2: the kernel with the PMGR bridge is already built
# (kernel.macho 9e8a4a12). Finish the payload volume and repack.
set -e
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
python3 unixnu build payload --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --unique-chip-id 0000000000000001

echo "== repack (iortfix FD + guards-DTB + new payload)"
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgr
python3 unixnu bootimg --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgr/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-pmgr/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgr/boot.img
echo "== DONE"
