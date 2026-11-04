#!/bin/bash
# What did the kernel step leave next to kernel.macho, and does the audit's
# .cache/firmware reference path already exist in the tree?
K=/home/yang/unixnu-work/UniXNU/out/socrates/kernel
T=/home/yang/unixnu-work/UniXNU/out/socrates/tree
echo "=== kernel dir:"
ls -la "$K" | head -12
echo
echo "=== .cache/firmware in tree:"
ls -la "$T/.cache/firmware/kernelcache.macho/" 2>/dev/null || echo "  (missing)"
echo
echo "=== xnu-prelink dir in tree:"
ls "$T/build/xnu-prelink/" 2>/dev/null || echo "  (missing)"
echo
echo "=== plan json candidates:"
for f in "$K"/kernel.json "$K"/kernel.macho.json; do
  [ -f "$f" ] && echo "  FOUND: $f ($(stat -c%s "$f") bytes)"
done
python3 - <<'EOF'
import json
from pathlib import Path
for name in ('kernel.json', 'kernel.macho.json'):
    p = Path('/home/yang/unixnu-work/UniXNU/out/socrates/kernel') / name
    if p.is_file():
        plan = json.loads(p.read_text())
        print(name, 'keys:', sorted(plan.keys())[:10])
        mods = [e.get('module') for e in plan.get('extents', [])]
        print('  AMFI in extents:', any('AppleMobileFileIntegrity' in (m or '') for m in mods))
        print('  ApplePMGR in extents:', any('ApplePMGR' == m or 'driver.ApplePMGR' in (m or '') for m in mods))
        print('  original_executable_sha256:', 'ApplePMGR' in str(plan.get('original_executable_sha256', {})))
EOF
