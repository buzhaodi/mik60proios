#!/bin/bash
# Inject the splash_region node (the stock ABL powers the panel off without it)
# and the XPU-guard reserved-memory nodes (SocratesBootMemoryDxe adds DRAM holes
# the device tree does not reserve as system memory; the protected ones crash
# DXE with a synchronous external abort - first hardware evidence 0xD8000000)
# into every vendor DTB block, then concatenate in stock order: the ABL picks
# its SoC block itself, exactly as the stock vendor_boot does.
#
# Guards (stock uefiplat.cfg [MemoryMap] cross-checked):
#   0x82800000+0x8000000  tz_stat..mpss: stock RSRV1 (TZ) + two cfg gaps
#   0xD8000000+0x100000   mpss_dsm..xbl_sc: the proven crash hole
#   0xD8800000+0x7400000  qtee..hwfence: stock TZApps Reserved (AddDynamicMem)
#   0xE7CC0000+0x7B40000  stock DXE heap end..llcc_lpi: stock never uses it
#   0xA2A80000+0x2B00000  stock Display Demura (MEM_RES)
set -e
D=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs
OUT=/mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb
: > "$OUT"

inject() { # $1=file $2=label(base) $3=base $4=size
  local f=$1 label=$2 base=$3 size=$4
  local path="/reserved-memory/$label"
  fdtput -c "$f" "$path" 2>/dev/null || true
  fdtput -t x "$f" "$path" reg 0x0 "$base" 0x0 "$size"
  local got want
  got=$(fdtget -t x "$f" "$path" reg | tr '\n' ' ' | sed 's/ $//')
  want="0 $base 0 $size"
  [ "$got" = "$want" ] || { echo "round-trip FAILED: $path got '$got' want '$want'"; exit 1; }
}

for f in dtb0_off1d47000.dtb dtb1_off1db84da.dtb dtb2_off1e256b3.dtb dtb3_off1ea2137.dtb \
         dtb4_off1f233c5.dtb dtb5_off1f93988.dtb dtb6_off1fffc4a.dtb dtb7_off207b7b7.dtb; do
  cp "$D/$f" /tmp/one.dtb
  inject /tmp/one.dtb splash_region@b8000000 b8000000 2b00000
  inject /tmp/one.dtb unixnu-tz-guard@82800000 82800000 8000000
  inject /tmp/one.dtb unixnu-dsm-gap@d8000000 d8000000 100000
  inject /tmp/one.dtb unixnu-tzapps@d8800000 d8800000 7400000
  inject /tmp/one.dtb unixnu-postheap@e7cc0000 e7cc0000 7b40000
  inject /tmp/one.dtb unixnu-demura@a2a80000 a2a80000 2b00000
  cat /tmp/one.dtb >> "$OUT"
  echo "injected+appended $f ($(stat -c%s /tmp/one.dtb) bytes)"
done
echo "== total: $(stat -c%s "$OUT") bytes =="
echo "== verify guards in first block:"
for n in splash_region@b8000000 unixnu-tz-guard@82800000 unixnu-dsm-gap@d8000000 \
         unixnu-tzapps@d8800000 unixnu-postheap@e7cc0000 unixnu-demura@a2a80000; do
  echo -n "  /$n reg: "
  fdtget -t x /tmp/one.dtb "/reserved-memory/$n" reg | tr '\n' ' '
  echo
done
