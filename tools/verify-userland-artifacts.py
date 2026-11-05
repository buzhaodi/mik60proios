#!/usr/bin/env python3
"""Verify the userland artifacts the way the kernel will read them.

Mirrors the checks of the board's CI (.github/workflows/userland.yml) so a locally built
userland image is validated with the same criteria before it goes into a payload:

  userland.img            N4KROOT container mockfs_mountroot parses (mockfs-test-file.patch)
  launchd.macho           the static arm64 Mach-O load_init_program() execs as PID 1
  kernel.macho.trustcache the v1/v2 trust-cache bundle DarwinBoot validates and AMFI checks

Usage: python3 verify-userland-artifacts.py BUILD_DIR [--test-source FILE]
  BUILD_DIR   the output directory of "bash userland/build.sh BUILD_DIR"
  --test-source   the file passed to mkn4kroot.py --test (userland/motd.txt); compared byte-exact
"""
import argparse
import json
import struct
import sys
from pathlib import Path

LC_LOAD_DYLIB = 0x0c
LC_LOAD_DYLINKER = 0x0e
LC_CODE_SIGNATURE = 0x1d
SUPERBLOB_MAGIC = b'\xfa\xde\x0c\xc0'
MOCKFS_LIMIT = 32 * 1024 * 1024   # mockfs_vfsops mountroot rejects a bigger container


