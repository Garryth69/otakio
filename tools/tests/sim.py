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


SCENARIOS = {
    # add a Mihon (APK) repository URL: Otakio reports which of its sources have Lua equivalents
    "mihonrepo": [("wait", 150), "R", "R", "R", "R", ("wait", 60), "SELECT", "DOWN", "DOWN", "CROSS", ("wait", 400), "SELECT", ("wait", 30)],
    # needs a data dir from 'browse' (--tmp): library grid, refresh/updates feed, history list, continue reading
    "lib": [("wait", 200), "R", "START", ("wait", 500), "L", ("wait", 200), "DOWN", "START", ("wait", 20), "CIRCLE",
            "SELECT", ("wait", 400), "CIRCLE", ("wait", 60), "R", "R", ("wait", 120), "DOWN", ("wait", 60), "R", "R", "R", "R", "R", ("wait", 60), "CROSS", ("wait", 60)],
    # install a keiyoushi-generated Madara extension through the Extensions screen and read from it
    "madara": [("wait", 150), "R", "R", "R", "R", ("wait", 30), "SQUARE", "TRIANGLE", ("wait", 30), "DOWN", "CROSS", ("wait", 150),
               "L", ("wait", 20), "DOWN", "CROSS", ("wait", 500), "DOWN", "CROSS", ("wait", 600), "DOWN", "CROSS", ("wait", 600),
               "RIGHT", ("wait", 300), "CIRCLE", ("wait", 60), "START", ("wait", 20), "DOWN", "DOWN", "CROSS", ("wait", 30), "CIRCLE", "CIRCLE"],
    # open MangaDex (installed on first run), browse popular, open a manga, read, global search
    "browse": [("wait", 150), "R", "R", "R", ("wait", 20), "DOWN", "CROSS", ("wait", 400), "DOWN", "RIGHT", "RIGHT", "CROSS", ("wait", 400),
               "DOWN", "CROSS", ("wait", 500), "RIGHT", ("wait", 200), "CIRCLE", ("wait", 60), "TRIANGLE", ("wait", 60), "CIRCLE", ("wait", 60),
               "CIRCLE", "CIRCLE", ("wait", 30), "TRIANGLE", ("wait", 700), "DOWN", "CROSS", ("wait", 300), "CIRCLE", ("wait", 40), "CIRCLE"],
    # walk every tab with R, open dialogs where each screen has them, then go back with L
    "tour": ["R", "START", "CIRCLE", "R", "DOWN", "R", "START", "CIRCLE", "R", "SQUARE", "SQUARE", "START", "CIRCLE",
             "SELECT", "DOWN", "CROSS", ("wait", 20), "CIRCLE", "R", "R", "R", "DOWN", "CROSS", "CIRCLE", "DOWN", "DOWN", "CROSS",
             "DOWN", "CROSS", "CIRCLE", "L", "L", "L", "L", "L", "L", "L", "START", "DOWN", "CROSS", "CIRCLE", "CIRCLE"],
    # install the built-in MangaDex extension, open Browse, open the source (offline -> empty grid)
    "extensions": ["R", "R", "R", "R", ("wait", 120), "SQUARE", "DOWN", "CROSS", ("wait", 60), "SQUARE", "SQUARE", "DOWN", "CROSS",
                   ("wait", 30), "L", "DOWN", "CROSS", ("wait", 60), "SQUARE", ("wait", 30), "CIRCLE", "CIRCLE", ("wait", 20),
                   "TRIANGLE", ("wait", 120), "DOWN", "CIRCLE"],
    # install a source, then Extensions > Installed > (X) > "Open source" must land on its catalog in Browse
    "opensrc": ["R", "R", "R", "R", ("wait", 120), "SQUARE", "DOWN", "CROSS", ("wait", 90), "SQUARE", "SQUARE", "DOWN",
                "CROSS", ("wait", 20), "CROSS", ("wait", 60)],
    # settings: language picker dialog, pick English, then back to the system language
    "lang": ["R", "R", "R", "R", "R", "R", "R", ("wait", 20), "CROSS", ("wait", 30), "DOWN", ("wait", 30), "CROSS", ("wait", 30),
             "CROSS", ("wait", 30), "UP", "CROSS", ("wait", 30)],
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
    # empty Import tab (help text)
    "importempty": ["R", "R", "R", "R", "R", "R", ("wait", 40)],
    # online: open a manga, download a chapter (Square), then the Downloads tab lists it with its cover
    "dlcover": [("wait", 150), "R", "R", "R", ("wait", 20), "DOWN", "CROSS", ("wait", 500), "DOWN", "CROSS", ("wait", 400),
                "DOWN", "SQUARE", ("wait", 700), "CIRCLE", ("wait", 40), "R", "R", ("wait", 120)],
    # after 'import' (same --tmp): read the 2nd imported manga, reader menu (Start + top-right icon) > Save image
    "saveimage": [("wait", 30), "DOWN", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", ("wait", 200), "START", ("wait", 40),
                  ("touch", 930, 40), ("wait", 30), "DOWN", "DOWN", "DOWN", "CROSS", ("wait", 60)],
    # after 'import': 3rd imported manga, page 2 is a PNG -> "Save image" must write a JPEG
    "savepng": [("wait", 30), "DOWN", "RIGHT", "RIGHT", "CROSS", ("wait", 120), "DOWN", "CROSS", ("wait", 200), "RIGHT", ("wait", 80),
                "START", ("wait", 40), ("touch", 930, 40), ("wait", 30), "DOWN", "DOWN", "DOWN", "CROSS", ("wait", 60)],
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", nargs="?", default="tour")
    ap.add_argument("--lang", type=int, default=1, help="System language id (1=English, 17=pt-BR)")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--online", action="store_true", help="perform real HTTP requests")
    ap.add_argument("--tls12", action="store_true", help="emulate the old NOBORU engine (TLS 1.2 only)")
    ap.add_argument("--skip-starter", action="store_true", help="don't auto-install the first-run extensions")
    ap.add_argument("--install", default="", help="comma separated extension ids to install on first frame")
    ap.add_argument("--keyboard", default="one piece")
    ap.add_argument("--shots", default="", help="comma separated frame numbers to screenshot")
    ap.add_argument("--outdir", default=os.path.join(ROOT, "tools", "tests", "screens"))
    ap.add_argument("--tmp", default=None)
    args = ap.parse_args()

    tmp = args.tmp or tempfile.mkdtemp(prefix="otakio_sim_")
    os.makedirs(os.path.join(tmp, "ux0", "data"), exist_ok=True)
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
        "rmdir": fs.rmdir, "rename": fs.rename, "listdir": listdir, "listzip": fs.listzip, "convert": fs.convert,
    })
    mock(ROOT + "/tools/tests/vita_mock.lua", ROOT, tmp)
    sim = L.globals().SIM
    sim.fs = L.globals().PYFS
    sim.language = args.lang
    sim.keyboardText = args.keyboard
    if args.install:
        sim.install = L.table_from(args.install.split(","))
    sys.path.insert(0, os.path.join(ROOT, "tools", "tests"))
    import render
    sim.textWidth = lambda size, bold, text: render.text_width(size, bold, text)
    sim.imageSize = lambda path: render.image_size(path) if os.path.isfile(path) else (None, None)
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
        sim.http = http
        sim.download = download
        sim.netstats = L.table_from(stats)
        globals()["NETSTATS"] = stats
    steps = SCENARIOS[args.scenario]
    script, frames = build_script(steps)
    lua_script = L.table_from({k: L.table_from({kk: (L.table_from(list(vv)) if isinstance(vv, tuple) else vv) for kk, vv in v.items()}) for k, v in script.items()})
    sim.script = lua_script
    sim.maxFrames = frames
    L.execute("""
        SIM.onFrame = function(frame)
            -- memory: Lua heap and GPU textures (current and peak)
            local kb = collectgarbage("count")
            if kb > (SIM.peakLua or 0) then SIM.peakLua = kb end
            local gpu = GetGPUMemoryUsed and GetGPUMemoryUsed() or 0
            if gpu > (SIM.peakGpu or 0) then SIM.peakGpu = gpu end
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
    print("   memory: lua now %.0f KB, lua peak %.0f KB, textures peak %.0f KB" % (L.eval('collectgarbage("count")'), sim.peakLua or 0, (sim.peakGpu or 0) / 1024))
    for line in list(sim.log.values()):
        print("  ", line)
    ext = os.path.join(tmp, "ux0", "data", "otakio", "extensions")
    if os.path.isdir(ext):
        print("   installed extension files:", os.listdir(ext))
    if not args.keep and not args.tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    else:
        print("data dir:", tmp)


if __name__ == "__main__":
    main()
