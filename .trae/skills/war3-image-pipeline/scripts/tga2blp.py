"""把 32 位 TGA 压成 BLP1 调色板贴图(尺寸不变), 并回读自检.

用法:
  python tga2blp.py --src <tga 目录> --dst <blp 目录> [--colors 256] [--no-verify]

产出: BLP1 / compression=1(调色板) / 256 色 BGRA / mip 128·64·32·16·8
单张 128x128 = 23004 B, 约为 32 位 TGA(65580 B) 的三分之一.
"""
import argparse
import glob
import math
import os
import struct

from PIL import Image

MIP_MIN = 8
HEADER_SIZE = 156
PALETTE_SIZE = 1024


def build_blp(src, dst, colors):
    im = Image.open(src).convert('RGBA')
    w, h = im.size
    if w != h:
        raise ValueError('只支持正方形图: %s %dx%d' % (src, w, h))
    alpha = im.getchannel('A').getextrema()
    rgb = im.convert('RGB')
    master = rgb.quantize(colors=colors, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)

    mips, size = [], w
    while size >= MIP_MIN:
        frame = master if size == w else rgb.resize((size, size), Image.LANCZOS).quantize(
            palette=master, dither=Image.FLOYDSTEINBERG)
        mips.append(bytes(frame.tobytes()))
        size //= 2

    pal = master.getpalette()[:colors * 3]
    pal += [0] * (256 * 3 - len(pal))
    palette = bytearray()
    for i in range(256):
        r, g, b = pal[i * 3], pal[i * 3 + 1], pal[i * 3 + 2]
        # 原图不透明时写 255, 避免部分工具把 0 当成全透明
        a = 255 if alpha[1] > 0 else 0
        palette += bytes((b, g, r, a))

    header = struct.pack('<4sIIIII', b'BLP1', 1, 0, w, h, 5) + struct.pack('<I', 1)
    offsets, sizes, cur = [], [], HEADER_SIZE + PALETTE_SIZE
    for m in mips:
        offsets.append(cur)
        sizes.append(len(m))
        cur += len(m)
    header += struct.pack('<16I', *(offsets + [0] * (16 - len(offsets))))
    header += struct.pack('<16I', *(sizes + [0] * (16 - len(sizes))))

    with open(dst, 'wb') as fp:
        fp.write(header)
        fp.write(palette)
        for m in mips:
            fp.write(m)


def decode_blp(path):
    d = open(path, 'rb').read()
    magic, comp, _flags, w, h = struct.unpack('<4sIIII', d[:20])
    if magic != b'BLP1' or comp != 1:
        raise ValueError('不是调色板 BLP1: %s' % path)
    offs = struct.unpack('<16I', d[28:92])
    sizes = struct.unpack('<16I', d[92:156])
    pal = [struct.unpack('<BBBB', d[HEADER_SIZE + i * 4:HEADER_SIZE + i * 4 + 4])[:3][::-1] for i in range(256)]
    mip = d[offs[0]:offs[0] + sizes[0]]
    im = Image.new('RGB', (w, h))
    im.putdata([pal[mip[i]] for i in range(w * h)])
    return im


def verify(src, dst):
    a = Image.open(src).convert('RGB').tobytes()
    b = decode_blp(dst).tobytes()
    se = sum((x - y) ** 2 for x, y in zip(a, b))
    mse = se / max(1, len(a))
    psnr = 10 * math.log10(255 * 255 / max(mse, 1e-9))
    return psnr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--dst', required=True)
    ap.add_argument('--colors', type=int, default=256)
    ap.add_argument('--no-verify', action='store_true')
    args = ap.parse_args()

    os.makedirs(args.dst, exist_ok=True)
    files = sorted(glob.glob(os.path.join(args.src, '*.tga')))
    total_in = total_out = 0
    low = []
    for f in files:
        dst = os.path.join(args.dst, os.path.splitext(os.path.basename(f))[0] + '.blp')
        total_in += os.path.getsize(f)
        build_blp(f, dst, args.colors)
        total_out += os.path.getsize(dst)
        if not args.no_verify:
            psnr = verify(f, dst)
            if psnr < 30:
                low.append((os.path.basename(f), psnr))

    print('%d 张: %.2f MB -> %.2f MB (单张 %.0f B)' % (
        len(files), total_in / 1048576, total_out / 1048576, total_out / max(1, len(files))))
    if low:
        print('PSNR 偏低(需人工确认):', ', '.join('%s %.1fdB' % x for x in low))
    else:
        print('校验通过: 全部 PSNR >= 30dB')


if __name__ == '__main__':
    main()
