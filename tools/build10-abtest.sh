#!/bin/bash
# Build 10: the A/B control kernel - defconfig back to CONFIG_XNU_SHENG_PMGR=n
# (bridge compiled out, bsd_init without the call, archive not force-loaded),
# same minimal args line. If THIS boots to the AMFI panic, the kernel binary
# delta (the linked bridge archive / LTO relayout) is the sole trigger.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/configs/socrates_defconfig "$BOARD/configs/socrates_defconfig"
python3 unixnu defconfig socrates_defconfig -D ../UniXNU-socrates
grep SHENG_PMGR out/socrates/.config

python3 unixnu build kernel --uefi $UEFI -D ../UniXNU-socrates
python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-abtest
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-abtest/boot.img
sha256sum /mnt/d/gittest/unixnu-work/out/boot-abtest/boot.img
echo "== kernel size for the record:"
ls -la out/socrates/kernel/kernel.macho
echo "== DONE"
