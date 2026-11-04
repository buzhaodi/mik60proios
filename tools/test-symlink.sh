#!/bin/bash
# Properly verify the materialized audit references.
F=/home/yang/unixnu-work/UniXNU/out/socrates/tree/.cache/firmware/kernelcache.macho/kernelcache.release.ipad7.decompressed
echo "readlink: $(readlink "$F" 2>&1)"
if [ -f "$F" ]; then echo "RESOLVES OK: $(stat -c%s "$F") bytes"; else echo "BROKEN/MISSING"; fi
python3 - "$F" <<'EOF'
import sys
from pathlib import Path
p = Path(sys.argv[1])
print('exists:', p.exists(), 'is_symlink:', p.is_symlink())
if p.is_symlink():
    print('target resolves:', (p.parent / p.readlink()).resolve().is_file())
EOF
echo "--- candidates:"
ls -la /home/yang/unixnu-work/UniXNU/out/socrates/tree/build/xnu-prelink/ 2>/dev/null
