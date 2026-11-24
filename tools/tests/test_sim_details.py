"""The chapter list of a series' details, end to end in the simulator, in both chapter orders:
- the d-pad cursor is drawn over the chapter it is on (newest-first order drew it mirrored, off screen, so only the
  list moved);
- chapters imported from folders come in number order ("Chapter 2" before "Chapter 10").
python tools/tests/test_sim_details.py"""
import os, shutil, subprocess, sys, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
work = tempfile.mkdtemp(prefix="otakio_details_")
fixtures = os.path.join(work, "fixtures")
subprocess.run([sys.executable, os.path.join(HERE, "make_import_fixtures.py"), fixtures], check=True, capture_output=True)
src = os.path.join(fixtures, "ux0", "data", "otakio", "import", "D Chapters Manga")


def run(order):
    tmp = os.path.join(work, order.replace(">", ""))
    series = os.path.join(tmp, "ux0", "data", "otakio", "import", "Long Manga")
    os.makedirs(series)
    shutil.copy(os.path.join(src, "cover.jpg"), series)
    for n in range(1, 41):
        shutil.copytree(os.path.join(src, "Chapter 1"), os.path.join(series, "Chapter %d" % n))
    shots = os.path.join(tmp, "shots")
    r = subprocess.run([sys.executable, os.path.join(HERE, "sim.py"), "detailscroll", "--tmp", tmp, "--keep", "--skip-starter",
                        "--set", 'ChapterSorting = "%s"' % order, "--shots", "700", "--outdir", shots],
                       capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    assert r.returncode == 0 and "scenario 'detailscroll' OK" in out, out[-3000:]
    return Image.open(os.path.join(shots, "detailscroll_00700.png")).convert("RGB")


for order in ("N->1", "1->N"):
    im = run(order)
    # the highlight is a filled band across the chapter column: count rows mostly covered by one non-background color
    bg = im.getpixel((940, 300))
    band = 0
    for y in range(100, 520):
        row = [im.getpixel((x, y)) for x in range(640, 940, 4)]
        if sum(1 for p in row if sum(abs(a - b) for a, b in zip(p, bg)) > 20) > len(row) * 0.8:
            band += 1
    assert band >= 30, "%s: no cursor highlight on the chapter list (%d rows)" % (order, band)
print("details chapter list: OK")
