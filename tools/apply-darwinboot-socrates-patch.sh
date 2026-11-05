#!/bin/bash
# Give a UniXNU DarwinBoot submodule checkout the two socrates bring-up changes
# it needs. Both are hardware-validated on 2026-11-05; upstream does not carry
# them (yet - the intent is to upstream the window fix; the stage bands are a
# bring-up tool and may stay local):
#
#  1. Entry.S   DarwinEnter stage bands: below the green handoff bar, yellow is
#               painted before the window's dc civac walk, cyan after it, white
#               right before the branch to the kernel entry. With no serial
#               console, the visible band set names the death stage when a boot
#               resets mid-handoff (evidence: 2026-11-05 rounds, BRINGUP-LOG 8).
#  2. DarwinBoot.c  a fixed 256 MiB window placement at 0x880000000 ("DRAM bank
#               1 low": the one conventional run with no unknown gaps inside)
#               tried before the first-fit scan, plus a "window 0x.. fixed/scan"
#               banner line. Without it the first-fit window rolled across the
#               unknown-owner "DRAM gap 0xc7cc0000" with every pool-layout
#               change and every boot, and a window that reached a protected
#               page died in the dc civac walk (asynchronous external abort).
#
# Idempotent: a second run on an already patched checkout is a no-op.
# Usage: bash apply-darwinboot-socrates-patch.sh /path/to/UniXNU/drivers/DarwinBoot
set -e
R="${1:?usage: apply-darwinboot-socrates-patch.sh /path/to/UniXNU/drivers/DarwinBoot}"
cd "$R"
test -f DarwinBootPkg/Driver/DarwinBoot.c || { echo "$R is not a DarwinBoot checkout" >&2; exit 1; }

PATCH="$(cd "$(dirname "$0")" && pwd)/darwinboot-socrates-diag.patch"
test -f "$PATCH" || { echo "patch not found: $PATCH" >&2; exit 1; }

# Written against the submodule revision the feeds fetched on 2026-11-03.
BASE="3c75734014cdab0acd9541e88057b7606ee7ae08"
if [ "$(git rev-parse HEAD 2>/dev/null)" != "$BASE" ]; then
    echo "note: checkout is not $BASE (the patch's base); applying anyway"
fi

if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    echo "applied: $PATCH"
elif grep -q "WINDOW_PREFERRED_BASE" DarwinBootPkg/Driver/DarwinBoot.c; then
    echo "already patched: fixed window and stage bands present"
else
    echo "the patch does not apply: the checkout drifted from its expected base" >&2
    exit 1
fi

grep -q "WINDOW_PREFERRED_BASE" DarwinBootPkg/Driver/DarwinBoot.c \
    && grep -q "band 2 yellow" DarwinBootPkg/Driver/Entry.S \
    && echo "verified: fixed window + stage bands are in place"
