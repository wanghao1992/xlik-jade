#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从魔兽争霸3 MPQ 归档中查找/提取 .mdx 模型, 并可按 chunk 标签剥离(常用 CAMS)。

依赖: mpyq (纯 Python, 无 32/64 位限制)
    python -m pip install mpyq

示例:
    # 在全部 MPQ 中搜索名字含 Vengeance 的模型
    python extract_mdx.py find Vengeance

    # 查看某个模型的 chunk 列表(判断是否带 CAMS)
    python extract_mdx.py info "units\\nightelf\\Vengeance\\Vengeance.mdx"

    # 提取并剥离 CAMS, 输出到指定文件
    python extract_mdx.py get "units\\nightelf\\Vengeance\\Vengeance.mdx" --out Vengeance.mdx

    # 批量: jobs.txt 每行 "源路径|输出文件名"
    python extract_mdx.py batch jobs.txt --out-dir ../assets/war3mapModel/job
"""

import argparse
import os
import struct
import sys

# MPQ 读取优先级: 后面的归档会覆盖前面的同名文件
MPQ_FILES = ["war3.mpq", "War3xLocal.mpq", "War3x.mpq", "War3Patch.mpq"]

DEFAULT_DIRS = [
    os.environ.get("WAR3_DIR", ""),
    r"D:\Lua\war3 1.27\Warcraft III Frozen Throne",
    r"C:\Program Files (x86)\Warcraft III",
    r"C:\Program Files\Warcraft III",
]


def mpq_paths(mpq_dir):
    dirs = [mpq_dir] if mpq_dir else [d for d in DEFAULT_DIRS if d and os.path.isdir(d)]
    if not dirs:
        sys.exit("找不到魔兽安装目录, 请用 --mpq-dir 指定(目录下应有 war3.mpq)")
    paths = []
    for d in dirs:
        for name in MPQ_FILES:
            p = os.path.join(d, name)
            if os.path.isfile(p):
                paths.append(p)
    if not paths:
        sys.exit("目录下没有 MPQ 文件: " + ", ".join(dirs))
    return paths


def open_archives(mpq_dir):
    try:
        import mpyq
    except ImportError:
        sys.exit("缺少 mpyq, 请先执行: python -m pip install mpyq")
    archives = []
    for p in mpq_paths(mpq_dir):
        try:
            archives.append((p, mpyq.MPQArchive(p)))
        except Exception as err:  # 归档损坏/版本不识别时跳过, 不影响其它归档
            print(f"[跳过] {os.path.basename(p)}: {err}")
    if not archives:
        sys.exit("没有可读取的 MPQ 归档")
    return archives


def norm(path):
    """统一成小写 + 反斜杠, 便于在 listfile 中匹配。"""
    return str(path).replace("/", "\\").lower()


def files_of(archive):
    """listfile 的键在 mpyq 里可能是 bytes, 统一成 {规范化字符串: 原始键}。"""
    table = {}
    for f in (archive.files or []):
        if isinstance(f, bytes):
            text, raw = f.decode("utf-8", "ignore"), f
        else:
            text, raw = str(f), str(f).encode("utf-8")
        table[norm(text)] = raw
    return table


def read_file(archive, raw):
    try:
        return archive.read_file(raw)
    except Exception:
        return archive.read_file(raw.decode("utf-8"))


def find_model(archives, path):
    """按路径查找并读取, 返回 (归档名, 数据) ; 磁盘上已存在的文件优先直接读。"""
    if os.path.isfile(path):
        with open(path, "rb") as fp:
            return "<本地文件>", fp.read()
    key = norm(path)
    if not key.endswith((".mdx", ".mdl")):
        key += ".mdx"
    alt = key[:-4] + (".mdl" if key.endswith(".mdx") else ".mdx")
    for mpq, archive in archives:
        table = files_of(archive)
        for k in (key, alt):
            raw = table.get(k)
            if raw is None:
                continue
            data = read_file(archive, raw)
            if data:
                return os.path.basename(mpq), data
    return None, None


def parse_chunks(data):
    """解析 MDX chunk 序列: [('CAMS', size), ...]; 结构异常时最后一组标记为 False。"""
    if len(data) < 4 or data[:4] != b"MDLX":
        raise ValueError("不是 MDX 文件(缺少 MDLX 文件头)")
    pos, out = 4, []
    while pos + 8 <= len(data):
        tag = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        end = pos + 8 + size
        if end > len(data):
            out.append((tag.decode("latin-1"), size, False))
            break
        out.append((tag.decode("latin-1"), size, True))
        pos = end
    return out


def strip_chunk(data, tag):
    """删除指定 tag 的 chunk(tag+size+data 整体移除), 其余字节保持原样。"""
    tag = tag.encode("latin-1")[:4].ljust(4, b" ")
    if data[:4] != b"MDLX":
        raise ValueError("不是 MDX 文件(缺少 MDLX 文件头)")
    out = bytearray(data[:4])
    pos, removed = 4, 0
    while pos + 8 <= len(data):
        cur = data[pos:pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        end = pos + 8 + size
        if end > len(data):
            out += data[pos:]  # 尾部结构异常, 原样保留
            break
        if cur != tag:
            out += data[pos:end]
        else:
            removed += 1
        pos = end
    return bytes(out), removed


def describe(data):
    tags = parse_chunks(data)
    names = [t for t, _, _ in tags]
    return {
        "size": len(data),
        "cams": "CAMS" in names,
        "tags": names,
    }


def cmd_find(args):
    archives = open_archives(args.mpq_dir)
    keyword = args.keyword.lower()
    hits = 0
    for path, archive in archives:
        for key in sorted(files_of(archive)):
            if not key.endswith((".mdx", ".mdl")):
                continue
            if keyword in key:
                hits += 1
                print(f"{os.path.basename(path):16} {key}")
                if args.detail:
                    _, data = find_model([(path, archive)], key)
                    if data:
                        info = describe(data)
                        print(f"{'':16} size={info['size']} CAMS={info['cams']}")
    print(f"-- 共 {hits} 条")


def cmd_info(args):
    archives = [] if os.path.isfile(args.path) else open_archives(args.mpq_dir)
    mpq, data = find_model(archives, args.path)
    if data is None:
        sys.exit("未找到: " + args.path)
    info = describe(data)
    print(f"归档: {mpq}")
    print(f"大小: {info['size']} 字节, CAMS: {info['cams']}")
    for tag, size, ok in parse_chunks(data):
        print(f"  {tag} {size}{'' if ok else '  <结构异常>'}")


def cmd_get(args):
    archives = [] if os.path.isfile(args.path) else open_archives(args.mpq_dir)
    mpq, data = find_model(archives, args.path)
    if data is None:
        sys.exit("未找到: " + args.path)
    removed = 0
    if args.strip:
        data, removed = strip_chunk(data, args.strip)
    out = args.out or os.path.basename(args.path).replace(".mdl", ".mdx")
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "wb") as fp:
        fp.write(data)
    print(f"来源: {mpq}")
    print(f"剥离: {args.strip or '-'} x{removed}")
    print(f"输出: {os.path.abspath(out)} ({len(data)} 字节)")


def cmd_batch(args):
    archives = open_archives(args.mpq_dir)
    with open(args.jobs, encoding="utf-8-sig") as fp:
        lines = [ln.strip() for ln in fp if ln.strip() and not ln.strip().startswith("#")]
    os.makedirs(args.out_dir, exist_ok=True)
    ok = fail = 0
    for line in lines:
        parts = [p.strip() for p in line.split("|")]
        src = parts[0]
        name = parts[1] if len(parts) > 1 else os.path.basename(src).replace(".mdl", ".mdx")
        mpq, data = find_model(archives, src)
        if data is None:
            print(f"[缺失] {src}")
            fail += 1
            continue
        removed = 0
        if args.strip:
            data, removed = strip_chunk(data, args.strip)
        dst = os.path.join(args.out_dir, name)
        with open(dst, "wb") as fp:
            fp.write(data)
        print(f"[OK] {name:44} {len(data):>8} 字节  剥离{args.strip or '-'}x{removed}  ({mpq})")
        ok += 1
    print(f"-- 成功 {ok}, 缺失 {fail}")


def main():
    parser = argparse.ArgumentParser(description="魔兽争霸3 MPQ 模型提取 / CAMS 剥离")
    parser.add_argument("--mpq-dir", help="魔兽安装目录(含 war3.mpq); 缺省自动探测")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("find", help="按关键字搜索模型路径")
    p.add_argument("keyword")
    p.add_argument("--detail", action="store_true", help="读取并显示大小/CAMS")
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("info", help="查看模型 chunk 列表")
    p.add_argument("path")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("get", help="提取单个模型")
    p.add_argument("path")
    p.add_argument("--out", help="输出文件路径")
    p.add_argument("--strip", default="CAMS", help="要剥离的 chunk 标签(默认 CAMS, 传空串则不剥离)")
    p.set_defaults(func=cmd_get)

    p = sub.add_parser("batch", help="按 jobs 文件批量提取")
    p.add_argument("jobs", help="每行 源路径|输出文件名")
    p.add_argument("--out-dir", required=True)
    p.add_argument("--strip", default="CAMS")
    p.set_defaults(func=cmd_batch)

    args = parser.parse_args()
    if not getattr(args, "strip", None):
        args.strip = None
    args.func(args)


if __name__ == "__main__":
    main()
