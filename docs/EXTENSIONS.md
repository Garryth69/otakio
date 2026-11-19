# Writing an Otakio extension

An extension is one Lua file that creates a **parser**: the object the app asks for lists, chapters and pages. The
catalog lives in [otakio-extensions](https://github.com/Garryth69/otakio-extensions); its README covers the
`index.json` format and how the catalog is generated. This page covers the code.

There are two kinds:

| Kind | When | Where |
|---|---|---|
| **Theme configuration** | the site runs a theme Otakio already implements (Madara, MangaThemesia, Keyoapp, ZeistManga, MangaCatalog, FoolSlide, GalleryAdults...) | generated from keiyoushi by `tools/gen_repo.py`; a few lines of settings |
| **Native** | the site has its own layout or API | hand-written in `repo/native/<name>.lua` |

Before writing a native extension, check `source/assets/libs/engines*.lua`: if the site uses a theme, a configuration
is enough.

## Header

Native files start with a metadata header. `gen_repo.py` turns it into the catalog entry, and the app reads the same
header for manual extensions (`ux0:data/otakio/extensions/manual/`).

```lua
-- @id otakio.example          (unique; becomes the file name)
-- @name Example
-- @lang en                    (or "all" plus "-- @langs en,es" for one source per language)
-- @version 1                  (raise it on every change: the app updates when it goes up)
-- @nsfw false
-- @baseUrl https://example.com
-- @api 2                      (optional: needs engine features newer than API level 1)
```

## A theme configuration

```lua
return Engines.Madara({
	id = "OTAKIO_EXAMPLE", name = "Example", baseUrl = "https://example.com", lang = "en", version = 1, nsfw = false,
	chapterMode = "MangaAjax",
})
```

Each theme's options are the keys its function reads from `cfg` in `engines*.lua` (selectors, paths, modes).

## A native parser

```lua
local U = Engines.util
local BASE = "https://example.com"
local p = U.newParser({id = "OTAKIO_EXAMPLE", name = "Example", baseUrl = BASE, lang = "en", version = 1, engine = "native"}, {})

function p:getPopularManga(page, dt)
	local doc = Http.getDocument(BASE .. "/popular?page=" .. page, {Referer = BASE .. "/"})
	for _, el in ipairs(doc:select("div.item")) do
		local a = el:selectFirst("a")
		local img = el:selectFirst("img")
		U.addManga(dt, p, a:text(), a:attr("abs:href"), img and img:attr("abs:src"))
	end
	dt.NoPages = doc:selectFirst("a.next") == nil
end

p.getLatestManga = p.getPopularManga

function p:searchManga(query, page, dt)
	-- query arrives encoded: Engines.decodeSearch(query) gives the text
end

function p:getChapters(manga, dt)
	-- dt.Description = "..."; manga.NewImageLink = Http.image(coverUrl, BASE .. "/")
	-- append chapters OLDEST FIRST: {Name = "...", Link = "/path", Date = "...", Pages = {}, Manga = manga}
end

function p:prepareChapter(chapter, dt)
	-- append one entry per page: a URL string, or Http.image(url, referer) when the site checks the Referer
end

function p:loadChapterPage(link, dt)
	dt.Link = link
end
```

| Method | Fills `dt` with |
|---|---|
| `getPopularManga(page, dt)`, `getLatestManga(page, dt)` | manga, through `U.addManga(dt, p, title, url, cover)`; `dt.NoPages = true` on the last page |
| `searchManga(query, page, dt[, tags])` | the same; `tags` holds the chosen values of `p.Filters`, when there are any |
| `getChapters(manga, dt)` | chapters, oldest first, plus `dt.Description` |
| `prepareChapter(chapter, dt)` | page images, in order |
| `loadChapterPage(link, dt)` | `dt.Link`: the final image address (most sources just copy it) |

The methods run inside a coroutine. Network calls give the frame back on their own; a long loop of your own should
call `coroutine.yield(false)` now and then.

## What an extension can use

- **`Http`**: `get`, `post`, `getDocument` (HTML), `postDocument`, `getJson`, `form` and `encode` (URL encoding),
  `image(url, referer, headers)` (a page or cover with request headers), `base64decode`.
- **`Html`**: a Jsoup-like API. It provides `select`, `selectFirst`, `text`, `ownText`, `wholeText` and `attr("abs:href")`,
  plus CSS selectors with `:has`, `:not`, `:contains`, `:containsOwn`, `:matches`, `:nth-child`, `:eq/:lt/:gt` and the
  `>`, `+` and `~` combinators. The engine runs both the parse and the selectors in C. The code is in
  `source/assets/libs/html.lua`.
- **`Json`**: `decode(text)` and `encode(value)`.
- **`Engines.util`**: `newParser`, `addManga`, `trim`, `absolute`, `pathOf`, `headers`, `date`, `srcsetBest`;
  `Engines.buildInfo(info, description)` builds the details text, and `Engines.decodeSearch(query)` decodes a search.

Extensions run in a **sandbox**: no `os`, `io`, `debug`, `require`, file system or app data, and settings are read-only.
Only download what the site serves to any visitor. Don't work around logins, captchas, Cloudflare challenges or hotlink
protection.

## Testing

Run the tools from the app repository, with Python and `lupa`. They load the app's own Lua code, so the engine under
test is the real one:

```sh
python tools/probe_sources.py --file repo/native/example.lua   # list, chapters, pages and one image, against the live site
python tools/trace_source.py otakio.example                     # the same, printing every request
python tools/validate_repo.py                                   # catalog consistency and SHA-256 pins
```

The daily health check in otakio-extensions runs the same probe on every source.

## Publishing

1. Put the file in `repo/native/`.
2. Regenerate the catalog with `tools/gen_repo.py`. It copies the file into `extensions/`, writes the entry and pins
   its SHA-256.
3. Open a pull request in otakio-extensions.

The app refuses any download whose hash doesn't match the index, so every file change needs the regenerated
`index.json`.
