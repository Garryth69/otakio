"""Touch input, end to end in the simulator:
- a tap that lasts a single frame (a quick tap while the app is busy loading covers) still opens the row under it;
  lists used to wait for the finger on two frames in a row, and lost it;
- a finger kept on a hint of the bottom bar presses its button once, and touch works again once it lifts.
python tools/tests/test_sim_touch.py"""
import glob, os, subprocess, sys, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
work = tempfile.mkdtemp(prefix="otakio_touch_")


def sim(scenario, *extra):
    r = subprocess.run([sys.executable, os.path.join(HERE, "sim.py"), scenario, "--outdir", work] + list(extra),
                       capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    assert r.returncode == 0 and "scenario '%s' OK" % scenario in out, out[-3000:]
    return out


# More > a one-frame tap on the Theme row: the theme picker is open (its card covers the dark background)
sim("quicktap", "--shots", "250")
im = Image.open(os.path.join(work, "quicktap_00250.png")).convert("RGB")
p = im.getpixel((480, 87))
assert sum(p) > 90, "a one-frame tap was lost (pixel %s, picker not open)" % (p,)

# R hint held for 200 frames: one step (Library -> Updates), then rail taps: Library, then the row at y 300
out = sim("hinthold", "--keep")
data = out.split("data dir:")[-1].split()[0]
screens = []
for log in glob.glob(os.path.join(data, "**", "log.txt"), recursive=True):
    with open(log, encoding="utf-8", errors="replace") as fh:
        screens += [l.split("> screen: ")[1].strip() for l in fh if "> screen: " in l]
assert screens == ["LIBRARY", "UPDATES", "LIBRARY", "EXTENSIONS"], screens
print("touch tests OK")
