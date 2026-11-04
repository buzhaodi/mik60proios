#!/bin/bash
# Symbolize the IortDtDxe crash offsets against the built module and show its source.
B=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64/QcomPkg/Drivers/IortDtDxe/IortDtDxe/DEBUG
TC=/home/yang/unixnu-work/UniXNU/out/socrates/toolchain
echo "=== source files:"
find /home/yang/unixnu-work/uefi-socrates/Silicon -ipath "*IortDtDxe*" -name "*.c" -o -ipath "*IortDtDxe*" -name "*.inf" | grep -v Build
echo
echo "=== llvm-symbolizer (dll + pdb):"
"$TC/llvm-symbolizer" --obj="$B/IortDtDxe.dll" 0x2FBC 0x18A4 0x1120 0x1050 2>&1 | head -40
echo
echo "=== map file function list (first 40 lines):"
head -40 "$B/IortDtDxe.map"
