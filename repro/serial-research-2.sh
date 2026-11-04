#!/bin/bash
# 1) Real serial implementations elsewhere in the tree (what do other SM8550
#    Mu-Silicium boards use?)
# 2) UART children inside the qup wrappers of the stock DTB.
echo "=== real SerialPortLib implementations in the tree:"
find /home/yang/unixnu-work/uefi-socrates -iname "*.inf" | xargs grep -l "SerialPortLib" 2>/dev/null | grep -i serial | head
echo
echo "=== QcomPkg serial-ish sources:"
find /home/yang/unixnu-work/uefi-socrates/Silicon/Qualcomm -iname "*uart*" -o -iname "*serial*" | grep -v Build | head -15
echo
echo "=== what serial lib does qrd8550 (SM8550 reference board) use:"
grep -rn "SerialPortLib" /home/yang/unixnu-work/uefi-socrates/Platforms/Qualcomm/qrd8550Pkg/*.dsc 2>/dev/null | head -5
grep -rln "SerialPortInitialize\|GENI" /home/yang/unixnu-work/uefi-socrates/Platforms/Qualcomm/qrd8550Pkg/ 2>/dev/null | head -5
echo
F=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb
echo "=== children inside qup wrappers (stock DTB):"
for q in "qcom,qupv3_1_geni_se@ac0000" "qcom,qupv3_2_geni_se@8c0000" "qcom,qupv3_i2c_geni_se@9c0000"; do
  echo "-- /soc/$q:"
  for c in $(fdtget -l "$F" "/soc/$q" 2>/dev/null); do
    case "$c" in *uart*) echo "   UART: $c  reg=$(fdtget -t x "$F" "/soc/$q/$c" reg 2>/dev/null | tr '\n' ' ') status=$(fdtget "$F" "/soc/$q/$c" status 2>/dev/null)";; esac
  done
done
echo
echo "=== also check qup_uart nodes anywhere (case-insensitive full node list):"
fdtget -l -R 2>/dev/null || true
python3 - <<'EOF'
import subprocess, struct
data = open('/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb','rb').read()
# brute scan for 'uart@' in the strings block
import re
for m in re.finditer(rb'uart@[0-9a-f]+', data):
    print('  found node name:', m.group(0).decode())
EOF
