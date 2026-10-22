#!/usr/bin/env python3
"""把几张帖子列表截图里挑出的行，按原样拼成一张列表截图。

首页列表是实时内容，一屏里难免混进不适合放商店的帖子。这里只挑内容干净的行，
每行都是 App 真实渲染的画面，不改动行内像素。

用法：
    python3 tools/appstore-screenshots/stitch_list.py --header home.png --out stitched.png \\
        home.png:0 tech-1.png:1 tech-2.png:5
先用 --list 查看每张图的行号和纵向范围：
    python3 tools/appstore-screenshots/stitch_list.py --list home.png tech-1.png
--header 那张图保留到第一条分隔线（状态栏、分区栏和第一行帖子），后面依次接上选中的行。
行号只计算顶部完整露出的行（分隔线在 --top 以下）。
"""

import argparse
from pathlib import Path

from PIL import Image

# 分区栏下沿：iPhone 17 Pro Max 为 300px，iPad Pro 13" 见调用方传入
DEFAULT_TOP = 300


def separators(im: Image.Image, x0=20, x1=1000):
    """列表行之间的分隔线：一段横跨整行、颜色一致的浅灰像素。"""
    px = im.load()
    _, height = im.size
    runs = []
    for y in range(height):
        color = px[x0, y]
        if color == (255, 255, 255) or sum(color) <= 600:
            continue
        if all(px[x, y] == color for x in range(x0, x1, 37)):
            if runs and y - runs[-1][1] <= 1:
                runs[-1][1] = y
            else:
                runs.append([y, y])
    return runs


def cells(im: Image.Image, top: int):
    seps = separators(im)
    return [(seps[i][1] + 1, seps[i + 1][1] + 1) for i in range(len(seps) - 1) if seps[i][0] >= top]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", nargs="+", type=Path, help="列出每张图的行号和纵向范围")
    parser.add_argument("--header", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--top", type=int, default=DEFAULT_TOP)
    parser.add_argument("picks", nargs="*", help="图片:行号")
    args = parser.parse_args()

    if args.list:
        for path in args.list:
            im = Image.open(path).convert("RGB")
            print(path.name, [(i, a, b) for i, (a, b) in enumerate(cells(im, args.top))])
        return

    header = Image.open(args.header).convert("RGB")
    width, height = header.size
    first_sep = next(s for s in separators(header) if s[0] >= args.top)
    canvas = Image.new("RGB", (width, height), (255, 255, 255))
    canvas.paste(header.crop((0, 0, width, first_sep[1] + 1)), (0, 0))
    y = first_sep[1] + 1

    for pick in args.picks:
        name, index = pick.rsplit(":", 1)
        im = Image.open(name).convert("RGB")
        top, bottom = cells(im, args.top)[int(index)]
        cell = im.crop((0, top, width, bottom))
        # 滚动中截的图右侧带滚动条，用同一行左边一点的颜色抹平
        px = cell.load()
        for row in range(cell.height):
            color = px[width - 24, row]
            for x in range(width - 20, width):
                px[x, row] = color
        canvas.paste(cell, (0, y))
        y += bottom - top
        if y >= height:
            break

    canvas.save(args.out)
    print(f"✓ {args.out}（内容高度 {min(y, height)}/{height}）")


if __name__ == "__main__":
    main()
