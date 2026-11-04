#!/bin/bash
# Build 8: isolation test - the PMGR-bridge kernel rebooted with the full
# bring-up arg line. Rebuild ONLY the payload with the minimal arg line
# (boot-progress + sheng-pmgr) - the kernel.macho (28a9c998, bridge verified
# inside) is unchanged - and repack.
set -e
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates

cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/board.toml "$BOARD/board.toml"
echo "kernel_args now: $(grep -c '^  "' "$BOARD/board.toml") active (minimal set)"
git -C "$BOARD" add board.toml
git -C "$BOARD" commit -m \
  "payload: minimal countdown kernel_args for the PMGR-bridge isolation boot - the full probe line rebooted the device; boot-progress stays as the only telemetry; probe re-add order documented in the comments" \
  || echo "(commit failed - continuing)"

python3 unixnu build payload --uefi $UEFI -D ../UniXNU-socrates --unique-chip-id 0000000000000001
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgr3
python3 unixnu bootimg --uefi $UEFI -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgr3/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-pmgr3/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgr3/boot.img
echo "== DONE"
