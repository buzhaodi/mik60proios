#!/bin/bash
# Extract the stock vendor DTB blocks from a connected Redmi K60 Pro (socrates).
# The 8 blocks are NOT in the published repo (they are Xiaomi firmware; on WSL
# they came from the official ROM tgz, which the repo deliberately does not
# carry). This script takes them straight off the phone instead, so a full
# from-source boot.img needs no 8.4 GB ROM download:
#
#   fastboot mode:  fastboot fetch vendor_boot   (unlocked ABL, no root needed)
#   adb fallback:    adb shell su -c 'dd if=/dev/block/by-name/vendor_boot'
#                   (needs Magisk root; write to /data/local/tmp first)
#
# The vendor_boot image is scanned for FDT blobs with tools/bootimg_extract_dtbs.py
# (scan order = file offset order = the stock DTB table order the ABL expects),
# then every block's qcom,msm-id is printed and checked against the set measured
# in BRINGUP-LOG.md #1 (0x25c/0x258/0x207/0x25b/0x259/0x218).
#
# Usage: bash fetch-vendor-dtbs-from-phone.sh [OUT_DIR]
#   OUT_DIR default ~/unixnu-work/firmware/vendor_dtbs
set -e
D=${1:-$HOME/unixnu-work/firmware/vendor_dtbs}
REPO=$(cd "$(dirname "$0")/.." && pwd)
IMG=$(mktemp -d)/vendor_boot.img
mkdir -p "$D"

if fastboot devices 2>/dev/null | grep -qw fastboot; then
  echo "== fastboot device found: fetching vendor_boot (unlocked ABL, no root)"
  fastboot fetch vendor_boot "$IMG"
elif adb get-state 2>/dev/null | grep -qw device; then
  echo "== adb device found (no fastboot): pulling vendor_boot with root"
  adb shell su -c 'dd if=/dev/block/by-name/vendor_boot of=/data/local/tmp/vendor_boot.img'
  adb pull /data/local/tmp/vendor_boot.img "$IMG"
  adb shell su -c 'rm /data/local/tmp/vendor_boot.img'
else
  echo "no device: connect the phone in fastboot mode (adb reboot bootloader)" >&2
  exit 1
fi
ls -l "$IMG"

echo "== extracting FDT blobs into $D"
python3 "$REPO/tools/bootimg_extract_dtbs.py" "$IMG" "$D"

count=$(ls "$D"/dtb*.dtb 2>/dev/null | wc -l | tr -d ' ')
echo "== msm-id check (expected set: 0x25c 0x258 0x207 0x25b 0x259 0x218)"
seen=""
for f in $(ls "$D"/dtb*.dtb | sort); do
  msm=$(fdtget -t x "$f" / qcom,msm-id 2>/dev/null | awk '{print $1}')
  board=$(fdtget -t x "$f" / qcom,board-id 2>/dev/null | awk '{print $1}')
  echo "  $(basename "$f"): msm-id ${msm:-none} board-id ${board:-none}"
  seen="$seen $msm"
done
if [ "$count" != 8 ]; then
  echo "!! expected 8 DTB blocks, got $count" >&2
  exit 1
fi
for want in 25c 258 207 25b 259 218; do
  echo "$seen" | grep -qw "$want" || echo "!! msm-id 0x$want not found (check the msm-id set)" >&2
done
echo "== OK: $count blocks in $D"
