#!/bin/bash
# Sync the memory map and run the firmware build.
set -e
SRC=/mnt/d/gittest/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c
DST="$HOME/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c"
cp "$SRC" "$DST"
echo "synced: $(md5sum "$DST" | cut -d' ' -f1)"
grep -m1 'aop_config' "$DST" | cut -c1-60
export http_proxy=http://127.0.0.1:10808
export https_proxy=http://127.0.0.1:10808
cd "$HOME/unixnu-work/UniXNU"
python3 unixnu build firmware --uefi "$HOME/unixnu-work/uefi-socrates" -D ../UniXNU-socrates 2>&1 | tail -10
