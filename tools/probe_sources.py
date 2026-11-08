"""Health check for Otakio sources: runs the real Lua engines against each site.

  python tools/probe_sources.py                 # probe every engine-based entry of repo/index.json
  python tools/probe_sources.py --only kei.en.  # id prefix filter
  python tools/probe_sources.py --candidates file.json   # used by gen_repo.py for theme auto-detection

Writes repo/health.json: {id: {status, popular, chapters, pages, checked}}
status: ok (pages load) | partial (listing works, chapters/pages don't) | dead (nothing works)
"""
import argparse, json, os, sys, time, threading
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lua_engine import Engine, ROOT

HEALTH = os.path.join(ROOT, "repo", "health.json")
_local = threading.local()


def engine():
    if not hasattr(_local, "e"):
        _local.e = Engine()
    return _local.e


def status_of(r):
    """ok = the reader shows real pages | partial = something works (list, chapters) | dead = nothing"""
    if r.get("pages") and r.get("image") in (None, "ok"):
        return "ok"
    if r.get("popular"):
        return "partial"
    return "dead"


_host_locks = {}
_host_locks_guard = threading.Lock()


def host_lock(url):
    """One request stream per site at a time, whatever the number of workers (be gentle with small sites)"""
    host = (url.split("//", 1)[-1].split("/", 1)[0]).lower()
    with _host_locks_guard:
        return _host_locks.setdefault(host, threading.Lock())


def probe_entry(entry):
    """entry: {id, engine: madara|mangathemesia|native|auto, baseUrl, file?, cfg?, guesses?}"""
    e = engine()
    attempts = []
    if entry["engine"] == "native":
        attempts.append(("file", os.path.join(ROOT, "repo", entry["file"]), {}))
    elif entry["engine"] == "auto":
        for g in entry.get("guesses", []):
            attempts.append(g)
    else:
        cfg = dict(entry.get("cfg", {}))
        cfg.setdefault("baseUrl", entry["baseUrl"])
        attempts.append(("Madara" if entry["engine"] == "madara" else "MangaThemesia", None, cfg))
    best = {"popular": 0, "chapters": 0, "pages": 0}
    chosen = None
    for kind, path, cfg in attempts:
        cfg = dict(cfg)
        cfg.setdefault("id", "PROBE")
        cfg.setdefault("name", entry.get("name", "probe"))
        cfg.setdefault("lang", entry.get("lang", "en"))
        cfg.setdefault("baseUrl", entry["baseUrl"])
        try:
            e.cloudflare = False
            e.blocked = False
            with host_lock(entry["baseUrl"]):
                parser = e.create(path if kind == "file" else kind, cfg)
                r = e.check(parser)
            if e.cloudflare and not r.get("pages"):
                r["cloudflare"] = True
            if e.blocked and not r.get("pages"):
                r["blocked"] = True
        except Exception as ex:
            r = {"popular": 0, "chapters": 0, "pages": 0, "error": str(ex)[:160]}
        if (r.get("pages", 0), r.get("popular", 0)) > (best.get("pages", 0), best.get("popular", 0)):
            best, chosen = r, (kind, cfg)
        elif r.get("cloudflare") and not chosen:
            best["cloudflare"] = True
        if r.get("pages"):
            break
    best["status"] = status_of(best)
    best["checked"] = time.strftime("%Y-%m-%d")
    if chosen and chosen[0] in ("Madara", "MangaThemesia"):
        # remember what worked (gen_repo.py reuses it for auto-detected sources)
        best["engine"] = chosen[0]
        best["cfg"] = {k: v for k, v in chosen[1].items() if k in ("mangaSubString", "mangaUrlDirectory")}
    return entry["id"], best


def run(entries, workers=24, verbose=True):
    results = {}
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(probe_entry, en): en for en in entries}
        done = 0
        for fut in as_completed(futures):
            done += 1
            try:
                ext_id, r = fut.result()
            except Exception as ex:
                en = futures[fut]
                ext_id, r = en["id"], {"status": "dead", "error": str(ex)[:160]}
            results[ext_id] = r
            if verbose:
                print(f"[{done}/{len(entries)}] {r['status']:7} {ext_id}  pop={r.get('popular', 0)} ch={r.get('chapters', 0)} pg={r.get('pages', 0)}", flush=True)
    return results


