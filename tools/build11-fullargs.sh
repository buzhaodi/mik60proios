#!/bin/bash
# Build 11: the no-bridge kernel (d39e9740, byte-identical executable to the
# working 9e8a4a12) + the FULL argument line with the offline-legacy-* display
# args restored. One clean-state boot decides: if this reaches the AMFI panic,
# the minimal-args experiment was the confounder and the bridge kernel needs a
# fresh look; if it still garbles, the relink metadata is the problem.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/board.toml "$BOARD/board.toml"
git -C "$BOARD" add board.toml
git -C "$BOARD" commit -m "payload: restore the offline-legacy-* display args - without them the native display path garbles the panel and resets; sheng-pmgr=0 on the no-bridge kernel" \
  || echo "(commit failed - continuing)"

python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-fullargs
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-fullargs/boot.img
sha256sum /mnt/d/gittest/unixnu-work/out/boot-fullargs/boot.img
grep -o "kernel args: .*" /home/yang/unixnu-work/UniXNU/out/socrates/logs/payload*.log 2>/dev/null | tail -1 || true
echo "== DONE"
