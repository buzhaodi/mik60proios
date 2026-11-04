#!/bin/bash
# Reset xnu-work to pristine and run the build's patch loop step by step.
set -u
cd ~/unixnu-work/UniXNU/out/socrates/tree
XNU=.cache/xnu-work
echo "== before reset =="
git -C "$XNU" status --porcelain | head -5
git -C "$XNU" reset --hard d8b8029 >/dev/null 2>&1 || git -C "$XNU" reset --hard origin/HEAD >/dev/null 2>&1
git -C "$XNU" clean -qfd 2>/dev/null
echo "== after reset: $(git -C "$XNU" log --oneline -1) =="

for PATCH in "$PWD"/patches/xnu/*.patch "$PWD"/kits/NativePrelink/patches/*.patch; do
  name=$(basename "$PATCH")
  if git -C "$XNU" apply --check "$PATCH" >/dev/null 2>&1; then
    git -C "$XNU" apply "$PATCH"
    echo "ok      $name"
  else
    echo "BROKEN  $name"
    echo "--- failing hunk context ---"
    git -C "$XNU" apply --check "$PATCH" 2>&1 | head -4
    break
  fi
done
