"""Publishes, updates or withdraws an engine patch in the catalog (repo/index.json "patches").

An engine patch fixes a theme engine (source/assets/libs/engines*.lua) for every installed app, without a new app
version: when a site theme changes its pages, dozens of sources break at once and only an engine change brings them
back. The app downloads the official catalog's patches (sha256 checked), runs them in the extension sandbox at
start-up before any extension, and rebuilds the installed extensions when a patch arrives. A patch replaces or wraps
Engines.* functions, for example:

    local base = Engines.Madara
    Engines.Madara = function(cfg)
        local p = base(cfg)
        local getChapters = p.getChapters
        function p:getChapters(manga, dt)
            getChapters(self, manga, dt)
            if #dt == 0 then
                -- the theme's new chapter list ...
            end
        end
        return p
    end

The same fix also goes into engines*.lua for the next release; --max-app makes the patch stop at the version that
carries it (the app ignores a patch outside minApp..maxApp). The health check (tools/lua_engine.py) applies the
catalog's patches too, so its results show the sources as the app runs them.

  python tools/add_patch.py repo/patches/madara-chapters.lua [--id madara-chapters] [--min-app 1.1.5] [--max-app 1.1.5]
  python tools/add_patch.py --remove madara-chapters

Then re-probe the theme's sources (python tools/probe_sources.py ...), run python tools/validate_repo.py and commit in
repo/. Removing a patch from the index removes it from every app on its next catalog refresh.
"""
import argparse, json, os, shutil, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_repo

REPO = os.path.join(gen_repo.ROOT, "repo")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("file", nargs="?", help="the patch (a .lua file; copied into repo/patches/ when it is elsewhere)")
    ap.add_argument("--id", help="patch id (default: the file name)")
    ap.add_argument("--min-app", help="first app version it applies to")
    ap.add_argument("--max-app", help="last app version it applies to (the one before the release that has the fix)")
    ap.add_argument("--remove", metavar="ID", help="withdraw a patch")
    args = ap.parse_args()

    path = os.path.join(REPO, "index.json")
    idx = json.load(open(path, encoding="utf8"))
    patches = idx.setdefault("patches", [])
    if args.remove:
        keep = [p for p in patches if p["id"] != args.remove]
        if len(keep) == len(patches):
            sys.exit("no patch %s" % args.remove)
        gone = [p for p in patches if p["id"] == args.remove][0]
        if os.path.exists(os.path.join(REPO, gone["file"])):
            os.remove(os.path.join(REPO, gone["file"]))
        patches[:] = keep
        print("withdrawn:", args.remove)
    else:
        if not args.file or not args.file.endswith(".lua"):
            sys.exit("give the patch's .lua file")
        pid = args.id or os.path.splitext(os.path.basename(args.file))[0]
        rel = "patches/%s.lua" % pid
        dest = os.path.join(REPO, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        if os.path.abspath(args.file) != os.path.abspath(dest):
            shutil.copy(args.file, dest)
        entry = next((p for p in patches if p["id"] == pid), None)
        if entry is None:
            entry = {"id": pid, "version": 0}
            patches.append(entry)
        entry["version"] = int(entry.get("version", 0)) + 1
        entry["file"] = rel
        for key, value in (("minApp", args.min_app), ("maxApp", args.max_app)):
            if value:
                entry[key] = value
        gen_repo.hash_entries([entry], REPO)
        print("patch %s v%d (%s)" % (pid, entry["version"], rel))
    if not patches:
        idx.pop("patches", None)
    with open(path, "w", encoding="utf8", newline="\n") as fh:
        json.dump(idx, fh, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
