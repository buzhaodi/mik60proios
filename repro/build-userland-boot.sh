#!/bin/bash
# Milestone "RAM root -> first EL0 process": build the boot image whose payload
# carries userland.img (the N4KROOT container XNU's mockfs mounts as rd=md0 and
# execs as PID 1). Run INSIDE WSL, like the other repro scripts - it expects the
# ~/unixnu-work tree of the bring-up session (fetched feeds; the kernel step must
# have produced out/socrates/kernel/kernel.macho once).
#
# Kernel: NOT rebuilt here. The payload stages the existing out/socrates/kernel/kernel.macho
# (probe bars + panic screen re-applied by the payload step). The firmware is built
# fresh with the two hardware-validated DarwinBoot changes applied below.
# The image is not committed to this repository - flash it from the build output.
set -e
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates
BOARD=/home/yang/unixnu-work/UniXNU-socrates
MONO=/mnt/d/gittest/mik60proios

# 0. CLI checkout: on a fresh machine ~/unixnu-work/UniXNU may not exist yet -
#    the monorepo ships the build driver in-tree (vendor/UniXNU/, already carrying
#    the --userland CLI patch), so bootstrap the work copy from there.
U=/home/yang/unixnu-work/UniXNU
if [ ! -d "$U" ]; then
  mkdir -p /home/yang/unixnu-work
  cp -R "$MONO/vendor/UniXNU" "$U"
  find "$U" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
  git -C "$U" init -q && git -C "$U" add -A \
    && git -C "$U" -c user.email=repro@test -c user.name=repro commit -qm "snapshot from mik60proios vendor/UniXNU"
fi

# 1. CLI: --userland is not in upstream main; apply the ported fork patch (idempotent).
bash "$MONO/tools/apply-unixnu-userland-patch.sh" /home/yang/unixnu-work/UniXNU

# 1b. Loader: the fixed 256 MiB window (0x880000000) and the handoff stage bands,
#     both hardware-validated 2026-11-05 (idempotent).
bash "$MONO/tools/apply-darwinboot-socrates-patch.sh" /home/yang/unixnu-work/UniXNU/drivers/DarwinBoot

# 2. board: sync board.toml, the userland kit, and the exec-trace patch set
#    (package/patches + the three scripts the kernel/payload steps run) from
#    the published monorepo copy. Without the script sync a WSL board tree
#    predating 2026-11-05 builds a kernel WITHOUT the g_exec_trace breadcrumb,
#    and the payload step then fails to resolve _g_exec_trace for the panic
#    screen (which is optional, but then the panic block answers nothing).
#    NOTE: the kernel is NOT rebuilt by this script - run the unixnu kernel
#    step (two passes) once before it so kernel.macho carries the trace.
cp "$MONO/board/UniXNU-socrates/board.toml" "$BOARD/board.toml"
mkdir -p "$BOARD/userland" "$BOARD/package/patches"
cp "$MONO"/board/UniXNU-socrates/userland/* "$BOARD/userland/"
cp "$MONO"/board/UniXNU-socrates/package/patches/*.patch "$BOARD/package/patches/"
cp "$MONO"/board/UniXNU-socrates/scripts/build-xnu-4k-baseline.sh "$BOARD/scripts/"
cp "$MONO"/board/UniXNU-socrates/scripts/patch-xnu-entry-probe.py "$BOARD/scripts/"
cp "$MONO"/board/UniXNU-socrates/scripts/xnu-panic-screen.c "$BOARD/scripts/"

# 3. userland: the signer self-test, the build, then the CI-mirror verification.
cd "$BOARD"
python3 userland/test-adhoc.py
bash userland/build.sh userland-build
python3 "$MONO/tools/verify-userland-artifacts.py" userland-build --test-source userland/motd.txt

# 4. payload: the RAM-root volume (userland.img + owner trust cache + rd=md0 entries).
cd /home/yang/unixnu-work/UniXNU
python3 unixnu build payload --uefi $UEFI -D "$BOARD" \
  --kernel out/socrates/kernel/kernel.macho \
  --userland "$BOARD/userland-build/userland.img" \
  --owner-trust-cache "$BOARD/userland-build/kernel.macho.trustcache" \
  --unique-chip-id 0000000000000001

# 5. FD: build it fresh. The dsc serial flag is 0, so this is the screen-console
#    build, and it carries the two hardware-validated DarwinBoot changes
#    (fixed window at 0x880000000 + the handoff stage bands) applied in step 5b.
python3 unixnu build firmware --uefi $UEFI -D "$BOARD"

# 6. boot image: BootShim + FD + DTB table + the RAM-root payload volume.
#    The image is NOT committed to this repository (see README "prebuilt images"):
#    flash it from the build output.
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-userland
python3 unixnu bootimg --uefi $UEFI -D "$BOARD" \
  --fd $UEFI/Build/socratesPkg/DEBUG_CLANGPDB/FV/SILICIUM_UEFI.fd \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-userland/boot.img

sha256sum /mnt/d/gittest/unixnu-work/out/boot-userland/boot.img
echo "== DONE: out/boot-userland/boot.img (fastboot boot, after one full Android boot)"
