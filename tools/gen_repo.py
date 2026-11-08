"""Builds the Otakio extension repository.

Sources:
  1. Mihon extension source trees using keiyoushi's gradle DSL
     (keiyoushi/extensions-source, yuzono/tachiyomi-extensions, yuzono/cursed-manga-extensions):
     every site built on a theme Otakio has an engine for (see ENGINES) becomes a tiny Lua
     extension that calls the engine. Simple Kotlin overrides (selectors, paths, flags) are
     copied into the extension config.
  2. Creckeryop/NOBORU-parsers: classic NOBORU parsers run unchanged in Otakio, so they are
     listed with their raw GitHub URL (downloaded on demand, not copied).
  3. repo/native/*.lua: hand written Otakio extensions (metadata in a header comment).

The same site published by several repositories is listed once (highest version wins).
With --probe every engine-based source is tested against the live site (listing, chapters,
pages); dead ones are marked "broken" (hidden by default in the app). Results are cached
in repo/health.json and reused by later runs without --probe.

Usage:
  python tools/gen_repo.py --kei <dir> --noboru <dir> [--yuzono <dir>] [--cursed <dir>] [--probe]

Output: repo/index.json + repo/extensions/*.lua, and the same tree copied into
source/repo (bundled in the VPK as the built-in, offline repository).
"""
import argparse, json, os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
ENGINES = {
    "madara": "Madara", "mangathemesia": "MangaThemesia",
    # engines_extra.lua
    "keyoapp": "Keyoapp", "zeistmanga": "ZeistManga", "heancms": "HeanCms", "mangacatalog": "MangaCatalog",
    "foolslide": "FoolSlide", "guya": "Guya", "mangak": "MangaK", "yiimanga": "YiiManga", "yiimadara": "YiiMadara",
    "vinetheme": "VineTheme", "pizzareader": "PizzaReader",
    # engines_intl.lua (ru / ja / zh)
    "grouple": "Grouple", "libgroup": "LibGroup", "multichan": "MultiChan", "fmreader": "FMReader", "natsuid": "NatsuId", "mangareader": "MangaReader", "liliana": "Liliana",
}
# per-site settings that keiyoushi keeps in Kotlin code instead of build.gradle.kts
SITE_EXTRA = {
    # LibGroup: the API tells the sites apart by a Site-Id header
    "mangalib": {"siteId": 1}, "slashlib": {"siteId": 2}, "hentailib": {"siteId": 4},
    # MangaReader: page parameter and ajax endpoint are Kotlin functions
    "jmanga": {"pageParam": "p", "searchPathSegment": "", "searchKeyword": "q", "chapterIdSelect": "ja-chaps", "ajaxPath": "/json/chapter?mode=vertical&id=%s"},
    "rawotaku": {"pageParam": "p", "searchPathSegment": "", "searchKeyword": "q", "chapterIdSelect": "ja-chaps", "ajaxPath": "/json/chapter?mode=vertical&id=%s"},
}
# themes ported in engines_extra.lua take any simple `override val/fun` as config
EXTRA_THEMES = set(ENGINES) - {"madara", "mangathemesia"}
NOBORU_RAW = "https://raw.githubusercontent.com/Creckeryop/NOBORU-parsers/master/parsers/"

# Kotlin `override val x = "..."` we can translate to engine config keys
SIMPLE_OVERRIDES = {
    "mangaSubString": "mangaSubString",
    "mangaUrlDirectory": "mangaUrlDirectory",
}
SAFE_OVERRIDE_RE = re.compile(
    r"override\s+(?:val|fun)\s+(mangaSubString|mangaUrlDirectory|chapterMode|genreDirectory|"
    r"filterNonMangaItems|sendViewCount|supportsPostId|datePattern|dateFormat|pageSize|"
    r"orderByFilterOptions|statusFilterOptions|useNewChapterEndpoint|useLoadMoreRequest|"
    r"altNamePrefix|seriesTypeSelector|projectPageString|hasProjectPage|adultFilterOptions|"
    r"archiveSelector|archiveUrlSelector|archiveTitleSelector|chapterListSelector|chapterNameSelector|pageListParseSelector)\b"
)
CONFIG_KEYS = ["id", "name", "baseUrl", "lang", "version", "nsfw", "extension", "mangaSubString", "mangaUrlDirectory", "chapterMode",
               "archiveSelector", "archiveUrlSelector", "archiveTitleSelector", "chapterListSelector", "chapterNameSelector", "pageListSelector"]
