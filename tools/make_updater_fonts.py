"""Makes the fonts of Otakio Updater (source/updater/regular.ttf, bold.ttf): the app's own Roboto, cut down to the
Latin characters the updater's English screens use (about 22 KB each instead of 13 MB, so installing the helper stays
quick). Run again only if the app fonts change. Needs: pip install uharfbuzz

  python tools/make_updater_fonts.py
"""
import os
import uharfbuzz as hb

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHARS = [chr(c) for c in range(0x20, 0x7F)] + list("…·—–’“”•✓")

for src, dst in (("roboto.ttf", "regular.ttf"), ("robboto.ttf", "bold.ttf")):
    face = hb.Face(hb.Blob.from_file_path(os.path.join(ROOT, "source", src)))
    subset_input = hb.SubsetInput()
    for ch in CHARS:
        subset_input.unicode_set.add(ord(ch))
    data = hb.subset(face, subset_input).blob.data
    path = os.path.join(ROOT, "source", "updater", dst)
    with open(path, "wb") as f:
        f.write(data)
    print(path, len(data), "bytes")
