ChapterSaver = {}
local allKeys = {}
local orderList = {}
local currentTask = nil
local Downloading = {}

---Path to saved chapters folder
local FOLDER = "ux0:data/otakio/chapters/"
local CHAPTERSAV_PATH = "ux0:data/otakio/c.c"

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

---@return string
---Creates key for a chapter from it's Manga's `parserID`, `Link` and chapter `Link`
local function getKey(chapter)
	return (chapter.Manga.ParserID .. chapter.Manga.Link):gsub("%p", "") .. "_" .. chapter.Link:gsub("%p", "")
end

ChapterSaver.getKey = getKey

---Page images the Vita can decode (GIF is left out: lpp-vita's GIF decoder crashes on many files)
local IMAGE_EXT = {jpg = true, jpeg = true, png = true, bmp = true, webp = true}
local function isImageName(name)
	local ext = string.match(string.lower(name or ""), "%.(%w+)$")
	return IMAGE_EXT[ext] == true
end

local function isPackageName(name)
	local lower = string.lower(name or "")
	return string.find(lower, "%.cbz$") ~= nil or string.find(lower, "%.zip$") ~= nil
end
local getFreeSpace = System.getFreeSpace
local is_notifyied = false
local is_notify_needed = true
local are_saved_chapters_updated = false

---Updates Cache things
function ChapterSaver.update()
	if #orderList == 0 and currentTask == nil then
		is_notifyied = false
		return
	end
	if not currentTask then
		currentTask = table.remove(orderList, 1)
		are_saved_chapters_updated = false
		if currentTask.Type == "Download" and getFreeSpace("ux0:") < 40 * 1024 * 1024 then
			if not is_notifyied then
				Notifications.push(Language[Settings.Language].NOTIFICATIONS.NO_SPACE_LEFT)
				is_notifyied = true
			end
			Downloading[currentTask.Key] = nil
			currentTask = nil
			return
		end
		currentTask.F = coroutine.create(currentTask.F)
	else
		if coroutine.status(currentTask.F) ~= "dead" then
			local _, msg, var1, var2 = coroutine.resume(currentTask.F)
			if _ then
				if currentTask.Destroy and msg and msg ~= "update_count+false" then
					if currentTask.Notify and not Settings.SilentDownloads then
						Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.CANCEL_DOWNLOAD, currentTask.MangaName, currentTask.ChapterName))
					end
					Downloading[currentTask.Key] = nil
					are_saved_chapters_updated = false
					currentTask = nil
				elseif msg == "update_count" then
					currentTask.page = var1
					currentTask.page_count = var2
				elseif msg == "update_count+false" then
					currentTask.page = var1
					currentTask.page_count = var2
				end
			else
				Console.error("Unknown error with saved chapters: " .. msg)
				Downloading[currentTask.Key] = nil
				are_saved_chapters_updated = false
				currentTask = nil
			end
		else
			if not currentTask.Fail then
				if currentTask.Type == "Download" and not Settings.SilentDownloads then
					Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.END_DOWNLOAD, currentTask.MangaName, currentTask.ChapterName))
				elseif currentTask.Type == "Import" then
					Notifications.push(Language[Settings.Language].NOTIFICATIONS.IMPORT_COMPLETED)
				end
			end
			Downloading[currentTask.Key] = nil
			are_saved_chapters_updated = false
			currentTask = nil
		end
	end
end

