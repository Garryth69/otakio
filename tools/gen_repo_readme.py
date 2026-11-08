"""Writes repo/README.md (the extension repository's front page) from repo/index.json.

  python tools/gen_repo_readme.py

Run it after gen_repo.py / probe_sources.py so the source list and the status column stay current.
"""
import collections, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.join(ROOT, "repo")

LANGS = [("all", "Multi-language"), ("en", "English"), ("pt-BR", "Portuguese (Brazil)"), ("pt", "Portuguese"),
         ("es", "Spanish"), ("es-419", "Spanish (Latin America)"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
         ("ru", "Russian"), ("ja", "Japanese"), ("zh", "Chinese"), ("zh-Hans", "Chinese (Simplified)"), ("zh-Hant", "Chinese (Traditional)")]
STATUS = {"ok": "🟢 works", "partial": "🟡 partial", "dead": "🔴 down", "relay": "🟡 relay", None: "⚪ untested"}
ORIGIN = {
    "otakio": "native (Otakio)",
    "keiyoushi": "keiyoushi theme",
    "yuzono": "yuzono theme",
    "cursed": "cursed theme",
    "noboru": "NOBORU parser",
}

HEADER = """# Otakio Extensions

**Source extensions** for [Otakio](https://github.com/Garryth69/otakio), a manga reader for the PS Vita. The app ships
without any source: they are installed from this repository, inside the app.

## Using it on the Vita

- **First launch:** on the last setup screen, pick **Install recommended sources**. It adds this repository and installs
  Otakio's own sources for your languages.
- **Any time:**
  1. Open **Extensions** and press **Select** → **Add repository**.
  2. Type `Garryth69/otakio-extensions` and confirm.
  3. In the **Available** tab, switch language with **Start** and install sources with **X**.

The app checks this repository for updates at startup. When an extension gets a new version here, the app's **Updates**
tab offers it with one click.

## Legal notice

- **No content is hosted here.** Each extension is a script that, on the user's console, reads public pages of a
  third-party website, the way a browser would.
- This project has no affiliation with the listed websites, publishers or authors. Site names only identify where an
  extension reads from.
- No extension works around anti-bot protection (Cloudflare and similar), paywalls or logins. Sites that require that
  are marked as down.
- **Removal requests:** see [REMOVAL.md](REMOVAL.md). Removed sources are listed in [REMOVED.md](REMOVED.md).
- Support the authors: buy official releases and use official services.

## Summary

{summary}

Status:
- **🟢 works:** listing, chapters and pages tested;
- **🟡 partial:** something fails;
- **🔴 down:** the site doesn't answer or blocks readers;
- **⚪ untested.**

The status below comes from the latest automated check (`health.json`). On the Vita, each source's dot also adjusts
itself with use.

## Sources
"""

FOOTER = """
## Repository layout

| Path | Contents |
|---|---|
| `index.json` | catalog read by the app (id, name, language, version, file, status) |
| `extensions/` | published extensions, one `.lua` per source |
| `native/` | source code of the native extensions (sites with their own API or layout) |
| `health.json` | latest automated test result of each source, with `deadSince`/`lastOk` history |
| `removed.json`, `REMOVED.md` | sources taken out of the catalog, with date and reason |

### `index.json` format

```json
{{
  "name": "Otakio Extensions", "format": 1, "minEngine": 1,
  "extensions": [
    {{"id": "otakio.mangapill", "name": "Mangapill", "lang": "en", "version": 1, "nsfw": false,
      "engine": "native", "baseUrl": "https://mangapill.com", "file": "extensions/otakio.mangapill.lua",
      "origin": "otakio", "compat": "full", "health": "ok", "checked": "2026-11-03", "recommended": true}}
  ]
}}
```

`file` is relative to `index.json` (or `url`, absolute). The app reinstalls an extension when `version` goes up.
Anyone can host their own repository in this format and add it in the app.

### How the extensions are made

Mihon/Tachiyomi extensions are Kotlin APKs for Android and don't run on the Vita. Otakio reimplements in Lua the
**themes** many sites share (Madara, MangaThemesia, Keyoapp, ZeistManga, FoolSlide, MangaCatalog, YiiManga,
VineTheme, HeanCms, Guya, PizzaReader, Grouple, GalleryAdults...). For those sites an extension is just a theme
configuration. Sites with their own structure have **native** extensions, hand-written in `native/`.

The catalog is generated, tested and pruned by tools in the app repository (`tools/gen_repo.py`,
`tools/probe_sources.py`, `tools/prune_repo.py`, `tools/gen_repo_readme.py`):
- keiyoushi-based sources follow keiyoushi (removed there = removed here);
- other sources are removed after 180 days down in a row.

## Credits

- **[keiyoushi/extensions-source](https://github.com/keiyoushi/extensions-source)** (Apache 2.0): the theme logic and the
  site list of the "keiyoushi theme" extensions were adapted from their Kotlin code.
- **[yuzono/tachiyomi-extensions](https://github.com/yuzono/tachiyomi-extensions)** and
  **[yuzono/cursed-manga-extensions](https://github.com/yuzono/cursed-manga-extensions)** (Apache 2.0): configurations of
  sites that use the same themes.
- **[Creckeryop/NOBORU-parsers](https://github.com/Creckeryop/NOBORU-parsers)**: the classic NOBORU parsers ("NOBORU
  parser") are downloaded straight from the original repository, not copied here.
- **The [Mihon](https://github.com/mihonapp/mihon)/Tachiyomi community**, for the extension and repository model.
- **Native extensions and Lua port:** Garryth69, with AI assistance (Claude, by Anthropic).

## License

[Apache 2.0](LICENSE). See [NOTICE.md](NOTICE.md) for third-party attributions.
"""


def main():
    index = json.load(open(os.path.join(REPO, "index.json"), encoding="utf-8"))
    exts = index["extensions"]
    by_lang = collections.defaultdict(list)
    for e in exts:
        by_lang[e["lang"]].append(e)
    ok = sum(1 for e in exts if e.get("health") == "ok")
    lines = ["| Language | Sources | 🟢 working |", "|---|---:|---:|"]
    for code, label in LANGS:
        items = by_lang.get(code, [])
        if items:
            lines.append(f"| {label} | {len(items)} | {sum(1 for e in items if e.get('health') == 'ok')} |")
    lines.append(f"| **Total** | **{len(exts)}** | **{ok}** |")
    out = [HEADER.format(summary="\n".join(lines))]
    for code, label in LANGS:
        items = by_lang.get(code, [])
        if not items:
            continue
        order = {"ok": 0, "partial": 1, "relay": 1, None: 2, "dead": 3}
        items.sort(key=lambda e: (order.get(e.get("health"), 2), e["name"].lower()))
        out.append(f"\n### {label} ({len(items)})\n")
        out.append("| Source | Site | Status | Type | 18+ |")
        out.append("|---|---|---|---|:---:|")
        for e in items:
            host = e.get("baseUrl", "").replace("https://", "").replace("http://", "").rstrip("/")
            out.append(f"| {e['name'].replace('|', '/')} | {host} | {STATUS.get(e.get('health'), e.get('health'))} | "
                       f"{ORIGIN.get(e.get('origin'), e.get('origin'))} | {'yes' if e.get('nsfw') else ''} |")
    out.append(FOOTER.format())
    with open(os.path.join(REPO, "README.md"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(out))
    print("repo/README.md:", len(exts), "extensions")


if __name__ == "__main__":
    main()
