"""The library's safety nets, end to end in the simulator (the whole app booting and running):
- the automatic backup (Settings.AutoBackup, 7 days by default): made at start when the newest one is that old (or
  missing), not again sooner, in backups/otakio_auto_*.otk with the whole library; every day when set to 1, never
  when set to 0;
- a save cut short (the console off between removing save.dat and renaming save.dat.tmp): the complete .tmp copy is
  used at the next start and the library is still there.
python tools/tests/test_sim_backup.py"""
import glob, os, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
tmp = tempfile.mkdtemp(prefix="otakio_backup_")
data = os.path.join(tmp, "ux0", "data", "otakio")
backups = os.path.join(data, "backups")


def run(*extra):
    r = subprocess.run([sys.executable, os.path.join(HERE, "sim.py"), "tour", "--tmp", tmp, "--keep", "--skip-starter"] + list(extra),
                       capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    assert r.returncode == 0 and "scenario 'tour' OK" in out, out[-3000:]
    return out


def autos():
    return sorted(glob.glob(os.path.join(backups, "otakio_auto_*.otk")))


# 1. a library and no backup yet: one is made at start, with every title
run("--seed-library", "12")
made = autos()
assert len(made) == 1, made
text = open(made[0], encoding="utf8").read()
assert text.count("ParserID") >= 12, text[:500]

# 2. the next start, the same week: no second one
run()
assert autos() == made, autos()

# 3. a week later (the newest backup is old): a new one
old = os.path.join(backups, "otakio_auto_2020-01-01_000000_from-1.0.0.otk")
os.rename(made[0], old)
run()
assert len(autos()) == 2 and old in autos(), autos()

# 4. every day (AutoBackup = 1): yesterday's backup is old enough; turned off (0): none at all
for f in autos():
    os.remove(f)
yesterday = os.path.join(backups, "otakio_auto_%s_000000_from-1.0.0.otk" % time.strftime("%Y-%m-%d", time.localtime(time.time() - 86400)))
open(yesterday, "w").write("return {}")
run("--set", "AutoBackup = 7")
assert autos() == [yesterday], autos()
run("--set", "AutoBackup = 1")
assert len(autos()) == 2, autos()
for f in autos():
    os.remove(f)
run("--set", "AutoBackup = 0")
assert autos() == [], autos()

# 5. save.dat lost mid-save, its complete copy left as save.dat.tmp: the library comes back from it
save = os.path.join(data, "save.dat")
library = open(save, encoding="utf8").read()
assert library.count("ParserID") >= 12
shutil.move(save, save + ".tmp")
run()
assert os.path.exists(save) and open(save, encoding="utf8").read().count("ParserID") >= 12, "library lost"
print("library backups in the simulator: OK")
