"""Generates Otakio's navigation icons, logo, LiveArea and bubble images with Pillow.
Icons are white-on-transparent so the app can tint them with the theme accent."""
import math, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "source")
ICONS = os.path.join(SRC, "assets", "icons")
IMAGES = os.path.join(SRC, "assets", "images")
BOLD = os.path.join(SRC, "robboto.ttf")
S = 4  # supersampling
N = 28  # icon size
W = (255, 255, 255, 255)


def canvas(n=N):
    img = Image.new("RGBA", (n * S, n * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(img, name, n=N):
    img.resize((n, n), Image.LANCZOS).save(os.path.join(ICONS, name))


def stroke(n=N):
    return int(2.4 * S)


def icon_library():
    img, d = canvas()
    s = stroke()
    # three books
    d.rounded_rectangle([4 * S, 5 * S, 9 * S, 23 * S], radius=S, outline=W, width=s)
    d.rounded_rectangle([11 * S, 5 * S, 16 * S, 23 * S], radius=S, outline=W, width=s)
    # tilted book
    pts = [(18 * S, 7 * S), (22.5 * S, 5.8 * S), (26 * S, 22 * S), (21.5 * S, 23.2 * S)]
    d.polygon(pts, outline=W, width=s)
    d.line([3 * S, 25 * S, 26 * S, 25 * S], fill=W, width=s)
    save(img, "nav_library.png")


def icon_updates():
    img, d = canvas()
    s = stroke()
    d.arc([6 * S, 4 * S, 22 * S, 20 * S], 180, 360, fill=W, width=s)
    d.line([6 * S + s // 2, 12 * S, 6 * S + s // 2, 19 * S], fill=W, width=s)
    d.line([22 * S - s // 2, 12 * S, 22 * S - s // 2, 19 * S], fill=W, width=s)
    d.line([4 * S, 20 * S, 24 * S, 20 * S], fill=W, width=s)
    d.ellipse([11 * S, 21 * S, 17 * S, 26 * S], fill=W)
    d.ellipse([12.5 * S, 1.5 * S, 15.5 * S, 4.5 * S], fill=W)
    save(img, "nav_updates.png")


def icon_history():
    img, d = canvas()
    s = stroke()
    d.ellipse([3 * S, 3 * S, 25 * S, 25 * S], outline=W, width=s)
    d.line([14 * S, 8 * S, 14 * S, 14.5 * S], fill=W, width=s)
    d.line([14 * S, 14 * S, 18.5 * S, 17 * S], fill=W, width=s)
    save(img, "nav_history.png")


def icon_browse():
    img, d = canvas()
    s = stroke()
    d.ellipse([3 * S, 3 * S, 25 * S, 25 * S], outline=W, width=s)
    c = 14 * S
    d.polygon([(c + 5 * S, c - 5 * S), (c + 1.8 * S, c + 1.8 * S), (c - 5 * S, c + 5 * S), (c - 1.8 * S, c - 1.8 * S)], fill=W)
    d.ellipse([c - 1.6 * S, c - 1.6 * S, c + 1.6 * S, c + 1.6 * S], fill=(0, 0, 0, 0))
    save(img, "nav_browse.png")


def icon_extensions():
    img, d = canvas()
    s = stroke()
    # puzzle piece
    d.rounded_rectangle([4 * S, 8 * S, 20 * S, 24 * S], radius=2 * S, outline=W, width=s)
    d.ellipse([9 * S, 3 * S, 15 * S, 9 * S], fill=W)
    d.ellipse([18 * S, 13 * S, 24 * S, 19 * S], fill=W)
    save(img, "nav_extensions.png")


def icon_downloads():
    img, d = canvas()
    s = stroke()
    d.line([14 * S, 3 * S, 14 * S, 17 * S], fill=W, width=s)
    d.line([8 * S, 11.5 * S, 14 * S, 17.5 * S], fill=W, width=s)
    d.line([20 * S, 11.5 * S, 14 * S, 17.5 * S], fill=W, width=s)
    d.line([4 * S, 19 * S, 4 * S, 24 * S], fill=W, width=s)
    d.line([24 * S, 19 * S, 24 * S, 24 * S], fill=W, width=s)
    d.line([4 * S, 24 * S, 24 * S, 24 * S], fill=W, width=s)
    save(img, "nav_downloads.png")


def icon_import():
    img, d = canvas()
    s = stroke()
    d.polygon([(3 * S, 7 * S), (11 * S, 7 * S), (13.5 * S, 10 * S), (25 * S, 10 * S), (25 * S, 23 * S), (3 * S, 23 * S)], outline=W, width=s)
    d.line([14 * S, 13 * S, 14 * S, 20 * S], fill=W, width=s)
    d.line([10.5 * S, 16.5 * S, 17.5 * S, 16.5 * S], fill=W, width=s)
    save(img, "nav_import.png")


def icon_more():
    img, d = canvas()
    # gear
    c, r_out, r_in = 14 * S, 11 * S, 7.5 * S
    pts = []
    teeth = 8
    for i in range(teeth * 4):
        a = i / (teeth * 4) * 2 * math.pi
        r = r_out if (i % 4) in (0, 1) else r_in
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=W)
    d.ellipse([c - 4 * S, c - 4 * S, c + 4 * S, c + 4 * S], fill=(0, 0, 0, 0))
    save(img, "nav_more.png")


def gradient(size, c1, c2):
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.6 + y / h * 0.4)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
    return img


ACCENT1 = (104, 56, 196)
ACCENT2 = (46, 18, 92)
BG = (20, 13, 34)


def mascot_mark(size):
    """Rounded square with an anime chibi mascot: cat-eared head, big shiny eyes, blush, manga speed lines."""
    big = size * S
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    grad = gradient((big, big), ACCENT1, ACCENT2)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.24), fill=255)
    # manga speed lines radiating from the face
    rays = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    cx, cy = big * 0.5, big * 0.56
    for i in range(28):
        a = i * math.pi * 2 / 28 + 0.06
        w = 0.035 if i % 2 else 0.018
        r1, r2 = big * 0.40, big * 0.95
        rd.polygon([(cx + math.cos(a - w) * r1, cy + math.sin(a - w) * r1),
                    (cx + math.cos(a) * r2, cy + math.sin(a) * r2),
                    (cx + math.cos(a + w) * r1, cy + math.sin(a + w) * r1)], fill=(255, 255, 255, 34))
    grad = Image.alpha_composite(grad, rays)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    hr = big * 0.29  # head radius
    ink = (46, 22, 90, 255)
    # cat ears (drawn first, the head covers their base)
    for side in (-1, 1):
        bx = cx + side * hr * 0.62
        ear = [(bx - side * hr * 0.42, cy - hr * 0.55), (cx + side * hr * 0.98, cy - hr * 1.30), (bx + side * hr * 0.40, cy - hr * 0.25)]
        d.polygon(ear, fill=W)
        inner = [(bx - side * hr * 0.18, cy - hr * 0.62), (cx + side * hr * 0.90, cy - hr * 1.08), (bx + side * hr * 0.26, cy - hr * 0.44)]
        d.polygon(inner, fill=(255, 170, 205, 255))
    d.ellipse([cx - hr, cy - hr * 0.92, cx + hr, cy + hr * 0.92], fill=W)
    # big anime eyes with catchlights
    ew, eh = hr * 0.25, hr * 0.36
    for side in (-1, 1):
        ex, ey = cx + side * hr * 0.42, cy + hr * 0.02
        d.ellipse([ex - ew, ey - eh, ex + ew, ey + eh], fill=ink)
        d.ellipse([ex - ew * 0.78, ey - eh * 0.05, ex + ew * 0.78, ey + eh * 0.86], fill=(124, 72, 230, 255))
        d.ellipse([ex - ew * 0.62, ey - eh * 0.72, ex + ew * 0.05, ey - eh * 0.08], fill=W)
        d.ellipse([ex + ew * 0.18, ey + eh * 0.30, ex + ew * 0.52, ey + eh * 0.62], fill=W)
        # blush
        bx2, by2 = cx + side * hr * 0.70, cy + hr * 0.46
        d.ellipse([bx2 - hr * 0.15, by2 - hr * 0.07, bx2 + hr * 0.15, by2 + hr * 0.07], fill=(255, 150, 190, 255))
    # "ω" mouth
    mw = max(1, int(big * 0.016))
    my = cy + hr * 0.40
    d.arc([cx - hr * 0.20, my - hr * 0.10, cx, my + hr * 0.12], 10, 170, fill=ink, width=mw)
    d.arc([cx, my - hr * 0.10, cx + hr * 0.20, my + hr * 0.12], 10, 170, fill=ink, width=mw)
    # sparkle
    sx, sy, sr = big * 0.83, big * 0.83, big * 0.07
    d.polygon([(sx, sy - sr), (sx + sr * 0.28, sy - sr * 0.28), (sx + sr, sy), (sx + sr * 0.28, sy + sr * 0.28), (sx, sy + sr), (sx - sr * 0.28, sy + sr * 0.28), (sx - sr, sy), (sx - sr * 0.28, sy - sr * 0.28)], fill=W)
    return img.resize((size, size), Image.LANCZOS)


def text_img(text, size, color=W):
    font = ImageFont.truetype(BOLD, size * S)
    bbox = font.getbbox(text)
    img = Image.new("RGBA", (bbox[2] + 4 * S, bbox[3] + 4 * S), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((0, 0), text, font=font, fill=color)
    img = img.resize((img.width // S, img.height // S), Image.LANCZOS)
    return img


def logo(width, height, path, mark=None):
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    mark_size = mark or int(height * 0.8)
    m = mascot_mark(mark_size)
    t = text_img("Otakio", int(height * 0.55))
    total = mark_size + 18 + t.width
    x = (width - total) // 2
    img.paste(m, (x, (height - mark_size) // 2), m)
    img.paste(t, (x + mark_size + 18, (height - t.height) // 2 - int(height * 0.04)), t)
    img.save(path)


def livearea():
    sce = os.path.join(SRC, "sce_sys")
    m = mascot_mark(128).convert("RGBA")
    bg = Image.new("RGBA", (128, 128), BG + (255,))
    bg.paste(m, (0, 0), m)
    bg.convert("P", palette=Image.ADAPTIVE, colors=255).save(os.path.join(sce, "icon0.png"))
    # LiveArea background 840x500
    la = gradient((840, 500), (30, 16, 56), (14, 8, 28)).convert("RGBA")
    lines = Image.new("RGBA", la.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lines)
    for i in range(16):
        x = 60 * i - 40
        d.line([x, 500, x + 300, 0], fill=(255, 255, 255, 14), width=2)
    la = Image.alpha_composite(la, lines)
    big = mascot_mark(220)
    la.paste(big, (80, 140), big)
    t = text_img("Otakio", 96)
    la.paste(t, (330, 170), t)
    sub = text_img("manga reader", 30, (200, 190, 255, 255))
    la.paste(sub, (336, 290), sub)
    la.convert("P", palette=Image.ADAPTIVE, colors=255).save(os.path.join(sce, "livearea", "contents", "bg.png"))
    # startup gate 280x158
    st = gradient((280, 158), ACCENT1, ACCENT2).convert("RGBA")
    t = text_img("Otakio", 44)
    st.paste(t, ((280 - t.width) // 2, (158 - t.height) // 2), t)
    st.convert("P", palette=Image.ADAPTIVE, colors=255).save(os.path.join(sce, "livearea", "contents", "startup.png"))


def main():
    for fn in [icon_library, icon_updates, icon_history, icon_browse, icon_extensions, icon_downloads, icon_import, icon_more]:
        fn()
    # splash logo keeps NOBORU's 666x172 slot so index.lua math stays valid
    logo(666, 172, os.path.join(IMAGES, "logo.png"), mark=150)
    logo(205, 85, os.path.join(IMAGES, "logo-small.png"), mark=56)
    mascot_mark(56).save(os.path.join(IMAGES, "mark.png"))
    livearea()
    print("assets generated")


if __name__ == "__main__":
    main()
