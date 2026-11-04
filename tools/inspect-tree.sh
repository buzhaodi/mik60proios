#!/bin/bash
# Tool invocation conventions of an archive builder that already works on
# Linux, plus the tree layout the PMGR builder will run in.
T=/home/yang/unixnu-work/UniXNU/out/socrates/tree
echo "=== build-mockfs-fixture.py tool calls:"
grep -n "llvm-\|clang\|ar\b\|objcopy\|run(\|toolchain\|CLT" "$T/scripts/build-mockfs-fixture.py" 2>/dev/null | head -15
echo
echo "=== tree scripts has audit/native_prelink?"
ls "$T/scripts/" | grep -i "audit-amfi\|native-prelink" | head
echo
echo "=== kits layout:"
ls "$T/kits/" | head
ls "$T/kits/socrates/ShengPlatformPower.cpp" 2>/dev/null && echo "  ShengPlatformPower.cpp IN TREE"
echo
echo "=== native-prelink candidates present?"
ls "$T/build/native-prelink/" 2>/dev/null | head -5
echo
echo "=== native_prelink module location:"
find "$T/kits" -name "native_prelink.py" | head -2
echo
echo "=== IOPlatformExpert.cpo.json:"
ls "$T/build/xnu/ios-obj/DEVELOPMENT_ARM64_BCM2837/iokit/DEVELOPMENT/IOPlatformExpert.cpo.json" 2>/dev/null && echo OK
echo
echo "=== kernelcache sha256:"
sha256sum /home/yang/unixnu-work/UniXNU/out/ipsw/21H461/kernelcache.decompressed
