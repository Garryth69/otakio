---Mihon-style screens added by Otakio: Updates, History, Extensions and Global search.
Screens = {}

local floor, max, min, abs, ceil = math.floor, math.max, math.min, math.abs, math.ceil
local X0 = Config.RAIL_WIDTH + 12
local X1 = 944
local TOP = 64

local function L()
	return Language[Settings.Language].OTAKIO
end

local function pressed(pad, oldPad, btn)
	return Controls.check(pad, btn) and not Controls.check(oldPad, btn)
end

-------------------------------------------------------------------------------
-- ListView: vertical list with variable row heights, d-pad + touch + inertia
-------------------------------------------------------------------------------

local ListView = {}
ListView.__index = ListView

function ListView.new(top)
	local lv = setmetatable({top = top or TOP, y = 0, v = 0, selected = 0, rows = {}, offsets = {}, height = 0, touchMode = 0, touchY = 0, timer = Timer.new(), interval = 260, pressedItem = 0}, ListView)
	return lv
end

---rows: list of {h = height, selectable = bool, ...}
function ListView:setRows(rows)
	self.rows = rows
	local y = 0
	for i, r in ipairs(rows) do
		self.offsets[i] = y
		y = y + r.h
	end
	for i = #rows + 1, #self.offsets do
		self.offsets[i] = nil
	end
	self.height = y
	if self.selected > #rows then
		self.selected = #rows
	end
end

function ListView:reset()
	self.y, self.v, self.selected = 0, 0, 0
end

local function nextSelectable(rows, from, dir)
	local i = from + dir
	while rows[i] do
		if rows[i].selectable ~= false then
			return i
		end
		i = i + dir
	end
	return from
end

---@return integer|nil index of a tapped row
function ListView:input(oldPad, pad, oldTouch, touch)
	local rows = self.rows
	local dirty = false
	if touch.x then
		self.selected = 0
	end
	local up, down = Controls.check(pad, SCE_CTRL_UP), Controls.check(pad, SCE_CTRL_DOWN)
	if (up or down) then
		local fresh = (up and not Controls.check(oldPad, SCE_CTRL_UP)) or (down and not Controls.check(oldPad, SCE_CTRL_DOWN))
		if fresh or Timer.getTime(self.timer) > self.interval then
			if self.selected == 0 then
				-- first visible selectable row
				for i = 1, #rows do
					if self.offsets[i] + rows[i].h > self.y and rows[i].selectable ~= false then
						self.selected = i
						break
					end
				end
			else
				self.selected = nextSelectable(rows, self.selected, up and -1 or 1)
			end
			self.interval = fresh and 260 or max(45, self.interval / 2)
			Timer.reset(self.timer)
		end
	else
		self.interval = 260
	end
	-- touch
	local tapped = nil
	if self.touchMode == 0 and oldTouch.x and touch.x and touch.x > X0 and touch.y > self.top then
		self.touchMode = 1
		self.touchY = touch.y
	elseif self.touchMode ~= 0 and not touch.x then
		if self.touchMode == 1 and oldTouch.x then
			local cy = oldTouch.y - self.top + self.y
			for i = 1, #rows do
				if cy >= self.offsets[i] and cy < self.offsets[i] + rows[i].h then
					if rows[i].selectable ~= false then
						tapped = i
						self.tapX = oldTouch.x
					end
					break
				end
			end
		end
		self.touchMode = 0
	end
	if self.touchMode == 1 and touch.y and (abs(touch.y - self.touchY) > 10 or abs(self.v) > 0.1) then
		self.touchMode = 2
	end
	if self.touchMode == 2 and touch.y and oldTouch.y then
		self.v = oldTouch.y - touch.y
	end
	self.pressedItem = 0
	if self.touchMode == 1 and touch.y then
		local cy = touch.y - self.top + self.y
		for i = 1, #rows do
			if cy >= self.offsets[i] and cy < self.offsets[i] + rows[i].h then
				self.pressedItem = i
				break
			end
		end
	end
	return tapped
end

function ListView:update()
	local viewH = 524 - self.top
	if abs(self.v) < 1 then
		self.v = 0
	else
		self.y = self.y + self.v
		self.v = self.v / 1.12
	end
	if self.selected > 0 and self.rows[self.selected] then
		local target = self.offsets[self.selected] + self.rows[self.selected].h / 2 - viewH / 2
		self.y = self.y + (target - self.y) / 4
	end
	local maxY = max(0, self.height - viewH)
	if self.y < 0 then
		self.y, self.v = 0, 0
	elseif self.y > maxY then
		self.y, self.v = maxY, 0
	end
end

---Iterates visible rows: calls fn(i, row, screenY, isSelected)
function ListView:draw(fn)
	local rows = self.rows
	for i = 1, #rows do
		local y = self.top + self.offsets[i] - self.y
		if y > 544 then
			break
		end
		if y + rows[i].h > self.top - 10 then
			fn(i, rows[i], y, i == self.selected or i == self.pressedItem)
		end
	end
	UI.scrollbar(X1 + 6, self.top, 520, self.y, self.height, 524 - self.top)
end

-------------------------------------------------------------------------------
-- shared: small cover thumbnails for list rows
-------------------------------------------------------------------------------

local thumbs = {}

