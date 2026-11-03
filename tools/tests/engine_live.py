"""Live smoke test for Otakio engines: runs the Lua engine code under LuaJIT with
Http.request backed by Python urllib. Usage: engine_live.py <engine> <baseUrl> [lang]"""
import sys, os, urllib.request, urllib.error, ssl
from lupa import luajit21
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))).replace("\\", "/")
engine, base = sys.argv[1], sys.argv[2]
lang = sys.argv[3] if len(sys.argv) > 3 else "en"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
ctx = ssl.create_default_context()
def fetch(url, method, body, headers):
    h = {"User-Agent": UA}
    for k, v in (headers or {}).items(): h[k] = v
    data = None
    if method == "POST":
        data = (body or "").encode()
        h["Content-Type"] = "application/x-www-form-urlencoded"
    try:
        req = urllib.request.Request(url, data=data, headers=h, method=method or "GET")
        with urllib.request.urlopen(req, timeout=25, context=ctx) as r:
            out = r.read().decode("utf8", "replace")
    except urllib.error.HTTPError as e:
        out = e.read().decode("utf8", "replace")
        print(f"  HTTP {e.code} {method} {url}")
    except Exception as e:
        print(f"  ERR {e} {url}"); out = ""
    print(f"  {method or 'GET'} {url} -> {len(out)} bytes")
    return out
L = luajit21.LuaRuntime(unpack_returned_tuples=True)
L.globals().py_fetch = fetch
L.execute(f'''
ROOT = "{root}"
Console = {{error = print, write = function() end}}
Notifications = {{pushUnique = print, push = print}}
Settings = {{Language = "English"}}
Language = {{English = {{}}}}
POST_METHOD = "POST"; XWWW = "form"; JSON = "json"
Parser = {{}}
function Parser:new(Name, Link, Lang, ID, Version) local p = {{Name=Name, Link=Link, Lang=Lang, ID=ID, Version=Version}}; setmetatable(p, self); self.__index = self; return p end
function CreateManga(Name, Link, ImageLink, ParserID, RawLink, BrowserLink) return {{Name=Name, Link=Link, ImageLink=ImageLink, ParserID=ParserID, RawLink=RawLink, BrowserLink=BrowserLink, Data={{}}}} end
dofile(ROOT .. "/source/assets/libs/json.lua")
dofile(ROOT .. "/source/assets/libs/html.lua")
dofile(ROOT .. "/source/assets/libs/http.lua")
dofile(ROOT .. "/source/assets/libs/engines.lua")
function Http.request(o)
  local hdr = {{}}
  for k, v in pairs(o.headers or {{}}) do hdr[k] = v end
  local body = o.body
  if type(body) == "table" then body = Http.form(body) end
  return py_fetch(o.url, o.method, body, hdr)
end
function run(f, ...) local co = coroutine.create(f); local ok, err = coroutine.resume(co, ...); while coroutine.status(co) ~= "dead" do ok, err = coroutine.resume(co) end; if not ok then error(err) end end
''')
lua = L.eval
if engine == "file":
    L.execute(f'local orig = Parser.new; function Parser:new(...) P = orig(self, ...); return P end; dofile("{base}")')
else:
    L.execute(f'P = Engines.{"Madara" if engine=="madara" else "MangaThemesia"}{{id="T", name="T", baseUrl="{base}", lang="{lang}"}}')
L.execute('pop = {}; run(function() P:getPopularManga(1, pop) end)')
n = lua('#pop'); print("popular:", n, "NoPages:", lua('pop.NoPages'))
for i in range(1, min(n, 3) + 1):
    print("  ", lua(f'pop[{i}].Name'), "|", lua(f'pop[{i}].Link'), "|", lua(f'type(pop[{i}].ImageLink)=="table" and pop[{i}].ImageLink.Link or pop[{i}].ImageLink'))
if n:
    L.execute('lat = {}; run(function() P:getLatestManga(1, lat) end)'); print("latest:", lua('#lat'))
    L.execute('srch = {}; run(function() P:searchManga(pop[1].Name:match("^(%S+)"), 1, srch) end)'); print("search:", lua('#srch'))
    L.execute('ch = {}; run(function() P:getChapters(pop[tonumber(os.getenv("IDX") or 1)], ch) end)')
    c = lua('#ch'); print("chapters:", c); print("desc:", (lua('ch.Description') or "")[:200].replace("\n"," / "))
    if c:
        print("  first:", lua('ch[1].Name'), lua('ch[1].Link'), " last:", lua('ch[#ch].Name'))
        L.execute('pg = {}; run(function() P:prepareChapter(ch[#ch], pg) end)')
        print("pages:", lua('#pg'), lua('pg[1] and (type(pg[1])=="table" and pg[1].Link or pg[1])'))
