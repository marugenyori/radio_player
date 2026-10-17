"""アプリアイコン（1024px、透明なし）を作る。

使い方: python tools/make_icon.py
出力: RadioPlayer/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # 大きく描いて縮小し、縁をなめらかにする
OUT = Path(__file__).resolve().parent.parent / "RadioPlayer/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def main() -> None:
    s = SIZE * SCALE
    img = Image.new("RGB", (s, s))
    d = ImageDraw.Draw(img)

    # 背景：上から下へ紺 → 濃い紫のグラデーション
    top, bottom = (24, 32, 72), (70, 30, 90)
    for y in range(s):
        t = y / s
        d.line([(0, y), (s, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))

    def r(v: float) -> int:
        return round(v * s)

    orange, cream, dark = (245, 133, 46), (255, 240, 214), (40, 30, 60)

    # アンテナ
    d.line([(r(0.36), r(0.30)), (r(0.62), r(0.12))], fill=cream, width=r(0.025))
    d.ellipse([r(0.60), r(0.095), r(0.65), r(0.145)], fill=cream)

    # 本体
    d.rounded_rectangle([r(0.16), r(0.30), r(0.84), r(0.80)], radius=r(0.08), fill=orange)

    # スピーカー
    d.ellipse([r(0.23), r(0.40), r(0.53), r(0.70)], fill=dark)
    for k in range(3):
        m = 0.04 + k * 0.045
        d.ellipse([r(0.23 + m), r(0.40 + m), r(0.53 - m), r(0.70 - m)], outline=orange, width=r(0.008))

    # 目盛りとつまみ
    d.rounded_rectangle([r(0.59), r(0.40), r(0.77), r(0.50)], radius=r(0.02), fill=cream)
    for k in range(5):
        x = 0.615 + k * 0.032
        d.line([(r(x), r(0.42)), (r(x), r(0.48))], fill=dark, width=r(0.006))
    d.ellipse([r(0.62), r(0.56), r(0.74), r(0.68)], fill=dark)
    d.ellipse([r(0.655), r(0.595), r(0.705), r(0.645)], fill=cream)

    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print(f"保存しました: {OUT}")


if __name__ == "__main__":
    main()
