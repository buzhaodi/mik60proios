#!/bin/bash
# Give a UniXNU DarwinBoot submodule checkout the three socrates bring-up changes
# it needs. All are hardware-validated; upstream does not carry them (yet - the
# intent is to upstream the window fix and the text-console handoff; the stage
# bands are a bring-up tool and may stay local):
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
#  3. BootVideo.h  hand the kernel boot_args Video.v_display = 0, so
#               PE_create_console picks kPETextMode instead of kPEGraphicsMode.
#               Graphics mode is the stock-iPhone "logo + spinner, no printf"
#               path: with it, not one character of console text ever paints
#               (first-flash evidence 2026-11-06 - bands and gear, no text).
#               This board has no debug UART, so the -v console is the only
#               kernel diagnostic channel.
#
# History: a TZ_SECURE_WDOG_DISABLE SMC (2026-11-05) lived here for one day.
# It killed the boot on dirty TZ state - after the deliberate panic cycles of
# the fork-diagnostics rounds, every boot reset with the hand-off page ending
# exactly at the statement before the SMC, and full Android boots (the ABL/PMIC
# pollution cure) did not help. Removed 2026-11-06; see DarwinBoot.c where it
# used to be. Do not put an SMC on this path without a fallback plan.
#
# Idempotent: a second run on an already patched checkout is a no-op.
# Usage: bash apply-darwinboot-socrates-patch.sh /path/to/UniXNU/drivers/DarwinBoot
set -e
# Resolve this script's directory before any cd: a relative $0 must not break
# once we have cd'd into the target checkout.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
R="${1:?usage: apply-darwinboot-socrates-patch.sh /path/to/UniXNU/drivers/DarwinBoot}"
cd "$R"
test -f DarwinBootPkg/Driver/DarwinBoot.c || { echo "$R is not a DarwinBoot checkout" >&2; exit 1; }

PATCH="$SELF_DIR/darwinboot-socrates-diag.patch"
test -f "$PATCH" || { echo "patch not found: $PATCH" >&2; exit 1; }

# Written against the submodule revision the feeds fetched on 2026-11-03.
BASE="3c75734014cdab0acd9541e88057b7606ee7ae08"
if [ "$(git rev-parse HEAD 2>/dev/null)" != "$BASE" ]; then
    echo "note: checkout is not $BASE (the patch's base); applying anyway"
fi

# One marker per change above, for both the already-patched detection and the
# final verification, so a partial state fails by naming what is missing.
marker () {  # marker <file> <pattern> <label>
    grep -q "$2" "DarwinBootPkg/Driver/$1" || { echo "missing: $3 ($1)" >&2; MISSING=1; return; }
    echo "present: $3"
}

if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
    echo "applied: $PATCH"
fi

MISSING=0
marker Entry.S        "band 2 yellow"            "stage bands"
marker DarwinBoot.c   "WINDOW_PREFERRED_BASE"    "fixed 256 MiB window"
marker BootVideo.h    "Video\[1\] = 0"           "text-mode handoff (v_display=0)"
if [ "$MISSING" -ne 0 ]; then
    echo "the DarwinBoot checkout is only partially patched (or drifted from the patch base)" >&2
    exit 1
fi
echo "verified: all three socrates DarwinBoot changes are in place"
