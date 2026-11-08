---Otakio source engines.
---Lua ports of the most used Mihon/keiyoushi "multisrc" themes. One engine powers
---hundreds of sites, so an extension only needs a tiny config file:
---
---  Engines.Madara {
---      id = "KEI_MANGATX_EN", name = "MangaTX", baseUrl = "https://mangatx.to",
---      lang = "en", version = 1, nsfw = false,
---  }
Engines = {}

local co_yield = coroutine.yield
local gsub, find, match, lower, sub = string.gsub, string.find, string.match, string.lower, (string.rawsub or string.sub)
local concat = table.concat

---ISO (Mihon) language code -> Otakio/NOBORU catalog language code
local LANG_MAP = {
	all = "DIF", en = "ENG", ru = "RUS", es = "ESP", ["es-419"] = "ESP", pt = "PRT", ["pt-BR"] = "BRA", ["pt-br"] = "BRA",
	fr = "FRA", ja = "JAP", tr = "TUR", it = "ITA", vi = "VIE", de = "DEU", pl = "POL", id = "IDN", zh = "CHN",
	["zh-Hans"] = "CHN", ["zh-Hant"] = "CHN", ro = "ROU", ko = "KOR", ar = "ARA", th = "THA", uk = "UKR", ["in"] = "IDN",
	fil = "FIL", my = "MYA", bg = "BUL", cs = "CES", hu = "HUN", nl = "NLD", ms = "MSA", fa = "FAS", hi = "HIN"
}

function Engines.toParserLang(iso)
	return LANG_MAP[iso or "all"] or string.upper(iso or "DIF")
end

