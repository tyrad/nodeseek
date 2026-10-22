#!/usr/bin/env python3
"""合成 App Store 截图：打码模拟器原图，套标题和机身，输出商店要求尺寸的 JPG。

用法（在仓库根目录）：
    python3 tools/appstore-screenshots/compose.py --device iphone --locale zh-Hans --out fastlane/screenshots/zh-Hans
    python3 tools/appstore-screenshots/compose.py --device ipad --locale zh-Hant --out fastlane/screenshots/zh-Hant --raw <原图目录>

设备：iphone 用 iPhone 17 Pro Max 模拟器原图（1320×2868），输出 1290×2796；
      ipad 用 iPad Pro 13-inch (M5) 模拟器原图（2064×2752），输出 2064×2752，文件名带 ipad- 前缀。
<原图目录> 需包含 home.png、detail.png、nq.png、dark.png。home.png 一般是 stitch_list.py 拼出的列表。
首页按分隔线自动给每行的头像和用户名打码；其余页面的打码区域按这批原图手工标定，
重拍后位置会变，需要同步调整 BLUR_BOXES。不传 --raw 时直接用 raw/<设备>/ 里已打码的图。
App 界面只有简体中文，繁体版只换截图上的文案。
"""

import argparse
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageFilter

from stitch_list import separators

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# 帖子列表的行内布局：分区栏下沿、头像相对行顶的区域、用户名起始 x、用户名和浏览数图标之间的最小空隙
LIST_LAYOUT = {
    "iphone": {"top": 300, "avatar": (40, 20, 210, 172), "text_x": 222, "gap": 20},
    "ipad": {"top": 139, "avatar": (26, 13, 134, 117), "text_x": 146, "gap": 14},
}

# 头像和用户名，坐标基于各设备原图
BLUR_BOXES = {
    "iphone": {
        "detail": [(560, 210, 760, 295)],
        "nq": [(42, 596, 172, 722), (190, 626, 418, 690)],
        "dark": [(560, 210, 760, 295)],
    },
    "ipad": {
        "detail": [(960, 75, 1110, 135)],
        "nq": [(28, 286, 116, 370), (126, 300, 276, 354)],
        "dark": [(960, 75, 1110, 135)],
    },
}

# 页面按 CSS 像素排版，再按倍率截图得到商店尺寸
DEVICES = {
    "iphone": {"size": (430, 932), "scale": 3, "prefix": ""},
    "ipad": {"size": (1032, 1376), "scale": 2, "prefix": "ipad-"},
}


def name_line(im, top, bottom, text_x, gap):
    """一行帖子里最下面一行文字就是用户名那一行；用户名到浏览数图标之间有一段空白。"""
    px = im.load()

    def inked(x, y):
        return sum(px[x, y]) < 690

    band_bottom = next((y for y in range(bottom - 2, top, -1)
                        if any(inked(x, y) for x in range(text_x, text_x + 500, 2))), None)
    if band_bottom is None:
        return None
    band_top = band_bottom
    while band_top > top and any(inked(x, band_top - 1) for x in range(text_x, text_x + 500, 2)):
        band_top -= 1
    x_end, blank = text_x, 0
    for x in range(text_x, text_x + 800):
        if any(inked(x, y) for y in range(band_top, band_bottom + 1)):
            x_end, blank = x, 0
        elif x_end > text_x:
            blank += 1
            if blank >= gap:
                break
    return (text_x - 8, band_top - 8, x_end + 10, band_bottom + 8)


def list_boxes(im, device):
    layout = LIST_LAYOUT[device]
    width, height = im.size
    seps = [s for s in separators(im) if s[0] >= layout["top"]]
    tops = [layout["top"]] + [s[1] + 1 for s in seps]
    bottoms = [s[0] for s in seps] + [height]
    ax0, ay0, ax1, ay1 = layout["avatar"]
    boxes = []
    for top, bottom in zip(tops, bottoms):
        if bottom - top < ay1 - ay0:
            continue
        boxes.append((ax0, top + ay0, ax1, min(top + ay1, bottom)))
        name = name_line(im, top, bottom, layout["text_x"], layout["gap"])
        if name:
            boxes.append(name)
    return boxes


