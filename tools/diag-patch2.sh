#!/bin/bash
# Replicate the build's patch loop exactly: reverse-check first, then forward.
cd ~/unixnu-work/UniXNU/out/socrates/tree
XNU=.cache/xnu-work

# the late patches the script reverses first
for LATE_PATCH in "$PWD"/patches/xnu/zzz-boot-progress.patch patches/xnu/zzy-staged-system-apps.patch \
    patches/xnu/zzy-native-gpu-addon-mount.patch; do
  if git -C "$XNU" apply --reverse --check "$LATE_PATCH" >/dev/null 2>&1; then
    git -C "$XNU" apply --reverse "$LATE_PATCH"
    echo "reversed: $(basename "$LATE_PATCH")"
  fi
done

for PATCH in "$PWD"/patches/xnu/*.patch "$PWD"/kits/NativePrelink/patches/*.patch; do
  name=$(basename "$PATCH")
  if git -C "$XNU" apply --reverse --check "$PATCH" >/dev/null 2>&1; then
    echo "already: $name"
    continue
  fi
  if git -C "$XNU" apply --check "$PATCH" >/dev/null 2>&1; then
    echo "applied: $name"
    git -C "$XNU" apply "$PATCH"
  else
    echo "BROKEN:  $name  <-- first genuinely failing patch"
    git -C "$XNU" apply --check "$PATCH" 2>&1 | head -5
    break
  fi
done
