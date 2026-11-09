"""Boots Otakio headlessly under LuaJIT with a mocked LuaPlayerPlus Vita API and
drives it with scripted button presses. Any Lua runtime error fails the run.

Usage: python tools/tests/sim.py [scenario] [--lang N] [--keep]
"""
import os, sys, shutil, tempfile, argparse, json
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).replace("\\", "/")

B = {"SELECT": 0x1, "START": 0x8, "UP": 0x10, "RIGHT": 0x20, "DOWN": 0x40, "LEFT": 0x80,
     "L": 0x100, "R": 0x200, "TRIANGLE": 0x1000, "CIRCLE": 0x2000, "CROSS": 0x4000, "SQUARE": 0x8000}


def build_script(steps, start=40, gap=12):
    """steps: list of button names (or ('touch', x, y) or ('wait', n)). Each press lasts 2 frames."""
    script = {}
    f = start
    for s in steps:
        if isinstance(s, tuple) and s[0] == "wait":
            f += s[1]
            continue
        if isinstance(s, tuple) and s[0] == "touch":
            script[f] = {"touch": (s[1], s[2])}
            script[f + 1] = {"touch": (s[1], s[2])}
        else:
            script[f] = {"pad": B[s]}
            script[f + 1] = {"pad": B[s]}
        f += gap
    return script, f + 60


def _stress():
    """Hours of use compressed: scroll a big catalog (many 'load more' pages), open/close many titles,
    then read hundreds of pages across chapters. Run with --online --install <id>; watch the mem@ samples."""
    steps = [("wait", 150), "R", "R", "R", ("wait", 20), "DOWN", "CROSS", ("wait", 400)]
    for _ in range(6):
        for _ in range(40):
            steps += ["DOWN", ("wait", 4)]
        steps += [("wait", 250)]
    for _ in range(8):
        steps += ["CROSS", ("wait", 350), "CIRCLE", ("wait", 40), "UP", "UP", "UP", "RIGHT"]
    steps += ["CROSS", ("wait", 400), "DOWN", "CROSS", ("wait", 500)]
    for _ in range(300):
        steps += ["RIGHT", ("wait", 25)]
    steps += ["CIRCLE", ("wait", 60), "CIRCLE", ("wait", 60)]
    return steps


