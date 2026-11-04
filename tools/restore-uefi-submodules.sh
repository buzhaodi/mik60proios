#!/bin/bash
# Recreate the uefi-socrates submodule gitlinks after a plain file copy.
# Gitlinks are index/tree entries - `cp -r` cannot carry them, so a copied
# checkout fails `git submodule update` with "pathspec did not match".
# Usage: bash restore-uefi-submodules.sh /path/to/uefi-socrates
set -e
R="${1:?usage: restore-uefi-submodules.sh /path/to/uefi-socrates}"
cd "$R"
test -f .gitmodules || { echo "no .gitmodules in $R" >&2; exit 1; }
for entry in \
  "a1501e0c2e642d6ac0d8f52c85af2a67b75a7799 Binaries" \
  "b8d46c71610318e36a661819e1e3c0b8bdda413a Common/Mu" \
  "b70b4b7bb02c43bf9db2172dfb3ed0457e2361d6 Common/Mu_OEM_Sample" \
  "9b12862efbebdd3d9263843e0b056caa2b8193da Mu_Basecore" \
  "2d465ad77c25de908f0ec7bdfcb57f865b61233c Silicium-ACPI" \
  "67b5686b4419b4cb8caa502711c41815f5279751 Silicon/Silicium/OpensslPkg/Library/OpensslLib/openssl"; do
  sha=${entry%% *}; path=${entry#* }
  rmdir --ignore-fail-on-non-empty "$path" 2>/dev/null || rm -rf "$path" 2>/dev/null || true
  git update-index --add --cacheinfo "160000,$sha,$path"
done
git commit -qm "restore submodule gitlinks (plain copy cannot carry them)" || true
echo "submodule gitlinks restored in $R"