def pixelate(src: Path, dst: Path, boxes):
    im = Image.open(src).convert("RGB")
    if callable(boxes):
        boxes = boxes(im)
    for box in boxes:
        region = im.crop(box)
        w, h = region.size
        region = region.resize((max(1, w // 12), max(1, h // 12)), Image.BILINEAR)
        region = region.resize((w, h), Image.NEAREST).filter(ImageFilter.GaussianBlur(4))
        im.paste(region, box[:2])
    im.save(dst, quality=92)


def chicken_leg_path():
    svg = (REPO / "nodeseek/Resources/Assets.xcassets/ChickenLeg.symbolset/ChickenLeg.svg").read_text()
    group = svg[svg.index('id="Regular-M"'):]
    return re.search(r'<path d="([^"]+)"', group).group(1)


ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">{}</svg>'
ICONS = {
    "checkin": f'<svg viewBox="-52 -88 102 102"><path fill="currentColor" d="{chicken_leg_path()}"/></svg>',
    "follow": ICON.format('<path d="M12 3l2.6 5.6 6 .7-4.5 4.1 1.2 6L12 16.4 6.7 19.4l1.2-6L3.4 9.3l6-.7z"/>'),
    "sort": ICON.format('<path d="M7 4v16M3 8l4-4 4 4M17 20V4M13 16l4 4 4-4"/>'),
    "font": ICON.format('<path d="M3 19l5-14 5 14M5 14h6M15 19v-6.5a3 3 0 0 1 6 0V19M15 15.5h6"/>'),
    "image": ICON.format('<rect x="3" y="4" width="18" height="16" rx="3"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/>'),
    "sticker": ICON.format('<circle cx="12" cy="12" r="9"/><path d="M8.5 14.5a4 4 0 0 0 7 0"/><path d="M9 9.5h.01M15 9.5h.01"/>'),
    "recent": ICON.format('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    "code": ICON.format('<path d="M8 7l-5 5 5 5M16 7l5 5-5 5M14 4l-4 16"/>'),
}

COPY = {
    "zh-Hans": {
        "cards": [
            ("MJJ 的<em>口袋论坛</em><br>刷 NS 更顺手", "开源客户端，分区一滑就切"),
            ("长帖也不卡<br>代码表格<em>都好看</em>", "原生渲染，几百楼回复也一滑到底"),
            ("NQ 测评报告<br>手机上<em>也看得清</em>", "基本信息 · IP 质量 · 网络 · 回程分页看"),
            ("有人回你<br>锁屏<em>秒知道</em>", "配合自部署 ns-apns，推送不经第三方"),
            ("小细节<br>都<em>替你想到了</em>", "签到、关注、传图，顺手的事都包了"),
            ("深夜刷帖<br>深色<em>不刺眼</em>", "跟随系统外观，字号随心调"),
        ],
        "features": [
            ("checkin", "自动签到", "鸡腿每天不断签"),
            ("follow", "特别关注", "关键词彩色高亮"),
            ("sort", "分区排序", "常逛的放前面"),
            ("font", "字号调节", "实时预览"),
            ("image", "NodeImage", "回帖一键传图"),
            ("sticker", "表情贴纸", "社区表情全都有"),
            ("recent", "最近浏览", "看过的随时找回"),
            ("code", "开源透明", "代码全公开"),
        ],
        "notifications": [
            ("现在", "新回复", "有人在「Debian 13 升级踩坑记录」里回复了你"),
            ("3 分钟前", "有人 @ 了你", "「这个 Docker 配置可以参考一下」"),
            ("12 分钟前", "新私信", "谢谢你的教程，已经跑起来了"),
        ],
    },
    "zh-Hant": {
        "cards": [
            ("MJJ 的<em>口袋論壇</em><br>刷 NS 更順手", "開源客戶端，分區一滑就切"),
            ("長帖也不卡<br>程式碼表格<em>都好看</em>", "原生渲染，幾百樓回覆也一滑到底"),
            ("NQ 測評報告<br>手機上<em>也看得清</em>", "基本資訊 · IP 品質 · 網路 · 回程分頁看"),
            ("有人回你<br>鎖屏<em>秒知道</em>", "配合自架 ns-apns，推播不經第三方"),
            ("小細節<br>都<em>替你想到了</em>", "簽到、關注、傳圖，順手的事都包了"),
            ("深夜刷帖<br>深色<em>不刺眼</em>", "跟隨系統外觀，字級隨心調"),
        ],
        "features": [
            ("checkin", "自動簽到", "雞腿每天不斷簽"),
            ("follow", "特別關注", "關鍵字彩色標示"),
            ("sort", "分區排序", "常逛的放前面"),
            ("font", "字級調整", "即時預覽"),
            ("image", "NodeImage", "回帖一鍵傳圖"),
            ("sticker", "表情貼紙", "社群表情全都有"),
            ("recent", "最近瀏覽", "看過的隨時找回"),
            ("code", "開源透明", "程式碼全公開"),
        ],
        "notifications": [
            ("現在", "新回覆", "有人在「Debian 13 升級踩坑記錄」裡回覆了你"),
            ("3 分鐘前", "有人 @ 了你", "「這個 Docker 設定可以參考一下」"),
            ("12 分鐘前", "新私訊", "謝謝你的教學，已經跑起來了"),
        ],
    },
}

CSS = """
*{box-sizing:border-box}
html,body{margin:0;width:var(--w);height:var(--h);overflow:hidden}
body{font-family:-apple-system,"PingFang SC","PingFang TC",sans-serif}
.card{width:var(--w);height:var(--h);position:relative;display:flex;flex-direction:column;align-items:center;background:#f6f7f8;color:#1a1f24}
.card.dark{background:#1a1f24;color:#f2f4f5}
.card::after{content:"";position:absolute;left:40px;top:44px;width:36px;height:6px;border-radius:3px;background:#14b8a6;transform:skewX(-25deg)}
.t{margin-top:64px;font-size:40px;font-weight:800;letter-spacing:1px;text-align:center;line-height:1.25}
.t em{font-style:normal;color:#14b8a6}
.s{margin-top:12px;font-size:20px;opacity:.75;text-align:center}
.phone{position:absolute;top:250px;width:340px;height:740px;border-radius:52px;border:10px solid #111;background:#111;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.25)}
.phone::before{content:"";position:absolute;top:8px;left:50%;transform:translateX(-50%);width:92px;height:27px;border-radius:14px;background:#000;z-index:1}
.card.dark .phone{border-color:#3a4048;box-shadow:0 20px 50px rgba(0,0,0,.5)}
.phone img{width:100%;display:block}
.lock{background:linear-gradient(180deg,#22313f,#0f1419);height:100%;display:flex;flex-direction:column;align-items:center;color:#fff}
.lock .clk{margin-top:70px;font-size:84px;font-weight:600;letter-spacing:-2px}
.lock .dt{font-size:17px;opacity:.8;margin-top:4px}
.nt{width:290px;margin-top:14px;background:rgba(255,255,255,.18);border-radius:20px;padding:12px 14px;display:flex;gap:10px;font-size:14px;line-height:1.35}
.nt:first-of-type{margin-top:150px}
.nt .ic{width:36px;height:36px;border-radius:9px;background:#fff;flex:none;display:flex;align-items:center;justify-content:center;font-weight:900;color:#1a1f24;font-size:15px}
.nt b{display:block}
.nt .tm{float:right;opacity:.6;font-size:12px}
.grid{position:absolute;top:240px;left:28px;right:28px;display:grid;grid-template-columns:1fr 1fr;gap:14px}
.f{background:#fff;border-radius:20px;padding:18px 16px;box-shadow:0 2px 10px rgba(0,0,0,.05)}
.f .e{width:32px;height:32px;color:#14b8a6}
.f .e svg{width:100%;height:100%}
.f b{display:block;font-size:19px;margin-top:10px;color:#1a1f24}
.f span{font-size:14px;color:#6b7280}
.f.hl{background:#1a1f24}
.f.hl b{color:#fff}
.f.hl span{color:#9ca3af}
"""

# iPad 画布更宽，放大字号，机身换成 4:3 平板比例
IPAD_CSS = """
.card::after{left:72px;top:72px;width:56px;height:9px}
.t{margin-top:110px;font-size:68px;line-height:1.2}
.s{margin-top:20px;font-size:32px}
.phone{top:390px;width:860px;height:1146px;border-radius:44px;border-width:18px}
.phone::before{display:none}
.lock .clk{margin-top:110px;font-size:150px}
.lock .dt{font-size:28px}
.nt{width:560px;border-radius:28px;padding:20px 24px;gap:16px;font-size:24px}
.nt:first-of-type{margin-top:200px}
.nt .ic{width:60px;height:60px;border-radius:14px;font-size:24px}
.nt .tm{font-size:20px}
.grid{top:390px;left:150px;right:150px;gap:28px}
.f{border-radius:32px;padding:30px 36px}
.f .e{width:60px;height:60px}
.f b{font-size:36px;margin-top:16px}
.f span{font-size:26px}
"""


def phone(img):
    return f'<div class="phone"><img src="{img}"></div>'


def lock_screen(copy):
    items = "".join(
        f'<div class="nt"><div class="ic">NS</div><div><span class="tm">{tm}</span><b>{title}</b>{body}</div></div>'
        for tm, title, body in copy["notifications"]
    )
    return f'<div class="phone"><div class="lock"><div class="clk">9:41</div><div class="dt">10月22日 星期四</div>{items}</div></div>'


def feature_grid(copy):
    features = copy["features"]
    cells = "".join(
        f'<div class="f{" hl" if i == len(features) - 1 else ""}"><div class="e">{ICONS[key]}</div><b>{name}</b><span>{desc}</span></div>'
        for i, (key, name, desc) in enumerate(features)
    )
    return f'<div class="grid">{cells}</div>'


# (文件名, 是否深色底, 主体)
CARDS = [
    ("01-home", False, lambda copy: phone("home.jpg")),
    ("02-detail", False, lambda copy: phone("detail.jpg")),
    ("03-nq-report", False, lambda copy: phone("nq.jpg")),
    ("04-push", False, lock_screen),
    ("05-features", False, feature_grid),
    ("06-dark", True, lambda copy: phone("dark.jpg")),
]


def render(index, device, copy, workdir: Path, out_dir: Path):
    name, dark, body = CARDS[index]
    title, subtitle = copy["cards"][index]
    if device == "ipad":
        title = title.replace("手机上", "平板上").replace("手機上", "平板上")
    config = DEVICES[device]
    (w, h), scale = config["size"], config["scale"]
    css = f":root{{--w:{w}px;--h:{h}px}}" + CSS + (IPAD_CSS if device == "ipad" else "")
    html = (
        f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>'
        f'<div class="card{" dark" if dark else ""}"><div class="t">{title}</div><div class="s">{subtitle}</div>{body(copy)}</div>'
        "</body></html>"
    )
    page = workdir / f"{name}.html"
    page.write_text(html)
    png = workdir / f"{name}.png"
    subprocess.run(
        [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--force-device-scale-factor={scale}",
         f"--window-size={w},{h}", f"--screenshot={png}", page.as_uri()],
        check=True, capture_output=True,
    )
    im = Image.open(png).convert("RGB")
    assert im.size == (w * scale, h * scale), f"{name} 尺寸异常：{im.size}"
    filename = f"{config['prefix']}{name}.jpg"
    im.save(out_dir / filename, quality=92)
    return filename


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", choices=DEVICES, default="iphone")
    parser.add_argument("--locale", choices=COPY, default="zh-Hans")
    parser.add_argument("--raw", type=Path, help="未打码的模拟器原图目录")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    boxes = {"home": lambda im: list_boxes(im, args.device), **BLUR_BOXES[args.device]}
    raw_dir = ROOT / "raw" / args.device
    raw_dir.mkdir(parents=True, exist_ok=True)
    if args.raw:
        for key, key_boxes in boxes.items():
            pixelate(args.raw / f"{key}.png", raw_dir / f"{key}.jpg", key_boxes)

    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        workdir = Path(tmp)
        for key in boxes:
            shutil.copy(raw_dir / f"{key}.jpg", workdir / f"{key}.jpg")
        for index in range(len(CARDS)):
            print(f"✓ {render(index, args.device, COPY[args.locale], workdir, args.out)}")


if __name__ == "__main__":
    main()
