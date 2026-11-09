---Otakio engines for Russian, Japanese and Chinese sites: Lua ports of keiyoushi "multisrc" themes
---(keiyoushi/extensions-source, Apache-2.0). Same contract as engines.lua / engines_extra.lua:
---
---  Engines.Grouple { id = "EXAMPLE_RU", name = "Example", baseUrl = "https://example.com", lang = "ru" }
local U = Engines.util
local trim, pathOf, absolute, newParser, headers, addManga = U.trim, U.pathOf, U.absolute, U.newParser, U.headers, U.addManga
local co_yield = coroutine.yield
local gsub, find, match, gmatch, lower, sub = string.gsub, string.find, string.match, string.gmatch, string.lower, (string.rawsub or string.sub)
local concat = table.concat

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

local function textOf(root, css)
	local el = root and root:selectFirst(css)
	if el then
		local t = trim(el:text())
		if t ~= "" then
			return t
		end
	end
end

local function attrImg(el)
	if not el then
		return nil
	end
	for _, a in ipairs({"data-src", "data-lazy-src", "data-original", "data-bg", "src"}) do
		local v = el:attr(a)
		if v ~= "" and not find(v, "^data:") then
			return el:attr("abs:" .. a)
		end
	end
end

local function getJson(url, h)
	local data = Http.getJson(url, h)
	return type(data) == "table" and data or {}
end

Engines.intl = {nn = nn, enc = enc, pushReversed = pushReversed, setCover = setCover, textOf = textOf, attrImg = attrImg, getJson = getJson}

-------------------------------------------------------------------------------
-- Grouple — Russian reader platform (ru)
-- Catalog: JSON API /api/catalog/search; chapters: table on the series page; pages: rm_h.readerInit(...) script
-------------------------------------------------------------------------------

