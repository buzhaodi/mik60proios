#!/bin/bash
F=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb
for n in qupv3_se7_2uart_tx_active qupv3_se7_2uart_rx_active qupv3_se7_2uart_sleep; do
  echo "== $n"
  echo -n "  pins: "; fdtget "$F" "/pinctrl@f000000/qupv3_se7_2uart_pins/$n" pins 2>/dev/null
  echo -n "  function: "; fdtget "$F" "/pinctrl@f000000/qupv3_se7_2uart_pins/$n" function 2>/dev/null
  echo -n "  bias: "; fdtget "$F" "/pinctrl@f000000/qupv3_se7_2uart_pins/$n" bias-pull-up 2>/dev/null
done
echo "== uart@a9c000 details:"
for p in compatible clock-names interrupts; do
  echo -n "  $p: "; fdtget "$F" "/soc/qcom,qupv3_1_geni_se@ac0000/qcom,qup_uart@a9c000" "$p" 2>/dev/null
done
