#!/usr/bin/env python3
"""Build the opt-in, guarded sheng original-PMGR integration instrument."""
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/sheng-platform-power'
OUT.mkdir(parents=True, exist_ok=True)
sys.path.insert(0, str(ROOT / 'kits/NativePrelink'))
from native_prelink import macho, backed_offset, exports

# A clean checkout has no native-owner-ufs candidate: this tree's own built
# prelinked kernel IS one - emit_prelink built it from the same pinned original
# kernelcache with the same slide, and it carries the same original ApplePMGR /
# AppleMobileFileIntegrity kexts (kernel.json holds the plan the audit pins
# against). Materialize the candidate layout the audit and the builder expect,
# plus the original-kernelcache copy the audit's target-provider section reads.
# Symlink targets are ABSOLUTE: the tree .cache is itself a symlink into the
# board repository, so a relative target written there resolves against the
# board checkout, not the tree, and ends up broken.
_kernel = ROOT / '../kernel/kernel.macho'
if _kernel.is_file():
    _prelink = ROOT / 'build/xnu-prelink'
    _prelink.mkdir(parents=True, exist_ok=True)
    for _name, _src in (('native-owner-ufs-cpu-desktop-0-candidate.macho', _kernel),
                        ('native-owner-ufs-cpu-desktop-0-candidate.json', ROOT / '../kernel/kernel.json')):
        _dst = _prelink / _name
        if not _dst.is_file():
            _dst.unlink(missing_ok=True)
            os.symlink(str(_src.resolve()), _dst)
_firmware = ROOT / '.cache/firmware/kernelcache.macho/kernelcache.release.ipad7.decompressed'
if not _firmware.is_file():
    _source = ROOT / '../../ipsw/21H461/kernelcache.decompressed'
    if _source.is_file() and hashlib.sha256(_source.read_bytes()).hexdigest() == \
            'f18b4df865405f2a287b84977d7aca745e056d656d9fc9df1662970ce2969de7':
        _firmware.parent.mkdir(parents=True, exist_ok=True)
        _firmware.unlink(missing_ok=True)
        os.symlink(str(_source.resolve()), _firmware)

# Clean first build: the audit needs a PREVIOUS prelink output as its reference
# candidate (a raw kernelcache is not enough - the audit pins per-module hashes
# against the emit_prelink plan json). With nothing materialized yet, defer
# gracefully: this kernel pass links without the bridge, and the pass's own
# prelink output feeds the NEXT kernel pass (the two-pass flow is normal: the
# bridge's audit validates against a prelinked candidate by design).
if not any((ROOT / 'build/xnu-prelink').glob('native-owner-ufs-*-candidate.macho')):
    print('PMGR bridge deferred: no reference candidate yet (clean build).')
    print('This kernel pass links without the bridge; run the kernel step a')
    print('SECOND time - the first prelink materializes the candidate it needs.')
    sys.exit(0)


def run(command, **kwargs):
    return subprocess.check_output([str(v) for v in command], timeout=90, **kwargs)


def require(value, message):
    if not value:
        raise SystemExit(message)


print(run(['python3', ROOT / 'scripts/audit-amfi-pmgr-contract.py'], text=True), end='')
header = '''// Generated exact storage/slot ABI; private fields stay opaque.
#pragma once
#include <IOKit/IOPMGR.h>
class ApplePMGR : public IOPMGR {
 OSDeclareAbstractStructors(ApplePMGR)
 unsigned char originalPrivate[0x4b8a8-sizeof(IOPMGR)];
public:
'''
guards = ''
for i in range(177, 340):
    if i == 320:
        header += ' virtual uint32_t readAon();\n'
    elif i == 321:
        header += ' virtual void writeAon(uint64_t);\n'
    else:
        header += f' virtual void opaque{i}() = 0;\n'
        guards += f' void opaque{i}() override {{ unavailable({i}); }}\n'
header += '};\nstatic_assert(sizeof(ApplePMGR)==0x4b8a8,"Original provider storage");\n'
(OUT / 'OriginalPMGRABI.h').write_text(header)
(OUT / 'GuardedPMGRSlots.inc').write_text(guards)
source = ROOT / 'kits/socrates/ShengPlatformPower.cpp'
obj = OUT / 'ShengPlatformPower.o'
record = json.loads((ROOT / 'build/xnu/ios-obj/DEVELOPMENT_ARM64_BCM2837/iokit/DEVELOPMENT/IOPlatformExpert.cpo.json').read_text().strip().rstrip(','))
command, i = [], 0
arguments = record['arguments']
while i < len(arguments):
    arg = arguments[i]
    if arg == record['file']:
        command.append(source)
    elif arg == '-o':
        command += ['-o', obj]
        i += 1
    elif arg == '-Xclang' and arguments[i + 1].startswith('-W'):
        i += 1
    elif not arg.startswith('-W'):
        command.append(arg)
    i += 1
command += ['-Wall', '-Wextra', '-Werror', '-Wno-unknown-warning-option', '-Wno-unused-parameter', '-Wno-c99-designator',
            '-Wno-reorder-init-list', '-Wno-deprecated-enum-enum-conversion',
            '-Wno-unnecessary-virtual-specifier', '-I', OUT, '-I', ROOT / '.cache/xnu-work/osfmk']
run(command, cwd=record['directory'])
raw = obj.read_bytes()
info = macho(raw)
require(info['kind'] == 1, 'Require actual ARM64 subtype-0 Mach-O object')
build_version = [struct.unpack_from('<2I', raw, at + 8) for cmd, at, _ in info['commands'] if cmd == 0x32]
require(build_version == [(2, 0x110000)], 'Require iOS17 build target')
sym_at = next(at for cmd, at, _ in info['commands'] if cmd == 2)
at, count, strings, _ = struct.unpack_from('<4I', raw, sym_at + 8)
symbols = []
for i in range(count):
    ix, kind, _, _, address = struct.unpack_from('<IBBHQ', raw, at + i * 16)
    symbols.append((raw[strings + ix:raw.index(b'\0', strings + ix)].decode(), address, kind))
