"""Removes dead or withdrawn extensions from the catalog (repo/index.json) and logs every removal.

Rules (decided for Otakio's long-term maintenance):
  1. keiyoushi-generated entries follow upstream: a site removed from keiyoushi/extensions-source is removed here
     right away (keiyoushi also removes sites at their owner's request); a site that moved to a new domain gets the
     new baseUrl here and is probed again.
  2. Every other entry (native, yuzono, cursed, NOBORU parsers) is removed after DEAD_DAYS days in a row of failed
     health checks (repo/health.json keeps "deadSince", see probe_sources.merge_health).
  3. OPT_OUT: sites whose owner asked to be left out, never published again.

Every removal is appended to repo/removed.json and listed in repo/REMOVED.md. gen_repo.py skips removed ids, so a
regeneration does not bring them back (delete the line from removed.json to restore one).

  python tools/prune_repo.py --kei <keiyoushi clone> [--days 180] [--probe] [--dry-run]
"""
import argparse, json, os, re, shutil, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_repo, probe_sources

ROOT = gen_repo.ROOT
REPO = os.path.join(ROOT, "repo")
REMOVED_JSON = os.path.join(REPO, "removed.json")
REMOVED_MD = os.path.join(REPO, "REMOVED.md")
DEAD_DAYS = 180

# site owners who asked to be left out: {extension id or host: "reason"}
OPT_OUT = {}


def load_removed():
    if os.path.exists(REMOVED_JSON):
        return json.load(open(REMOVED_JSON, encoding="utf8"))
    return []


def removed_ids():
    """ids gen_repo.py must not publish again"""
    return {r["id"] for r in load_removed()}


def save_removed(log):
    with open(REMOVED_JSON, "w", encoding="utf8", newline="\n") as fh:
        json.dump(log, fh, ensure_ascii=False, indent=1)
    lines = ["# Removed extensions", "",
             "Extensions taken out of the catalog, newest first. Installed copies keep working on the device; the app",
             "marks them as *Removed from repository*.", "",
             "Reasons: **removed upstream** (no longer in keiyoushi/extensions-source), **dead** (failed every daily",
             "check for more than %d days), **site closed**, **opt-out** (the site owner asked; see REMOVAL.md)." % DEAD_DAYS,
             "", "| Date | Extension | Site | Reason |", "|---|---|---|---|"]
    for r in sorted(log, key=lambda r: r.get("date", ""), reverse=True):
        lines.append("| %s | %s | %s | %s |" % (r.get("date", ""), r.get("name", r["id"]), gen_repo.host_of(r.get("baseUrl", "")), r["reason"]))
    with open(REMOVED_MD, "w", encoding="utf8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def kei_source_of(entry):
    """'lang_dir/pkg' from the header line of a keiyoushi-generated extension file"""
    path = os.path.join(REPO, entry.get("file", ""))
    if not os.path.isfile(path):
        return None
    m = re.search(r"keiyoushi/extensions-source: (\S+?)/(\S+?)\)?\s*$", open(path, encoding="utf8").readline())
    return (m.group(1), m.group(2)) if m else None


def days_since(date):
    try:
        return (time.time() - time.mktime(time.strptime(date, "%Y-%m-%d"))) / 86400
    except (TypeError, ValueError):
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kei", help="keiyoushi/extensions-source clone (build.gradle.kts files are enough)")
    ap.add_argument("--days", type=int, default=DEAD_DAYS)
    ap.add_argument("--probe", action="store_true", help="probe sources whose domain changed")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    today = time.strftime("%Y-%m-%d")

    idx = json.load(open(os.path.join(REPO, "index.json"), encoding="utf8"))
    health = probe_sources.load_health()
    log = load_removed()
    remove, moved = {}, []

    for e in idx["extensions"]:
        h = health.get(e["id"]) or {}
        if e["id"] in OPT_OUT or gen_repo.host_of(e["baseUrl"]) in OPT_OUT:
            remove[e["id"]] = "opt-out"
            continue
        if e.get("origin") == "keiyoushi" and args.kei:
            src = kei_source_of(e)
            if src:
                gradle = os.path.join(args.kei, "src", src[0], src[1], "build.gradle.kts")
                if not os.path.exists(gradle):
                    remove[e["id"]] = "removed upstream"
                    continue
                hosts = {gen_repo.host_of(s["baseUrl"]): s["baseUrl"] for s in gen_repo.parse_gradle(open(gradle, encoding="utf8").read())[4]
                         if "$" not in s["baseUrl"]}
                if hosts and gen_repo.host_of(e["baseUrl"]) not in hosts:
                    moved.append((e, sorted(hosts.values())[0]))
            continue  # keiyoushi entries follow upstream only
        if h.get("status") == "dead":
            since = h.get("deadSince") or h.get("checked") or today
            if days_since(since) > args.days:
                remove[e["id"]] = "dead since %s" % since

    print("domain changes:")
    for e, new in moved:
        print("  %-32s %s -> %s" % (e["id"], e["baseUrl"], new))
    print("removals:")
    for ext_id, why in remove.items():
        print("  %-32s %s" % (ext_id, why))
    if args.dry_run:
        return

    targets = []
    for e, new in moved:
        path = os.path.join(REPO, e["file"])
        text = open(path, encoding="utf8").read().replace(e["baseUrl"], new)
        open(path, "w", encoding="utf8", newline="\n").write(text)
        e["baseUrl"] = new
        health.pop(e["id"], None)
        for k in ("health", "checked"):
            e.pop(k, None)
        targets.append({"id": e["id"], "engine": "native", "baseUrl": new, "lang": e["lang"], "file": e["file"]})
    kept = []
    for e in idx["extensions"]:
        why = remove.get(e["id"])
        if not why:
            kept.append(e)
            continue
        log.append({"id": e["id"], "name": e.get("name"), "baseUrl": e.get("baseUrl"), "origin": e.get("origin"), "date": today,
                    "reason": why})
        if e.get("file") and os.path.isfile(os.path.join(REPO, e["file"])):
            os.remove(os.path.join(REPO, e["file"]))
        health.pop(e["id"], None)
    idx["extensions"] = kept
    if args.probe and targets:
        probe_sources.merge_health(health, probe_sources.run(targets, workers=1, verbose=False))
        for e, _ in moved:
            h = health.get(e["id"])
            if h:
                e["health"], e["checked"] = h["status"], h.get("checked")
                e["compat"] = {"dead": "broken", "partial": "partial"}.get(h["status"], "full")
    probe_sources.save_health(health)
    gen_repo.hash_entries(idx["extensions"], REPO)
    json.dump(idx, open(os.path.join(REPO, "index.json"), "w", encoding="utf8", newline="\n"), ensure_ascii=False, separators=(",", ":"))
    save_removed(log)
    # keep the bundled test catalog in sync
    bundled = os.path.join(ROOT, "source", "repo")
    shutil.rmtree(bundled, ignore_errors=True)
    shutil.copytree(REPO, bundled, ignore=shutil.ignore_patterns("native", "health.json", "removed.json", ".git", ".github", "*.md", "LICENSE"))
    print("catalog: %d extensions, %d removed in total" % (len(kept), len(log)))


if __name__ == "__main__":
    main()
