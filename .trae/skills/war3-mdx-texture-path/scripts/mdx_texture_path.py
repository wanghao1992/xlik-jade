#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""MDX/MDL 贴图路径编辑器: 列出 / 改写 / 批量替换贴图路径, 并校验结构.

- 二进制 mdx: 'MDLX' 头 + [tag(4) + size(u32) + data], TEXS 每条 268 字节
  (replaceableId(u32) + path[260] + flags(u32))
- 文本 mdl: `Bitmap { ... Image "<path>", ... }`, 只替换 Image 引号内的路径, 其余字节不动

子命令:
  list     列出贴图路径(mdx 同时列出 chunk 链)
  set      单文件改一条(按槽位号/旧文件名, * 表示全部)
  replace  批量替换: 把所有匹配旧名的条目改成新路径
  localize 统一改为 war3mapTextures\\<同名> 相对路径(需贴图目录内存在)
"""
import argparse
import os
import re
import struct
import sys

TEXS_ENTRY = 268
PATH_LEN = 260
MDL_RE = re.compile(rb'(?<=")([^"\r\n]+)(?=")')


def load(path):
    with open(path, 'rb') as f:
        raw = bytearray(f.read())
    return raw, raw[:4] == b'MDLX'


def chunks(d):
    assert d[:4] == b'MDLX', '不是 MDX: %s' % bytes(d[0:4])
    pos, out = 4, []
    while pos < len(d):
        if pos + 8 > len(d):
            raise SystemExit('chunk 头越界 @0x%04X' % pos)
        tag = d[pos:pos + 4].decode('ascii', 'replace')
        size = struct.unpack_from('<I', d, pos + 4)[0]
        data = pos + 8
        if data + size > len(d):
            raise SystemExit('chunk %s 长度越界 @0x%04X size=%d' % (tag, pos, size))
        out.append((tag, pos, data, size))
        pos = data + size
    if pos != len(d):
        raise SystemExit('chunk 链末尾不齐: pos=0x%04X len=0x%04X' % (pos, len(d)))
    return out


def entries(d, is_mdx):
    """返回 [(idx, replaceableId, path, write_span_start, write_span_end)]
    写回时: mdx 用 (offset, 260 字节整段); mdl 用 (start, end) 只换引号内容."""
    res = []
    if is_mdx:
        for tag, _pos, data, size in chunks(d):
            if tag != 'TEXS':
                continue
            for i in range(size // TEXS_ENTRY):
                p = data + i * TEXS_ENTRY
                rid = struct.unpack_from('<I', d, p)[0]
                raw = bytes(d[p + 4:p + 4 + PATH_LEN])
                name = raw.split(b'\x00')[0].decode('utf-8', 'replace')
                res.append((i, rid, name, p + 4, p + 4 + PATH_LEN))
        return res
    # 文本 MDL: 只看 Bitmap 块里的 Image 行
    for m in re.finditer(rb'Image[ \t]+"([^"\r\n]*)"', d):
        res.append((len(res), 0, m.group(1).decode('utf-8', 'replace'), m.start(1), m.end(1)))
    return res


def base_of(name):
    return os.path.basename(name.replace('\\', '/'))


def write_entry(d, start, end, text, is_mdx):
    raw = text.encode('utf-8')
    if is_mdx:
        if len(raw) > PATH_LEN - 1:
            raise SystemExit('路径过长(%d 字节, 上限 %d): %s' % (len(raw), PATH_LEN - 1, text))
        d[start:end] = raw + b'\x00' * (PATH_LEN - len(raw))
    else:
        d[start:end] = raw


def save(path, raw):
    with open(path, 'wb') as f:
        f.write(raw)


def show(path, raw, is_mdx, prefix='== '):
    print('%s%s (%d 字节, %s)' % (prefix, path, len(raw), 'mdx' if is_mdx else 'mdl'))
    if is_mdx:
        print('   chunks: ' + ' '.join(t for t, *_ in chunks(raw)))
    for i, rid, name, _s, _e in entries(raw, is_mdx):
        tag = '' if is_mdx else ' Image'
        print('   [%d]%s%s replaceableId=%d path=%s' % (
            i, tag, '', rid, name) if is_mdx else '   [%d]%s path=%s' % (i, tag, name))


def cmd_list(args):
    for path in args.files:
        raw, is_mdx = load(path)
        show(path, raw, is_mdx)


def cmd_set(args):
    path = args.file
    raw, is_mdx = load(path)
    ents = entries(raw, is_mdx)
    if not ents:
        raise SystemExit('该模型没有贴图条目')
    if args.slot == '*':
        rewrite_all(raw, [(s, e, args.text) for _i, _r, _n, s, e in ents], is_mdx)
        print('已改写全部 %d 条贴图路径 -> %s' % (len(ents), args.text))
    else:
        hit = [x for x in ents if str(x[0]) == args.slot or base_of(x[2]) == args.slot]
        if not hit:
            raise SystemExit('找不到槽位/贴图名: %s (现有: %s)' % (
                args.slot, ', '.join('%d:%s' % (i, n) for i, _r, n, _s, _e in ents)))
        rewrite_all(raw, [(s, e, args.text) for _i, _r, _o, s, e in hit], is_mdx)
        for i, _rid, old, _s, _e in hit:
            print('   [%d] %s -> %s' % (i, old, args.text))
    if args.dry_run:
        print('(dry-run, 未写入)')
        return
    save(path, raw)
    raw, is_mdx = load(path)
    show(path, raw, is_mdx, '   已保存 ')


def cmd_replace(args):
    total = 0
    for path in args.files:
        raw, is_mdx = load(path)
        hit, edits = [], []
        for i, rid, name, s, e in entries(raw, is_mdx):
            if rid != 0 or (base_of(name) != args.old and name != args.old):
                continue
            hit.append((i, name))
            edits.append((s, e, args.text))
        rewrite_all(raw, edits, is_mdx)
        if not hit:
            print('   跳过 ' + path + ' (没有匹配 ' + args.old + ')')
            continue
        print('== ' + path)
        for i, old in hit:
            print('   [%d] %s -> %s' % (i, old, args.text))
        total += len(hit)
        if not args.dry_run:
            save(path, raw)
    print('共替换 %d 条%s' % (total, '' if not args.dry_run else ' (dry-run, 未写入)'))


def rewrite_all(d, edits, is_mdx):
    """按 (start, end, text) 批量写入.
    文本 mdl 的长度会变, 后面的偏移会失效, 所以从后往前写."""
    for start, end, text in sorted(edits, key=lambda x: x[0], reverse=True):
        write_entry(d, start, end, text, is_mdx)


def localize(raw, is_mdx, assets):
    changes, edits = [], []
    for i, rid, name, s, e in entries(raw, is_mdx):
        base = base_of(name)
        if not base:
            changes.append((i, name, None, '空路径'))
            continue
        if rid != 0:
            changes.append((i, name, None, 'replaceableId=%d(内置替换贴图), 保留' % rid))
            continue
        target = 'war3mapTextures\\' + base
        if not os.path.isfile(os.path.join(assets, base)):
            changes.append((i, name, None, '贴图目录内不存在 %s' % base))
            continue
        if name == target:
            changes.append((i, name, target, '已是目标路径'))
            continue
        edits.append((s, e, target))
        changes.append((i, name, target, '改写'))
    rewrite_all(raw, edits, is_mdx)
    return changes


def cmd_localize(args):
    for path in args.files:
        raw, is_mdx = load(path)
        print('== ' + path)
        for i, old, new, why in localize(raw, is_mdx, args.assets):
            if new is None:
                print('   [%d] 跳过 %s (%s)' % (i, old, why))
            else:
                print('   [%d] %s -> %s (%s)' % (i, old, new, why))
        if args.dry_run:
            print('   (dry-run, 未写入)')
        else:
            save(path, raw)


def main():
    ap = argparse.ArgumentParser(description='MDX/MDL 贴图路径编辑器')
    sub = ap.add_subparsers(dest='cmd', required=True)

    p1 = sub.add_parser('list', help='列出贴图路径(mdx 同时列出 chunk 链)')
    p1.add_argument('files', nargs='+')
    p1.set_defaults(func=cmd_list)

    p2 = sub.add_parser('set', help='单文件改写一条(槽位号/旧文件名/*)')
    p2.add_argument('file')
    p2.add_argument('slot', help='槽位号(0,1,...) 或旧文件名, * 表示全部')
    p2.add_argument('text', help='新路径, 如 war3mapTextures\\\\Shockwave.blp')
    p2.add_argument('--dry-run', action='store_true')
    p2.set_defaults(func=cmd_set)

    p3 = sub.add_parser('replace', help='批量把所有匹配旧名的条目改成新路径')
    p3.add_argument('old', help='旧文件名(或完整旧路径)')
    p3.add_argument('text', help='新路径')
    p3.add_argument('files', nargs='+')
    p3.add_argument('--dry-run', action='store_true')
    p3.set_defaults(func=cmd_replace)

    p4 = sub.add_parser('localize', help='统一改为 war3mapTextures\\\\<同名> 相对路径')
    p4.add_argument('files', nargs='+')
    p4.add_argument('--assets', default=os.path.join('vendor', 'assets', 'war3mapTextures'))
    p4.add_argument('--dry-run', action='store_true')
    p4.set_defaults(func=cmd_localize)

    args = ap.parse_args()
    args.func(args)


if __name__ == '__main__':
    sys.exit(main())
