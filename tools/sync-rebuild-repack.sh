#!/bin/bash
# One shot: sync the tz-reserved MemoryMapLib fix (Windows 3b5dd96) into the WSL
# uefi-socrates copy, rebuild the firmware incrementally, repack the boot image
# with the new FD + the 8-DTB table + the payload ramdisk.
set -e

echo "== 1. sync MemoryMapLib.c from the Windows repo (3b5dd96)"
SRC=/mnt/d/gittest/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c
DST=/home/yang/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c
cp "$SRC" "$DST"
grep -n "tz-reserved" "$DST" | head -3
git -C /home/yang/unixnu-work/uefi-socrates commit -am \
  "socrates: reserve the 0xD8000000..0xD8100000 hole (sync from Windows 3b5dd96, first-boot hardware evidence)" \
  || echo "(commit failed - identity? continuing uncommitted, the build does not care)"

echo "== 2. rebuild firmware (incremental)"
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
python3 unixnu build firmware --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates

FD=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd
echo "== FD: $(stat -c '%s bytes, %y' "$FD")"
cp "$FD" /mnt/d/gittest/unixnu-work/out/SILICIUM_UEFI-fd-tzfixed.bin

echo "== 3. repack boot image (new FD + 8-DTB table + payload ramdisk)"
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-tzfix
python3 unixnu bootimg --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-tzfix/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-tzfix/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-tzfix/boot.img
echo "== DONE"
