#!/bin/bash
# REPRODUCTION TEST: build the entire chain from the PUBLISHED repo content.
# Fresh copies of both device repos from mik60proios, clean device work dir,
# reused only: the upstream CLI checkout (with the local bootimg.py fixes)
# and the sha-pinned ipsw/feeds caches.
set -e
R=/home/yang/repro
SRC=/mnt/d/gittest/mik60proios
U=/home/yang/unixnu-work/UniXNU

echo "== 1. fresh copies from the published repo"
rm -rf "$R"; mkdir -p "$R"
cp -r "$SRC/board/UniXNU-socrates" "$R/UniXNU-socrates"
cp -r "$SRC/firmware/uefi-socrates" "$R/uefi-socrates"
# the unixnu driver needs the device and firmware repos to BE git repos (it
# runs submodule updates); a copy out of the monorepo carries no .git.
for repo in UniXNU-socrates uefi-socrates; do
  git -C "$R/$repo" init -q
  git -C "$R/$repo" add -A
  git -C "$R/$repo" -c user.email=repro@test -c user.name=repro commit -qm "snapshot from mik60proios"
done
echo "   board repo:  $(git -C "$R/UniXNU-socrates" log --oneline -1)"
echo "   firmware:    $(git -C "$R/uefi-socrates" log --oneline -1)"

echo "== 2. clean the device work dir (keep ipsw/feeds caches)"
if [ -d "$U/out/socrates" ] && [ ! -d "$U/out/socrates.bak" ]; then
  mv "$U/out/socrates" "$U/out/socrates.bak"
fi
rm -rf "$U/out/socrates"

cd "$U"
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808

echo "== 3. defconfig from the published repo"
python3 unixnu defconfig socrates_defconfig -D "$R/UniXNU-socrates"
grep SHENG_PMGR out/socrates/.config

echo "== 4. fetch (sha-pinned caches should make this fast)"
python3 unixnu fetch --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"

echo "== 5. tree"
python3 unixnu tree --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"

echo "== 6. kernel (full XNU compile, TWO passes: pass 1 materializes the PMGR bridge reference, pass 2 links the bridge in)"
python3 unixnu build kernel --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" || true
python3 unixnu build kernel --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"
echo "   kernel: $(sha256sum out/socrates/kernel/kernel.macho | cut -c1-16)"
strings out/socrates/kernel/kernel.macho | grep -c sheng_pmgr || echo "!! NO sheng_pmgr SYMBOLS - BRIDGE MISSING"

echo "== 7. payload"
python3 unixnu build payload --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" --unique-chip-id 0000000000000001

echo "== 8. firmware (full openssl rebuild - the long one)"
python3 unixnu build firmware --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"
FD="$R/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd"
echo "   FD: $(stat -c%s "$FD") bytes (expect 3145728)"

echo "== 9. DTB guards from the published tools"
bash "$SRC/tools/inject-nodes.sh" | tail -3

echo "== 10. bootimg"
mkdir -p /mnt/d/gittest/mik60proios/prebuilt-test
python3 unixnu bootimg --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk "$U/out/socrates/payload/payload.img" \
  -o /mnt/d/gittest/mik60proios/prebuilt-test/boot-repro.img
sha256sum /mnt/d/gittest/mik60proios/prebuilt-test/boot-repro.img
echo "== REPRO DONE"
