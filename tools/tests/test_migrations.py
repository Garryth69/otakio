"""Data migrations (source/assets/libs/migrations.lua) against a real temporary folder:
fresh install, old data (baseline), a real step, a failing step (data restored), data from a newer app.

  python tools/tests/test_migrations.py"""
import os, shutil, sys, tempfile
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def runtime(tmp):
    L = luajit21.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()

    def real(p):
        return os.path.join(tmp, p.replace("ux0:data/otakio/", "").replace("/", os.sep))

    files = {}

    def openFile(p, mode):
        f = open(real(p), "rb" if mode == 1 else "wb")
        files[id(f)] = f
        return f

    system = {
        "openFile": openFile,
        "closeFile": lambda f: f.close(),
        "readFile": lambda f, n: f.read(n).decode("latin-1"),
        "writeFile": lambda f, d, n: f.write(d.encode("latin-1") if isinstance(d, str) else d),
        "sizeFile": lambda f: os.fstat(f.fileno()).st_size,
        "doesFileExist": lambda p: os.path.isfile(real(p)),
        "doesDirExist": lambda p: os.path.isdir(real(p)),
        "deleteFile": lambda p: os.remove(real(p)),
        "createDirectory": lambda p: os.makedirs(real(p), exist_ok=True),
        "listDirectory": lambda p: L.table_from([L.table_from({"name": n, "directory": os.path.isdir(os.path.join(real(p), n))})
                                                 for n in sorted(os.listdir(real(p)))]),
        "rename": lambda a, b: os.replace(real(a), real(b)),
    }
    g.System = L.table_from(system)
    g.FREAD, g.FCREATE = 1, 2
    L.execute('Config = {DATA = "ux0:data/otakio/"}; LOG = {}; function ExtLog(m) LOG[#LOG + 1] = m end')
    L.execute('table.serialize = function() return "{}" end')
    L.execute(open(os.path.join(ROOT, "source/assets/libs/fs.lua"), encoding="utf-8").read())
    L.execute(open(os.path.join(ROOT, "source/assets/libs/migrations.lua"), encoding="utf-8").read())
    return L


def fresh_dir():
    d = tempfile.mkdtemp(prefix="otakio_mig_")
    return d


def check(cond, msg):
    if not cond:
        print("FAIL:", msg)
        sys.exit(1)
    print("ok  ", msg)


STEPS = """{
  [1] = {name = "baseline", baseline = true, run = function() end},
  [2] = {name = "rename field", run = function(dir)
    local s = FS.read(dir .. "settings.ini")
    FS.write(dir .. "settings.ini", (s:gsub("OldField", "NewField")))
    FS.write(dir .. "cache/history.dat", "converted")
  end}
}"""
FAILING = """{
  [1] = {name = "baseline", baseline = true, run = function() end},
  [2] = {name = "breaks", run = function(dir)
    FS.write(dir .. "settings.ini", "half written")
    error("boom")
  end}
}"""

# 1. fresh install: no settings.ini -> version written, nothing run
d = fresh_dir()
L = runtime(d)
check(L.eval("Migrations.run()") == "fresh", "fresh install")
check(open(os.path.join(d, "data_version.txt")).read().strip() == "1", "fresh install writes the current version")

# 2. data from 1.0 - 1.1.1 (no data_version.txt): baseline only
d = fresh_dir()
open(os.path.join(d, "settings.ini"), "w").write("Settings = {OldField = 1}")
L = runtime(d)
check(L.eval("Migrations.run()") == "migrated", "old data reaches the baseline")
check(open(os.path.join(d, "data_version.txt")).read().strip() == "1", "baseline version written")
check(not os.path.isdir(os.path.join(d, "backups")), "the baseline makes no copy")
check(L.eval("Migrations.run()") == "current", "second start: nothing to do")

# 3. a real step: data converted, a copy kept
os.makedirs(os.path.join(d, "cache"), exist_ok=True)
open(os.path.join(d, "cache", "history.dat"), "w").write("old history")
check(L.eval("Migrations.run({steps = %s, current = 2})" % STEPS) == "migrated", "step 2 runs")
check("NewField" in open(os.path.join(d, "settings.ini")).read(), "step 2 converted settings.ini")
check(open(os.path.join(d, "backups", "pre-migration-2", "settings.ini")).read() == "Settings = {OldField = 1}", "the original settings were copied first")
check(open(os.path.join(d, "backups", "pre-migration-2", "cache", "history.dat")).read() == "old history", "cache files copied too")
check(open(os.path.join(d, "data_version.txt")).read().strip() == "2", "version 2 written")

# 4. a failing step: the data goes back to how it was, version unchanged
d = fresh_dir()
open(os.path.join(d, "settings.ini"), "w").write("Settings = {Keep = true}")
open(os.path.join(d, "data_version.txt"), "w").write("1\n")
L = runtime(d)
check(L.eval("Migrations.run({steps = %s, current = 2})" % FAILING) == "failed", "a failing step is reported")
check(open(os.path.join(d, "settings.ini")).read() == "Settings = {Keep = true}", "settings.ini restored after the failure")
check(open(os.path.join(d, "data_version.txt")).read().strip() == "1", "version stays at 1")
check(L.eval("Migrations.failed") is True, "the user is told at startup")

# 5. data from a newer Otakio: untouched
d = fresh_dir()
open(os.path.join(d, "settings.ini"), "w").write("Settings = {}")
open(os.path.join(d, "data_version.txt"), "w").write("9\n")
L = runtime(d)
check(L.eval("Migrations.run()") == "newer", "newer data is left alone")
check(open(os.path.join(d, "data_version.txt")).read().strip() == "9", "its version is kept")
print("migration tests OK")
