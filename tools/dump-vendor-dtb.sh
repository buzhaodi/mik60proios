#!/bin/bash
# Dump msm-id/board-id/memory/reserved-memory of every vendor DTB block, so the
# SocratesBootMemoryDxe algorithm can be replayed offline on the tree the ABL
# actually hands to the firmware.
D=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs
for f in "$D"/dtb*.dtb; do
  echo "=== $(basename "$f")"
  echo -n "  msm-id:  "; fdtget -t x "$f" / qcom,msm-id 2>/dev/null
  echo -n "  board-id: "; fdtget -t x "$f" / qcom,board-id 2>/dev/null
  echo -n "  memory nodes: "; fdtget -l "$f" / 2>/dev/null | grep -i "^memory" | tr '\n' ' '; echo
  for m in $(fdtget -l "$f" / 2>/dev/null | grep -i "^memory"); do
    echo -n "    /$m reg: "; fdtget -t x "$f" "/$m" reg 2>/dev/null
  done
  echo "  reserved-memory children:"
  for r in $(fdtget -l "$f" /reserved-memory 2>/dev/null); do
    echo -n "    /$r reg: "; fdtget -t x "$f" "/reserved-memory/$r" reg 2>/dev/null | tr '\n' ' '; echo
  done
done
