#!/bin/bash
# Board DTB (socrates.dtb) reserved-memory + /reserved-memory cells, and the
# reserved-memory fragments of the first dtbo entries (what ABL may merge in).
S=/mnt/d/gittest/unixnu-work/UniXNU-socrates/scripts/data/socrates.dtb
echo "=== socrates.dtb reserved-memory:"
fdtget -l "$S" /reserved-memory 2>/dev/null | while read -r r; do
  echo -n "  /$r reg: "
  fdtget -t x "$S" "/reserved-memory/$r" reg 2>/dev/null | tr '\n' ' '
  echo
done
echo -n "  #address-cells: "; fdtget -t i "$S" /reserved-memory '#address-cells' 2>/dev/null
echo -n "  #size-cells:    "; fdtget -t i "$S" /reserved-memory '#size-cells' 2>/dev/null
echo
echo "=== dtbo reserved-memory mentions (dtbo_all.txt):"
grep -n "reserved-memory" /mnt/d/gittest/unixnu-work/out/dtbo_all.txt | head -10
