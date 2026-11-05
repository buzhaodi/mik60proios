#!/bin/bash
# Give a UniXNU checkout the "build payload --userland" support it needs for the
# socrates RAM-root milestone. Upstream main (c1ecc5b) does not carry the flag -
# the feature lives in the vermeer porter's fork (yyx2025/UniXNU@vermeer-fix),
# whose payload.py is based on an older upstream, so the hunks are ported onto
# our pinned checkout instead of pulling the whole fork branch (which would also
# drag in unrelated vermeer-era changes next to the proven kernel build).
#
# What the patch adds (all verified against the built volume):
#   cli.py     --userland FILE
#   payload.py Payloads/userland.img staging, make-socrates-adt.py --ramdisk,
#               menu entries userland (default; userland_args + rd=md0) and
#               userland-full (kernel_args + rd=md0), size_mib_userland,
#               userland_sha256 in payload.json
#
# Idempotent: a second run on an already patched checkout is a no-op.
# Usage: bash apply-unixnu-userland-patch.sh /path/to/UniXNU
set -e
# Resolve this script's directory before any cd: a relative $0 must not break
# once we have cd'd into the target checkout.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
R="${1:?usage: apply-unixnu-userland-patch.sh /path/to/UniXNU}"
cd "$R"
test -f unixnu && test -d scripts/unixnu || { echo "$R is not a UniXNU checkout" >&2; exit 1; }

PATCH="$SELF_DIR/unixnu-userland-payload.patch"
test -f "$PATCH" || { echo "patch not found: $PATCH" >&2; exit 1; }

if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    echo "applied: $PATCH"
elif grep -q "userland.img" scripts/unixnu/payload.py && grep -q "'--userland'" scripts/unixnu/cli.py; then
    echo "already patched: --userland present in scripts/unixnu/{cli,payload}.py"
else
    echo "the patch does not apply: checkout drifted from the expected base" >&2
    echo "(upstream c1ecc5b + the local bootimg.py fixes)" >&2
    exit 1
fi

python3 -m py_compile scripts/unixnu/cli.py scripts/unixnu/payload.py
python3 unixnu build payload --help 2>/dev/null | grep -q -- "--userland" \
    && echo "verified: 'build payload --userland' is wired"
