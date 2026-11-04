#!/bin/bash
# Build 6: enable the original-PMGR bridge so AMFI's ApplePMGRNub latch finds
# a provider-less nub (first-boot evidence 2026-11-04: "AMFI: No PMGR?"
# @ConfigurationSettings.cpp:235 on the RAM root). Kernel step rebuilds only
# bsd_init.o (the SHENG_PMGR stamp), relinks and re-prelinks; the firmware is
# unchanged (the iortfix FD), so only kernel + payload + boot image rebuild.
set -e

echo "== 1. sync the three changed files from the Windows repo"
BOARD=/home/yang/unixnu-work/UniXNU-socrates
cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/board.toml "$BOARD/board.toml"
cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/configs/socrates_defconfig "$BOARD/configs/socrates_defconfig"
cp /mnt/d/gittest/unixnu-work/UniXNU-socrates/scripts/build-sheng-platform-power.py "$BOARD/scripts/build-sheng-platform-power.py"
chmod +x "$BOARD/scripts/build-sheng-platform-power.py"
echo "defconfig PMGR:  $(grep SHENG_PMGR "$BOARD/configs/socrates_defconfig")"
echo "args sheng-pmgr: $(grep -c 'sheng-pmgr=2' "$BOARD/board.toml")"
git -C "$BOARD" add board.toml configs/socrates_defconfig scripts/build-sheng-platform-power.py
git -C "$BOARD" commit -m \
  "pmgr: enable the original-PMGR bridge (provider-less ApplePMGRNub, CONFIG_XNU_SHENG_PMGR) - first-boot evidence 2026-11-04: AMFI 'No PMGR?' panic at ConfigurationSettings.cpp:235 on the RAM root; the vermeer builder verifies against the pinned original kernelcache" \
  || echo "(commit failed - identity? continuing uncommitted, the build does not care)"

echo "== 2. rebuild the kernel (archives + bsd_init.o + relink + prelink)"
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
python3 unixnu build kernel --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates

echo "== 3. rebuild the payload volume"
python3 unixnu build payload --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates

echo "== 4. repack (iortfix FD + guards-DTB + new payload)"
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-pmgr
python3 unixnu bootimg --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk /home/yang/unixnu-work/UniXNU/out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-pmgr/boot.img
ls -l /mnt/d/gittest/unixnu-work/out/boot-pmgr/
sha256sum /mnt/d/gittest/unixnu-work/out/boot-pmgr/boot.img
echo "== DONE"