---Undo ParserManager's search escaping and return plain text
function Engines.decodeSearch(s)
	s = tostring(s or "")
	s = gsub(s, "%%%%", "%%")
	s = gsub(s, "+", " ")
	s = gsub(s, "%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end)
	return s
end

local function trim(s)
	return (gsub(gsub(s or "", "^%s+", ""), "%s+$", ""))
end

local function pathOf(url, baseUrl)
	if not url or url == "" then
		return ""
	end
	local path = match(url, "^%a+://[^/]+(/.*)$")
	if path then
		return path
	end
	return url
end

local function absolute(baseUrl, path)
	if not path or path == "" then
		return baseUrl
	end
	if find(path, "^%a+://") then
		return path
	end
	if sub(path, 1, 2) == "//" then
		return "https:" .. path
	end
	if sub(path, 1, 1) ~= "/" then
		path = "/" .. path
	end
	return baseUrl .. path
end

local function srcsetBest(srcset)
	local best, bestW = nil, -1
	for item in string.gmatch(srcset or "", "[^,]+") do
		local url, w = match(trim(item), "^(%S+)%s*(%d*)")
		w = tonumber(w) or 0
		if url and w >= bestW then
			best, bestW = url, w
		end
	end
	return best
end

---Jsoup-like image attribute resolution used by most WordPress themes
local function imageFromElement(el)
	if not el then
		return nil
	end
	local attrs = {"data-src", "data-lazy-src", "data-lzl-src", "data-cfsrc", "data-manga-src", "data-original"}
	for _, a in ipairs(attrs) do
		if el:hasAttr(a) and el:attr(a) ~= "" then
			return el:attr("abs:" .. a)
		end
	end
	if el:hasAttr("srcset") and el:attr("srcset") ~= "" then
		local best = srcsetBest(el:attr("srcset"))
		if best then
			return Html.absUrl(el:attr("abs:src") ~= "" and el:attr("abs:src") or "", best)
		end
	end
	local src = el:attr("abs:src")
	if find(src, "^data:") then
		return nil
	end
	return src
end
Engines.imageFromElement = imageFromElement

local function buildInfo(info, description)
	local lines = {}
	local L = Language and Settings and Language[Settings.Language] and Language[Settings.Language].OTAKIO or {}
	if info.Author and info.Author ~= "" then
		lines[#lines + 1] = (L.AUTHOR or "Author") .. ": " .. info.Author
	end
	if info.Artist and info.Artist ~= "" and info.Artist ~= info.Author then
		lines[#lines + 1] = (L.ARTIST or "Artist") .. ": " .. info.Artist
	end
	if info.Status and info.Status ~= "" then
		lines[#lines + 1] = (L.STATUS or "Status") .. ": " .. info.Status
	end
	if info.Genres and #info.Genres > 0 then
		lines[#lines + 1] = (L.GENRES or "Genres") .. ": " .. concat(info.Genres, ", ")
	end
	local head = concat(lines, "\n")
	description = trim(description or "")
	if head ~= "" and description ~= "" then
		return head .. "\n\n" .. description
	end
	return head ~= "" and head or description
end
Engines.buildInfo = buildInfo

local function newParser(cfg, defaults)
	for k, v in pairs(defaults) do
		if cfg[k] == nil then
			cfg[k] = v
		end
	end
	cfg.baseUrl = gsub(cfg.baseUrl, "/+$", "")
	local p = Parser:new(cfg.name, cfg.baseUrl, Engines.toParserLang(cfg.lang), cfg.id, cfg.version or 1)
	p.NSFW = cfg.nsfw and true or nil
	p.Config = cfg
	p.Engine = cfg.engine
	p.IsoLang = cfg.lang
	p.ExtensionID = cfg.extension or p.ExtensionID -- native files omit it: keep the id the loader set
	return p
end

local function headers(p, extra)
	local h = {Referer = p.Config.baseUrl .. "/"}
	if extra then
		for k, v in pairs(extra) do
			h[k] = v
		end
	end
	return h
end

local function addManga(dt, p, title, url, cover)
	title = trim(title)
	if title == "" or not url or url == "" then
		return false
	end
	local path = pathOf(url, p.Config.baseUrl)
	-- cover: plain URL (gets the source's Referer) or a ready Http.image link object
	local coverLink = type(cover) == "table" and cover or nil
	local coverUrl = coverLink and coverLink.Link or cover
	local manga = CreateManga(title, path, coverUrl or "", p.ID, absolute(p.Config.baseUrl, path), absolute(p.Config.baseUrl, path))
	if manga then
		if coverLink then
			manga.ImageLink = coverLink
		elseif cover and cover ~= "" then
			manga.ImageLink = Http.image(cover, p.Config.baseUrl .. "/")
		end
		dt[#dt + 1] = manga
		return true
	end
	return false
end

-------------------------------------------------------------------------------
-- Madara (WordPress "WP-Manga" theme) — ~240 sources in keiyoushi
-------------------------------------------------------------------------------

local MADARA_ORDER = {
	["Relevance"] = "",
	["Latest"] = "latest",
	["A-Z"] = "alphabet",
	["Rating"] = "rating",
	["Trending"] = "trending",
	["Most views"] = "views",
	["New"] = "new-manga"
}

local MADARA_STATUS = {
	["Completed"] = "end",
	["Ongoing"] = "on-going",
	["Canceled"] = "canceled",
	["On hold"] = "on-hold"
}

local madaraArchiveSelector = "div.page-item-detail, .manga__item, .c-tabs-item__content"
local madaraSearchCardSelector = ".c-tabs-item__content, div.page-item-detail"

local function madaraParseArchive(p, doc, dt, selector)
	local cfg = p.Config
	local count = 0
	for _, el in ipairs(doc:select(selector or cfg.archiveSelector or madaraArchiveSelector)) do
		local link = el:selectFirst(cfg.archiveUrlSelector or ".post-title a") or el:selectFirst("a")
		if link then
			local title = cfg.archiveTitleSelector and el:selectFirst(cfg.archiveTitleSelector) and el:selectFirst(cfg.archiveTitleSelector):text() or link:text()
			if title == "" then
				title = link:attr("title")
			end
			local cover = imageFromElement(el:selectFirst("img"))
			if addManga(dt, p, title, link:attr("abs:href"), cover) then
				count = count + 1
			end
		end
	end
	return count
end

local function madaraLoadMore(p, page, dt, sortKey, extra)
	local cfg = p.Config
	local body = {
		{"action", "madara_load_more"},
		{"page", tostring(page - 1)},
		{"template", cfg.ajaxTemplate or "madara-core/content/content-archive"},
		{"vars[paged]", "1"},
		{"vars[template]", "archive"},
		{"vars[posts_per_page]", tostring(cfg.pageSize)},
		{"vars[post_type]", "wp-manga"},
		{"vars[post_status]", "publish"},
		{"vars[manga_archives_item_layout]", "big_thumbnail"}
	}
	if cfg.filterNonManga then
		body[#body + 1] = {"vars[meta_query][0][key]", "_wp_manga_chapter_type"}
		body[#body + 1] = {"vars[meta_query][0][value]", "manga"}
	end
	if sortKey then
		body[#body + 1] = {"vars[orderby]", "meta_value_num"}
		body[#body + 1] = {"vars[meta_key]", sortKey}
		body[#body + 1] = {"vars[order]", "DESC"}
	end
	if extra then
		for _, kv in ipairs(extra) do
			body[#body + 1] = kv
		end
	end
	local doc = Http.postDocument(cfg.baseUrl .. "/wp-admin/admin-ajax.php", body, headers(p, {["X-Requested-With"] = "XMLHttpRequest"}), cfg.baseUrl .. "/")
	local count = madaraParseArchive(p, doc, dt)
	dt.NoPages = count < cfg.pageSize
	return count
end

local function madaraListing(p, page, dt, orderBy, sortKey)
	local cfg = p.Config
	if not cfg.useGetListing then
		local count = madaraLoadMore(p, page, dt, sortKey)
		if count > 0 or page > 1 then
			return
		end
		-- older Madara versions don't support madara_load_more; fall back to GET listing
		cfg.useGetListing = true
	end
	local url = cfg.baseUrl .. "/" .. cfg.mangaSubString .. "/" .. (page > 1 and ("page/" .. page .. "/") or "") .. "?m_orderby=" .. orderBy
	local doc = Http.getDocument(url, headers(p))
	local count = madaraParseArchive(p, doc, dt)
	dt.NoPages = count == 0 or doc:selectFirst("div.nav-previous, nav.navigation-ajax, a.nextpostslink, .wp-pagenavi a.next") == nil and count < 10
end

local function madaraSearch(p, query, page, dt, tags)
	local cfg = p.Config
	query = Engines.decodeSearch(query)
	local params = {{"s", query}, {"post_type", "wp-manga"}}
	if tags then
		local order = MADARA_ORDER[tags["Sort By"] or ""]
		if order and order ~= "" then
			params[#params + 1] = {"m_orderby", order}
		end
		for _, status in ipairs(tags["Status"] or {}) do
			if MADARA_STATUS[status] then
				params[#params + 1] = {"status[]", MADARA_STATUS[status]}
			end
		end
		local adult = tags["Adult content"]
		if adult == "None" then
			params[#params + 1] = {"adult", "0"}
		elseif adult == "Only" then
			params[#params + 1] = {"adult", "1"}
		end
	end
	local url = cfg.baseUrl .. "/" .. (page > 1 and ("page/" .. page .. "/") or "") .. "?" .. Http.form(params)
	local doc = Http.getDocument(url, headers(p))
	local count = madaraParseArchive(p, doc, dt, madaraSearchCardSelector)
	dt.NoPages = count == 0 or doc:selectFirst("div.nav-previous, nav.navigation-ajax, a.nextpostslink, .wp-pagenavi a.next, a.next.page-numbers") == nil
end

local function madaraStatus(text)
	text = lower(text or "")
	if find(text, "ongoing") or find(text, "on going") or find(text, "andamento") or find(text, "lançamento") or find(text, "en curso") or find(text, "emision") or find(text, "devam") or find(text, "updating") then
		return "Ongoing"
	elseif find(text, "complet") or find(text, "finaliz") or find(text, "conclu") or find(text, "end") or find(text, "tamamlan") then
		return "Completed"
	elseif find(text, "hiatus") or find(text, "hold") or find(text, "pausa") then
		return "On hold"
	elseif find(text, "cancel") then
		return "Canceled"
	end
	return trim(text) ~= "" and text or nil
end

local function madaraChapterList(p, doc, dt)
	local cfg = p.Config
	local list = {}
	for _, el in ipairs(doc:select(cfg.chapterListSelector or "li.wp-manga-chapter, div.wp-manga-chapter")) do
		local a = el:selectFirst("a")
		if a then
			local href = a:attr("abs:href")
			if href ~= "" then
				local name = cfg.chapterNameSelector and el:selectFirst(cfg.chapterNameSelector) and el:selectFirst(cfg.chapterNameSelector):text() or a:text()
				local date = el:selectFirst(cfg.chapterDateSelector or "span.chapter-release-date")
				list[#list + 1] = {
					Name = trim(name) ~= "" and trim(name) or href,
					Link = pathOf(href, cfg.baseUrl),
					Date = date and date:text() or nil
				}
			end
		end
	end
	return list
end

local function madaraGetChapters(p, manga, dt)
	local cfg = p.Config
	local mangaUrl = absolute(cfg.baseUrl, manga.Link)
	local doc = Http.getDocument(mangaUrl, headers(p))
	co_yield(false)
	-- details
	local info = {}
	local authors = doc:select(cfg.authorSelector or "div.author-content > a, div.manga-authors > a"):eachText()
	info.Author = concat(authors, ", ")
	info.Artist = concat(doc:select("div.artist-content > a"):eachText(), ", ")
	local statusEls = doc:select("div.summary-content, div.summary-heading:contains(Status) + div")
	info.Status = madaraStatus(statusEls[#statusEls] and statusEls[#statusEls]:text())
	info.Genres = doc:select("div.genres-content a"):eachText()
	local descEl = doc:selectFirst(cfg.descriptionSelector or "div.description-summary div.summary__content, div.summary_content div.post-content_item > h5 + div, div.summary_content div.manga-excerpt, div.manga-summary")
	local description = descEl and descEl:wholeText() or ""
	dt.Description = buildInfo(info, description)
	local thumb = imageFromElement(doc:selectFirst("div.summary_image img"))
	if thumb then
		manga.NewImageLink = Http.image(thumb, cfg.baseUrl .. "/")
	end
	-- chapters
	local list = madaraChapterList(p, doc, dt)
	local mode = cfg.chapterMode
	if #list == 0 and mode ~= "AdminAjax" then
		local mangaPath = gsub(pathOf(mangaUrl), "/+$", "")
		local ajaxDoc = Http.postDocument(cfg.baseUrl .. mangaPath .. "/ajax/chapters/", "", headers(p, {["X-Requested-With"] = "XMLHttpRequest"}), cfg.baseUrl .. "/")
		list = madaraChapterList(p, ajaxDoc, dt)
	end
	if #list == 0 then
		local id = doc:selectFirst("[id^=manga-chapters-holder]")
		id = id and id:attr("data-id") or ""
		if id == "" then
			local el = doc:selectFirst("input.rating-post-id")
			id = el and el:attr("value") or ""
		end
		if id == "" then
			local el = doc:selectFirst("a[data-post]")
			id = el and el:attr("data-post") or ""
		end
		if id ~= "" then
			local ajaxDoc = Http.postDocument(cfg.baseUrl .. "/wp-admin/admin-ajax.php", {{"action", "manga_get_chapters"}, {"manga", id}}, headers(p, {["X-Requested-With"] = "XMLHttpRequest"}), cfg.baseUrl .. "/")
			list = madaraChapterList(p, ajaxDoc, dt)
		end
	end
	if #list == 0 and doc:selectFirst("div.chapters-loading") then
		-- Madara-styled comics platform (KunManga, ZinManga): chapters come from a paginated JSON API
		local slug = match(pathOf(mangaUrl), "^/[^/]+/([^/?#]+)")
		local page, lastPage = 1, 1
		while slug and page <= lastPage and page <= 40 do
			local data = Http.getJson(cfg.baseUrl .. "/api/comics/" .. slug .. "/chapters?page=" .. page .. "&per_page=50&order=desc", headers(p, {Accept = "application/json"}))
			data = type(data) == "table" and data.data
			if type(data) ~= "table" or type(data.chapters) ~= "table" then
				break
			end
			for _, c in ipairs(data.chapters) do
				if c.chapter_slug then
					list[#list + 1] = {Name = c.chapter_name or c.chapter_slug, Link = "/" .. match(pathOf(mangaUrl), "^/([^/]+)/") .. "/" .. slug .. "/" .. c.chapter_slug, Date = type(c.updated_at) == "string" and sub(c.updated_at, 1, 10) or nil}
				end
			end
			lastPage = tonumber(data.last_page) or 1
			page = page + 1
		end
	end
	-- Madara lists newest first; Otakio stores oldest first
	for i = #list, 1, -1 do
		local c = list[i]
		dt[#dt + 1] = {Name = c.Name, Link = c.Link, Date = c.Date, Pages = {}, Manga = manga}
	end
end

local function madaraPrepareChapter(p, chapter, dt)
	local cfg = p.Config
	local url = absolute(cfg.baseUrl, chapter.Link)
	local doc = Http.getDocument(url, headers(p))
	if doc:selectFirst("#single-pager") then
		doc = Http.getDocument(url .. (find(url, "?", 1, true) and "&" or "?") .. "style=list", headers(p))
	end
	if doc:selectFirst("#chapter-protector-data") then
		Notifications.pushUnique((Language[Settings.Language].OTAKIO or {}).PROTECTED_CHAPTER or "This chapter is protected and is not supported yet")
	end
	for _, el in ipairs(doc:select(cfg.pageListSelector or "div.page-break, li.blocks-gallery-item, .reading-content .text-left:not(:has(.blocks-gallery-item))")) do
		local img = el:selectFirst("img")
		local src = imageFromElement(img)
		if src and src ~= "" then
			dt[#dt + 1] = Http.image(trim(src), url)
		end
	end
	if #dt == 0 then
		-- "protected" readers draw each page on a canvas that names its image
		for _, canvas in ipairs(doc:select("canvas[data-page-url]")) do
			local src = gsub(trim(canvas:attr("abs:data-page-url")), "^http:", "https:")
			if src ~= "" then
				dt[#dt + 1] = Http.image(src, url)
			end
		end
	end
	if #dt == 0 then
		-- last resort: images placed straight in the reader (centered ones are prev/next buttons)
		for _, img in ipairs(doc:select(".reading-content img")) do
			local src = imageFromElement(img)
			if src and src ~= "" and not find(img:attr("class"), "aligncenter", 1, true) then
				dt[#dt + 1] = Http.image(trim(src), url)
			end
		end
	end
end

---@param cfg table
---@return table Parser
function Engines.Madara(cfg)
	cfg.engine = "madara"
	local p = newParser(cfg, {
		mangaSubString = "manga",
		chapterMode = "MangaPage",
		pageSize = 20,
		filterNonManga = true
	})
	p.Filters = {
		{Name = "Sort By", Type = "radio", Tags = {"Relevance", "Latest", "A-Z", "Rating", "Trending", "Most views", "New"}},
		{Name = "Status", Type = "check", Tags = {"Completed", "Ongoing", "Canceled", "On hold"}},
		{Name = "Adult content", Type = "radio", Tags = {"All", "None", "Only"}}
	}
	function p:getPopularManga(page, dt)
		madaraListing(self, page, dt, "views", "_wp_manga_views")
	end
	function p:getLatestManga(page, dt)
		madaraListing(self, page, dt, "latest", "_latest_update")
	end
	function p:searchManga(query, page, dt, tags)
		madaraSearch(self, query, page, dt, tags)
	end
	function p:getChapters(manga, dt)
		madaraGetChapters(self, manga, dt)
	end
	function p:prepareChapter(chapter, dt)
		madaraPrepareChapter(self, chapter, dt)
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

-------------------------------------------------------------------------------
-- MangaThemesia (WP "MangaReader"/"MangaStream") — ~110 sources in keiyoushi
-------------------------------------------------------------------------------

local THEMESIA_ORDER = {
	["Default"] = "",
	["A-Z"] = "title",
	["Z-A"] = "titlereverse",
	["Latest update"] = "update",
	["Latest added"] = "latest",
	["Popular"] = "popular"
}
local THEMESIA_STATUS = {["All"] = "", ["Ongoing"] = "ongoing", ["Completed"] = "completed", ["Hiatus"] = "hiatus", ["Dropped"] = "dropped"}
local THEMESIA_TYPE = {["All"] = "", ["Manga"] = "manga", ["Manhwa"] = "manhwa", ["Manhua"] = "manhua", ["Comic"] = "comic"}

local function themesiaImg(el)
	if not el then
		return nil
	end
	for _, a in ipairs({"data-lazy-src", "data-src", "data-cfsrc"}) do
		if el:hasAttr(a) and el:attr(a) ~= "" then
			return el:attr("abs:" .. a)
		end
	end
	local src = el:attr("abs:src")
	if src == "" or find(src, "^data:") then
		return nil
	end
	return src
end

local function themesiaList(p, page, dt, params)
	local cfg = p.Config
	local q = {}
	for _, kv in ipairs(params) do
		if kv[2] and kv[2] ~= "" then
			q[#q + 1] = kv
		end
	end
	q[#q + 1] = {"page", tostring(page)}
	local url = cfg.baseUrl .. cfg.mangaUrlDirectory .. "/?" .. Http.form(q)
	local doc = Http.getDocument(url, headers(p))
	local count = 0
	for _, el in ipairs(doc:select(cfg.searchMangaSelector or ".utao .uta .imgu, .listupd .bs .bsx, .listo .bs .bsx")) do
		local a = el:selectFirst("a")
		if a then
			local title = a:attr("title")
			if title == "" then
				local tt = el:selectFirst(".tt, .bigor .tt, h3, h2")
				title = tt and tt:text() or a:text()
			end
			if addManga(dt, p, title, a:attr("abs:href"), themesiaImg(el:selectFirst("img"))) then
				count = count + 1
			end
		end
	end
	dt.NoPages = count == 0 or doc:selectFirst("div.pagination .next, div.hpage .r") == nil
end

local function themesiaGetChapters(p, manga, dt)
	local cfg = p.Config
	local doc = Http.getDocument(absolute(cfg.baseUrl, manga.Link), headers(p))
	co_yield(false)
	local details = doc:selectFirst(cfg.seriesDetailsSelector or "div.bigcontent, div.animefull, div.main-info, div.postbody") or doc
	local info = {}
	local function pick(css)
		local el = details:selectFirst(css)
		if el then
			local t = el:ownText()
			if t == "" then
				t = el:text()
			end
			if t ~= "" and t ~= "-" and lower(t) ~= "n/a" and lower(t) ~= "unknown" then
				return t
			end
		end
	end
	info.Author = pick(".infotable tr:contains(Author) td:last-child, .tsinfo .imptdt:contains(Author) i, .fmed b:contains(Author)+span, .tsinfo .imptdt:contains(autor) i, .fmed b:contains(Autor)+span, .tsinfo .imptdt:contains(Yazar) i")
	info.Artist = pick(".infotable tr:contains(Artist) td:last-child, .tsinfo .imptdt:contains(Artist) i, .fmed b:contains(Artist)+span, .fmed b:contains(Artista)+span")
	info.Status = pick(".infotable tr:contains(Status) td:last-child, .tsinfo .imptdt:contains(Status) i, .fmed b:contains(Status)+span, .tsinfo .imptdt:contains(Estado) i, .tsinfo .imptdt:contains(Durum) i")
	info.Genres = details:select("div.gnr a, .mgen a, .seriestugenre a"):eachText()
	local desc = details:selectFirst(cfg.seriesDescriptionSelector or ".desc, .entry-content[itemprop=description]")
	dt.Description = buildInfo(info, desc and desc:wholeText() or "")
	local thumb = themesiaImg(details:selectFirst(".infomanga > div[itemprop=image] img, .thumb img"))
	if thumb then
		manga.NewImageLink = Http.image(thumb, cfg.baseUrl .. "/")
	end
	local list = {}
	for _, el in ipairs(doc:select(cfg.chapterListSelector or "div.bxcl li, div.cl li, #chapterlist li, ul li:has(div.chbox):has(div.eph-num)")) do
		local a = el:selectFirst("a")
		if a and a:attr("href") ~= "" then
			local nameEl = el:select(".lch a, .chapternum")
			local name = nameEl:text()
			if name == "" then
				name = a:text()
			end
			local date = el:selectFirst(".chapterdate")
			list[#list + 1] = {Name = trim(name), Link = pathOf(a:attr("abs:href"), cfg.baseUrl), Date = date and date:text() or nil}
		end
	end
	for i = #list, 1, -1 do
		local c = list[i]
		dt[#dt + 1] = {Name = c.Name, Link = c.Link, Date = c.Date, Pages = {}, Manga = manga}
	end
end

local function themesiaPrepareChapter(p, chapter, dt)
	local cfg = p.Config
	local url = absolute(cfg.baseUrl, chapter.Link)
	local doc, body = Http.getDocument(url, headers(p))
	for _, img in ipairs(doc:select(cfg.pageSelector or "div#readerarea img")) do
		local src = themesiaImg(img)
		if src and src ~= "" then
			dt[#dt + 1] = Http.image(trim(src), url)
		end
	end
	if #dt > 0 then
		return
	end
	-- pages loaded via javascript: ts_reader.run({... "images":[...] })
	local script = doc:selectFirst("script[src^=data:text/javascript;base64,dHNfcmVhZGVyLnJ1bih7]")
	local source = body
	if script then
		source = Http.base64decode(match(script:attr("src"), "base64,(.+)$") or "")
	end
	local list = match(source, "[\"']?images[\"']?%s*[:=]%s*(%b[])") or match(source, "[\"']?imageUrls[\"']?%s*[:=]%s*(%b[])")
	if list then
		local images = Json.decode(list) or {}
		for _, src in ipairs(images) do
			if type(src) == "string" then
				src = gsub(src, "\\/", "/")
				dt[#dt + 1] = Http.image(absolute(cfg.baseUrl, src), url)
			end
		end
	end
end

---@param cfg table
---@return table Parser
function Engines.MangaThemesia(cfg)
	cfg.engine = "mangathemesia"
	local p = newParser(cfg, {mangaUrlDirectory = "/manga"})
	if cfg.mangaUrlDirectory ~= "" and sub(cfg.mangaUrlDirectory, 1, 1) ~= "/" then
		cfg.mangaUrlDirectory = "/" .. cfg.mangaUrlDirectory
	end
	p.Filters = {
		{Name = "Order by", Type = "radio", Tags = {"Default", "A-Z", "Z-A", "Latest update", "Latest added", "Popular"}},
		{Name = "Status", Type = "radio", Tags = {"All", "Ongoing", "Completed", "Hiatus", "Dropped"}},
		{Name = "Type", Type = "radio", Tags = {"All", "Manga", "Manhwa", "Manhua", "Comic"}}
	}
	function p:getPopularManga(page, dt)
		themesiaList(self, page, dt, {{"order", "popular"}})
	end
	function p:getLatestManga(page, dt)
		themesiaList(self, page, dt, {{"order", "update"}})
	end
	function p:searchManga(query, page, dt, tags)
		local params = {{"title", Engines.decodeSearch(query)}}
		if tags then
			params[#params + 1] = {"order", THEMESIA_ORDER[tags["Order by"] or ""] or ""}
			params[#params + 1] = {"status", THEMESIA_STATUS[tags["Status"] or ""] or ""}
			params[#params + 1] = {"type", THEMESIA_TYPE[tags["Type"] or ""] or ""}
		end
		themesiaList(self, page, dt, params)
	end
	function p:getChapters(manga, dt)
		themesiaGetChapters(self, manga, dt)
	end
	function p:prepareChapter(chapter, dt)
		themesiaPrepareChapter(self, chapter, dt)
	end
	function p:loadChapterPage(link, dt)
		dt.Link = link
	end
	return p
end

---os is removed by the sandbox after startup; Clock keeps the original os.date
local function date(fmt, t)
	if Clock and Clock.date then
		return Clock.date(fmt, t)
	end
	return os and os.date(fmt, t)
end

---Shared helpers for the engines in engines_extra.lua and native extensions
Engines.util = {
	date = date,
	trim = trim,
	pathOf = pathOf,
	absolute = absolute,
	newParser = newParser,
	headers = headers,
	addManga = addManga,
	srcsetBest = srcsetBest
}