def load_health():
    if os.path.exists(HEALTH):
        return json.load(open(HEALTH, encoding="utf8"))
    return {}


def merge_health(health, results, today=None, ci=False):
    """Merges probe results into health.json keeping a history per source:
    lastOk   = last day it worked (ok or partial)
    deadSince = first day of the current unbroken run of "dead" results (cleared when it works again)
    tools/prune_repo.py removes sources dead for more than 180 days."""
    today = today or time.strftime("%Y-%m-%d")
    for ext_id, r in results.items():
        old = health.get(ext_id) or {}
        r = dict(r)
        if ci and r.get("status") == "dead" and (r.get("cloudflare") or r.get("blocked")) and old.get("status") in ("ok", "partial"):
            # worked before, blocked now from a CI runner: keep the last real result, flag it, don't start the clock
            kept = dict(old)
            kept["unverified"] = today
            health[ext_id] = kept
            continue
        r.pop("unverified", None)
        if r.get("status") == "dead":
            r["deadSince"] = old.get("deadSince") if old.get("status") == "dead" and old.get("deadSince") else today
        else:
            r.pop("deadSince", None)
        r["lastOk"] = today if r.get("status") in ("ok", "partial") else old.get("lastOk")
        if r["lastOk"] is None:
            r.pop("lastOk")
        health[ext_id] = r
    return health


def apply_health(entries, health):
    """Copies health.json results into index entries (health, checked, compat, unverified)"""
    for e in entries:
        h = health.get(e["id"])
        if not h or e.get("relay"):
            continue
        e["health"], e["checked"] = h["status"], h.get("checked")
        e["compat"] = {"dead": "broken", "partial": "partial"}.get(h["status"], "full")
        if h.get("unverified"):
            e["unverified"] = h["unverified"]
        else:
            e.pop("unverified", None)


def save_health(h):
    with open(HEALTH, "w", encoding="utf8", newline="\n") as fh:
        json.dump(h, fh, ensure_ascii=False, indent=0, sort_keys=True)


CACHE = os.path.join(ROOT, "_ref", "probe_cache")


def fetch_parser(ext_id, url):
    import urllib.request
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, ext_id + ".lua")
    if not os.path.exists(path):
        try:
            with urllib.request.urlopen(url, timeout=20) as r:
                open(path, "wb").write(r.read())
        except Exception:
            return None
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--ids", help="file with one extension id per line")
    ap.add_argument("--workers", type=int, default=24)
    ap.add_argument("--ci", action="store_true", help="CI runner: blocks from a datacenter IP don't mark working sources dead")
    ap.add_argument("--update-index", action="store_true", help="also write the results into repo/index.json")
    args = ap.parse_args()
    index = json.load(open(os.path.join(ROOT, "repo", "index.json"), encoding="utf8"))
    entries = []
    wanted = set(open(args.ids).read().split()) if args.ids else None
    for e in index["extensions"]:
        if not e["id"].startswith(args.only):
            continue
        if wanted is not None and e["id"] not in wanted:
            continue
        if e.get("file"):
            # every engine-based or native extension: run its generated file as the app would
            entries.append({"id": e["id"], "engine": "native", "baseUrl": e["baseUrl"], "file": e["file"], "lang": e["lang"]})
        elif e.get("url"):
            # classic Lua parsers are downloaded from their repository, like the app installs them
            path = fetch_parser(e["id"], e["url"])
            if path:
                entries.append({"id": e["id"], "engine": "native", "baseUrl": e["baseUrl"], "file": path, "lang": e["lang"]})
    results = run(entries, args.workers)
    health = load_health()
    merge_health(health, results, ci=args.ci)
    save_health(health)
    if args.update_index:
        apply_health(index["extensions"], health)
        with open(os.path.join(ROOT, "repo", "index.json"), "w", encoding="utf8", newline="\n") as fh:
            json.dump(index, fh, ensure_ascii=False, separators=(",", ":"))
    counts = {}
    for r in results.values():
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print("summary:", counts)


if __name__ == "__main__":
    main()
