"""Runs Otakio's Lua source engines on the PC (LuaJIT via lupa) with real HTTP.
Used by probe_sources.py (health checks) and the tests."""
import os, ssl, urllib.request, urllib.error
from lupa import luajit21

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"


def ua_for(url):
    """Same choice as net.lua userAgentFor(): MangaDex blocks browser user agents, the app identifies itself"""
    return "Otakio/1.0" if "mangadex" in url.lower() else UA
_ctx = ssl.create_default_context()
# OTAKIO_TLS12=1 behaves like the old NOBORU engine: OpenSSL 1.0.2 -> TLS 1.2 at most, no ChaCha20/X25519.
VITA_CIPHERS = ("ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:"
                "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:"
                "ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES128-SHA:AES256-SHA")
if os.environ.get("OTAKIO_TLS12"):
    # old NOBORU engine
    _ctx.maximum_version = ssl.TLSVersion.TLSv1_2
    _ctx.set_ciphers(VITA_CIPHERS)
# default: the Otakio engine (curl 8 + OpenSSL 1.1.1, TLS 1.3)
# the Vita build does not verify certificates (no CA bundle on the console)
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE

BOOT = r'''
local ROOT = ...
string.rawsub = string.sub
Console = {error = function() end, write = function() end}
Notifications = {pushUnique = function() end, push = function() end}
Settings = {Language = "English", NSFW = true}
Language = {English = {}}
POST_METHOD = "POST"; XWWW = "form"; JSON = "json"
Parser = {}
function Parser:new(Name, Link, Lang, ID, Version)
  local p = {Name = Name, Link = Link, Lang = Lang, ID = ID, Version = Version}
  setmetatable(p, self); self.__index = self
  LAST_PARSER = p
  return p
end
function CreateManga(Name, Link, ImageLink, ParserID, RawLink, BrowserLink)
  if Name and Link and ImageLink and ParserID then
    return {Name = Name, Link = Link, ImageLink = ImageLink, ParserID = ParserID, RawLink = RawLink, BrowserLink = BrowserLink, Data = {}}
  end
end
dofile(ROOT .. "/source/assets/libs/utils.lua")
dofile(ROOT .. "/source/assets/libs/json.lua")
dofile(ROOT .. "/source/assets/libs/html.lua")
dofile(ROOT .. "/source/assets/libs/http.lua")
dofile(ROOT .. "/source/assets/libs/engines.lua")
dofile(ROOT .. "/source/assets/libs/engines_extra.lua")
-- like the app: os is gone after startup, only Clock keeps os.date/os.time
Clock = {date = os.date, now = os.time}
os = nil
function Http.request(o)
  local hdr = {}
  for k, v in pairs(o.headers or {}) do hdr[k] = v end
  local body = o.body
  if type(body) == "table" then body = o.contentType == "json" and Json.encode(body) or Http.form(body) end
  if o.contentType == "json" then hdr["Content-Type"] = "application/json" end
  return PY_FETCH(o.url, o.method or "GET", body or "", hdr)
end
function RUN(f, ...)
  local co = coroutine.create(f)
  local ok, err = coroutine.resume(co, ...)
  while ok and coroutine.status(co) ~= "dead" do ok, err = coroutine.resume(co) end
  if not ok then error(err, 0) end
end
'''


