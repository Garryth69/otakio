"""Renders draw-op lists captured by vita_mock.lua into PNG screenshots (960x544)."""
import os
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REG = os.path.join(ROOT, "source", "roboto.ttf")
BOLD = os.path.join(ROOT, "source", "robboto.ttf")


def rgba(c):
    c = int(c)
    return (c & 255, (c >> 8) & 255, (c >> 16) & 255, (c >> 24) & 255)


@lru_cache(maxsize=64)
def font(size, bold):
    return ImageFont.truetype(BOLD if bold else REG, int(size))


@lru_cache(maxsize=64)
def font_basic(size, bold):
    """Without raqm: some site titles make raqm_layout() fail (the Vita's FreeType draws them fine)."""
    return ImageFont.truetype(BOLD if bold else REG, int(size), layout_engine=ImageFont.Layout.BASIC)


def text_width(size, bold, text):
    try:
        return int(round(font(size, bool(bold)).getlength(text)))
    except Exception:  # raqm_layout() failed (OSError or ValueError, depending on Pillow)
        return int(round(font_basic(size, bool(bold)).getlength(text)))


SNAPSHOTS = {}


def snapshot(img_id, path):
    """Copies the pixels of a texture at load time (files like temp/cache.image get reused)."""
    im = _load(path)
    if im is not None:
        SNAPSHOTS["#" + str(int(img_id))] = im


def load_image(path):
    if path.startswith("#"):
        return SNAPSHOTS.get(path)
    return _load(path)


# SIM_BLUR_IMAGES=<radius>: downloaded images (covers, pages) are blurred as they load, for README screenshots that
# don't show third-party artwork; the app's own icons stay sharp
_BLUR = float(os.environ.get("SIM_BLUR_IMAGES") or 0)


def _load(path):
    try:
        im = Image.open(path)
        im.load()
        im = im.convert("RGBA")
        if _BLUR and "ux0" in path.replace("\\", "/").split("/"):
            from PIL import ImageFilter
            im = im.filter(ImageFilter.GaussianBlur(_BLUR * max(1.0, max(im.size) / 512)))
        return im
    except Exception:
        return None


def image_size(path):
    im = _load(path)
    if im is None:
        return None, None
    return im.size


def tint(im, color):
    if color is False or color is None:
        return im
    r, g, b, a = rgba(color)
    if (r, g, b, a) == (255, 255, 255, 255):
        return im
    px = im.split()
    out = Image.merge("RGBA", [
        px[0].point(lambda v: v * r // 255),
        px[1].point(lambda v: v * g // 255),
        px[2].point(lambda v: v * b // 255),
        px[3].point(lambda v: v * a // 255),
    ])
    return out


# problems found while rendering (tools/tests/ui_audit.py reads them): text leaving the screen, text that can hardly
# be read on what is behind it
ISSUES = []


def _lum(c):
    def ch(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(c[0]) + 0.7152 * ch(c[1]) + 0.0722 * ch(c[2])


def _contrast(a, b):
    la, lb = _lum(a), _lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def _check_text(canvas, path, size, bold, x, y, text, col):
    if not text.strip() or col[3] < 200:
        return
    try:
        w = text_width(size, bool(bold), text)
    except Exception:
        return
    if x + w > 962 or x < -2:
        ISSUES.append((path, "offscreen", "%r x=%d w=%d" % (text[:40], x, w)))
    # what is behind the text: the most common color in its box
    box = (max(0, int(x)), max(0, int(y)), min(960, int(x + w)), min(544, int(y + size)))
    if box[2] - box[0] < 4 or box[3] - box[1] < 4:
        return
    region = canvas.crop(box).convert("RGB").resize((16, 4))
    bg = max(region.getcolors(64) or [(0, (0, 0, 0))])[1]
    ratio = _contrast(col, bg)
    if ratio < 2.2:
        ISSUES.append((path, "contrast", "%r %.1f:1 text=%s bg=%s" % (text[:40], ratio, col[:3], bg)))


def render(ops, path):
    canvas = Image.new("RGBA", (960, 544), (0, 0, 0, 255))

    def blend(layer_fn, box=None):
        overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        layer_fn(ImageDraw.Draw(overlay), overlay)
        canvas.alpha_composite(overlay)

    for op in ops:
        kind = op[0]
        if kind == "clear":
            canvas.paste(rgba(op[1])[:3] + (255,), (0, 0, 960, 544))
        elif kind == "rect":
            x0, x1, y0, y1, c = op[1:6]
            x0, x1 = sorted((x0, x1))
            y0, y1 = sorted((y0, y1))
            col = rgba(c)
            if x1 - x0 < 1 or y1 - y0 < 1:
                continue
            if col[3] == 255:
                ImageDraw.Draw(canvas).rectangle([x0, y0, x1 - 1, y1 - 1], fill=col)
            else:
                blend(lambda d, o: d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=col))
        elif kind == "orect":
            x0, x1, y0, y1, c = op[1:6]
            col = rgba(c)
            if abs(x1 - x0) < 1 or abs(y1 - y0) < 1:
                continue
            blend(lambda d, o: d.rectangle([min(x0, x1), min(y0, y1), max(x0, x1) - 1, max(y0, y1) - 1], outline=col))
        elif kind == "circle":
            x, y, r, c = op[1:5]
            col = rgba(c)
            if r <= 0:
                print("   render: circle with radius", r, "at", x, y)
                continue
            blend(lambda d, o: d.ellipse([x - r, y - r, x + r, y + r], fill=col))
        elif kind in ("img", "simg", "ximg"):
            im = load_image(op[1])
            if im is None:
                continue
            if kind == "img":
                x, y, c = op[2], op[3], op[4]
                part = tint(im, c)
                pos = (int(x), int(y))
            elif kind == "simg":
                x, y, sx, sy, c = op[2:7]
                w, h = max(1, int(im.width * sx)), max(1, int(im.height * sy))
                part = tint(im.resize((w, h)), c)
                pos = (int(x), int(y))
            else:
                x, y, sx, sy, w, h, scx, scy, c = op[2:11]
                crop = im.crop((int(sx), int(sy), int(sx + w), int(sy + h)))
                tw, th = max(1, int(w * scx)), max(1, int(h * scy))
                part = tint(crop.resize((tw, th)), c)
                pos = (int(x - tw / 2), int(y - th / 2))
            if pos[0] >= 960 or pos[1] >= 544 or pos[0] + part.width <= 0 or pos[1] + part.height <= 0:
                continue  # entirely off screen
            canvas.alpha_composite(part, dest=(max(0, pos[0]), max(0, pos[1])), source=(max(0, -pos[0]), max(0, -pos[1])))
        elif kind == "text":
            size, bold, x, y, text, c = op[1:7]
            col = rgba(c)
            _check_text(canvas, path, size, bold, x, y, text, col)
            f = font(size, bool(bold))
            try:
                blend(lambda d, o: d.text((x, y), text, font=f, fill=col))
            except Exception:
                fb = font_basic(size, bool(bold))
                blend(lambda d, o: d.text((x, y), text, font=fb, fill=col))
    canvas.convert("RGB").save(path)
