#!/bin/bash
# Symbolize the IortDxe crash offsets (0x2FBC faulting PC, 0x18A4 and 0x1120
# from the backtrace) against the built module.
B=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64
TC=/home/yang/unixnu-work/UniXNU/out/socrates/toolchain
echo "=== IortDxe build artifacts:"
find "$B" -iname "*IortDxe*" | head -20
echo
D=$(find "$B" -type d -iname "IortDxe*" | head -1)
echo "=== dir: $D"
ls -la "$D" 2>/dev/null
ls -la "$D/DEBUG" 2>/dev/null
echo "=== source:"
find /home/yang/unixnu-work/uefi-socrates -iname "IortDxe*" -not -path "*/Build/*" | head -10