---@param chapter table
---Creates task for downloading `chapter`
function ChapterSaver.downloadChapter(chapter, silent)
	local k = getKey(chapter)
	Downloading[k] = {
		Type = "Download",
		Key = k,
		MangaName = chapter.Manga.Name,
		ChapterName = chapter.Name,
		Drive = Settings.getSaveDrivePath(),
		F = function()
			local FolderPath = Downloading[k].Drive .. ":data/otakio/chapters/"
			if not doesDirExist(FolderPath .. k) then
				createDirectory(FolderPath .. k)
			end
			local t = {}
			local connection
			local retry_get_chptrs = 0
			while retry_get_chptrs < 3 do
				ParserManager.prepareChapter(chapter, t)
				while ParserManager.check(t) do
					coroutine.yield("update_count", 0, 0)
				end
				if #t < 1 then
					Console.error("error getting pages")
					retry_get_chptrs = retry_get_chptrs + 1
					if retry_get_chptrs < 3 then
						connection = Threads.netActionUnSafe(Network.isWifiEnabled)
						if not connection then
							ConnectMessage.show()
						end
						while ConnectMessage.isActive() do
							coroutine.yield(true)
						end
						Console.error("retrying")
					end
				else
					break
				end
				coroutine.yield(true)
			end
			if retry_get_chptrs == 3 then
				Notifications.pushUnique(Language[Settings.Language].NOTIFICATIONS.NET_PROBLEM .. "\nMaybe chapter has 0 pages")
				removeDirectory(FolderPath .. k)
				Downloading[k].Fail = true
				Downloading[k] = nil
				return
			end
			local parser = GetParserByID(chapter.Manga.ParserID)
			for i = 1, #t do
				coroutine.yield("update_count", i - 1, #t)
				local result = {}
				parser:loadChapterPage(t[i], result)
				coroutine.yield(false)
				local retry = 0
				while retry < 3 do
					local link = result.Link
					if retry > 0 or ImageProxy.shouldProxy(link) then
						link = ImageProxy.wrap(link)
					end
					Threads.insertTask(
						result,
						{
							Type = "FileDownload",
							Link = link,
							Path = FolderPath .. k .. "/" .. i .. ".image"
						}
					)
					while Threads.check(result) do
						local progress = Threads.getProgress(result)
						coroutine.yield("update_count+false", i - 1 + progress, #t)
					end
					if doesFileExist(FolderPath .. k .. "/" .. i .. ".image") then
						local size = System.getPictureResolution(FolderPath .. k .. "/" .. i .. ".image")
						if not size or size <= 0 then
							Console.error("error loading picture for " .. k .. " " .. i)
							retry = retry + 1
							if retry < 3 then
								connection = Threads.netActionUnSafe(Network.isWifiEnabled)
								if not connection then
									ConnectMessage.show()
								end
								while ConnectMessage.isActive() do
									coroutine.yield(true)
								end
								Console.error("retrying")
							end
						else
							break
						end
					else
						Console.error("download of " .. k .. "/" .. i .. ".image failed")
						retry = retry + 1
						if retry < 3 then
							connection = Threads.netActionUnSafe(Network.isWifiEnabled)
							if not connection then
								ConnectMessage.show()
							end
							while ConnectMessage.isActive() do
								coroutine.yield(true)
							end
							Console.error("retrying")
						end
					end
					coroutine.yield(true)
				end
				if retry == 3 then
					Notifications.pushUnique(Language[Settings.Language].NOTIFICATIONS.NET_PROBLEM)
					removeDirectory(FolderPath .. k)
					Downloading[k].Fail = true
					Downloading[k] = nil
					return
				end
			end
			local fh = openFile(FolderPath .. k .. "/done.txt", FCREATE)
			writeFile(fh, #t, string.len(#t))
			closeFile(fh)
			allKeys[k] = Downloading[k].Drive
			ChapterSaver.save()
			Downloading[k] = nil
		end
	}
	are_saved_chapters_updated = false
	orderList[#orderList + 1] = Downloading[k]
	if not silent and not Settings.SilentDownloads then
		Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.START_DOWNLOAD, chapter.Manga.Name, chapter.Name))
	end
end

local getTime = System.getTime
local getDate = System.getDate
local copyFile = CopyFile

local listZip = System.listZip
local extractFromZip = System.extractFromZip
local rename = System.rename

function ChapterSaver.importManga(path)
	local h, mn, s = getTime()
	local _, d, mo, y = getDate()
	-- a short hash of the source path identifies the import: two imports in the same second don't collide,
	-- re-importing the same item doesn't duplicate it, and accents/long names stay out of the cache folder names
	local hash = 5381
	for i = 1, #path do
		hash = (hash * 33 + string.byte(path, i)) % 4294967296
	end
	local Manga = CreateManga(path:match(".*/(.*)%..-$") or path:match(".*/(.-)$"), string.format("local:%08x%x", hash, #path), "", "IMPORTED", "local:book")
	if path:find("^uma0:") then
		Manga.Location = "uma0"
	else
		Manga.Location = "ux0"
	end
	Downloading[path] = {
		Type = "Import",
		Key = path,
		MangaName = Manga.Name,
		Drive = "ux0",
		ChapterName = "Importing"
	}
	local this = Downloading[path]
	this.F = function()
		if doesDirExist(path) then
			-- a manga folder may hold chapter folders, .cbz/.zip chapters or the pages themselves;
			-- loose files next to chapters (cover.jpg, info.txt…) are ignored
			local groups = {folder = {}, package = {}, image = {}}
			for _, f in ipairs(listDirectory(path) or {}) do
				if f.directory then
					groups.folder[#groups.folder + 1] = f
				elseif isPackageName(f.name) then
					groups.package[#groups.package + 1] = f
				elseif isImageName(f.name) then
					groups.image[#groups.image + 1] = f
				end
			end
			local type = (#groups.folder > 0 and "folder") or (#groups.package > 0 and "package") or (#groups.image > 0 and "image") or nil
			if not type then
				Notifications.push(path .. "\nerror: no supported images found")
				Downloading[path].Fail = true
				Downloading[path] = nil
				return
			end
			local dir = groups[type]
			-- a loose image next to the chapters (cover.jpg) becomes the cover
			local looseCover = nil
			if type ~= "image" then
				for _, f in ipairs(groups.image) do
					if not looseCover or string.find(string.lower(f.name), "^cover") then
						looseCover = path .. "/" .. f.name
					end
				end
			end
			table.sort(
				dir,
				function(a, b)
					return a.name < b.name
				end
			)
			if type == "folder" then
				local is_cover_loaded = false
				local Chapters = {}
				Cache.addManga(Manga)
				for _, folder in ipairs(dir) do
					local Chapter = {
						Name = folder.name,
						Link = table.concat({h, mn, s, d, mo, y, _}, "B"),
						Pages = {},
						Manga = Manga
					}
					local subDir = listDirectory(path .. "/" .. folder.name) or {}
					table.sort(
						subDir,
						function(a, b)
							return a.name < b.name
						end
					)
					local imageLinks = {}
					for _, f in ipairs(subDir) do
						if not f.directory and isImageName(f.name) then
							imageLinks[#imageLinks + 1] = path .. "/" .. folder.name .. "/" .. f.name
						end
					end
					if #imageLinks > 0 then
						Chapters[#Chapters + 1] = Chapter
						if not is_cover_loaded then
							copyFile(imageLinks[1], "ux0:data/otakio/cache/" .. Cache.getKey(Manga) .. "/cover.image")
							is_cover_loaded = true
						end
						imageLinks = table.concat(imageLinks, "\n")
						local k = getKey(Chapter)
						removeDirectory(FOLDER .. k)
						createDirectory(FOLDER .. k)
						local fh = openFile(FOLDER .. k .. "/custom.txt", FCREATE)
						writeFile(fh, imageLinks, #imageLinks)
						closeFile(fh)
						allKeys[k] = true
					else
						Notifications.push(Chapter.Name .. "\nerror: no supported images found")
					end
				end
				if #Chapters > 0 then
					Cache.saveChapters(Manga, Chapters)
					if looseCover then
						copyFile(looseCover, "ux0:data/otakio/cache/" .. Cache.getKey(Manga) .. "/cover.image")
					end
					Database.addManga(Manga)
					ChapterSaver.save()
				else
					Cache.removeManga(Manga)
					Notifications.push(path .. "\nerror: no supported chapters found")
					Downloading[path].Fail = true
				end
				Downloading[path] = nil
			elseif type == "image" then
				local imageLinks = {}
				for _, f in ipairs(dir) do
					imageLinks[_] = path .. "/" .. f.name
				end
				local Chapter = {
					Name = Manga.Name,
					Link = table.concat({h, mn, s, d, mo, y}, "B"),
					Pages = {},
					Manga = Manga
				}
				if #imageLinks > 0 then
					Cache.addManga(Manga, {Chapter})
					copyFile(imageLinks[1], "ux0:data/otakio/cache/" .. Cache.getKey(Manga) .. "/cover.image")
					imageLinks = table.concat(imageLinks, "\n")
					local k = getKey(Chapter)
					removeDirectory(FOLDER .. k)
					createDirectory(FOLDER .. k)
					local fh = openFile(FOLDER .. k .. "/custom.txt", FCREATE)
					writeFile(fh, imageLinks, #imageLinks)
					closeFile(fh)
					allKeys[k] = true
					Database.addManga(Manga)
					ChapterSaver.save()
				else
					Notifications.push(path .. "\nerror: no supported images found")
					Downloading[path].Fail = true
				end
				Downloading[path] = nil
			elseif type == "package" then
				local is_cover_loaded = false
				Cache.addManga(Manga)
				local mk = Cache.getKey(Manga)
				local Chapters = {}
				for _, pack in ipairs(dir) do
					local Chapter = {
						Name = pack.name:match("(.*)%..-$"),
						Link = table.concat({h, mn, s, d, mo, y, _}, "B"),
						Pages = {},
						Manga = Manga
					}
					local zipDir = listZip(path .. "/" .. pack.name) or {}
					table.sort(
						zipDir,
						function(a, b)
							return a.name < b.name
						end
					)
					local is_contain_images = false
					for _, file in ipairs(zipDir) do
						Console.write(file.name)
						if isImageName(file.name) then
							if not is_cover_loaded then
								extractFromZip(path .. "/" .. pack.name, file.name, "ux0:data/otakio/cache/" .. mk .. "/cover.image")
								is_cover_loaded = true
							end
							is_contain_images = true
							break
						end
					end
					if is_contain_images then
						Chapters[#Chapters + 1] = Chapter
						local k = getKey(Chapter)
						removeDirectory(FOLDER .. k)
						createDirectory(FOLDER .. k)
						local fh = openFile(FOLDER .. k .. "/custom.txt", FCREATE)
						writeFile(fh, path .. "/" .. pack.name, #(path .. "/" .. pack.name))
						closeFile(fh)
						allKeys[k] = true
					else
						Notifications.push(path .. "/" .. pack.name .. "\nerror: no supported images found")
					end
				end
				if #Chapters > 0 then
					Cache.saveChapters(Manga, Chapters)
					if looseCover then
						copyFile(looseCover, "ux0:data/otakio/cache/" .. Cache.getKey(Manga) .. "/cover.image")
					end
					Database.addManga(Manga)
					ChapterSaver.save()
				else
					Cache.removeManga(Manga)
					Notifications.push(Manga.Name .. "\nerror: no supported chapters found")
					Downloading[path].Fail = true
				end
				Downloading[path] = nil
			end
		elseif doesFileExist(path) then
			if isPackageName(path) then
				Cache.addManga(Manga)
				local mk = Cache.getKey(Manga)
				local Chapter = {
					Name = path:match(".*/(.*)%..-$"),
					Link = table.concat({h, mn, s, d, mo, y, _}, "B"),
					Pages = {},
					Manga = Manga
				}
				local zipDir = listZip(path) or {}
				table.sort(
					zipDir,
					function(a, b)
						return a.name < b.name
					end
				)
				local is_cover_loaded = false
				for _, file in ipairs(zipDir) do
					Console.write(file.name)
					if isImageName(file.name) then
						extractFromZip(path, file.name, "ux0:data/otakio/cache/" .. mk .. "/cover.image")
						is_cover_loaded = true
						break
					end
				end
				if is_cover_loaded then
					local k = getKey(Chapter)
					removeDirectory(FOLDER .. k)
					createDirectory(FOLDER .. k)
					local fh = openFile(FOLDER .. k .. "/custom.txt", FCREATE)
					writeFile(fh, path, #path)
					closeFile(fh)
					allKeys[k] = true
					Cache.saveChapters(Manga, {Chapter})
					Database.addManga(Manga)
					ChapterSaver.save()
				else
					Cache.removeManga(Manga)
					Notifications.push(path .. "\nerror: no supported images found")
					Downloading[path].Fail = true
				end
				Downloading[path] = nil
			else
				Notifications.push(path .. "\nerror: this format not supported")
				Downloading[path].Fail = true
				Downloading[path] = nil
			end
		end
	end
	are_saved_chapters_updated = false
	orderList[#orderList + 1] = this
end

---@return boolean
---Gives info if download is running
function ChapterSaver.is_download_running()
	return currentTask ~= nil or #orderList > 0
end

---@param key string
---Stops task by it's key
local function stop(key, silent)
	if Downloading[key] then
		if Downloading[key] == currentTask then
			Downloading[key].Destroy = true
			Downloading[key].Notify = silent == nil
			Network.stopCurrentDownload()
			local FolderPath = Downloading[key].Drive .. ":data/otakio/chapters/"
			removeDirectory(FolderPath .. key)
		else
			local newOrder = {}
			for _, v in ipairs(orderList) do
				if v == Downloading[key] then
					if is_notify_needed and silent == nil and not Settings.SilentDownloads then
						Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.CANCEL_DOWNLOAD, v.MangaName, v.ChapterName))
					end
				else
					newOrder[#newOrder + 1] = v
				end
			end
			orderList = newOrder
		end
		are_saved_chapters_updated = false
		Downloading[key] = nil
	end
end

---@param chapters table
---@param silent boolean
---Stops List of `chapters` downloading and notify if `silent == nil`
function ChapterSaver.stopList(chapters, silent)
	local newOrder = {}
	local orderCount = #orderList
	for _, v in ipairs(chapters) do
		local key = getKey(v)
		local d = Downloading[key]
		if d then
			if d == currentTask then
				d.Destroy = true
				d.Notify = silent == nil
				Network.stopCurrentDownload()
				local FolderPath = Downloading[key].Drive .. ":data/otakio/chapters/"
				removeDirectory(FolderPath .. key)
			else
				for i, od in pairs(orderList) do
					if od == d then
						orderList[i] = nil
						break
					end
				end
			end
			Downloading[key] = nil
		end
	end
	for i = 1, orderCount do
		if orderList[i] ~= nil then
			newOrder[#newOrder + 1] = orderList[i]
		end
	end
	orderList = newOrder
	are_saved_chapters_updated = false
end

---@param chapter table
---@param silent boolean
---Stops `chapter` downloading and notify if `silent == nil`
function ChapterSaver.stop(chapter, silent)
	if chapter then
		stop(getKey(chapter), silent)
	end
end

---@param item table
---Stops `chapter` downloading by List item from `Cache.getDownloadingList` function
function ChapterSaver.stopByListItem(item)
	if item then
		stop(item.Key)
	end
end

---@param chapter table
---Deletes saved chapter
function ChapterSaver.delete(chapter, silent)
	local k = getKey(chapter)
	if allKeys[k] then
		local FolderPath = (allKeys[k] == true and "ux0" or allKeys[k]) .. ":data/otakio/chapters/"
		removeDirectory(FolderPath .. k)
		allKeys[k] = nil
		ChapterSaver.save()
		if not silent and not Settings.SilentDownloads then
			Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.CHAPTER_REMOVE, k))
		end
	end
end

local cached = {}

---@return table
---Returns all active downloadings
function ChapterSaver.getDownloadingList()
	if are_saved_chapters_updated then
		return cached
	end
	local list = {}
	orderList[0] = currentTask
	for i = currentTask and 0 or 1, #orderList do
		list[#list + 1] = orderList[i]
	end
	are_saved_chapters_updated = true
	cached = list
	return cached
end

function ChapterSaver.clearDownloadingList()
	if currentTask then
		stop(currentTask.Key, true)
	end
	for i = 1, #orderList do
		local key = orderList[i].Key
		local FolderPath = Downloading[key].Drive .. ":data/otakio/chapters/"
		Downloading[key] = nil
		removeDirectory(FolderPath .. key)
	end
	orderList = {}
end

---@param chapter table
---@return boolean
---Gives `true` if chapter is downloaded
function ChapterSaver.check(chapter)
	local key = allKeys[getKey(chapter)]
	return key == true or key == "uma0" and doesDirExist("uma0:data/otakio") or key == "ux0" or chapter and chapter.FastLoad
end

---@param manga table
---@return boolean
---Gives `true` if at least one chapter of `manga` is downloaded
function ChapterSaver.hasDownloadsForManga(manga)
	local prefix = (manga.ParserID .. manga.Link):gsub("%p", "") .. "_"
	local n = #prefix
	for key in pairs(allKeys) do
		if string.rawsub(key, 1, n) == prefix then
			return true
		end
	end
	return false
end

---@param manga table
---@return integer number of downloaded chapters
function ChapterSaver.countForManga(manga)
	local prefix = (manga.ParserID .. manga.Link):gsub("%p", "") .. "_"
	local n, c = #prefix, 0
	for key in pairs(allKeys) do
		if string.rawsub(key, 1, n) == prefix then
			c = c + 1
		end
	end
	return c
end

---@param chapter table
---@return boolean
---Gives `true` if chapter is downloading
function ChapterSaver.is_downloading(chapter)
	return Downloading[getKey(chapter)]
end

local statFile = System.statFile

---@param chapter table
---@return table
---Gives table with all pathes to chapters images (pages)
function ChapterSaver.getChapter(chapter)
	if chapter.FastLoad then
		local _table_ = {
			Done = true
		}
		local info = statFile(chapter.Path)
		if info and info.directory then
			local dir = listDirectory(chapter.Path) or {}
			table.sort(
				dir,
				function(a, b)
					return a.name < b.name
				end
			)
			for _, file in ipairs(dir) do
				if not file.directory and (isImageName(file.name) or file.name:find("%.image$")) then
					_table_[#_table_ + 1] = {
						Path = chapter.Path .. "/" .. file.name
					}
				end
			end
		else
			local zip = listZip(chapter.Path) or {}
			table.sort(
				zip,
				function(a, b)
					return a.name < b.name
				end
			)
			for _, file in ipairs(zip) do
				if not file.directory and isImageName(file.name) then
					_table_[#_table_ + 1] = {
						Extract = file.name,
						Path = chapter.Path
					}
				end
			end
		end
		return _table_
	end
	local k = getKey(chapter)
	local _table_ = {
		Done = true
	}
	if allKeys[k] then
		local FolderPath = (allKeys[k] == true and "ux0" or allKeys[k]) .. ":data/otakio/chapters/"
		if doesFileExist(FolderPath .. k .. "/custom.txt") then
			local fh_2 = openFile(FolderPath .. k .. "/custom.txt", FREAD)
			local pathes = readFile(fh_2, sizeFile(fh_2))
			closeFile(fh_2)
			local lines = ToLines(pathes)
			if #lines == 1 and isPackageName(lines[1]) then
				local zip = listZip(lines[1]) or {}
				table.sort(
					zip,
					function(a, b)
						return a.name < b.name
					end
				)
				for _, file in ipairs(zip) do
					if not file.directory and isImageName(file.name) then
						_table_[#_table_ + 1] = {
							Extract = file.name,
							Path = lines[1]
						}
					end
				end
			else
				for _, path in ipairs(lines) do
					_table_[_] = {
						Path = path
					}
				end
			end
		else
			local pages = #(listDirectory(FolderPath .. k) or {}) - 1
			for i = 1, pages do
				_table_[i] = {
					Path = FolderPath .. k .. "/" .. i .. ".image"
				}
			end
		end
	end
	return _table_
end

---Saves saved chapters changes
function ChapterSaver.save()
	if doesFileExist(CHAPTERSAV_PATH) then
		deleteFile(CHAPTERSAV_PATH)
	end
	local fh = openFile(CHAPTERSAV_PATH, FCREATE)
	local saveData = "Keys = " .. table.serialize(allKeys, true)
	writeFile(fh, saveData, #saveData)
	closeFile(fh)
end

---Loads saved chapters changes
function ChapterSaver.load()
	allKeys = {}
	if doesFileExist(CHAPTERSAV_PATH) then
		local fh = openFile(CHAPTERSAV_PATH, FREAD)
		local loadKeysFunction = load("local " .. readFile(fh, sizeFile(fh)) .. " return Keys")
		if loadKeysFunction then
			local keys = loadKeysFunction() or {}
			local cnt = 0
			for _, _ in pairs(keys) do
				cnt = cnt + 1
			end
			local cntr = 1
			for k, _ in pairs(keys) do
				local FolderPath = (_ == true and "ux0" or _) .. ":data/otakio/chapters/"
				coroutine.yield("ChapterSaver: Checking " .. FolderPath .. k, cntr / cnt)
				if not Settings.SkipCacheChapterChecking then
					if doesFileExist(FolderPath .. k .. "/custom.txt") then
						local fh_2 = openFile(FolderPath .. k .. "/custom.txt", FREAD)
						local pathes = readFile(fh_2, sizeFile(fh_2))
						closeFile(fh_2)
						for _, path in ipairs(ToLines(pathes)) do
							if not doesFileExist(path) then
								removeDirectory(FolderPath .. k)
								Notifications.push("here chapters_error\n" .. k)
								break
							end
						end
						allKeys[k] = true
					elseif doesFileExist(FolderPath .. k .. "/done.txt") then
						local fh_2 = openFile(FolderPath .. k .. "/done.txt", FREAD)
						local pages = readFile(fh_2, sizeFile(fh_2))
						closeFile(fh_2)
						local lDir = listDirectory(FolderPath .. k) or {}
						if tonumber(pages) == #lDir - 1 then
							--[[
                            -- This code checks all images in cache, their type (more safer)
                            local count = 0
                            for i = 1, #lDir do
                            local width = System.getPictureResolution(FOLDER .. k .. "/" .. lDir[i].name)
                            if not width or width <= 0 then
                            count = count + 1
                            if count == 2 then
                            rem_dir("ux0:data/otakio/chapters/" .. k)
                            Notifications.push("chapters_error_wrong_image\n" .. k)
                            break
                            end
                            end
                            end
                            if count < 2 then
                            Keys[k] = true
                            end]]
							allKeys[k] = _
						else
							removeDirectory(FolderPath .. k)
							Notifications.push("chapters_error\n" .. k)
						end
					else
						removeDirectory(FolderPath .. k)
						Notifications.push("chapters_error\n" .. k)
					end
				else
					allKeys[k] = _
				end
				cntr = cntr + 1
			end
			local dirList = listDirectory("ux0:data/otakio/chapters") or {}
			for _, v in ipairs(dirList) do
				if not allKeys[v.name] and v.directory then
					removeDirectory("ux0:data/otakio/chapters/" .. v.name)
				end
			end
			if doesDirExist("uma0:data/otakio") then
				dirList = listDirectory("uma0:data/otakio/chapters") or {}
				for _, v in ipairs(dirList) do
					if not allKeys[v.name] and v.directory then
						removeDirectory("uma0:data/otakio/chapters/" .. v.name)
					end
				end
			end
		end
		closeFile(fh)
		ChapterSaver.save()
	end
end

function ChapterSaver.setKey(key)
	allKeys[key] = true
	ChapterSaver.save()
end

---Clears all saved chapters
function ChapterSaver.clear()
	is_notify_needed = false
	local list = ChapterSaver.getDownloadingList()
	for i = 1, #list do
		ChapterSaver.stopByListItem(list[i])
	end
	is_notify_needed = true
	removeDirectory("ux0:data/otakio/chapters")
	createDirectory("ux0:data/otakio/chapters")
	if doesDirExist("uma0:data/otakio") then
		removeDirectory("uma0:data/otakio/chapters")
		createDirectory("uma0:data/otakio/chapters")
	end
	allKeys = {}
	ChapterSaver.save()
	Notifications.push(Language[Settings.Language].NOTIFICATIONS.CHAPTERS_CLEARED)
end
