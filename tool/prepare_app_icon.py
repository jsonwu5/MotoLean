#!/usr/bin/env python3
"""从 assets/app_icon.png 派生 Android 自适应图标所需的透明前景。

自适应图标要求「前景透明 + 背景纯色」，而源图是满幅的青色底插画。
这里把青色背景抠成透明，保留骑手与速度线，供 flutter_launcher_icons 使用。

用法：python3 tool/prepare_app_icon.py
"""

from __future__ import annotations

import pathlib

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'assets' / 'app_icon.png'
TARGET = ROOT / 'assets' / 'app_icon_foreground.png'

# 青色背景判定阈值：R 明显低于 G/B，且 G、B 都够亮
TEAL_MIN_GB = 140
TEAL_MIN_G_R = 55
TEAL_MIN_B_R = 45

# 速度线的柔光会在背景上留下极低透明度残留，纯色底上会显出一层雾。
# 把低于该值的 alpha 直接归零，再线性拉伸剩余部分。
ALPHA_FLOOR = 0.18


def main() -> None:
    image = Image.open(SOURCE).convert('RGBA')
    pixels = np.asarray(image).astype(np.float32)
    red, green, blue = pixels[..., 0], pixels[..., 1], pixels[..., 2]

    teal = (
        (green > TEAL_MIN_GB)
        & (blue > TEAL_MIN_GB)
        & ((green - red) > TEAL_MIN_G_R)
        & ((blue - red) > TEAL_MIN_B_R)
    )

    # 轻度羽化，避免抠图边缘出现硬锯齿
    mask = Image.fromarray(((~teal) * 255).astype(np.uint8))
    alpha = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255.0

    alpha = np.clip((alpha - ALPHA_FLOOR) / (1 - ALPHA_FLOOR), 0.0, 1.0)

    out = np.dstack([red, green, blue, alpha * 255]).astype(np.uint8)
    Image.fromarray(out).save(TARGET, optimize=True)

    print(f'背景占比 {teal.mean() * 100:.1f}%')
    print(f'已写入 {TARGET.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