SCENARIOS = {
    "stress": _stress(),
    # first run with --setup: language, active languages (tick a 2nd one), adult content, direction, orientation,
    # confirm button, theme, then "Install recommended sources"
    "setup": [("wait", 60), "DOWN", "UP", "CROSS", ("wait", 20), "DOWN", "CROSS", "CIRCLE", ("wait", 20), "DOWN", "CROSS", ("wait", 20),
              "CIRCLE", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20),
              "CROSS", ("wait", 40), "CROSS", ("wait", 80)],
    # first run without a connection: "Install recommended sources" can't read the repository (no-connection
    # message), then Extensions > Repositories (Select) still offers it while nothing is installed. With a bundled
    # catalog (test builds) the sources come from it instead
    "setupoffline": [("wait", 60), "DOWN", "UP", "CROSS", ("wait", 20), "DOWN", "CROSS", "CIRCLE", ("wait", 20), "DOWN", "CROSS", ("wait", 20),
                     "CIRCLE", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20),
                     "CROSS", ("wait", 40), "CROSS", ("wait", 80), "SELECT", ("wait", 60), "CROSS", ("wait", 200)],
    # first run (--setup --online, SIM_FAKE_RELEASE) with an app update out: the update prompt must wait for the setup
    # and its recommended sources, then the update keeps the repository and the sources
    "setupupdate": [("wait", 60), "DOWN", "UP", "CROSS", ("wait", 20), "DOWN", "CROSS", "CIRCLE", ("wait", 20), "DOWN", "CROSS", ("wait", 20),
                    "CIRCLE", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20), "CROSS", ("wait", 20),
                    "CROSS", ("wait", 40), "CROSS", ("wait", 1500), "UP", "CROSS", ("wait", 300)],
    # add a Mihon (APK) repository URL: Otakio reports which of its sources have Lua equivalents
    "mihonrepo": [("wait", 150), "R", "R", "R", "R", ("wait", 60), "SELECT", "DOWN", "DOWN", "CROSS", ("wait", 400), "SELECT", ("wait", 30)],
    # needs a data dir from 'browse' (--tmp): library grid, refresh/updates feed, history list, continue reading
    "lib": [("wait", 200), "R", "START", ("wait", 500), "L", ("wait", 200), "DOWN", "START", ("wait", 20), "CIRCLE",
            "SELECT", ("wait", 400), "CIRCLE", ("wait", 60), "R", "R", ("wait", 120), "DOWN", ("wait", 60), "R", "R", "R", "R", "R", ("wait", 60), "CROSS", ("wait", 60)],
    # install a keiyoushi-generated Madara extension through the Extensions screen and read from it
    "madara": [("wait", 150), "R", "R", "R", "R", ("wait", 30), "SQUARE", "TRIANGLE", ("wait", 30), "DOWN", "CROSS", ("wait", 150),
               "L", ("wait", 20), "DOWN", "CROSS", ("wait", 500), "DOWN", "CROSS", ("wait", 600), "DOWN", "CROSS", ("wait", 600),
               "RIGHT", ("wait", 300), "CIRCLE", ("wait", 60), "START", ("wait", 20), "DOWN", "DOWN", "CROSS", ("wait", 30), "CIRCLE", "CIRCLE"],
    # open the first source (installed on first run), browse popular, open a manga, read, global search
    "browse": [("wait", 150), "R", "R", "R", ("wait", 20), "DOWN", "CROSS", ("wait", 400), "DOWN", "RIGHT", "RIGHT", "CROSS", ("wait", 400),
               "DOWN", "CROSS", ("wait", 500), "RIGHT", ("wait", 200), "CIRCLE", ("wait", 60), "TRIANGLE", ("wait", 60), "CIRCLE", ("wait", 60),
               "CIRCLE", "CIRCLE", ("wait", 30), "TRIANGLE", ("wait", 700), "DOWN", "CROSS", ("wait", 300), "CIRCLE", ("wait", 40), "CIRCLE"],
    # walk every tab with R, open dialogs where each screen has them, then go back with L
    "tour": ["R", "START", "CIRCLE", "R", "DOWN", "R", "START", "CIRCLE", "R", "SQUARE", "SQUARE", "START", "CIRCLE",
             "SELECT", "DOWN", "CROSS", ("wait", 20), "CIRCLE", "R", "R", "R", "DOWN", "CROSS", "CIRCLE", "DOWN", "DOWN", "CROSS",
             "DOWN", "CROSS", "CIRCLE", "L", "L", "L", "L", "L", "L", "L", "START", "DOWN", "CROSS", "CIRCLE", "CIRCLE"],
    # install a built-in extension, open Browse, open the source (offline -> empty grid)
    "extensions": ["R", "R", "R", "R", ("wait", 120), "SQUARE", "DOWN", "CROSS", ("wait", 60), "SQUARE", "SQUARE", "DOWN", "CROSS",
                   ("wait", 30), "L", "DOWN", "CROSS", ("wait", 60), "SQUARE", ("wait", 30), "CIRCLE", "CIRCLE", ("wait", 20),
                   "TRIANGLE", ("wait", 120), "DOWN", "CIRCLE"],
    # install a source, then Extensions > Installed > (X) > "Open source" must land on its catalog in Browse
    "opensrc": ["R", "R", "R", "R", ("wait", 120), "SQUARE", "DOWN", "CROSS", ("wait", 90), "SQUARE", "SQUARE", "DOWN",
                "CROSS", ("wait", 20), "CROSS", ("wait", 60)],
    # settings: language picker dialog, pick English, then back to the system language
    "lang": ["R", "R", "R", "R", "R", "R", "R", ("wait", 20), "CROSS", ("wait", 30), "DOWN", ("wait", 30), "CROSS", ("wait", 30),
             "CROSS", ("wait", 30), "UP", "CROSS", ("wait", 30)],
    # Library scroll stress: run with --seed-library 400; fast scrolling down and up through every cover, twice
    "libscroll": [("wait", 120)] + (["DOWN"] * 140 + [("wait", 30)] + ["UP"] * 140 + [("wait", 30)]) * 2
                 + ["RIGHT", "RIGHT", "DOWN"] * 40 + [("wait", 200)],
    # app update: run with --online and SIM_FAKE_RELEASE=<vpk>; accept the startup prompt, install, restart
    "appupdate": [("wait", 150), "UP", "CROSS", ("wait", 500)],
    # same with SIM_SLOW_DL=7200 (a 2-minute download): must finish without being stopped, the progress panel on screen
    "appupdateslow": [("wait", 150), "UP", "CROSS", ("wait", 1200), ("wait", 3600), ("wait", 3600), ("wait", 600)],
    # cancel with Circle while the update downloads (SIM_SLOW_DL=3000)
    "appupdatecancel": [("wait", 150), "UP", "CROSS", ("wait", 600), "CIRCLE", ("wait", 200)],
    # More > About: version row and the credits card (scrolled into view)
    "about": ["R", "R", "R", "R", "R", "R", "R", ("wait", 20)] + ["DOWN"] * 11 + ["CROSS", ("wait", 60)],
    # online: add a manga from an installed source, More > Data > create backup, clear library, restore it
    "backup": [("wait", 150), "R", "R", "R", ("wait", 20), "DOWN", "CROSS", ("wait", 500), "DOWN", "START", ("wait", 30), "RIGHT",
               "START", ("wait", 30), "CIRCLE", ("wait", 20), "R", "R", "R", "R", ("wait", 20)] + ["DOWN"] * 8 +
              ["CROSS", ("wait", 20), "DOWN", "CROSS", ("wait", 60), "DOWN", "DOWN", "DOWN", "CROSS", ("wait", 30),
               "UP", "UP", "CROSS", ("wait", 20), "CROSS", ("wait", 20), "UP", "CROSS", ("wait", 200),
               "CIRCLE", "L", "L", "L", "L", "L", "L", "L", ("wait", 60)],
    # clean install with only a .otk in ux0:data/otakio/backups: More > Data > Restore backup, back to the Library
    "restore": ["R", "R", "R", "R", "R", "R", "R", ("wait", 20)] + ["DOWN"] * 8 +
               ["CROSS", ("wait", 20), "DOWN", "DOWN", "CROSS", ("wait", 20), "CROSS", ("wait", 20), "UP", "CROSS", ("wait", 400),
                "CIRCLE", "L", "L", "L", "L", "L", "L", "L", ("wait", 120)],
    # needs a prepared ux0:data/otakio/import (--tmp): import 4 items with Square, open the Library, read the first manga
    "import": ["R", "R", "R", "R", "R", "R", ("wait", 30), "DOWN", "SQUARE", ("wait", 60), "DOWN", "DOWN", "SQUARE", ("wait", 60),
               "DOWN", "DOWN", "DOWN", "SQUARE", ("wait", 60), "DOWN", "DOWN", "DOWN", "DOWN", "SQUARE", ("wait", 120),
               "L", "L", "L", "L", "L", "L", ("wait", 60)],
    # after 'import' (same --tmp): open the 2nd imported manga, read its first chapter and turn a page
    "importread": [("wait", 30), "DOWN", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", ("wait", 200), "RIGHT", ("wait", 100)],
    # needs a library (--tmp): Triangle refreshes it online, then the Updates tab shows what was found
    "refresh": [("wait", 60), "TRIANGLE", ("wait", 900), "R", ("wait", 60)],
    # an installed extension older than the catalog: startup notice, Extensions > Updates tab, update it
    "extupdate": [("wait", 150), "R", "R", "R", "R", ("wait", 30), "SQUARE", "SQUARE", ("wait", 30), "DOWN", "CROSS", ("wait", 30),
                  "CROSS", ("wait", 120)],
    # Downloads tab of an existing data dir (--tmp)
    "downloads": ["R", "R", "R", "R", "R", ("wait", 120)],
    # after 'dlcover' (same --tmp): Downloads views with Square (Downloaded -> History -> Queue -> Downloaded), Start on
    # a downloaded manga lists its chapters, then History > Triangle clears it (the chapter stays downloaded)
    "dlviews": ["R", "R", "R", "R", "R", ("wait", 60), "SQUARE", ("wait", 40), "SQUARE", ("wait", 40), "SQUARE", ("wait", 40),
                "DOWN", "START", ("wait", 40), "CIRCLE", ("wait", 20), "SQUARE", ("wait", 20), "TRIANGLE", ("wait", 20), "UP", "CROSS", ("wait", 60),
                "SQUARE", "SQUARE", ("wait", 60)],
    # More > Theme: the picker shows color chips; moving the cursor previews the theme, Circle restores the one in use
    "themepick": ["R", "R", "R", "R", "R", "R", "R", ("wait", 20), "DOWN", "DOWN", "CROSS", ("wait", 30), "DOWN", "DOWN", ("wait", 30),
                  "CIRCLE", ("wait", 30)],
    # after 'import': Select opens the reader settings while the chapter is still loading and again on a page;
    # Circle closes only the sheet (the reader stays open)
    "readerselect": [("wait", 30), "DOWN", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", "SELECT", ("wait", 30), "CIRCLE",
                     ("wait", 200), "SELECT", ("wait", 30), "CIRCLE", ("wait", 40)],
    # every tab in turn (Library ... More), 60 frames each: screenshots for UI consistency checks
    "alltabs": [("wait", 60)] + ["DOWN", ("wait", 30), "R", ("wait", 60)] * 7 + ["DOWN", ("wait", 30)],
    # Browse with sources in two languages but only one active: Start cycles only the active languages
    "browselang": [("wait", 150), "R", "R", "R", ("wait", 40), "START", ("wait", 30), "START", ("wait", 30), "START", ("wait", 30)],
    # adaptive clocks: idle for 6+ s (default clocks), a button (fast), idle again (default)
    "idleclock": [("wait", 500), "DOWN", ("wait", 60), ("wait", 400)],
    # empty Import tab (help text)
    "importempty": ["R", "R", "R", "R", "R", "R", ("wait", 40)],
    # online: open a manga, download a chapter (Square), then the Downloads tab lists it with its cover
    "dlcover": [("wait", 150), "R", "R", "R", ("wait", 20), "DOWN", "CROSS", ("wait", 500), "DOWN", "CROSS", ("wait", 400),
                "DOWN", "SQUARE", ("wait", 700), "CIRCLE", ("wait", 40), "R", "R", ("wait", 120)],
    # after 'import' (same --tmp): read the 2nd imported manga, reader menu (Start + top-right icon) > Save image
    "saveimage": [("wait", 30), "DOWN", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", ("wait", 200), "START", ("wait", 40),
                  ("touch", 930, 40), ("wait", 30), "UP", "CROSS", ("wait", 60)],
    # after 'import': reader sheet (menu icon): background Black, brightness 85%, color filter on (Warm), then the
    # Night preset (Multiply), close; shots at 330 (sheet), 345 (Night) and 380 (closed, filtered page)
    "readercolors": [("wait", 30), "DOWN", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", ("wait", 200), "START", ("wait", 40),
                     ("touch", 930, 40), ("wait", 30), "DOWN", "DOWN", "DOWN", "RIGHT", "DOWN", "LEFT", "LEFT", "LEFT",
                     "DOWN", "CROSS", ("wait", 10), "DOWN", "RIGHT", ("wait", 10), "CIRCLE", ("wait", 60)],
    # after 'import': 3rd imported manga, page 2 is a PNG -> "Save image" must write a JPEG
    "savepng": [("wait", 30), "DOWN", "RIGHT", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", ("wait", 200), "RIGHT", ("wait", 80),
                "START", ("wait", 40), ("touch", 930, 40), ("wait", 30), "UP", "CROSS", ("wait", 60)],
    # Extensions > Available with every language chip, then the Downloads tab
    "extlang": ["R", "R", "R", "R", ("wait", 120), "SQUARE", ("wait", 30), "START", "START", "START", "START", ("wait", 30),
                "L", "L", "L", ("wait", 30)],
    # settings: theme dialog, categories, backup create/restore
    "settings": ["L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "DOWN", "DOWN", "CROSS", "DOWN", "CROSS", ("wait", 10),
                 "DOWN", "DOWN", "DOWN", "CROSS", ("wait", 10), "CROSS", ("wait", 20), "CIRCLE", "CIRCLE",
                 "DOWN", "DOWN", "DOWN", "DOWN", "DOWN", "CROSS", "CROSS", ("wait", 10), "DOWN", "CROSS", ("wait", 10), "CROSS", ("wait", 10), "CIRCLE",
                 "UP", "UP", "UP", "UP", "UP", "UP", "UP", "UP", "UP", "UP", "UP", "CROSS", "DOWN", "DOWN", "CROSS", "CIRCLE"],
}


