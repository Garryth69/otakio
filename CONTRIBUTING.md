# Contributing to Otakio

Thanks for helping! Bug reports, source fixes, new sources and translations are all welcome.

- **App** (reader, interface, engines, translations): this repository.
- **Sources / catalog** (`index.json`, native extensions): [otakio-extensions](https://github.com/Garryth69/otakio-extensions).
- **Security problems**: do not open an issue, see [SECURITY.md](SECURITY.md).

## Ground rules for sources

Otakio only reads sites that a normal browser can open without tricks. A source is **not** accepted if it needs:

- bypassing Cloudflare or any other JavaScript/anti-bot challenge;
- defeating hotlink protection, image scrambling or deliberate encryption;
- logging in, or API keys taken from the site's web app;
- paid or DRM-protected content.

Site owners can ask for their site to be removed: see the extension repository's `REMOVAL.md`.

## Setup

Python 3 and:

```
pip install lupa pillow
git clone https://github.com/Garryth69/otakio-extensions repo   # only needed to work on sources
```

Everything runs on a PC: `tools/tests/sim.py` runs the whole app on a simulated Vita, and `tools/lua_engine.py`
runs the extension engines against the real sites.

## Before opening a pull request

```
python tools/check_syntax.py
python tools/run_lua.py tools/tests/test_core.lua
python tools/check_lang.py
python tools/tests/sim.py tour          # also: extensions, settings, lang, about, extlang, opensrc
python tools/tests/sim.py setup --setup
```

The same checks run in CI on every pull request. For interface changes, attach a screenshot
(`python tools/tests/sim.py <scenario> --shots 100,200` writes them to `tools/tests/screens/`).
If you have a Vita, say whether you tested on hardware.

Keep commits focused, written in English, and without personal data (paths, IPs, emails).

## Writing a native extension

A native extension is a single Lua file in the extension repository's `native/` folder. The header is required:

```lua
-- @id otakio.example
-- @name Example
-- @lang en
-- @version 1
-- @nsfw false
-- @baseUrl https://example.com
```

Most sites run a known theme. Then the file is just a configuration of one of the engines in
`source/assets/libs/engines*.lua` (`Madara`, `MangaThemesia`, `GalleryAdults`, `HeanCms`, `Keyoapp`, ...):

```lua
return Engines.Madara({id = "OTAKIO_EXAMPLE", name = "Example", baseUrl = "https://example.com", lang = "en", version = 1})
```

Otherwise, write the parser by hand with `Engines.util.newParser` and implement:

| Method | Fills `dt` with |
|---|---|
| `getPopularManga(page, dt)`, `getLatestManga(page, dt)`, `searchManga(query, page, dt)` | manga added with `Engines.util.addManga(dt, p, title, url, cover)`; set `dt.NoPages = true` on the last page |
| `getChapters(manga, dt)` | chapters `{Name, Link, Pages = {}, Manga = manga}`, **oldest first**; optionally `dt.Description` |
| `prepareChapter(chapter, dt)` | one entry per page (image URLs, or page URLs resolved later) |
| `loadChapterPage(link, dt)` | `dt.Link` = the final image (`Http.image(url, referer)`) |

`repo/native/mangatown.lua` is a complete, commented example. Extensions run sandboxed: no file system,
`io`, `os` or module loading. Use `Http.*` for network and `Engines.*` helpers for parsing.

Test it against the live site:

```
python tools/probe_sources.py --file repo/native/example.lua
```

It reports popular, chapter and page counts the way the app would see them, and exits with 0 only when real pages load. When you change an existing source,
bump `@version`, which is how installed copies learn there is an update.

## Translating the interface

Interface strings live in `source/assets/libs/lang_<code>.lua`, with English (`lang_en.lua`) as the reference.
Missing keys fall back to English.

- **Fix or complete a language:** edit its file, then run `python tools/check_lang.py`. It lists missing keys and
  any `%d`/`%s` placeholders that differ from English. Placeholders must match.
- **Add a language:**
  1. Copy `lang_en.lua` to `lang_<code>.lua` and rename the table (`Language.<Name>`).
  2. In `source/assets/libs/language.lua`, add the code to the load list, and the name to `ORDER`, `NATIVE`
     and `SYSTEM`. Map the Vita system language id in `SYSTEM_LANGUAGE` if one exists.
  3. Run `check_lang.py` and `python tools/tests/sim.py lang`.

## License

By contributing you agree that your work is released under the license of the repository you contribute to:
GPL-3.0 for the app, Apache-2.0 for the extension repository.
