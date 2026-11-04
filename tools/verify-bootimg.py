#!/usr/bin/env python3
"""Manually unpack the produced boot image (v0) and check the kernel blob's gzip."""
import struct
import zlib
from pathlib import Path

img = Path('/home/yang/unixnu-work/UniXNU/out/socrates/boot/boot.img').read_bytes()
print('magic:', img[:8])
ksize, kaddr, rsize, raddr, ssize, saddr, tags, page = struct.unpack_from('<8I', img, 8)
print(f'kernel {ksize:#x} @{kaddr:#x}, ramdisk {rsize:#x}, page {page:#x}, version {struct.unpack_from("<I", img, 40)[0]}')
kernel = img[page:page + ksize]
print('kernel head:', kernel[:8].hex(), '| gzip magic ok:', kernel[:2] == b'\x1f\x8b')
u = zlib.decompressobj(16 + zlib.MAX_WBITS)
data = u.decompress(kernel)
print('decompressed:', len(data), 'eof:', u.eof, 'unused:', len(u.unused_data))
