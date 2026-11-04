#!/bin/bash
F=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb
P=/soc/pinctrl@f000000/qupv3_se7_2uart_pins
for n in qupv3_se7_2uart_tx_active qupv3_se7_2uart_rx_active; do
  echo "== $n"
  echo -n "  props: "; fdtget -p "$F" "$P/$n"
  for pr in pins function bias-pull-up bias-disable input-enable drive-strength power-source; do
    v=$(fdtget "$F" "$P/$n" "$pr" 2>/dev/null)
    [ -n "$v" ] && echo "  $pr: $v"
  done
done
