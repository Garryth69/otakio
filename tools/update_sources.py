"""Brings keiyoushi's fixes to catalog sources that don't work: regenerates them from the current keiyoushi code and
keeps the new file only when it does better in a live test.

keiyoushi's maintainers fix sources every day (a new selector, path or option in the Kotlin code, a new versionCode).
prune_repo.py follows their domain changes and removals and add_sources.py their new sources; this follows their fixes.
The weekly sync (otakio-extensions regen.yml) runs it after them.

A catalog entry is a candidate when:
  - it was generated from keiyoushi and its health is "partial" or "dead";
  - its site answers (not down, parked, behind a browser check or refusing the robot: a new file can't change that);
  - the file generated now differs from the published one (ignoring the version line).
Each candidate is probed live with the app's own engines and replaces the published file only when its status is
better (dead -> partial or ok, partial -> ok). Working sources are never touched. At most --max per run.

  python tools/update_sources.py --kei <keiyoushi clone> [--max 20] [--summary repo/sync.json] [--dry-run]
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_repo, probe_sources, prune_repo

REPO = prune_repo.REPO
RANK = {"dead": 0, "partial": 1, "ok": 2}
SKIP_SITES = {"gone", "parked", "cloudflare", "blocked"}
VERSION_LINE = re.compile(r"^\s*version = \d+,\s*$", re.M)


def same_code(a, b):
    return VERSION_LINE.sub("", a) == VERSION_LINE.sub("", b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kei", required=True, help="keiyoushi/extensions-source clone (sparse is fine)")
    ap.add_argument("--max", type=int, default=20, help="sources probed at most per run")
    ap.add_argument("--summary", help="JSON file to record the updates in (merged into an existing one)")
    ap.add_argument("--dry-run", action="store_true", help="list the candidates only")
    args = ap.parse_args()

    idx = json.load(open(os.path.join(REPO, "index.json"), encoding="utf8"))
    health = probe_sources.load_health()
    by_id = {e["id"]: e for e in idx["extensions"]}

    # 1. not working, generated from keiyoushi, the site answers
    wanted = []
    for e in idx["extensions"]:
        h = health.get(e["id"]) or {}
        if e.get("origin") != "keiyoushi" or h.get("status") not in ("dead", "partial"):
            continue
        if h.get("site") in SKIP_SITES or h.get("cloudflare") or h.get("blocked"):
            continue
        src = prune_repo.kei_source_of(e)
        if src and os.path.exists(os.path.join(args.kei, "src", src[0], src[1], "build.gradle.kts")):
            wanted.append((e, src))
    print("%d keiyoushi sources not working with their site up" % len(wanted))
    if not wanted:
        return

    # 2. their Kotlin code (overrides), when the clone is sparse
    if os.path.isdir(os.path.join(args.kei, ".git")):
        dirs = sorted({"src/%s/%s" % src for _, src in wanted})
        subprocess.run(["git", "-C", args.kei, "sparse-checkout", "add"] + dirs, check=False)

    # 3. generate again; keep the ones whose code changed
    tmp = tempfile.mkdtemp()
    os.makedirs(os.path.join(tmp, "extensions"))
    fresh = {}
    for e, (lang_dir, pkg) in wanted:
        for g in gen_repo.build_kei_dir(os.path.join(args.kei, "src", lang_dir, pkg), lang_dir, pkg, tmp, "keiyoushi", "kei",
                                        "keiyoushi/extensions-source"):
            if g["id"] != e["id"]:
                continue
            new = open(os.path.join(tmp, g["file"]), encoding="utf8").read()
            old_path = os.path.join(REPO, e["file"])
            old = open(old_path, encoding="utf8").read() if os.path.exists(old_path) else ""
            if not same_code(new, old):
                fresh[e["id"]] = g
    candidates = sorted(fresh)[:args.max]
    print("%d with changed code, probing %d" % (len(fresh), len(candidates)))
    for c in candidates:
        print("  " + c)
    if args.dry_run or not candidates:
        shutil.rmtree(tmp, ignore_errors=True)
        return

    # 4. probe, keep the better ones
    targets = [{"id": i, "engine": "native", "baseUrl": fresh[i]["baseUrl"], "lang": fresh[i]["lang"],
                "file": os.path.join(tmp, fresh[i]["file"])} for i in candidates]
    results = probe_sources.run(targets, workers=3, verbose=False)
    updated = []
    for ext_id in candidates:
        r = results.get(ext_id) or {}
        old_status = (health.get(ext_id) or {}).get("status", "dead")
        if RANK.get(r.get("status"), 0) <= RANK.get(old_status, 0):
            print("  %s: still %s, kept as it was" % (ext_id, r.get("status")))
            continue
        e, g = by_id[ext_id], fresh[ext_id]
        text = open(os.path.join(tmp, g["file"]), encoding="utf8").read()
        version = max(int(e.get("version", 1)) + 1, int(g["version"]))
        text = VERSION_LINE.sub("\tversion = %d," % version, text, count=1)
        with open(os.path.join(REPO, e["file"]), "w", encoding="utf8", newline="\n") as fh:
            fh.write(text)
        e["version"] = version
        e["engine"] = g["engine"]
        probe_sources.merge_health(health, {ext_id: r})
        updated.append({"id": ext_id, "name": e["name"], "from": old_status, "to": r["status"]})
        print("  %s: %s -> %s, updated to v%d" % (ext_id, old_status, r["status"], version))
    shutil.rmtree(tmp, ignore_errors=True)
    if updated:
        probe_sources.apply_health(idx["extensions"], health)
        gen_repo.hash_entries(idx["extensions"], REPO)
        with open(os.path.join(REPO, "index.json"), "w", encoding="utf8", newline="\n") as fh:
            json.dump(idx, fh, ensure_ascii=False, separators=(",", ":"))
        probe_sources.save_health(health)
        # the bundled test catalog follows the real one (not a scratch catalog, as in the tests)
        bundled = os.path.join(gen_repo.ROOT, "source", "repo")
        if os.path.abspath(REPO) == os.path.abspath(os.path.join(gen_repo.ROOT, "repo")) and os.path.isdir(bundled):
            shutil.rmtree(bundled, ignore_errors=True)
            shutil.copytree(REPO, bundled, ignore=shutil.ignore_patterns("native", "health.json", "removed.json", ".git", ".github", "*.md", "LICENSE", "sync.json"))
    print("updated %d of %d probed" % (len(updated), len(candidates)))
    if args.summary:
        summary = {}
        if os.path.exists(args.summary):
            summary = json.load(open(args.summary, encoding="utf8"))
        summary.setdefault("date", time.strftime("%Y-%m-%d"))
        summary["updated"] = updated
        with open(args.summary, "w", encoding="utf8") as fh:
            json.dump(summary, fh, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
