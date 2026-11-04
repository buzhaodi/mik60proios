#!/bin/bash
# Is the PMGR bridge actually in the built kernel?
T=/home/yang/unixnu-work/UniXNU/out/socrates/tree
K=/home/yang/unixnu-work/UniXNU/out/socrates/kernel
echo "=== sheng-pmgr-mode stamp:"
cat "$T/build/xnu/ios-obj/DEVELOPMENT_ARM64_BCM2837/.sheng-pmgr-mode" 2>/dev/null
echo
echo "=== bsd_init.o references:"
strings "$T/build/xnu/ios-obj/DEVELOPMENT_ARM64_BCM2837/bsd/DEVELOPMENT/bsd_init.o" 2>/dev/null | grep -i "sheng_pmgr\|sheng-pmgr" | head -5
echo
echo "=== kernel.macho symbols (nm):"
NM=$(find /home/yang/unixnu-work/UniXNU/out/socrates/toolchain -name "llvm-nm" 2>/dev/null | head -1)
[ -z "$NM" ] && NM=$(command -v llvm-nm || command -v nm)
echo "nm tool: $NM"
"$NM" "$K/kernel.macho" 2>/dev/null | grep -i "sheng_pmgr\|ShengPlatformPower\|ApplePMGRNub" | head -8
echo
echo "=== raw string scan of kernel.macho:"
strings "$K/kernel.macho" 2>/dev/null | grep -i "sheng_pmgr\|sheng-pmgr" | head -5
echo
echo "=== bsd_init.c patched block:"
grep -n "sheng_pmgr_run" "$T/.cache/xnu-work/bsd/kern/bsd_init.c" 2>/dev/null | head -3
grep -n -A3 "XNU_SHENG_PMGR" "$T/.cache/xnu-work/bsd/kern/bsd_init.c" 2>/dev/null | head -12
