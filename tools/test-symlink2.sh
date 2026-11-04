#!/bin/bash
# Where does the broken-looking firmware symlink actually point?
F=/home/yang/unixnu-work/UniXNU/out/socrates/tree/.cache/firmware/kernelcache.macho/kernelcache.release.ipad7.decompressed
echo "readlink -f: $(readlink -f "$F" 2>&1)"
ls -ld /home/yang/unixnu-work/UniXNU/out/socrates/tree
D=$(dirname "$F")
echo "dirname: $D"
echo "realpath of dir: $(realpath "$D")"
cd "$D" || exit 1
echo "cd ok; 5-up resolution: $(realpath ../../../../../ipsw/21H461/kernelcache.decompressed 2>&1)"
echo "ls 5-up: $(ls ../../../../../ipsw/21H461/kernelcache.decompressed 2>&1 | head -1)"
echo "--- try 4-up too:"
ls ../../../../ipsw/21H461/kernelcache.decompressed 2>&1 | head -1
