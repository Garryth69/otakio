"""The app's unattended-maintenance paths, end to end in the simulator (the whole app booting and running):
- remote settings: remote.json (served by SIM_FAKE_REMOTE) is downloaded at startup, kept on the card, its notice
  shown once and its user agent applied;
- replaced extensions: an installed kei.es.mhscans becomes the native otakio.mhscans (REPLACED_BY) on the first
  catalog refresh.
python tools/tests/test_sim_maintenance.py"""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
tmp = tempfile.mkdtemp(prefix="otakio_maint_")
data = os.path.join(tmp, "ux0", "data", "otakio")
os.makedirs(os.path.join(data, "extensions"))

# an old theme-based install of a source that now has a native replacement
open(os.path.join(data, "extensions", "kei.es.mhscans.lua"), "w").write(
    'Engines.Madara {\n\tid = "KEI_ESMHSCANS",\n\tname = "MHScans",\n\tbaseUrl = "https://mhscans.com",\n\tlang = "es",\n'
    '\tversion = 1,\n\tnsfw = false,\n\textension = "kei.es.mhscans",\n}\n')
open(os.path.join(data, "extensions.dat"), "w").write(
    'return {["kei.es.mhscans"] = {id = "kei.es.mhscans", name = "MHScans", lang = "es", version = 1, nsfw = false, '
    'engine = "madara", origin = "keiyoushi", compat = "full", repo = "Otakio", file = "kei.es.mhscans.lua", date = 0}}')

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36"
remote = os.path.join(tmp, "remote.json")
json.dump({"format": 1, "userAgent": UA, "notice": {"id": "sim-notice", "text": {"English": "Hello from remote.json"}}},
          open(remote, "w"))

env = dict(os.environ, SIM_FAKE_REMOTE=remote)
r = subprocess.run([sys.executable, os.path.join(HERE, "sim.py"), "tour", "--tmp", tmp, "--keep", "--skip-starter"],
                   env=env, capture_output=True, text=True, timeout=600)
out = r.stdout + r.stderr
assert r.returncode == 0 and "scenario 'tour' OK" in out, out[-3000:]

seen = open(os.path.join(data, "remote_seen.txt")).read().split()
assert seen == ["sim-notice"], seen
cached = json.load(open(os.path.join(data, "remote.json")))
assert cached["userAgent"] == UA, cached

installed = open(os.path.join(data, "extensions.dat"), encoding="utf8").read()
assert '"otakio.mhscans"' in installed, installed[:500]
assert '"kei.es.mhscans"' not in installed, installed[:500]
assert os.path.exists(os.path.join(data, "extensions", "otakio.mhscans.lua"))
print("maintenance paths in the simulator: OK")
