---Main content screens: Library, Browse (sources + source catalog), Downloads,
---Import and Settings. Updates/History/Extensions/Global search live in screens.lua.
Catalogs = {}
Panels = {}

local slider = CreateSlider()
local TOUCH_MODES = TOUCH_MODES

local doesFileExist = System.doesFileExist
local doesDirExist = System.doesDirExist
local listDirectory = System.listDirectory
local abs, ceil, floor, max, min = math.abs, math.ceil, math.floor, math.max, math.min
local copyFile = CopyFile

-- layout ---------------------------------------------------------------------
local X0 = Config.RAIL_WIDTH + 12
local X1 = 944
local COLS = 5
local GAP = 10
local PITCH_X = MANGA_WIDTH + GAP
local PITCH_Y = MANGA_HEIGHT + GAP + 6
local GRID_X = X0 + floor(((X1 - X0) - (COLS * MANGA_WIDTH + (COLS - 1) * GAP)) / 2)
local ROW_H = 72
local LIST_TOP = 64

local function gridTop()
	return Catalogs.hasCategoryBar() and 98 or 64
end

local currentParser = nil
local touchTimer = Timer.new()

local status = "LIBRARY"

local downloadedImages = {}
local page = 1
local currentMangaList = {}
local parsersList = {}
local currentCategory = 0
local listVersion = -1

local chaptersFolderSize
local cacheFolderSize
local sure_clear_library
local sure_clear_chapters
local sure_clear_all_cache
local sure_clear_cache
local manga_load_status = 0

local smilesList = {"ಥ_ಥ", "ಠ_ಠ", "ヽ(`Д´)ﾉ", "°Д°", "(ó﹏ò｡)", "(╥﹏╥)", "(⊙_⊙)", "ʘ‿ʘ", "(￣ω￣)", "(´• ω •`) ♡", "(⌒_⌒;)", "(✧∀✧)/"}
local smile = nil

local function L()
	return Language[Settings.Language].OTAKIO
end

-- height of the credits card under the About rows
local CREDITS_H = 450

local function isGrid()
	return status == "MANGA" or status == "LIBRARY"
end

local mangaSelector =
	Selector:new(
	-COLS,
	COLS,
	-1,
	1,
	function()
		return max(1, floor((slider.Y) / PITCH_Y) * COLS + 1)
	end
)

local function listCap()
	return max(1, floor(slider.Y / ROW_H) + 1)
end

local parserSelector = Selector:new(-1, 1, -3, 3, listCap)
local downloadSelector = Selector:new(-1, 1, -3, 3, listCap)
local settingSelector = Selector:new(-1, 1, -3, 3, listCap)
local importSelector = Selector:new(-1, 1, -3, 3, listCap)

-------------------------------------------------------------------------------
-- cover loading (LRU-ish: covers near the viewport stay loaded)
-------------------------------------------------------------------------------

local function freeMangaImage(manga)
	if manga and manga.ImageDownload then
		Threads.remove(manga)
		if manga.Image and manga.Image.free then
			manga.Image:free()
		end
		manga.Image = nil
		manga.ImageDownload = nil
	end
end
Catalogs.freeMangaImage = freeMangaImage

local function setNewImage(manga)
	if manga.Image ~= nil and type(manga.Image) == "table" and manga.Image.Type == "image" then
		manga.Image:free()
	end
	manga.Image = manga.newImage
	manga.newImage = nil
	manga.ImageFade = 0
end

local function loadImageTask(manga, path)
	Threads.addTask(manga, {
		Type = "Image",
		Path = path,
		Table = manga,
		MaxHeight = MANGA_HEIGHT * 2,
		Index = "newImage",
		OnFinalComplete = function()
			setNewImage(manga)
		end
	})
end

local function loadMangaImage(manga)
	if CustomCovers.hasCustomCover(manga) then
		local customCoverPath = "ux0:data/otakio/cache/" .. Cache.getKey(manga) .. "/custom_cover.image"
		if doesFileExist(customCoverPath) and (System.getPictureResolution(customCoverPath) or -1) > 0 then
			loadImageTask(manga, customCoverPath)
		else
			if not Cache.isCached(manga) then
				Cache.addManga(manga)
			end
			local cover = CustomCovers.getCustomCover(manga)
			local cacheKey = Cache.getKey(manga)
			local t = {}
			if cover.Path then
				copyFile(cover.Path:find("^...?0:") and cover.Path or ("ux0:data/otakio/" .. cover.Path), customCoverPath)
				loadImageTask(manga, customCoverPath)
			elseif cover.ParserID then
				Threads.insertTask(manga, {
					Type = "function",
					OnComplete = function()
						ParserManager.getPageImage(cover.ParserID, cover.Link, t)
						while ParserManager.check(t) do
							coroutine.yield(false)
						end
						Threads.insertTask(manga, {
							Type = "FileDownload",
							ImageFile = true,
							Link = t.Link,
							Path = customCoverPath,
							OnComplete = function()
								loadImageTask(manga, customCoverPath)
							end
						})
					end
				})
			elseif cover.Link then
				Threads.insertTask(manga, {
					Type = "FileDownload",
					ImageFile = true,
					Link = cover.Link,
					Path = customCoverPath,
					OnComplete = function()
						loadImageTask(manga, customCoverPath)
					end
				})
			else
				CustomCovers.setMangaCover(manga, nil)
			end
		end
	else
		local path = manga.Path or ("cache/" .. Cache.getKey(manga) .. "/cover.image")
		local seen = Cache.TEMP_COVERS .. Cache.getKey(manga) .. ".image"
		if path and doesFileExist("ux0:data/otakio/" .. path) and (System.getPictureResolution("ux0:data/otakio/" .. path) or -1) > 0 then
			loadImageTask(manga, path)
		elseif not Database.check(manga) and doesFileExist(seen) and (System.getPictureResolution(seen) or -1) > 0 then
			-- downloaded earlier in this session (scrolled away and back): decode it from disk
			loadImageTask(manga, seen)
		else
			if Database.check(manga) and not Cache.isCached(manga) then
				Cache.addManga(manga)
			end
			Threads.addTask(manga, {
				Type = "ImageDownload",
				Link = manga.ImageLink,
				Table = manga,
				Index = "newImage",
				OnFinalComplete = function()
					setNewImage(manga)
				end,
				MaxHeight = MANGA_HEIGHT * 2,
				Path = Cache.isCached(manga) and path or (Cache.TEMP_COVERS .. Cache.getKey(manga) .. ".image")
			})
		end
	end
end
Catalogs.loadMangaImage = loadMangaImage

local KEEP_LOADED = COLS * 6 -- covers kept in VRAM around the viewport

