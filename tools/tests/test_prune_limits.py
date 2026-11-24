"""Safety limits of the unattended weekly sync (tools/prune_repo.py), offline on a scratch catalog:
- sources dead for DEAD_DAYS leave at most --max-removals a run, the longest-dead first;
- nothing dead is removed when a large share of the catalog looks dead at once (a broken health check);
- keiyoushi removals beyond the limit are all held back;
- a keiyoushi clone that looks incomplete is not followed at all;
- a dead source whose site only refuses the health check's machine stays.
python tools/tests/test_prune_limits.py"""
import json, os, sys, tempfile, time
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import prune_repo, probe_sources

OLD = time.strftime("%Y-%m-%d", time.gmtime(time.time() - (prune_repo.DEAD_DAYS + 30) * 86400))


def ago(days):
    return time.strftime("%Y-%m-%d", time.gmtime(time.time() - days * 86400))


def setup(n_ok, dead_days, kei=()):
    """A scratch root: repo/ with n_ok working native sources, one dead native per entry of dead_days and the keiyoushi
    entries `kei` (pkg names, all present upstream unless missing from the clone)."""
    root = tempfile.mkdtemp()
    repo = os.path.join(root, "repo")
    os.makedirs(os.path.join(repo, "extensions"))
    entries, health = [], {}

    def add(ext_id, origin, header="-- Otakio extension\n"):
        path = "extensions/%s.lua" % ext_id
        open(os.path.join(repo, path), "w").write(header + "return {}\n")
        entries.append({"id": ext_id, "name": ext_id, "lang": "en", "version": 1, "engine": "native", "origin": origin,
                        "baseUrl": "https://%s.example" % ext_id.replace(".", "-"), "file": path})

    for i in range(n_ok):
        add("otakio.ok%d" % i, "otakio")
        health["otakio.ok%d" % i] = {"status": "ok", "checked": ago(0)}
    for i, d in enumerate(dead_days):
        add("otakio.dead%d" % i, "otakio")
        health["otakio.dead%d" % i] = {"status": "dead", "checked": ago(0), "deadSince": ago(d)}
    for pkg in kei:
        add("kei.en." + pkg, "keiyoushi", "-- Otakio extension (generated from keiyoushi/extensions-source: en/%s)\n" % pkg)
    json.dump({"extensions": entries}, open(os.path.join(repo, "index.json"), "w"))
    json.dump(health, open(os.path.join(repo, "health.json"), "w"))
    prune_repo.ROOT, prune_repo.REPO = root, repo
    prune_repo.REMOVED_JSON = os.path.join(repo, "removed.json")
    prune_repo.REMOVED_MD = os.path.join(repo, "REMOVED.md")
    probe_sources.HEALTH = os.path.join(repo, "health.json")
    return root, repo


def kei_clone(present, filler=0):
    root = tempfile.mkdtemp()
    for pkg in list(present) + ["filler%d" % i for i in range(filler)]:
        d = os.path.join(root, "src", "en", pkg)
        os.makedirs(d)
        open(os.path.join(d, "build.gradle.kts"), "w").write(
            'keiyoushi {\n name = "%s"\n theme = "madara"\n source {\n lang = "en"\n baseUrl = "https://kei-en-%s.example"\n }\n}\n' % (pkg, pkg))
    return root


def run(*argv):
    summary = os.path.join(tempfile.mkdtemp(), "sync.json")
    sys.argv = ["prune_repo.py", "--max-removals", "3", "--summary", summary] + list(argv)
    prune_repo.main()
    return json.load(open(summary))


def ids(repo):
    return {e["id"] for e in json.load(open(os.path.join(repo, "index.json")))["extensions"]}


# dead sources: 3 a run, the longest-dead first, the rest deferred; a recent death stays
root, repo = setup(20, [prune_repo.DEAD_DAYS + 50, prune_repo.DEAD_DAYS + 10, prune_repo.DEAD_DAYS + 40,
                        prune_repo.DEAD_DAYS + 30, prune_repo.DEAD_DAYS + 20, 10])
s = run()
assert sorted(r["id"] for r in s["removed"]) == ["otakio.dead0", "otakio.dead2", "otakio.dead3"], s
assert sorted(s["deferred"]) == ["otakio.dead1", "otakio.dead4"], s
assert "otakio.dead5" in ids(repo) and "otakio.dead0" not in ids(repo)
s = run()
assert sorted(r["id"] for r in s["removed"]) == ["otakio.dead1", "otakio.dead4"] and s["deferred"] == [], s
assert all("dead since" in r["reason"] for r in json.load(open(prune_repo.REMOVED_JSON)))

# dead for long, but the site only refuses the health check's machine: kept (the console may still read it)
root, repo = setup(20, [prune_repo.DEAD_DAYS + 50, prune_repo.DEAD_DAYS + 40])
h = json.load(open(probe_sources.HEALTH))
h["otakio.dead0"]["site"] = "blocked"
h["otakio.dead1"]["site"] = "gone"
json.dump(h, open(probe_sources.HEALTH, "w"))
s = run()
assert [r["id"] for r in s["removed"]] == ["otakio.dead1"] and s["kept"] == ["otakio.dead0"], s
assert "site down" in s["removed"][0]["reason"], s
assert "otakio.dead0" in ids(repo)

# half the catalog dead at once: the health check is suspect, nothing goes
root, repo = setup(4, [prune_repo.DEAD_DAYS + 5] * 4)
s = run()
assert s["removed"] == [] and len(s["held"]) == 4, s
assert len(ids(repo)) == 8

# keiyoushi: more removals than the limit are all held back; within the limit they go
pkgs = ["a", "b", "c", "d", "e"]
root, repo = setup(5, [], kei=pkgs)
s = run("--kei", kei_clone(["a"], filler=prune_repo.MIN_KEI_SOURCES))
assert s["removed"] == [] and len(s["held"]) == 4, s
s = run("--kei", kei_clone(["a", "b", "c"], filler=prune_repo.MIN_KEI_SOURCES))
assert sorted(r["id"] for r in s["removed"]) == ["kei.en.d", "kei.en.e"], s

# an incomplete clone (a failed checkout) is not followed: nothing removed upstream
root, repo = setup(5, [], kei=pkgs)
s = run("--kei", kei_clone([]))
assert s["removed"] == [] and s["held"] == [], s
assert len(ids(repo)) == 10
print("prune limits: OK")
