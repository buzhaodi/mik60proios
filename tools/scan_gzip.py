#!/usr/bin/env python3
"""Scan a binary for gzip members and try to decompress each; print text candidates.

Usage: scan_gzip.py <file> [outdir]
"""
import sys
import zlib
from pathlib import Path


def main():
    src = Path(sys.argv[1])
    outdir = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    blob = src.read_bytes()
    pos = 0
    found = 0
    while True:
        off = blob.find(b'\x1f\x8b\x08', pos)
        if off < 0:
            break
        d = zlib.decompressobj(16 + zlib.MAX_WBITS)
        try:
            data = d.decompress(blob[off:off + 20_000_000])
        except zlib.error:
            pos = off + 1
            continue
        if len(data) > 200:
            found += 1
            printable = sum(32 <= b < 127 or b in (9, 10, 13) for b in data[:2000]) / min(len(data), 2000)
            print(f'gzip @{off:#x}: {len(data)} bytes, printable {printable:.2f}, head={data[:60]!r}')
            if outdir is not None and printable > 0.85:
                (outdir / f'gzip_{off:#x}.bin').write_bytes(data)
        pos = off + 1
    print(f'{found} gzip members')


if __name__ == '__main__':
    main()
