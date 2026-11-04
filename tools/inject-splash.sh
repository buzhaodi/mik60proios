#!/bin/bash
# Inject the splash_region node into every vendor DTB and concatenate them all
# in stock order - the ABL picks the SoC-matching block itself, exactly as the
# stock vendor_boot does.
set -e
D=/mnt/d/gittest/unixnu-work/firmware/vendor_dtbs
OUT=/mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb
: > "$OUT"
for f in dtb0_off1d47000.dtb dtb1_off1db84da.dtb dtb2_off1e256b3.dtb dtb3_off1ea2137.dtb \
         dtb4_off1f233c5.dtb dtb5_off1f93988.dtb dtb6_off1fffc4a.dtb dtb7_off207b7b7.dtb; do
  cp "$D/$f" /tmp/one.dtb
  # board.toml bootimg.dtb_node, mirrored: /reserved-memory/splash_region
  fdtput -c /tmp/one.dtb /reserved-memory/splash_region 2>/dev/null || true
  fdtput -t s /tmp/one.dtb /reserved-memory/splash_region label cont_splash_region
  fdtput -t x /tmp/one.dtb /reserved-memory/splash_region reg 0x0 0xb8000000 0x0 0x2b00000
  # verify round-trip
  got=$(fdtget -t s /tmp/one.dtb /reserved-memory/splash_region label)
  [ "$got" = "cont_splash_region" ] || { echo "round-trip failed on $f"; exit 1; }
  cat /tmp/one.dtb >> "$OUT"
  echo "injected+appended $f ($(stat -c%s /tmp/one.dtb) bytes)"
done
echo "== total: $(stat -c%s "$OUT") bytes =="