def fail(message):
    print(f'  !! {message}')
    return 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('build_dir', type=Path)
    parser.add_argument('--test-source', type=Path)
    args = parser.parse_args()
    problems = 0

    img = (args.build_dir / 'userland.img').read_bytes()
    report = json.loads((args.build_dir / 'userland.json').read_text())
    macho = (args.build_dir / 'launchd.macho').read_bytes()
    trustcache = (args.build_dir / 'kernel.macho.trustcache').read_bytes()

    # --- the container header mockfs_mountroot validates (mockfs-test-file.patch) ---
    magic, version, count, launch_off, launch_size, test_off, test_size = \
        struct.unpack_from('<8sII4Q', img, 0)
    print(f'container: magic={magic!r} version={version} count={count}')
    print(f'container: launch {launch_size} @ {launch_off}, test {test_size} @ {test_off}, total {len(img)}')
    if magic != b'N4KROOT\x00':
        problems += fail('container magic is not N4KROOT')
    if version != 1 or count != 2:
        problems += fail('container version/count is not 1/2')
    if launch_off != 4096:
        problems += fail('launch_offset is not the one 4 KiB page mockfs requires')
    if not (test_off % 4096 == 0 and test_off >= 8192):
        problems += fail('test_offset is not 4 KiB aligned and >= 8192')
    if not (0 < launch_size <= test_off - launch_off and 0 < test_size <= len(img) - test_off):
        problems += fail('file sizes do not fit the container layout')
    if len(img) > MOCKFS_LIMIT:
        problems += fail(f'container is {len(img)} bytes; mockfs mountroot rejects over 32 MiB')

    # The launch file must really be the signed Mach-O, byte for byte.
    launch = img[launch_off:launch_off + launch_size]
    if launch != macho:
        problems += fail('the container launch file is not byte-identical to launchd.macho')
    if args.test_source is not None:
        if img[test_off:test_off + test_size] != args.test_source.read_bytes():
            problems += fail('the container test file is not byte-identical to its source')
        else:
            print('container: test file matches its source byte-exact')

    # --- the load commands of the executable the kernel will exec ---
    if struct.unpack_from('<I', launch, 0)[0] != 0xfeedfacf:
        problems += fail('launch file is not a 64-bit Mach-O (0xfeedfacf)')
    mh_flags = struct.unpack_from('<I', launch, 24)[0]
    ncmds = struct.unpack_from('<I', launch, 16)[0]
    off, commands, unixthread_off, segments = 32, set(), None, []
    for _ in range(ncmds):
        command, size = struct.unpack_from('<II', launch, off)
        commands.add(command)
        if command == 0x5:  # LC_UNIXTHREAD: the entry a dyld-less binary needs
            unixthread_off = off
        if command == 0x19:  # LC_SEGMENT_64: (vmaddr, vmsize)
            segments.append(struct.unpack_from('<QQ', launch, off + 24))
        off += size
    for name, code in (('LC_LOAD_DYLINKER', LC_LOAD_DYLINKER), ('LC_LOAD_DYLIB', LC_LOAD_DYLIB),
                       ('LC_CODE_SIGNATURE', LC_CODE_SIGNATURE)):
        print(f'launch:    {"has" if code in commands else "no "} {name}')
    # The kernel never reads LC_MAIN (mach_loader.c: dyld does) and its path
    # sets needs_dynlinker - with no dyld, parse_machfile fails and exec kills
    # PID 1 with EXEC_EXIT_REASON_BAD_MACHO. The entry must be LC_UNIXTHREAD.
    if 0x80000028 in commands:
        problems += fail('LC_MAIN is still present: the kernel demands a dyld it does not have')
    if unixthread_off is None:
        problems += fail('no LC_UNIXTHREAD: the kernel has no entry point to start PID 1 at')
    else:
        ut_cmd, ut_size, ut_flavor, ut_count = struct.unpack_from('<4I', launch, unixthread_off)
        ut_sp, ut_pc = struct.unpack_from('<QQ', launch, unixthread_off + 16 + 248)
        print(f'launch:    LC_UNIXTHREAD flavor {ut_flavor}, pc {ut_pc:#x}')
        if not (ut_size == 288 and ut_flavor == 6 and ut_count == 68):
            problems += fail('LC_UNIXTHREAD is not an arm_thread_state64 (288 bytes, flavor 6, count 68)')
        if ut_sp != 0:
            problems += fail('LC_UNIXTHREAD sp is not 0 (the kernel places the default stack)')
        if not any(vmaddr <= ut_pc < vmaddr + vmsize for vmaddr, vmsize in segments):
            problems += fail('LC_UNIXTHREAD pc is outside the mapped segments')
    if LC_LOAD_DYLINKER in commands or LC_LOAD_DYLIB in commands:
        problems += fail('dynamic load commands present: this root has no dyld')
    if LC_CODE_SIGNATURE not in commands:
        problems += fail('no LC_CODE_SIGNATURE: the kernel refuses an unsigned root executable')
    if SUPERBLOB_MAGIC not in launch:
        problems += fail('no embedded signature SuperBlob (FADE0CC0)')
    if mh_flags & 0x20000000:   # MH_PIE
        problems += fail('Mach-O is still PIE: a static RAM-root image has nothing to slide')
    if mh_flags & 0x40000000:   # MH_DYLDLINK
        problems += fail('MH_DYLDLINK still set: the image must not require a dynamic linker')

    # --- the trust cache DarwinBoot validates and AMFI looks the cdhash up in ---
    cache_count, cache_offset = struct.unpack_from('<2I', trustcache, 0)
    if cache_count != 1 or cache_offset != 8:
        problems += fail('trust cache header is not version-1 with one module')
    elif struct.unpack_from('<I', trustcache, 8)[0] != 2:
        problems += fail('trust cache module is not version 2')
    else:
        entries = struct.unpack_from('<I', trustcache, 28)[0]
        entry = trustcache[32:32 + 20].hex()
        print(f'cache:     {entries} entry, cdhash {entry}')
        if entries != 1:
            problems += fail('trust cache does not hold exactly one cdhash')
        if entry != report['cdhash']:
            problems += fail('trust cache does not name the signature that was embedded')
        # v2 module: 8-byte v1 header + 24-byte module header + one 24-byte record (20 cdhash + 4 category)
        if len(trustcache) != 8 + 24 + 24 * entries:
            problems += fail('trust cache size does not match its entry count')
        category = trustcache[32 + 20]
        if not 1 <= category <= 4:
            problems += fail(f'trust cache category byte {category} is outside the 1-4 range DarwinBoot validates')

    print(f'launch:    cdhash {report["cdhash"]}, code_limit {report["code_limit"]}, pages {report["pages"]}')
    if problems:
        print(f'FAILED: {problems} problem(s)')
        return 1
    print('PASS: userland artifacts are what the kernel will accept')
    return 0


if __name__ == '__main__':
    sys.exit(main())
