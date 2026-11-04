#!/bin/bash
# Pack the serial-console firmware into a boot image (kernel + payload + DTB
# unchanged from the repro build; only the FD is the serial variant).
set -e
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

# confirm the FD is the serial build (23:57) and the dsc flag got restored
ls -l --time-style=+%H:%M "$UEFI/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd"
grep "SOCRATES_SERIAL_CONSOLE         = " "$UEFI/Platforms/Xiaomi/socratesPkg/socrates.dsc"

mkdir -p /mnt/d/gittest/mik60proios/prebuilt-test
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/mik60proios/prebuilt-test/boot-serial.img
sha256sum /mnt/d/gittest/mik60proios/prebuilt-test/boot-serial.img
echo "== DONE"
