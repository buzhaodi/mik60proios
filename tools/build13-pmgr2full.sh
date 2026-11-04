#!/bin/bash
# Build 13: bridge ladder rung 2 - the SAME bridge kernel (4c6f8436) and the
# SAME proven arg line, only sheng-pmgr=0 -> 2: the mode-2 publication path
# runs for real. Single variable.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/board.toml "$BOARD/board.toml"
git -C "$BOARD" add board.toml
git -C "$BOARD" commit -m "bridge ladder rung 2: sheng-pmgr=2 on the proven line - the publication path runs" \
  || echo "(commit failed - continuing)"

python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgr2full
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgr2full/boot.img
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgr2full/boot.img
grep -o "sheng-pmgr=[02]" out/socrates/logs/payload.log 2>/dev/null | tail -1
echo "== DONE"