class Engine:
    def __init__(self, timeout=15):
        self.timeout = timeout
        self.requests = 0
        self.L = luajit21.LuaRuntime(unpack_returned_tuples=True)
        self.L.globals().PY_FETCH = self._fetch
        self.L.execute(BOOT, ROOT)

    def _fetch(self, url, method, body, headers):
        self.requests += 1
        h = {"User-Agent": ua_for(url)}
        for k, v in headers.items():
            h[k] = v
        data = None
        if method == "POST":
            data = (body or "").encode()
            h.setdefault("Content-Type", "application/x-www-form-urlencoded")
        try:
            req = urllib.request.Request(url, data=data, headers=h, method=method)
            with urllib.request.urlopen(req, timeout=self.timeout, context=_ctx) as r:
                return self._seen(r.read().decode("utf8", "replace"))
        except urllib.error.HTTPError as e:
            try:
                return self._seen(e.read().decode("utf8", "replace"))
            except Exception:
                return ""
        except Exception:
            return ""

    def _seen(self, body):
        # Cloudflare challenge pages need a real browser (JavaScript): the Vita can't pass them either
        head = body[:6000]
        if "<title>Just a moment...</title>" in head or "cf-chl-" in head or "Attention Required! | Cloudflare" in head or "cf-error-details" in head:
            self.cloudflare = True
        return body

    def fetch_bytes(self, url, headers):
        h = {"User-Agent": ua_for(url)}
        h.update(headers)
        try:
            req = urllib.request.Request(url, headers=h)
            with urllib.request.urlopen(req, timeout=self.timeout, context=_ctx) as r:
                return r.read(4 * 1024 * 1024)
        except urllib.error.HTTPError as e:
            return e.read(4096)
        except Exception:
            return b""

    def check_image(self):
        """Downloads the first page like the reader does: 'ok' when the Vita can decode it."""
        L = self.L
        try:
            L.execute("PL = {}; RUN(function() if P.loadChapterPage then P:loadChapterPage(PG[1], PL) end end)")
            L.execute("""
                local v = PL.Link or PG[1]
                IMG_URL, IMG_H = v, {}
                if type(v) == "table" then
                    IMG_URL = v.Link
                    for i = 1, 4 do
                        local hd = v["Header" .. i]
                        if type(hd) == "string" and hd:find(":") then IMG_H[#IMG_H + 1] = hd end
                    end
                end""")
            url = L.globals().IMG_URL
            if not isinstance(url, str) or not url:
                return "nolink"
            url = url.replace("%%", "%")
            if url.startswith("//"):
                url = "https:" + url
            headers = {}
            for hd in L.globals().IMG_H.values():
                k, v = hd.split(":", 1)
                headers[k.strip()] = v.strip()
            data = self.fetch_bytes(url, headers)
        except Exception as e:
            return "error"
        if data[:3] == bytes([0xFF, 0xD8, 0xFF]) or data[:4] == bytes([0x89, 0x50, 0x4E, 0x47]) or (data[:4] == b"RIFF" and data[8:12] == b"WEBP"):
            return "ok"
        if data[:3] == b"GIF":
            return "gif"
        if data[4:12] in (b"ftypavif", b"ftypavis"):
            return "avif"
        return "bad"

    def create(self, engine, cfg):
        """engine: 'Madara' | 'MangaThemesia' | path to a .lua extension file"""
        if engine.endswith(".lua"):
            self.L.execute("LAST_PARSER = nil; dofile(...)", engine.replace("\\", "/"))
        else:
            t = self.L.table_from(cfg, recursive=True)
            self.L.globals().Engines[engine](t)
        return self.L.globals().LAST_PARSER

    def check(self, parser, deep=True):
        """Returns dict(popular, chapters, pages, sample)"""
        L = self.L
        L.globals().P = parser
        res = {"popular": 0, "chapters": 0, "pages": 0}
        try:
            L.execute("POP = {}; RUN(function() P:getPopularManga(1, POP) end)")
        except Exception as e:
            res["error"] = str(e)[:160]
            return res
        res["popular"] = L.eval("#POP")
        if not res["popular"] or not deep:
            return res
        res["sample"] = L.eval("POP[1].Name")
        # try a couple of entries: some popular titles have no readable chapters
        for i in range(1, min(3, res["popular"]) + 1):
            try:
                L.execute(f"CH = {{}}; RUN(function() P:getChapters(POP[{i}], CH) end)")
                n = L.eval("#CH")
                if n:
                    res["chapters"] = n
                    L.execute("PG = {}; RUN(function() P:prepareChapter(CH[#CH], PG) end)")
                    res["pages"] = L.eval("#PG")
                    if res["pages"]:
                        res["image"] = self.check_image()
                        break
            except Exception as e:
                res["error"] = str(e)[:160]
        return res
