Cache = {}

local CACHE_INFO_PATH = "ux0:data/otakio/cache/info.txt"

local data = {}
local history = {}
local bookmarks = {}
local cachedHistory = {}

local writeFile = System.writeFile
local closeFile = System.closeFile
local deleteFile = System.deleteFile
local openFile = System.openFile
local readFile = System.readFile
local sizeFile = System.sizeFile
local doesFileExist = System.doesFileExist
local doesDirExist = System.doesDirExist
local createDirectory = System.createDirectory
local listDirectory = System.listDirectory
local removeDirectory = RemoveDirectory

local is_history_updated = false
local historyTime = {}
local historyVersion = 0
local HISTORY_TIME_PATH = "ux0:data/otakio/cache/history_time.dat"

local function bumpHistory()
	historyVersion = historyVersion + 1
end

---@return integer
function Cache.getHistoryVersion()
	return historyVersion
end

---@param manga table
---@return number|nil unix time of last reading/opening
function Cache.getLastRead(manga)
	return historyTime[(manga.ParserID .. manga.Link):gsub("%p", "")]
end

local function saveHistoryTime()
	FS.saveTable(HISTORY_TIME_PATH, historyTime)
end

---@param manga table
---@return string
---Gives key for a given `manga`
local function getKey(manga)
	return (AsciiKey((manga.ParserID .. manga.Link):gsub("%p", "")))
end

---@param manga table
---@return string
---Gives key for a given `manga`
Cache.getKey = getKey

---@return table
---Returns all manga in cache
function Cache.getManga()
	local mangaList = {}
	for key, value in pairs(data) do
		mangaList[key] = value
	end
	return mangaList
end

---@param manga table
---@param chapters table | nil
---Adds `Manga` to cache if it is not in cache
function Cache.addManga(manga, chapters)
	local key = getKey(manga)
	if not data[key] then
		data[key] = manga
		manga.Path = "cache/" .. key .. "/cover.image"
		if not doesDirExist("ux0:data/otakio/cache/" .. key) then
			createDirectory("ux0:data/otakio/cache/" .. key)
		end
		if doesFileExist("ux0:data/otakio/cache/" .. key .. "/cover.image") then
			deleteFile("ux0:data/otakio/cache/" .. key .. "/cover.image")
		end
		if chapters then
			Cache.saveChapters(manga, chapters)
		end
		if manga.ParserID ~= "IMPORTED" then
			Threads.insertTask(
				tostring(manga) .. "coverDownload",
				{
					Type = "FileDownload",
					Path = "cache/" .. key .. "/cover.image",
					Link = manga.ImageLink
				}
			)
		end
		Cache.save()
	end
end

---@param manga table
---Removes given `manga` from cache
function Cache.removeManga(manga)
	local mangaKey = getKey(manga)
	if data[mangaKey] then
		data[mangaKey] = nil
		manga.Path = nil
		removeDirectory("ux0:data/otakio/cache/" .. mangaKey)
		Cache.save()
	end
end

