#!/bin/bash
# Does the vermeer template (or the sm8550-common SoC repo) already carry the
# platform-power bridge that satisfies AMFI's ApplePMGRNub wait?
R=/home/yang/unixnu-work
for repo in UniXNU-vermeer UniXNU-sm8550-common UniXNU-sheng UniXNU-fuxi UniXNU-marble UniXNU-sirius; do
  d="$R/$repo"
  [ -d "$d" ] || continue
  echo "=== $repo:"
  grep -rn "platform-power\|PlatformPower\|SHENG_PMGR\|sheng-pmgr\|sheng_pmgr" "$d" \
      --include="*.toml" --include="*.py" --include="*.cpp" --include="*.sh" 2>/dev/null |
      grep -v "out/" | head -8
  find "$d" -iname "*platform*power*" -not -path "*/out/*" 2>/dev/null | head -5
  echo
done
echo "=== local device tree packages available under gittest:"
ls /mnt/d/ 2>/dev/null | head
