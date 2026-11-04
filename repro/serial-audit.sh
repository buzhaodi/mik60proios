#!/bin/bash
# How does the built firmware currently satisfy the SerialPortLib class, and
# where would our GENI lib slot in?
D=/home/yang/unixnu-work/uefi-socrates
echo "=== SerialPortLib in KailuaPkg.dsc.inc:"
grep -in "serialport" "$D/Silicon/Qualcomm/KailuaPkg/KailuaPkg.dsc.inc" || echo "  (not present)"
echo "=== DebugLib in KailuaPkg.dsc.inc:"
grep -in "debuglib" "$D/Silicon/Qualcomm/KailuaPkg/KailuaPkg.dsc.inc" | head -4
echo "=== what the BUILD used for SerialPortLib (build report style):"
grep -rn "SerialPortLib" "$D/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64" --include="*.inf" -l 2>/dev/null | head -3
echo "=== FrameBufferSerialPortLib consumers in socrates.dsc:"
grep -in "serial" "$D/Platforms/Xiaomi/socratesPkg/socrates.dsc" | head -5
echo "=== socrates.dec content:"
cat "$D/Platforms/Xiaomi/socratesPkg/socrates.dec" | head -20
