"""Health check for Otakio sources: runs the real Lua engines against each site.

  python tools/probe_sources.py                 # probe every engine-based entry of repo/index.json
  python tools/probe_sources.py --only kei.en.  # id prefix filter
  python tools/probe_sources.py --file my.lua   # test a new extension file
  python tools/probe_sources.py --candidates file.json   # used by gen_repo.py for theme auto-detection

Writes repo/health.json: {id: {status, popular, chapters, pages, checked, movedTo?, site?}}
status: ok (pages load) | partial (listing works, chapters/pages don't) | dead (nothing works)
site (dead sources only), what the site's home page does: gone (no answer: DNS, connection, TLS, a 5xx error) | parked (a domain
parking page) | blocked (403/429/503 to this machine: a CI runner's address is often refused, the console may not be)
| cloudflare (a challenge page: the console can't pass it either) | up (it answers: the extension is what broke).
tools/prune_repo.py leaves "blocked" sources in the catalog.
movedTo: the site answers from another address now (its own sends visitors there) and the extension works there; the
app sends the source's requests to it (see sourceprefs.lua), so nobody has to wait for a new extension version
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
    # the engine decodes GIF and AVIF itself since engine 2
    if r.get("pages") and r.get("image") in (None, "ok", "gif", "avif"):
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
    if best["status"] == "dead":
        best["site"] = "cloudflare" if best.get("cloudflare") else site_state(entry["baseUrl"])
    if chosen and chosen[0] in ("Madara", "MangaThemesia"):
        # remember what worked (gen_repo.py reuses it for auto-detected sources)
        best["engine"] = chosen[0]
        best["cfg"] = {k: v for k, v in chosen[1].items() if k in ("mangaSubString", "mangaUrlDirectory")}
    return entry["id"], best


# where expired or sold domains end up: never a site's new home
PARKING = ("sedo.", "parkingcrew", "bodis.", "hugedomains", "dan.com", "afternic", "godaddy", "namecheap", "porkbun",
           "parklogic", "above.com", "/lander")


def site_state(url, timeout=15):
    """Why a dead source's site fails, from its home page: gone | parked | blocked | cloudflare | up (see the top)"""
    import socket, ssl, urllib.error, urllib.request
    from lua_engine import UA, _ctx, vita_url
    try:
        req = urllib.request.Request(vita_url(url), headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout, context=_ctx) as r:
            final, body = r.geturl(), r.read(200000).decode("utf8", "replace")
    except urllib.error.HTTPError as e:
        try:
            body = e.read(20000).decode("utf8", "replace")
        except Exception:
            body = ""
        if "<title>Just a moment...</title>" in body or "cf-chl-" in body:
            return "cloudflare"
        if e.code in (403, 429, 503):
            return "blocked"
        # 500-530 (Cloudflare's 52x: the site behind it doesn't answer): the server is down
        return "gone" if 500 <= e.code < 600 else "up"
    except (urllib.error.URLError, socket.timeout, ssl.SSLError, ConnectionError, OSError):
        return "gone"
    except Exception:
        return "gone"
    low = (final + " " + body[:20000]).lower()
    if any(p in low for p in PARKING):
        return "parked"
    if "<title>just a moment...</title>" in low or "cf-chl-" in low:
        return "cloudflare"
    return "up"


def origin_of(url):
    """'https://Host.example:443/x' -> 'https://host.example' (scheme and host; a port only when it isn't the default)"""
    scheme, _, rest = (url or "").partition("://")
    host = rest.split("/", 1)[0].split("?", 1)[0].lower()
    if host.endswith(":443") or host.endswith(":80"):
        host = host.rsplit(":", 1)[0]
    return scheme.lower() + "://" + host


def host_key(url):
    host = origin_of(url).split("://", 1)[-1]
    return host[4:] if host.startswith("www.") else host


def find_move(base_url, timeout=15):
    """The address a site answers from now, when its own sends visitors to another host (an HTTP redirect or a meta
    refresh); None when it stays on its host, nothing answers, or the new place is a parking page"""
    import re, urllib.error, urllib.parse, urllib.request
    from lua_engine import UA, _ctx
    try:
        req = urllib.request.Request(base_url.rstrip("/") + "/", headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout, context=_ctx) as r:
            target, body = r.geturl(), r.read(300000).decode("utf8", "replace")
    except urllib.error.HTTPError as err:
        # the redirect was followed but the new place answered with an error (a block page...): its address still
        # counts, the extension's own probe there decides
        target, body = err.geturl() or base_url, ""
    except Exception:
        return None
    if host_key(target) == host_key(base_url):
        m = re.search(r"""<meta[^>]+http-equiv=["']?refresh["']?[^>]*url=['"]?([^"'>\s]+)""", body, re.I)
        if not m:
            return None
        target = urllib.parse.urljoin(target, m.group(1))
    if host_key(target) == host_key(base_url) or not target.startswith("http") or any(p in target.lower() for p in PARKING):
        return None
    return origin_of(target)


def probe_moved(entry, new_origin):
    """Probes the extension with its address swapped for `new_origin` (a temporary copy of its file)"""
    import tempfile
    path = entry["file"] if os.path.isabs(entry["file"]) else os.path.join(ROOT, "repo", entry["file"])
    old = origin_of(entry["baseUrl"])
    text = open(path, encoding="utf8").read()
    if old not in text:
        return None
    tmp = os.path.join(tempfile.mkdtemp(prefix="otakio_moved_"), os.path.basename(path))
    open(tmp, "w", encoding="utf8").write(text.replace(old, new_origin))
    moved = dict(entry, file=tmp, baseUrl=new_origin)
    return probe_entry(moved)[1]


