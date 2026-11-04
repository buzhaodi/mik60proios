#!/usr/bin/env python3
"""Replicate the check-socrates.py map-row regex against the WSL MemoryMapLib.c."""
import re
import sys

path = '/home/yang/unixnu-work/uefi-socrates/Platforms/Xiaomi/socratesPkg/Library/MemoryMapLib/MemoryMapLib.c'
source = open(path, encoding='utf-8').read()
rows = [(m[1], int(m[2], 16), int(m[3], 16), m[4]) for m in re.finditer(
    r'\{"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),([^}]+)\}', source)]
print('rows:', len(rows))
print('head:', rows[:3] if rows else source[:200])
