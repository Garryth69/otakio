---Library (Mihon-style): categories, filters, sorting and a versioned cache so the
---grid never re-sorts the whole list every frame like the old implementation did.
Database = {}

local SAVE_PATH = Config.DATA .. "save.dat"

local database = {}
local version = 0
local listCache = {key = nil, list = {}}

local doesDirExist = System.doesDirExist

local function getKey(manga)
	return (AsciiKey((manga.ParserID .. manga.Link):gsub("%p", "")))
end
Database.getKey = getKey

local function touch()
	version = version + 1
end

function Database.getVersion()
	return version
end

---Marks library as changed (unread counters, covers...) so screens refresh their lists
Database.touch = touch

-------------------------------------------------------------------------------
-- categories
-------------------------------------------------------------------------------

---@return table list of {id, name}
function Database.getCategories()
	Settings.Categories = Settings.Categories or {}
	return Settings.Categories
end

function Database.addCategory(name)
	local cats = Database.getCategories()
	local maxId = 0
	for _, c in ipairs(cats) do
		if c.id > maxId then
			maxId = c.id
		end
	end
	cats[#cats + 1] = {id = maxId + 1, name = name}
	Settings.save()
	touch()
	return maxId + 1
end

function Database.renameCategory(id, name)
	for _, c in ipairs(Database.getCategories()) do
		if c.id == id then
			c.name = name
		end
	end
	Settings.save()
	touch()
end

function Database.removeCategory(id)
	local cats = Database.getCategories()
	for i, c in ipairs(cats) do
		if c.id == id then
			table.remove(cats, i)
			break
		end
	end
	for _, m in ipairs(database) do
		if m.Categories then
			m.Categories[id] = nil
		end
	end
	Settings.save()
	Database.save()
end

function Database.moveCategory(id, delta)
	local cats = Database.getCategories()
	for i, c in ipairs(cats) do
		if c.id == id then
			local j = i + delta
			if j >= 1 and j <= #cats then
				cats[i], cats[j] = cats[j], cats[i]
				Settings.save()
				touch()
			end
			return
		end
	end
end

---@param manga table
---@param ids table set {[id]=true}
function Database.setMangaCategories(manga, ids)
	local key = getKey(manga)
	local idx = database[key]
	if idx then
		database[idx].Categories = ids
		Database.save()
	end
end

function Database.getMangaCategories(manga)
	local idx = database[getKey(manga)]
	return idx and database[idx].Categories or {}
end

-------------------------------------------------------------------------------
-- queries
-------------------------------------------------------------------------------

local function unreadOf(m)
	return m.Counter or 0
end

local SORTERS = {
	["A-Z"] = function(a, b)
		return a.Name:lower() < b.Name:lower()
	end,
	["Z-A"] = function(a, b)
		return a.Name:lower() > b.Name:lower()
	end,
	["Unread"] = function(a, b)
		if unreadOf(a) ~= unreadOf(b) then
			return unreadOf(a) > unreadOf(b)
		end
		return a.Name:lower() < b.Name:lower()
	end,
	["Last read"] = function(a, b)
		local ta, tb = Cache.getLastRead(a) or 0, Cache.getLastRead(b) or 0
		if ta ~= tb then
			return ta > tb
		end
		return a.Name:lower() < b.Name:lower()
	end,
	["Latest chapter"] = function(a, b)
		local ta, tb = a.LastUpdate or 0, b.LastUpdate or 0
		if ta ~= tb then
			return ta > tb
		end
		return a.Name:lower() < b.Name:lower()
	end
}

Database.SORT_MODES = {"Date added", "A-Z", "Z-A", "Unread", "Last read", "Latest chapter"}
Database.FILTERS = {"All", "Unread", "Downloaded", "Completed"}

local function hasDownloads(m)
	return ChapterSaver.hasDownloadsForManga and ChapterSaver.hasDownloadsForManga(m) or false
end

---@param category integer|nil  nil/0 = all
---@return table
---Gets Library manga list (cached, filtered, sorted)
function Database.getMangaList(category)
	category = category or 0
	local sortMode = Settings.LibrarySorting or "Date added"
	local filter = Settings.LibraryFilter or "All"
	local cacheKey = version .. "|" .. category .. "|" .. sortMode .. "|" .. filter .. "|" .. Cache.getHistoryVersion()
	if listCache.key == cacheKey then
		return listCache.list
	end
	local mangaList = {}
	local uma0_flag = doesDirExist("uma0:data/otakio")
	for i = 1, #database do
		local m = database[i]
		if m.Location ~= "uma0" or uma0_flag then
			local ok = category == 0 or (m.Categories and m.Categories[category])
			if ok and filter ~= "All" then
				if filter == "Unread" then
					ok = unreadOf(m) > 0
				elseif filter == "Downloaded" then
					ok = hasDownloads(m)
				elseif filter == "Completed" then
					ok = m.Counter == 0
				end
			end
			if ok then
				mangaList[#mangaList + 1] = m
			end
		end
	end
	local sorter = SORTERS[sortMode]
	if sorter then
		table.sort(mangaList, sorter)
	end
	listCache.key = cacheKey
	listCache.list = mangaList
	return mangaList
end

---All library manga, unfiltered (for updates, backup...)
function Database.getAll()
	local t = {}
	for i = 1, #database do
		t[i] = database[i]
	end
	return t
end

function Database.count()
	return #database
end

---@param manga table
---Adds `manga` to database
function Database.addManga(manga, categories)
	local key = getKey(manga)
	if not database[key] then
		manga.DateAdded = manga.DateAdded or Clock.now()
		manga.Categories = categories or manga.Categories or {}
		database[#database + 1] = manga
		database[key] = #database
		Database.save()
	end
end

---@param manga table
---@return boolean
---Checks if `manga` is in library
function Database.check(manga)
	return database[getKey(manga)] ~= nil
end

---@param key string
---@return boolean
function Database.checkByKey(key)
	return database[key] ~= nil
end

---@param key string
---@return table|nil
function Database.getByKey(key)
	local idx = database[key]
	return idx and database[idx] or nil
end

---@param manga table
---Removes `manga` from library
function Database.removeManga(manga)
	local key = getKey(manga)
	if database[key] then
		local n = database[key]
		table.remove(database, n)
		database[key] = nil
		for i = n, #database do
			local k = getKey(database[i])
			database[k] = database[k] - 1
		end
		Database.save()
	end
end

local KEEP = {"Data", "Categories", "DateAdded", "Counter", "LastUpdate", "Location"}

---Saves library to `save.dat`
function Database.save()
	local mangaTable = {}
	for k = 1, #database do
		local m = database[k]
		local key = getKey(m)
		mangaTable[k] = CreateManga(m.Name, m.Link, m.ImageLink, m.ParserID, m.RawLink, m.BrowserLink)
		for _, field in ipairs(KEEP) do
			mangaTable[k][field] = m[field]
		end
		mangaTable[k].Path = "cache/" .. key .. "/cover.image"
		mangaTable[k].Location = m.Location or "ux0"
		mangaTable[key] = k
	end
	FS.saveTable(SAVE_PATH, mangaTable)
	touch()
end

---Loads library from `save.dat`
function Database.load()
	database = FS.loadTable(SAVE_PATH) or {}
	-- rebuild index (also repairs files written by older versions)
	local clean = {}
	for i = 1, #database do
		local m = database[i]
		if type(m) == "table" and m.ParserID and m.Link then
			m.Categories = m.Categories or {}
			clean[#clean + 1] = m
			clean[getKey(m)] = #clean
		end
	end
	database = clean
	touch()
end

---Resets library
function Database.clear()
	database = {}
	Database.save()
end
