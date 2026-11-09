---Backup / restore (Mihon-like) and one-tap migration from NOBORU.
Backup = {}

local DIR = Config.DATA .. "backups/"
local CACHE = Config.DATA .. "cache/"

local function L()
	return Language[Settings.Language].OTAKIO
end

local LIB_FIELDS = {"Name", "Link", "ImageLink", "ParserID", "RawLink", "BrowserLink", "Data", "Categories", "DateAdded", "Counter", "LastUpdate"}

local function copyManga(m)
	local t = {}
	for _, f in ipairs(LIB_FIELDS) do
		t[f] = m[f]
	end
	return t
end

local AUTO_PREFIX = "otakio_auto_" -- backups made before an app update
local AUTO_KEEP = 3

---Keeps only the newest AUTO_KEEP automatic backups (the user's own backups are never removed)
local function pruneAuto()
	local auto = {}
	for _, f in ipairs(FS.list(DIR)) do
		if not f.directory and f.name:find("^" .. AUTO_PREFIX) and f.name:find("%.otk$") then
			auto[#auto + 1] = f.name
		end
	end
	table.sort(auto, function(a, b)
		return a > b
	end)
	for i = AUTO_KEEP + 1, #auto do
		FS.delete(DIR .. auto[i])
	end
end

---Creates ux0:data/otakio/backups/otakio_YYYY-MM-DD_HHMM.otk
---opts.auto: before an app update, silent, named otakio_auto_YYYY-MM-DD_HHMMSS_from-<version>.otk (the last 3 are kept)
---@return string|nil path of the backup, nil if it couldn't be written
function Backup.create(opts)
	local auto = opts and opts.auto
	local data = {
		format = 1,
		app = Config.VERSION_NAME,
		date = Clock.now(),
		library = {},
		bookmarks = {},
		history = FS.loadTable(CACHE .. "history.dat") or {},
		historyTime = FS.loadTable(CACHE .. "history_time.dat") or {},
		settings = {},
		extensions = {},
		repos = {}
	}
	for _, m in ipairs(Database.getAll()) do
		local key = Database.getKey(m)
		data.library[#data.library + 1] = copyManga(m)
		local b = FS.loadTable(CACHE .. key .. "/bookmarks.dat")
		if b then
			data.bookmarks[key] = b
		end
	end
	for k, v in pairs(Settings) do
		if type(v) ~= "function" and k ~= "Version" then
			data.settings[k] = v
		end
	end
	for id, meta in pairs(Extensions.getInstalled()) do
		data.extensions[#data.extensions + 1] = {id = id, name = meta.name, version = meta.version}
	end
	for _, r in ipairs(Extensions.getRepos()) do
		if not r.builtin then
			data.repos[#data.repos + 1] = r.url
		end
	end
	FS.mkdir(DIR)
	local name = "otakio_" .. Clock.date("%Y-%m-%d_%H%M") .. ".otk"
	if auto then
		name = AUTO_PREFIX .. Clock.date("%Y-%m-%d_%H%M%S") .. "_from-" .. Config.VERSION_NAME .. ".otk"
	end
	local ok = FS.saveTable(DIR .. name, data)
	if auto then
		if ok then
			pruneAuto()
		end
	elseif ok then
		Notifications.push(string.format(L().BACKUP_CREATED, "ux0:data/otakio/backups/" .. name), 2000)
	else
		Notifications.push(L().BACKUP_FAILED)
	end
	return ok and (DIR .. name) or nil
end

local function restore(path)
	local data = FS.loadTable(path)
	if not data or not data.library then
		Notifications.push(L().BACKUP_INVALID)
		return
	end
	local added = 0
	for _, m in ipairs(data.library) do
		local manga = CreateManga(m.Name, m.Link, m.ImageLink or "", m.ParserID, m.RawLink, m.BrowserLink)
		if manga then
			for _, f in ipairs(LIB_FIELDS) do
				if m[f] ~= nil then
					manga[f] = m[f]
				end
			end
			if not Database.check(manga) then
				Database.addManga(manga, m.Categories)
				added = added + 1
			end
			Cache.addManga(manga)
			local key = Database.getKey(manga)
			if data.bookmarks and data.bookmarks[key] then
				FS.saveTable(CACHE .. key .. "/bookmarks.dat", data.bookmarks[key])
				Cache.loadBookmarks(manga)
			end
		end
	end
	Cache.save()
	if type(data.history) == "table" then
		Cache.mergeHistory(data.history, data.historyTime)
	end
	if data.settings and data.settings.Categories then
		Settings.Categories = data.settings.Categories
	end
	if data.settings and data.settings.FavouriteParsers then
		for k, v in pairs(data.settings.FavouriteParsers) do
			Settings.FavouriteParsers[k] = v
		end
	end
	Settings.save()
	for _, url in ipairs(data.repos or {}) do
		Extensions.addRepo(url)
	end
	-- reinstall missing extensions once repositories are loaded
	local missing = {}
	for _, e in ipairs(data.extensions or {}) do
		if not Extensions.isInstalled(e.id) then
			missing[#missing + 1] = e.id
		end
	end
	if #missing > 0 then
		Backup.pendingExtensions = missing
		Extensions.refresh(true)
	end
	Database.touch()
	Notifications.push(string.format(L().BACKUP_RESTORED, added), 2000)
end

---Called every frame: installs extensions from a restored backup once the catalog is ready
function Backup.update()
	if Backup.pendingExtensions and not Extensions.isRefreshing() and not Extensions.isBusy("refresh") then
		for _, id in ipairs(Backup.pendingExtensions) do
			local entry = Extensions.getEntry(id)
			if entry then
				Extensions.install(entry)
			end
		end
		Backup.pendingExtensions = nil
	end
end

function Backup.restoreMenu()
	local files = {}
	for _, f in ipairs(FS.list(DIR)) do
		if not f.directory and (f.name:find("%.otk$") or f.name:find("%.lua$")) then
			files[#files + 1] = f.name
		end
	end
	table.sort(files, function(a, b)
		return a > b
	end)
	if #files == 0 then
		Notifications.push(L().NO_BACKUPS)
		return
	end
	local items = {}
	for i, name in ipairs(files) do
		items[i] = {label = name, value = name}
	end
	Dialog.menu(L().RESTORE_BACKUP, items, function(item)
		Dialog.confirm(L().RESTORE_BACKUP_Q, item.value, function()
			restore(DIR .. item.value)
		end)
	end)
end

---Imports library, reading progress and parsers from a NOBORU installation
function Backup.importNoboru()
	local root = "ux0:data/noboru/"
	if not FS.dirExists(root) then
		Notifications.push(L().NOBORU_NOT_FOUND)
		return
	end
	Dialog.confirm(L().IMPORT_NOBORU_Q, L().IMPORT_NOBORU_DESC, function()
		local parsers = Extensions.importNoboruParsers()
		local lib = FS.loadTable(root .. "save.dat") or {}
		local added = 0
		for i = 1, #lib do
			local m = lib[i]
			if type(m) == "table" and m.ParserID and m.Link then
				local manga = CreateManga(m.Name, m.Link, m.ImageLink or "", m.ParserID, m.RawLink, m.BrowserLink)
				if manga then
					manga.Data = m.Data
					if not Database.check(manga) then
						Database.addManga(manga)
						added = added + 1
					end
					Cache.addManga(manga)
					local key = Database.getKey(manga)
					for _, file in ipairs({"bookmarks.dat", "chapters.dat"}) do
						if FS.exists(root .. "cache/" .. key .. "/" .. file) then
							FS.copy(root .. "cache/" .. key .. "/" .. file, CACHE .. key .. "/" .. file)
						end
					end
					Cache.loadBookmarks(manga)
				end
			end
		end
		Cache.save()
		Database.touch()
		Notifications.push(string.format(L().NOBORU_IMPORTED, added, parsers), 2500)
	end)
end
