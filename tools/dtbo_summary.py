#!/usr/bin/env python3
"""Summarize each DTBO entry: board ids, panel nodes, touch nodes, splash regions.

Usage: dtbo_summary.py <dtbo.img>
"""
import struct
import sys

FDT_MAGIC = 0xD00DFEED
BEGIN_NODE, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9
DTBO_MAGIC = 0xD7B7AB1E


def get_string(blob, off_strings, offset):
    end = blob.index(b'\0', off_strings + offset)
    return blob[off_strings + offset:end].decode('ascii', 'replace')


def walk_nodes(blob, path=(), out=None):
    """Yield (path, props) for every node."""
    (magic, totalsize, off_struct, off_strings, *_r) = struct.unpack_from('>10I', blob, 0)
    if magic != FDT_MAGIC:
        raise ValueError(f'not an FDT (magic {magic:#x})')
    pos = off_struct
    cur = None
    stack = []
    while True:
        (token,) = struct.unpack_from('>I', blob, pos)
        pos += 4
        if token == BEGIN_NODE:
            nul = blob.index(b'\0', pos)
            name = blob[pos:nul].decode('ascii', 'replace')
            pos = (nul + 4) & ~3
            stack.append(name)
            cur = {}
            yield ('/'.join(stack), cur)
        elif token == END_NODE:
            stack.pop()
        elif token == PROP:
            (length, nameoff) = struct.unpack_from('>II', blob, pos)
            pos += 8
            data = blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
            name = get_string(blob, off_strings, nameoff)
            if cur is not None:
                cur[name] = data
        elif token in (NOP,):
            continue
        else:
            break


def s(data):
    if data and data[-1:] == b'\0' and all(32 <= b < 127 for b in data[:-1]):
        return data[:-1].decode('ascii')
    return None


def main():
    blob = open(sys.argv[1], 'rb').read()
    (magic, total, header_size, entry_size, entry_count, page_size, version) = struct.unpack_from('>7I', blob, 0)
    for i in range(entry_count):
        off = header_size + i * entry_size
        (dt_size, dt_offset, eid, rev, c0, c1, c2, c3) = struct.unpack_from('>8I', blob, off)
        sub = blob[dt_offset:dt_offset + dt_size]
        print(f'=== entry {i} (size {dt_size}, id {eid:#x}, rev {rev:#x}, custom {c0:#x},{c1:#x},{c2:#x},{c3:#x})')
        try:
            for path, props in walk_nodes(sub):
                tail = path.rsplit('/', 1)[-1]
                compat = s(props.get('compatible', b''))
                if 'qcom,board-id' in props or 'qcom,msm-id' in props:
                    print(f'  {tail}: board-id={props.get("qcom,board-id", b"").hex()} msm-id={props.get("qcom,msm-id", b"").hex()}')
                if compat and ('mdss_dsi' in compat and 'ctrl' not in tail) or tail.startswith('qcom,mdss_dsi_') or (compat and 'dsi_' in compat and 'panel' in str(props.get('qcom,mdss-dsi-panel-name', b''))):
                    name = s(props.get('qcom,mdss-dsi-panel-name', b'')) or compat
                    w = props.get('qcom,mdss-dsi-panel-width', b'')
                    h = props.get('qcom,mdss-dsi-panel-height', b'')
                    if w and h:
                        name += f' {struct.unpack(">I", w)[0]}x{struct.unpack(">I", h)[0]}'
                    print(f'  PANEL {tail}: {name}')
                if compat and ('goodix' in compat or 'novatek' in compat or 'focal' in compat or 'touchscreen' in tail):
                    print(f'  TOUCH {tail}: {compat} {dict((k, s(v) or v.hex()) for k, v in props.items() if k.startswith("goodix,") or k == "reg")}')
                if 'splash' in tail or (compat and 'splash' in compat):
                    print(f'  SPLASH {tail}: label={s(props.get("label", b""))} reg={props.get("reg", b"").hex()}')
                if tail.startswith('memory@') and 'reg' in props:
                    print(f'  MEM  {tail}: label={s(props.get("label", b""))} reg={props["reg"].hex()}')
        except ValueError as e:
            print(f'  (bad FDT: {e})')


if __name__ == '__main__':
    main()
