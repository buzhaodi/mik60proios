#!/bin/bash
# WSL-side setup: copy the uefi checkout to ext4 and init its submodules through the host proxy.
set -e
# mirrored networking: the host proxy is on shared localhost
export http_proxy="http://127.0.0.1:10808"
export https_proxy="http://127.0.0.1:10808"
echo "proxy -> ${http_proxy}"
cd ~/unixnu-work
if [ ! -d uefi-socrates ]; then
  cp -r /mnt/d/gittest/unixnu-work/uefi-socrates .
fi
cd uefi-socrates
git submodule update --init --depth 1 --jobs 4 \
  Binaries Common/Mu Common/Mu_OEM_Sample Mu_Basecore Silicium-ACPI \
  Silicon/Silicium/OpensslPkg/Library/OpensslLib/openssl
echo "== submodule status =="
git submodule status | head -8
