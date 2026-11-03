---Updates feed (Mihon "Updates" tab): new chapters found while refreshing the library.
Updates = {}

local PATH = Config.DATA .. "updates.dat"
local MAX_ENTRIES = 400

local entries = {}
local version = 0
local unseen = 0

function Updates.load()
	local data = FS.loadTable(PATH) or {}
	entries = data.entries or {}
	unseen = data.unseen or 0
	version = version + 1
end

local function save()
	FS.saveTable(PATH, {entries = entries, unseen = unseen})
end

function Updates.getVersion()
	return version
end

function Updates.getList()
	return entries
end

function Updates.getUnseen()
	return unseen
end

function Updates.markSeen()
	if unseen ~= 0 then
		unseen = 0
		save()
	end
end

---Compares chapter lists before/after a refresh and records new chapters
---@param manga table library manga
---@param oldChapters table chapters stored before refresh
---@param newChapters table chapters fetched now
---@return table list of new chapter objects
function Updates.registerRefresh(manga, oldChapters, newChapters)
	local known = {}
	for i = 1, #oldChapters do
		known[oldChapters[i].Link] = true
	end
	local fresh = {}
	-- first refresh of a manga: don't flood the feed with its whole back catalogue
	if #oldChapters == 0 then
		return fresh
	end
	local now = Clock.now()
	for i = 1, #newChapters do
		local c = newChapters[i]
		if not known[c.Link] then
			fresh[#fresh + 1] = c
			table.insert(entries, 1, {
				MangaKey = Database.getKey(manga),
				MangaName = manga.Name,
				ParserID = manga.ParserID,
				ChapterName = c.Name,
				ChapterLink = c.Link,
				Date = now
			})
		end
	end
	if #fresh > 0 then
		manga.LastUpdate = now
		unseen = unseen + #fresh
		while #entries > MAX_ENTRIES do
			entries[#entries] = nil
		end
		save()
		version = version + 1
		if Settings.AutoDownloadNew and Database.check(manga) then
			for _, c in ipairs(fresh) do
				if not ChapterSaver.check(c) and not ChapterSaver.is_downloading(c) then
					ChapterSaver.downloadChapter(c, true)
				end
			end
		end
	end
	return fresh
end

function Updates.remove(index)
	table.remove(entries, index)
	save()
	version = version + 1
end

function Updates.clear()
	entries = {}
	unseen = 0
	save()
	version = version + 1
end

---Builds a chapter object usable by the reader/downloader from a feed entry
---@return table|nil chapter, table|nil chapterList, integer|nil index
function Updates.resolve(entry)
	local manga = Database.getByKey(entry.MangaKey) or Cache.getMangaByKey(entry.MangaKey)
	if not manga then
		return nil
	end
	local chapters = Cache.loadChapters(manga, true)
	for i = 1, #chapters do
		if chapters[i].Link == entry.ChapterLink then
			return chapters[i], chapters, i, manga
		end
	end
	return {Name = entry.ChapterName, Link = entry.ChapterLink, Pages = {}, Manga = manga}, nil, nil, manga
end
