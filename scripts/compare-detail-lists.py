"""生成旧、新详情列表的截图对照和速度汇总，参数依次为旧目录、新目录、输出目录。"""

import argparse
import html
import json
import math
import os
import statistics
from pathlib import Path

from PIL import Image, ImageChops


def read(directory, name):
    return json.loads((directory / name).read_text())


def timings(directory):
    runs = read(directory, "page-timing.json")
    summary = {}
    for scenario in sorted({run["scenario"] for run in runs}):
        group = [run for run in runs if run["scenario"] == scenario]
        if len(group) != 20 or len({run["iteration"] for run in group}) != 20:
            raise ValueError(f"{scenario} 需要 20 次完整测量")
        metrics = {}
        for key in ("layoutMS", "visibleMS", "complexVisibleMS", "longestFrameMS"):
            values = sorted(run[key] for run in group if key in run)
            if values:
                if len(values) != len(group):
                    raise ValueError(f"{scenario} 缺少 {key}")
                p95 = values[math.ceil(0.95 * len(values)) - 1]
                metrics[key] = [round(statistics.median(values), 1), round(p95, 1)]
        metrics["peakMiB"] = round(max(run["peakSampledBytes"] for run in group) / 2**20, 1)
        summary[scenario] = metrics
    return summary


def composite(path, size, background):
    with Image.open(path) as source:
        image = source.convert("RGBA")
        canvas = Image.new("RGB", size, background)
        canvas.paste(image, (0, 0), image)
        return canvas


def different_percent(old, new, name):
    paths = [directory / (name + ".png") for directory in (old, new)]
    with Image.open(paths[0]) as left, Image.open(paths[1]) as right:
        size = max(left.width, right.width), max(left.height, right.height)
    background = "black" if "-dark-" in name else "white"
    images = [composite(path, size, background) for path in paths]
    red, green, blue = ImageChops.difference(*images).split()
    histogram = ImageChops.lighter(ImageChops.lighter(red, green), blue).histogram()
    return round(100 * sum(histogram[17:]) / (size[0] * size[1]), 2)


def gallery(floors, old, new, output):
    lines = ['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>详情楼层截图对照</title>',
             '<style>body{font:16px system-ui;margin:2rem}summary{padding:.45rem}section{display:flex;gap:1rem}'
             'img{display:block;max-width:44vw;height:auto}figure{margin:0}figcaption{padding:.5rem 0}</style>',
             '<h1>详情楼层截图对照</h1><p>按楼层高度差的绝对值排序。像素差为任一颜色通道相差超过 16 的像素比例。</p>']
    for floor in floors:
        name = floor["name"]
        lines.append(f'<details><summary>{html.escape(name)}　{floor["old"]:.1f} → {floor["new"]:.1f} pt'
                     f'　像素差 {floor["percent"]}%</summary><section>')
        for label, directory in (("Texture", old), ("TextKit", new)):
            path = html.escape(os.path.relpath(directory / (name + ".png"), output))
            lines.append(f'<figure><figcaption>{label}</figcaption><img loading="lazy" src="{path}"></figure>')
        lines.append("</section></details>")
    return "\n".join(lines) + "</html>\n"


def compare(old, new, output):
    heights = read(old, "floor-heights.json")
    measured = read(new, "floor-heights.json")
    if not heights or heights.keys() != measured.keys():
        raise ValueError("新旧楼层采样集合不一致或为空")
    floors = []
    for name, height in heights.items():
        floors.append(dict(name=name, old=height, new=measured[name], delta=round(measured[name] - height, 2),
                           percent=different_percent(old, new, name)))
    floors.sort(key=lambda row: (-abs(row["delta"]), row["name"]))
    ui = dict(pairs=len(floors), within1=sum(abs(row["new"] - row["old"]) <= 1 for row in floors),
              maxDelta=abs(floors[0]["delta"]))
    summary = dict(Texture=timings(old), TextKit=timings(new), UI=ui)
    output.mkdir(parents=True, exist_ok=True)
    for filename, data in (("summary.json", summary), ("floors.json", floors)):
        (output / filename).write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    (output / "index.html").write_text(gallery(floors, old, new, output))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("old", "new", "output"):
        parser.add_argument(argument, type=Path)
    args = parser.parse_args()
    compare(args.old, args.new, args.output)
