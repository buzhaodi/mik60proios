#!/bin/bash
# Which serial lib does the current build actually link?
B=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64/QcomPkg/Drivers/IortDtDxe/IortDtDxe/OUTPUT
grep -i "serial" "$B/IortDtDxe.inf" | head -4
echo "--- libs dir:"
ls "$B/../DEBUG" 2>/dev/null | grep -i serial | head -4
echo "--- map file libraries:"
grep -o "lib[A-Za-z]*SerialPortLib[A-Za-z]*" /home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64/QcomPkg/Drivers/IortDtDxe/IortDtDxe/DEBUG/IortDtDxe.map 2>/dev/null | sort -u | head -3
grep -o "[A-Za-z0-9_]*SerialPortLib[A-Za-z0-9_]*" /home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64/QcomPkg/Drivers/IortDtDxe/IortDtDxe/DEBUG/IortDtDxe.map 2>/dev/null | sort -u | head -5
