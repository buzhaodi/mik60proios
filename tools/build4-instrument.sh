#!/bin/bash
# Build 4: reserve every protected DRAM gap in MemoryMapLib (the 0x82800000 TZ
# core hole was still Conv) and add bring-up prints to SocratesBootMemoryDxe
# (raw x0 dtb pointer before any read + every reg it collects), then rebuild
# the FD and repack with the guard-injected 8-DTB table and the payload.
set -e

echo "== 1. sync the two changed files from the Windows repo"
UEFI=/home/yang/unixnu-work/uefi-socrates
cp /mnt/d/gittest/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c \
   "$UEFI/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c"
cp /mnt/d/gittest/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Drivers/SocratesBootMemoryDxe/SocratesBootMemoryDxe.c \
   "$UEFI/Platforms/Xiaomi/socratesPkg/Drivers/SocratesBootMemoryDxe/SocratesBootMemoryDxe.c"
echo "protected gaps synced: $(grep -c 'protected gap' "$UEFI/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c")"
echo "print lines synced:    $(grep -c 'SocratesMEM' "$UEFI/Platforms/Xiaomi/socratesPkg/Drivers/SocratesBootMemoryDxe/SocratesBootMemoryDxe.c")"
git -C "$UEFI" commit -am \
  "socrates: reserve every protected DRAM gap (TZ core 0x82800000 was Conv) + SocratesBootMemoryDxe bring-up prints" \
  || echo "(commit failed - identity? continuing uncommitted, the build does not care)"

echo "== 2. rebuild firmware (incremental)"
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
python3 unixnu build firmware --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates

FD=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd
echo "== FD: $(stat -c '%s bytes, %y' "$FD")"
cp "$FD" /mnt/d/gittest/unixnu-work/out/SILICIUM_UEFI-fd-protfix.bin

echo "== 3. repack (guards-DTB + payload)"
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-instr
python3 unixnu bootimg --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-instr/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-instr/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-instr/boot.img
echo "== DONE"
