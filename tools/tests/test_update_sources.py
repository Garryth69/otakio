"""tools/update_sources.py, offline on a scratch catalog (the live probe is replaced by fixed results):
- a broken keiyoushi source whose regenerated code does better is replaced, with a higher version and a new hash;
- one that does no better is left as it was;
- working sources and sources whose site is down are never touched.
python tools/tests/test_update_sources.py"""
import hashlib, json, os, sys, tempfile, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import probe_sources, prune_repo, update_sources

root = tempfile.mkdtemp()
repo = os.path.join(root, "repo")
os.makedirs(os.path.join(repo, "extensions"))
kei = tempfile.mkdtemp()
today = time.strftime("%Y-%m-%d")
entries, health = [], {}
STATUS = {"fixed": "dead", "still": "dead", "works": "ok", "gone": "dead"}
for pkg, status in STATUS.items():
    ext_id = "kei.en." + pkg
    path = "extensions/%s.lua" % ext_id
    old = ("-- Otakio extension (generated from keiyoushi/extensions-source: en/%s)\nEngines.Madara {\n\tid = \"KEI_EN%s\",\n"
           "\tname = \"%s\",\n\tbaseUrl = \"https://%s.example\",\n\tlang = \"en\",\n\tversion = 3,\n\tnsfw = false,\n"
           "\textension = \"%s\",\n\tchapterMode = \"MangaAjax\",\n}\n") % (pkg, pkg.upper(), pkg, pkg, ext_id)
    open(os.path.join(repo, path), "w", newline="\n").write(old)
    entries.append({"id": ext_id, "name": pkg, "lang": "en", "version": 3, "engine": "madara", "origin": "keiyoushi",
                    "baseUrl": "https://%s.example" % pkg, "file": path,
                    "sha256": hashlib.sha256(old.encode()).hexdigest()})
    health[ext_id] = {"status": status, "checked": today}
    # keiyoushi changed every one of them since (the option is gone): the regenerated code differs
    d = os.path.join(kei, "src", "en", pkg)
    os.makedirs(d)
    open(os.path.join(d, "build.gradle.kts"), "w").write(
        'keiyoushi {\n name = "%s"\n versionCode = 5\n theme = "madara"\n source {\n lang = "en"\n baseUrl = "https://%s.example"\n }\n}\n' % (pkg, pkg))
health["kei.en.gone"]["site"] = "gone"
json.dump({"extensions": entries}, open(os.path.join(repo, "index.json"), "w"))
json.dump(health, open(os.path.join(repo, "health.json"), "w"))
prune_repo.REPO = update_sources.REPO = repo
probe_sources.HEALTH = os.path.join(repo, "health.json")

probed = []


def fake_run(targets, workers=3, verbose=False):
    probed.extend(t["id"] for t in targets)
    return {t["id"]: {"status": "ok" if t["id"] == "kei.en.fixed" else "dead", "popular": 1, "chapters": 1, "pages": 1}
            for t in targets}


probe_sources.run = fake_run
summary = os.path.join(root, "sync.json")
sys.argv = ["update_sources.py", "--kei", kei, "--summary", summary]
update_sources.main()

assert sorted(probed) == ["kei.en.fixed", "kei.en.still"], probed
idx = {e["id"]: e for e in json.load(open(os.path.join(repo, "index.json")))["extensions"]}
fixed = open(os.path.join(repo, "extensions", "kei.en.fixed.lua")).read()
assert idx["kei.en.fixed"]["version"] == 6 and "version = 6," in fixed, (idx["kei.en.fixed"], fixed)
assert idx["kei.en.fixed"]["sha256"] == hashlib.sha256(fixed.encode()).hexdigest()
assert json.load(open(probe_sources.HEALTH))["kei.en.fixed"]["status"] == "ok"
for untouched in ("still", "works", "gone"):
    assert idx["kei.en." + untouched]["version"] == 3, untouched
    assert "version = 3," in open(os.path.join(repo, "extensions", "kei.en.%s.lua" % untouched)).read(), untouched
s = json.load(open(summary))
assert s["updated"] == [{"id": "kei.en.fixed", "name": "fixed", "from": "dead", "to": "ok"}], s
print("update sources: OK")
