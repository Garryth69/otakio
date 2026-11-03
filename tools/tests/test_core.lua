local root = ...
string.rawsub = string.sub
dofile(root .. "/source/assets/libs/utils.lua") -- installs the UTF-8 string.sub override like on device
dofile(root .. "/source/assets/libs/json.lua")
dofile(root .. "/source/assets/libs/html.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end

-- JSON
local j = Json.decode([[{"a":[1,2,{"b":"x\u00e9\n"}],"n":null,"t":true,"f":-1.5e2}]])
eq(j.a[3].b, "xé\n", "json unicode"); eq(j.t, true); eq(j.f, -150); eq(j.n, nil)
eq(Json.decode(Json.encode({name = "a\"b", list = {1, 2, 3}})).name, 'a"b')

-- HTML
local html = [[
<!DOCTYPE html><html><head><title>T &amp; t</title><script>var a = "<div class='x'>";</script></head>
<body>
<div class="page-item-detail manga" data-post-id="42">
  <div class="item-thumb"><a href="/manga/one-piece/"><img data-src="https://cdn.x/1.jpg" src="data:x"></a></div>
  <div class="post-title"><h3><a href="/manga/one-piece/">One Piece</a></h3></div>
</div>
<div class="page-item-detail"><div class="post-title"><h3><a href="https://site.com/manga/naruto">Naruto &#8211; Shippuden</a></h3></div></div>
<ul class=main><li class="wp-manga-chapter"><a href="https://site.com/manga/one-piece/chapter-2/">Chapter 2</a><span class="chapter-release-date"><i>2 days ago</i></span>
<li class="wp-manga-chapter"><a href="https://site.com/manga/one-piece/chapter-1/"> Chapter 1 </a></ul>
<div class="summary-heading"><h5>Status</h5></div><div class="summary-content">OnGoing</div>
<p>para one<div>breaks p</div>
<div id="readerarea"><img src=" https://i/1.jpg "><img class="lazy" data-lazy-src="//i/2.jpg"></div>
</body></html>]]
local doc = Html.parse(html, "https://site.com/manga/")
local items = doc:select("div.page-item-detail, .manga__item")
eq(#items, 2, "items")
eq(items[1]:selectFirst(".post-title a"):text(), "One Piece")
eq(items[1]:selectFirst(".post-title a"):attr("abs:href"), "https://site.com/manga/one-piece/")
eq(items[2]:selectFirst(".post-title a"):text(), "Naruto – Shippuden")
eq(items[1]:selectFirst("img"):attr("data-src"), "https://cdn.x/1.jpg")
eq(items[1]:selectFirst("[data-post-id]") , nil, "self not descendant")
eq(doc:selectFirst("[data-post-id]"):attr("data-post-id"), "42")
local chs = doc:select("li.wp-manga-chapter")
eq(#chs, 2, "li implicit close"); eq(chs[2]:selectFirst("a"):text(), "Chapter 1")
eq(chs[1]:selectFirst("span.chapter-release-date"):text(), "2 days ago")
eq(doc:selectFirst("div.summary-heading:contains(status) + div"):text(), "OnGoing")
eq(#doc:select("ul.main > li"), 2, "child comb")
eq(#doc:select("ul > a"), 0, "child comb neg")
eq(doc:selectFirst("title"):text(), "T & t")
eq(#doc:select("div.x"), 0, "script raw")
eq(#doc:select("#readerarea img"), 2)
eq(doc:select("#readerarea img")[2]:attr("abs:data-lazy-src"), "https://i/2.jpg")
eq(doc:selectFirst("img:not(.lazy)"):attr("data-src"), "https://cdn.x/1.jpg")
eq(#doc:select("div:has(> a)"), 1, "has relative")
eq(doc:selectFirst("li:last-child a"):text(), "Chapter 1")
eq(doc:selectFirst("li:eq(0) a"):text(), "Chapter 2")
eq(Html.absUrl("https://a.com/x/y/z.html", "../b.jpg"), "https://a.com/x/b.jpg")
eq(Html.absUrl("https://a.com/x/", "?page=2"), "https://a.com/x/?page=2")
print("core tests OK")

-- table.serialize must round-trip any string (\r\n descriptions broke NOBORU caches)
local nasty = "a\r\nb\"c\\d\0e\tf\27g ção 漫画"
local t = load(("return " .. table.serialize({Description = nasty, [1] = {Name = nasty}, ["we\"ird\rkey"] = 1.5}, true)))()
eq(t.Description, nasty, "serialize value")
eq(t[1].Name, nasty, "serialize nested")
eq(t["we\"ird\rkey"], 1.5, "serialize key")
print("serialize tests OK")

-- error pages must not decode as numbers (GitHub "404: Not Found")
eq(Json.decode("404: Not Found"), nil, "json trailing garbage")
eq(Json.decode("  {\"a\":1}  ").a, 1, "json whitespace")
print("json strict tests OK")