def detect_moves(entries, results, workers=8, verbose=True):
    """Sources whose list doesn't load: if their address now leads to another domain where the extension works
    better, the result becomes that one, with movedTo = the new address"""
    rank = {"ok": 2, "partial": 1, "dead": 0}
    cands = [en for en in entries if en.get("baseUrl") and not (results.get(en["id"]) or {}).get("popular")]

    def one(en):
        new = find_move(en["baseUrl"])
        return en, new, probe_moved(en, new) if new else None

    with ThreadPoolExecutor(max_workers=max(1, workers)) as pool:
        for en, new, r in pool.map(one, cands):
            old = results.get(en["id"]) or {}
            if r and r.get("popular") and rank.get(r["status"], 0) > rank.get(old.get("status"), 0):
                r["movedTo"] = new
                results[en["id"]] = r
                if verbose:
                    print("moved   %s  %s -> %s  (%s)" % (en["id"], en["baseUrl"], new, r["status"]), flush=True)
    return results


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
    tools/prune_repo.py removes sources dead for more than 90 days.
    A downgrade (ok -> partial, ok/partial -> dead) needs two checks in a row: the first one only keeps the last
    result with "pending" = {status, since}, so a site that failed once (a timeout, a bad minute) doesn't flicker
    in the app. An upgrade counts at once. A dead run started that way dates from the first failed check."""
    today = today or time.strftime("%Y-%m-%d")
    rank = {"ok": 2, "partial": 1, "dead": 0}
    for ext_id, r in results.items():
        old = health.get(ext_id) or {}
        r = dict(r)
        new_rank, old_rank = rank.get(r.get("status"), 0), rank.get(old.get("status"))
        pending = old.get("pending") if isinstance(old.get("pending"), dict) else None
        if old_rank is not None and new_rank < old_rank and not pending:
            # first worse result: keep the last one, wait for the next check to confirm it
            kept = dict(old)
            kept["pending"] = {"status": r.get("status"), "since": today}
            if r.get("error"):
                kept["pending"]["error"] = r["error"]
            health[ext_id] = kept
            continue
        first_fail = pending.get("since") if pending and r.get("status") == "dead" and pending.get("status") == "dead" else None
        r.pop("pending", None)
        if ci and r.get("status") == "dead" and (r.get("cloudflare") or r.get("blocked")) and old.get("status") in ("ok", "partial"):
            # worked before, blocked now from a CI runner: keep the last real result, flag it, don't start the clock
            kept = dict(old)
            kept["unverified"] = today
            health[ext_id] = kept
            continue
        r.pop("unverified", None)
        if r.get("status") == "dead":
            r["deadSince"] = old.get("deadSince") if old.get("status") == "dead" and old.get("deadSince") else (first_fail or today)
        else:
            r.pop("deadSince", None)
        r["lastOk"] = today if r.get("status") in ("ok", "partial") else old.get("lastOk")
        if r["lastOk"] is None:
            r.pop("lastOk")
        health[ext_id] = r
    return health


def issue_of(h):
    """Where a source that doesn't fully work stops, for the app to say it in words (None when it works):
    blocked (Cloudflare/anti-bot page) | list | chapters | pages | images (pages found, the image server refuses)"""
    if not h or h.get("status") == "ok":
        return None
    if h.get("cloudflare") or h.get("blocked"):
        return "blocked"
    if not h.get("popular"):
        return "list"
    if not h.get("chapters"):
        return "chapters"
    if not h.get("pages"):
        return "pages"
    return "images"


def set_issue(entry, h):
    issue = issue_of(h)
    if issue:
        entry["issue"] = issue
    else:
        entry.pop("issue", None)


def set_moved(entry, h):
    """movedTo travels from health.json to the index entry (the app reads it there)"""
    if h and h.get("movedTo"):
        entry["movedTo"] = h["movedTo"]
    else:
        entry.pop("movedTo", None)


def apply_health(entries, health):
    """Copies health.json results into index entries (health, checked, compat, issue, unverified)"""
    for e in entries:
        h = health.get(e["id"])
        if not h or e.get("relay"):
            continue
        e["health"], e["checked"] = h["status"], h.get("checked")
        e["compat"] = {"dead": "broken", "partial": "partial"}.get(h["status"], "full")
        set_issue(e, h)
        set_moved(e, h)
        if h.get("unverified"):
            e["unverified"] = h["unverified"]
        else:
            e.pop("unverified", None)


def prune_health(health, ids):
    """Drops the entries of extensions no longer in the catalog (removed, replaced, filtered out); returns how many"""
    gone = [k for k in health if k not in ids]
    for k in gone:
        del health[k]
    return len(gone)


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
    ap.add_argument("--file", help="probe one extension file (not yet in index.json) and print the result; health.json is not touched")
    args = ap.parse_args()
    if args.file:
        head = {}
        for line in open(args.file, encoding="utf8"):
            if line.startswith("-- @"):
                k, _, v = line[4:].strip().partition(" ")
                head[k] = v.strip()
        ext_id, r = probe_entry({"id": head.get("id", "file"), "engine": "native", "file": os.path.abspath(args.file),
                                 "baseUrl": head.get("baseUrl", ""), "lang": head.get("lang", "en"), "name": head.get("name", "probe")})
        print(ext_id, json.dumps(r, ensure_ascii=False))
        sys.exit(0 if r["status"] == "ok" else 1)
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
    detect_moves(entries, results, workers=min(args.workers, 8))
    health = load_health()
    merge_health(health, results, ci=args.ci)
    pruned = prune_health(health, {e["id"] for e in index["extensions"]})
    if pruned:
        print("health.json: dropped %d entries of extensions no longer in the catalog" % pruned)
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
