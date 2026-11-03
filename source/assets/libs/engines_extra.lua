---More Otakio engines: Lua ports of the smaller keiyoushi "multisrc" themes.
---Same contract as engines.lua (one config table per site), e.g.
---
---  Engines.Keyoapp { id = "KEI_ENAGSCOMICS", name = "Ags Comics", baseUrl = "https://agrcomics.com", lang = "en" }
local U = Engines.util
local trim, pathOf, absolute, newParser, headers, addManga = U.trim, U.pathOf, U.absolute, U.newParser, U.headers, U.addManga
local co_yield = coroutine.yield
local gsub, find, match, gmatch, lower, sub = string.gsub, string.find, string.match, string.gmatch, string.lower, (string.rawsub or string.sub)
local concat = table.concat

-------------------------------------------------------------------------------
-- shared helpers
-------------------------------------------------------------------------------

---JSON null -> nil
local function nn(v)
	if v == Json.null then
		return nil
	end
	return v
end

local function enc(s)
	return Http.encode(tostring(s or ""))
end

---Mihon lists chapters newest first, Otakio stores them oldest first
local function pushReversed(dt, list, manga)
	for i = #list, 1, -1 do
		local c = list[i]
		dt[#dt + 1] = {Name = c.Name, Link = c.Link, Date = c.Date, Pages = {}, Manga = manga}
	end
end

local function setCover(p, manga, url)
	if url and url ~= "" then
		manga.NewImageLink = Http.image(url, p.Config.baseUrl .. "/")
	end
end

local function addPages(dt, list, referer)
	for _, src in ipairs(list) do
		if type(src) == "string" and src ~= "" then
			dt[#dt + 1] = Http.image(trim(gsub(src, "\\/", "/")), referer)
		end
	end
end

local function attrImg(el)
	if not el then
		return nil
	end
	for _, a in ipairs({"data-src", "data-lazy-src", "data-original", "src"}) do
		local v = el:attr(a)
		if v ~= "" and not find(v, "^data:") then
			return el:attr("abs:" .. a)
		end
	end
end

local function textOf(root, css)
	local el = root and root:selectFirst(css)
	if el then
		local t = trim(el:text())
		if t ~= "" then
			return t
		end
	end
end

---Find the first table inside a decoded JSON value accepted by `pred`
local function deepFind(value, pred, depth)
	depth = depth or 0
	if type(value) ~= "table" or depth > 40 then
		return nil
	end
	if pred(value) then
		return value
	end
	for _, v in pairs(value) do
		local r = deepFind(v, pred, depth + 1)
		if r then
			return r
		end
	end
end

---Next.js data: __NEXT_DATA__ (pages router) or the RSC "flight" stream (app router, `rsc: 1` header).
---`hint` (a plain substring such as '"chapters"') skips decoding flight lines that can't match:
---a flight response has hundreds of lines and decoding all of them takes seconds on the Vita.
function Engines.extractNextJs(body, pred, hint)
	body = body or ""
	local nextData = match(body, '<script id="__NEXT_DATA__"[^>]*>(.-)</script>')
	if nextData then
		return deepFind(Json.decode(nextData, 2000), pred)
	end
	local n = 0
	for line in string.gmatch(body, "[^\n]+") do
		if not hint or find(line, hint, 1, true) then
			local payload = match(line, "^%w+:(.*)$")
			local first = payload and sub(payload, 1, 1)
			if first == "{" or first == "[" then
				local found = deepFind(Json.decode(payload, 2000), pred)
				if found then
					return found
				end
			end
		end
		n = n + 1
		if n % 25 == 0 then
			co_yield(false)
		end
	end
end

local function getJson(url, h)
	local data = Http.getJson(url, h)
	return type(data) == "table" and data or {}
end

-------------------------------------------------------------------------------
-- MangaCatalog — single-series fan sites (one "source" lists a handful of series)
-------------------------------------------------------------------------------

function Engines.MangaCatalog(cfg)
	cfg.engine = "mangacatalog"
	local p = newParser(cfg, {})
	local series = cfg.sourceList or {{cfg.name, cfg.baseUrl}}
	local function list(dt, query)
		query = lower(query or "")
		for _, s in ipairs(series) do
			if query == "" or find(lower(s[1]), query, 1, true) then
				addManga(dt, p, s[1], s[2])
			end
		end
		dt.NoPages = true
	end
	function p:getPopularManga(page, dt)
		list(dt)
	end
	p.getLatestManga = p.getPopularManga
	function p:searchManga(query, page, dt)
		list(dt, Engines.decodeSearch(query))
	end
	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		-- two layouts in the wild: the theme's Tailwind one and an older Bootstrap one (chapter table)
		local info = trim(doc:select("div.bg-bg-secondary > div.px-6 > div.flex-col"):text())
		if info == "" then
			info = trim(doc:select("div.card-body > p"):text())
		end
		dt.Description = match(info, "Description%s*(.+)$") or info
		local cover = doc:selectFirst("div.flex > img, .card-img-right")
		setCover(self, manga, cover and cover:attr("abs:src"))
		local out = {}
		for _, el in ipairs(doc:select(cfg.chapterListSelector or "div.w-full > div.bg-bg-secondary > div.grid")) do
			local a = el:selectFirst(".col-span-4 > a")
			if a and a:attr("href") ~= "" then
				local extra = textOf(el, ".text-xs:not(a)")
				out[#out + 1] = {Name = trim(a:text()) .. (extra and (" - " .. extra) or ""), Link = pathOf(a:attr("abs:href"))}
			end
		end
		if #out == 0 then
			for _, el in ipairs(doc:select("tbody > tr")) do
				local a = el:selectFirst("a.btn-primary, a[href]")
				if a and a:attr("href") ~= "" then
					out[#out + 1] = {Name = textOf(el, "td:first-child") or trim(a:text()), Link = pathOf(a:attr("abs:href")), Date = textOf(el, "td:nth-child(2)")}
				end
			end
		end
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc = Http.getDocument(url, headers(self))
		local imgs = doc:select(cfg.pageSelector or "img[data-src]")
		if imgs:size() == 0 then
			imgs = doc:select("div.pages img.pages__img, img.pages__img, .js-pages-container img")
		end
		for _, img in ipairs(imgs) do
			local src = attrImg(img)
			if src then
				dt[#dt + 1] = Http.image(src, url)
			end
		end
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- YiiManga / YiiMadara — "MangaNato-like" Yii framework sites
-------------------------------------------------------------------------------

local function yiiList(p, url, dt, itemCss, linkCss, imgCss, nextCss)
	local doc = Http.getDocument(url, headers(p))
	local count = 0
	for _, el in ipairs(doc:select(itemCss)) do
		local a = el:selectFirst(linkCss)
		if a and addManga(dt, p, a:text(), a:attr("abs:href"), attrImg(el:selectFirst(imgCss))) then
			count = count + 1
		end
	end
	dt.NoPages = count == 0 or doc:selectFirst(nextCss) == nil
end

local function yiiDetails(p, manga, doc)
	local info = {}
	for _, h in ipairs(doc:select(".main-info-list li > h5, .post-content_item .summary-heading > h5, .info-item > span.sh, .post-content_item > b, .minfo")) do
		local label = lower(gsub(trim(h:ownText() ~= "" and h:ownText() or h:text()), "[:%-%s]+$", ""))
		local box = h:parentElement()
		local value = box and trim(box:select("> .summary-content, > i, > a, > span:not(.sh), > p"):text()) or ""
		if value == "" and box then
			value = trim(gsub(box:text(), "^%s*" .. gsub(h:text(), "%p", "%%%0"), ""))
		end
		if value ~= "" and value ~= "Updating" then
			if find(label, "^author") or find(label, "^autor") then
				info.Author = value
			elseif find(label, "^artist") then
				info.Artist = value
			elseif find(label, "^status") or find(label, "^estado") then
				info.Status = value
			elseif find(label, "^genre") or find(label, "^género") then
				info.Genres = {value}
			end
		end
	end
	local desc = doc:selectFirst(".short-desc-content, .dsct, .description-summary, .ss-manga, .post-content_item .entry-content")
	return Engines.buildInfo(info, desc and desc:text() or "")
end

function Engines.YiiManga(cfg)
	cfg.engine = "yiimanga"
	local p = newParser(cfg, {searchParam = "s"})
	local function listUrl(path, page)
		return cfg.baseUrl .. (path and ("/" .. path) or "") .. "/page/" .. page .. "/"
	end
	local ITEMS, LINK, IMG, NEXT = ".latest-list .latest-item, .list .list-item", ".latest-right a:has(h3), .latest-right a:has(h4), .item-title a", ".latest-left img, .item-img img", "#pagination li.next a"
	function p:getLatestManga(page, dt)
		yiiList(self, listUrl(nil, page), dt, ITEMS, LINK, IMG, NEXT)
	end
	function p:getPopularManga(page, dt)
		if cfg.popularPath then
			yiiList(self, listUrl(cfg.popularPath, page) .. "?order=views", dt, ITEMS, LINK, IMG, NEXT)
		else
			self:getLatestManga(page, dt)
		end
	end
	function p:searchManga(query, page, dt)
		local url = cfg.baseUrl .. "/search/?" .. Http.form({{cfg.searchParam, Engines.decodeSearch(query)}, {"page", tostring(page)}})
		yiiList(self, url, dt, ITEMS, LINK, IMG, NEXT)
	end
	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		dt.Description = yiiDetails(self, manga, doc)
		setCover(self, manga, attrImg(doc:selectFirst("img.img-cover, .summary_image img, .manga-detail .poster img")))
		local out = {}
		for _, el in ipairs(doc:select("ul.chapter-list li, ul.row-content-chapter li, .list-items li.item")) do
			local a = el:selectFirst("a[href]")
			if a then
				local name = textOf(el, ".chapter-name, .item a > span:first-child") or trim(a:text())
				out[#out + 1] = {Name = name, Link = pathOf(a:attr("abs:href")), Date = textOf(el, ".ct-update, .chapter-time, .item a > span:nth-child(2)")}
			end
		end
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc = Http.getDocument(url, headers(self))
		for _, img in ipairs(doc:select(".reading-content img, .read-content img")) do
			local src = attrImg(img)
			if src then
				dt[#dt + 1] = Http.image(src, url)
			end
		end
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

function Engines.YiiMadara(cfg)
	cfg.engine = "yiimadara"
	local p = newParser(cfg, {directoryPath = "manga", searchParam = "q"})
	local function listUrl(path, page)
		return cfg.baseUrl .. "/" .. path .. (cfg.pageSegment and "/page" or "") .. "/" .. page .. (cfg.trailingSlash and "/" or "")
	end
	local ITEMS, LINK, IMG, NEXT = "div.page-item, div.page-item-detail, div.home-item, div.manga-item", "h3 a", "img", "#blog-pager li.next a"
	function p:getPopularManga(page, dt)
		yiiList(self, listUrl(cfg.directoryPath, page) .. "?orderby=trending", dt, ITEMS, LINK, IMG, NEXT)
	end
	function p:getLatestManga(page, dt)
		yiiList(self, listUrl(cfg.directoryPath, page), dt, ITEMS, LINK, IMG, NEXT)
	end
	function p:searchManga(query, page, dt)
		local q = gsub(Engines.decodeSearch(query), "'", "’")
		local url = cfg.baseUrl .. "/search" .. (cfg.trailingSlash and "/" or "") .. "?" .. Http.form({{cfg.searchParam, q}, {"page", tostring(page)}})
		yiiList(self, url, dt, ITEMS, LINK, IMG, NEXT)
	end
	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		dt.Description = yiiDetails(self, manga, doc)
		setCover(self, manga, attrImg(doc:selectFirst(".summary_image img")))
		local out = {}
		for _, el in ipairs(doc:select("ul.row-content-chapter li")) do
			local a = el:selectFirst("a")
			if a then
				out[#out + 1] = {Name = trim(a:text()), Link = pathOf(a:attr("abs:href")), Date = textOf(el, ".chapter-time")}
			end
		end
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc = Http.getDocument(url, headers(self))
		for _, img in ipairs(doc:select(".read-content img")) do
			local src = attrImg(img)
			if src then
				dt[#dt + 1] = Http.image(src, url)
			end
		end
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- ZeistManga — Blogger based sites, listings come from the Blogger JSON feed
-------------------------------------------------------------------------------

local ZEIST_PAGE = 20

local function zeistText(v)
	return type(v) == "table" and v["$t"] or nil
end

local function zeistLink(entry)
	for _, l in ipairs(entry.link or {}) do
		if l.rel == "alternate" then
			return l.href
		end
	end
end

local function zeistHasCategory(entry, term)
	for _, c in ipairs(entry.category or {}) do
		if c.term == term then
			return true
		end
	end
	return false
end

local function zeistThumb(entry)
	local t = entry["media$thumbnail"]
	if t and t.url then
		return (gsub(gsub(t.url, "/s%d+[^/]*%-c/", "/w600/"), "=s%d+[^=]*%-c$", "=w600"))
	end
	local content = zeistText(entry.content)
	return content and match(content, '<img[^>]-src="([^"]+)"')
end

function Engines.ZeistManga(cfg)
	cfg.engine = "zeistmanga"
	local p = newParser(cfg, {mangaCategory = "Series", chapterCategory = "Chapter"})
	local EXCLUDED = {Anime = true, Novel = true, Novela = true}
	local function feedUrl(...)
		local labels = {}
		for i, label in ipairs({...}) do
			labels[i] = enc(label)
		end
		return cfg.baseUrl .. "/feeds/posts/default/-/" .. concat(labels, "/") .. "?alt=json"
	end
	local function listFeed(url, page, dt)
		local start = ZEIST_PAGE * (page - 1) + 1
		local data = getJson(url .. "&max-results=" .. (ZEIST_PAGE + 1) .. "&start-index=" .. start, headers(p))
		local entries = data.feed and data.feed.entry or {}
		local count = 0
		for _, e in ipairs(entries) do
			if count < ZEIST_PAGE and zeistHasCategory(e, cfg.mangaCategory) then
				local skip = false
				for _, c in ipairs(e.category or {}) do
					skip = skip or EXCLUDED[c.term] == true
				end
				if not skip and addManga(dt, p, zeistText(e.title) or "", zeistLink(e), zeistThumb(e)) then
					count = count + 1
				end
			end
		end
		dt.NoPages = #entries <= ZEIST_PAGE
	end
	function p:getLatestManga(page, dt)
		listFeed(feedUrl(cfg.mangaCategory) .. "&orderby=published", page, dt)
	end
	function p:getPopularManga(page, dt)
		if page == 1 and cfg.supportsLatest ~= false then
			local doc = Http.getDocument(cfg.baseUrl, headers(self))
			for _, el in ipairs(doc:select(cfg.popularMangaSelector or "div.PopularPosts div.grid > figure")) do
				local a = el:selectFirst(cfg.popularMangaSelectorUrl or "figcaption > a")
				if a then
					addManga(dt, self, a:text(), a:attr("abs:href"), attrImg(el:selectFirst("img")))
				end
			end
			if #dt > 0 then
				dt.NoPages = true
				return
			end
		end
		self:getLatestManga(page, dt)
	end
	function p:searchManga(query, page, dt)
		local q = "label:" .. cfg.mangaCategory .. " " .. Engines.decodeSearch(query)
		listFeed(feedUrl(cfg.mangaCategory) .. "&q=" .. enc(q), page, dt)
	end
	local function chapterFeed(doc, title)
		local script = doc:selectFirst("#clwd > script")
		local label = script and match(script:data(), "clwd%.run%([\"'](.-)[\"']%)")
		if label then
			return feedUrl(cfg.chapterCategory, label)
		end
		local old = doc:selectFirst("#myUL > script")
		local src = old and match(old:attr("src"), "([^']+)%?")
		if src then
			return absolute(cfg.baseUrl, pathOf(src)) .. "?alt=json"
		end
		local latest = doc:selectFirst("#latest > script")
		label = latest and match(latest:data(), "label%s*=%s*'([^']+)'")
		if label then
			return feedUrl(label)
		end
		return feedUrl(cfg.chapterCategory, title)
	end
	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		local box = doc:selectFirst(cfg.mangaDetailsSelector or ".grid.gtc-235fr, .main-content") or doc
		dt.Description = Engines.buildInfo({
			Author = textOf(box, cfg.mangaDetailsSelectorAuthor or "span#author"),
			Artist = textOf(box, cfg.mangaDetailsSelectorArtist or "span#artist"),
			Status = textOf(box, cfg.mangaDetailsSelectorStatus or "span[data-status]"),
			Genres = box:select(cfg.mangaDetailsSelectorGenres or "div.mt-15 > a[rel=tag]"):eachText()
		}, textOf(box, cfg.mangaDetailsSelectorDescription or "#synopsis, .synopsis") or "")
		setCover(self, manga, attrImg(box:selectFirst("img")))
		local url = chapterFeed(doc, manga.Name)
		local out, start = {}, 1
		repeat
			local data = getJson(url .. "&max-results=150&start-index=" .. start, headers(self))
			local entries = data.feed and data.feed.entry or {}
			for _, e in ipairs(entries) do
				if zeistHasCategory(e, cfg.chapterCategory) then
					local link = zeistLink(e)
					if link then
						out[#out + 1] = {Name = zeistText(e.title) or "", Link = pathOf(link), Date = sub(zeistText(e.published) or "", 1, 10)}
					end
				end
			end
			local total = data.feed and tonumber(zeistText(data.feed["openSearch$totalResults"]) or "") or 0
			start = start + #entries
		until #entries == 0 or start > total or start > 3000
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc, body = Http.getDocument(url, headers(self))
		-- some templates ship the page list as a script array: wz_pages_chapter = ["...", ...]
		local list = match(body or "", "wz_pages_chapter%s*=%s*(%b[])")
		if list then
			for src in gmatch(list, '"(https?://[^"]+)"') do
				dt[#dt + 1] = Http.image(src, url)
			end
			if #dt > 0 then
				return
			end
		end
		local imgs = doc:select((cfg.pageListSelector or "div.check-box div.separator") .. " img[src]")
		if imgs:size() == 0 then
			imgs = doc:select("#reader img[src], .post-body img[src], .entry-content img[src], article img[src]")
		end
		if imgs:size() == 0 then
			-- newer Zeist templates keep the post body as raw HTML inside a hidden textarea
			local raw = doc:selectFirst("textarea#zeist-raw-data")
			if raw then
				imgs = Html.parse(raw:data()):select("img[src]")
			end
		end
		for _, img in ipairs(imgs) do
			dt[#dt + 1] = Http.image(img:attr("abs:src"), url)
		end
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- Keyoapp — Tailwind/Laravel scanlator theme
-------------------------------------------------------------------------------

local function keyoBackground(el)
	local style = el and el:attr("style") or ""
	local url = match(style, "url%(['\"]?([^'\")]+)")
	if url then
		url = gsub(url, "[?&]w=%d+", "")
		return url .. (find(url, "?", 1, true) and "&" or "?") .. "w=480"
	end
end

function Engines.Keyoapp(cfg)
	cfg.engine = "keyoapp"
	local p = newParser(cfg, {})
	local function cards(doc, css, dt, query)
		query = query and lower(query) or nil
		for _, el in ipairs(doc:select(css)) do
			local a = el:selectFirst("a[href]")
			local title = a and a:attr("title") or ""
			if title == "" then
				title = el:attr("title")
			end
			if a and (not query or find(lower(title), query, 1, true)) then
				addManga(dt, p, title, a:attr("abs:href"), keyoBackground(el:selectFirst("*[style*=background-image]")))
			end
		end
		dt.NoPages = true
	end
	function p:getPopularManga(page, dt)
		local doc = Http.getDocument(cfg.baseUrl, headers(self))
		cards(doc, "div:contains(Popular) + div .group.overflow-hidden.grid, div:contains(Trending) + div .group.overflow-hidden.grid, div:contains(Popularie) + div .group.overflow-hidden.grid", dt)
		if #dt == 0 then
			self:getLatestManga(page, dt)
		end
	end
	function p:getLatestManga(page, dt)
		cards(Http.getDocument(cfg.baseUrl .. "/latest/", headers(self)), "div.grid > div.group", dt)
	end
	function p:searchManga(query, page, dt)
		local q = Engines.decodeSearch(query)
		cards(Http.getDocument(cfg.baseUrl .. "/series?q=" .. enc(q), headers(self)), "#searched_series_page > button", dt, q)
	end
	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		local function row(label)
			for _, d in ipairs(doc:select("div:has(span:containsOwn(" .. label .. ")) ~ div")) do
				local t = trim(d:text())
				if t ~= "" then
					return t
				end
			end
		end
		dt.Description = Engines.buildInfo({
			Author = row("Author"),
			Artist = row("Artist"),
			Status = row("Status"),
			Genres = doc:select("div:has(>h1) a[href*='genre=']"):eachText()
		}, textOf(doc, "#expand_content") or "")
		setCover(self, manga, keyoBackground(doc:selectFirst("div[class*=photoURL], div[style*=photoURL]")))
		local out = {}
		for _, el in ipairs(doc:select("#chapters > a, #chapters > div")) do
			local a = el:tagName() == "a" and el or el:selectFirst("a[href]")
			local name = textOf(el, ".text-sm")
			local paid = el:selectFirst("img[alt*=Coin]") ~= nil
			local upcoming = find(name or "", "Upcoming", 1, true) ~= nil
			if a and name and not paid and not upcoming then
				out[#out + 1] = {Name = name, Link = pathOf(a:attr("abs:href")), Date = textOf(el, ".text-xs")}
			end
		end
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc, body = Http.getDocument(url, headers(self))
		local host = match(body or "", "realUrl%s*=%s*`[^`]-//([^/`]+)")
		host = host and gsub(host, "%${[^}]*}", "")
		for _, img in ipairs(doc:select("#pages > img")) do
			local uid = img:attr("uid")
			if uid ~= "" and host then
				dt[#dt + 1] = Http.image("https://" .. host .. "/uploads/" .. uid, url)
			else
				local src = attrImg(img)
				if src then
					dt[#dt + 1] = Http.image(src, url)
				end
			end
		end
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- HeanCms — JSON API (api.<site>) used by scanlators like Omega Scans
-------------------------------------------------------------------------------

function Engines.HeanCms(cfg)
	cfg.engine = "heancms"
	local p = newParser(cfg, {mangaSubDirectory = "series", coverPath = ""})
	cfg.apiUrl = cfg.apiUrl or gsub(cfg.baseUrl, "://", "://api.", 1)
	cfg.cdnUrl = cfg.cdnUrl or cfg.apiUrl
	local function img(path)
		if not path or path == "" then
			return nil
		end
		if find(path, "^https?://") then
			return path
		end
		return cfg.cdnUrl .. "/" .. cfg.coverPath .. path
	end
	local function query(page, dt, q, orderBy, order)
		local url = cfg.apiUrl .. "/query?" .. Http.form({
			{"query_string", q or ""}, {"status", "All"}, {"order", order or "desc"}, {"orderBy", orderBy},
			{"series_type", "Comic"}, {"page", tostring(page)}, {"perPage", "12"}, {"tags_ids", "[]"}, {"adult", "true"}
		})
		local data = getJson(url, headers(p, {Accept = "application/json"}))
		for _, s in ipairs(data.data or {}) do
			addManga(dt, p, s.title or "", "/" .. cfg.mangaSubDirectory .. "/" .. tostring(s.series_slug) .. "#" .. tostring(s.id), img(nn(s.thumbnail)))
		end
		local meta = data.meta or {}
		dt.NoPages = not (meta.current_page and meta.last_page and meta.current_page < meta.last_page)
	end
	function p:getPopularManga(page, dt)
		query(page, dt, "", "total_views")
	end
	function p:getLatestManga(page, dt)
		query(page, dt, "", "latest")
	end
	function p:searchManga(q, page, dt)
		query(page, dt, Engines.decodeSearch(q), "total_views")
	end
	function p:getChapters(manga, dt)
		local slug = match(manga.Link, "/([^/#]+)#?%d*$") or ""
		local id = match(manga.Link, "#(%d+)$")
		local s = getJson(cfg.apiUrl .. "/series/" .. slug, headers(self, {Accept = "application/json"}))
		id = id or (s.id and tostring(s.id))
		local desc = nn(s.description) and Html.parse(s.description):text() or ""
		dt.Description = Engines.buildInfo({Author = nn(s.author), Artist = nn(s.studio), Status = nn(s.status)}, desc)
		setCover(self, manga, img(nn(s.thumbnail)))
		local out, page = {}, 1
		while id and page <= 40 do
			local data = getJson(cfg.apiUrl .. "/chapter/query?page=" .. page .. "&perPage=100&series_id=" .. id, headers(self, {Accept = "application/json"}))
			for _, c in ipairs(data.data or {}) do
				if (tonumber(c.price) or 0) == 0 then
					local name = trim(c.chapter_name or "")
					if nn(c.chapter_title) and trim(c.chapter_title) ~= "" then
						name = name .. " - " .. trim(c.chapter_title)
					end
					out[#out + 1] = {Name = name, Link = "/" .. cfg.mangaSubDirectory .. "/" .. slug .. "/" .. tostring(c.chapter_slug), Date = nn(c.created_at) and sub(c.created_at, 1, 10)}
				end
			end
			local meta = data.meta or {}
			if not (meta.current_page and meta.last_page and meta.current_page < meta.last_page) then
				break
			end
			page = page + 1
		end
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = cfg.apiUrl .. gsub(chapter.Link, "^/" .. cfg.mangaSubDirectory .. "/", "/chapter/")
		local data = getJson(url, headers(self, {Accept = "application/json"}))
		local cd = data.chapter and data.chapter.chapter_data
		local list = type(cd) == "table" and cd.images or data.data or {}
		local out = {}
		for _, src in ipairs(list) do
			out[#out + 1] = img(type(src) == "table" and src.src or src)
		end
		addPages(dt, out, cfg.baseUrl .. "/")
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- Guya — Django "guya.moe"-style readers (JSON API)
-------------------------------------------------------------------------------

function Engines.Guya(cfg)
	cfg.engine = "guya"
	local p = newParser(cfg, {})
	local function cover(c)
		if not c or c == "" then
			return nil
		end
		return absolute(cfg.baseUrl, c)
	end
	local function all(dt, q)
		local data = getJson(cfg.baseUrl .. "/api/get_all_series/", headers(p))
		local titles = {}
		for title in pairs(data) do
			titles[#titles + 1] = title
		end
		table.sort(titles)
		for _, title in ipairs(titles) do
			local s = data[title]
			if type(s) == "table" and (not q or find(lower(title), lower(q), 1, true)) then
				addManga(dt, p, title, "/reader/series/" .. tostring(s.slug) .. "/", cover(nn(s.cover)))
			end
		end
		dt.NoPages = true
	end
	function p:getPopularManga(page, dt)
		all(dt)
	end
	p.getLatestManga = p.getPopularManga
	function p:searchManga(query, page, dt)
		all(dt, Engines.decodeSearch(query))
	end
	local function series(slug)
		return getJson(cfg.baseUrl .. "/api/series/" .. slug .. "/", headers(p))
	end
	local function bestGroup(groups, sort)
		for _, g in ipairs(sort or {}) do
			if groups[g] then
				return g
			end
		end
		local keys = {}
		for k in pairs(groups) do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		return keys[1]
	end
	function p:getChapters(manga, dt)
		local slug = match(manga.Link, "/series/([^/]+)") or ""
		local s = series(slug)
		dt.Description = Engines.buildInfo({Author = nn(s.author), Artist = nn(s.artist)}, nn(s.description) and Html.parse(s.description):text() or "")
		setCover(self, manga, cover(nn(s.cover)))
		local nums = {}
		for num in pairs(s.chapters or {}) do
			nums[#nums + 1] = num
		end
		table.sort(nums, function(a, b)
			return (tonumber(a) or 0) < (tonumber(b) or 0)
		end)
		for _, num in ipairs(nums) do
			local c = s.chapters[num]
			dt[#dt + 1] = {Name = num .. ((nn(c.title) and c.title ~= "") and (" - " .. c.title) or ""), Link = slug .. "/" .. num, Pages = {}, Manga = manga}
		end
	end
	function p:prepareChapter(chapter, dt)
		local slug, num = match(chapter.Link, "^([^/]+)/(.+)$")
		local s = series(slug or "")
		local c = s.chapters and s.chapters[num or ""]
		if not c then
			return
		end
		local g = bestGroup(c.groups or {}, c.preferred_sort or s.preferred_sort)
		local out = {}
		for _, file in ipairs(g and c.groups[g] or {}) do
			out[#out + 1] = cfg.baseUrl .. "/media/manga/" .. s.slug .. "/chapters/" .. c.folder .. "/" .. g .. "/" .. file
		end
		addPages(dt, out, cfg.baseUrl .. "/")
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- PizzaReader — JSON API reader used by Italian/French scanlation teams
-------------------------------------------------------------------------------

function Engines.PizzaReader(cfg)
	cfg.engine = "pizzareader"
	local p = newParser(cfg, {})
	local function list(url, dt, sortBy)
		local comics = getJson(url, headers(p)).comics or {}
		if sortBy then
			table.sort(comics, sortBy)
		end
		for _, c in ipairs(comics) do
			if type(c) == "table" and nn(c.slug) then
				addManga(dt, p, tostring(nn(c.title) or c.slug), "/comics/" .. c.slug, nn(c.thumbnail_small) or nn(c.thumbnail))
			end
		end
		dt.NoPages = true
	end
	local function updated(c)
		local last = nn(c.last_chapter)
		return tostring(type(last) == "table" and nn(last.published_on) or nn(c.updated_at) or "")
	end
	function p:getPopularManga(page, dt)
		list(cfg.baseUrl .. "/api/comics", dt, function(a, b)
			return (tonumber(nn(a.views)) or 0) > (tonumber(nn(b.views)) or 0)
		end)
	end
	function p:getLatestManga(page, dt)
		list(cfg.baseUrl .. "/api/comics", dt, function(a, b)
			return updated(a) > updated(b)
		end)
	end
	function p:searchManga(query, page, dt)
		list(cfg.baseUrl .. "/api/search/" .. enc(Engines.decodeSearch(query)), dt)
	end
	function p:getChapters(manga, dt)
		local slug = match(manga.Link, "/comics/([^/?#]+)") or ""
		local c = getJson(cfg.baseUrl .. "/api/comics/" .. slug, headers(p)).comic or {}
		local genres = {}
		for _, g in ipairs(nn(c.genres) or {}) do
			genres[#genres + 1] = nn(g.name)
		end
		dt.Description = Engines.buildInfo({Author = nn(c.author), Artist = nn(c.artist), Genres = genres}, nn(c.description) or "")
		setCover(self, manga, nn(c.thumbnail))
		local chapters = {}
		for _, ch in ipairs(nn(c.chapters) or {}) do
			if type(ch) == "table" and nn(ch.url) then
				chapters[#chapters + 1] = ch
			end
		end
		local function key(ch)
			return (tonumber(nn(ch.volume)) or 0) * 1e6 + (tonumber(nn(ch.chapter)) or 0) * 100 + (tonumber(nn(ch.subchapter)) or 0)
		end
		table.sort(chapters, function(a, b)
			return key(a) < key(b)
		end)
		for _, ch in ipairs(chapters) do
			dt[#dt + 1] = {Name = tostring(nn(ch.full_title) or nn(ch.title) or ch.url), Link = ch.url, Pages = {}, Manga = manga}
		end
	end
	function p:prepareChapter(chapter, dt)
		local data = getJson(cfg.baseUrl .. "/api" .. chapter.Link, headers(p))
		addPages(dt, (data.chapter or {}).pages or {}, cfg.baseUrl .. "/")
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- FoOlSlide — classic scanlator reader
-------------------------------------------------------------------------------

function Engines.FoolSlide(cfg)
	cfg.engine = "foolslide"
	local p = newParser(cfg, {urlModifier = ""})
	local root = function()
		return cfg.baseUrl .. cfg.urlModifier
	end
	local function groups(doc, dt, nextCss)
		for _, el in ipairs(doc:select("div.group")) do
			local a = el:selectFirst("a[title]")
			local cover = el:selectFirst("img")
			if a then
				addManga(dt, p, a:text(), a:attr("abs:href"), cover and gsub(cover:attr("abs:src"), "/thumb_", "/"))
			end
		end
		dt.NoPages = doc:selectFirst(nextCss) == nil
	end
	function p:getPopularManga(page, dt)
		groups(Http.getDocument(root() .. "/directory/" .. page .. "/", headers(self)), dt, "div.next")
	end
	function p:getLatestManga(page, dt)
		groups(Http.getDocument(root() .. "/latest/" .. page .. "/", headers(self)), dt, "div.next")
	end
	function p:searchManga(query, page, dt)
		groups(Http.postDocument(root() .. "/search/", {search = Engines.decodeSearch(query)}, headers(self)), dt, "a:has(span.next)")
	end
	function p:getChapters(manga, dt)
		-- "adult=true" skips the mature content warning
		local doc = Http.postDocument(absolute(cfg.baseUrl, manga.Link), {adult = "true"}, headers(self), absolute(cfg.baseUrl, manga.Link))
		co_yield(false)
		local info = doc:selectFirst("div.info")
		dt.Description = info and trim(info:text()) or ""
		local thumb = doc:selectFirst("div.thumbnail img, table.thumb img")
		setCover(self, manga, thumb and thumb:attr("abs:src"))
		local out = {}
		for _, el in ipairs(doc:select("div.group div.element, div.list div.element")) do
			local a = el:selectFirst("a[title]")
			if a then
				out[#out + 1] = {Name = trim(a:text()), Link = pathOf(a:attr("abs:href")), Date = textOf(el, "div.meta_r")}
			end
		end
		pushReversed(dt, out, manga)
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local body = Http.post(url, {adult = "true"}, headers(self))
		local list = Json.decode(match(body, "var pages%s*=%s*(%b[])") or "[]") or {}
		local out = {}
		for _, pg in ipairs(list) do
			if type(pg) == "table" and pg.url then
				out[#out + 1] = absolute(cfg.baseUrl, pg.url)
			end
		end
		addPages(dt, out, url)
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- MangaK — Next.js sites with an api.<host> backend (MangaBuddy family)
-------------------------------------------------------------------------------

function Engines.MangaK(cfg)
	cfg.engine = "mangak"
	local p = newParser(cfg, {})
	cfg.apiUrl = cfg.apiUrl or ("https://api." .. match(cfg.baseUrl, "^%a+://([^/]+)"))
	local function search(page, dt, params)
		params[#params + 1] = {"page", tostring(page)}
		params[#params + 1] = {"limit", "24"}
		local data = getJson(cfg.apiUrl .. "/titles/search?" .. Http.form(params), headers(p))
		local d = data.data or {}
		for _, m in ipairs(d.items or {}) do
			addManga(dt, p, m.name or "", absolute(cfg.baseUrl, nn(m.url)), nn(m.cover))
		end
		dt.NoPages = not (d.pagination and d.pagination.has_next)
	end
	function p:getPopularManga(page, dt)
		search(page, dt, {{"sort", "popular"}, {"window", "week"}})
	end
	function p:getLatestManga(page, dt)
		search(page, dt, {{"sort", "latest"}})
	end
	function p:searchManga(query, page, dt)
		search(page, dt, {{"q", sub(Engines.decodeSearch(query), 1, 50)}})
	end
	local function pageProps(url)
		local body = Http.get(url, headers(p))
		co_yield(false)
		return Engines.extractNextJs(body, function(t)
			return t.pageProps ~= nil
		end) or {}
	end
	function p:getChapters(manga, dt)
		local props = pageProps(absolute(cfg.baseUrl, manga.Link)).pageProps or {}
		local m = props.initialManga or {}
		local function names(list)
			local out = {}
			for _, e in ipairs(type(list) == "table" and list or {}) do
				out[#out + 1] = e.name
			end
			return out
		end
		dt.Description = Engines.buildInfo({Author = concat(names(m.authors), ", "), Status = nn(m.status), Genres = names(m.genres)}, nn(m.summary) or "")
		setCover(self, manga, nn(m.cover))
		if not m.id then
			return
		end
		local data = getJson(cfg.apiUrl .. "/titles/" .. m.id .. "/chapters", headers(self))
		local list = (data.data or {}).chapters or {}
		table.sort(list, function(a, b)
			return (tonumber(a.chapter_number) or 0) < (tonumber(b.chapter_number) or 0)
		end)
		for _, c in ipairs(list) do
			dt[#dt + 1] = {Name = c.name or "", Link = pathOf(c.url or ""), Date = nn(c.updated_at) and sub(c.updated_at, 1, 10), Pages = {}, Manga = manga}
		end
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local props = pageProps(url).pageProps or {}
		addPages(dt, (props.initialChapter or {}).images or {}, cfg.baseUrl .. "/")
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- VineTheme — Next.js app router sites with a public /api/series endpoint
-------------------------------------------------------------------------------

function Engines.VineTheme(cfg)
	cfg.engine = "vinetheme"
	local p = newParser(cfg, {})
	local RSC = {rsc = "1"}
	local function slugOf(m)
		return (m.urlSlug and m.urlSlug ~= Json.null and m.urlSlug ~= "") and m.urlSlug or m.slug
	end
	local function api(page, dt, params)
		params[#params + 1] = {"contentMode", "comics"}
		params[#params + 1] = {"limit", "24"}
		params[#params + 1] = {"page", tostring(page)}
		local data = getJson(cfg.baseUrl .. "/api/series?" .. Http.form(params), headers(p))
		for _, m in ipairs(data.data or {}) do
			local cover = m.coverImage ~= Json.null and m.coverImage or nil
			addManga(dt, p, m.title or "", "/series/comic/" .. tostring(slugOf(m)), cover and absolute(cfg.baseUrl, cover))
		end
		dt.NoPages = not (data.meta and data.meta.hasMore == true)
	end
	function p:getPopularManga(page, dt)
		api(page, dt, {{"sort", "popular"}})
	end
	function p:getLatestManga(page, dt)
		api(page, dt, {{"sort", "updated"}})
	end
	function p:searchManga(query, page, dt)
		api(page, dt, {{"q", Engines.decodeSearch(query)}})
	end
	local function detail(url)
		local body = Http.get(url, headers(p, RSC))
		co_yield(false)
		return Engines.extractNextJs(body, function(t)
			return type(t.series) == "table" and type(t.chapters) == "table"
		end, '"chapters"')
	end
	function p:getChapters(manga, dt)
		local base = absolute(cfg.baseUrl, manga.Link) .. "?sort=desc"
		local d = detail(base)
		if not d then
			return
		end
		local s = d.series
		dt.Description = Engines.buildInfo({Status = nn(s.status), Author = nn(s.team) and nn(s.team.name)}, nn(s.description) and Html.parse(s.description):text() or "")
		if s.coverImage and s.coverImage ~= Json.null then
			setCover(self, manga, absolute(cfg.baseUrl, s.coverImage))
		end
		local list = {}
		local function add(chapters)
			for _, c in ipairs(chapters or {}) do
				if c.isLocked ~= true then
					list[#list + 1] = c
				end
			end
		end
		add(d.chapters)
		for page = 2, math.min(tonumber(d.totalPages) or 1, 30) do
			local more = detail(base .. "&page=" .. page)
			add(more and more.chapters)
		end
		table.sort(list, function(a, b)
			return (tonumber(a.number) or 0) < (tonumber(b.number) or 0)
		end)
		local seen = {}
		for _, c in ipairs(list) do
			local num = gsub(tostring(c.number), "%.0$", "")
			if not seen[num] then
				seen[num] = true
				local name = (nn(c.title) and c.title ~= "" and c.title ~= num) and c.title or ("Chapter " .. num)
				dt[#dt + 1] = {Name = name, Link = manga.Link .. "/chapter/" .. num, Date = c.publishedAt and c.publishedAt ~= Json.null and sub(c.publishedAt, 1, 10) or nil, Pages = {}, Manga = manga}
			end
		end
	end
	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local body = Http.get(url, headers(self, RSC))
		co_yield(false)
		local ch = Engines.extractNextJs(body, function(t)
			return type(t.chapter) == "table" and type(t.chapter.pages) == "table"
		end, '"pages"')
		local out = {}
		for _, pg in ipairs(ch and ch.chapter.pages or {}) do
			if pg.imageUrl and pg.imageUrl ~= Json.null then
				out[#out + 1] = absolute(cfg.baseUrl, pg.imageUrl)
			end
		end
		addPages(dt, out, cfg.baseUrl .. "/")
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end
