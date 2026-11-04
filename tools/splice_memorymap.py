#!/usr/bin/env python3
"""Replace the gMemoryDescriptor block in MemoryMapLib.c with the freshly
generated out/memorymap_entries.c lines (2-space indent, trailing commas)."""
from pathlib import Path

cpath = Path('uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c')
entries = [l.strip().rstrip(',').lstrip() for l in Path('out/memorymap_entries.c').read_text().splitlines() if l.strip().startswith('{"')]
lines = cpath.read_text().splitlines()
start = lines.index('STATIC EFI_MEMORY_REGION_DESCRIPTOR gMemoryDescriptor[] = {')
end = next(i for i in range(start + 1, len(lines)) if lines[i] == '};')
block = ['STATIC EFI_MEMORY_REGION_DESCRIPTOR gMemoryDescriptor[] = {'] + ['  ' + l + ',' for l in entries] + ['};']
cpath.write_text('\n'.join(lines[:start] + block + lines[end + 1:]) + '\n', newline='\n')
print(f'spliced {len(entries)} descriptors (was {end - start - 1})')
