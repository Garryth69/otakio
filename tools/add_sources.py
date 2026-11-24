"""Adds the sources keiyoushi published since the catalog was generated, the ones that pass a live test.

The weekly sync (otakio-extensions regen.yml) runs it after prune_repo.py, so the catalog keeps growing while nobody
maintains it. A keiyoushi extension is a candidate when:
  - its theme has an Otakio engine (gen_repo.ENGINES) and its language is published (gen_repo.DEFAULT_LANGS);
  - its id is not in the catalog, not removed (removed.json) and not a closed site (gen_repo.CLOSED_SITES);
  - no source of the catalog already serves the same site in the same language.
Each candidate is generated exactly like gen_repo.py does it and probed live with the app's own engines. Only the
ones that come back "ok" are added (at most --max per run); the others leave no trace.

  python tools/add_sources.py --kei <keiyoushi clone> [--max 15] [--summary repo/sync.json] [--dry-run]

A sparse clone (only build.gradle.kts files, like the weekly workflow's) is completed for the candidates with
`git sparse-checkout add`, so their Kotlin overrides are read too.
"""
import argparse, glob, json, os, shutil, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_repo, probe_sources, prune_repo

REPO = prune_repo.REPO


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kei", required=True, help="keiyoushi/extensions-source clone (sparse is fine)")
    ap.add_argument("--max", type=int, default=15, help="sources added at most per run")
    ap.add_argument("--summary", help="JSON file to record the additions in (merged into an existing one)")
    ap.add_argument("--dry-run", action="store_true", help="list the candidates only")
    args = ap.parse_args()

    idx = json.load(open(os.path.join(REPO, "index.json"), encoding="utf8"))
    have_ids = {e["id"] for e in idx["extensions"]}
    have_sites = {(gen_repo.host_of(e.get("baseUrl", "")), e.get("lang", "").lower()) for e in idx["extensions"]}
    skip = gen_repo.CLOSED_SITES | prune_repo.removed_ids()
    langs = {x.strip().lower() for x in gen_repo.DEFAULT_LANGS.split(",") if x.strip()}

    # 1. candidates from the build files alone
    candidates = []
    for gradle in sorted(glob.glob(os.path.join(args.kei, "src", "*", "*", "build.gradle.kts"))):
        ext_dir = os.path.dirname(gradle)
        pkg, lang_dir = os.path.basename(ext_dir), os.path.basename(os.path.dirname(ext_dir))
        name, theme, nsfw, version, sources = gen_repo.parse_gradle(open(gradle, encoding="utf8").read())
        if theme not in gen_repo.ENGINES or not name or not sources:
            continue
        fresh = False
        for src in sources:
            lang = src["lang"] if len(sources) > 1 else lang_dir
            ext_id = "kei." + lang.lower() + "." + pkg.lower()
            if (ext_id in have_ids or ext_id in skip or src["lang"].lower() not in langs or "$" in src["baseUrl"]
                    or (gen_repo.host_of(src["baseUrl"]), src["lang"].lower()) in have_sites):
                continue
            fresh = True
        if fresh:
            candidates.append((ext_dir, lang_dir, pkg))
    print("%d new keiyoushi extensions with an Otakio engine" % len(candidates))
    if args.dry_run or not candidates:
        for c in candidates:
            print("  %s/%s" % (c[1], c[2]))
        return

    # 2. their Kotlin sources (overrides), when the clone is sparse
    if os.path.isdir(os.path.join(args.kei, ".git")):
        rel = [os.path.relpath(c[0], args.kei).replace(os.sep, "/") for c in candidates]
        subprocess.run(["git", "-C", args.kei, "sparse-checkout", "add"] + rel, check=False)

    # 3. generate in a scratch folder, probe, keep the working ones
    tmp = tempfile.mkdtemp()
    os.makedirs(os.path.join(tmp, "extensions"))
    entries = []
    for ext_dir, lang_dir, pkg in candidates:
        for e in gen_repo.build_kei_dir(ext_dir, lang_dir, pkg, tmp, "keiyoushi", "kei", "keiyoushi/extensions-source"):
            site = (gen_repo.host_of(e["baseUrl"]), e["lang"].lower())
            if e["id"] in have_ids or e["id"] in skip or e["lang"].lower() not in langs or site in have_sites:
                continue
            have_sites.add(site)
            entries.append(e)
    targets = [{"id": e["id"], "engine": "native", "baseUrl": e["baseUrl"], "lang": e["lang"],
                "file": os.path.join(tmp, e["file"])} for e in entries]
    print("probing %d candidates..." % len(targets))
    results = probe_sources.run(targets, workers=3, verbose=False)
    by_id = {e["id"]: e for e in entries}
    added = []
    health = probe_sources.load_health()
    today = time.strftime("%Y-%m-%d")
    for ext_id in sorted(results):
        r = results[ext_id]
        if r.get("status") != "ok" or len(added) >= args.max:
            continue
        e = by_id[ext_id]
        shutil.copy(os.path.join(tmp, e["file"]), os.path.join(REPO, e["file"]))
        e.pop("_cfg", None)
        probe_sources.merge_health(health, {ext_id: r})
        h = health[ext_id]
        e["health"], e["checked"], e["compat"] = h["status"], h.get("checked", today), "full"
        idx["extensions"].append(e)
        added.append({"id": ext_id, "name": e["name"], "lang": e["lang"], "baseUrl": e["baseUrl"]})
        print("  added %s (%s)" % (ext_id, e["baseUrl"]))
    shutil.rmtree(tmp, ignore_errors=True)
    if added:
        gen_repo.hash_entries(idx["extensions"], REPO)
        with open(os.path.join(REPO, "index.json"), "w", encoding="utf8", newline="\n") as fh:
            json.dump(idx, fh, ensure_ascii=False, separators=(",", ":"))
        probe_sources.save_health(health)
        # keep the bundled test catalog in sync (with the real catalog only, not a scratch one)
        bundled = os.path.join(gen_repo.ROOT, "source", "repo")
        if os.path.abspath(REPO) == os.path.abspath(os.path.join(gen_repo.ROOT, "repo")):
            shutil.rmtree(bundled, ignore_errors=True)
            shutil.copytree(REPO, bundled, ignore=shutil.ignore_patterns("native", "health.json", "removed.json", ".git", ".github", "*.md", "LICENSE"))
    print("added %d of %d candidates" % (len(added), len(entries)))
    if args.summary:
        summary = {}
        if os.path.exists(args.summary):
            summary = json.load(open(args.summary, encoding="utf8"))
        summary.setdefault("date", today)
        summary["added"] = added
        with open(args.summary, "w", encoding="utf8") as fh:
            json.dump(summary, fh, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