class FS:
    def isfile(self, p):
        return os.path.isfile(p)

    def isdir(self, p):
        return os.path.isdir(p.rstrip("/") or "/")

    def mkdir(self, p):
        os.makedirs(p, exist_ok=True)

    def remove(self, p):
        if os.path.isfile(p):
            os.remove(p)

    def rmdir(self, p):
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)

    def listzip(self, p):
        import zipfile
        try:
            with zipfile.ZipFile(p) as z:
                return "\n".join(n for n in z.namelist() if not n.endswith("/"))
        except Exception:
            return ""

    def extract(self, zpath, name, dst):
        # stands in for System.extractFromZip(Async): one member of a zip/cbz to a file
        import zipfile
        try:
            with zipfile.ZipFile(zpath) as z:
                data = z.read(name)
            with open(dst, "wb") as fh:
                fh.write(data)
            return True
        except Exception:
            return False

    def extractall(self, zpath, dst):
        # stands in for System.extractZipAsync, with lpp-vita's behavior: entries in zip order, folders created only
        # from their own "dir/" entries, and a file whose folder is missing crashes the app (NULL FILE* write)
        import zipfile
        with zipfile.ZipFile(zpath) as z:
            for info in z.infolist():
                out = os.path.join(dst, info.filename)
                if info.filename.endswith("/"):
                    os.makedirs(out, exist_ok=True)
                    continue
                if not os.path.isdir(os.path.dirname(out)):
                    raise RuntimeError("lpp-vita extractor crash: no folder for " + info.filename)
                with open(out, "wb") as fh:
                    fh.write(z.read(info))
        return True

    def promote(self, pkg, app_root, running):
        # stands in for System.installApp (the system promoter): installs the package under ux0:app/<TITLE_ID>.
        # Like on the console, the title that is running can't be replaced (the promoter still reports success).
        import struct
        sfo_path = os.path.join(pkg, "sce_sys", "param.sfo")
        if not os.path.isfile(sfo_path):
            return False
        d = open(sfo_path, "rb").read()
        ks, ds, n = struct.unpack_from("<III", d, 8)
        title = None
        for i in range(n):
            ko, fmt, ln, mx, do = struct.unpack_from("<HHIII", d, 20 + i * 16)
            if d[ks + ko:d.index(b"\0", ks + ko)] == b"TITLE_ID":
                title = d[ds + do:ds + do + ln].rstrip(b"\0").decode()
        if not title or title == running:
            return True
        app_dir = os.path.join(app_root, title)
        shutil.rmtree(app_dir, ignore_errors=True)
        shutil.copytree(pkg, app_dir)
        return True

    def convert(self, src, dst, fmt):
        # stands in for the engine's System.convertImage (JPEG/PNG/WebP -> JPEG/PNG/WebP)
        try:
            from PIL import Image
            Image.open(src).convert("RGB").save(dst, {"png": "PNG", "webp": "WEBP"}.get(fmt, "JPEG"), quality=92)
            return True
        except Exception:
            return False

    def rename(self, a, b):
        if os.path.exists(b):
            os.remove(b)
        os.rename(a, b)


