#!/bin/bash
# Why did the kernelcache materialization in build-sheng-platform-power.py not fire?
T=/home/yang/unixnu-work/UniXNU/out/socrates/tree
src="$T/../../ipsw/21H461/kernelcache.decompressed"
echo "source path: $src"
ls -la "$src" 2>&1 | head -2
if [ -f "$src" ]; then
  echo "sha256: $(sha256sum "$src" | cut -d' ' -f1)"
fi
echo "--- firmware dir now:"
ls -la "$T/.cache/firmware/kernelcache.macho/" 2>&1 | head -3
echo "--- .cache listing:"
ls "$T/.cache/" 2>/dev/null | head
