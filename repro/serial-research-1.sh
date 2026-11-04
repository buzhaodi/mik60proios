#!/bin/bash
# 1) Read the QcomPkg reference serial driver.
# 2) Find socrates' debug UART in the stock DTB (chosen/stdout-path, uart nodes).
echo "=== reference SerialPort.c (QcomPkg/PlatformPeiLib):"
cat /home/yang/unixnu-work/uefi-socrates/Silicon/Qualcomm/QcomPkg/Library/PlatformPeiLib/SerialPort.c
echo
echo "=== available SerialPortLib classes in the tree:"
find /home/yang/unixnu-work/uefi-socrates/Silicon/Qualcomm -iname "*SerialPort*" | head -10
echo
echo "=== socrates stock DTB UART nodes:"
for f in /mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb; do
  echo "-- /chosen:"
  fdtget -l "$f" /chosen 2>/dev/null | head
  fdtget "$f" /chosen stdout-path 2>/dev/null && echo "(stdout-path above)"
  echo "-- uart nodes under /soc:"
  for u in $(fdtget -l "$f" /soc 2>/dev/null | grep -i "uart\|geni\|qup"); do
    echo -n "  /soc/$u: compat="
    fdtget "$f" "/soc/$u" compatible 2>/dev/null | tr '\n' ' '
    echo -n " reg="
    fdtget -t x "$f" "/soc/$u" reg 2>/dev/null | tr '\n' ' '
    echo
  done
  echo "-- qup parent nodes:"
  for q in $(fdtget -l "$f" /soc 2>/dev/null | grep -i "qup"); do
    echo -n "  /soc/$q: reg="
    fdtget -t x "$f" "/soc/$q" reg 2>/dev/null | tr '\n' ' '
    echo
  done
done
