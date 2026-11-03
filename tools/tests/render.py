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


def text_width(size, bold, text):
    return int(round(font(size, bool(bold)).getlength(text)))


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


def _load(path):
    try:
        im = Image.open(path)
        im.load()
        return im.convert("RGBA")
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
            if x1 - x0 < 0.5 or y1 - y0 < 0.5:
                continue
            if col[3] == 255:
                ImageDraw.Draw(canvas).rectangle([x0, y0, x1 - 1, y1 - 1], fill=col)
            else:
                blend(lambda d, o: d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=col))
        elif kind == "orect":
            x0, x1, y0, y1, c = op[1:6]
            col = rgba(c)
            blend(lambda d, o: d.rectangle([min(x0, x1), min(y0, y1), max(x0, x1) - 1, max(y0, y1) - 1], outline=col))
        elif kind == "circle":
            x, y, r, c = op[1:5]
            col = rgba(c)
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
            canvas.alpha_composite(part, dest=(max(0, pos[0]), max(0, pos[1])), source=(max(0, -pos[0]), max(0, -pos[1])))
        elif kind == "text":
            size, bold, x, y, text, c = op[1:7]
            col = rgba(c)
            f = font(size, bool(bold))
            blend(lambda d, o: d.text((x, y), text, font=f, fill=col))
    canvas.convert("RGB").save(path)
