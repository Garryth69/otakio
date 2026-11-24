"""Writes the weekly status report of the extension catalog (Markdown), for the "Catalog status" issue that
status.yml in otakio-extensions keeps up to date. Meant to be read after weeks or months away: what works, what
changed since the previous week, what the automation did and whether the robots themselves are healthy.

  python tools/status_report.py --old <health.json a week ago> [--runs runs.json] [--out report.md]

repo/health.json, repo/sync.json (last weekly sync), repo/removed.json and repo/index.json are read from the
extension repository clone in repo/. runs.json is `gh run list --json workflowName,conclusion,createdAt` output.
"""
import argparse, collections, json, os, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.join(ROOT, "repo")


def load(path, default):
    try:
        with open(path, encoding="utf8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", help="health.json of the previous report (missing: no comparison)")
    ap.add_argument("--runs", help="workflow runs as JSON (gh run list --json workflowName,conclusion,createdAt)")
    ap.add_argument("--out")
    args = ap.parse_args()

    health = load(os.path.join(REPO, "health.json"), {})
    old = load(args.old, {}) if args.old else {}
    index = load(os.path.join(REPO, "index.json"), {"extensions": []})
    names = {e["id"]: e.get("name", e["id"]) for e in index.get("extensions", [])}
    sync = load(os.path.join(REPO, "sync.json"), {})
    removed = load(os.path.join(REPO, "removed.json"), [])
    runs = load(args.runs, []) if args.runs else []
    today = time.strftime("%Y-%m-%d", time.gmtime())

    count = collections.Counter(h.get("status") for h in health.values())
    old_count = collections.Counter(h.get("status") for h in old.values())

    def delta(status):
        if not old:
            return ""
        d = count[status] - old_count[status]
        return " (%+d)" % d if d else ""

    out = ["_Updated %s by the status workflow. Read this after time away: everything below happened on its own._" % today, ""]
    out += ["## Sources", "",
            "| Working | Partial | Down | Total |", "|---:|---:|---:|---:|",
            "| %d%s | %d%s | %d%s | %d%s |" % (count["ok"], delta("ok"), count["partial"], delta("partial"), count["dead"], delta("dead"),
                                              len(health), (" (%+d)" % (len(health) - len(old))) if old and len(health) != len(old) else ""), ""]

    dead_sites = collections.Counter(h.get("site") or "unknown" for h in health.values() if h.get("status") == "dead")
    if dead_sites:
        words = {"gone": "site down", "parked": "domain parked", "blocked": "refuse the robot only",
                 "cloudflare": "browser check", "up": "site changed", "unknown": "not classified yet"}
        out += ["Down, by cause: " + ", ".join("%s %d" % (words.get(k, k), n) for k, n in dead_sites.most_common()), ""]

    def label(i):
        return "%s (`%s`)" % (names.get(i, i), i)

    broke = sorted(i for i, h in health.items() if old.get(i, {}).get("status") == "ok" and h.get("status") != "ok")
    back = sorted(i for i, h in health.items() if i in old and old[i].get("status") != "ok" and h.get("status") == "ok")
    moved = sorted((i, h.get("movedTo")) for i, h in health.items() if h.get("movedTo") and not old.get(i, {}).get("movedTo"))
    if old:
        out += ["### Changes since last week", ""]
        if not (broke or back or moved):
            out.append("Nothing changed.")
        LIMIT = 25

        def capped(items):
            return items[:LIMIT], max(0, len(items) - LIMIT)

        shown, more = capped(broke)
        for i in shown:
            out.append("- stopped working: %s, now %s" % (label(i), health[i].get("status")))
        if more:
            out.append("- ... and %d more that stopped working" % more)
        shown, more = capped(back)
        for i in shown:
            out.append("- working again: %s" % label(i))
        if more:
            out.append("- ... and %d more working again" % more)
        for i, to in moved:
            out.append("- site moved: %s -> %s (requests follow it already; the weekly sync applies it to the file)" % (label(i), to))
        out.append("")

    out += ["## Weekly sync with keiyoushi", ""]
    if sync:
        out.append("Last run: %s." % sync.get("date", "?"))
        for a in sync.get("added", []):
            out.append("- new source added (passed a live test): %s, %s" % (label(a["id"]), a.get("baseUrl", "")))
        for m in sync.get("moved", []):
            out.append("- new domain applied: %s -> %s" % (label(m["id"]), m["to"]))
        for r in sync.get("removed", []):
            out.append("- removed: %s (%s)" % (label(r["id"]), r["reason"]))
        held = sync.get("held", [])
        if held:
            out += ["", "**Held back for a person** (more removals than the safety limit; run `tools/prune_repo.py` by hand"
                    " with a higher `--max-removals` after checking them):"]
            for r in held:
                out.append("- %s (%s)" % (label(r["id"]), r["reason"]))
        if sync.get("deferred"):
            out.append("- %d more sources dead for 90 days leave in the next weeks (at most 8 a week)" % len(sync["deferred"]))
        for u in (sync.get("updated") or [])[:25]:
            out.append("- fixed from keiyoushi's code: %s (`%s`), %s -> %s" % (u.get("name", u["id"]), u["id"], u.get("from"), u.get("to")))
        if sync.get("kept"):
            out.append("- %d sources dead for 90 days kept: their site refuses the robot's machine only, the console may "
                       "still read them (%s)" % (len(sync["kept"]), ", ".join("`%s`" % k for k in sync["kept"][:10])))
        if not (sync.get("added") or sync.get("moved") or sync.get("removed") or held or sync.get("deferred") or sync.get("kept") or sync.get("updated")):
            out.append("Nothing to do.")
    else:
        out.append("No sync recorded yet.")
    out.append("")
    recent = [r for r in removed if r.get("date", "") >= time.strftime("%Y-%m-%d", time.gmtime(time.time() - 90 * 86400))]
    if recent:
        out.append("Removed in the last 90 days: %d (see REMOVED.md)." % len(recent))
        out.append("")

    out += ["## Robots", ""]
    if runs:
        by = collections.defaultdict(list)
        for r in runs:
            # runs still going (this very report) or skipped by their own conditions say nothing about health
            if r.get("conclusion") not in (None, "", "skipped"):
                by[r.get("workflowName", "?")].append(r)
        out += ["| Workflow | Last run | Result | Failures in the last 10 |", "|---|---|---|---:|"]
        alarm = False
        for name in sorted(by):
            rs = sorted(by[name], key=lambda r: r.get("createdAt", ""), reverse=True)[:10]
            fails = sum(1 for r in rs if r.get("conclusion") == "failure")
            last = rs[0]
            out.append("| %s | %s | %s | %d |" % (name, last.get("createdAt", "")[:10], last.get("conclusion"), fails))
            alarm = alarm or (len(rs) >= 3 and all(r.get("conclusion") == "failure" for r in rs[:3]))
        if alarm:
            out += ["", "**A robot failed its last 3 runs.** Open the Actions tab of this repository to see why."]
    else:
        out.append("No run data.")
    out.append("")

    text = "\n".join(out) + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf8") as fh:
            fh.write(text)
    else:
        print(text)


if __name__ == "__main__":
    main()
