#!/bin/bash
# macOS port of inject-nodes.sh (the original targets the WSL2 workspace: /mnt/d
# paths and GNU `stat -c%s`). Same nodes, same stock order, same round-trip
# check; iterates every dtb*.dtb in the directory instead of the eight WSL
# filenames, so it accepts both the WSL names (dtb0_off...) and the
# fetch-vendor-dtbs-from-phone.sh names (dtb_00_off0x...).
# Requires Homebrew dtc (fdtput/fdtget).
#
# Usage: bash inject-nodes-mac.sh [DTB_DIR] [OUT_DTB]
#   DTB_DIR  default ~/unixnu-work/firmware/vendor_dtbs
#   OUT_DTB  default ~/unixnu-work/out/socrates-all-dtbs.dtb
set -e
D=${1:-$HOME/unixnu-work/firmware/vendor_dtbs}
OUT=${2:-$HOME/unixnu-work/out/socrates-all-dtbs.dtb}
command -v fdtput >/dev/null || { echo "fdtput missing: brew install dtc" >&2; exit 1; }
command -v fdtget >/dev/null || { echo "fdtget missing: brew install dtc" >&2; exit 1; }
blocks=$(ls "$D"/dtb*.dtb 2>/dev/null | sort)
[ "$(printf '%s\n' "$blocks" | grep -c .)" = 8 ] || { echo "expected 8 vendor DTB blocks in $D" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
TMP=/tmp/one.dtb
trap 'rm -f "$TMP"' EXIT

filesize() { stat -f%z "$1"; }   # BSD stat; the GNU original uses stat -c%s

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

for f in $blocks; do
  cp "$f" "$TMP"
  msm=$(fdtget -t x "$TMP" / qcom,msm-id 2>/dev/null | awk '{print $1}')
  inject "$TMP" splash_region@b8000000 b8000000 2b00000
  inject "$TMP" unixnu-tz-guard@82800000 82800000 8000000
  inject "$TMP" unixnu-dsm-gap@d8000000 d8000000 100000
  inject "$TMP" unixnu-tzapps@d8800000 d8800000 7400000
  inject "$TMP" unixnu-postheap@e7cc0000 e7cc0000 7b40000
  inject "$TMP" unixnu-demura@a2a80000 a2a80000 2b00000
  cat "$TMP" >> "$OUT"
  echo "injected+appended $(basename "$f") ($(filesize "$TMP") bytes) msm-id ${msm:-none}"
done
echo "== total: $(filesize "$OUT") bytes =="
echo "== verify guards in last block:"
for n in splash_region@b8000000 unixnu-tz-guard@82800000 unixnu-dsm-gap@d8000000 \
         unixnu-tzapps@d8800000 unixnu-postheap@e7cc0000 unixnu-demura@a2a80000; do
  echo -n "  /$n reg: "
  fdtget -t x "$TMP" "/reserved-memory/$n" reg | tr '\n' ' '
  echo
done
