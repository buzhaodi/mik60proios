#!/bin/bash
# Build 9: bisect the reboot. Same kernel (28a9c998, bridge linked in), only
# the boot arg changes: sheng-pmgr=0 - sheng_pmgr_run returns immediately.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/board.toml "$BOARD/board.toml"
git -C "$BOARD" add board.toml
git -C "$BOARD" commit -m "payload: watchdog-bridge boot: minimal args + watchdog control + sheng-pmgr=2" \
  || echo "(commit failed - continuing)"

python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-wdtfix
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-wdtfix/boot.img
sha256sum /mnt/d/gittest/unixnu-work/out/boot-wdtfix/boot.img
echo "== DONE"
