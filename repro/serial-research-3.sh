#!/bin/bash
# Which of the two UARTs routes to the Type-C debug connector? Read their
# pinctrl-0 phandles and resolve the pin groups (SBU pins of the Type-C = the
# factory debug cable).
F=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb
for path in "/soc/qcom,qupv3_1_geni_se@ac0000/qcom,qup_uart@a9c000" "/soc/qcom,qupv3_2_geni_se@8c0000/qcom,qup_uart@898000"; do
  echo "=== $path"
  fdtget "$F" "$path" status 2>/dev/null
  echo -n "  pinctrl-0: "; fdtget -t x "$F" "$path" pinctrl-0 2>/dev/null | tr '\n' ' '; echo
  echo -n "  pinctrl-names: "; fdtget "$F" "$path" pinctrl-names 2>/dev/null | tr '\n' ' '; echo
  echo -n "  interrupt regs etc: "; fdtget -t x "$F" "$path" interrupts 2>/dev/null | tr '\n' ' '; echo
  echo "  all props:"
  fdtget -p "$F" "$path" 2>/dev/null | tr '\n' ' '; echo
done
echo
echo "=== tlmm pin groups referenced (resolve the pinctrl phandles to pin numbers):"
python3 - <<'EOF'
import struct, subprocess
# resolve phandle -> /tlmm pinmux node path via fdtget scanning
# cheap approach: dump all /tlmm children names and grep for qup/uart
F='/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb'
out = subprocess.run(['fdtget','-l',F,'/tlmm'], capture_output=True, text=True).stdout
pins = [p for p in out.split() if 'uart' in p.lower() or 'qup' in p.lower()]
print('tlmm uart/qup groups:', pins[:20])
EOF
