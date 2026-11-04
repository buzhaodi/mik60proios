#!/bin/bash
# Find every consumer of the MemoryMapLib class across the WSL uefi-socrates
# checkout (submodules included, Build output excluded).
R=/home/yang/unixnu-work/uefi-socrates
echo "=== files mentioning MemoryMapLib (excluding its own lib and Build):"
grep -rln --include="*.inf" --include="*.dsc" --include="*.c" --include="*.h" "MemoryMapLib" "$R" 2>/dev/null |
  grep -v '/Build/' | grep -v 'socratesPkg/Library/MemoryMapLib'
echo
echo "=== who calls GetMemoryMap / the descriptor table:"
grep -rln --include="*.c" --include="*.h" "GetMemoryMap\|EFI_MEMORY_REGION_DESCRIPTOR" "$R" 2>/dev/null |
  grep -v '/Build/' | grep -v 'socratesPkg/Library/MemoryMapLib' | head
