#!/bin/bash
# Milestone "RAM root -> first EL0 process": build the boot image whose payload
# carries userland.img (the N4KROOT container XNU's mockfs mounts as rd=md0 and
# execs as PID 1). Run INSIDE WSL, like the other repro scripts - it expects the
# ~/unixnu-work tree of the bring-up session (built kernel + uefi-socrates).
#
# Kernel: NOT rebuilt. The payload stages the existing out/socrates/kernel/kernel.macho
# (probe bars + panic screen re-applied by the payload step) and the boot image packs
# the FD extracted from prebuilt/boot-pmgrlate-boot.img, so everything outside the
# payload volume is byte-identical to the image that reached "Failed to mount root
# device" on hardware (fd a3741876..., dtb 5c731bfe..., kernel section e5909857...).
set -e
cd /home/yang/unixnu-work/UniXNU
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
UEFI=/home/yang/unixnu-work/uefi-socrates
BOARD=/home/yang/unixnu-work/UniXNU-socrates
MONO=/mnt/d/gittest/mik60proios

# 1. CLI: --userland is not in upstream main; apply the ported fork patch (idempotent).
bash "$MONO/tools/apply-unixnu-userland-patch.sh" /home/yang/unixnu-work/UniXNU

# 2. board: sync board.toml and the userland kit from the published monorepo copy.
cp "$MONO/board/UniXNU-socrates/board.toml" "$BOARD/board.toml"
mkdir -p "$BOARD/userland"
cp "$MONO"/board/UniXNU-socrates/userland/* "$BOARD/userland/"

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

# 5. FD: the uefi-socrates Build tree holds the SERIAL-console variant (the flag is
# back to 0 in the dsc, but the built volume is the serial one). Unpack the screen-
# console FD byte-exact from the device-proven prebuilt instead of rebuilding it.
python3 - <<'EOF'
import struct, zlib, hashlib
d = open("/mnt/d/gittest/mik60proios/prebuilt/boot-pmgrlate-boot.img", "rb").read()
ksize = struct.unpack_from("<I", d, 8)[0]
page = struct.unpack_from("<I", d, 36)[0]
kernel = d[page:page + ksize]
data = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(kernel)
fd = data[192:192 + 3145728]
digest = hashlib.sha256(fd).hexdigest()
assert digest == "a3741876d887326bd0cd5958abcc1cc9fda8d5299e7adf8a40bda8dea01e498d", digest
open("/tmp/fd-proven.fd", "wb").write(fd)
print("fd unpacked from the proven prebuilt:", digest)
EOF

# 6. boot image: same kernel section (shim+FD gzip, e5909857...), same DTB table,
#    new RAM-root payload volume.
mkdir -p /mnt/d/gittest/unixnu-work/out/boot-userland
python3 unixnu bootimg --uefi $UEFI -D "$BOARD" \
  --fd /tmp/fd-proven.fd \
  --dtb /mnt/d/gittest/unixnu-work/out/socrates-all-dtbs.dtb \
  --ramdisk out/socrates/payload/payload.img \
  -o /mnt/d/gittest/unixnu-work/out/boot-userland/boot.img

# 7. deliver as the milestone prebuilt.
cp /mnt/d/gittest/unixnu-work/out/boot-userland/boot.img  "$MONO/prebuilt/boot-userland-boot.img"
cp /mnt/d/gittest/unixnu-work/out/boot-userland/boot.json "$MONO/prebuilt/boot-userland-boot.json"
sha256sum "$MONO/prebuilt/boot-userland-boot.img"
echo "== DONE: prebuilt/boot-userland-boot.img (fastboot boot, after one full Android boot)"
