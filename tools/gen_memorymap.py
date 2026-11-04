#!/usr/bin/env python3
"""Generate socratesPkg MemoryMapLib.c from measured inputs.

Sources (all measured from the socrates OS3.0.304.0.WMKCNXM fastboot archive):
  - the stock uefiplat.cfg text region of images/uefi.elf (sha256 90648bc5...),
  - the socrates base dtb (vendor_boot images, Kalama QCM, msm-id 0x25c),
  - the socrates dtbo overlay entry 50 (model "8550 socrates").

Algorithm: the stock [MemoryMap] regions and the DT no-map reservations are both
coverage obligations with attribute rules (check-socrates.py): every stock region
must be covered, a descriptor overlapping a stock NoMap range must be
HobOnlyNoCacheSetting, one overlapping a stock Reserv range must be Reserv, and
every DT reservation must sit inside a single Reserv descriptor. The map below
partitions the stock+DT interval union at every boundary, so descriptors never
overlap: a segment inside a DT reservation takes the DT name (HobOnly when a
covering stock range is NoMap, Reserv otherwise); a segment only in stock keeps
the stock attributes (NoMap stock -> HobOnly, MEM_RES stock -> Reserv); a segment
outside both is Conventional. The port UEFI FD policy follows sheng/vermeer: a
3 MiB FD at 0xA7100000 inside the stock 4 MiB window at 0xA7000000.
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from dtbo_summary import walk_nodes

DRAM_BASE = 0x80000000
DRAM_TOP = 0x100000000
PAGE = 0x1000
# the port FD splits the stock 4 MiB UEFI FD window (0xA7000000)
PORT_FD = [(0xA7000000, 0x100000, 'FD Reserved'), (0xA7100000, 0x300000, 'UEFI FD')]

# Gaps between the stock cfg and DT regions that are NOT usable DDR: XPU/TZ
# protection or windows the stock firmware never allocates from. Filling these
# with Conventional memory lets MemoryInitPei publish them as write-back system
# memory, and the first DXE allocation inside dies as a synchronous external
# abort (first-boot hardware evidence: FAR 0xD8000000, ESR 0x96000010). Gaps
# INSIDE a stock Conv window (the DXE Heap pieces at 0xC7CC0000 and
# 0xDFC00000) stay Conventional.
PROTECTED_GAPS = [
    (0x81CF4000, 0xC000),      # aop_config end..SMEM start
    (0x81F20000, 0x6E0000),    # adsp_mhi end..global_sync: TZ neighbourhood
    (0x82800000, 0x4600000),   # tz_stat end..RSRV1: TZ core, no stock/DT cover
    (0x89800000, 0x1000000),   # RSRV1 end..mpss: mpss-adjacent
    (0xD8000000, 0x100000),    # mpss_dsm end..xbl_sc: the proven crash hole
    (0xA5580000, 0xB80000),    # Display Demura end..DBI Dump
    (0xDFC00000, 0x6840000),   # TZApps end..hwfence: outside every DRAM bank
    (0xE671D000, 0x190E3000),  # hwfence end..llcc_lpi: stock never uses below 4 GiB
]


def parse_stock(path):
    text = Path(path).read_text()
    mem = text.split('[MemoryMap]')[1].split('[RegisterMap]')[0]
    regions = []
    for line in mem.splitlines():
        line = line.strip()
        if not line.startswith('0x'):
            continue
        parts = [p.strip() for p in line.split(',')]
        base, size = int(parts[0], 16), int(parts[1], 16)
        regions.append(dict(name=parts[2].strip('"'), addr=base, size=size,
                            hobop=parts[3], rt=parts[4], ra=parts[5], mt=parts[6], ca=parts[7]))
    reg = text.split('[RegisterMap]')[1].split('\n[')[0]
    registers = []
    for line in reg.splitlines():
        line = line.strip()
        if not line.startswith('0x'):
            continue
        parts = [p.strip() for p in line.split(',')]
        if len(parts) != 8:
            continue
        registers.append(dict(name=parts[2].strip('"'), addr=int(parts[0], 16), size=int(parts[1], 16),
                              hobop=parts[3], rt=parts[4], ra=parts[5], mt=parts[6], ca=parts[7]))
    return regions, registers


def dt_regions():
    regions = []
    blob = open('firmware/base_dtb/dtb_00_off0x1d47000.dtb', 'rb').read()
    for path, props in list(walk_nodes(blob)):
        if not path.startswith('/reserved-memory/') or path.count('/') != 2:
            continue
        if 'reg' not in props or 'no-map' not in props:
            continue
        reg = props['reg']
        if len(reg) != 16:
            continue
        cells = struct.unpack('>4I', reg)
        addr = (cells[0] << 32) | cells[1]
        size = (cells[2] << 32) | cells[3]
        # page-round (dump_display_region is 0x800; containment keeps the DT extent)
        size = (size + PAGE - 1) & ~(PAGE - 1)
        regions.append((path.rsplit('/', 1)[-1], addr, size))
    dtbo = open('firmware/extracted/socrates_images_OS3.0.304.0.WMKCNXM_16.0/images/dtbo.img', 'rb').read()
    (magic, total, hs, es, ec, ps, ver) = struct.unpack_from('>7I', dtbo, 0)
    off = hs + 50 * es
    dt_size, dt_offset = struct.unpack_from('>2I', dtbo, off)
    sub = dtbo[dt_offset:dt_offset + dt_size]
    for path, props in list(walk_nodes(sub)):
        if '/__overlay__/' not in path or 'reg' not in props:
            continue
        name = path.rsplit('/', 1)[-1]
        if not any(k in name for k in ('splash_region', 'xbl_dt_log', 'aop_image',
                                       'xbl_ramdump_region', 'dump_display_region', 'disp_rdump_region')):
            continue
        reg = props['reg']
        if len(reg) != 16:
            continue
        cells = struct.unpack('>4I', reg)
        addr = (cells[0] << 32) | cells[1]
        size = (cells[2] << 32) | cells[3]
        if addr < DRAM_BASE:
            continue
        # splash_region and disp_rdump_region sit inside the stock Display Reserved
        # window; the stock entry already covers them
        if addr == 0xB8000000:
            continue
        size = (size + PAGE - 1) & ~(PAGE - 1)
        regions.append((name, addr, size))
    # The socrates DT has no reservation for 0xD8000000..0xD8100000 (mpss_dsm ends
    # exactly at 0xD8000000, xbl_sc starts at 0xD8100000) while the vermeer (K70) DT
    # carries tz-reserved-region@d8000000 there. On the phone this hole is not
    # NS-accessible: the first boot allocated DXE memory into it and the access
    # died as a synchronous external abort (FAR 0xD8000000, ESR 0x96000010) - so
    # reserve it explicitly, like the K70 tree does.
    regions.append(('tz-reserved-region@d8000000', 0xD8000000, 0x100000))
    # de-duplicate (the dtbo repeats base-dt names); keep the largest extent per name+addr
    return sorted(set(regions), key=lambda r: (r[1], r[0]))


def main():
    stock, registers = parse_stock('firmware/uefi_extract/socrates-uefiplat.cfg')
    dt = dt_regions()
    # drop the stock UEFI FD window (the port FD split replaces it)
    stock_keep = [r for r in stock if r['name'] != 'UEFI FD']

    # coverage obligations and boundaries
    bounds = set()
    for r in stock_keep:
        bounds.add(r['addr'])
        bounds.add(r['addr'] + r['size'])
    for _, a, s in dt:
        bounds.add(a)
        bounds.add(a + s)
    for a, s, _n in PORT_FD:
        bounds.add(a)
        bounds.add(a + s)
    bounds = sorted(b for b in bounds if DRAM_BASE <= b <= DRAM_TOP)

    def covering_stock(a, s):
        return [r for r in stock_keep if a < r['addr'] + r['size'] and r['addr'] < a + s]

    def covering_dt(a, s):
        return [d for d in dt if a >= d[1] and a + s <= d[1] + d[2]]

    def in_port_fd(a, s):
        return any(a >= fa and a + s <= fa + fs for fa, fs, _n in PORT_FD)

    entries = []
    for lo, hi in zip(bounds, bounds[1:]):
        size = hi - lo
        dts = covering_dt(lo, size)
        stocks = covering_stock(lo, size)
        if dts:
            # the stock name is the ABI: LocateMemoryRegionByName looks regions
            # up by the stock cfg label ("XBL DT", "SMEM", "AOP", ...), and a
            # DT-node name hides them - IortDtDxe scans an uninitialized
            # descriptor when "XBL DT" cannot be found (first-boot evidence:
            # it dereferenced stack garbage 0xD8000000 as the region base)
            name = stocks[0]['name'] if stocks else dts[0][0]
            if any(r['hobop'] == 'NoMap' for r in stocks):
                hobop, rt, ra, mt, ca = 'HobOnlyNoCacheSetting', 'MEM_RES', 'UNCACHEABLE', 'Reserv', 'UNCACHED_UNBUFFERED_XN'
            else:
                hobop, rt, ra, mt, ca = 'AddMem', 'MEM_RES', 'UNCACHEABLE', 'Reserv', 'UNCACHED_UNBUFFERED_XN'
            entries.append((name, lo, size, hobop, rt, ra, mt, ca))
        elif in_port_fd(lo, size):
            name = next(n for fa, fs, n in PORT_FD if lo >= fa and lo + size <= fa + fs)
            entries.append((name, lo, size, 'AddMem', 'SYS_MEM', 'SYS_MEM_CAP', 'BsData', 'WRITE_BACK'))
        elif stocks:
            r = stocks[0]
            if r['hobop'] == 'NoMap':
                # a stock NoMap range must not be mapped
                entries.append((r["name"], lo, size, "HobOnlyNoCacheSetting", 'MEM_RES', 'UNCACHEABLE', 'Reserv', 'UNCACHED_UNBUFFERED_XN'))
            else:
                mt = 'Reserv' if r['mt'] == 'Reserv' else r['mt']
                entries.append((r["name"], lo, size, "AddMem", r["rt"], r["ra"], mt, r["ca"]))
        else:
            if any(lo >= a and lo + size <= a + s for a, s in PROTECTED_GAPS):
                entries.append((f'protected gap {lo:#x}', lo, size,
                                'AddMem', 'MEM_RES', 'UNCACHEABLE', 'Reserv', 'UNCACHED_UNBUFFERED_XN'))
            else:
                entries.append((f'DRAM gap {lo:#x}', lo, size, 'AddMem', 'SYS_MEM', 'SYS_MEM_CAP', 'Conv', 'WRITE_BACK_XN'))

    # the sheng-proven conservative second-bank entry
    entries.append(('DRAM bank 1 low', 0x880000000, 0x3B300000, 'AddMem', 'SYS_MEM', 'SYS_MEM_CAP', 'Conv', 'WRITE_BACK_XN'))
    # register map verbatim
    for r in registers:
        entries.append((r['name'], r['addr'], r['size'],
                        'NoHob' if r['hobop'] == 'NoHob' else r['hobop'],
                        r['rt'], r['ra'], r['mt'], r['ca']))

    # merge adjacent segments that share name and attributes (readability only)
    merged = []
    for e in entries:
        e = list(e)
        if merged and merged[-1][0] == e[0] and merged[-1][1] + merged[-1][2] == e[1] and merged[-1][3:] == e[3:]:
            merged[-1][2] += e[2]
        else:
            merged.append(e)

    # EFI_MEMORY_REGION_DESCRIPTOR.Name is CHAR8[32]: keep the C string within 31 chars,
    # dropping the @address hint first (names are display text; coverage is by interval)
    def fit(name):
        if len(name) <= 31:
            return name
        if '@' in name:
            name = name.split('@', 1)[0]
        return name[:31]

    merged = [(fit(e[0]), *e[1:]) for e in merged]
    lines = ['  {"%s", %#x, %#x, %s, %s, %s, %s, %s},' % tuple(e) for e in merged]
    Path('out/memorymap_entries.c').write_text('\n'.join(lines) + '\n', encoding='utf-8', newline='\n')
    print(f'{len(merged)} descriptors -> out/memorymap_entries.c')
    # self-audit: overlaps and page alignment below 4 GiB
    dram = sorted([e for e in merged if DRAM_BASE <= e[1] < DRAM_TOP], key=lambda e: e[1])
    for a, b in zip(dram, dram[1:]):
        if a[1] + a[2] > b[1]:
            print(f'OVERLAP: {a[0]} {a[1]:#x}+{a[2]:#x} vs {b[0]} {b[1]:#x}')
    for e in dram:
        if e[1] % PAGE or e[2] % PAGE:
            print(f'UNALIGNED: {e[0]} {e[1]:#x}+{e[2]:#x}')
    print('self-audit done')


if __name__ == '__main__':
    main()