# `override val name: Type = "x" | true | 12` and `override fun name(): String = "x"`
GENERIC_OVERRIDE_RE = re.compile(
    r'override\s+(?:val|fun)\s+(\w+)(?:\(\))?\s*(?::\s*[\w?]+)?\s*=\s*("(?:[^"\\$]|\\.)*"|true|false|-?\d+)\s*$', re.M)
SOURCE_LIST_RE = re.compile(r'Pair\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)')

# Markers used to recognise WordPress manga themes inside hand-written Kotlin sources
MADARA_MARKERS = re.compile(r"admin-ajax|wp-manga|page-item-detail|manga_get_chapters|madara", re.I)
THEMESIA_MARKERS = re.compile(r"readerarea|ts_reader|listupd|bsx", re.I)
NOT_LISTING_SEGMENTS = {"wp-admin", "ajax", "page", "genre", "comic-genre", "manga-genre", "wp-content", "search", "tag"}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def _blocks(text, keyword):
    """Bodies of every `keyword { ... }` block, with nested braces (baseUrl { custom(...) }) kept inside."""
    for m in re.finditer(r"\b%s\s*\{" % keyword, text):
        depth, i = 1, m.end()
        while i < len(text) and depth:
            depth += {"{": 1, "}": -1}.get(text[i], 0)
            i += 1
        yield text[m.end():i - 1]


def parse_gradle(text):
    """Returns (name, theme, nsfw, version, [sources]) from a keiyoushi-style build.gradle.kts."""
    name = re.search(r'\bname\s*=\s*"([^"]+)"', text)
    theme = re.search(r'\btheme\s*=\s*"([^"]+)"', text)
    cw = re.search(r"contentWarning\s*=\s*ContentWarning\.(\w+)", text)
    version = re.search(r"versionCode\s*=\s*(\d+)", text)
    sources = []
    for body in _blocks(text, "source"):
        lang = re.search(r'\blang\s*=\s*"([^"]+)"', body)
        # baseUrl = "..." | baseUrl { custom("...") } | mirrors("...", ...)
        base = (re.search(r'\bbaseUrl\s*=\s*"([^"]+)"', body) or re.search(r'custom\(\s*"([^"]+)"', body)
                or re.search(r'mirrors\(\s*"([^"]+)"', body))
        sname = re.search(r'\bname\s*=\s*"([^"]+)"', body)
        if lang and base:
            sources.append({"lang": lang.group(1), "baseUrl": base.group(1).rstrip("/"), "name": sname.group(1) if sname else None})
    return (
        name.group(1) if name else None,
        theme.group(1) if theme else None,
        (cw.group(1) if cw else "SAFE") == "NSFW",
        int(version.group(1)) if version else 0,
        sources,
    )


def parse_overrides(ext_dir, theme=None):
    """Extracts simple engine overrides and decides if the source is fully supported."""
    cfg, compat = {}, "full"
    generic = theme in EXTRA_THEMES
    for dirpath, _, files in os.walk(ext_dir):
        for f in files:
            if not f.endswith(".kt"):
                continue
            src = open(os.path.join(dirpath, f), encoding="utf8").read()
            for key, cfg_key in SIMPLE_OVERRIDES.items():
                m = re.search(r"override\s+val\s+" + key + r"(?:\s*:\s*String)?\s*=\s*\"([^\"]*)\"", src)
                if m:
                    cfg[cfg_key] = m.group(1)
            # selectors of the newer keiyoushi Madara lib (`override fun archiveSelector() = "..."`)
            for key in ("archiveSelector", "archiveUrlSelector", "archiveTitleSelector", "chapterListSelector", "chapterNameSelector", "pageListParseSelector"):
                m = re.search(r"override\s+(?:val|fun)\s+" + key + r"(?:\(\))?(?:\s*:\s*String)?\s*=\s*\"([^\"]*)\"", src)
                if m:
                    cfg["pageListSelector" if key == "pageListParseSelector" else key] = m.group(1)
            m = re.search(r"override\s+val\s+chapterMode\s*=\s*ChapterMode\.(\w+)", src)
            if m:
                cfg["chapterMode"] = m.group(1)
            simple = set()
            if generic:
                for key, raw in GENERIC_OVERRIDE_RE.findall(src):
                    simple.add(key)
                    if key in ("id", "version", "extension", "nsfw", "versionId"):
                        continue
                    cfg[key] = json.loads(raw) if raw[0] == '"' else (raw == "true" if raw in ("true", "false") else int(raw))
                if theme == "mangacatalog" and "sourceList" in src:
                    simple.add("sourceList")
                    block = src.split("sourceList", 1)[1].split("\n    )", 1)[0]
                    block = re.sub(r"//[^\n]*", "", block)
                    cfg["sourceList"] = [list(x) for x in SOURCE_LIST_RE.findall(block)]
            overrides = re.findall(r"override\s+(?:suspend\s+)?(?:val|fun)\s+(\w+)", src)
            if [o for o in overrides if o not in simple and not SAFE_OVERRIDE_RE.match("override val " + o)]:
                compat = "partial"
    return cfg, compat


