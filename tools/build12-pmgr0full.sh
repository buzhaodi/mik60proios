#!/bin/bash
# Build 12: the bridge-link ladder, step 1. Bridge kernel (CONFIG_XNU_SHENG_PMGR=y,
# archive force-loaded, bsd_init calls sheng_pmgr_run) + the VERBATIM proven arg
# line + sheng-pmgr=0 - the bridge returns at its first line. Decides whether
# merely LINKING the bridge is safe; mode 2 (the runtime publication) is the
# next rung.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/configs/socrates_defconfig "$BOARD/configs/socrates_defconfig"
cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/board.toml "$BOARD/board.toml"
git -C "$BOARD" add board.toml configs/socrates_defconfig
git -C "$BOARD" commit -m "bridge ladder step 1: bridge kernel + verbatim proven args + sheng-pmgr=0 (link-only test)" \
  || echo "(commit failed - continuing)"

python3 unixnu defconfig socrates_defconfig -D ../UniXNU-socrates
grep SHENG_PMGR out/socrates/.config
python3 unixnu build kernel --uefi $UEFI -D ../UniXNU-socrates
python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
echo "== VERIFY the bridge is linked and the args carry mode 0:"
strings out/socrates/kernel/kernel.macho | grep -c sheng_pmgr || true
grep -o "sheng-pmgr=0" out/socrates/.config 2>/dev/null || true
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgr0full
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgr0full/boot.img
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgr0full/boot.img
grep -o "kernel args: .*" out/socrates/logs/payload.log 2>/dev/null | tail -1 || true
echo "== DONE"
