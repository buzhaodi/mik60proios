#!/bin/bash
# Build 5: the crash is solved at the source - IortDtDxe scanned an uninitialized
# XblDtRegion because the generator had renamed the "XBL DT" stock region to the
# DT node name (stack garbage 0xD8000000 = the region base it dereferenced).
# Fixes: generator prefers the stock cfg name on stock-covered segments (names
# are the LocateMemoryRegionByName ABI), one more protected gap (0xDFC00000,
# outside every DRAM bank), and the driver zero-initialises its descriptor.
set -e

echo "== 1. sync the changed files from the Windows repos"
UEFI=/home/yang/unixnu-work/uefi-socrates
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cp /mnt/d/gittest/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c \
   "$UEFI/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c"
cp /mnt/d/gittest/unixnu-work/uefi-socrates/Silicon/Qualcomm/QcomPkg/Drivers/IortDtDxe/IortDtDxe.c \
   "$UEFI/Silicon/Qualcomm/QcomPkg/Drivers/IortDtDxe/IortDtDxe.c"
# the checker now allows a DT reservation to partition across several Reserved
# descriptors (union coverage) - the stock-name rename split adspslpi/aop_config
cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/scripts/check-socrates.py \
   "$BOARD/scripts/check-socrates.py"
echo "XBL DT descriptor:  $(grep -c '"XBL DT"' "$UEFI/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c")"
echo "zero-init in driver: $(grep -c 'XblDtRegion = {0}' "$UEFI/Silicon/Qualcomm/QcomPkg/Drivers/IortDtDxe/IortDtDxe.c")"
echo "union coverage rule:  $(grep -c 'Union coverage' "$BOARD/scripts/check-socrates.py")"
git -C "$BOARD" add scripts/check-socrates.py
git -C "$BOARD" commit -m \
  "check: union coverage for DT reservations - the generator now names segments by the covering stock cfg label, and one reservation can meet two stock regions (adspslpi, aop_config)" \
  || echo "(board commit failed - identity? continuing)"
git -C "$UEFI" commit -am \
  "socrates: keep the stock cfg region names (LocateMemoryRegionByName ABI - the DT-node rename made IortDtDxe scan stack garbage 0xD8000000); protect the 0xDFC00000 bank-external gap; zero-init the driver descriptor" \
  || echo "(commit failed - identity? continuing uncommitted, the build does not care)"

echo "== 2. rebuild firmware (incremental)"
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
python3 unixnu build firmware --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates

FD=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd
echo "== FD: $(stat -c '%s bytes, %y' "$FD")"
cp "$FD" /mnt/d/gittest/unixnu-work/out/SILICIUM_UEFI-fd-iortfix.bin

echo "== 3. repack (guards-DTB + payload)"
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-iortfix
python3 unixnu bootimg --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-iortfix/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-iortfix/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-iortfix/boot.img
echo "== DONE"