local function ensureThumb(manga)
	if manga and not manga.ImageDownload then
		Catalogs.loadMangaImage(manga)
		manga.ImageDownload = true
		thumbs[#thumbs + 1] = manga
	end
end

local function freeThumbs()
	for _, m in ipairs(thumbs) do
		Catalogs.freeMangaImage(m)
	end
	thumbs = {}
end

local function drawThumb(manga, x, y, w, h)
	if manga and manga.Image and manga.Image.e then
		DrawDetailsManga(x + w / 2, y + h / 2, manga, h / MANGA_HEIGHT)
	else
		UI.shimmer(x, y, x + w, y + h)
	end
end

-------------------------------------------------------------------------------
-- Updates
-------------------------------------------------------------------------------

local Upd = {list = ListView.new(TOP), version = -1}
Screens.UPDATES = Upd

local function buildUpdateRows()
	local rows = {}
	local lastLabel
	for i, e in ipairs(Updates.getList()) do
		local label = Clock.dayLabel(e.Date or 0)
		if label ~= lastLabel then
			rows[#rows + 1] = {h = 36, selectable = false, header = label}
			lastLabel = label
		end
		rows[#rows + 1] = {h = 72, entry = e, index = i, manga = Database.getByKey(e.MangaKey) or Cache.getMangaByKey(e.MangaKey)}
	end
	Upd.list:setRows(rows)
end

function Upd.onEnter()
	Updates.markSeen()
	Upd.version = -1
end

function Upd.onLeave()
	freeThumbs()
end

local function openUpdate(row)
	local chapter, chapters, idx, manga = Updates.resolve(row.entry)
	if not manga then
		Notifications.push(L().MANGA_NOT_FOUND)
		return
	end
	if chapters and idx then
		freeThumbs()
		Cache.makeHistory(manga)
		Reader.load(chapters, idx)
		AppMode = READER
	else
		Details.setManga(manga)
	end
end

function Upd.input(oldPad, pad, oldTouch, touch)
	local tapped = Upd.list:input(oldPad, pad, oldTouch, touch)
	local row = Upd.list.rows[tapped or Upd.list.selected]
	if tapped and row then
		openUpdate(row)
	elseif pressed(pad, oldPad, SCE_CTRL_CROSS) and row and row.entry then
		openUpdate(row)
	elseif pressed(pad, oldPad, SCE_CTRL_START) and row and row.manga then
		Details.setManga(row.manga)
	elseif pressed(pad, oldPad, SCE_CTRL_SQUARE) and row and row.entry then
		local chapter = Updates.resolve(row.entry)
		if chapter and chapter.Manga then
			if ChapterSaver.check(chapter) then
				Notifications.push(L().ALREADY_DOWNLOADED)
			elseif not ChapterSaver.is_downloading(chapter) then
				ChapterSaver.downloadChapter(chapter)
			end
		end
	elseif pressed(pad, oldPad, SCE_CTRL_TRIANGLE) then
		-- Triangle refreshes, like in the Library
		ParserManager.updateCounters()
	elseif pressed(pad, oldPad, SCE_CTRL_SELECT) and #Updates.getList() > 0 then
		Dialog.confirm(L().CLEAR_UPDATES_Q, nil, function()
			Updates.clear()
		end)
	end
end

function Upd.update()
	if Upd.version ~= Updates.getVersion() then
		Upd.version = Updates.getVersion()
		buildUpdateRows()
	end
	Upd.list:update()
	Panel.set(Panels.UPDATES or {})
end

function Upd.draw()
	if #Upd.list.rows == 0 then
		UI.emptyState((X0 + X1) / 2, 290, L().NO_UPDATES, L().NO_UPDATES_HINT, "(￣ω￣)")
	end
	Upd.list:draw(function(i, row, y, sel)
		if row.header then
			UI.text(BONT16, X0 + 8, y + 10, row.header, COLOR_ACCENT)
			return
		end
		if sel then
			UI.listHighlight(X0, y + 2, X1, y + row.h - 4, i == Upd.list.selected)
		end
		local manga = row.manga
		if manga then
			ensureThumb(manga)
		end
		drawThumb(manga, X0 + 14, y + 7, 38, 57)
		-- same row type as Browse, Extensions and Downloads: title in FONT20, details in FONT16
		UI.text(FONT20, X0 + 66, y + 9, row.entry.MangaName, COLOR_FONT, 600)
		UI.text(FONT16, X0 + 66, y + 39, row.entry.ChapterName, COLOR_SUBFONT, 600)
		UI.textRight(FONT16, X1 - 16, y + 12, Clock.relative(row.entry.Date), COLOR_SUBFONT)
		if manga then
			local chapter = {Link = row.entry.ChapterLink, Manga = manga}
			if ChapterSaver.check(chapter) then
				UI.textRight(BONT16, X1 - 16, y + 38, "✓", COLOR_SUCCESS)
			else
				local d = ChapterSaver.is_downloading(chapter)
				if d then
					local pct = d.page_count and d.page_count > 0 and math.ceil(100 * d.page / d.page_count) or 0
					UI.textRight(FONT16, X1 - 16, y + 38, pct .. "%", COLOR_ACCENT)
				end
			end
		end
	end)
	Graphics.fillRect(Config.RAIL_WIDTH, 960, 0, TOP - 4, COLOR_BACK)
	UI.header(L().UPDATES, #Updates.getList() > 0 and tostring(#Updates.getList()) or nil)
	if LibraryRefresh.current then
		UI.textRight(FONT16, X1 - 30, 22, string.format(L().REFRESHING, LibraryRefresh.current, LibraryRefresh.total), COLOR_SUBFONT)
		UI.spinner(X1 - 12, 32, 7)
	end
end

-------------------------------------------------------------------------------
-- History
-------------------------------------------------------------------------------

local Hist = {list = ListView.new(TOP), version = -1, info = {}}
Screens.HISTORY = Hist

local function historyInfo(manga)
	local key = Cache.getKey(manga)
	local info = Hist.info[key]
	if info then
		return info
	end
	info = {chapter = nil, page = nil}
	if not Cache.BookmarksLoaded(manga) then
		Cache.loadBookmarks(manga)
	end
	local latest = Cache.getLatestBookmark(manga)
	if latest then
		local chapters = Cache.loadChapters(manga, true)
		for i = 1, #chapters do
			if chapters[i].Link:gsub("%p", "") == latest then
				info.chapter = chapters[i].Name
				info.index = i
				info.total = #chapters
				local b = Cache.getBookmark(chapters[i])
				info.page = b
				break
			end
		end
	end
	Hist.info[key] = info
	return info
end

function Hist.onEnter()
	Hist.version = -1
	Hist.info = {}
end

function Hist.onLeave()
	freeThumbs()
end

local function resume(manga)
	local chapters = Cache.loadChapters(manga, true)
	if #chapters == 0 then
		Details.setManga(manga)
		return
	end
	local info = historyInfo(manga)
	local idx = info.index or 1
	if info.page == true and chapters[idx + 1] then
		idx = idx + 1
	end
	freeThumbs()
	Cache.makeHistory(manga)
	Reader.load(chapters, idx)
	AppMode = READER
end

function Hist.input(oldPad, pad, oldTouch, touch)
	local tapped = Hist.list:input(oldPad, pad, oldTouch, touch)
	local row = Hist.list.rows[tapped or Hist.list.selected]
	if tapped and row then
		if Hist.list.tapX and Hist.list.tapX > X1 - 140 then
			resume(row.manga)
		else
			Details.setManga(row.manga)
		end
	elseif pressed(pad, oldPad, SCE_CTRL_CROSS) and row then
		resume(row.manga)
	elseif pressed(pad, oldPad, SCE_CTRL_START) and row then
		Details.setManga(row.manga)
	elseif pressed(pad, oldPad, SCE_CTRL_SQUARE) and row then
		Cache.removeHistory(row.manga)
	end
end

function Hist.update()
	if Hist.version ~= Cache.getHistoryVersion() then
		Hist.version = Cache.getHistoryVersion()
		local rows = {}
		for _, manga in ipairs(Cache.getHistory()) do
			rows[#rows + 1] = {h = 80, manga = manga}
		end
		Hist.list:setRows(rows)
	end
	Hist.list:update()
	Panel.set(Panels.HISTORY or {})
end

function Hist.draw()
	if #Hist.list.rows == 0 then
		UI.emptyState((X0 + X1) / 2, 290, L().NO_HISTORY, L().NO_HISTORY_HINT, "(´• ω •`)")
	end
	Hist.list:draw(function(i, row, y, sel)
		if sel then
			UI.listHighlight(X0, y + 2, X1, y + row.h - 4, i == Hist.list.selected)
		end
		local manga = row.manga
		ensureThumb(manga)
		drawThumb(manga, X0 + 14, y + 8, 42, 63)
		UI.text(FONT20, X0 + 70, y + 6, manga.Name, COLOR_FONT, 560)
		local info = historyInfo(manga)
		local sub
		if info.chapter then
			sub = info.chapter
			if type(info.page) == "number" then
				sub = sub .. "  ·  " .. Language[Settings.Language].DETAILS.PAGE .. info.page
			elseif info.page == true then
				sub = sub .. "  ·  ✓"
			end
		else
			local p = GetAnyParserByID(manga.ParserID)
			sub = p and p.Name or manga.ParserID
		end
		UI.text(FONT16, X0 + 70, y + 34, sub, COLOR_SUBFONT, 560)
		UI.text(FONT16, X0 + 70, y + 54, Clock.relative(Cache.getLastRead(manga)), COLOR_SUBFONT, 300)
		-- resume button
		UI.roundRect(X1 - 130, y + 22, X1 - 16, y + 56, 17, COLOR_ACCENT)
		UI.textCenter(BONT16, X1 - 73, y + 28, info.chapter and L().RESUME or L().START, COLOR_ON_ACCENT)
	end)
	Graphics.fillRect(Config.RAIL_WIDTH, 960, 0, TOP - 4, COLOR_BACK)
	UI.header(L().HISTORY, Settings.Incognito and L().INCOGNITO_ON or nil)
end

-------------------------------------------------------------------------------
-- Extensions
-------------------------------------------------------------------------------

local EXT_TOP = 138
local Ext = {list = ListView.new(EXT_TOP), tab = 1, lang = "*", query = "", version = -1}
Screens.EXTENSIONS = Ext

local TABS = {"INSTALLED", "AVAILABLE", "UPDATES_TAB"}

---Language groups shown as chips (Mihon codes folded together: pt + pt-BR, es + es-419)
local LANG_GROUPS = {
	{id = "*", label = "ALL"},
	{id = "en", label = "LANG_EN", codes = {en = true}},
	{id = "pt", label = "LANG_PT", codes = {["pt-BR"] = true, ["pt-br"] = true, pt = true}},
	{id = "es", label = "LANG_ES", codes = {es = true, ["es-419"] = true}},
	{id = "fr", label = "LANG_FR", codes = {fr = true}},
	{id = "de", label = "LANG_DE", codes = {de = true}},
	{id = "it", label = "LANG_IT", codes = {it = true}},
	{id = "ru", label = "LANG_RU", codes = {ru = true}},
	{id = "ja", label = "LANG_JA", codes = {ja = true}},
	{id = "zh", label = "LANG_ZH", codes = {zh = true, ["zh-Hans"] = true, ["zh-Hant"] = true, ["zh-hans"] = true, ["zh-hant"] = true}}
}
-- multi-language sources have no chip: they show up under every language (or under the languages they list)
local MULTI_GROUP = {id = "all", label = "LANG_MULTI", codes = {all = true, multi = true}}

local function groupOf(lang)
	lang = lang or "all"
	if MULTI_GROUP.codes[lang] then
		return MULTI_GROUP, 1
	end
	for i = 2, #LANG_GROUPS do
		if LANG_GROUPS[i].codes[lang] then
			return LANG_GROUPS[i], i
		end
	end
	return {id = "other", label = "LANG_OTHER"}, #LANG_GROUPS + 1
end

---Chips of the language groups the user keeps active (More > Source languages); "All" is always first
local function activeGroups()
	local out = {}
	for i, g in ipairs(LANG_GROUPS) do
		if i == 1 or IsSourceLangEnabled(g.id) then
			out[#out + 1] = g
		end
	end
	return out
end

---Chip text of a language group: the full name, or its short code when all chips don't fit in one row
local chipFits = {}
local function langChipLabel(g)
	local groups = activeGroups()
	local key = Settings.Language .. ":" .. #groups
	for _, x in ipairs(groups) do
		key = key .. x.id
	end
	if chipFits[key] == nil then
		local full = 0
		for _, x in ipairs(groups) do
			full = full + Font.getTextWidth(FONT16, L()[x.label]) + 32
		end
		chipFits[key] = full <= X1 - X0
	end
	if chipFits[key] or g.id == "*" then
		return L()[g.label]
	end
	return string.upper(g.id)
end

---Set of language groups from a list of ISO codes (a multi-language extension's "langs": {"en", "es"...})
local function langSet(list)
	if type(list) ~= "table" or #list == 0 then
		return nil
	end
	local set = {}
	for _, code in ipairs(list) do
		local g = groupOf(code).id
		if g == "all" then
			return nil
		end
		set[g] = true
	end
	return set
end

---Row label of a multi-language extension with known languages ("en/es/fr/de"), else nil (its own code is shown)
local function langLabel(lang, groups)
	if groupOf(lang).id ~= "all" or not groups then
		return nil
	end
	local t = {}
	for g in pairs(groups) do
		t[#t + 1] = g
	end
	table.sort(t, function(a, b)
		local _, ia = groupOf(a)
		local _, ib = groupOf(b)
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	return table.concat(t, "/")
end

---@param lang string the extension's language ("all" for multi-language)
---@param langs table|nil set of the groups a multi-language extension really has sources in (nil = every language)
local function langMatches(lang, langs)
	local id = groupOf(lang).id
	if id == "all" and langs then
		-- an extension with sources in en, es, fr, de shows under those chips only, and only while one of them is active
		if Ext.lang ~= "*" then
			return langs[Ext.lang] == true and IsSourceLangEnabled(Ext.lang)
		end
		for g in pairs(langs) do
			if IsSourceLangEnabled(g) then
				return true
			end
		end
		return false
	end
	if id ~= "all" and not IsSourceLangEnabled(id) then
		return false
	end
	return Ext.lang == "*" or id == Ext.lang or id == "all"
end

local function extVisible(e)
	if e.nsfw and not Settings.NSFW then
		return false
	end
	e.langGroups = e.langGroups or langSet(e.langs)
	e.langLabel = e.langLabel or langLabel(e.lang, e.langGroups)
	if not langMatches(e.lang, e.langGroups) then
		return false
	end
	if Ext.query ~= "" and not e.name:lower():find(Ext.query:lower(), 1, true) then
		return false
	end
	return true
end

---Sorts by language group, status, then name, and inserts a header row per group
local function groupedRows(list)
	for _, e in ipairs(list) do
		e.status = SourceStatus.of(e.id, e.entry or e)
	end
	-- inside each language: working sources first (green, yellow, red), then by name
	table.sort(list, function(a, b)
		local _, ga = groupOf(a.lang)
		local _, gb = groupOf(b.lang)
		if ga ~= gb then
			return ga < gb
		end
		local ra, rb = SourceStatus.rank(a.status), SourceStatus.rank(b.status)
		if ra ~= rb then
			return ra < rb
		end
		return a.name:lower() < b.name:lower()
	end)
	local rows, last = {}, nil
	for _, e in ipairs(list) do
		local g = groupOf(e.lang)
		if g.id ~= last then
			rows[#rows + 1] = {h = 34, selectable = false, header = L()[g.label] or g.id}
			last = g.id
		end
		rows[#rows + 1] = {h = 72, ext = e}
	end
	return rows
end

local function buildExtRows()
	local installed = Extensions.getInstalled()
	local list = {}
	if Ext.tab == 1 or Ext.tab == 3 then
		for id, meta in pairs(installed) do
			local entry = Extensions.getEntry(id)
			local e = {id = id, name = meta.name, lang = meta.lang or "all", version = meta.version, nsfw = meta.nsfw, compat = meta.compat, origin = meta.origin, installed = true, entry = entry, error = meta.error}
			e.langGroups = GetExtensionLangGroups(id) or langSet(entry and entry.langs)
			e.langLabel = langLabel(e.lang, e.langGroups)
			if (Ext.tab == 1 or Extensions.hasUpdate(id)) and langMatches(e.lang, e.langGroups) and (Ext.query == "" or e.name:lower():find(Ext.query:lower(), 1, true)) then
				list[#list + 1] = e
			end
		end
	else
		for _, e in ipairs(Extensions.getCatalog()) do
			if not installed[e.id] and extVisible(e) then
				list[#list + 1] = e
			end
		end
	end
	Ext.list:setRows(groupedRows(list))
end

local function setLangGroup(id)
	Ext.lang = id
	Ext.list:reset()
	Ext.version = -1
end

---Language groups for the setup / settings checklist (without "All")
function Ext.langGroups()
	local out = {}
	for i = 2, #LANG_GROUPS do
		out[#out + 1] = LANG_GROUPS[i]
	end
	out[#out + 1] = {id = "other", label = "LANG_OTHER"}
	return out
end

---Called after the active languages change: drop a chip that is no longer shown
function Ext.languagesChanged()
	if Ext.lang ~= "*" and not IsSourceLangEnabled(Ext.lang) then
		Ext.lang = "*"
	end
	Ext.list:reset()
	Ext.version = -1
	ChangeNSFW()
end

function Ext.onEnter()
	if Ext.lang ~= "*" and not IsSourceLangEnabled(Ext.lang) then
		Ext.lang = "*"
	end
	Extensions.refresh(false)
	Ext.version = -1
end

local function extAction(e)
	if Extensions.isInstalling(e.id) then
		return
	end
	if not e.installed then
		if not Threads.isOnline() and not (e.source or ""):find("^app0:") then
			Notifications.push(Language[Settings.Language].SETTINGS.NoConnection)
			return
		end
		Extensions.install(e)
		return
	end
	local items = {}
	if Extensions.hasUpdate(e.id) then
		items[#items + 1] = {label = L().UPDATE, value = "update"}
	end
	items[#items + 1] = {label = L().OPEN_SOURCE, value = "open"}
	items[#items + 1] = {label = L().UNINSTALL, value = "uninstall", danger = true}
	Dialog.menu(e.name, items, function(item)
		if item.value == "update" then
			Extensions.install(e.entry)
		elseif item.value == "uninstall" then
			Dialog.confirm(string.format(L().UNINSTALL_Q, e.name), nil, function()
				Extensions.uninstall(e.id)
			end)
		elseif item.value == "open" then
			-- straight into the source's catalog in Browse, whatever language Browse is filtered to
			-- an extension with one source per language opens the one of the language chip that is selected
			local p = GetParserOfExtension(e.id, Ext.lang ~= "*" and Ext.lang or nil)
			if p and (Settings.NSFW or not p.NSFW) then
				Menu.setMode("CATALOGS")
				Catalogs.openParser(p)
			else
				Notifications.push(L().SOURCE_HIDDEN)
			end
		end
	end)
end

function Ext.repoMenu()
	local items = {
		{label = L().REFRESH_REPOS, value = "refresh"},
		{label = L().UPDATE_ALL, value = "updateall"},
		{label = "+ " .. L().ADD_REPO, value = "add"},
		{label = L().IMPORT_NOBORU_PARSERS, value = "noboru"}
	}
	for _, r in ipairs(Extensions.getRepos()) do
		local st = Extensions.getRepoStatus(r.url)
		local sub
		if r.builtin then
			sub = st == "offline" and L().REPO_OFFLINE or L().REPO_BUILTIN
		elseif st and st:find("^mihon:") then
			local m, t = st:match("^mihon:(%d+)/(%d+)")
			sub = string.format(L().REPO_MIHON, tonumber(m), tonumber(t))
		else
			sub = r.url .. (st == "error" and "  ⚠" or "")
		end
		items[#items + 1] = {label = r.name, sub = sub, value = r}
	end
	Dialog.menu(L().REPOSITORIES, items, function(item)
		if item.value == "refresh" then
			Extensions.refresh(true)
		elseif item.value == "updateall" then
			Extensions.updateAll()
		elseif item.value == "add" then
			local url = TextInput(L().REPO_URL, "", 256, TYPE_LATIN)
			if url and url ~= "" and url ~= "https://" then
				local function add()
					if not Extensions.addRepo(url) then
						Notifications.push(L().REPO_EXISTS)
					end
				end
				if Extensions.isOfficialRepo(url) then
					add()
				else
					-- extensions run code on the console: third-party repositories need an explicit OK
					Dialog.confirm(L().REPO_UNOFFICIAL_Q, L().REPO_UNOFFICIAL_MSG, add)
				end
			end
		elseif item.value == "noboru" then
			local n = Extensions.importNoboruParsers()
			Notifications.push(string.format(L().IMPORTED_N, n))
		elseif type(item.value) == "table" and not item.value.builtin then
			Dialog.confirm(string.format(L().REMOVE_REPO_Q, item.value.name), item.value.url, function()
				Extensions.removeRepo(item.value.url)
			end)
		end
	end)
end

function Ext.input(oldPad, pad, oldTouch, touch)
	-- tab chips touch
	if oldTouch.x and not touch.x and oldTouch.y > 56 and oldTouch.y < 96 then
		local x = X0
		for i, t in ipairs(TABS) do
			local w = Font.getTextWidth(FONT16, Ext.tabLabel(i)) + 24
			if oldTouch.x >= x and oldTouch.x <= x + w then
				Ext.tab = i
				Ext.list:reset()
				Ext.version = -1
			end
			x = x + w + 8
		end
	elseif oldTouch.x and not touch.x and oldTouch.y >= 96 and oldTouch.y < EXT_TOP - 4 then
		local x = X0
		for _, g in ipairs(activeGroups()) do
			local w = Font.getTextWidth(FONT16, langChipLabel(g)) + 24
			if oldTouch.x >= x and oldTouch.x <= x + w then
				setLangGroup(g.id)
			end
			x = x + w + 8
		end
	end
	local tapped = Ext.list:input(oldPad, pad, oldTouch, touch)
	local row = Ext.list.rows[tapped or Ext.list.selected]
	if tapped and row and row.ext then
		extAction(row.ext)
	elseif pressed(pad, oldPad, SCE_CTRL_CROSS) and row and row.ext then
		extAction(row.ext)
	elseif pressed(pad, oldPad, SCE_CTRL_SQUARE) then
		Ext.tab = Ext.tab % #TABS + 1
		Ext.list:reset()
		Ext.version = -1
	elseif pressed(pad, oldPad, SCE_CTRL_TRIANGLE) then
		local q = TextInput(L().SEARCH_EXTENSIONS, Ext.query, 64)
		if q then
			Ext.query = q
			Ext.list:reset()
			Ext.version = -1
		end
	elseif pressed(pad, oldPad, SCE_CTRL_START) then
		-- next language group
		local groups = activeGroups()
		for i, g in ipairs(groups) do
			if g.id == Ext.lang then
				setLangGroup(groups[i % #groups + 1].id)
				break
			end
		end
	elseif pressed(pad, oldPad, SCE_CTRL_SELECT) then
		Ext.repoMenu()
	end
end

function Ext.tabLabel(i)
	if i == 1 then
		return L().INSTALLED .. " (" .. Extensions.countInstalled() .. ")"
	elseif i == 3 then
		local n = Extensions.countUpdates()
		return L().UPDATES_TAB .. (n > 0 and (" (" .. n .. ")") or "")
	end
	return L().AVAILABLE
end

function Ext.update()
	local v = Extensions.getVersion() .. "|" .. tostring(Settings.NSFW)
	if Ext.version ~= v then
		Ext.version = v
		buildExtRows()
	end
	Ext.list:update()
	Panel.set(Panels.EXTENSIONS or {})
end

local ORIGIN_LABEL = {keiyoushi = "keiyoushi", yuzono = "yuzono", cursed = "Cursed", noboru = "Lua", otakio = "Otakio", manual = "Manual"}

function Ext.draw()
	Ext.list:draw(function(i, row, y, sel)
		if row.header then
			UI.text(BONT16, X0 + 8, y + 8, row.header, COLOR_ACCENT)
			return
		end
		local e = row.ext
		if sel then
			UI.listHighlight(X0, y + 2, X1, y + row.h - 4, i == Ext.list.selected)
		end
		local cx = X0 + 40
		UI.roundRect(cx - 22, y + 13, cx + 22, y + 57, 12, COLOR_SURFACE2)
		UI.textCenter(BONT30, cx, y + 16, e.name:match("[%w]") or "?", COLOR_ACCENT)
		-- computed every frame so the dot follows the background checks live
		local status = SourceStatus.of(e.id, e.entry or e)
		SourceStatus.drawDot(cx + 20, y + 55, status)
		local tx = X0 + 76
		local name = UI.ellipsize(FONT20, e.name, 380)
		Font.print(FONT20, tx, y + 10, name, COLOR_FONT)
		local w = tx + Font.getTextWidth(FONT20, name) + 8
		if e.nsfw then
			w = w + UI.tag(w, y + 13, "18+", COLOR_DANGER, COLOR_WHITE) + 6
		end
		if e.error then
			UI.text(FONT16, tx, y + 40, "⚠ " .. e.error, COLOR_DANGER, 560)
		elseif e.installed and Extensions.isRemoved(e.id) then
			UI.text(FONT16, tx, y + 40, L().REMOVED_FROM_REPO or Language.English.OTAKIO.REMOVED_FROM_REPO, COLOR_WARNING, 560)
		else
			-- "Works" / "Unstable" / "Doesn't work" in the status color, then the details
			local label = L()["STATUS_" .. status:upper()] or status
			local color = (status == "ok" and COLOR_SUCCESS) or (status == "broken" and COLOR_DANGER) or COLOR_WARNING
			Font.print(FONT16, tx, y + 40, label, color)
			local sub = "  ·  " .. (e.langLabel or e.lang or "all") .. "  ·  v" .. tostring(e.version or "?") .. "  ·  " .. (ORIGIN_LABEL[e.origin] or e.origin or "")
			UI.text(FONT16, tx + Font.getTextWidth(FONT16, label), y + 40, sub, COLOR_SUBFONT, 560 - Font.getTextWidth(FONT16, label))
		end
		-- action button
		local label, bg, fg
		if Extensions.isInstalling(e.id) then
			UI.spinner(X1 - 60, y + 36, 9)
		else
			if not e.installed then
				label, bg, fg = L().INSTALL, COLOR_ACCENT, COLOR_ON_ACCENT
			elseif Extensions.hasUpdate(e.id) then
				label, bg, fg = L().UPDATE, COLOR_SUCCESS, COLOR_BLACK
			else
				label, bg, fg = L().INSTALLED_LABEL, COLOR_SURFACE2, COLOR_SUBFONT
			end
			local bw = Font.getTextWidth(BONT16, label) + 28
			UI.roundRect(X1 - 16 - bw, y + 20, X1 - 16, y + 52, 16, bg)
			UI.textCenter(BONT16, X1 - 16 - bw / 2, y + 26, label, fg)
		end
	end)
	if #Ext.list.rows == 0 then
		if Extensions.isRefreshing() then
			UI.spinner((X0 + X1) / 2, 300, 14)
		elseif not Extensions.hasRepos() then
			UI.emptyState((X0 + X1) / 2, 300, L().NO_REPOS, L().NO_REPOS_HINT, "(o_O)?")
		elseif Ext.tab == 1 then
			UI.emptyState((X0 + X1) / 2, 300, L().NO_EXTENSIONS, L().NO_EXTENSIONS_HINT, "(⊙_⊙)")
		elseif Ext.tab == 3 then
			UI.emptyState((X0 + X1) / 2, 300, L().ALL_UP_TO_DATE, nil, "(✧∀✧)/")
		else
			UI.emptyState((X0 + X1) / 2, 300, L().NOTHING_HERE, L().CHANGE_FILTERS_HINT)
		end
	end
	Graphics.fillRect(Config.RAIL_WIDTH, 960, 0, EXT_TOP - 4, COLOR_BACK)
	local sub = Ext.query ~= "" and ('"' .. Ext.query .. '"') or nil
	UI.header(L().EXTENSIONS, sub)
	if Extensions.isRefreshing() then
		UI.spinner(X1 - 12, 32, 7)
	end
	local x = X0
	for i = 1, #TABS do
		x = x + UI.chip(x, 60, Ext.tabLabel(i), Ext.tab == i) + 8
	end
	x = X0
	for _, g in ipairs(activeGroups()) do
		x = x + UI.chip(x, 98, langChipLabel(g), Ext.lang == g.id) + 8
	end
end

-------------------------------------------------------------------------------
-- Global search
-------------------------------------------------------------------------------

GlobalSearch = {}
local GS = {query = "", sections = {}, sel = 1, col = 1, y = 0, v = 0, active = false}
Screens.GLOBALSEARCH = GS

local SEC_H = 236
local THUMB_W, THUMB_H = 104, 156
local THUMB_GAP = 12

function GlobalSearch.prompt()
	local q = TextInput(Language[Settings.Language].APP.SEARCH, GS.query, 128)
	if q and q:gsub("%s", "") ~= "" then
		GlobalSearch.start(q)
	end
end

function GlobalSearch.stop()
	for _, s in ipairs(GS.sections) do
		ParserManager.remove(s.results)
		for _, m in ipairs(s.results) do
			Catalogs.freeMangaImage(m)
		end
	end
	GS.sections = {}
end

function GlobalSearch.start(query)
	GlobalSearch.stop()
	GS.query = query
	GS.sel, GS.col, GS.y, GS.v = 1, 1, 0, 0
	local pinned, others = {}, {}
	for _, p in ipairs(GetParserList()) do
		if p.searchManga then
			if Settings.FavouriteParsers[p.ID] then
				pinned[#pinned + 1] = p
			else
				others[#others + 1] = p
			end
		end
	end
	for _, list in ipairs({pinned, others}) do
		for _, p in ipairs(list) do
			local s = {parser = p, results = {}, scroll = 0}
			GS.sections[#GS.sections + 1] = s
			ParserManager.getMangaListAsync("Search", p, 1, s.results, query)
		end
	end
	Menu.setMode("GLOBALSEARCH")
end

function GS.onLeave()
	-- keep results while user opens details; free when leaving the screen
	if Details.getStatus() == "END" then
		GlobalSearch.stop()
	end
end

---Sections with results first (keeps order stable once loaded)
local function visibleSections()
	local done, pending = {}, {}
	for _, s in ipairs(GS.sections) do
		if #s.results > 0 then
			done[#done + 1] = s
		elseif ParserManager.check(s.results) then
			pending[#pending + 1] = s
		end
	end
	for _, s in ipairs(pending) do
		done[#done + 1] = s
	end
	return done
end

function GS.input(oldPad, pad, oldTouch, touch)
	local list = visibleSections()
	local s = list[GS.sel]
	if pressed(pad, oldPad, SCE_CTRL_UP) then
		GS.sel = max(1, GS.sel - 1)
		GS.col = 1
	elseif pressed(pad, oldPad, SCE_CTRL_DOWN) then
		GS.sel = min(#list, GS.sel + 1)
		GS.col = 1
	elseif pressed(pad, oldPad, SCE_CTRL_LEFT) then
		GS.col = max(1, GS.col - 1)
	elseif pressed(pad, oldPad, SCE_CTRL_RIGHT) and s then
		GS.col = min(#s.results, GS.col + 1)
	elseif pressed(pad, oldPad, SCE_CTRL_CROSS) and s and s.results[GS.col] then
		Details.setManga(s.results[GS.col])
	elseif pressed(pad, oldPad, SCE_CTRL_TRIANGLE) then
		GlobalSearch.prompt()
	elseif pressed(pad, oldPad, SCE_CTRL_CIRCLE) then
		GlobalSearch.stop()
		Menu.setMode("CATALOGS")
		return
	elseif pressed(pad, oldPad, SCE_CTRL_SQUARE) and s then
		-- open this source with the same search
		local parser = s.parser
		GlobalSearch.stop()
		Menu.setMode("CATALOGS")
		Catalogs.openParser(parser)
		CatalogModes.setSearch(GS.query)
		return
	end
	-- touch: tap a cover, drag to scroll
	if oldTouch.x and touch.x then
		GS.v = oldTouch.y - touch.y
		GS.dragged = GS.dragged or abs(touch.y - (GS.touchStartY or touch.y)) > 10
	elseif touch.x and not oldTouch.x then
		GS.touchStartY = touch.y
		GS.dragged = false
	elseif oldTouch.x and not touch.x and not GS.dragged then
		local si = floor((oldTouch.y - TOP + GS.y) / SEC_H) + 1
		local sec = list[si]
		if sec then
			local ci = floor((oldTouch.x - X0 + sec.scroll) / (THUMB_W + THUMB_GAP)) + 1
			if sec.results[ci] then
				GS.sel, GS.col = si, ci
				Details.setManga(sec.results[ci])
			end
		end
	end
end

function GS.update()
	local list = visibleSections()
	if GS.sel > #list then
		GS.sel = max(1, #list)
	end
	if abs(GS.v) > 1 then
		GS.y = GS.y + GS.v
		GS.v = GS.v / 1.12
	else
		GS.v = 0
		local target = (GS.sel - 1) * SEC_H - (524 - TOP - SEC_H) / 2
		GS.y = GS.y + (target - GS.y) / 4
	end
	GS.y = max(0, min(GS.y, max(0, #list * SEC_H - (524 - TOP))))
	for i, s in ipairs(list) do
		local target = i == GS.sel and max(0, (GS.col - 1) * (THUMB_W + THUMB_GAP) - (X1 - X0 - THUMB_W) / 2) or s.scroll
		s.scroll = s.scroll + (target - s.scroll) / 5
		-- load covers of visible sections
		local sy = TOP + (i - 1) * SEC_H - GS.y
		if sy > -SEC_H and sy < 544 then
			for j, m in ipairs(s.results) do
				local x = X0 + (j - 1) * (THUMB_W + THUMB_GAP) - s.scroll
				if x > X0 - THUMB_W * 2 and x < 960 + THUMB_W and not m.ImageDownload then
					Catalogs.loadMangaImage(m)
					m.ImageDownload = true
				end
			end
		end
	end
	Panel.set(Panels.GLOBALSEARCH or {})
end

function GS.draw()
	local list = visibleSections()
	for i, s in ipairs(list) do
		local sy = TOP + (i - 1) * SEC_H - GS.y
		if sy > -SEC_H and sy < 544 then
			local focused = i == GS.sel
			UI.text(BONT16, X0 + 4, sy + 4, s.parser.Name, focused and COLOR_ACCENT or COLOR_FONT, 500)
			local count = ParserManager.check(s.results) and "…" or tostring(#s.results)
			UI.textRight(FONT16, X1 - 8, sy + 4, count, COLOR_SUBFONT)
			if #s.results == 0 then
				UI.spinner(X0 + 40, sy + 110, 10)
			end
			for j, m in ipairs(s.results) do
				local x = X0 + (j - 1) * (THUMB_W + THUMB_GAP) - s.scroll
				if x > X0 - THUMB_W - 20 and x < 960 then
					local y = sy + 30
					if m.Image and m.Image.e then
						DrawDetailsManga(x + THUMB_W / 2, y + THUMB_H / 2, m, THUMB_H / MANGA_HEIGHT)
					else
						UI.shimmer(x, y, x + THUMB_W, y + THUMB_H)
					end
					UI.text(FONT16, x, y + THUMB_H + 4, m.Name, COLOR_FONT, THUMB_W)
					if Database.check(m) then
						UI.tag(x + 4, y + 4, "♥", COLOR_ACCENT, COLOR_ON_ACCENT)
					end
					if focused and j == GS.col then
						UI.focusRing(x, y, x + THUMB_W, y + THUMB_H)
					end
				end
			end
		end
	end
	if #GS.sections == 0 then
		UI.emptyState((X0 + X1) / 2, 290, L().NO_SOURCES, L().NO_SOURCES_HINT)
	elseif #list == 0 then
		UI.emptyState((X0 + X1) / 2, 290, L().NO_RESULTS, nil, "(╥﹏╥)")
	end
	Graphics.fillRect(Config.RAIL_WIDTH, 960, 0, TOP - 4, COLOR_BACK)
	UI.header(L().GLOBAL_SEARCH, '"' .. GS.query .. '"')
	local pendingCount = 0
	for _, s in ipairs(GS.sections) do
		if ParserManager.check(s.results) then
			pendingCount = pendingCount + 1
		end
	end
	if pendingCount > 0 then
		UI.textRight(FONT16, X1 - 30, 22, string.format(L().SEARCHING_N, #GS.sections - pendingCount, #GS.sections), COLOR_SUBFONT)
		UI.spinner(X1 - 12, 32, 7)
	end
end

-------------------------------------------------------------------------------
-- panels
-------------------------------------------------------------------------------

function Screens.genPanels()
	local P = Language[Settings.Language].PANEL
	local O = Language[Settings.Language].OTAKIO
	Panels.UPDATES = {"L\\R", "Cross", "Square", "Triangle", "Start", "Select",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.READ, Square = O.DOWNLOAD, Triangle = P.UPDATE, Start = O.DETAILS, Select = O.CLEAR}
	Panels.HISTORY = {"L\\R", "Cross", "Square", "Start",
		["L\\R"] = P.CHANGE_SECTION, Cross = O.RESUME, Square = P.DELETE, Start = O.DETAILS}
	Panels.EXTENSIONS = {"L\\R", "Cross", "Square", "Triangle", "Start", "Select",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.SELECT, Square = O.TAB, Triangle = P.SEARCH, Start = O.LANGUAGE, Select = O.REPOSITORIES}
	Panels.GLOBALSEARCH = {"Cross", "Square", "Triangle", "Circle",
		Cross = P.SELECT, Square = O.OPEN_IN_SOURCE, Triangle = P.SEARCH, Circle = P.BACK}
end
