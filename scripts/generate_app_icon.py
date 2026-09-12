#!/usr/bin/env python3
"""生成 ENVPilot 的应用图标（简约几何风，非透明玻璃质感）。

设计：圆角方块底 + 白色终端提示符 chevron + 三枚运行时标记圆点
（绿 / 蓝 / 橙，对应 Node / JDK / Python）。

用法：
    python3 scripts/generate_app_icon.py

产物：
    Resources/SourceAssets/ENVPilotAppIcon.png   1024×1024 主稿
    Resources/AppIcon.iconset/                   全套尺寸
    Resources/AppIcon.icns                       打包用图标
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ICONSET_DIR = ROOT / "Resources" / "AppIcon.iconset"
SOURCE_PNG = ROOT / "Resources" / "SourceAssets" / "ENVPilotAppIcon.png"
ICNS_PATH = ROOT / "Resources" / "AppIcon.icns"

# 主稿在 4096 下绘制再降采样，保证小尺寸边缘干净。
SUPERSAMPLE = 4096

# macOS 应用图标的标准留白与圆角比例。
CONTENT_RATIO = 0.82
CORNER_RATIO = 0.2237

# 底色：深靛蓝渐变，白色前景对比足够。
BACKGROUND_TOP = (58, 74, 138)
BACKGROUND_BOTTOM = (26, 33, 64)

# 三枚运行时标记，保持与主界面一致的语义色。
DOTS = [
    (52, 199, 123),   # Node.js
    (86, 156, 236),   # JDK
    (240, 164, 62),   # Python
]

# iconset 需要的尺寸：文件名 -> 像素边长。
ICONSET_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        gradient.putpixel(
            (0, y),
            tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
        )
    return gradient.resize((size, size), Image.Resampling.BILINEAR)


def draw_chevron(size: int) -> Image.Image:
    """白色终端提示符「>」。

    用圆头折线绘制：先画带圆角接缝的折线，再在两端各补一个半径等于半线宽的圆，
    等价于 round cap，但避免了 `ImageDraw.line` 默认端头过圆的问题。
    """
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    stroke = size * 0.120
    apex_x = size * 0.565
    left_x = size * 0.335
    top_y = size * 0.315
    mid_y = size * 0.500
    bottom_y = size * 0.685

    points = [(left_x, top_y), (apex_x, mid_y), (left_x, bottom_y)]
    draw.line(points, fill=(255, 255, 255, 255), width=round(stroke), joint="curve")

    cap = stroke / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse((x - cap, y - cap, x + cap, y + cap), fill=(255, 255, 255, 255))

    return layer


def draw_dots(size: int) -> Image.Image:
    """右侧三枚彩色圆点，纵向排列。"""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    center_x = size * 0.745
    step = size * 0.148
    center_y = size * 0.5
    radius = size * 0.054

    for index, color in enumerate(DOTS):
        cy = center_y + (index - 1) * step
        draw.ellipse(
            (center_x - radius, cy - radius, center_x + radius, cy + radius),
            fill=(*color, 255),
        )

    return layer


def draw_highlight(size: int) -> Image.Image:
    """左上角的柔和径向高光，避免纯色底过于死板（仍是实底，不是玻璃质感）。"""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    center_x = size * 0.24
    center_y = size * 0.16
    extent = size * 0.95

    for step in range(48, 0, -1):
        t = step / 48
        radius = extent * t
        alpha = round(26 * (1 - t) ** 1.6)
        if alpha <= 0:
            continue
        ImageDraw.Draw(layer).ellipse(
            (center_x - radius, center_y - radius, center_x + radius, center_y + radius),
            fill=(255, 255, 255, alpha),
        )

    return layer.filter(ImageFilter.GaussianBlur(size * 0.03))


def render_icon() -> Image.Image:
    size = SUPERSAMPLE
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # 圆角方块底：占画布 82%，四周留出 macOS 图标标准边距。
    content_size = round(size * CONTENT_RATIO)
    offset = (size - content_size) // 2
    radius = round(content_size * CORNER_RATIO)

    plate = vertical_gradient(content_size, BACKGROUND_TOP, BACKGROUND_BOTTOM).convert("RGBA")
    plate.alpha_composite(draw_highlight(content_size))
    plate.putalpha(rounded_mask(content_size, radius))
    canvas.alpha_composite(plate, (offset, offset))

    # 前景元素在未缩放的坐标系里绘制，再平移到方块上。
    canvas.alpha_composite(draw_chevron(content_size), (offset, offset))
    canvas.alpha_composite(draw_dots(content_size), (offset, offset))

    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def main() -> None:
    icon = render_icon()

    SOURCE_PNG.parent.mkdir(parents=True, exist_ok=True)
    icon.save(SOURCE_PNG)
    print(f"source  → {SOURCE_PNG.relative_to(ROOT)}")

    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    for name in ICONSET_DIR.glob("*.png"):
        name.unlink()
    for name, edge in ICONSET_SIZES.items():
        icon.resize((edge, edge), Image.Resampling.LANCZOS).save(ICONSET_DIR / name)
    print(f"iconset → {ICONSET_DIR.relative_to(ROOT)} ({len(ICONSET_SIZES)} 个尺寸)")

    subprocess.run(
        ["iconutil", "--convert", "icns", str(ICONSET_DIR), "--output", str(ICNS_PATH)],
        check=True,
    )
    print(f"icns    → {ICNS_PATH.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