vtable = next(va for name, va, _ in symbols if name == '__ZTV18ShengPlatformPower')
relocations = {}
for segment in info['segments']:
    for section in segment['sections']:
        if section['va'] <= vtable < section['va'] + section['size']:
            at, count = struct.unpack_from('<2I', raw, section['command_offset'] + 56)
            for i in range(count):
                offset, bits = struct.unpack_from('<2I', raw, at + i * 8)
                if bits >> 27 & 1 and bits >> 28 == 0 and bits >> 25 & 3 == 3:
                    relocations[section['va'] + offset] = symbols[bits & 0xffffff][0]
entries = [relocations.get(vtable + 16 + i * 8) for i in range(340)]
require(all(entries) and vtable + 16 + 340 * 8 not in relocations, 'Exact 340-entry provider table')
reference = ROOT / 'build/xnu-prelink/native-owner-ufs-rootauth3-candidate.macho'
if not reference.exists():
    # Build products are pruned: a later candidate built from the same original kernelcache has the identical original
    # ApplePMGR class and inherited native IOPMGR slots; every slot/pointer check below still runs against it.
    later = sorted((ROOT / 'build/xnu-prelink').glob('native-owner-ufs-cpu-desktop-*-candidate.macho'), key=lambda f: f.stat().st_mtime)
    require(later, 'No reference candidate available (run the kernel step once first)')
    reference = later[-1]
candidate = reference.read_bytes()
meta = macho(candidate)
native_names = {n: va for va, names in exports(candidate, meta).items() for n in names}


def ptr(va):
    return struct.unpack_from('<Q', candidate, backed_offset(meta['segments'], va, 8, len(candidate)))[0]


bindings = {'__ZN9ApplePMGRC2EPK11OSMetaClass': 0xfffffff0049f003c,
            '__ZN9ApplePMGRD2Ev': 0xfffffff0049f019c,
            '__ZN9ApplePMGR10gMetaClassE': 0xfffffff006adf490}
for slot, name in enumerate(entries):
    if slot in (0, 1, 7) or 168 <= slot < 340 and slot not in (320, 321):
        require('18ShengPlatformPower' in name, f'Own guard/lifecycle required at slot {slot}')
    elif slot in (320, 321):
        require('9ApplePMGR' in name, 'Only actual original AON implementations inherited')
        bindings[name] = ptr(0xfffffff005ce26d8 + slot * 8)
    else:
        require(native_names.get(name) == ptr(native_names['__ZTV6IOPMGR'] + 16 + slot * 8),
                f'Native IOPMGR/IOService entry differs at {slot}')
undefined = {n for n, _, k in symbols if k == 1 and 'ApplePMGR' in n}
require(undefined == set(bindings), 'All and only audited original base imports')
bindings.update({'_sheng_original_pmgr_nub_create': 0xfffffff004a22568,
                 '_sheng_original_pmgr_nub_read': 0xfffffff004a24adc,
                 '_sheng_original_pmgr_nub_write': 0xfffffff004a230ec})
asm = OUT / 'original-bindings.S'
asm.write_text(''.join(f'.globl {name}\n.set {name}, {va:#x}\n' for name, va in bindings.items()))
sdk = run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
run(['xcrun', 'clang', '-target', 'arm64-apple-ios17.0', '-isysroot', sdk, '-c', asm, '-o', OUT / 'original-bindings.o'])
late = OUT / 'ShengPlatformPower.late.o'
# llvm-objcopy cannot edit Mach-O; make the two edits directly, without touching
# any instruction: empty __DATA,__mod_init_func (the publication runs from the
# sheng_pmgr_run hook in bsd_init, not from a C++ static initializer) and
# globalize the initializer symbol. section_64 layout: addr +32, size +40,
# reloff +56, nreloc +60; nlist_64 n_type is +4 into each 16-byte entry.
blob = bytearray(raw)
mod_init = next(s for seg in info['segments'] for s in seg['sections'] if s['name'] == '__mod_init_func')
struct.pack_into('<Q', blob, mod_init['command_offset'] + 40, 0)   # size
struct.pack_into('<II', blob, mod_init['command_offset'] + 56, 0, 0)  # reloff, nreloc
entry = next(i for i, (n, _, _) in enumerate(symbols)
             if n == '__GLOBAL__sub_I_ShengPlatformPower.cpp')
blob[at + entry * 16 + 4] |= 0x01  # N_EXT
late.write_bytes(bytes(blob))


def text_section(blob):
    section = next(s for seg in macho(blob)['segments'] for s in seg['sections'] if s['name'] == '__text')
    return blob[section['fileoff']:section['fileoff'] + section['size']]


require(text_section(raw) == text_section(late.read_bytes()), 'Late registration cannot change instructions')
archive = OUT / 'libShengPlatformPower.a'
archive.unlink(missing_ok=True)
run(['xcrun', 'ar', 'rcs', archive, late, OUT / 'original-bindings.o'])
report = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'archive_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
          'bindings': {name: hex(va) for name, va in bindings.items()}, 'virtual_entries': 340,
          'mode': 'opt-in lifecycle/publication/refusal instrument; not a functional power backend',
          'runtime_qualified': False, 'original_executable_modified': False}
(OUT / 'build-report.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS: ordinary ARM64/iOS17 build; exact native and original bindings; unimplemented power slots stop')
