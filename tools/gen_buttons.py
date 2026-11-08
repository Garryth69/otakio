"""Generates the PS Vita button icons used in the hint bar, dialogs and details screen.

One style for every button: dark badge with a thin ring, face-button symbols in the classic
PlayStation colours, white bold letters on L / R / SELECT / START. Drawn 8x larger and downscaled.

  python tools/gen_buttons.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "source", "assets", "images")
FONT = os.path.join(ROOT, "source", "robboto.ttf")
S = 8  # supersampling

FILL = (38, 34, 52, 255)
RING = (108, 98, 140, 255)
TEXT = (240, 236, 250, 255)
BLUE = (124, 176, 255, 255)
RED = (255, 110, 130, 255)
PINK = (244, 142, 222, 255)
GREEN = (86, 214, 170, 255)


def badge(w, h, round_all=True):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = (h * S) // 2 if round_all else 5 * S
    d.rounded_rectangle((0, 0, w * S - 1, h * S - 1), radius=r, fill=RING)
    d.rounded_rectangle((S, S, w * S - 1 - S, h * S - 1 - S), radius=max(1, r - S), fill=FILL)
    return img, d


def finish(img, w, h, name):
    img.resize((w, h), Image.LANCZOS).save(os.path.join(OUT, name))


def face(name, draw_symbol):
    img, d = badge(16, 16)
    draw_symbol(d, 8 * S, 8 * S)
    finish(img, 16, 16, name)


def sym_cross(d, cx, cy):
    a, w = 3.6 * S, int(1.7 * S)
    d.line((cx - a, cy - a, cx + a, cy + a), fill=BLUE, width=w)
    d.line((cx - a, cy + a, cx + a, cy - a), fill=BLUE, width=w)


def sym_circle(d, cx, cy):
    r, w = 3.9 * S, int(1.6 * S)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=RED, width=w)


def sym_square(d, cx, cy):
    a, w = 3.5 * S, int(1.6 * S)
    d.rectangle((cx - a, cy - a, cx + a, cy + a), outline=PINK, width=w)


def sym_triangle(d, cx, cy):
    r, w = 4.4 * S, int(1.6 * S)
    pts = [(cx, cy - r), (cx + r * 0.95, cy + r * 0.62), (cx - r * 0.95, cy + r * 0.62)]
    d.line(pts + [pts[0], pts[1]], fill=GREEN, width=w, joint="curve")


def sym_dpad(d, cx, cy):
    a, t = 4.6 * S, 1.7 * S
    d.rectangle((cx - t, cy - a, cx + t, cy + a), fill=TEXT)
    d.rectangle((cx - a, cy - t, cx + a, cy + t), fill=TEXT)


def labelled(name, text, w, size, spacing=0.0):
    img, d = badge(w, 16, round_all=True)
    font = ImageFont.truetype(FONT, int(size * S))
    # letter spacing: draw glyph by glyph
    widths = [d.textlength(ch, font=font) for ch in text]
    total = sum(widths) + spacing * S * (len(text) - 1)
    x = (w * S - total) / 2
    bbox = d.textbbox((0, 0), text, font=font)
    y = (16 * S - (bbox[3] - bbox[1])) / 2 - bbox[1]
    for ch, cw in zip(text, widths):
        d.text((x, y), ch, font=font, fill=TEXT)
        x += cw + spacing * S
    finish(img, w, 16, name)


def main():
    face("cross_button.png", sym_cross)
    face("circle_button.png", sym_circle)
    face("square_button.png", sym_square)
    face("triangle_button.png", sym_triangle)
    face("dpad.png", sym_dpad)
    labelled("l_button.png", "L", 24, 10.5)
    labelled("r_button.png", "R", 24, 10.5)
    labelled("select_button.png", "SELECT", 48, 7.6, 0.5)
    labelled("start_button.png", "START", 48, 7.6, 0.5)
    print("buttons written to", OUT)


if __name__ == "__main__":
    main()
