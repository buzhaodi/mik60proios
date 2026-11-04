#!/usr/bin/env python3
"""Extract embedded FDT/DTB blobs from an Android boot image (or any file).

Scans for the FDT magic 0xD00DFEED at 4-byte alignment and dumps every blob.
Usage: bootimg_extract_dtbs.py <boot.img> <outdir>
"""
import struct
import sys
from pathlib import Path

FDT_MAGIC = 0xD00DFEED


def main():
    src, outdir = Path(sys.argv[1]), Path(sys.argv[2])
    blob = src.read_bytes()
    outdir.mkdir(parents=True, exist_ok=True)
    pos = 0
    found = 0
    while pos + 8 < len(blob):
        off = blob.find(b'\xd0\x0d\xfe\xed', pos)
        if off < 0 or off % 4:
            if off < 0:
                break
            pos = off + 1
            continue
        (magic, totalsize) = struct.unpack_from('>II', blob, off)
        if 40 <= totalsize <= 0x800000 and off + totalsize <= len(blob):
            (ostruct, ostrings, omem, version) = struct.unpack_from('>4I', blob, off + 8)
            if version in (16, 17) and ostruct < totalsize and ostrings < totalsize:
                name = outdir / f'dtb_{found:02d}_off{off:#x}.dtb'
                name.write_bytes(blob[off:off + totalsize])
                print(f'{name}: size {totalsize} version {version}')
                found += 1
                pos = off + totalsize
                continue
        pos = off + 4
    print(f'{found} blobs')


if __name__ == '__main__':
    main()
