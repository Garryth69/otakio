"""Creates the ux0:data/otakio/import/ fixtures used by the 'import', 'importread', 'saveimage' and 'savepng' scenarios.

  python tools/tests/make_import_fixtures.py <sim --tmp dir>

Items (alphabetical order is the order the Import screen lists them):
  A Folder Manga/            three JPEG pages
  B Archive Manga.cbz        three JPEG pages
  C Mixed Formats.zip        JPEG, PNG, JPEG (page 2 is a PNG: 'savepng' saves it as JPEG)
  D Chapters Manga/          cover.jpg + "Chapter 1/" and "Chapter 2/" with two pages each
"""
import io, os, sys, zipfile
from PIL import Image, ImageDraw


def page(text, fmt="JPEG", size=(800, 1200), color=(235, 228, 210)):
    im = Image.new("RGB", size, color)
    d = ImageDraw.Draw(im)
    d.rectangle([40, 40, size[0] - 40, size[1] - 40], outline=(40, 40, 40), width=6)
    d.text((80, 80), text, fill=(20, 20, 20))
    buf = io.BytesIO()
    im.save(buf, fmt, quality=90) if fmt == "JPEG" else im.save(buf, fmt)
    return buf.getvalue()


def main():
    tmp = sys.argv[1]
    base = os.path.join(tmp, "ux0", "data", "otakio", "import")
    os.makedirs(base, exist_ok=True)
    a = os.path.join(base, "A Folder Manga")
    os.makedirs(a, exist_ok=True)
    for i in range(1, 4):
        open(os.path.join(a, "%02d.jpg" % i), "wb").write(page("A page %d" % i))
    with zipfile.ZipFile(os.path.join(base, "B Archive Manga.cbz"), "w") as z:
        for i in range(1, 4):
            z.writestr("%02d.jpg" % i, page("B page %d" % i))
    with zipfile.ZipFile(os.path.join(base, "C Mixed Formats.zip"), "w") as z:
        z.writestr("01.jpg", page("C page 1"))
        z.writestr("02.png", page("C page 2 (PNG)", "PNG"))
        z.writestr("03.jpg", page("C page 3"))
    d = os.path.join(base, "D Chapters Manga")
    for c in (1, 2):
        cd = os.path.join(d, "Chapter %d" % c)
        os.makedirs(cd, exist_ok=True)
        for i in range(1, 3):
            open(os.path.join(cd, "%02d.jpg" % i), "wb").write(page("D ch%d p%d" % (c, i)))
    open(os.path.join(d, "cover.jpg"), "wb").write(page("D cover", size=(400, 600), color=(120, 80, 200)))
    print("import fixtures written to", base)


if __name__ == "__main__":
    main()
