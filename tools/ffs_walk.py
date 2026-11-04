#!/usr/bin/env python3
"""Walk FFS files in a UEFI firmware volume; list files and their sections.

Usage: ffs_walk.py <fv.bin> [extract-dir]
"""
import struct
import sys
from pathlib import Path

SECTION_NAMES = {0x01: 'COMPRESSION', 0x02: 'GUID_DEFINED', 0x14: 'VERSION',
                 0x15: 'USER_INTERFACE', 0x16: 'COMPATIBILITY16', 0x17: 'FIRMWARE_VOLUME_IMAGE',
                 0x18: 'FREEFORM_SUBTYPE_GUID', 0x19: 'RAW', 0x1B: 'PE32', 0x1C: 'PIC',
                 0x01 | 0x80: ''}
FILE_TYPES = {0x02: 'FREEFORM', 0x03: 'SEC_CORE', 0x07: 'DRIVER', 0x08: 'COMBINED_PEIM_DRIVER',
              0x09: 'APPLICATION', 0x0B: 'FIRMWARE_VOLUME_IMAGE', 0x0C: 'COMBINED_SMM_DXE',
              0x0D: 'SMM', 0xF0: 'FFS_PAD', 0x01: 'RAW'}


def ffs_files(blob, fv_base, fv_len, hlen):
    pos = fv_base + hlen
    end = fv_base + fv_len
    while pos + 24 <= end:
        hdr = blob[pos:pos + 24]
        name = hdr[:16]
        (itype_check, ftype, attrs) = struct.unpack_from('<HBB', blob, pos + 16)
        size = hdr[20] | (hdr[21] << 8) | (hdr[22] << 16)
        state = hdr[23]
        if size in (0, 0xFFFFFF) or size < 24:
            break
        yield pos, name, ftype, size
        pos = (pos + size + 7) & ~7


def sections(blob, start, end):
    pos = start
    while pos + 4 <= end:
        size = blob[pos] | (blob[pos+1] << 8) | (blob[pos+2] << 16)
        stype = blob[pos+3]
        if size < 4 or pos + size > end:
            break
        yield pos, size, stype
        pos = (pos + size + 3) & ~3


def main():
    blob = Path(sys.argv[1]).read_bytes()
    outdir = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    (fv_base,) = (blob.find(b'_FVH') - 0x28,)
    fvlen = struct.unpack_from('<Q', blob, fv_base + 32)[0]
    hlen = struct.unpack_from('<H', blob, fv_base + 0x30)[0]
    for pos, name, ftype, size in ffs_files(blob, fv_base, fvlen, hlen):
        guid = name.hex()
        label = FILE_TYPES.get(ftype, hex(ftype))
        ui = ''
        for spos, ssize, stype in sections(blob, pos + 24, pos + size):
            if stype == 0x15:
                try:
                    ui = blob[spos+4:spos+ssize].decode('utf-16-le').rstrip('\0')
                except UnicodeDecodeError:
                    pass
        if ftype != 0xF0:
            print(f'@{pos:#x} {label:12} {guid}  "{ui}"')
            if outdir and ui:
                for spos, ssize, stype in sections(blob, pos + 24, pos + size):
                    if stype in (0x19, 0x01):
                        (outdir / f'{pos:#x}_{ui}.sec{stype:02x}').write_bytes(blob[spos+4:spos+ssize])


if __name__ == '__main__':
    main()
