#!/bin/bash
# Repack the boot image with the guard-injected 8-DTB table. The firmware
# volume is unchanged (the 08:23 tz-fixed build) - this fix is DT-side only.
set -e
cd /home/yang/unixnu-work/UniXNU
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-dtfix
python3 unixnu bootimg --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-dtfix/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-dtfix/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-dtfix/boot.img
echo "== DONE"
