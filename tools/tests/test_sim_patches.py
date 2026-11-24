"""Engine patches from the official catalog, end to end in the simulator (the whole app booting and running):
- a patch listed in the catalog's index.json is downloaded (sha256 checked), kept on the card, run before the
  extensions, and the installed extensions are rebuilt on top of it;
- the next start runs it again from the card, before any extension;
- a patch with a wrong sha256, or made for other app versions (maxApp), is never installed;
- a patch the catalog stops listing is removed.
python tools/tests/test_sim_patches.py"""
import hashlib, json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
tmp = tempfile.mkdtemp(prefix="otakio_patch_")
data = os.path.join(tmp, "ux0", "data", "otakio")
os.makedirs(os.path.join(data, "extensions"))
OFFICIAL = "https://raw.githubusercontent.com/Garryth69/otakio-extensions/main/index.json"

# an installed Madara source and the official repository
open(os.path.join(data, "extensions", "test.madara.lua"), "w").write(
    'Engines.Madara {\n\tid = "TEST_MADARA",\n\tname = "Test Madara",\n\tbaseUrl = "https://madara.example",\n\tlang = "en",\n'
    '\tversion = 1,\n\tnsfw = false,\n\textension = "test.madara",\n}\n')
open(os.path.join(data, "extensions.dat"), "w").write(
    'return {["test.madara"] = {id = "test.madara", name = "Test Madara", lang = "en", version = 1, nsfw = false, '
    'engine = "madara", origin = "test", compat = "full", repo = "Otakio", file = "test.madara.lua", date = 0}}')
open(os.path.join(data, "repos.dat"), "w").write('return {{name = "Otakio", url = "%s"}}' % OFFICIAL)

# the catalog: the real index plus patches
catalog = os.path.join(tmp, "catalog")
os.makedirs(os.path.join(catalog, "patches"))
index = json.load(open(os.path.join(ROOT, "repo", "index.json"), encoding="utf8"))
PATCH = ('local base = Engines.Madara\n'
         'Engines.Madara = function(cfg)\n'
         '\tExtLog("PATCHED-MADARA " .. tostring(cfg.id))\n'
         '\treturn base(cfg)\n'
         'end\n')


def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def publish(patches):
    for p in patches:
        open(os.path.join(catalog, p["file"]), "w", newline="\n").write(p.pop("_text"))
    index["patches"] = patches
    json.dump(index, open(os.path.join(catalog, "index.json"), "w"))


def run():
    log = os.path.join(data, "log.txt")
    if os.path.exists(log):
        os.remove(log)
    shutil.rmtree(os.path.join(data, "repocache"), ignore_errors=True)  # always read the catalog again
    env = dict(os.environ, SIM_FAKE_REPO=catalog)
    r = subprocess.run([sys.executable, os.path.join(HERE, "sim.py"), "tour", "--tmp", tmp, "--keep", "--skip-starter"],
                       env=env, capture_output=True, text=True, timeout=600)
    out = r.stdout + r.stderr
    assert r.returncode == 0 and "scenario 'tour' OK" in out, out[-3000:]
    return open(log, encoding="utf8").read()


publish([
    {"id": "madara-test", "version": 1, "file": "patches/madara-test.lua", "sha256": sha(PATCH), "_text": PATCH},
    {"id": "bad-hash", "version": 1, "file": "patches/bad-hash.lua", "sha256": "0" * 64, "_text": "Engines.BAD = true\n"},
    {"id": "old-app", "version": 1, "file": "patches/old-app.lua", "sha256": sha("Engines.OLD = true\n"), "maxApp": "1.0.0",
     "_text": "Engines.OLD = true\n"},
])

# 1. downloaded on the first refresh, applied, the installed Madara source rebuilt on top of it
log = run()
assert "engine patch madara-test v1" in log, log[-3000:]
assert "PATCHED-MADARA TEST_MADARA" in log, log[-3000:]
assert "engine patch bad-hash: download failed or sha256 mismatch" in log, log[-3000:]
assert "old-app" not in log, log[-3000:]
saved = open(os.path.join(data, "patches.dat"), encoding="utf8").read()
assert "madara-test" in saved and "bad-hash" not in saved and "old-app" not in saved, saved
assert os.path.exists(os.path.join(data, "patches", "madara-test.lua"))

# 2. the next start: run from the card before the extensions load (the catalog still lists it: nothing downloaded)
log = run()
first_patch = log.index("engine patch madara-test v1")
assert first_patch < log.index("PATCHED-MADARA TEST_MADARA"), log[-3000:]

# 3. withdrawn from the catalog: removed from the card
publish([])
log = run()
assert "engine patch madara-test withdrawn" in log, log[-3000:]
assert not os.path.exists(os.path.join(data, "patches", "madara-test.lua"))
print("engine patches in the simulator: OK")