---@param chapter table
---@param mode integer | boolean
---Set's bookmark for given `Chapter`
function Cache.setBookmark(chapter, mode)
	if Settings.Incognito then
		return
	end
	Cache.addManga(chapter.Manga)
	local mangaKey = getKey(chapter.Manga)
	local chapterKey = chapter.Link:gsub("%p", "")
	if not bookmarks[mangaKey] then
		bookmarks[mangaKey] = {}
	end
	bookmarks[mangaKey][chapterKey] = mode
	bookmarks[mangaKey].LatestBookmark = chapterKey
	historyTime[mangaKey] = Clock.now()
	bumpHistory()
	if doesFileExist("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat") then
		deleteFile("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat")
	end
	local fh = openFile("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat", FCREATE)
	local serializedBookmarks = "return " .. table.serialize(bookmarks[mangaKey], true)
	writeFile(fh, serializedBookmarks, #serializedBookmarks)
	closeFile(fh)
end

---Marks a list of chapters as read (`true`) or unread (`nil`) with a single disk write
---@param chapters table
---@param mode boolean|nil
function Cache.markChapters(chapters, mode)
	if #chapters == 0 then
		return
	end
	local manga = chapters[1].Manga
	Cache.addManga(manga)
	local mangaKey = getKey(manga)
	bookmarks[mangaKey] = bookmarks[mangaKey] or {}
	for i = 1, #chapters do
		bookmarks[mangaKey][chapters[i].Link:gsub("%p", "")] = mode or nil
	end
	if mode then
		bookmarks[mangaKey].LatestBookmark = chapters[#chapters].Link:gsub("%p", "")
	end
	Cache.saveBookmarks(manga)
	bumpHistory()
end

---@param key string
---@return table|nil cached manga
function Cache.getMangaByKey(key)
	return data[key]
end

---@param chapter table
---@return nil | boolean | number
---Gives latest readed page for `Chapter`
---`number` latest readed page, `true` if manga readed full, `nil` if no bookmark on this `Chapter`
function Cache.getBookmark(chapter)
	local mangaKey = getKey(chapter.Manga)
	local chapterKey = chapter.Link:gsub("%p", "")
	return bookmarks[mangaKey] and bookmarks[mangaKey][chapterKey]
end

---@param manga table
---@return string
---Gives key for latest closed chapter
function Cache.getLatestBookmark(manga)
	local mangaKey = getKey(manga)
	return bookmarks[mangaKey] and bookmarks[mangaKey].LatestBookmark
end

function Cache.getBookmarkKey(chapter)
	return chapter.Link:gsub("%p", "")
end

---@param manga table
---Saves all bookmarks related to given `manga`
function Cache.saveBookmarks(manga)
	local mangaKey = getKey(manga)
	if doesDirExist("ux0:data/otakio/cache/" .. mangaKey) then
		if doesFileExist("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat") then
			deleteFile("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat")
		end
		local fh = openFile("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat", FCREATE)
		local serializedBookmarks = "return " .. table.serialize(bookmarks[mangaKey], true)
		writeFile(fh, serializedBookmarks, #serializedBookmarks)
		closeFile(fh)
	end
end

---@param manga table
---Loads all bookmarks in cache for given `manga`
function Cache.loadBookmarks(manga)
	local mangaKey = getKey(manga)
	if doesFileExist("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat") then
		local fh = openFile("ux0:data/otakio/cache/" .. mangaKey .. "/bookmarks.dat", FREAD)
		local loadBookmarksFunction = load(readFile(fh, sizeFile(fh)))
		closeFile(fh)
		if loadBookmarksFunction then
			bookmarks[mangaKey] = loadBookmarksFunction() or {}
		end
	end
end

---@param manga table
---Checks if bookmarks is already loaded (in cache)
function Cache.BookmarksLoaded(manga)
	local mangaKey = getKey(manga)
	return bookmarks[mangaKey] ~= nil
end

---@param manga table
---Clears bookmarks for given `manga`
function Cache.clearBookmarks(manga)
	local mangaKey = getKey(manga)
	bookmarks[mangaKey] = {}
	Cache.saveBookmarks(manga)
	bumpHistory()
end

---@param manga table
---Creates/Updates History record
function Cache.makeHistory(manga)
	if Settings.Incognito then
		return
	end
	local key = getKey(manga)
	historyTime[key] = Clock.now()
	saveHistoryTime()
	bumpHistory()
	for i = 1, #history do
		if history[i] == key then
			if i == 1 then
				return
			end
			table.remove(history, i)
			break
		end
	end
	table.insert(history, 1, key)
	Cache.saveHistory()
	is_history_updated = true
end

---@param Manga table
---Removes given `Manga` from history
function Cache.removeHistory(Manga)
	local key = getKey(Manga)
	for i = 1, #history do
		if history[i] == key then
			table.remove(history, i)
			historyTime[key] = nil
			saveHistoryTime()
			Cache.saveHistory()
			is_history_updated = true
			bumpHistory()
			break
		end
	end
end

---@return table
---Gives list of all History records
function Cache.getHistory()
	if is_history_updated then
		local newHistoryList = {}
		local uma0Flag = doesDirExist("uma0:data/otakio")
		for i = 1, #history do
			local file = history[i]
			if data[file] then
				if data[file].Location ~= "uma0" or uma0Flag then
					newHistoryList[#newHistoryList + 1] = data[file]
				end
			end
		end
		is_history_updated = false
		cachedHistory = newHistoryList
	end
	return cachedHistory
end

---Adds history entries from a backup (newest first) without touching what is already there
---@param keys table manga keys
---@param times table|nil key -> unix time of last reading
function Cache.mergeHistory(keys, times)
	local present = {}
	for i = 1, #history do
		present[history[i]] = true
	end
	for _, key in ipairs(keys or {}) do
		if type(key) == "string" and not present[key] then
			history[#history + 1] = key
			present[key] = true
		end
		if times and times[key] and not historyTime[key] then
			historyTime[key] = times[key]
		end
	end
	is_history_updated = true
	bumpHistory()
	saveHistoryTime()
	Cache.saveHistory()
end

---Saves all History records
function Cache.saveHistory()
	if doesFileExist("ux0:data/otakio/cache/history.dat") then
		deleteFile("ux0:data/otakio/cache/history.dat")
	end
	local fh = openFile("ux0:data/otakio/cache/history.dat", FCREATE)
	local serializedHistory = "return " .. table.serialize(history, true)
	writeFile(fh, serializedHistory, #serializedHistory)
	closeFile(fh)
end

---Loads History records from `history.dat` file
function Cache.loadHistory()
	if doesFileExist("ux0:data/otakio/cache/history.dat") then
		local fh = openFile("ux0:data/otakio/cache/history.dat", FREAD)
		local loadHistoryFunction = load(readFile(fh, sizeFile(fh)))
		closeFile(fh)
		if loadHistoryFunction then
			history = loadHistoryFunction() or {}
		end
	end
	historyTime = FS.loadTable(HISTORY_TIME_PATH) or {}
	bumpHistory()
	Cache.saveHistory()
	is_history_updated = true
end

---@param manga table
---@return boolean
---Gives is manga in history
function Cache.inHistory(manga)
	return history[getKey(manga)] ~= nil
end

---@param manga table
---Checks if `manga` is cached
function Cache.isCached(manga)
	return manga and data[getKey(manga)] ~= nil or false
end

---@param manga table
---@param chapters table
---Updates `chapter` List for given `manga`
-- chapter lists waiting to be written (key -> chapters): saving thousands of chapters takes long on the Vita, so it
-- runs in the background, spread over frames; loadChapters serves these until the file is written
local pendingChapters = {}

local function writeChapters(key, chapters)
	local path = "ux0:data/otakio/cache/" .. key .. "/chapters.dat"
	local chaptersList = {}
	for i = 1, #chapters do
		local copy = {}
		for k, v in pairs(chapters[i]) do
			copy[k] = k == "Manga" and "10101010101010" or v
		end
		chaptersList[i] = copy
		if i % 300 == 0 and coroutine.running() then
			coroutine.yield(false)
		end
	end
	chaptersList.Description = chapters.Description or ""
	local serializedChaptersList = "return " .. table.serialize(chaptersList, true)
	if not doesDirExist("ux0:data/otakio/cache/" .. key) then
		return
	end
	if doesFileExist(path) then
		deleteFile(path)
	end
	local fh = openFile(path, FCREATE)
	writeFile(fh, serializedChaptersList, #serializedChaptersList)
	closeFile(fh)
end

function Cache.saveChapters(manga, chapters)
	local key = getKey(manga)
	if not key then
		return
	end
	pendingChapters[key] = chapters
	local job = "chapters:" .. key
	if Threads.check(job) then
		return -- the queued job writes the latest list when it runs
	end
	Threads.addTask(job, {
		Type = "function",
		Priority = Threads.BACKGROUND,
		OnComplete = function()
			local list = pendingChapters[key]
			if not list then
				return
			end
			local ok, err = pcall(writeChapters, key, list)
			if not ok then
				Console.error("saveChapters: " .. tostring(err))
			end
			if pendingChapters[key] == list then
				pendingChapters[key] = nil
			end
		end
	})
end

---Writes every pending chapter list now (before quitting, backups or clearing the cache)
function Cache.flushChapters()
	for key, list in pairs(pendingChapters) do
		pcall(writeChapters, key, list)
		pendingChapters[key] = nil
	end
end

---@param manga table
---@return table
---Gives chapter list for given `manga`
local function hideOffline(list, skipHiding)
	if skipHiding or not Settings.HideInOffline then
		list.Description = list.Description or ""
		return list
	end
	local t = {}
	for i = 1, #list do
		local chapter = list[i]
		t[#t + 1] = ChapterSaver.check(chapter) and chapter or nil
	end
	t.Description = list.Description or ""
	return t
end

function Cache.loadChapters(manga, skipHiding)
	local key = getKey(manga)
	if data[key] and pendingChapters[key] then
		-- not written yet: same list the app just saved
		local list = {Description = pendingChapters[key].Description}
		for i, chapter in ipairs(pendingChapters[key]) do
			list[i] = chapter
		end
		return hideOffline(list, skipHiding)
	end
	if data[key] then
		if doesFileExist("ux0:data/otakio/cache/" .. key .. "/chapters.dat") then
			local fh = openFile("ux0:data/otakio/cache/" .. key .. "/chapters.dat", FREAD)
			local success, newChaptersList =
				pcall(
				function()
					local content = readFile(fh, sizeFile(fh))
					return load(content:gsub('"10101010101010"', "..."))(data[key])
				end
			)
			closeFile(fh)
			if success then
				if skipHiding then
					newChaptersList.Description = newChaptersList.Description or ""
					return newChaptersList
				end
				if Settings.HideInOffline then
					local t = {}
					for i = 1, #newChaptersList do
						local chapter = newChaptersList[i]
						t[#t + 1] = ChapterSaver.check(chapter) and chapter or nil
					end
					t.Description = newChaptersList.Description or ""
					return t
				else
					newChaptersList.Description = newChaptersList.Description or ""
					return newChaptersList
				end
			else
				Console.error(newChaptersList)
			end
		end
	end
	return {}
end

---Loads Cache
function Cache.load()
	data = {}
	if doesFileExist(CACHE_INFO_PATH) then
		local fh = openFile(CACHE_INFO_PATH, FREAD)
		local loadCacheFunction = load(readFile(fh, sizeFile(fh)))
		if loadCacheFunction then
			local newData = loadCacheFunction() or {}
			local count = 0
			for _ in pairs(newData) do
				count = count + 1
			end
			local i = 1
			for k, v in pairs(newData) do
				local path = "ux0:data/otakio/cache/" .. k
				coroutine.yield("Cache: Checking " .. path, i / count)
				if not Settings.SkipCacheChapterChecking then
					if doesDirExist(path) then
						if doesFileExist("ux0:data/otakio/" .. v.Path) then
							coroutine.yield("Cache: Checking ux0:data/otakio/" .. v.Path, i / count)
							local imageSize = System.getPictureResolution("ux0:data/otakio/" .. v.Path)
							if not imageSize or imageSize <= 0 then
								deleteFile("ux0:data/otakio/" .. v.Path)
							end
						end
						data[k] = v
					else
						Notifications.push("cache_error\n" .. k)
					end
				else
					data[k] = v
				end
				i = i + 1
			end
		end
		closeFile(fh)
	end
	Cache.save()
end

---Saves Cache
function Cache.save()
	if doesFileExist(CACHE_INFO_PATH) then
		deleteFile(CACHE_INFO_PATH)
	end
	local fh = openFile(CACHE_INFO_PATH, FCREATE)
	local saveData = {}
	for k, v in pairs(data) do
		saveData[k] = CreateManga(v.Name, v.Link, v.ImageLink, v.ParserID, v.RawLink)
		saveData[k].Data = v.Data
		saveData[k].Path = "cache/" .. k .. "/cover.image"
		saveData[k].Location = v.Location or "ux0"
	end
	local serializedData = "return " .. table.serialize(saveData, true)
	writeFile(fh, serializedData, #serializedData)
	closeFile(fh)
end

---@param mode string | '"notlibrary"' | '"all"'
---Clears cache in specific `mode`
function Cache.clear(mode)
	mode = mode or "notlibrary"
	if mode == "notlibrary" then
		local d = listDirectory("ux0:data/otakio/cache") or {}
		for i = 1, #d do
			local f = d[i]
			if not Database.checkByKey(f.name) and f.directory then
				removeDirectory("ux0:data/otakio/cache/" .. f.name)
				data[f.name] = nil
			end
		end
		local newHistory = {}
		for i = 1, #history do
			if data[history[i]] then
				newHistory[#newHistory + 1] = history[i]
			end
		end
		history = newHistory
	elseif mode == "all" then
		local directory = listDirectory("ux0:data/otakio/cache") or {}
		for i = 1, #directory do
			local file = directory[i]
			if not file.name:find("^IMPORTED") or not Database.checkByKey(file.name) then
				removeDirectory("ux0:data/otakio/cache/" .. file.name)
				data[file.name] = nil
			end
		end
		local newHistory = {}
		for i = 1, #history do
			if data[history[i]] then
				newHistory[#newHistory + 1] = history[i]
			end
		end
		history = newHistory
		bookmarks = {}
	end
	Cache.saveHistory()
	is_history_updated = true
	Cache.save()
end
