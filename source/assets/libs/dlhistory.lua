---Download history: finished, failed and canceled chapter downloads (Downloads tab > History).
---Only a list: clearing it never touches the downloaded chapters.
DownloadHistory = {}

local PATH = "ux0:data/otakio/download_history.dat"
local MAX = 300

local entries = nil -- newest first: {t, manga, chapter, parser, link, status = "ok" | "failed" | "canceled", pages}

local function load()
	if not entries then
		local t = FS.loadTable(PATH)
		entries = type(t) == "table" and t or {}
	end
	return entries
end

local function save()
	FS.saveTable(PATH, entries or {})
end

local version = 0

---@param task table ChapterSaver task (MangaName, ChapterName, Manga, page_count)
---@param status string "ok" | "failed" | "canceled"
function DownloadHistory.add(task, status)
	if not task or task.Type ~= "Download" then
		return
	end
	local list = load()
	local manga = task.Manga or {}
	table.insert(list, 1, {
		t = Clock.now(),
		manga = task.MangaName or manga.Name or "?",
		chapter = task.ChapterName or "?",
		parser = manga.ParserID,
		link = manga.Link,
		status = status,
		pages = task.page_count
	})
	while #list > MAX do
		table.remove(list)
	end
	version = version + 1
	save()
end

function DownloadHistory.list()
	return load()
end

function DownloadHistory.count()
	return #load()
end

---Removes one entry (index in DownloadHistory.list())
function DownloadHistory.remove(i)
	local list = load()
	if list[i] then
		table.remove(list, i)
		version = version + 1
		save()
	end
end

---Empties the history; downloaded chapters stay where they are
function DownloadHistory.clear()
	entries = {}
	version = version + 1
	save()
end

---Changes whenever the list changes (screens cache their rows on it)
function DownloadHistory.version()
	return version
end

---The manga of an entry, when it is still known to the app (library or cache)
function DownloadHistory.findManga(entry)
	if not entry or not entry.parser or not entry.link then
		return nil
	end
	for _, m in pairs(Cache.getManga()) do
		if m.ParserID == entry.parser and m.Link == entry.link then
			return m
		end
	end
	return nil
end