function Engines.Grouple(cfg)
	cfg.engine = "grouple"
	local p = newParser(cfg, {})
	local API_HEADERS = {Referer = cfg.baseUrl .. "/", Accept = "application/json, text/plain, */*"}

	local function search(dt, sortType, page, query)
		local url = cfg.baseUrl .. "/api/catalog/search?offset=" .. (50 * (page - 1)) .. "&sortType=" .. sortType
		if query and query ~= "" then
			url = url .. "&q=" .. enc(query)
		end
		local data = getJson(url, API_HEADERS)
		local count = 0
		for _, it in ipairs(type(data.list) == "table" and data.list or {}) do
			local link = type(it.elementId) == "table" and nn(it.elementId.linkName)
			local name = nn(it.name)
			if type(link) == "string" and type(name) == "string" then
				if addManga(dt, p, name, cfg.baseUrl .. "/" .. link, nn(it.picUrl)) then
					count = count + 1
				end
			end
		end
		local offset, limit, total = tonumber(nn(data.offset)), tonumber(nn(data.limit)), tonumber(nn(data.total))
		dt.NoPages = count == 0 or not (offset and limit and total and offset + limit < total)
	end

	function p:getPopularManga(page, dt)
		search(dt, "RATING", page)
	end
	function p:getLatestManga(page, dt)
		search(dt, "DATE_UPDATE", page)
	end
	function p:searchManga(query, page, dt)
		search(dt, "RATING", page, Engines.decodeSearch(query))
	end

	function p:getChapters(manga, dt)
		local url = absolute(cfg.baseUrl, manga.Link)
		local body = Http.get(url, headers(self)) or ""
		co_yield(false)
		local doc = Html.parse(body, url)
		co_yield(false)
		-- details
		local info = {}
		for _, el in ipairs(doc:select(".cr-info-details > *")) do
			local title = lower(textOf(el, ".cr-info-details-item__title") or "")
			local value = textOf(el, ".cr-info-details-item__status")
			if value and (find(title, "выпуск", 1, true) or find(title, "status", 1, true)) and not info.Status then
				info.Status = value
			end
		end
		local authors, artists = {}, {}
		for _, person in ipairs(doc:select(".cr-main-person-item")) do
			local role = lower(textOf(person, ".cr-main-person-item__role") or "")
			local name = textOf(person, ".cr-main-person-item__name")
			if name then
				if find(role, "автор", 1, true) or find(role, "сценар", 1, true) then
					authors[#authors + 1] = name
				elseif find(role, "худож", 1, true) or find(role, "иллюст", 1, true) then
					artists[#artists + 1] = name
				end
			end
		end
		info.Author = concat(authors, ", ")
		info.Artist = concat(artists, ", ")
		local genres = {}
		for _, g in ipairs(doc:select(".creation-element-tags .creation-element-tags__item span")) do
			local t = trim(g:text())
			if t ~= "" and not g:hasClass("text-secondary") then
				genres[#genres + 1] = t
			end
		end
		info.Genres = genres
		dt.Description = Engines.buildInfo(info, textOf(doc, ".cr-description__content") or "")
		setCover(self, manga, attrImg(doc:selectFirst(".cr-hero-poster__img") or doc:selectFirst(".cr-hero-overlay__bg")))
		-- chapter links carry the user hash when the site shows one (needed by chapters that require it)
		local hash = match(body, "user_hash[^']+'([^']+)'")
		local suffix = hash and ("?d=" .. hash .. "&mtr=true") or "?mtr=true"
		local out = {}
		for _, row in ipairs(doc:select("tr.item-row")) do
			local a = row:selectFirst("a.chapter-link")
			local dateEl = row:selectFirst("td.date")
			-- rows with a "text-info" date are announcements of chapters that aren't out yet
			if a and a:attr("href") ~= "" and not (dateEl and dateEl:hasClass("text-info")) then
				local name = trim(a:ownText())
				if name == "" then
					name = trim(a:text())
				end
				out[#out + 1] = {Name = name, Link = pathOf(a:attr("abs:href")) .. suffix, Date = dateEl and (nn(dateEl:attr("data-date")) or trim(dateEl:text()))}
			end
		end
		pushReversed(dt, out, manga)
	end

	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local body = Http.get(url, headers(self)) or ""
		local start = find(body, "rm_h.readerInit(", 1, true) or find(body, "rm_h.readerDoInit(", 1, true)
		if not start then
			return -- paid / premium / licensed chapter: the reader reports "no pages"
		end
		local stop = find(body, ");", start, true) or #body
		local args = sub(body, start, stop)
		for host, middle, path in gmatch(args, "%[%s*['\"]([^'\"]*)['\"]%s*,%s*['\"]([^'\"]*)['\"]%s*,%s*['\"]([^'\"]*)['\"]") do
			local img
			if middle == "" and find(path, "^/static/") then
				img = cfg.baseUrl .. path
			elseif find(middle, "/manga/$") then
				img = host .. path
			else
				img = middle .. host .. path
			end
			if not find(img, "://", 1, true) then
				img = "https:" .. img
			end
			if find(img, "one-way.work", 1, true) then
				img = match(img, "^([^?]+)") -- this image host needs no token
			end
			img = gsub(img, "//resh", "//h")
			-- "/static/deleted1.png": the page was taken down (licensed title) or needs a logged-in account
			if not find(img, "/static/deleted", 1, true) then
				dt[#dt + 1] = Http.image(img, cfg.baseUrl .. "/")
			end
		end
	end

	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- LibGroup — "Lib" family sites (ru). Public JSON API (api.cdnlibs.org) keyed by a Site-Id header
-------------------------------------------------------------------------------

---ProseMirror-like summary ({type="doc", content={...}}) or plain string -> text
local function flattenDoc(v, out)
	out = out or {}
	v = nn(v)
	if type(v) == "string" then
		out[#out + 1] = v
	elseif type(v) == "table" then
		if type(v.text) == "string" then
			out[#out + 1] = v.text
		end
		for _, c in ipairs(type(v.content) == "table" and v.content or {}) do
			flattenDoc(c, out)
		end
		if v.type == "paragraph" then
			out[#out + 1] = "\n"
		end
	end
	return out
end

function Engines.LibGroup(cfg)
	cfg.engine = "libgroup"
	local p = newParser(cfg, {apiUrl = "https://api.cdnlibs.org", siteId = 1})
	local API = gsub(cfg.apiUrl, "/+$", "")
	local H = {Referer = cfg.baseUrl .. "/", Accept = "application/json", ["Site-Id"] = tostring(cfg.siteId)}
	local imageServer

	local function serverUrl()
		if imageServer then
			return imageServer
		end
		local data = getJson(API .. "/api/constants?fields[]=imageServers", H)
		local list = type(data.data) == "table" and data.data.imageServers or {}
		-- "compress" is keiyoushi's default; "main" answers 403 to apps
		local preferred = {cfg.imageServer or "compress", "secondary", "download", "main"}
		for _, id in ipairs(preferred) do
			for _, s in ipairs(type(list) == "table" and list or {}) do
				if s.id == id and type(s.site_ids) == "table" then
					for _, sid in ipairs(s.site_ids) do
						if tonumber(sid) == tonumber(cfg.siteId) and type(s.url) == "string" then
							imageServer = s.url
							return imageServer
						end
					end
				end
			end
		end
		return nil
	end

	local function addList(dt, data)
		local count = 0
		for _, m in ipairs(type(data.data) == "table" and data.data or {}) do
			local slug = nn(m.slug_url)
			local title = nn(m.rus_name)
			if not title or title == "" then
				title = nn(m.eng_name) or nn(m.name)
			end
			if type(slug) == "string" and type(title) == "string" and title ~= "" then
				local cover = type(m.cover) == "table" and (nn(m.cover.default) or nn(m.cover.thumbnail)) or nil
				if addManga(dt, p, title, cfg.baseUrl .. "/ru/manga/" .. slug, cover) then
					count = count + 1
				end
			end
		end
		local meta = type(data.meta) == "table" and data.meta or {}
		dt.NoPages = count == 0 or meta.has_next_page == false
	end

	function p:getPopularManga(page, dt)
		addList(dt, getJson(API .. "/api/manga?site_id[]=" .. cfg.siteId .. "&page=" .. page, H))
	end
	function p:getLatestManga(page, dt)
		addList(dt, getJson(API .. "/api/manga?site_id[]=" .. cfg.siteId .. "&sort_by=last_chapter_at&page=" .. page, H))
	end
	function p:searchManga(query, page, dt)
		addList(dt, getJson(API .. "/api/manga?site_id[]=" .. cfg.siteId .. "&q=" .. enc(Engines.decodeSearch(query)) .. "&page=" .. page, H))
	end

	local function slugOf(manga)
		return match(manga.Link or "", "/manga/([^/?#]+)") or match(manga.Link or "", "([^/?#]+)$")
	end

	function p:getChapters(manga, dt)
		local slug = slugOf(manga)
		if not slug then
			return
		end
		local details = getJson(API .. "/api/manga/" .. slug .. "?fields[]=summary&fields[]=authors&fields[]=artists&fields[]=genres&fields[]=status_id", H)
		local d = type(details.data) == "table" and details.data or {}
		local info = {Genres = {}}
		local names = {}
		for _, a in ipairs(type(d.authors) == "table" and d.authors or {}) do
			names[#names + 1] = nn(a.rus_name) or nn(a.name)
		end
		info.Author = concat(names, ", ")
		names = {}
		for _, a in ipairs(type(d.artists) == "table" and d.artists or {}) do
			names[#names + 1] = nn(a.rus_name) or nn(a.name)
		end
		info.Artist = concat(names, ", ")
		for _, g in ipairs(type(d.genres) == "table" and d.genres or {}) do
			info.Genres[#info.Genres + 1] = nn(g.name)
		end
		info.Status = type(d.status) == "table" and nn(d.status.label) or nil
		dt.Description = Engines.buildInfo(info, trim(gsub(concat(flattenDoc(d.summary)), "\n+$", "")))
		co_yield(false)
		local data = getJson(API .. "/api/manga/" .. slug .. "/chapters", H)
		-- API order is oldest first, like Otakio
		for _, c in ipairs(type(data.data) == "table" and data.data or {}) do
			local number, volume = nn(c.number), nn(c.volume)
			if number and volume then
				local branch = type(c.branches) == "table" and c.branches[1] and nn(c.branches[1].branch_id)
				local name = "Том " .. volume .. " Глава " .. number
				if type(nn(c.name)) == "string" and c.name ~= "" then
					name = name .. " - " .. c.name
				end
				local created = type(c.branches) == "table" and c.branches[1] and nn(c.branches[1].created_at)
				dt[#dt + 1] = {
					Name = name,
					Link = "/" .. slug .. "/chapter?number=" .. enc(number) .. "&volume=" .. enc(volume) .. (branch and ("&branch_id=" .. branch) or ""),
					Date = type(created) == "string" and sub(created, 1, 10) or nil,
					Pages = {},
					Manga = manga
				}
			end
		end
	end

	function p:prepareChapter(chapter, dt)
		local data = getJson(API .. "/api/manga" .. chapter.Link, H)
		local pages = type(data.data) == "table" and data.data.pages or {}
		local server = serverUrl()
		if not server or type(pages) ~= "table" then
			return
		end
		table.sort(pages, function(a, b)
			return (tonumber(a.slug) or 0) < (tonumber(b.slug) or 0)
		end)
		for _, pg in ipairs(pages) do
			local path = nn(pg.url)
			if type(path) == "string" and path ~= "" then
				dt[#dt + 1] = Http.image(server .. gsub(path, "^//", "/"), cfg.baseUrl .. "/")
			end
		end
	end

	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- MultiChan — DataLife Engine sites (ru); pages listed in a "fullimg" script array
-------------------------------------------------------------------------------

function Engines.MultiChan(cfg)
	cfg.engine = "multichan"
	local p = newParser(cfg, {})

	local function list(url, dt)
		local doc = Http.getDocument(url, headers(p))
		local count = 0
		for _, el in ipairs(doc:select("div.content_row")) do
			local a = el:selectFirst("h2 > a")
			local title = el:attr("title")
			if title == "" and a then
				title = a:text()
			end
			if a and addManga(dt, p, title, a:attr("abs:href"), attrImg(el:selectFirst("img"))) then
				count = count + 1
			end
		end
		local nextLink = false
		for _, a in ipairs(doc:select("#pagination a, .navigation a, a")) do
			local t = a:text()
			if find(t, "Вперед", 1, true) or find(t, "Далее", 1, true) then
				nextLink = true
				break
			end
		end
		dt.NoPages = count == 0 or not nextLink
	end

	function p:getPopularManga(page, dt)
		list(cfg.baseUrl .. "/mostfavorites?offset=" .. (20 * (page - 1)), dt)
	end
	function p:getLatestManga(page, dt)
		list(cfg.baseUrl .. "/manga/new?offset=" .. (20 * (page - 1)), dt)
	end
	function p:searchManga(query, page, dt)
		list(cfg.baseUrl .. "/?do=search&subaction=search&story=" .. enc(Engines.decodeSearch(query)) .. "&search_start=" .. page, dt)
	end

	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		local info = {}
		for _, row in ipairs(doc:select("#info_wrap tr, #info_wrap > div")) do
			local t = row:text()
			if find(t, "Автор", 1, true) then
				info.Author = textOf(row, ".item2")
			elseif find(t, "Загружено", 1, true) then
				info.Status = textOf(row, ".item2")
			end
		end
		local genres = {}
		for _, a in ipairs(doc:select(".sidetags ul a:last-child")) do
			genres[#genres + 1] = trim(a:text())
		end
		info.Genres = genres
		local desc = doc:selectFirst("div#description")
		dt.Description = Engines.buildInfo(info, desc and trim(desc:ownText() ~= "" and desc:ownText() or desc:text()) or "")
		local cover = doc:selectFirst("img#cover")
		setCover(self, manga, cover and cover:attr("abs:src"))
		local out = {}
		for _, row in ipairs(doc:select("table.table_cha tr")) do
			local a = row:selectFirst("a[href]")
			if a then
				out[#out + 1] = {Name = trim(a:text()), Link = pathOf(a:attr("abs:href")), Date = textOf(row, "div.date")}
			end
		end
		pushReversed(dt, out, manga)
	end

	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local body = Http.get(url, headers(self)) or ""
		local list = match(body, '"fullimg"%s*:%s*%[(.-)%]')
		if not list then
			return
		end
		for item in gmatch(list, "[^,]+") do
			local img = trim(gsub(gsub(item, '"', ""), "\\/", "/"))
			if img ~= "" then
				if find(img, "^//") then
					img = "https:" .. img
				end
				dt[#dt + 1] = Http.image(img, cfg.baseUrl .. "/")
			end
		end
	end

	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- FMReader — FMReader-based sites (ja raw)
-------------------------------------------------------------------------------

local function styleUrl(el)
	if not el then
		return nil
	end
	local bg = el:attr("data-bg")
	if bg ~= "" then
		return el:attr("abs:data-bg")
	end
	local url = match(el:attr("style"), "url%(%s*['\"]?([^'\")]+)")
	if url and not find(url, "lazy%-loading") then
		return Html.absUrl(el.baseUri or "", url) ~= "" and url or url
	end
	return attrImg(el)
end

function Engines.FMReader(cfg)
	cfg.engine = "fmreader"
	local p = newParser(cfg, {requestPath = "manga-list.html", popularSort = "sort=views"})

	local function list(url, dt)
		local doc = Http.getDocument(url, headers(p))
		local count = 0
		-- classic FMReader cards, and the newer "manga-card" layout
		for _, el in ipairs(doc:select("div.thumb-item-flow, div.media, div.manga-card")) do
			local a = el:selectFirst(".series-title a, h3 a, a.manga-title")
			local title = a and trim(a:text()) or ""
			if a and title ~= "" then
				local img = el:selectFirst(".img-in-ratio, a.manga-cover, img")
				local cover = styleUrl(img)
				if cover and find(cover, "^/") then
					cover = cfg.baseUrl .. cover
				end
				if addManga(dt, p, title, a:attr("abs:href"), cover) then
					count = count + 1
				end
			end
		end
		local nextBtn = doc:selectFirst(".pagination a[rel=next], .pagination li.next a, a.next")
		local hasNext = nextBtn ~= nil
		if not hasNext then
			for _, a in ipairs(doc:select(".pagination a")) do
				if find(a:text(), "»", 1, true) and not a:hasClass("disabled") then
					hasNext = true
					break
				end
			end
		end
		dt.NoPages = count == 0 or not hasNext
	end

	function p:getPopularManga(page, dt)
		list(cfg.baseUrl .. "/" .. cfg.requestPath .. "?listType=pagination&page=" .. page .. "&" .. cfg.popularSort .. "&sort_type=DESC", dt)
	end
	function p:getLatestManga(page, dt)
		list(cfg.baseUrl .. "/" .. cfg.requestPath .. "?listType=pagination&page=" .. page .. "&sort=last_update&sort_type=DESC", dt)
	end
	function p:searchManga(query, page, dt)
		list(cfg.baseUrl .. "/" .. cfg.requestPath .. "?name=" .. enc(Engines.decodeSearch(query)) .. "&page=" .. page, dt)
	end

	function p:getChapters(manga, dt)
		local url = absolute(cfg.baseUrl, manga.Link)
		local doc = Http.getDocument(url, headers(self))
		co_yield(false)
		local info = doc:selectFirst("div.card-body div.row, div.row") or doc
		local authors, genres = {}, {}
		for _, a in ipairs(info:select("li a.btn-info")) do
			local t = trim(a:text())
			if t ~= "" and lower(t) ~= "updating" then
				authors[#authors + 1] = t
			end
		end
		for _, a in ipairs(info:select("li a.btn-danger")) do
			genres[#genres + 1] = trim(a:text())
		end
		local desc = trim(doc:select("div.detail .content, .summary-content p, div.row ~ div.row p"):text())
		dt.Description = Engines.buildInfo({Author = concat(authors, ", "), Genres = genres, Status = textOf(info, "li a.btn-success")}, desc)
		setCover(self, manga, attrImg(info:selectFirst("img.thumbnail")))
		local rows = doc:select("div#list-chapters p, table.table tr, .list-chapters > a, ul.list-chapters li")
		if rows:size() == 0 then
			-- chapters loaded by the page script from app/manga/controllers
			local slug = match(manga.Link, "/manga%-([^/]-)%.html") or match(manga.Link, "/m/([^/?#]+)")
			if slug then
				local listUrl = cfg.baseUrl .. "/app/manga/controllers/cont.Listchapter.php?slug=" .. enc(slug)
				local body = Http.get(listUrl, headers(self))
				rows = Html.parse(body, cfg.baseUrl .. "/"):select("div#list-chapters p, table.table tr, .list-chapters > a, a[href]")
			end
		end
		local out, seen = {}, {}
		for _, row in ipairs(rows) do
			local a = row:tagName() == "a" and row or row:selectFirst("a[href]")
			if a then
				local href = a:attr("abs:href")
				if href ~= "" and not seen[href] then
					seen[href] = true
					local name = trim(a:attr("title"))
					if name == "" then
						name = trim(a:text())
					end
					out[#out + 1] = {Name = name, Link = pathOf(href), Date = textOf(row, "time, .chapter-time, .publishedDate")}
				end
			end
		end
		pushReversed(dt, out, manga)
	end

	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc = Http.getDocument(url, headers(self))
		local imgs = doc:select("img.chapter-img")
		if imgs:size() == 0 then
			local id = doc:selectFirst("input[name=chapter]#chapter")
			if id and id:attr("value") ~= "" then
				local body = Http.get(cfg.baseUrl .. "/app/manga/controllers/cont.imagesChap.php?cid=" .. enc(id:attr("value")), headers(self))
				imgs = Html.parse(body, url):select("img.chapter-img, img")
			end
		end
		for _, img in ipairs(imgs) do
			local src
			local encoded = img:attr("data-img")
			if encoded ~= "" and not find(encoded, ".", 1, true) then
				-- FMReader "base64 page list": data-img holds the image URL in base64
				src = Http.base64decode(encoded)
			else
				src = attrImg(img)
			end
			if src and src ~= "" and not find(src, "lazy%-loading") and not find(src, "^data:") then
				dt[#dt + 1] = Http.image(trim(src), url)
			end
		end
	end

	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- NatsuId — (ja) WordPress theme: listings/details from the public wp-json REST API,
-- chapters from admin-ajax "chapter_list", pages from section[data-image-data]
-------------------------------------------------------------------------------

local function wpTerms(embedded, taxonomy)
	local out = {}
	for _, group in ipairs(type(embedded) == "table" and type(embedded["wp:term"]) == "table" and embedded["wp:term"] or {}) do
		if type(group) == "table" and type(group[1]) == "table" and group[1].taxonomy == taxonomy then
			for _, t in ipairs(group) do
				out[#out + 1] = Html.unescape(tostring(t.name or ""))
			end
		end
	end
	return out
end

local function wpCover(m)
	local media = type(m._embedded) == "table" and m._embedded["wp:featuredmedia"]
	local first = type(media) == "table" and media[1]
	return type(first) == "table" and nn(first.source_url) or nil
end

function Engines.NatsuId(cfg)
	cfg.engine = "natsuid"
	local p = newParser(cfg, {})
	local FIELDS = "&_fields=id,slug,title,_links,_embedded&_embed=wp:featuredmedia"

	local function list(dt, page, extra)
		local data = Http.getJson(cfg.baseUrl .. "/wp-json/wp/v2/manga?per_page=20&page=" .. page .. extra .. FIELDS, headers(p))
		local count = 0
		for _, m in ipairs(type(data) == "table" and data or {}) do
			local title = type(m.title) == "table" and nn(m.title.rendered)
			if m.slug and title then
				if addManga(dt, p, Html.unescape(title), cfg.baseUrl .. "/manga/" .. m.slug .. "/", wpCover(m)) then
					count = count + 1
				end
			end
		end
		dt.NoPages = count < 20
	end

	function p:getPopularManga(page, dt)
		list(dt, page, "&orderby=date")
	end
	function p:getLatestManga(page, dt)
		list(dt, page, "&orderby=modified")
	end
	function p:searchManga(query, page, dt)
		list(dt, page, "&search=" .. enc(Engines.decodeSearch(query)))
	end

	function p:getChapters(manga, dt)
		local slug = match(manga.Link or "", "/manga/([^/]+)")
		if not slug then
			return
		end
		local data = Http.getJson(cfg.baseUrl .. "/wp-json/wp/v2/manga?slug[]=" .. enc(slug) .. "&_fields=id,content,_links,_embedded&_embed=wp:term,wp:featuredmedia", headers(self))
		local m = type(data) == "table" and data[1]
		if type(m) ~= "table" or not m.id then
			return
		end
		local content = type(m.content) == "table" and nn(m.content.rendered) or ""
		local desc = trim(Html.parse("<div>" .. content .. "</div>"):text())
		local genres = wpTerms(m._embedded, "genre")
		dt.Description = Engines.buildInfo({
			Author = concat(wpTerms(m._embedded, "series-author"), ", "),
			Artist = concat(wpTerms(m._embedded, "artist"), ", "),
			Status = wpTerms(m._embedded, "status")[1],
			Genres = genres
		}, desc)
		setCover(self, manga, wpCover(m))
		co_yield(false)
		-- a high page number makes the theme return the whole list (hidden chapters included)
		local body = Http.get(cfg.baseUrl .. "/wp-admin/admin-ajax.php?manga_id=" .. m.id .. "&page=9999&action=chapter_list", headers(self))
		local doc = Html.parse(body, cfg.baseUrl .. "/")
		local out = {}
		for _, a in ipairs(doc:select("a[href]")) do
			local time = a:selectFirst("time")
			if time then
				local span = a:selectFirst("span")
				local name = span and trim(span:ownText()) or ""
				if name == "" then
					name = trim(a:text())
				end
				local date = time:attr("datetime")
				out[#out + 1] = {Name = name, Link = pathOf(a:attr("abs:href")), Date = date ~= "" and sub(date, 1, 10) or nil}
			end
		end
		pushReversed(dt, out, manga)
	end

	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local doc = Http.getDocument(url, headers(self))
		for _, img in ipairs(doc:select("section[data-image-data] img")) do
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
-- MangaReader — "mangareader.to"-style sites (ja); pages come from an ajax JSON {html = "..."}
-------------------------------------------------------------------------------

---Percent-encodes raw UTF-8 bytes (headers such as Referer can't carry Japanese/Chinese text)
local function asciiUrl(url)
	return (gsub(url or "", "[\128-\255]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end
Engines.intl.asciiUrl = asciiUrl

local function imgAttrMR(el)
	if not el then
		return nil
	end
	for _, a in ipairs({"data-lazy-src", "data-src", "data-url", "src"}) do
		local v = el:attr(a)
		if v ~= "" and not find(v, "^data:") then
			return trim(el:attr("abs:" .. a))
		end
	end
end

function Engines.MangaReader(cfg)
	cfg.engine = "mangareader"
	local p = newParser(cfg, {
		pageParam = "page", searchPathSegment = "search", searchKeyword = "keyword", chapterIdSelect = "en-chapters",
		ajaxPath = "/ajax/image/list/%s?mode=vertical", sortPopular = "most-viewed", sortLatest = "latest-updated"
	})

	local function list(url, dt)
		local doc = Http.getDocument(url, headers(p))
		local count = 0
		for _, a in ipairs(doc:select(".manga_list-sbs .manga-poster, .manga-poster")) do
			local img = a:selectFirst("img")
			local title = img and trim(img:attr("alt")) or ""
			if a:attr("href") ~= "" and title ~= "" and addManga(dt, p, title, a:attr("abs:href"), imgAttrMR(img)) then
				count = count + 1
			end
		end
		dt.NoPages = count == 0 or doc:selectFirst("ul.pagination > li.active + li") == nil
	end

	local function filterUrl(sort, page)
		return cfg.baseUrl .. "/filter/?sort=" .. sort .. "&" .. cfg.pageParam .. "=" .. page
	end

	function p:getPopularManga(page, dt)
		list(filterUrl(cfg.sortPopular, page), dt)
	end
	function p:getLatestManga(page, dt)
		list(filterUrl(cfg.sortLatest, page), dt)
	end
	function p:searchManga(query, page, dt)
		local path = cfg.searchPathSegment ~= "" and ("/" .. cfg.searchPathSegment) or ""
		list(cfg.baseUrl .. path .. "/?" .. cfg.searchKeyword .. "=" .. enc(Engines.decodeSearch(query)) .. "&" .. cfg.pageParam .. "=" .. page, dt)
	end

	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		local box = doc:selectFirst("#ani_detail") or doc
		local genres, authors = {}, {}
		for _, a in ipairs(box:select(".genres > a")) do
			genres[#genres + 1] = trim(a:ownText())
		end
		local status
		for _, item in ipairs(box:select(".anisc-info > .item")) do
			local head = lower(textOf(item, ".item-head") or "")
			if find(head, "author", 1, true) or find(head, "著者", 1, true) or find(head, "作者", 1, true) then
				for _, a in ipairs(item:select("a")) do
					authors[#authors + 1] = trim(gsub(a:ownText(), ",", ""))
				end
			elseif find(head, "status", 1, true) or find(head, "状態", 1, true) or find(head, "ステータス", 1, true) then
				status = textOf(item, ".name")
			end
		end
		local desc = box:selectFirst(".description")
		dt.Description = Engines.buildInfo({Genres = genres, Author = concat(authors, ", "), Status = status}, desc and trim(desc:ownText() ~= "" and desc:ownText() or desc:text()) or "")
		setCover(self, manga, imgAttrMR(box:selectFirst("img")))
		local out = {}
		for _, li in ipairs(doc:select("#" .. cfg.chapterIdSelect .. " > li.chapter-item")) do
			local a = li:selectFirst("a")
			if a and a:attr("href") ~= "" then
				local id = li:attr("data-id")
				out[#out + 1] = {Name = textOf(a, ".name") or trim(a:text()), Link = pathOf(a:attr("abs:href")) .. (id ~= "" and ("#" .. id) or "")}
			end
		end
		pushReversed(dt, out, manga)
	end

	function p:prepareChapter(chapter, dt)
		local path, id = match(chapter.Link, "^([^#]*)#?(.*)$")
		local url = absolute(cfg.baseUrl, path)
		if id == "" then
			local doc = Http.getDocument(url, headers(self))
			local el = doc:selectFirst("div[data-reading-id]")
			id = el and el:attr("data-reading-id") or ""
			if id == "" then
				return
			end
		end
		local data = Http.getJson(cfg.baseUrl .. string.format(cfg.ajaxPath, enc(id)), {Referer = asciiUrl(url), Accept = "application/json, text/javascript, */*; q=0.01", ["X-Requested-With"] = "XMLHttpRequest"})
		local html = type(data) == "table" and nn(data.html)
		if type(html) ~= "string" then
			return
		end
		for _, el in ipairs(Html.parse(html, url):select(".container-reader-chapter > div > img, .container-reader-chapter img, img")) do
			local src = imgAttrMR(el)
			if src and src ~= "" then
				dt[#dt + 1] = Http.image(src, src)
			end
		end
	end

	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- Liliana — (ja) Pages from /ajax/image/list/chap/<CHAPTER_ID> ({status, html})
-------------------------------------------------------------------------------

function Engines.Liliana(cfg)
	cfg.engine = "liliana"
	local p = newParser(cfg, {})

	local function list(url, dt)
		local doc = Http.getDocument(url, headers(p))
		local count = 0
		for _, el in ipairs(doc:select("div#main div.grid > div")) do
			local a = el:selectFirst(".text-center a")
			if a and addManga(dt, p, a:text(), a:attr("abs:href"), attrImg(el:selectFirst("img"))) then
				count = count + 1
			end
		end
		dt.NoPages = count == 0 or doc:selectFirst(".blog-pager > span.pagecurrent + span") == nil
	end

	function p:getPopularManga(page, dt)
		list(cfg.baseUrl .. "/ranking/week/" .. page, dt)
	end
	function p:getLatestManga(page, dt)
		list(cfg.baseUrl .. "/all-manga/" .. page .. "/?sort=last_update&status=0", dt)
	end
	function p:searchManga(query, page, dt)
		list(cfg.baseUrl .. "/search/" .. page .. "/?keyword=" .. enc(Engines.decodeSearch(query)), dt)
	end

	function p:getChapters(manga, dt)
		local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(self))
		co_yield(false)
		local genres = {}
		for _, a in ipairs(doc:select(".a2 div > a[rel=tag].label")) do
			genres[#genres + 1] = trim(a:text())
		end
		local author = textOf(doc, "div.y6x11p i.fa-user + span.dt")
		if author and lower(author) == "updating" then
			author = nil
		end
		dt.Description = Engines.buildInfo({Genres = genres, Author = author, Status = textOf(doc, "div.y6x11p i.fa-rss + span.dt")}, textOf(doc, "div#syn-target") or "")
		setCover(self, manga, attrImg(doc:selectFirst(".a1 > figure img")))
		local out = {}
		for _, li in ipairs(doc:select("ul > li.chapter")) do
			local a = li:selectFirst("a")
			if a and a:attr("href") ~= "" then
				local t = li:selectFirst("time[datetime]")
				local ts = t and tonumber(t:attr("datetime"))
				out[#out + 1] = {Name = trim(a:text()), Link = pathOf(a:attr("abs:href")), Date = ts and Clock and Clock.date and Clock.date("%Y-%m-%d", ts) or nil}
			end
		end
		pushReversed(dt, out, manga)
	end

	function p:prepareChapter(chapter, dt)
		local url = absolute(cfg.baseUrl, chapter.Link)
		local body = Http.get(url, headers(self))
		local id = match(body or "", "const%s+CHAPTER_ID%s*=%s*['\"]?([%w_-]+)")
		if not id then
			return
		end
		local data = Http.getJson(cfg.baseUrl .. "/ajax/image/list/chap/" .. id, {Referer = Engines.intl.asciiUrl(url), Accept = "application/json, text/javascript, */*; q=0.01", ["X-Requested-With"] = "XMLHttpRequest"})
		local html = type(data) == "table" and nn(data.html)
		if type(html) ~= "string" then
			return
		end
		local pages = {}
		for _, div in ipairs(Html.parse(html, url):select("div.separator")) do
			local a = div:selectFirst("a")
			local src = a and a:attr("abs:href") or ""
			local path = lower(match(src, "^[^?#]*") or "")
			if src ~= "" and not find(path, "%.svg$") and not find(src, "loading_comments", 1, true) then
				pages[#pages + 1] = {index = tonumber(div:attr("data-index")) or #pages, url = src}
			end
		end
		table.sort(pages, function(a, b)
			return a.index < b.index
		end)
		for _, pg in ipairs(pages) do
			-- the image hosts reject a foreign Referer (keiyoushi sends none)
			dt[#dt + 1] = pg.url
		end
	end

	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end


-------------------------------------------------------------------------------
-- GalleryAdults — NSFW gallery sites (en)
-- One gallery = one chapter. Pages come from the plain $.parseJSON('{"1":"j,w,h",...}') list when the gallery
-- page has it, else every reader page (/<pageUri>/<id>/<n>/) is opened for its image.
-------------------------------------------------------------------------------

local GA_EXT = {p = "png", b = "bmp", g = "gif", w = "webp"}

local function gaInput(body, id)
	local tag = match(body, "<input[^>]-id=[\"']" .. id .. "[\"'][^>]*>")
	return tag and match(tag, "value=[\"']([^\"']*)[\"']") or nil
end

local function gaHost(url)
	return url and match(url, "^https?://([^/]+)") or nil
end

function Engines.GalleryAdults(cfg)
	cfg.engine = "galleryadults"
	local p = newParser(cfg, {
		itemSel = "div.thumb",
		titleSel = ".caption",
		linkSel = ".inner_thumb a",
		imgSel = ".inner_thumb img",
		nextSel = ".pagination li.active + li:not(.disabled), a[rel=next]",
		detailSel = ".gallery_top",
		coverSel = ".cover img",
		thumbSel = ".gallery_thumb img",
		pageUri = "g",
		totalId = "load_pages",
		galleryId = "gallery_id",
		serverPrefix = "m",
		readerImgSel = "img#gimg, img#fimg, img#readerImg, #image-container img"
	})
	local c = p.Config
	local base = c.baseUrl

	local function H()
		return {Referer = base .. "/"}
	end

	local function list(path, page, dt, query)
		local url = base .. gsub(gsub(path, "{page}", tostring(page)), "{q}", function()
			return enc(query or "")
		end)
		local doc = Http.getDocument(url, H())
		local count = 0
		for _, el in ipairs(doc:select(c.itemSel)) do
			local a = c.linkSel == "" and el or el:selectFirst(c.linkSel)
			local t = el:selectFirst(c.titleSel)
			local title = t and trim(t:text()) or ""
			local img = el:selectFirst(c.imgSel)
			if title == "" and img then
				title = trim(img:attr("alt"))
			end
			if a and a:attr("href") ~= "" and addManga(dt, p, title, a:attr("abs:href"), attrImg(img)) then
				count = count + 1
			end
		end
		dt.NoPages = count == 0 or doc:selectFirst(c.nextSel) == nil
	end

	function p:getPopularManga(page, dt)
		list(c.popularPath, page, dt)
	end

	function p:getLatestManga(page, dt)
		list(c.latestPath or c.popularPath, page, dt)
	end

	function p:searchManga(query, page, dt)
		list(c.searchPath, page, dt, Engines.decodeSearch(query))
	end

	local function tagList(root, css)
		local out = {}
		for _, a in ipairs(root and css and root:select(css) or {}) do
			local name = c.tagNameSel and a:selectFirst(c.tagNameSel)
			local t = trim(name and name:text() or a:ownText())
			if t == "" then
				t = trim(a:text())
			end
			if t ~= "" then
				out[#out + 1] = t
			end
		end
		return out
	end

	function p:getChapters(manga, dt)
		local url = absolute(base, manga.Link)
		local doc = Http.getDocument(url, H())
		local info = doc:selectFirst(c.detailSel) or doc
		local tags = tagList(info, c.tagsSel)
		local artists = tagList(info, c.artistsSel)
		local parodies = tagList(info, c.parodiesSel)
		local extra = #parodies > 0 and ("Parodies: " .. concat(parodies, ", ")) or ""
		dt.Description = Engines.buildInfo({Author = #artists > 0 and concat(artists, ", ") or nil, Genres = tags, Status = "Completed"}, extra)
		local cover = info:selectFirst(c.coverSel)
		setCover(p, manga, attrImg(cover))
		dt[#dt + 1] = {Name = "Chapter", Link = pathOf(url), Pages = {}, Manga = manga}
	end

	function p:prepareChapter(chapter, dt)
		local url = absolute(base, chapter.Link)
		local body = Http.get(url, H()) or ""
		local doc = Html.parse(body, url)
		local json = match(body, "parseJSON%(%s*'(.-)'%s*%)")
		local dir, loadId = gaInput(body, "load_dir"), gaInput(body, "load_id")
		if json and dir and loadId then
			local server = gaInput(body, "load_server")
			local host
			if server and server ~= "" then
				host = c.serverPrefix .. server .. "." .. gaHost(base)
			else
				host = gaHost(attrImg(doc:selectFirst(c.thumbSel))) or gaHost(attrImg(doc:selectFirst(c.coverSel)))
			end
			local pages = {}
			for n, e in gmatch(json, "\"(%d+)\"%s*:%s*\"(%a)") do
				pages[#pages + 1] = {n = tonumber(n), ext = GA_EXT[e] or "jpg"}
			end
			table.sort(pages, function(a, b)
				return a.n < b.n
			end)
			if host and #pages > 0 then
				for _, pg in ipairs(pages) do
					dt[#dt + 1] = Http.image("https://" .. host .. "/" .. dir .. "/" .. loadId .. "/" .. pg.n .. "." .. pg.ext, base .. "/")
				end
				return
			end
		end
		-- no page list: open each reader page
		local gid = gaInput(body, c.galleryId) or gaInput(body, "load_id") or match(body, "data%-gallery%-id=[\"'](%d+)") or match(chapter.Link, "/(%d+)/?$")
		local total = tonumber(gaInput(body, c.totalId) or "") or tonumber(match(body, "data%-total%-pages=[\"'](%d+)") or "")
		if not total and c.countPattern then
			total = tonumber(match(body, c.countPattern) or "")
		end
		if not total then
			total = doc:select(c.thumbSel):size()
		end
		for n = 1, total or 0 do
			dt[#dt + 1] = base .. "/" .. c.pageUri .. "/" .. gid .. "/" .. n .. "/"
		end
	end

	function p:loadChapterPage(link, dt)
		if type(link) == "string" and find(link, base, 1, true) == 1 then
			local img = attrImg(Http.getDocument(link, H()):selectFirst(c.readerImgSel))
			dt.Link = img and Http.image(img, base .. "/") or nil
		else
			dt.Link = link
		end
	end
	return p
end
