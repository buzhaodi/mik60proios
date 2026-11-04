#!/bin/bash
# Build 7: the resolved out/socrates/.config still carried CONFIG_XNU_SHENG_PMGR=n
# from project setup - the repo defconfig flip never reached the build. Regenerate
# it, rebuild the kernel (bsd_init.o + relink + prelink only), VERIFY the bridge
# symbols landed, then payload + boot image.
set -e
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates
BOARD=/home/yang/unixnu-work/UniXNU-socrates

echo "== 1. regenerate the resolved config from the board defconfig"
python3 unixnu defconfig socrates_defconfig -D ../UniXNU-socrates
grep SHENG_PMGR out/socrates/.config

echo "== 2. rebuild the kernel with the bridge"
python3 unixnu build kernel --uefi $UEFI -D ../UniXNU-socrates

echo "== 3. VERIFY the bridge is really in this time"
T=out/socrates/tree
strings "$T/build/xnu/ios-obj/DEVELOPMENT_ARM64_BCM2837/bsd/DEVELOPMENT/bsd_init.o" | grep -i sheng_pmgr | head -3
nm out/socrates/kernel/kernel.macho 2>/dev/null | grep -i "sheng_pmgr\|ShengPlatformPower" | head -6
strings out/socrates/kernel/kernel.macho | grep -i "sheng_pmgr" | head -3

echo "== 4. payload + repack"
python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgr2
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgr2/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-pmgr2/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgr2/boot.img
echo "== DONE"
