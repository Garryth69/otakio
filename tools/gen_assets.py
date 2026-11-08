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
    """Rounded square with a capital "O" drawn in simple lines: spiky hair on top, a ninja-style headband with a
    metal plate across the forehead and an open manga at the bottom.
    One outline width (white) for every shape, one dark fill (hair, band), one light fill (plate, pages)."""
    big = size * S
    u = big / 100.0
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    grad = gradient((big, big), ACCENT1, ACCENT2)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.24), fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    line = max(2, int(3.4 * u))  # every outline
    fine = max(1, int(2.0 * u))  # every inner detail
    dark = (40, 18, 80, 255)
    light = (236, 232, 250, 255)
    detail = (88, 56, 160, 255)

    def P(*pts):
        return [(x * u, y * u) for x, y in pts]

    def shape(pts, fill):
        d.polygon(pts, fill=fill)
        d.line(pts + [pts[0], pts[1]], fill=W, width=line, joint="curve")

    # the "O": a thick white ring
    cx, cy, r, ring = 50, 55, 25, 8
    d.ellipse([(cx - r - ring / 2) * u, (cy - r - ring / 2) * u, (cx + r + ring / 2) * u, (cy + r + ring / 2) * u], outline=W, width=int(ring * u))
    # spiky hair
    shape(P((21, 44), (9, 32), (22, 33), (16, 15), (32, 25), (37, 7), (48, 21), (60, 6), (63, 22), (79, 12), (75, 30),
            (91, 28), (79, 44)), dark)
    # headband: knot tails, band, metal plate (two rivets + engraved line)
    shape(P((78, 38), (92, 43), (90, 48), (77, 44)), dark)
    shape(P((78, 42), (90, 54), (85, 57), (76, 46)), dark)
    d.rounded_rectangle([20 * u, 36 * u, 80 * u, 47 * u], radius=int(3 * u), fill=dark, outline=W, width=line)
    d.rounded_rectangle([38 * u, 33.5 * u, 62 * u, 49.5 * u], radius=int(3 * u), fill=light, outline=W, width=line)
    for rx in (42, 58):
        d.ellipse([(rx - 1.5) * u, (41.5 - 1.5) * u, (rx + 1.5) * u, (41.5 + 1.5) * u], fill=detail)
    d.line(P((46, 41.5), (54, 41.5)), fill=detail, width=fine)
    # open manga at the bottom (bigger than the band, overlapping the lower ring)
    shape(P((50, 74), (22, 69), (22, 90), (50, 95)), light)
    shape(P((50, 74), (78, 69), (78, 90), (50, 95)), light)
    for k in range(4):
        y = 75.5 + k * 4.2
        d.line(P((27, y - 2.6), (45, y + 0.6)), fill=detail, width=fine)
        d.line(P((55, y + 0.6), (73, y - 2.6)), fill=detail, width=fine)
    return img.resize((size, size), Image.LANCZOS)


TITLE_FONT = os.path.join(ROOT, "tools", "fonts", "Fredoka.ttf")  # SIL OFL 1.1, see tools/fonts/OFL-Fredoka.txt


def text_img(text, size, color=W, weight="Bold"):
    """Title text in Fredoka (rounded, manga-friendly); falls back to the app's Roboto Bold"""
    try:
        font = ImageFont.truetype(TITLE_FONT, size * S)
        font.set_variation_by_name(weight)
    except Exception:
        font = ImageFont.truetype(BOLD, size * S)
    bbox = font.getbbox(text)
    img = Image.new("RGBA", (bbox[2] + 4 * S, bbox[3] + 4 * S), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((2 * S, 0), text, font=font, fill=color)
    img = img.crop(img.getbbox()) if img.getbbox() else img
    img = img.resize((max(1, img.width // S), max(1, img.height // S)), Image.LANCZOS)
    return img


def logo(width, height, path, mark=None):
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    mark_size = mark or int(height * 0.8)
    m = mascot_mark(mark_size)
    t = text_img("Otakio", int(height * 0.55))
    total = mark_size + 18 + t.width
    x = (width - total) // 2
    img.paste(m, (x, (height - mark_size) // 2), m)
    img.paste(t, (x + mark_size + 18, (height - t.height) // 2), t)
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
    sub = text_img("manga reader", 30, (200, 190, 255, 255), "Medium")
    top = 250 - (t.height + 22 + sub.height) // 2
    la.paste(t, (330, top), t)
    la.paste(sub, (334, top + t.height + 22), sub)
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
