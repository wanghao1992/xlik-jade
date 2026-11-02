"""把生成的原始画作处理成 128x128 的 32 位 TGA.

用法:
  python make_tga.py --src <raw 目录> --dst <tga 目录> --prefix card --names <名字清单.txt>
                     [--size 128] [--keep-height 0.85] [--sheet <预览图.png>]

约定:
  raw 目录里第 i 张叫 <prefix>_01.jpg / .png / .webp, 与 names 第 i 行一一对应.
  默认裁掉底部 15%(生成工具水印), 居中裁正方形, LANCZOS 缩放到 --size, 保存为 32 位 TGA.
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw

RAW_EXTS = ('.jpg', '.jpeg', '.png', '.webp')


def find_raw(src_dir, prefix, idx):
    for ext in RAW_EXTS:
        p = os.path.join(src_dir, '%s_%02d%s' % (prefix, idx, ext))
        if os.path.exists(p):
            return p
    return None


def to_square_tga(src, dst, size, keep_height):
    im = Image.open(src).convert('RGB')
    w, h = im.size
    keep_h = int(h * keep_height)
    left = (w - keep_h) // 2
    im = im.crop((left, 0, left + keep_h, keep_h))
    im = im.resize((size, size), Image.LANCZOS).convert('RGBA')
    im.save(dst, format='TGA')
    return im


def build_sheet(names, out_dir, path, size):
    cell, cols = size, 7
    rows = (len(names) + cols - 1) // cols
    canvas = Image.new('RGB', (cols * cell, rows * (cell + 14)), (20, 24, 32))
    draw = ImageDraw.Draw(canvas)
    for i, name in enumerate(names):
        x, y = (i % cols) * cell, (i // cols) * (cell + 14)
        tga = os.path.join(out_dir, name + '.tga')
        if os.path.exists(tga):
            canvas.paste(Image.open(tga).convert('RGB'), (x, y))
        draw.text((x + 2, y + cell + 1), '%02d' % (i + 1), fill=(220, 220, 220))
    canvas.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--dst', required=True)
    ap.add_argument('--prefix', required=True)
    ap.add_argument('--names', required=True, help='UTF-8 文本, 一行一个名字')
    ap.add_argument('--size', type=int, default=128)
    ap.add_argument('--keep-height', type=float, default=0.85)
    ap.add_argument('--sheet')
    args = ap.parse_args()

    with open(args.names, encoding='utf-8-sig') as fp:
        names = [x.strip() for x in fp if x.strip()]
    os.makedirs(args.dst, exist_ok=True)

    missing = []
    for i, name in enumerate(names, 1):
        raw = find_raw(args.src, args.prefix, i)
        if raw is None:
            missing.append('%s_%02d' % (args.prefix, i))
            continue
        to_square_tga(raw, os.path.join(args.dst, name + '.tga'), args.size, args.keep_height)

    print('生成 %d 张, 缺失 %d 张' % (len(names) - len(missing), len(missing)))
    if missing:
        print('缺失:', ', '.join(missing))
    if args.sheet:
        build_sheet(names, args.dst, args.sheet, args.size)
        print('预览图:', args.sheet)
    files = glob.glob(os.path.join(args.dst, '*.tga'))
    print('目录现有 TGA %d 个, 合计 %.2f MB' % (len(files), sum(os.path.getsize(f) for f in files) / 1048576))


if __name__ == '__main__':
    main()