---Frees covers outside items [first - margin, last + margin], except the one open in Details
local function freeCoversOutside(first, last, margin)
	local newTable = {}
	for _, i in ipairs(downloadedImages) do
		local manga = currentMangaList[i]
		if (i < first - margin or i > last + margin) and manga and (Details.getFade() == 0 or manga ~= Details.getManga()) then
			freeMangaImage(manga)
		else
			newTable[#newTable + 1] = i
		end
	end
	downloadedImages = newTable
end

local function visibleRange()
	local first = max(1, floor((slider.Y) / PITCH_Y) * COLS + 1)
	local last = min(#currentMangaList, first + COLS * 3 - 1)
	return first, last
end

-- texture budget short of memory: covers that are not on screen go first
Textures.register("covers", 1, function()
	local first, last = visibleRange()
	freeCoversOutside(first, last, 0)
end)

local function UpdateMangas()
	local first, last = visibleRange()
	if abs(slider.V) < 6 and Timer.getTime(touchTimer) > 120 then
		-- preload one extra row below
		local preloadLast = min(#currentMangaList, last + COLS)
		for i = first, preloadLast do
			local manga = currentMangaList[i]
			if manga and not manga.ImageDownload then
				loadMangaImage(manga)
				manga.ImageDownload = true
				downloadedImages[#downloadedImages + 1] = i
			end
		end
	end
	-- free covers far away from the viewport only when we hold too many
	if #downloadedImages > KEEP_LOADED then
		freeCoversOutside(first, last, COLS * 2)
	end
	-- cancel pending downloads that scrolled away (fast flings)
	if abs(slider.V) > 20 then
		for _, i in ipairs(downloadedImages) do
			local manga = currentMangaList[i]
			if manga and (i < first - COLS or i > last + COLS) and Threads.check(manga) and not manga.Image then
				Threads.remove(manga)
				manga.ImageDownload = nil
			end
		end
	end
end

-------------------------------------------------------------------------------
-- selection actions
-------------------------------------------------------------------------------

local function selectManga(index)
	local manga = currentMangaList[index]
	if manga then
		Details.setManga(manga)
	end
end

local function selectParser(index)
	local newParser = parsersList[index]
	if newParser then
		currentParser = newParser
		Catalogs.setStatus("MANGA")
		CatalogModes.load(newParser)
	end
end

---Opens a source catalog directly (used by global search "see more")
function Catalogs.openParser(parser)
	if parser then
		currentParser = parser
		Catalogs.setStatus("MANGA")
		CatalogModes.load(parser)
	end
end

function Catalogs.getCurrentParser()
	return currentParser
end

local function selectSetting(index)
	local item = Settings.list()[index]
	if item and Settings.isTab(item) then
		settingSelector:resetSelected()
		slider.Y = 0
		Settings.setTab(item)
	elseif item then
		if SettingsFunctions[item] then
			if item == "ClearChapters" then
				sure_clear_chapters = sure_clear_chapters + 1
				if sure_clear_chapters == 2 then
					SettingsFunctions[item]()
					chaptersFolderSize = nil
					sure_clear_chapters = 0
				end
			elseif item == "ClearLibrary" then
				sure_clear_library = sure_clear_library + 1
				if sure_clear_library == 2 then
					SettingsFunctions[item]()
					sure_clear_library = 0
				end
			elseif item == "ClearAllCache" then
				sure_clear_all_cache = sure_clear_all_cache + 1
				if sure_clear_all_cache == 2 then
					cacheFolderSize = nil
					SettingsFunctions[item]()
					sure_clear_all_cache = 0
				end
			elseif item == "ClearCache" then
				sure_clear_cache = sure_clear_cache + 1
				if sure_clear_cache == 2 then
					cacheFolderSize = nil
					SettingsFunctions[item]()
					sure_clear_cache = 0
				end
			else
				SettingsFunctions[item]()
				Settings.save()
			end
		end
		if item ~= "ClearChapters" then
			sure_clear_chapters = 0
		end
		if item ~= "ClearCache" then
			sure_clear_cache = 0
		end
		if item ~= "ClearAllCache" then
			sure_clear_all_cache = 0
		end
		if item ~= "ClearLibrary" then
			sure_clear_library = 0
		end
	end
end

local function selectImport(index)
	local list = Import.listDir()
	if index > 0 and index <= #list then
		Import.go(list[index])
	end
end

mangaSelector:xaction(selectManga)
parserSelector:xaction(selectParser)
-- Downloads tab: active queue first, then every manga with downloaded chapters
local downloadedCache, downloadedStamp = nil, nil

local function downloadedManga()
	local stamp = #ChapterSaver.getDownloadingList()
	if downloadedCache and downloadedStamp == stamp then
		return downloadedCache
	end
	local list = {}
	for _, manga in pairs(Cache.getManga()) do
		local n = ChapterSaver.countForManga(manga)
		if n > 0 then
			list[#list + 1] = {kind = "manga", manga = manga, count = n}
		end
	end
	table.sort(list, function(a, b)
		return (a.manga.Name or ""):lower() < (b.manga.Name or ""):lower()
	end)
	downloadedCache, downloadedStamp = list, stamp
	return list
end

local function downloadRows()
	local rows = {}
	for _, task in ipairs(ChapterSaver.getDownloadingList()) do
		rows[#rows + 1] = {kind = "task", task = task}
	end
	local done = downloadedManga()
	if #done > 0 then
		rows[#rows + 1] = {kind = "section", label = string.format(L().DOWNLOADED_N, #done)}
		for _, row in ipairs(done) do
			rows[#rows + 1] = row
		end
	end
	return rows
end

-- covers of the downloaded manga shown in the Downloads tab (freed when leaving it)
local downloadThumbs = {}

local function freeDownloadThumbs()
	for _, m in ipairs(downloadThumbs) do
		freeMangaImage(m)
	end
	downloadThumbs = {}
end

local function deleteDownloads(row)
	Dialog.confirm(Language[Settings.Language].EXTRA.RemoveAll or "Remove", row.manga.Name, function()
		for _, chapter in ipairs(Cache.loadChapters(row.manga, true) or {}) do
			ChapterSaver.delete(chapter, true)
		end
		downloadedCache = nil
	end)
end

local function selectDownloadRow(row)
	if not row then
		return
	end
	if row.kind == "task" then
		ChapterSaver.stopByListItem(row.task)
	elseif row.kind == "manga" then
		Details.setManga(row.manga)
	end
end

downloadSelector:xaction(function(item)
	selectDownloadRow(downloadRows()[item])
end)
settingSelector:xaction(selectSetting)
importSelector:xaction(selectImport)

-------------------------------------------------------------------------------
-- library helpers
-------------------------------------------------------------------------------

function Catalogs.hasCategoryBar()
	return status == "LIBRARY" and #Database.getCategories() > 0
end

local function categoryTabs()
	local tabs = {{id = 0, name = L().ALL}}
	for _, c in ipairs(Database.getCategories()) do
		tabs[#tabs + 1] = {id = c.id, name = c.name}
	end
	return tabs
end

local function cycleCategory(delta)
	local tabs = categoryTabs()
	local idx = 1
	for i, t in ipairs(tabs) do
		if t.id == currentCategory then
			idx = i
		end
	end
	idx = ((idx - 1 + delta) % #tabs) + 1
	currentCategory = tabs[idx].id
	Catalogs.shrink()
	downloadedImages = {}
	mangaSelector:resetSelected()
	slider.Y = 0
	listVersion = -1
end

---Library options dialog (sort / filter / categories)
function Catalogs.libraryOptions()
	Dialog.menu(L().LIBRARY_OPTIONS, {
		{label = L().SORT_BY, sub = L().SORT_NAMES[Settings.LibrarySorting] or Settings.LibrarySorting, value = "sort"},
		{label = L().FILTER, sub = L().FILTER_NAMES[Settings.LibraryFilter or "All"] or Settings.LibraryFilter, value = "filter"},
		{label = L().EDIT_CATEGORIES, sub = string.format(L().N_CATEGORIES, #Database.getCategories()), value = "categories"},
		{label = L().REFRESH_LIBRARY, value = "refresh"}
	}, function(item)
		if item.value == "sort" then
			local items, sel = {}, 1
			for i, m in ipairs(Database.SORT_MODES) do
				items[i] = {label = L().SORT_NAMES[m] or m, value = m}
				if m == Settings.LibrarySorting then
					sel = i
				end
			end
			Dialog.choice(L().SORT_BY, items, sel, function(choice)
				Settings.LibrarySorting = choice.value
				Settings.save()
				listVersion = -1
			end)
		elseif item.value == "filter" then
			local items, sel = {}, 1
			for i, m in ipairs(Database.FILTERS) do
				items[i] = {label = L().FILTER_NAMES[m] or m, value = m}
				if m == (Settings.LibraryFilter or "All") then
					sel = i
				end
			end
			Dialog.choice(L().FILTER, items, sel, function(choice)
				Settings.LibraryFilter = choice.value
				Settings.save()
				listVersion = -1
			end)
		elseif item.value == "categories" then
			CategoryEditor.open()
		elseif item.value == "refresh" then
			ParserManager.updateCounters()
		end
	end)
end

---Resume reading the most recent chapter of `manga` straight from the grid
local function continueReading(manga)
	if not manga then
		return
	end
	local chapters = Cache.loadChapters(manga, true)
	if #chapters == 0 then
		Details.setManga(manga)
		return
	end
	Cache.loadBookmarks(manga)
	local latest = Cache.getLatestBookmark(manga)
	local idx = 1
	for i = 1, #chapters do
		if chapters[i].Link:gsub("%p", "") == latest then
			idx = Cache.getBookmark(chapters[i]) == true and min(i + 1, #chapters) or i
			break
		end
	end
	Catalogs.shrink()
	Cache.makeHistory(manga)
	Reader.load(chapters, idx)
	AppMode = READER
end

-------------------------------------------------------------------------------
-- input
-------------------------------------------------------------------------------

local function pressed(pad, oldpad, btn)
	return Controls.check(pad, btn) and not Controls.check(oldpad, btn)
end

function Catalogs.input(oldpad, pad, oldtouch, touch)
	if status == "MANGA" then
		if pressed(pad, oldpad, SCE_CTRL_CIRCLE) then
			status = "CATALOGS"
			Catalogs.terminate()
		elseif pressed(pad, oldpad, SCE_CTRL_SQUARE) then
			CatalogModes.show()
		elseif pressed(pad, oldpad, SCE_CTRL_TRIANGLE) then
			CatalogModes.searchPrompt()
		elseif pressed(pad, oldpad, SCE_CTRL_START) then
			local manga = currentMangaList[mangaSelector:getSelected()]
			if manga then
				if Database.check(manga) then
					Database.removeManga(manga)
					Notifications.push(Language[Settings.Language].NOTIFICATIONS.REMOVED_FROM_LIBRARY)
				else
					Database.addManga(manga)
					Cache.addManga(manga)
					Notifications.push(Language[Settings.Language].NOTIFICATIONS.ADDED_TO_LIBRARY)
				end
			end
		end
	elseif status == "CATALOGS" then
		if pressed(pad, oldpad, SCE_CTRL_TRIANGLE) then
			GlobalSearch.prompt()
		elseif pressed(pad, oldpad, SCE_CTRL_SQUARE) then
			local item = parsersList[parserSelector:getSelected()]
			if item then
				Settings.toggleFavouriteParser(item)
			end
		elseif pressed(pad, oldpad, SCE_CTRL_START) then
			SettingsFunctions.PreferredCatalogLanguage()
		end
	elseif status == "SETTINGS" then
		if pressed(pad, oldpad, SCE_CTRL_CIRCLE) then
			Settings.back()
			settingSelector:resetSelected()
			slider.Y = 0
		end
	elseif status == "IMPORT" then
		if pressed(pad, oldpad, SCE_CTRL_CIRCLE) then
			Import.back()
			importSelector:resetSelected()
		end
		if pressed(pad, oldpad, SCE_CTRL_SQUARE) then
			local item = Import.listDir()[importSelector:getSelected()]
			if item and item.active and item.name ~= "..." then
				ChapterSaver.importManga(Import.getPath(item))
				importSelector:resetSelected()
			end
		end
	elseif status == "LIBRARY" then
		if pressed(pad, oldpad, SCE_CTRL_TRIANGLE) then
			ParserManager.updateCounters()
		elseif pressed(pad, oldpad, SCE_CTRL_SQUARE) then
			cycleCategory(1)
		elseif pressed(pad, oldpad, SCE_CTRL_START) then
			Catalogs.libraryOptions()
		elseif pressed(pad, oldpad, SCE_CTRL_SELECT) then
			continueReading(currentMangaList[mangaSelector:getSelected()])
		end
	elseif status == "DOWNLOAD" then
		if pressed(pad, oldpad, SCE_CTRL_TRIANGLE) then
			ChapterSaver.clearDownloadingList()
		elseif pressed(pad, oldpad, SCE_CTRL_SQUARE) then
			local row = downloadRows()[downloadSelector:getSelected()]
			if row and row.kind == "manga" then
				deleteDownloads(row)
			end
		end
	end
	if slider.V ~= 0 or touch.x then
		Timer.reset(touchTimer)
	end
	if isGrid() then
		mangaSelector:input(#currentMangaList, oldpad, pad, touch.x)
	elseif status == "CATALOGS" then
		parserSelector:input(#parsersList, oldpad, pad, touch.x)
	elseif status == "DOWNLOAD" then
		downloadSelector:input(#downloadRows(), oldpad, pad, touch.x)
	elseif status == "SETTINGS" then
		settingSelector:input(#Settings.list(), oldpad, pad, touch.x)
	elseif status == "IMPORT" then
		importSelector:input(#Import.listDir(), oldpad, pad, touch.x)
	end
	-- touch handling -----------------------------------------------------------
	local top = isGrid() and gridTop() or LIST_TOP
	if TOUCH_MODES.MODE == TOUCH_MODES.NONE and oldtouch.x and touch.x and touch.x > X0 then
		if status == "LIBRARY" and Catalogs.hasCategoryBar() and touch.y < top and touch.y > 52 then
			-- tap on category chips
			local x = X0
			for _, tab in ipairs(categoryTabs()) do
				local w = Font.getTextWidth(FONT16, tab.name) + 24
				if touch.x >= x and touch.x <= x + w then
					if tab.id ~= currentCategory then
						currentCategory = tab.id
						cycleCategory(0)
					end
					break
				end
				x = x + w + 8
			end
			TOUCH_MODES.MODE = TOUCH_MODES.SLIDE
		else
			TOUCH_MODES.MODE = TOUCH_MODES.READ
			slider.TouchY = touch.y
		end
	elseif TOUCH_MODES.MODE ~= TOUCH_MODES.NONE and not touch.x then
		if oldtouch.x and TOUCH_MODES.MODE == TOUCH_MODES.READ and oldtouch.y > top then
			if isGrid() then
				local col = floor((oldtouch.x - GRID_X) / PITCH_X)
				local row = floor((oldtouch.y - top + slider.Y) / PITCH_Y)
				local inCardX = (oldtouch.x - GRID_X) - col * PITCH_X <= MANGA_WIDTH
				local inCardY = (oldtouch.y - top + slider.Y) - row * PITCH_Y <= MANGA_HEIGHT
				if col >= 0 and col < COLS and inCardX and inCardY then
					local i = row * COLS + col + 1
					if currentMangaList[i] then
						selectManga(i)
					end
				end
			elseif oldtouch.x > X0 and oldtouch.x < X1 then
				local id = floor((oldtouch.y - LIST_TOP + slider.Y) / ROW_H) + 1
				if status == "CATALOGS" then
					selectParser(id)
				elseif status == "DOWNLOAD" then
					selectDownloadRow(downloadRows()[id])
				elseif status == "SETTINGS" then
					if Settings.list()[id] then
						selectSetting(id)
					end
				elseif status == "IMPORT" then
					if oldtouch.x < X1 - 70 then
						if Import.listDir()[id] then
							selectImport(id)
						end
					else
						local item = Import.listDir()[id]
						if item and item.active and item.name ~= "..." then
							ChapterSaver.importManga(Import.getPath(item))
							importSelector:resetSelected()
						end
					end
				end
			end
		end
		TOUCH_MODES.MODE = TOUCH_MODES.NONE
	end
	local newItemID = 0
	if TOUCH_MODES.MODE == TOUCH_MODES.READ then
		if abs(slider.V) > 0.1 or abs(slider.TouchY - touch.y) > 10 then
			TOUCH_MODES.MODE = TOUCH_MODES.SLIDE
		elseif not isGrid() and oldtouch.x > X0 and oldtouch.x < X1 and oldtouch.y > LIST_TOP then
			local id = floor((oldtouch.y - LIST_TOP + slider.Y) / ROW_H) + 1
			local count = (status == "CATALOGS" and #parsersList) or (status == "DOWNLOAD" and #downloadRows()) or (status == "SETTINGS" and #Settings.list()) or (status == "IMPORT" and #Import.listDir()) or 0
			if id >= 1 and id <= count then
				newItemID = id
			end
		end
	end
	if slider.ItemID > 0 and newItemID > 0 and slider.ItemID ~= newItemID then
		TOUCH_MODES.MODE = TOUCH_MODES.SLIDE
	else
		slider.ItemID = newItemID
	end
	if TOUCH_MODES.MODE == TOUCH_MODES.SLIDE and oldtouch.x and touch.x and touch.x > X0 then
		slider.V = oldtouch.y - touch.y
	end
end

-------------------------------------------------------------------------------
-- hint panels
-------------------------------------------------------------------------------

function GenPanels()
	local P = Language[Settings.Language].PANEL
	local O = Language[Settings.Language].OTAKIO
	Panels["MANGA"] = {"L\\R", "Square", "Cross", "Start", "Triangle", "Circle",
		["L\\R"] = P.CHANGE_SECTION, Square = P.MODE, Triangle = Language[Settings.Language].APP.SEARCH, Circle = P.BACK, Cross = P.SELECT, Start = O.ADD_REMOVE}
	Panels["IMPORT"] = {"L\\R", "Cross", "Square", "Circle",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.SELECT}
	Panels["LIBRARY"] = {"L\\R", "Cross", "Select", "Square", "Triangle", "Start",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.SELECT, Select = O.CONTINUE_READING, Square = O.CATEGORY, Triangle = P.UPDATE, Start = O.OPTIONS}
	Panels["CATALOGS"] = {"L\\R", "Cross", "Square", "Triangle", "Start",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.SELECT, Square = O.PIN, Triangle = O.GLOBAL_SEARCH, Start = O.LANGUAGE}
	Panels["DOWNLOAD"] = {"L\\R", "Cross", "Square", "Triangle",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.CANCEL, Triangle = O.CANCEL_ALL}
	Panels["SETTINGS"] = {"L\\R", "Cross", "Circle",
		["L\\R"] = P.CHANGE_SECTION, Cross = P.SELECT}
	if Screens and Screens.genPanels then
		Screens.genPanels()
	end
end

-------------------------------------------------------------------------------
-- update
-------------------------------------------------------------------------------

local function clampSlider(contentHeight, viewHeight)
	local maxY = max(0, contentHeight - viewHeight)
	if slider.Y < 0 then
		slider.Y = 0
		slider.V = 0
	elseif slider.Y > maxY then
		slider.Y = maxY
		slider.V = 0
		return true
	end
	return false
end

local function requestMorePages()
	if status == "MANGA" and not currentMangaList.NoPages and currentParser and not ParserManager.check(currentMangaList) then
		if page == 1 and #currentMangaList == 0 and CatalogModes.getMangaMode() == "Popular" then
			-- the background status check may have just fetched this very page: show it at once
			local list = SourceStatus.takeFreshPopular(currentParser)
			if list then
				for i = 1, #list do
					currentMangaList[i] = list[i]
				end
				currentMangaList.NoPages = list.NoPages
				page = page + 1
				return
			end
		end
		ParserManager.getMangaListAsync(CatalogModes.getMangaMode(), currentParser, page, currentMangaList, CatalogModes.getSearchData(), CatalogModes.getTagsData())
		page = page + 1
	end
end

function Catalogs.update()
	if abs(slider.V) < 1 then
		slider.V = 0
	else
		slider.Y = slider.Y + slider.V
		slider.V = slider.V / 1.12
	end
	if isGrid() then
		if status == "LIBRARY" then
			local v = Database.getVersion() .. ":" .. currentCategory
			if listVersion ~= v then
				local newList = Database.getMangaList(currentCategory)
				if newList ~= currentMangaList then
					-- keep images of manga that stay in the list
					currentMangaList = newList
					downloadedImages = {}
					for i, m in ipairs(currentMangaList) do
						if m.ImageDownload then
							downloadedImages[#downloadedImages + 1] = i
						end
					end
				end
				listVersion = v
			end
		end
		UpdateMangas()
		if ParserManager.check(currentMangaList) then
			manga_load_status = 1
		end
		local top = gridTop()
		local viewH = 524 - top
		local item = mangaSelector:getSelected()
		if item ~= 0 then
			local rowY = floor((item - 1) / COLS) * PITCH_Y
			local target = rowY + MANGA_HEIGHT / 2 - viewH / 2
			slider.Y = slider.Y + (target - slider.Y) / 4
			if status == "MANGA" and item > #currentMangaList - COLS * 2 then
				requestMorePages()
			end
		end
		local contentH = ceil(#currentMangaList / COLS) * PITCH_Y
		if clampSlider(contentH, viewH) then
			requestMorePages()
		end
		if status == "MANGA" and #currentMangaList == 0 then
			requestMorePages()
		end
	else
		local list, item = {}, 0
		if status == "CATALOGS" then
			parsersList = GetParserList()
			list = parsersList
			item = parserSelector:getSelected()
			Panels["CATALOGS"].Square = parsersList[item] and (Settings.FavouriteParsers[parsersList[item].ID] and L().UNPIN or L().PIN)
		elseif status == "DOWNLOAD" then
			list = downloadRows()
			item = downloadSelector:getSelected()
			local row = list[item]
			Panels["DOWNLOAD"].Cross = row and (row.kind == "task" and Language[Settings.Language].PANEL.CANCEL or row.kind == "manga" and Language[Settings.Language].PANEL.SELECT) or nil
			Panels["DOWNLOAD"].Square = row and row.kind == "manga" and Language[Settings.Language].PANEL.DELETE or nil
			Panels["DOWNLOAD"].Triangle = #ChapterSaver.getDownloadingList() > 0 and L().CANCEL_ALL or nil
		elseif status == "SETTINGS" then
			list = Settings.list()
			Panels["SETTINGS"].Circle = Settings.inTab() and Language[Settings.Language].PANEL.BACK or nil
			Panels["SETTINGS"].Cross = #list > 0 and Language[Settings.Language].PANEL.SELECT or nil
			item = settingSelector:getSelected()
		elseif status == "IMPORT" then
			list = Import.listDir()
			item = importSelector:getSelected()
			Panels["IMPORT"].Square = list[item] and Import.canImport(list[item]) and Language[Settings.Language].PANEL.IMPORT or nil
			Panels["IMPORT"].Circle = Import.canBack() and Language[Settings.Language].PANEL.BACK or nil
		end
		local viewH = 524 - LIST_TOP
		if item ~= 0 then
			local target = (item - 0.5) * ROW_H - viewH / 2
			slider.Y = slider.Y + (target - slider.Y) / 4
		end
		clampSlider(#list * ROW_H + (status == "SETTINGS" and Settings.getTab() == "About" and CREDITS_H + 24 or 0), viewH)
	end
	Panel.set(Panels[status] or {})
end

-------------------------------------------------------------------------------
-- drawing
-------------------------------------------------------------------------------

local function drawEmpty(title, subtitle)
	UI.emptyState((X0 + X1) / 2, 290, title, subtitle, smile)
end

local function langName(code)
	local P = Language[Settings.Language].PARSERS
	return P[code] or code or ""
end

local function drawRowBase(i, y, selected)
	if selected or slider.ItemID == i then
		UI.listHighlight(X0, y + 2, X1, y + ROW_H - 4, selected)
	end
end

---Value shown on the right side / subtitle of a settings row
local function settingInfo(task)
	local LS = Language[Settings.Language]
	local YORN = LS.YORN
	local bool = {
		ShowNSFW = Settings.NSFW, HideInOffline = Settings.HideInOffline, SkipFontLoading = Settings.SkipFontLoad,
		DoubleTapReader = Settings.DoubleTapReader, RefreshLibAtStart = Settings.RefreshLibAtStart,
		SilentDownloads = Settings.SilentDownloads,
		SkipCacheChapterChecking = Settings.SkipCacheChapterChecking, PressEdgesToChangePage = Settings.PressEdgesToChangePage,
		LoadSummary = Settings.LoadSummary, AutoUpdateExtensions = Settings.AutoUpdateExtensions,
		AutoDownloadNew = Settings.AutoDownloadNew, Incognito = Settings.Incognito, DataSaver = Settings.DataSaver,
		ReaderPageNumber = Settings.ReaderPageNumber ~= false,
		CheckExtUpdatesAtStart = Settings.CheckExtUpdatesAtStart ~= false,
		AppAutoUpdate = Settings.AppAutoUpdate ~= false
	}
	if bool[task] ~= nil then
		return nil, bool[task]
	end
	if task == "Language" then
		return LanguageNames[Settings.Language][Settings.Language]
	elseif task == "ReaderOrientation" then
		return LS.READER[Settings.Orientation]
	elseif task == "PreferredCatalogLanguage" then
		return LS.PARSERS[Settings.ParserLanguage] or Settings.ParserLanguage
	elseif task == "SourceLanguages" then
		return Settings.sourceLanguagesText()
	elseif task == "ZoomReader" then
		return LS.READER[Settings.ZoomReader]
	elseif task == "ChangeUI" then
		return LS.THEME[Settings.Theme] or Settings.Theme
	elseif task == "LibrarySorting" then
		return L().SORT_NAMES[Settings.LibrarySorting] or Settings.LibrarySorting
	elseif task == "LibraryFilter" then
		return L().FILTER_NAMES[Settings.LibraryFilter or "All"]
	elseif task == "ChapterSorting" then
		return Settings.ChapterSorting
	elseif task == "ConnectionTime" then
		return tostring(Settings.ConnectionTime)
	elseif task == "Proxy" then
		return Settings.UseProxy and (Settings.ProxyIP .. ":" .. Settings.ProxyPort) or L().OFF
	elseif task == "LeftStickDeadZone" then
		return tostring(Settings.LeftStickDeadZone)
	elseif task == "LeftStickSensitivity" then
		return tostring(Settings.LeftStickSensitivity)
	elseif task == "RightStickDeadZone" then
		return tostring(Settings.RightStickDeadZone)
	elseif task == "RightStickSensitivity" then
		return tostring(Settings.RightStickSensitivity)
	elseif task == "ChangingPageButtons" then
		return LS.PAGINGCONTROLS[Settings.ChangingPageButtons]
	elseif task == "ShowVersion" then
		return Config.VERSION_NAME
	elseif task == "CheckAppUpdate" then
		return AppUpdate.status()
	elseif task == "ReaderDirection" then
		return LS.READER[Settings.ReaderDirection]
	elseif task == "SwapXO" then
		return LS.SETTINGS[Settings.KeyType]
	elseif task == "SaveDataPath" then
		return Settings.SaveDataPath
	elseif task == "ImageProxy" then
		return L().PROXY_MODES[Settings.ImageProxy or "Auto"]
	elseif task == "SaveImageFormat" then
		return Settings.SaveImageFormat or "PNG"
	elseif task == "PreloadPages" then
		return tostring(Settings.PreloadPages or 3)
	elseif task == "ExtensionRepos" then
		return string.format(L().N_REPOS, #Extensions.getRepos())
	elseif task == "EditCategories" then
		return string.format(L().N_CATEGORIES, #Database.getCategories())
	elseif task == "ClearChapters" then
		if chaptersFolderSize == nil then
			chaptersFolderSize = 0
			local function getDirectorySize(dir)
				local d = listDirectory(dir) or {}
				for k = 1, #d do
					if d[k].directory then
						getDirectorySize(dir .. "/" .. d[k].name)
					else
						chaptersFolderSize = chaptersFolderSize + d[k].size
					end
				end
			end
			getDirectorySize("ux0:data/otakio/chapters")
			if doesDirExist("uma0:data/otakio/chapters") then
				getDirectorySize("uma0:data/otakio/chapters")
			end
		end
		if sure_clear_chapters > 0 then
			return LS.SETTINGS.PressAgainToAccept, nil, COLOR_DANGER
		end
		return BytesToStr(chaptersFolderSize)
	elseif task == "ClearAllCache" then
		if cacheFolderSize == nil then
			cacheFolderSize = 0
			local function getDirectorySize(dir)
				local d = listDirectory(dir) or {}
				for j = 1, #d do
					if d[j].directory then
						getDirectorySize(dir .. "/" .. d[j].name)
					else
						cacheFolderSize = cacheFolderSize + d[j].size
					end
				end
			end
			getDirectorySize("ux0:data/otakio/cache")
		end
		if sure_clear_all_cache > 0 then
			return LS.SETTINGS.PressAgainToAccept, nil, COLOR_DANGER
		end
		return BytesToStr(cacheFolderSize)
	elseif task == "ClearLibrary" and sure_clear_library > 0 then
		return LS.SETTINGS.PressAgainToAccept, nil, COLOR_DANGER
	elseif task == "ClearCache" and sure_clear_cache > 0 then
		return LS.SETTINGS.PressAgainToAccept, nil, COLOR_DANGER
	end
	return nil
end

local function drawSettings(item)
	local LS = Language[Settings.Language]
	local list = Settings.list()
	local first = max(1, floor(slider.Y / ROW_H) + 1)
	for i = first, min(#list, first + 8) do
		local task = list[i]
		local y = LIST_TOP + (i - 1) * ROW_H - slider.Y
		drawRowBase(i, y, item == i)
		do
			local title = LS.SETTINGS[task] or task
			local desc = LS.SETTINGS_DESCRIPTION[task]
			local value, toggle, valueColor = settingInfo(task)
			local isTab = Settings.isTab(task)
			local textW = X1 - X0 - 60 - (toggle ~= nil and 60 or 0) - (value and 220 or 0)
			if desc then
				UI.text(FONT20, X0 + 20, y + 10, title, COLOR_FONT, textW)
				UI.text(FONT16, X0 + 20, y + 40, desc, COLOR_SUBFONT, textW)
			else
				UI.text(FONT20, X0 + 20, y + 24, title, COLOR_FONT, textW)
			end
			if toggle ~= nil then
				UI.toggle(X1 - 64, y + 24, toggle)
			elseif value then
				local v = UI.ellipsize(FONT16, value, 240)
				UI.textRight(FONT16, X1 - (isTab and 40 or 20), y + 26, v, valueColor or COLOR_ACCENT)
			end
			if isTab then
				UI.textRight(FONT20, X1 - 16, y + 22, "›", COLOR_SUBFONT)
			end
		end
	end
	if #list == 0 then
		drawEmpty(L().NOTHING_HERE)
	end
end

---Credits card under the About rows
local function drawCredits(y)
	local w = X1 - X0
	UI.roundRect(X0, y, X1, y + CREDITS_H, 14, COLOR_SURFACE)
	Font.print(BONT30, X0 + 24, y + 16, Config.APP_NAME, COLOR_ACCENT)
	UI.text(FONT16, X0 + 24 + Font.getTextWidth(BONT30, Config.APP_NAME) + 12, y + 30, Config.VERSION_NAME, COLOR_SUBFONT)
	UI.text(FONT16, X0 + 24, y + 58, L().ABOUT_TAGLINE, COLOR_FONT, w - 48)
	Graphics.fillRect(X0 + 24, X1 - 24, y + 88, y + 89, COLOR_DIVIDER)
	local sections = {
		{L().CREDITS_AUTHOR, "Garryth69 · " .. L().CREDITS_AI},
		{L().CREDITS_BASED_ON, "NOBORU — Creckeryop"},
		{L().CREDITS_ENGINE, "lpp-vita (Rinnegatamante, Creckeryop) · VitaSDK · vita2d (xerpi)", "LuaJIT · curl · OpenSSL · libwebp"},
		{L().CREDITS_SOURCES, L().CREDITS_SOURCES_TEXT},
		{L().CREDITS_TRANSLATIONS, "SamuEDL (ES) · theHeroGAC, Rinnegatamante (IT) · Samilop Iter (FR)", "lukrynka (DE) · rutantan (PT-BR) · Creckeryop (RU) · " .. L().CREDITS_REVISED},
	}
	local ty = y + 100
	for _, s in ipairs(sections) do
		UI.text(BONT16, X0 + 24, ty, s[1], COLOR_ACCENT, w - 48)
		ty = ty + 24
		for i = 2, #s do
			UI.text(FONT16, X0 + 24, ty, s[i], COLOR_FONT, w - 48)
			ty = ty + 22
		end
		ty = ty + 8
	end
	UI.text(FONT13, X0 + 24, y + CREDITS_H - 30, "GPLv3 · " .. L().CREDITS_SUPPORT, COLOR_SUBFONT, w - 48)
end

local function drawSources(item)
	local list = parsersList
	if #list == 0 then
		if Extensions.countInstalled() == 0 then
			drawEmpty(L().NO_SOURCES, L().NO_SOURCES_HINT)
		else
			drawEmpty(L().NO_SOURCES_LANG, L().NO_SOURCES_LANG_HINT)
		end
		return
	end
	local first = max(1, floor(slider.Y / ROW_H) + 1)
	local installed = Extensions.getInstalled()
	for i = first, min(#list, first + 8) do
		local parser = list[i]
		local y = LIST_TOP + (i - 1) * ROW_H - slider.Y
		drawRowBase(i, y, item == i)
		-- monogram avatar
		local cx = X0 + 40
		UI.roundRect(cx - 22, y + 13, cx + 22, y + 57, 12, COLOR_SURFACE2)
		UI.textCenter(BONT30, cx, y + 16, (parser.Name or "?"):match("[%w]") or "?", COLOR_ACCENT)
		local extId = parser.ExtensionID
		SourceStatus.drawDot(cx + 20, y + 55, SourceStatus.of(extId or parser.ID, extId and (Extensions.getEntry(extId) or installed[extId])))
		local tx = X0 + 76
		local name = UI.ellipsize(FONT20, parser.Name, 420)
		Font.print(FONT20, tx, y + 10, name, COLOR_FONT)
		local w = tx + Font.getTextWidth(FONT20, name) + 8
		if Settings.FavouriteParsers[parser.ID] then
			UI.icon(MiniStarIcon, w, y + 16, COLOR_ACCENT)
			w = w + 22
		end
		if parser.NSFW then
			w = w + UI.tag(w, y + 13, "18+", COLOR_DANGER, COLOR_WHITE) + 6
		end
		if parser.isNew then
			UI.tag(w, y + 13, L().NEW, COLOR_ACCENT, COLOR_ON_ACCENT)
		end
		UI.text(FONT16, tx, y + 40, langName(parser.Lang) .. "  ·  " .. (parser.Link or ""):gsub("^https?://", ""), COLOR_SUBFONT, 640)
		UI.textRight(FONT16, X1 - 16, y + 12, "v" .. tostring(parser.Version), COLOR_SUBFONT)
	end
end

local function drawImport(item)
	local LS = Language[Settings.Language]
	local list = Import.listDir()
	if Import.isEmpty() then
		drawEmpty(L().IMPORT_EMPTY, L().IMPORT_HELP)
	end
	local first = max(1, floor(slider.Y / ROW_H) + 1)
	for i = first, min(#list, first + 8) do
		local object = list[i]
		local y = LIST_TOP + (i - 1) * ROW_H - slider.Y
		drawRowBase(i, y, item == i)
		local name = object.name
		local color = COLOR_FONT
		if not object.active then
			if object.directory then
				name = "*" .. LS.IMPORT.EXTERNAL_MEMORY .. "*"
				color = COLOR_ACCENT
			else
				color = COLOR_SUBFONT
			end
		end
		UI.text(FONT20, X0 + 20, y + 10, name, color, X1 - X0 - 120)
		local textDis = object.name == "..." and LS.IMPORT.GOBACK or object.directory and (object.active and LS.IMPORT.FOLDER or LS.IMPORT.DRIVE .. ' "' .. object.name .. '"') or object.active and LS.IMPORT.FILE or LS.IMPORT.UNSUPFILE
		UI.text(FONT16, X0 + 20, y + 40, textDis, COLOR_SUBFONT, X1 - X0 - 120)
		if object.active and object.name ~= "..." then
			UI.icon(ImportIcon, X1 - 48, y + 22, COLOR_ACCENT)
		end
	end
end

local function drawDownloads(item)
	local list = downloadRows()
	if #list == 0 then
		drawEmpty(Language[Settings.Language].MESSAGE.NO_DOWNLOADING_MANGA, L().DOWNLOADS_HINT)
		return
	end
	local first = max(1, floor(slider.Y / ROW_H) + 1)
	for i = first, min(#list, first + 8) do
		local row = list[i]
		local y = LIST_TOP + (i - 1) * ROW_H - slider.Y
		if row.kind == "section" then
			UI.text(BONT16, X0 + 20, y + ROW_H - 30, row.label, COLOR_ACCENT)
			Graphics.fillRect(X0 + 20, X1 - 20, y + ROW_H - 6, y + ROW_H - 5, COLOR_DIVIDER)
		elseif row.kind == "manga" then
			drawRowBase(i, y, item == i)
			local m = row.manga
			if not m.ImageDownload then
				loadMangaImage(m)
				m.ImageDownload = true
				downloadThumbs[#downloadThumbs + 1] = m
			end
			if m.Image and m.Image.e then
				DrawDetailsManga(X0 + 14 + 21, y + 4 + 32, m, 64 / MANGA_HEIGHT)
			else
				UI.shimmer(X0 + 14, y + 4, X0 + 56, y + 68)
			end
			local parser = GetParserByID(m.ParserID)
			UI.text(FONT20, X0 + 70, y + 10, m.Name or "?", COLOR_FONT, X1 - X0 - 250)
			UI.text(FONT16, X0 + 70, y + 40, parser and parser.Name or m.ParserID or "", COLOR_SUBFONT, X1 - X0 - 250)
			UI.textRight(FONT16, X1 - 20, y + 26, string.format(L().N_CHAPTERS, row.count), COLOR_SUCCESS)
		else
			local task = row.task
			drawRowBase(i, y, item == i)
			UI.text(FONT20, X0 + 20, y + 6, task.MangaName, COLOR_FONT, X1 - X0 - 160)
			UI.text(FONT16, X0 + 20, y + 32, task.ChapterName, COLOR_SUBFONT, X1 - X0 - 160)
			local pageCount = task.page_count or 0
			local pg = task.page or 0
			if pageCount > 0 then
				UI.progress(X0 + 20, y + 56, X1 - 120, 6, pg / pageCount)
				UI.textRight(FONT16, X1 - 20, y + 46, math.ceil(pg) .. "/" .. pageCount, COLOR_SUBFONT)
			else
				UI.textRight(FONT16, X1 - 20, y + 46, i == 1 and L().PREPARING or L().QUEUED, COLOR_SUBFONT)
			end
		end
	end
end

local function drawGrid()
	local top = gridTop()
	if #currentMangaList == 0 then
		if status == "LIBRARY" then
			if Database.count() == 0 then
				drawEmpty(L().LIBRARY_EMPTY, L().LIBRARY_EMPTY_HINT)
			else
				drawEmpty(L().LIBRARY_FILTER_EMPTY, L().LIBRARY_FILTER_EMPTY_HINT)
			end
		elseif status == "MANGA" then
			if ParserManager.check(currentMangaList) or manga_load_status == 0 then
				-- skeleton grid while the first page loads
				for i = 1, COLS * 2 do
					local x = GRID_X + ((i - 1) % COLS) * PITCH_X
					local y = top + floor((i - 1) / COLS) * PITCH_Y
					UI.shimmer(x, y, x + MANGA_WIDTH, y + MANGA_HEIGHT)
				end
			else
				drawEmpty(Language[Settings.Language].MESSAGE.NO_CATALOG_MANGA)
			end
		end
		return
	end
	local first = max(1, floor(slider.Y / PITCH_Y) * COLS + 1)
	for i = first, min(#currentMangaList, first + COLS * 3 - 1) do
		local x = GRID_X + ((i - 1) % COLS) * PITCH_X
		local y = top - slider.Y + floor((i - 1) / COLS) * PITCH_Y
		if y < 544 and y + MANGA_HEIGHT > top - 40 then
			local manga = currentMangaList[i]
			DrawManga(x + MANGA_WIDTH / 2, y + MANGA_HEIGHT / 2, manga)
			-- badges
			local bx = x + 6
			if status == "LIBRARY" then
				local c = manga.Counter
				if c and c > 0 then
					bx = bx + UI.tag(bx, y + 6, tostring(c), COLOR_ACCENT, COLOR_ON_ACCENT) + 4
				end
				if Settings.ShowDownloadBadge ~= false and ChapterSaver.hasDownloadsForManga(manga) then
					UI.tag(bx, y + 6, "↓", COLOR_SUCCESS, COLOR_BLACK)
				end
			elseif status == "MANGA" and Database.check(manga) then
				UI.tag(bx, y + 6, L().IN_LIBRARY, COLOR_ACCENT, COLOR_ON_ACCENT)
			end
		end
	end
	local item = mangaSelector:getSelected()
	if item ~= 0 then
		local x = GRID_X + ((item - 1) % COLS) * PITCH_X
		local y = top - slider.Y + floor((item - 1) / COLS) * PITCH_Y
		UI.focusRing(x, y, x + MANGA_WIDTH, y + MANGA_HEIGHT)
	end
	-- loading more indicator at the end of the catalog
	if status == "MANGA" and ParserManager.check(currentMangaList) then
		UI.spinner((X0 + X1) / 2, 510, 10)
	end
	UI.scrollbar(X1 + 6, top, 520, slider.Y, ceil(#currentMangaList / COLS) * PITCH_Y, 524 - top)
end

local function drawHeader()
	local LS = Language[Settings.Language]
	if status == "LIBRARY" then
		UI.header(L().LIBRARY, Database.count() > 0 and tostring(Database.count()) or nil)
		if LibraryRefresh.current then
			local text = string.format(L().REFRESHING, LibraryRefresh.current, LibraryRefresh.total)
			UI.textRight(FONT16, X1 - 30, 22, text, COLOR_SUBFONT)
			UI.spinner(X1 - 12, 32, 7)
		end
		local filter = Settings.LibraryFilter or "All"
		if filter ~= "All" and not LibraryRefresh.current then
			UI.textRight(FONT16, X1, 22, L().FILTER .. ": " .. (L().FILTER_NAMES[filter] or filter), COLOR_ACCENT)
		end
		if Catalogs.hasCategoryBar() then
			-- background behind chips so the grid scrolls under them
			local x = X0
			for _, tab in ipairs(categoryTabs()) do
				x = x + UI.chip(x, 58, tab.name, tab.id == currentCategory) + 8
			end
		end
	elseif status == "MANGA" then
		local mode = CatalogModes.getMangaMode()
		local sub = LS.MODES[mode] or mode
		if mode == "Search" then
			sub = sub .. ' "' .. Engines.decodeSearch(CatalogModes.getSearchData() or "") .. '"'
		end
		UI.header(currentParser and currentParser.Name or "", sub)
	elseif status == "CATALOGS" then
		UI.header(L().BROWSE, LS.PARSERS[Settings.ParserLanguage] or Settings.ParserLanguage)
	elseif status == "DOWNLOAD" then
		local n = #ChapterSaver.getDownloadingList()
		UI.header(L().DOWNLOADS, n > 0 and tostring(n) or nil)
	elseif status == "SETTINGS" then
		local tab = Settings.getTab()
		if Settings.inTab() then
			UI.header(LS.SETTINGS[tab] or tab)
		else
			UI.header(L().MORE)
		end
	elseif status == "IMPORT" then
		UI.header(L().IMPORT, Import.getCurrentPathLabel and Import.getCurrentPathLabel() or nil)
	end
end

function Catalogs.draw()
	Graphics.fillRect(Config.RAIL_WIDTH, 960, 0, 544, COLOR_BACK)
	if status == "SETTINGS" then
		drawSettings(settingSelector:getSelected())
		UI.scrollbar(X1 + 6, LIST_TOP, 520, slider.Y, #Settings.list() * ROW_H, 524 - LIST_TOP)
		if Settings.inTab() and Settings.getTab() == "About" then
			drawCredits(LIST_TOP + #Settings.list() * ROW_H - slider.Y + 12)
		end
	elseif status == "CATALOGS" then
		drawSources(parserSelector:getSelected())
		UI.scrollbar(X1 + 6, LIST_TOP, 520, slider.Y, #parsersList * ROW_H, 524 - LIST_TOP)
	elseif status == "IMPORT" then
		drawImport(importSelector:getSelected())
		UI.scrollbar(X1 + 6, LIST_TOP, 520, slider.Y, #Import.listDir() * ROW_H, 524 - LIST_TOP)
	elseif status == "DOWNLOAD" then
		drawDownloads(downloadSelector:getSelected())
	elseif isGrid() then
		drawGrid()
	end
	-- header band (drawn last so content scrolls beneath it)
	local headerH = isGrid() and gridTop() - 6 or LIST_TOP - 4
	Graphics.fillRect(Config.RAIL_WIDTH, 960, 0, headerH, COLOR_BACK)
	drawHeader()
end

---Frees all images loaded in catalog
function Catalogs.shrink()
	for _, i in ipairs(downloadedImages) do
		freeMangaImage(currentMangaList[i])
	end
	collectgarbage("collect")
	ParserManager.remove(currentMangaList)
	Loading.setStatus("NONE")
end

function Catalogs.terminate()
	Catalogs.shrink()
	downloadedImages = {}
	if status ~= "LIBRARY" then
		currentMangaList = {}
	end
	listVersion = -1
	page = 1
	slider.Y = 0
	slider.V = 0
	manga_load_status = 0
	mangaSelector:resetSelected()
	parserSelector:resetSelected()
	downloadSelector:resetSelected()
	settingSelector:resetSelected()
	importSelector:resetSelected()
end

function Catalogs.getStatus()
	return status
end

---@param newStatus string
function Catalogs.setStatus(newStatus)
	if status == "LIBRARY" and newStatus ~= "LIBRARY" then
		currentMangaList = {}
	end
	if status == "DOWNLOAD" and newStatus ~= "DOWNLOAD" then
		freeDownloadThumbs()
	end
	status = newStatus
	downloadedCache = nil
	chaptersFolderSize = nil
	cacheFolderSize = nil
	sure_clear_library = 0
	sure_clear_chapters = 0
	sure_clear_cache = 0
	manga_load_status = 0
	sure_clear_all_cache = 0
	smile = smilesList[math.random(1, #smilesList)]
	Catalogs.terminate()
end

-------------------------------------------------------------------------------
-- Category editor (Settings > Library > Edit categories, or library options)
-------------------------------------------------------------------------------
CategoryEditor = {}

local function askName(default)
	local name = TextInput(L().CATEGORY_NAME, default or "", 32)
	if name then
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name ~= "" then
			return name
		end
	end
end

function CategoryEditor.open()
	local items = {{label = "+ " .. L().ADD_CATEGORY, value = "add"}}
	for _, c in ipairs(Database.getCategories()) do
		items[#items + 1] = {label = c.name, value = c.id}
	end
	Dialog.menu(L().EDIT_CATEGORIES, items, function(item)
		if item.value == "add" then
			local name = askName()
			if name then
				Database.addCategory(name)
			end
			CategoryEditor.open()
		else
			local id = item.value
			Dialog.menu(item.label, {
				{label = L().RENAME, value = "rename"},
				{label = L().MOVE_UP, value = "up"},
				{label = L().MOVE_DOWN, value = "down"},
				{label = L().DELETE, value = "delete", danger = true}
			}, function(action)
				if action.value == "rename" then
					local name = askName(item.label)
					if name then
						Database.renameCategory(id, name)
					end
					CategoryEditor.open()
				elseif action.value == "up" or action.value == "down" then
					Database.moveCategory(id, action.value == "up" and -1 or 1)
					CategoryEditor.open()
				elseif action.value == "delete" then
					Dialog.confirm(L().DELETE_CATEGORY_Q, item.label, function()
						Database.removeCategory(id)
						if currentCategory == id then
							currentCategory = 0
						end
						CategoryEditor.open()
					end)
				end
			end)
		end
	end)
end

---Assign categories to a manga (from details screen)
function CategoryEditor.assign(manga)
	local cats = Database.getCategories()
	if #cats == 0 then
		CategoryEditor.open()
		return
	end
	local current = Database.getMangaCategories(manga)
	local items = {}
	for i, c in ipairs(cats) do
		items[i] = {label = c.name, checked = current[c.id] == true, id = c.id}
	end
	Dialog.checklist(L().SET_CATEGORIES, items, function(result)
		local set = {}
		for _, it in ipairs(result) do
			if it.checked then
				set[it.id] = true
			end
		end
		Database.setMangaCategories(manga, set)
	end)
end
