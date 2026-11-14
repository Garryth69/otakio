"""Takes extensions out of the catalog by hand, with a reason, the same way prune_repo.py does it automatically:
the entry leaves repo/index.json (its file too), its health line goes, and repo/removed.json + REMOVED.md record it
so gen_repo.py never publishes it again. The bundled test catalog (source/repo) is synced.

  python tools/remove_sources.py "reason" id1 id2 ...
"""
import json, os, shutil, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_repo, probe_sources, prune_repo

REPO = prune_repo.REPO


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    reason, ids = sys.argv[1], set(sys.argv[2:])
    path = os.path.join(REPO, "index.json")
    idx = json.load(open(path, encoding="utf8"))
    log = prune_repo.load_removed()
    health = probe_sources.load_health()
    kept, gone = [], []
    for e in idx["extensions"]:
        if e["id"] in ids:
            gone.append(e)
        else:
            kept.append(e)
    missing = ids - {e["id"] for e in gone}
    if missing:
        sys.exit("not in the catalog: " + ", ".join(sorted(missing)))
    today = time.strftime("%Y-%m-%d")
    for e in gone:
        if e.get("file"):
            f = os.path.join(REPO, e["file"])
            if os.path.isfile(f):
                os.remove(f)
        health.pop(e["id"], None)
        log.append({"id": e["id"], "name": e.get("name", e["id"]), "baseUrl": e.get("baseUrl", ""),
                    "origin": e.get("origin", ""), "date": today, "reason": reason})
        print("removed", e["id"], e.get("baseUrl", ""))
    idx["extensions"] = kept
    gen_repo.hash_entries(idx["extensions"], REPO)
    json.dump(idx, open(path, "w", encoding="utf8", newline="\n"), ensure_ascii=False, separators=(",", ":"))
    probe_sources.save_health(health)
    prune_repo.save_removed(log)
    bundled = os.path.join(gen_repo.ROOT, "source", "repo")
    shutil.rmtree(bundled, ignore_errors=True)
    shutil.copytree(REPO, bundled, ignore=shutil.ignore_patterns("native", "health.json", "removed.json", ".git", ".github", "*.md", "LICENSE"))
    print("catalog: %d extensions" % len(kept))


if __name__ == "__main__":
    main()
