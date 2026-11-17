"""Madara fallback for sites with their own card design (engines.lua madaraParseLinks) and for readers that number
their page images, run offline on a fixture page.
python tools/tests/test_madara_fallback.py"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from lua_engine import Engine

BASE = "https://site.example"

LISTING = """<!DOCTYPE html><html><body class="archive header-style-1 is-sidebar">
<header><nav class="main-menu"><a href="%(b)s/manga/menu-pick/"><img src="%(b)s/m.jpg" alt="Menu Pick"></a></nav></header>
<div class="aqua-mega-menu__card"><a href="%(b)s/manga/mega-pick/"><img src="%(b)s/mega.jpg" alt="Mega"></a></div>
<div class="hero-slider"><a href="%(b)s/manga/slide-pick/"><img src="%(b)s/s.jpg" alt="Slide"></a></div>
<div class="site-content"><div class="aqua-manga-grid">
  <article class="aqua-manga-card">
    <a href="%(b)s/manga/first-series/" class="cover"><img src="%(b)s/first.jpg" alt="First cover">
      <div class="badges"><span>hot</span></div></a>
    <div class="body"><h3><a href="%(b)s/manga/first-series/">First Series</a></h3>
      <a href="%(b)s/manga/first-series/chapter-10/">Chapter 10</a></div>
  </article>
  <article class="asura-card"><div class="poster">
    <a href="%(b)s/manga/second-series/" aria-label="Second Series"><img src="%(b)s/second.jpg" alt=""></a></div>
    <div class="body"><a href="%(b)s/manga/second-series/" title="Second Series"> </a></div>
  </article>
  <div class="tile"><div><img src="%(b)s/third.jpg" alt="Third Series"></div><a href="%(b)s/manga/third-series/"> </a></div>
  <div class="tile"><a href="%(b)s/manga/no-cover/">No Cover</a></div>
</div>
<a href="%(b)s/manga/page/2/">2</a>
<aside><a href="%(b)s/manga/aside-pick/"><img src="%(b)s/a.jpg" alt="Aside"></a></aside>
</div></body></html>""" % {"b": BASE}

CLASSIC = """<html><body><div class="page-item-detail"><div class="post-title"><a href="%(b)s/manga/classic/">Classic</a></div>
<img src="%(b)s/c.jpg"></div><div class="tile"><a href="%(b)s/manga/extra/"><img src="%(b)s/e.jpg" alt="Extra"></a></div>
</body></html>""" % {"b": BASE}

READER = """<html><body><div class="asura-theater-reader reading-manga"><div class="stream">
<img src="%(b)s/p/1.webp" data-page="1"><img src="%(b)s/p/2.webp" data-page="2"><img src="%(b)s/logo.png">
</div></div></body></html>""" % {"b": BASE}

pages = {}


def fetch(url, method, body, headers):
    if method == "POST":
        return ""  # no madara_load_more: the engine falls back to the GET listing
    return pages.get(url.split("?")[0], "")


e = Engine()
e.L.globals().PY_FETCH = fetch
L = e.L
L.globals().P = e.create("Madara", {"id": "T", "name": "T", "baseUrl": BASE, "lang": "en"})


def listing(html):
    pages[BASE + "/manga/"] = html
    L.execute("POP = {}; RUN(function() P:getPopularManga(1, POP) end)")
    got = []
    for i in range(1, L.eval("#POP") + 1):
        m = L.eval("POP[%d]" % i)
        cover = m.ImageLink
        if not isinstance(cover, str) and cover is not None:
            cover = cover.Link
        got.append((m.Name, m.Link, cover))
    return got


got = listing(LISTING)
names = [g[0] for g in got]
assert names == ["First Series", "Second Series", "Third Series"], names
assert got[0][1].endswith("/manga/first-series/") and got[0][2] == BASE + "/first.jpg", got[0]
assert got[1][2] == BASE + "/second.jpg", got[1]
assert got[2][2] == BASE + "/third.jpg", got[2]

# a page the known selectors understand is read as before: the fallback doesn't add other links
names = [g[0] for g in listing(CLASSIC)]
assert names == ["Classic"], names

pages[BASE + "/manga/x/chapter-1/"] = READER
L.execute('PG = {}; RUN(function() P:prepareChapter({Link = "/manga/x/chapter-1/", Name = "1", Manga = {}}, PG) end)')
links = []
for i in range(1, L.eval("#PG") + 1):
    v = L.eval("PG[%d]" % i)
    links.append(v if isinstance(v, str) else v.Link)
assert links == [BASE + "/p/1.webp", BASE + "/p/2.webp"], links

# the paged reader keeps its pages in a script (written by PHP: trailing comma)
pages[BASE + "/manga/x/chapter-2/"] = """<html><body><div class="reading-content"></div><script>
var chapter_images_per_page = 1, chapter_preloaded_images=[{"src":"%(b)s/q/1.jpg"},{"src":"%(b)s/q/2.jpg"},];
</script></body></html>""" % {"b": BASE}
L.execute('PG = {}; RUN(function() P:prepareChapter({Link = "/manga/x/chapter-2/", Name = "2", Manga = {}}, PG) end)')
got = [L.eval("PG[%d]" % i) for i in range(1, L.eval("#PG") + 1)]
got = [g if isinstance(g, str) else g.Link for g in got]
assert got == [BASE + "/q/1.jpg", BASE + "/q/2.jpg"], got

# a skin with its own reader: img.reader-page inside .reader-pages
pages[BASE + "/manga/x/chapter-3/"] = """<html><body><div class="reader-pages"><img class="reader-page" src="%(b)s/r/1.webp">
<img class="reader-page" src="%(b)s/r/2.webp"></div></body></html>""" % {"b": BASE}
L.execute('PG = {}; RUN(function() P:prepareChapter({Link = "/manga/x/chapter-3/", Name = "3", Manga = {}}, PG) end)')
got = [L.eval("PG[%d]" % i) for i in range(1, L.eval("#PG") + 1)]
got = [g if isinstance(g, str) else g.Link for g in got]
assert got == [BASE + "/r/1.webp", BASE + "/r/2.webp"], got

# a skin with its own chapter rows: links one level below the series page, newest first, labels for names
pages[BASE + "/manga/own-rows/"] = """<html><body><nav><a href="/manga/own-rows/menu-link/">Menu</a></nav>
<div class="chapter-list-full"><div class="chapter-row-full"><a class="chapter-link" href="/manga/own-rows/capitulo-2/">
<img src="t.webp"><span class="chapter-num">Capitulo 2</span><span class="chapter-date">20.10.26</span></a></div>
<div class="chapter-row-full"><a class="chapter-link" href="/manga/own-rows/capitulo-1/"><span class="chapter-num">Capitulo 1</span></a></div>
</div><a href="/manga/own-rows/capitulo-1/page/2/">deeper</a><a href="/manga/other/">other</a></body></html>"""
L.execute('CH = {}; RUN(function() P:getChapters({Link = "/manga/own-rows/", Name = "x"}, CH) end)')
names = [L.eval("CH[%d].Name" % i) for i in range(1, L.eval("#CH") + 1)]
assert names == ["Capitulo 1", "Capitulo 2"], names
assert L.eval("CH[2].Link") == "/manga/own-rows/capitulo-2/" and L.eval("CH[2].Date") == "20.10.26"
print("madara fallback: OK")
