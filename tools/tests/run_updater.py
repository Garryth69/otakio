"""Runs Otakio Updater (source/updater/index.lua) against a simulator data folder, as the console would after
Otakio handed over an update:

  python tools/tests/run_updater.py <sim tmp dir> [--fail]

ux0: maps to <tmp>/ux0. The promoter installs the package under ux0:app/<TITLE_ID> (Otakio is closed now);
--fail makes it do nothing, like a failed install. Prints the screens shown, the result file and the relaunch."""
import os, shutil, struct, sys
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
tmp = sys.argv[1]
fail = "--fail" in sys.argv


def real(p):
    p = p.replace("ux0:/", "ux0:").replace("ux0:", os.path.join(tmp, "ux0") + "/")
    p = p.replace("app0:", os.path.join(ROOT, "source", "updater") + "/")  # the helper's own files (fonts)
    return os.path.normpath(p)


def sfo_values(path):
    d = open(path, "rb").read()
    ks, ds, n = struct.unpack_from("<III", d, 8)
    out = {}
    for i in range(n):
        ko, fmt, ln, mx, do = struct.unpack_from("<HHIII", d, 20 + i * 16)
        name = d[ks + ko:d.index(b"\0", ks + ko)].decode()
        out[name] = d[ds + do:ds + do + ln].rstrip(b"\0").decode("utf-8", "replace")
    return out


class Exit(Exception):
    pass


L = luajit21.LuaRuntime(unpack_returned_tuples=True)
log = []
files = {}


def open_file(p, mode):
    fh = open(real(p), "rb" if mode == 1 else "wb")
    files[id(fh)] = fh
    return id(fh)


def read_file(h, n):
    return files[h].read(n)


def write_file(h, data, n):
    files[h].write(data if isinstance(data, bytes) else data.encode("utf-8", "surrogateescape"))


def size_file(h):
    f = files[h]
    cur = f.tell(); f.seek(0, 2); n = f.tell(); f.seek(cur)
    return n


def close_file(h):
    files.pop(h).close()


def list_dir(p):
    rp = real(p)
    if not os.path.isdir(rp):
        return None
    return L.table_from([L.table_from({"name": n, "directory": os.path.isdir(os.path.join(rp, n))}) for n in os.listdir(rp)])


def install_app(p):
    rp = real(p)
    if fail or not os.path.isfile(os.path.join(rp, "sce_sys", "param.sfo")):
        return True  # the promoter reports success either way
    title = sfo_values(os.path.join(rp, "sce_sys", "param.sfo"))["TITLE_ID"]
    if title == "OTAK00002":
        return True  # the updater itself is running
    dest = os.path.join(tmp, "ux0", "app", title)
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(rp, dest)
    log.append("installApp: %s -> ux0:app/%s" % (p, title))
    return True


def extract_sfo(p):
    v = sfo_values(real(p))
    return L.table_from({"version": v.get("APP_VER"), "title": v.get("TITLE"), "title_id": v.get("TITLE_ID")})


def launch(t):
    log.append("launchApp(%s)" % t)


def do_exit():
    raise Exit()


def rmdir(p):
    try:
        os.rmdir(real(p))
    except OSError:
        pass


system = {
    "doesFileExist": lambda p: os.path.isfile(real(p)),
    "doesDirExist": lambda p: os.path.isdir(real(p)),
    "openFile": open_file, "readFile": read_file, "writeFile": write_file, "sizeFile": size_file, "closeFile": close_file,
    "deleteFile": lambda p: os.path.isfile(real(p)) and os.remove(real(p)),
    "deleteDirectory": rmdir, "listDirectory": list_dir,
    "createDirectory": lambda p: os.makedirs(real(p), exist_ok=True),
    "rename": lambda a, b: os.replace(real(a), real(b)),
    "wait": lambda us: None, "installApp": install_app, "extractSfo": extract_sfo,
    "launchApp": launch, "exit": do_exit,
}
g = L.globals()
g.System = L.table_from(system)
g.FREAD, g.FCREATE = 1, 2
L.execute("""
Color = {new = function(r, g, b) return r * 65536 + g * 256 + b end}
Screen = {clear = function() end, flip = function() end, waitVblankStart = function() end}
SHOWN = {}
BARS = {}
Graphics = {initBlend = function() end, termBlend = function() end,
  debugPrint = function(x, y, text) if SHOWN[#SHOWN] ~= text then SHOWN[#SHOWN + 1] = text end end,
  fillRect = function(x0, x1, y0) if x0 == 148 and y0 == 330 and x1 ~= 812 then BARS[#BARS + 1] = math.floor((x1 - 148) / 6.64) end end}
FONTS = 0
Font = {load = function(p) FONTS = FONTS + 1 return {path = p} end, setPixelSizes = function() end,
  print = function(f, x, y, text) if SHOWN[#SHOWN] ~= text then SHOWN[#SHOWN + 1] = text end end}
Timer = {new = function() return {} end, getTime = function() return 1234.5 end}
""")
try:
    L.execute(open(os.path.join(ROOT, "source", "updater", "index.lua"), encoding="utf-8").read())
    print("updater ended without exiting")
except Exception as e:
    if not isinstance(e, Exit) and "Exit" not in repr(e):
        raise
shown = L.eval("SHOWN")
print("screens:", [shown[i] for i in range(1, len(shown) + 1)])
print("fonts loaded:", L.eval("FONTS"))
bars = L.eval("BARS")
print("progress bar (%):", sorted(set(bars[i] for i in range(1, len(bars) + 1))))
for line in log:
    print(" ", line)
res = os.path.join(tmp, "ux0", "data", "otakio", "update_result.txt")
print("result file:", open(res).read() if os.path.exists(res) else None)
print("update dir left:", os.path.isdir(os.path.join(tmp, "ux0", "data", "otakio", "update")))
inst = os.path.join(tmp, "ux0", "app", "OTAK00001", "sce_sys", "param.sfo")
print("installed Otakio APP_VER:", sfo_values(inst)["APP_VER"] if os.path.exists(inst) else None)
