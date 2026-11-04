#!/bin/bash
# How does the sheng board satisfy AMFI's PMGR requirement, and what does
# build-sheng-platform-power.py need? (socrates hit "AMFI: No PMGR?" at
# ConfigurationSettings.cpp:235 on the first XNU boot.)
R=/home/yang/unixnu-work
echo '=== "No PMGR" / PMGR mentions in UniXNU:'
grep -rn "No PMGR" "$R/UniXNU" --include="*.py" --include="*.md" --include="*.toml" 2>/dev/null | grep -v out/ | head
echo
echo '=== sheng-pmgr in board/configs:'
grep -rn "SHENG_PMGR\|sheng-pmgr\|sheng_pmgr" "$R/UniXNU" --include="*.py" --include="*.toml" 2>/dev/null | grep -v out/ | head -15
echo
echo '=== build-sheng-platform-power.py exists?'
find "$R/UniXNU" -name "build-sheng-platform-power.py" -not -path "*/out/*" 2>/dev/null
echo
echo '=== the socrates/vermeer adt tool pmgr handling:'
grep -n "pmgr\|PMGR" "$R/UniXNU-socrates/scripts/make-socrates-adt.py" | head -10