def seed_library(data_dir, n):
    """Library stress fixture: save.dat with n manga and a JPEG cover (varied sizes) for each one"""
    import random
    from PIL import Image, ImageDraw
    rnd = random.Random(7)
    os.makedirs(data_dir, exist_ok=True)
    rows = []
    for i in range(1, n + 1):
        link = "stress%04d" % i
        key = "STRESS" + link  # Cache.getKey: ParserID .. Link without punctuation
        cover_dir = os.path.join(data_dir, "cache", key)
        os.makedirs(cover_dir, exist_ok=True)
        w = rnd.choice([200, 300, 450, 720])
        h = int(w * rnd.choice([1.4, 1.5, 1.6]))
        img = Image.new("RGB", (w, h), (rnd.randrange(40, 220), rnd.randrange(40, 220), rnd.randrange(40, 220)))
        ImageDraw.Draw(img).text((10, 10), str(i), fill=(255, 255, 255))
        img.save(os.path.join(cover_dir, "cover.image"), "JPEG", quality=80)
        rows.append('{Name = "Stress manga %d %s", Link = "%s", ImageLink = "", ParserID = "STRESS", RawLink = "", '
                    'BrowserLink = "", Path = "cache/%s/cover.image", Location = "ux0", Categories = {}, DateAdded = %d}'
                    % (i, "long title " * (i % 4), link, key, 1700000000 + i))
    body = "return {" + ",\n".join(rows) + "}"
    open(os.path.join(data_dir, "save.dat"), "w", encoding="utf-8").write(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", nargs="?", default="tour")
    ap.add_argument("--lang", type=int, default=1, help="System language id (1=English, 17=pt-BR)")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--online", action="store_true", help="perform real HTTP requests")
    ap.add_argument("--tls12", action="store_true", help="emulate the old NOBORU engine (TLS 1.2 only)")
    ap.add_argument("--skip-starter", action="store_true", help="don't auto-install the first-run extensions")
    ap.add_argument("--setup", action="store_true", help="show the first-run setup wizard (skipped by default)")
    ap.add_argument("--inject-error", type=int, default=0, help="raise a Lua error inside Menu.update at this frame (tests the error barrier)")
    ap.add_argument("--install", default="", help="comma separated extension ids to install on first frame")
    ap.add_argument("--keyboard", default="one piece")
    ap.add_argument("--shots", default="", help="comma separated frame numbers to screenshot")
    ap.add_argument("--outdir", default=os.path.join(ROOT, "tools", "tests", "screens"))
    ap.add_argument("--tmp", default=None)
    ap.add_argument("--seed-library", type=int, default=0, help="start with N manga in the Library, each with a real JPEG cover")
    args = ap.parse_args()

    tmp = args.tmp or tempfile.mkdtemp(prefix="otakio_sim_")
    os.makedirs(os.path.join(tmp, "ux0", "data"), exist_ok=True)
    if args.seed_library:
        seed_library(os.path.join(tmp, "ux0", "data", "otakio"), args.seed_library)
    if not args.setup:
        os.makedirs(os.path.join(tmp, "ux0", "data", "otakio"), exist_ok=True)
        open(os.path.join(tmp, "ux0", "data", "otakio", ".setup_done"), "w").write("sim")
    if args.skip_starter:
        os.makedirs(os.path.join(tmp, "ux0", "data", "otakio"), exist_ok=True)
        open(os.path.join(tmp, "ux0", "data", "otakio", ".firstrun_v2"), "w").write("sim")
    tmp = tmp.replace("\\", "/")
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    L.execute("string.rawsub = nil")
    mock = L.eval("function(path, root, tmp) local f = assert(loadfile(path)); f(root, tmp) end")
    fs = FS()

    def listdir(p):
        if not os.path.isdir(p):
            return None
        out = []
        for name in sorted(os.listdir(p)):
            full = os.path.join(p, name)
            out.append(L.table_from({"name": name, "directory": os.path.isdir(full), "size": os.path.getsize(full) if os.path.isfile(full) else 0}))
        return L.table_from(out)

    # SIM table must exist before the mock body runs, so pass fs via a global first
    L.globals().PYFS = L.table_from({
        "isfile": fs.isfile, "isdir": fs.isdir, "mkdir": fs.mkdir, "remove": fs.remove,
        "rmdir": fs.rmdir, "rename": fs.rename, "listdir": listdir, "listzip": fs.listzip, "convert": fs.convert, "extract": fs.extract,
        "extractall": fs.extractall, "promote": fs.promote,
    })
    mock(ROOT + "/tools/tests/vita_mock.lua", ROOT, tmp)
    sim = L.globals().SIM
    sim.fs = L.globals().PYFS
    sim.installFails = bool(os.environ.get("SIM_INSTALL_FAILS"))  # app update test: the promoter does nothing
    if os.environ.get("SIM_SLOW_DL"):  # app update test: the .vpk download takes this many frames (16.7 ms each)
        sim.slowFrames = int(os.environ["SIM_SLOW_DL"])
    if os.environ.get("SIM_STALL_AT"):  # ...and its bytes stop arriving at this fraction (0-1)
        sim.stallAt = float(os.environ["SIM_STALL_AT"])
    sim.language = args.lang
    sim.keyboardText = args.keyboard
    if args.install:
        sim.install = L.table_from(args.install.split(","))
    if args.inject_error:
        sim.injectError = args.inject_error
    if os.environ.get("SIM_CONN_LOST"):
        sim.showConnLost = int(os.environ["SIM_CONN_LOST"])
    sys.path.insert(0, os.path.join(ROOT, "tools", "tests"))
    import render
    sim.textWidth = lambda size, bold, text: render.text_width(size, bold, text)
    import time as _t3
    MOCKSTATS = {"s": 0.0}
    globals()["MOCKSTATS"] = MOCKSTATS
    def _image_size(path):
        # PIL decode only emulates what the Vita does in its loader thread: keep it out of the frame time
        t = _t3.perf_counter()
        try:
            return render.image_size(path) if os.path.isfile(path) else (None, None)
        finally:
            MOCKSTATS["s"] += _t3.perf_counter() - t
    sim.imageSize = _image_size
    sim.onImageLoad = lambda img_id, path: render.snapshot(img_id, path) if args.shots and os.path.isfile(path) else None
    if args.shots:
        os.makedirs(args.outdir, exist_ok=True)
        frames_wanted = [int(x) for x in args.shots.split(",") if x.strip()]
        sim.capture = L.table_from({f: True for f in frames_wanted})

        def on_capture(frame, ops):
            plain = [list(op.values()) for op in ops.values()]
            out = os.path.join(args.outdir, f"{args.scenario}_{frame:05d}.png")
            render.render(plain, out)
            print("   screenshot:", out)
        sim.onCapture = on_capture
    if args.online:
        import urllib.request, urllib.error, ssl
        sys.path.insert(0, os.path.join(ROOT, "tools"))
        if args.tls12:
            from lua_engine import _ctx as ctx  # TLS 1.2 / OpenSSL 1.0.2 ciphers, like the old engine
        else:
            ctx = ssl.create_default_context()  # Otakio engine: curl 8 + OpenSSL 1.1.1 (TLS 1.3), no CA bundle
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
        stats = {"req": 0, "bytes": 0}

        def fetch(url, method=None, post=None, ctype=None, headers=(), ua=None):
            url = url.replace("%%", "%")  # lpp-vita un-escapes doubled percent signs
            fake = os.environ.get("SIM_FAKE_RELEASE")
            if fake:
                # app update test: a fake "latest release" serving a local VPK (SIM_FAKE_RELEASE=path, tag v9.9.9)
                if "api.github.com/repos/" in url and url.endswith("/releases/latest"):
                    return json.dumps({"tag_name": "v9.9.9", "assets": [{"name": "Otakio-9.9.9.vpk", "size": os.path.getsize(fake),
                                       "browser_download_url": "https://example.invalid/Otakio-9.9.9.vpk"}]}).encode()
                if url == "https://example.invalid/Otakio-9.9.9.vpk":
                    data = open(fake, "rb").read()
                    if os.environ.get("SIM_FAKE_TRUNCATE"):
                        data = data[: len(data) // 2]
                    return data
            if not url and os.environ.get("SIM_TRACE_EMPTY"):
                print("   EMPTY URL at frame", L.eval("SIM.frame"), L.eval("SIM.dumpTask()"), flush=True)
                os._exit(3)
            # the patched engine sends the user agent chosen by the Lua side
            h = {"User-Agent": ua if (ua and not args.tls12) else UA}
            for line in headers:
                if line and ":" in line:
                    k, v = line.split(":", 1)
                    h[k.strip()] = v.strip()
            data = None
            if method == 1:
                data = (post or "").encode()
                h["Content-Type"] = "application/json" if ctype == 1 else "application/x-www-form-urlencoded"
            try:
                req = urllib.request.Request(url, data=data, headers=h)
                with urllib.request.urlopen(req, timeout=20, context=ctx) as r:
                    body = r.read()
            except urllib.error.HTTPError as e:
                # like libcurl on the Vita: error pages still return their body
                print("   HTTP", e.code, url)
                body = e.read()
            except Exception as e:
                print("   HTTP ERR", url, e)
                body = b""
            stats["req"] += 1
            stats["bytes"] += len(body)
            if os.environ.get("SIM_HTTP_LOG"):
                print("   GET", len(body), url[:400], flush=True)
            return body

        def http(url, ua=None, method=None, post=None, ctype=None, cookie=None, h1=None, h2=None, h3=None, h4=None, *rest):
            body = fetch(url, method, post, ctype, (h1, h2, h3, h4), ua).decode("utf8", "replace")
            # lpp-vita returns string responses with their C terminator (NUL) appended
            return body + chr(0) if body else body

        def download(url, path, ua=None, method=None, post=None, ctype=None, cookie=None, h1=None, h2=None, h3=None, h4=None, *rest):
            body = fetch(url, method, post, ctype, (h1, h2, h3, h4), ua)
            if body:
                with open(path, "wb") as fh:
                    fh.write(body)
        sim.wifi = True
        import time as _time
        def _timed(fn):
            def g(*a):
                t = _time.perf_counter()
                try:
                    return fn(*a)
                finally:
                    stats["net_s"] = stats.get("net_s", 0.0) + _time.perf_counter() - t
            return g
        sim.http = _timed(http)
        sim.download = _timed(download)
        sim.netstats = L.table_from(stats)
        globals()["NETSTATS"] = stats
    steps = SCENARIOS[args.scenario]
    script, frames = build_script(steps)
    lua_script = L.table_from({k: L.table_from({kk: (L.table_from(list(vv)) if isinstance(vv, tuple) else vv) for kk, vv in v.items()}) for k, v in script.items()})
    sim.script = lua_script
    sim.maxFrames = frames
    import time as _t2
    sim.now = _t2.perf_counter
    sim.netSeconds = lambda: (globals().get("NETSTATS") or {}).get("net_s", 0.0) + globals()["MOCKSTATS"]["s"]
    L.execute("""
        SIM.worst = {}
        -- sampling profiler: every N VM instructions remember where the app is; slow frames keep their samples
        local dbg = debug
        SIM.samples = {}
        dbg.sethook(function()
            local info = dbg.getinfo(2, "Sl")
            local where = info and (info.short_src:match("[^/]+$") or "?") .. ":" .. tostring(info.currentline) or "?"
            -- the first app frame above the hook tells which function is busy
            for level = 2, 12 do
                local i2 = dbg.getinfo(level, "Sln")
                if not i2 then break end
                if i2.short_src:find("assets/libs") or i2.short_src:find("main.lua") or i2.short_src:find("extensions/") then
                    where = (i2.short_src:match("[^/]+$") or "?") .. ":" .. tostring(i2.currentline) .. " " .. tostring(i2.name)
                    break
                end
            end
            SIM.samples[#SIM.samples + 1] = where
        end, "", 20000)
        SIM.onFrame = function(frame)
            -- frame time without the (synchronous, simulated) network: the Lua work the Vita would really do
            local t, net = SIM.now(), SIM.netSeconds()
            if SIM.lastT then
                local dt = (t - SIM.lastT) - (net - SIM.lastNet)
                if dt > 0.05 then
                    local count = {}
                    for _, w in ipairs(SIM.samples) do count[w] = (count[w] or 0) + 1 end
                    local top = {}
                    for w, n in pairs(count) do top[#top + 1] = {w, n} end
                    table.sort(top, function(a, b) return a[2] > b[2] end)
                    local hot = {}
                    for k = 1, math.min(3, #top) do hot[#hot + 1] = top[k][1] .. " x" .. top[k][2] end
                    SIM.worst[#SIM.worst + 1] = {dt, frame, tostring(Menu and Menu.getMode and Menu.getMode()) .. "/" .. tostring(AppMode) .. " [" .. table.concat(hot, "; ") .. "]"}
                end
            end
            SIM.lastT, SIM.lastNet = t, net
            SIM.samples = {}
            -- memory: Lua heap and GPU textures (current and peak)
            local kb = collectgarbage("count")
            if kb > (SIM.peakLua or 0) then SIM.peakLua = kb end
            local gpu = GetGPUMemoryUsed and GetGPUMemoryUsed() or 0
            if gpu > (SIM.peakGpu or 0) then SIM.peakGpu = gpu end
            -- profile suspected heavy functions once the app is loaded: log calls slower than 20 ms (PC time)
            if not SIM.profiled and Menu and Cache and Details then
                SIM.profiled = true
                local targets = {
                    {Cache, "Cache", {"saveChapters", "save", "loadChapters", "addManga", "saveBookmarks", "makeHistory"}},
                    {Database, "Database", {"save", "add", "remove"}},
                    {ChapterSaver, "ChapterSaver", {"save", "load"}},
                    {Details, "Details", {"setManga"}},
                    {Html, "Html", {"parse"}},
                    {Json, "Json", {"decode", "encode"}},
                    {SourceStatus, "SourceStatus", {"save"}},
                }
                for _, t in ipairs(targets) do
                    local tbl, tname, fns = t[1], t[2], t[3]
                    if tbl then
                        for _, fname in ipairs(fns) do
                            local orig = tbl[fname]
                            if type(orig) == "function" then
                                tbl[fname] = function(...)
                                    local t0, n0 = SIM.now(), SIM.netSeconds()
                                    local r = {orig(...)}
                                    local dt = (SIM.now() - t0) - (SIM.netSeconds() - n0)
                                    if dt > 0.005 then
                                        SIM.slow = SIM.slow or {}
                                        local key = tname .. "." .. fname
                                        local e = SIM.slow[key] or {n = 0, total = 0, max = 0}
                                        e.n, e.total, e.max = e.n + 1, e.total + dt, math.max(e.max, dt)
                                        SIM.slow[key] = e
                                    end
                                    return unpack(r)
                                end
                            end
                        end
                    end
                end
            end
            if SIM.injectError and frame == SIM.injectError and Menu then
                local orig = Menu.update
                Menu.update = function(...)
                    Menu.update = orig
                    error("injected test error")
                end
                SIM.log[#SIM.log + 1] = "inject@" .. frame
            end
            if SIM.showConnLost and frame == SIM.showConnLost and ConnectMessage then
                ConnectMessage.show() -- the "connection lost" card (SIM_CONN_LOST=<frame>)
            end
            if frame == 30 and SIM.install then
                Backup.pendingExtensions = SIM.install
                Extensions.refresh(true)
            end
            if Menu and Menu.getMode and not SIM.hooked and Notifications then
                SIM.hooked = true
                local push = Notifications.push
                Notifications.push = function(msg, ms)
                    SIM.log[#SIM.log + 1] = "notify@" .. frame .. ": " .. (tostring(msg):gsub("%c", " / "))
                    return push(msg, ms)
                end
                local pushUnique = Notifications.pushUnique
                Notifications.pushUnique = function(msg, ms)
                    SIM.log[#SIM.log + 1] = "notify@" .. frame .. ": " .. (tostring(msg):gsub("%c", " / "))
                    return pushUnique(msg, ms)
                end
                local rl = Reader.load
                Reader.load = function(chapters, num)
                    SIM.log[#SIM.log + 1] = "Reader.load(" .. #chapters .. " chapters, " .. tostring(num) .. ")"
                    return rl(chapters, num)
                end
                local ds = Details.setManga
                Details.setManga = function(m)
                    SIM.log[#SIM.log + 1] = "Details.setManga(" .. tostring(m and m.Name)  .. ") cached=" .. tostring(Cache.isCached(m)) .. " chapters=" .. #Cache.loadChapters(m, true)
                    return ds(m)
                end
                for _, name in ipairs({"menu", "choice", "checklist", "confirm"}) do
                    local orig = Dialog[name]
                    Dialog[name] = function(title, ...)
                        SIM.log[#SIM.log + 1] = "dialog@" .. frame .. ": " .. name .. " '" .. tostring(title) .. "'"
                        return orig(title, ...)
                    end
                end
            end
            if AppMode ~= SIM.lastApp then
                SIM.lastApp = AppMode
                SIM.log[#SIM.log + 1] = "appmode@" .. frame .. ": " .. tostring(AppMode == 1 and "READER" or "MENU")
            end
            if frame % 1000 == 0 then
                SIM.log[#SIM.log + 1] = string.format("mem@%d: lua=%dKB gpu=%dKB threads=%d mode=%s", frame, collectgarbage("count"),
                    math.floor((GetGPUMemoryUsed and GetGPUMemoryUsed() or 0) / 1024), Threads.getTasksNum(), tostring(Menu and Menu.getMode and Menu.getMode()))
            end
            if AppMode == 1 and frame % 100 == 0 then
                local pf = PYFS.listdir(SIM.mapPath("ux0:data/otakio/temp/prefetch")) or {}
                SIM.log[#SIM.log + 1] = "reader@" .. frame .. ": threads=" .. Threads.getTasksNum() .. " prefetched=" .. #pf .. " gpu=" .. math.floor(GetGPUMemoryUsed() / 1024) .. "KB"
            end
            if Menu and Menu.getMode then
                local m = tostring(Menu.getMode()) .. (Catalogs.getStatus and ("/" .. tostring(Catalogs.getStatus())) or "")
                if m ~= SIM.lastMode then
                    SIM.lastMode = m
                    SIM.log[#SIM.log + 1] = "mode@" .. frame .. ": " .. m
                end
            end
        end
    """)
    run = L.eval("""function()
        local ok, err = xpcall(function() dofile("app0:index.lua") end, debug.traceback)
        return ok, err
    end""")
    ok, err = run()
    if not ok and "SIM_DONE" not in str(err):
        print("FAILED at frame", sim.frame)
        print(err)
        sys.exit(1)
    if args.online:
        print("   network:", NETSTATS)
    print(f"scenario '{args.scenario}' OK: {sim.frame} frames, {sim.draws} rect draws")
    worst = sorted([tuple(w.values()) for w in sim.worst.values()], key=lambda w: -w[0])[:6]
    NL = chr(10) + " " * 6
    if worst:
        print("   worst frames (s, frame, mode [hot spots]):" + NL + NL.join("%.2f@%d %s" % (w[0], w[1], w[2]) for w in worst))
    else:
        print("   worst frames: none > 50 ms")
    slow = sim.slow
    if slow:
        items = sorted(((k, v.n, v.total, v.max) for k, v in slow.items()), key=lambda x: -x[2])
        print("   slow calls (>5 ms PC, ~150 ms Vita): " + ", ".join("%s x%d max %.2fs" % (k, n, mx) for k, n, tot, mx in items))
    print("   memory: lua now %.0f KB, lua peak %.0f KB, textures peak %.0f KB" % (L.eval('collectgarbage("count")'), sim.peakLua or 0, (sim.peakGpu or 0) / 1024))
    for line in list(sim.log.values()):
        print("  ", line)
    ext = os.path.join(tmp, "ux0", "data", "otakio", "extensions")
    if os.path.isdir(ext):
        print("   installed extension files:", os.listdir(ext))
    if L.eval("SIM.installedFrom") or L.eval("SIM.launched") or L.eval("SIM.exited"):
        print("   app update: installApp(%s) launchApp(%s) exit=%s" % (L.eval("SIM.installedFrom"), L.eval("SIM.launched"), L.eval("SIM.exited")))
    if L.eval("SIM.cpuLog"):
        print("   cpu clock changes:", L.eval("SIM.cpuLog"))
    if L.eval("SIM.dlStarts"):
        print("   app update: vpk download started %s time(s), stopped %s time(s)" % (L.eval("SIM.dlStarts"), L.eval("SIM.stopped or 0")))
    if not args.keep and not args.tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    else:
        print("data dir:", tmp)


if __name__ == "__main__":
    main()
