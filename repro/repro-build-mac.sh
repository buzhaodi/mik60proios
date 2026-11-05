#!/bin/bash
# REPRODUCTION TEST on native macOS (arm64): build the entire chain from the
# PUBLISHED repo content — the macOS counterpart of repro/repro-build.sh.
#
# Differences from the WSL2 script (each one is a macOS port, not a behavior change):
#   - paths: no /mnt/d; the workspace is ~/unixnu-work (README layout)
#   - PATH: /opt/homebrew/bin first — this machine's `ninja` is a depot_tools
#     wrapper that cannot run, and the kernel step needs Homebrew LLVM/LLD
#     (Apple clang has no llvm-lib/lld-link for the edk2 CLANGPDB tool chain)
#   - network: GitHub needs the local proxy (127.0.0.1:10808); Apple's IPSW CDN
#     stays direct (no_proxy)
#   - the bridge symbol check: macOS `strings` only scans loadable segments of
#     a Mach-O and misses the symbol table — GNU strings scans the whole file.
#     llvm-nm is the authoritative check on both platforms.
#   - tools/inject-nodes-mac.sh instead of tools/inject-nodes.sh (BSD stat,
#     no /mnt/d, globs instead of the eight WSL filenames)
# Prerequisites: Xcode (iphoneos SDK), Homebrew llvm lld lzfse dtc ninja mtools,
# and the 8 vendor DTB blocks (tools/fetch-vendor-dtbs-from-phone.sh, or the
# official ROM tgz) already in ~/unixnu-work/firmware/vendor_dtbs.
set -e
R=$HOME/unixnu-work
SRC=$HOME/gittest/mik60proios
U=$R/UniXNU
export PATH=/opt/homebrew/bin:$PATH
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
export no_proxy="*.cdn-apple.com,updates.cdn-apple.com"

echo "== 1. fresh copies from the published repo (the UniXNU build driver ships in vendor/)"
rm -rf "$R/UniXNU.new" "$R/UniXNU-socrates.new" "$R/uefi-socrates.new"
cp -R "$SRC/vendor/UniXNU" "$R/UniXNU.new"
find "$R/UniXNU.new" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
cp -R "$SRC/board/UniXNU-socrates" "$R/UniXNU-socrates.new"
cp -R "$SRC/firmware/uefi-socrates" "$R/uefi-socrates.new"
# the unixnu driver needs the repos to BE git repos (it runs submodule updates
# on the device and firmware checkouts); a copy out of the monorepo carries
# no .git. The vendored UniXNU already carries the --userland CLI patch
# (scripts/unixnu/{cli,payload}.py), so the idempotent applier below is a no-op;
# it stays in the flow so a vendor drift fails loudly instead of silently.
for repo in UniXNU UniXNU-socrates uefi-socrates; do
  git -C "$R/$repo.new" init -q
  git -C "$R/$repo.new" add -A
  git -C "$R/$repo.new" -c user.email=repro@test -c user.name=repro commit -qm "snapshot from mik60proios"
done
bash "$SRC/tools/apply-unixnu-userland-patch.sh" "$R/UniXNU.new"
bash "$SRC/tools/restore-uefi-submodules.sh" "$R/uefi-socrates.new"
[ -d "$R/UniXNU" ] && rm -rf "$R/UniXNU.old" && mv "$R/UniXNU" "$R/UniXNU.old"
[ -d "$R/UniXNU-socrates" ] && rm -rf "$R/UniXNU-socrates.old" && mv "$R/UniXNU-socrates" "$R/UniXNU-socrates.old"
[ -d "$R/uefi-socrates" ] && rm -rf "$R/uefi-socrates.old" && mv "$R/uefi-socrates" "$R/uefi-socrates.old"
mv "$R/UniXNU.new" "$R/UniXNU"
mv "$R/UniXNU-socrates.new" "$R/UniXNU-socrates"
mv "$R/uefi-socrates.new" "$R/uefi-socrates"
echo "   driver:      $(git -C "$R/UniXNU" log --oneline -1)"
echo "   board repo:  $(git -C "$R/UniXNU-socrates" log --oneline -1)"
echo "   firmware:    $(git -C "$R/uefi-socrates" log --oneline -1)"

echo "== 2. defconfig from the published repo"
cd "$U"
python3 unixnu defconfig socrates_defconfig -D "$R/UniXNU-socrates"
grep SHENG_PMGR out/socrates/.config

echo "== 3. fetch (sha-pinned feeds; IPSW members are range-fetched)"
python3 unixnu fetch --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"
python3 unixnu ipsw fetch --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"

echo "== 4. tree"
python3 unixnu tree --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates"

echo "== 5. kernel (full XNU compile, TWO passes: pass 1 materializes the PMGR bridge reference, pass 2 links the bridge in)"
python3 unixnu build kernel --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" -j 8 || true
python3 unixnu build kernel --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" -j 8
echo "   kernel: $(shasum -a 256 out/socrates/kernel/kernel.macho | cut -c1-16)"
BRIDGE=$(/opt/homebrew/opt/llvm/bin/llvm-nm out/socrates/kernel/kernel.macho | grep -c sheng)
[ "$BRIDGE" -gt 0 ] || { echo "!! NO sheng_pmgr SYMBOLS - BRIDGE MISSING"; exit 1; }
echo "   bridge symbols: $BRIDGE"

echo "== 6. payload"
python3 unixnu build payload --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" --unique-chip-id 0000000000000001

echo "== 7. firmware"
python3 unixnu build firmware --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" -j 6
FD="$R/uefi-socrates/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd"
echo "   FD: $(stat -f%z "$FD") bytes (expect 3145728)"

echo "== 8. DTB guards (vendor DTBs from the phone: tools/fetch-vendor-dtbs-from-phone.sh)"
bash "$SRC/tools/inject-nodes-mac.sh" | tail -3

echo "== 9. bootimg"
python3 unixnu bootimg --uefi "$R/uefi-socrates" -D "$R/UniXNU-socrates" \
  --dtb "$R/out/socrates-all-dtbs.dtb" \
  --ramdisk "$U/out/socrates/payload/payload.img" \
  -o "$SRC/prebuilt-test/boot-repro-mac.img"
shasum -a 256 "$SRC/prebuilt-test/boot-repro-mac.img"
echo "== REPRO DONE (native macOS)"
