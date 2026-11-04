#!/usr/bin/env python3
"""Resolve pinctrl/clock phandles of the two stock UART nodes to TLMM pin
configs and GCC clock names - identifies the Type-C debug UART and gives the
driver its clock dependencies."""
import struct
import sys


def walk(data, off, path, nodes, props):
    # FDT structural walk: nodes[(path)] = {prop: bytes}
    while True:
        tag = struct.unpack_from('>I', data, off)[0]
        off += 4
        if tag == 0x1:  # FDT_BEGIN_NODE
            end = data.index(b'\0', off)
            name = data[off:end].decode()
            off = (end + 4) & ~3
            parent = path
            path = path + '/' + name if name else path
            off = walk(data, off, path, nodes, props)
            path = parent
        elif tag == 0x2:  # FDT_END_NODE
            return off
        elif tag == 0x3:  # FDT_PROP
            size, nameoff = struct.unpack_from('>2I', data, off)
            off += 8
            name = strings[data.index(b'\0', strings_off + nameoff):].split(b'\0')[0].decode() if False else None
            name = get_string(nameoff)
            props.setdefault(path, {})[name] = data[off:off + size]
            off = (off + size + 3) & ~3
        elif tag == 0x4:  # FDT_NOP
            continue
        elif tag == 0x9:  # FDT_END
            return len(data)
        else:
            raise SystemExit(f'unexpected tag {tag:#x} at {off:#x}')


data = open(sys.argv[1], 'rb').read()
magic, totalsize, off_struct, off_strings = struct.unpack_from('>4I', data, 0)
strings = data[off_strings:]


def get_string(off):
    end = strings.index(b'\0', off)
    return strings[off:end].decode()


nodes, props = [], {}
walk(data, off_struct, '', nodes, props)
phandle_map = {}
for path, pr in props.items():
    if 'phandle' in pr:
        phandle_map[struct.unpack('>I', pr['phandle'])[0]] = (path, pr)

for want in (0x1ea, 0x1eb,):
    if want in phandle_map:
        path, pr = phandle_map[want]
        print(f'phandle {want:#x} -> {path}')
        for k, v in pr.items():
            if not v:
                continue
            if k in ('pins', 'function', 'bias-disable', 'drive-strength', 'input-enable'):
                vals = struct.unpack(f'>{len(v)//4}I', v) if len(v) % 4 == 0 else v
                print(f'    {k}: {vals}')
    else:
        print(f'phandle {want:#x} not found')

print()
for uart in ('/soc/qcom,qupv3_1_geni_se@ac0000/qcom,qup_uart@a9c000',
             '/soc/qcom,qupv3_2_geni_se@8c0000/qcom,qup_uart@898000'):
    pr = props.get(uart, {})
    print(f'{uart}:')
    for k in ('clocks', 'clock-names'):
        if k in pr:
            words = struct.unpack(f'>{len(pr[k])//4}I', pr[k])
            names = [phandle_map[w][0] for w in words[::2] if w in phandle_map]
            print(f'  {k}: {list(zip(names, words[1::2])) if k == "clocks" else pr[k]}')
    for k in ('compatible', 'reg-names'):
        if k in pr:
            print(f'  {k}: {pr[k]}')
