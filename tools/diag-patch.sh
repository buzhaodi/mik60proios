#!/bin/bash
# Diagnose which patch fails and why.
cd ~/unixnu-work/UniXNU/out/socrates/tree/patches/xnu
XNU=~/unixnu-work/UniXNU/out/socrates/tree/.cache/xnu-work
for p in *.patch ../kits/NativePrelink/patches/*.patch; do
  name=$(basename "$p")
  if git -C "$XNU" apply --check "$p" >/dev/null 2>&1; then
    echo "OK    $name"
  else
    echo "FAILS $name"
  fi
done
echo "== xnu commit =="
git -C "$XNU" log --oneline -1 2>/dev/null
echo "== kern_exec.c around line 183 =="
sed -n '170,200p' "$XNU/bsd/kern/kern_exec.c"
