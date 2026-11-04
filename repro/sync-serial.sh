#!/bin/bash
# Sync the serial port files to the WSL build tree and compile a serial-console
# firmware variant to verify the driver compiles.
set -e
B=/home/yang/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg
M=/mnt/d/gittest/mik60proios/firmware/uefi-socrates/Platforms/Xiaomi/socratesPkg
mkdir -p "$B/Library"
rm -rf "$B/Library/SerialPortLib"
cp -r "$M/Library/SerialPortLib" "$B/Library/"
cp "$M/socrates.dec" "$B/socrates.dec"
cp "$M/socrates.dsc" "$B/socrates.dsc"
echo "synced"

cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
# compile the SERIAL variant via the build driver's -D defines
python3 - <<'EOF'
import re
p = '/home/yang/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/socrates.dsc'
s = open(p).read()
s = s.replace('SOCRATES_SERIAL_CONSOLE         = 0', 'SOCRATES_SERIAL_CONSOLE         = 1')
open(p, 'w').write(s)
print('serial console ON for this build')
EOF
python3 unixnu build firmware --uefi /home/yang/unixnu-work/uefi-socrates -D ../UniXNU-socrates 2>&1 | tail -3
FD=/home/yang/unixnu-work/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd
echo "FD: $(stat -c '%s bytes, %y' "$FD")"
# restore the flag to 0 so later builds stay screen-console
python3 - <<'EOF'
p = '/home/yang/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/socrates.dsc'
s = open(p).read()
s = s.replace('SOCRATES_SERIAL_CONSOLE         = 1', 'SOCRATES_SERIAL_CONSOLE         = 0')
open(p, 'w').write(s)
print('serial console flag restored to 0')
EOF
