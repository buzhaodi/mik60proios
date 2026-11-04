#!/bin/bash
# Every LocateMemoryRegionByName call site and the helper implementation.
R=/home/yang/unixnu-work/uefi-socrates
echo "=== call sites:"
grep -rn "LocateMemoryRegionByName" "$R/Silicon" "$R/Platforms/Xiaomi/socratesPkg" --include="*.c" 2>/dev/null | grep -v Build | grep -v "MemoryMapHelperLib.c:"
echo
echo "=== helper implementation:"
cat "$R/Silicon/Silicium/SiliciumPkg/Library/MemoryMapHelperLib/MemoryMapHelperLib.c" 2>/dev/null
echo
echo "=== helper header:"
cat "$R/Silicon/Silicium/SiliciumPkg/Include/Library/MemoryMapHelperLib.h" 2>/dev/null
