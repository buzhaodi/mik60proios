#!/bin/bash
# Symbols immediately around the faulting offset 0x2FBC and the module entry path.
M=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/AARCH64/QcomPkg/Drivers/IortDtDxe/IortDtDxe/DEBUG/IortDtDxe.map
echo "=== map lines 0x2xxx-0x3xxx (faulting area):"
awk '/^00002|^00003/' "$M" | grep -v '\.obj' | head -40
echo
echo "=== IortDtDxe.c source:"
cat /home/yang/unixnu-work/uefi-socrates/Silicon/Qualcomm/QcomPkg/Drivers/IortDtDxe/IortDtDxe.c
