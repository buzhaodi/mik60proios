#!/bin/bash
# Where do the two ADTs differ? (inputs were identical - the difference is a lead)
G=/tmp/kernel-compare/boot-pmgr.adt
B=/tmp/kernel-compare/boot-abtest.adt
echo "=== byte-level diff summary:"
cmp -l "$G" "$B" | wc -l
echo "=== first 60 differing bytes (offset: good bad):"
cmp -l "$G" "$B" | head -60
echo
echo "=== differing ranges:"
python3 - <<'EOF'
g = open('/tmp/kernel-compare/boot-pmgr.adt','rb').read()
b = open('/tmp/kernel-compare/boot-abtest.adt','rb').read()
print(f'sizes: {len(g)} {len(b)}')
runs, start = [], None
for i, (x, y) in enumerate(zip(g, b)):
    if x != y:
        if start is None:
            start = i
    else:
        if start is not None:
            runs.append((start, i))
            start = None
if start is not None:
    runs.append((start, len(g)))
print(f'{len(runs)} differing runs:')
for s, e in runs[:30]:
    print(f'  [{s:#06x}..{e:#06x}) len={e-s}: good={g[s:min(e,s+32)].hex()}')
    print(f'                        bad ={b[s:min(e,s+32)].hex()}')
EOF
