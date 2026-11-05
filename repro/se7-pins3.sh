#!/bin/bash
# Dump every property of the SE7 UART pinmux nodes (the phandle-resolve earlier
# showed the paths; the pins property read came back empty - use -R recursion
# from the pinctrl node instead).
F=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb
P=/soc/pinctrl@f000000/qupv3_se7_2uart_pins
echo "=== pinmux group props:"
fdtget -p "$F" "$P" 2>/dev/null
for n in qupv3_se7_2uart_tx_active qupv3_se7_2uart_rx_active; do
  echo "=== $n all props:"
  fdtget -p "$F" "$P/$n" 2>/dev/null
  for pr in pins function bias-pull-up bias-disable drive-strength input-enable power-source; do
    v=$(fdtget "$F" "$P/$n" "$pr" 2>/dev/null)
    [ -n "$v" ] && echo "  $pr: $v"
  done
done
echo
echo "=== dump raw FDT region of the tx_active node (find 'pins' in the struct block):"
python3 - <<'EOF'
import struct, re
data = open('/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs/dtb0_off1d47000.dtb','rb').read()
# find the string 'qupv3_se7_2uart_tx_active' in the strings block, then locate
# the BEGIN_NODE that references it and dump the following 200 bytes as props
magic, totalsize, off_struct, off_strings = struct.unpack_from('>4I', data, 0)
sidx = data.find(b'qupv3_se7_2uart_tx_active\x00', off_strings)
print(f'strings offset for tx_active name: {sidx:#x}')
# scan the struct block for FDT_PROP with a nameoff pointing into that string
off = off_struct
while off < len(data) - 4:
    tag = struct.unpack_from('>I', data, off)[0]
    if tag == 0x3:  # FDT_PROP
        size, nameoff = struct.unpack_from('>2I', data, off + 4)
        if off_strings + nameoff == sidx:
            print(f'PROP at {off:#x}: size={size}, nameoff={nameoff}, value={data[off+12:off+12+min(size,32)].hex()}')
    off += 4
EOF