def lua_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    return lua_str(v)


def write_extension(out_dir, ext_id, engine, cfg, header):
    lines = ["-- Otakio extension (%s)" % header, "Engines.%s {" % ENGINES[engine]]
    keys = [k for k in CONFIG_KEYS if k in cfg] + sorted(k for k in cfg if k not in CONFIG_KEYS)
    for k in keys:
        lines.append("\t%s = %s," % (k, lua_value(cfg[k])))
    lines.append("}")
    fname = ext_id + ".lua"
    with open(os.path.join(out_dir, "extensions", fname), "w", encoding="utf8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    return "extensions/" + fname


def make_entry(ext_id, cfg, engine, origin, compat, out_dir, header):
    return {
        "id": ext_id,
        "name": cfg["name"],
        "lang": cfg["lang"],
        "version": cfg["version"],
        "nsfw": cfg["nsfw"],
        "engine": engine,
        "baseUrl": cfg["baseUrl"],
        "file": write_extension(out_dir, ext_id, engine, cfg, header),
        "origin": origin,
        "compat": compat,
        "_cfg": cfg,
    }


def build_keiyoushi_format(root, out_dir, origin, prefix, repo_label):
    """Any repository using keiyoushi's gradle DSL (keiyoushi, yuzono, cursed-manga-extensions...)."""
    entries = []
    src_root = os.path.join(root, "src")
    for lang_dir in sorted(os.listdir(src_root)):
        if not os.path.isdir(os.path.join(src_root, lang_dir)):
            continue
        for pkg in sorted(os.listdir(os.path.join(src_root, lang_dir))):
            ext_dir = os.path.join(src_root, lang_dir, pkg)
            gradle = os.path.join(ext_dir, "build.gradle.kts")
            if not os.path.exists(gradle):
                continue
            name, theme, nsfw, version, sources = parse_gradle(open(gradle, encoding="utf8").read())
            if theme not in ENGINES or not name or not sources:
                continue
            overrides, compat = parse_overrides(ext_dir, theme)
            for src in sources:
                lang = src["lang"] if len(sources) > 1 else lang_dir
                ext_id = prefix + "." + lang.lower() + "." + pkg.lower()
                cfg = {
                    # keep "KEI_" ids stable: library entries reference them
                    "id": prefix.upper() + "_" + re.sub(r"[^A-Z0-9]", "", (src["lang"] + "_" + pkg).upper()),
                    "name": src["name"] or name,
                    "baseUrl": src["baseUrl"],
                    "lang": src["lang"],
                    "version": version + 1,
                    "nsfw": nsfw,
                    "extension": ext_id,
                }
                cfg.update(SITE_EXTRA.get(pkg.lower(), {}))
                for k, v in overrides.items():
                    if k == "sourceList":
                        # "$baseUrl/manga/x" inside Kotlin string templates
                        v = [[n, u.replace("${baseUrl}", src["baseUrl"]).replace("$baseUrl", src["baseUrl"])] for n, u in v]
                    cfg[k] = v
                entries.append(make_entry(ext_id, cfg, theme, origin, compat, out_dir, "generated from %s: %s/%s" % (repo_label, lang_dir, pkg)))
    return entries


NOBORU_LANG = {"ENG": "en", "RUS": "ru", "ESP": "es", "PRT": "pt", "BRA": "pt-BR", "FRA": "fr", "JAP": "ja", "DIF": "all",
               "TUR": "tr", "ITA": "it", "VIE": "vi", "DEU": "de", "POL": "pl", "IDN": "id", "CHN": "zh", "ROU": "ro",
               "KOR": "ko", "RAW": "ja", "THA": "th", "ARA": "ar"}


# keep in sync with REPLACED_BY in source/assets/libs/extensions.lua
NOBORU_REPLACED = {"noboru.mangadex", "noboru.mangadexdif", "noboru.mangakakalot"}

# sites that shut down for good (domain gone, parked/for sale, "website closed" page); checked 2026-11-03.
# Sites that are only behind Cloudflare are NOT listed: they are alive and stay in the catalog as dead.
CLOSED_SITES = {
    "noboru.batodif", "noboru.hensharkdif", "noboru.ninehentaien", "noboru.hencafeng", "noboru.hencafengv2",
    "noboru.mangareaderen", "noboru.mangasee", "noboru.mangafast", "noboru.mangaowlen", "noboru.rcomiconlinetoeng",
    "noboru.vlcomic", "noboru.xoxocen", "noboru.ninemangaspa", "noboru.doujinhentaiesp", "noboru.mangalibrosesp",
    "noboru.tmangaonlesp", "noboru.goldenmangas", "noboru.animeregiaptg", "noboru.brmangaspt", "noboru.unionmangaspt",
    "kei.en.anisascans", "kei.en.auntmanhwa", "kei.en.mangahe", "kei.es.esmi2manga", "kei.pt.starlightscan",
}


def hash_entries(entries, repo_dir):
    """Pins every published file with its SHA-256: the app refuses a download whose hash differs (tampering,
    corruption). Entries with an external "url" (NOBORU parsers) are not pinned: their upstream may change."""
    import hashlib
    for e in entries:
        path = os.path.join(repo_dir, e.get("file") or "")
        if e.get("file") and os.path.isfile(path):
            e["sha256"] = hashlib.sha256(open(path, "rb").read()).hexdigest()
        else:
            e.pop("sha256", None)


def build_noboru(noboru_root):
    entries = []
    readme = open(os.path.join(noboru_root, "README.md"), encoding="utf8").read()
    broken = {re.sub(r"\W", "", b).lower() for b in re.findall(r"~~(.+?)~~", readme)}
    pdir = os.path.join(noboru_root, "parsers")
    for f in sorted(os.listdir(pdir)):
        if not f.endswith(".lua"):
            continue
        text = open(os.path.join(pdir, f), encoding="utf8", errors="replace").read()
        found = re.findall(r'Parser:new\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,?\s*(\d*)', text)
        if not found:
            continue
        name, link, lang, pid, ver = found[0]
        nsfw = bool(re.search(r"\.NSFW\s*=\s*true", text))
        is_broken = re.sub(r"\W", "", name).lower() in broken
        if "noboru." + pid.lower() in NOBORU_REPLACED:
            continue  # dead site API, an Otakio native extension replaces it
        entries.append({
            "id": "noboru." + pid.lower(),
            "name": name if len(found) == 1 else name + " (+%d)" % (len(found) - 1),
            "lang": NOBORU_LANG.get(lang, "all") if len(found) == 1 else "all",
            "version": int(ver or 1),
            "nsfw": nsfw,
            "engine": "noboru",
            "baseUrl": link,
            "url": NOBORU_RAW + f.replace(" ", "%20"),
            "origin": "noboru",
            "compat": "broken" if is_broken else "full",
        })
    return entries


def build_native(out_dir):
    entries = []
    ndir = os.path.join(ROOT, "repo", "native")
    if not os.path.isdir(ndir):
        return entries
    for f in sorted(os.listdir(ndir)):
        if not f.endswith(".lua"):
            continue
        text = open(os.path.join(ndir, f), encoding="utf8").read()
        meta = dict(re.findall(r"^--\s*@(\w+)\s+(.+?)\s*$", text, re.M))
        ext_id = meta.get("id", "otakio." + f[:-4].lower())
        shutil.copy(os.path.join(ndir, f), os.path.join(out_dir, "extensions", ext_id + ".lua"))
        entries.append({
            "id": ext_id,
            "name": meta.get("name", f[:-4]),
            "lang": meta.get("lang", "all"),
            "version": int(meta.get("version", "1")),
            "nsfw": meta.get("nsfw", "false") == "true",
            "engine": "native",
            "baseUrl": meta.get("baseUrl", ""),
            "file": "extensions/" + ext_id + ".lua",
            "origin": "otakio",
            # offered by the app's first-run "Install recommended sources" button (filtered by language and NSFW)
            "recommended": True,
            "compat": "full",
            "relay": meta.get("relay") == "true",
        })
    return entries


def host_of(url):
    return re.sub(r"^www\.", "", re.sub(r"^https?://", "", url).split("/")[0].lower())


def dedupe(entries):
    """Same site published by several repositories: keep the highest version (first wins on ties)."""
    by_key, out = {}, []
    for e in entries:
        if e["engine"] not in ENGINES:
            out.append(e)
            continue
        key = (host_of(e["baseUrl"]), e["lang"].lower())
        kept = by_key.get(key)
        if kept is None:
            by_key[key] = e
            out.append(e)
        elif e["version"] > kept["version"]:
            out[out.index(kept)] = e
            by_key[key] = e
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kei", required=True, help="keiyoushi/extensions-source clone")
    ap.add_argument("--noboru", required=True, help="Creckeryop/NOBORU-parsers clone")
    ap.add_argument("--yuzono", help="yuzono/tachiyomi-extensions clone")
    ap.add_argument("--cursed", help="yuzono/cursed-manga-extensions clone (source of mojuru/cursed-manga-repo)")
    ap.add_argument("--probe", action="store_true", help="test every source live and mark dead ones (slow)")
    ap.add_argument("--langs", default="en,pt-BR,pt,es,es-419,fr,de,it,ru,ja,zh,zh-Hans,zh-Hant,all",
                    help="languages to publish (comma separated, Mihon codes; 'all' = multi-language sources)")
    args = ap.parse_args()
    import probe_sources

    out = os.path.join(ROOT, "repo")
    shutil.rmtree(os.path.join(out, "extensions"), ignore_errors=True)
    os.makedirs(os.path.join(out, "extensions"))
    entries = build_native(out)
    entries += build_noboru(args.noboru)
    entries += build_keiyoushi_format(args.kei, out, "keiyoushi", "kei", "keiyoushi/extensions-source")
    if args.yuzono:
        entries += build_keiyoushi_format(args.yuzono, out, "yuzono", "yzn", "yuzono/tachiyomi-extensions")
    if args.cursed:
        entries += build_keiyoushi_format(args.cursed, out, "cursed", "cursed", "yuzono/cursed-manga-extensions")
    import prune_repo  # removed.json: extensions taken out by tools/prune_repo.py stay out
    skip = CLOSED_SITES | prune_repo.removed_ids()
    entries = [e for e in entries if e["id"] not in skip]
    allowed = {x.strip().lower() for x in args.langs.split(",") if x.strip()}
    dropped = [e for e in entries if e["lang"].lower() not in allowed]
    entries = [e for e in entries if e["lang"].lower() in allowed]
    print("language filter %s: dropped %d entries" % (sorted(allowed), len(dropped)))
    before = len(entries)
    entries = dedupe(entries)
    keep = {e.get("file") for e in entries}
    for f in os.listdir(os.path.join(out, "extensions")):
        if "extensions/" + f not in keep:
            os.remove(os.path.join(out, "extensions", f))
    print("deduplicated %d entries published by more than one repository" % (before - len(entries)))

    health = probe_sources.load_health()
    if args.probe:
        targets = []
        for e in entries:
            if e["engine"] in ENGINES and "_health" not in e:
                # probe the generated extension file itself: exactly what the app will run
                targets.append({"id": e["id"], "engine": "native", "baseUrl": e["baseUrl"], "lang": e["lang"], "file": e["file"]})
        print("probing %d sources live..." % len(targets))
        probe_sources.merge_health(health, probe_sources.run(targets, verbose=False))
    for e in entries:
        if "_health" in e:
            health[e["id"]] = e.pop("_health")
        e.pop("_cfg", None)
        h = health.get(e["id"])
        if e.get("relay"):
            # TLS 1.3-only site: works on the Vita only through a relay, never "broken"
            e["health"] = "relay"
        elif h:
            e["health"] = h["status"]
            e["checked"] = h.get("checked")
            if h["status"] == "dead":
                e["compat"] = "broken"
            elif h["status"] == "partial":
                e["compat"] = "partial"
            elif h["status"] == "ok":
                e["compat"] = "full"  # verified working, even if the Kotlin source had custom code
    probe_sources.save_health(health)

    hash_entries(entries, out)
    index = {"name": "Otakio Extensions", "format": 1, "minEngine": 1, "extensions": entries}
    with open(os.path.join(out, "index.json"), "w", encoding="utf8", newline="\n") as fh:
        json.dump(index, fh, ensure_ascii=False, separators=(",", ":"))
    bundled = os.path.join(ROOT, "source", "repo")
    shutil.rmtree(bundled, ignore_errors=True)
    shutil.copytree(out, bundled, ignore=shutil.ignore_patterns("native", "health.json", ".git", ".github", "*.md", "LICENSE"))
    stats = {}
    langs = {}
    for e in entries:
        langs[e["lang"]] = langs.get(e["lang"], 0) + 1
    print("by language:", langs)
    for e in entries:
        o = stats.setdefault(e["origin"], {"total": 0, "full": 0, "partial": 0, "broken": 0})
        o["total"] += 1
        o[e["compat"]] += 1
    print("extensions:", len(entries))
    for k, v in stats.items():
        print("  %-10s %s" % (k, v))


if __name__ == "__main__":
    main()
