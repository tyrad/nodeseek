"""用同一设备的游客和已登录截图，检查「我的」首次可辨认的录像帧。"""
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops

directory = Path(sys.argv[1])
card, screen = map(json.loads, sys.argv[2:])
width, height = round(screen["width"]), round(screen["height"])
size = (width, height)
movie = directory / "me-open.mov"


def reference(filename):
    with Image.open(directory / filename) as image:
        return image.convert("L").resize(size, Image.Resampling.LANCZOS)


guest = reference("me-guest.png")
member = reference("me-member.png")
x, y = round(card["x"]), round(card["y"])
# 对齐当前 MeProfileCard 的头像、间距和导航栏，避免匹配到底部常驻的「我的」。
title_box = (width // 2 - 23, y - 59, width // 2 + 23, y - 29)
name_box = (x + 92, y + 12, min(x + 230, width - 40), y + 63)


def ink(image, box, contrast):
    patch = image.crop(box)
    background = patch.getpixel((0, 0))
    return patch.point(lambda p: 255 if abs(p - background) >= contrast else 0)


def signature(image, box, text_line=False):
    mask = ink(image, box, 95)
    if text_line:
        # 用户名为粗体，取首行文字；下面的 UID/等级等副标题可以异步变化。
        rows = [row for row in range(mask.height) if mask.crop((0, row, mask.width, row + 1)).getbbox()]
        if not rows:
            raise ValueError("参考图缺少账号文字")
        end = next((a + 1 for a, b in zip(rows, rows[1:]) if b > a + 1), rows[-1] + 1)
        box = (box[0], box[1] + rows[0], box[2], box[1] + end)
        mask = ink(image, box, 95)
    bounds = mask.getbbox()
    if not bounds:
        raise ValueError("参考图中没有可匹配的文字")
    tight = (box[0] + bounds[0], box[1] + bounds[1], box[0] + bounds[2], box[1] + bounds[3])
    padded = (tight[0] - 2, tight[1] - 2, tight[2] + 2, tight[3] + 2)
    return padded, ink(image, padded, 95)


def matches(frame, template, shifts):
    (left, top, right, bottom), mask = template
    for dy in shifts:
        candidate = ink(frame, (left, top + dy, right, bottom + dy), 75)
        union = ImageChops.lighter(mask, candidate).histogram()[255]
        overlap = ImageChops.darker(mask, candidate).histogram()[255]
        if union and overlap / union >= 0.68:
            return True
    return False


title = signature(guest, title_box)
# 导航标题会先于正文切换。另取资料卡下方固定的“我的帖子”行，避免把旧通知页计入。
row_top = round(card["y"] + card["height"] + 48)
body = signature(guest, (x + 52, row_top, x + 133, row_top + 46), True)
guest_name = signature(guest, name_box, True)
member_name = signature(member, name_box, True)
vertical = [0] + [n for d in range(1, 15) for n in (-d, d)]
if matches(guest, member_name, vertical) or not matches(member, member_name, [0]):
    raise ValueError("账号参考图无法区分，需人工核对录像")

frames = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
    "-show_frames", "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", movie]))["frames"]
times = [float(frame["best_effort_timestamp_time"]) for frame in frames]
if not times:
    raise ValueError("未录到画面")

first = named = first_guest = None
first_state = None
cmd = ["ffmpeg", "-v", "error", "-i", movie, "-vf", f"scale={width}:{height}:flags=lanczos,setpts=N/(25*TB)", "-enc_time_base", "1:600",
       "-fps_mode", "passthrough", "-pix_fmt", "gray", "-f", "rawvideo", "-"]
with subprocess.Popen(cmd, stdout=subprocess.PIPE) as decoder:
    for index, time in enumerate(times):
        data = decoder.stdout.read(width * height)
        if len(data) != width * height:
            raise ValueError("录像时间戳与解码帧不一致")
        frame = Image.frombytes("L", size, data)
        if not matches(frame, title, [0]):
            continue
        if first is None and not matches(frame, body, range(-8, min(250, height - body[0][3]))):
            continue
        is_member = matches(frame, member_name, vertical)
        is_guest = matches(frame, guest_name, vertical)
        if first is None:
            first = index
            first_state = "member" if is_member else "guest" if is_guest else "unresolved"
            frame.save(directory / "me-first-frame.png")
        if is_guest and first_guest is None:
            first_guest = index
            frame.save(directory / "me-first-guest.png")
        if is_member and named is None:
            named = index
            frame.save(directory / "me-first-name.png")
    if decoder.wait() != 0:
        raise ValueError("录像解码失败")

if first is None or named is None:
    raise ValueError("未能从录像识别我的页或目标账号，请核对录像")
result = dict(firstPageFrame=first, firstNameFrame=named, firstState=first_state,
              delayMs=round((times[named] - times[first]) * 1000, 1),
              firstPagePTS=times[first], firstNamePTS=times[named], firstGuestFrame=first_guest,
              previousFrameGapMs=round((times[first] - times[first-1])*1000, 1) if first else None)
(directory / "me-timing.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result), flush=True)
if first != named or first_guest is not None:
    raise SystemExit("我的页首屏未直接显示目标账号或之后闪现了游客状态")
