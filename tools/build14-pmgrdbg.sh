#!/bin/bash
# Build 14: instrument the bridge failure path - one panic carries the failure
# stage and every observation slot. Same proven arg line, sheng-pmgr=2.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/package/ShengPlatformPower.cpp \
   "$BOARD/package/ShengPlatformPower.cpp"
cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/scripts/build-xnu-4k-baseline.sh \
   "$BOARD/scripts/build-xnu-4k-baseline.sh"
chmod +x "$BOARD/scripts/build-xnu-4k-baseline.sh"
git -C "$BOARD" add package/ShengPlatformPower.cpp scripts/build-xnu-4k-baseline.sh
git -C "$BOARD" commit -m "bridge: move sheng_pmgr_run after IOKitBSDInit - pre-IOKit the registry platform does not exist and panics cannot paint; drop the redundant OSKextLoad (ApplePMGR is in our prelink roots)" \
  || echo "(commit failed - continuing)"

python3 unixnu build kernel --uefi $UEFI -D ../UniXNU-socrates
python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgrlate
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgrlate/boot.img
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgrlate/boot.img
grep -o "sheng-pmgr=2" out/socrates/logs/payload.log 2>/dev/null | tail -1
echo "== DONE"
