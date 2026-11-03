---Reader page actions (menu icon / Triangle while reading): per-manga reader layout,
---use the page as cover, save the page to the memory card
Extra = {}

local doesFileExist = System.doesFileExist
local copyFile = CopyFile
local getTime = System.getTime
local getDate = System.getDate
local getImageFormat = System.getImageFormat
local rename = System.rename
local last_unique = nil
local extractFromZip = System.extractFromZip

-- captured at load: main.lua later sandboxes System down to what extensions may use
local convertImage = System.convertImage
local deleteFile = System.deleteFile
local FORMAT_EXT = {PNG = "png", JPEG = "jpg", WebP = "webp"}

---Gives the saved page its final name, converted at full resolution by the engine to the format chosen in
---Settings.SaveImageFormat (PNG by default); if the conversion fails the page keeps the source's format
local function finishSave(tmp, base)
	if not doesFileExist(tmp) then
		return
	end
	local format = getImageFormat(tmp)
	local ext = (format == nil or format == "jpeg") and "jpg" or format
	local target = FORMAT_EXT[Settings.SaveImageFormat or "PNG"] or "png"
	if ext ~= target and convertImage and convertImage(tmp, base .. "." .. target, target) then
		deleteFile(tmp)
		ext = target
	else
		rename(tmp, base .. "." .. ext)
	end
	Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.END_DOWNLOAD, "image", base .. "." .. ext), 1000)
end

local function pageAction(action, selectedManga)
	if action == "cover" then
		local page = Reader.getCurrentPageImageLink()
		if page then
			local cacheKey = Cache.getKey(selectedManga)
			if cacheKey == nil then
				Cache.addManga(selectedManga)
				cacheKey = Cache.getKey(selectedManga)
				if cacheKey == nil then
					return
				end
				Cache.save()
			end
			local tempTable = {}
			if page.Extract then
			elseif page.Path then
				CustomCovers.setMangaCover(selectedManga, page)
				copyFile(page.Path:find("^...?0:") and page.Path or ("ux0:data/otakio/" .. page.Path), "ux0:data/otakio/cache/" .. cacheKey .. "/custom_cover.image")
				Notifications.push(Language[Settings.Language].NOTIFICATIONS.COVER_SET_COMPLETED)
			elseif page.ParserID then
				CustomCovers.setMangaCover(selectedManga, page)
				Threads.insertTask(
					tempTable,
					{
						Type = "function",
						OnComplete = function()
							ParserManager.getPageImage(page.ParserID, page.Link, tempTable)
							while (ParserManager.check(tempTable)) do
								coroutine.yield(false)
							end
							Threads.insertTask(
								tempTable,
								{
									Type = "FileDownload",
									Link = tempTable.Link,
									Path = "ux0:data/otakio/cache/" .. cacheKey .. "/custom_cover.image",
									OnComplete = function()
										Notifications.push(Language[Settings.Language].NOTIFICATIONS.COVER_SET_COMPLETED)
									end
								}
							)
						end
					}
				)
			elseif page.Link then
				CustomCovers.setMangaCover(selectedManga, page)
				Threads.insertTask(
					tempTable,
					{
						Type = "FileDownload",
						Link = page.Link,
						Path = "ux0:data/otakio/cache/" .. cacheKey .. "/custom_cover.image",
						OnComplete = function()
							Notifications.push(Language[Settings.Language].NOTIFICATIONS.COVER_SET_COMPLETED)
						end
					}
				)
			else
				return
			end
		end
	elseif action == "save" then
		local page = Reader.getCurrentPageImageLink()
		if page then
			local _, d, mo, y = getDate()
			local h, mn, s = getTime()
			local unique_name = string.format("%04d.%02d.%02d-%02d.%02d.%02d", y, mo, d, h, mn, s)
			if unique_name == last_unique then
				return
			end
			last_unique = unique_name
			local base = Settings.SaveDataPath .. ":data/otakio/pictures/" .. unique_name
			local tmp = base .. ".image"
			local tempTable = {}
			if page.Extract then
				extractFromZip(page.Path, page.Extract, tmp)
				finishSave(tmp, base)
			elseif page.Path then
				copyFile(page.Path:find("^...?0:") and page.Path or ("ux0:data/otakio/" .. page.Path), tmp)
				finishSave(tmp, base)
			elseif page.ParserID then
				Threads.insertTask(tempTable, {
					Type = "function",
					OnComplete = function()
						ParserManager.getPageImage(page.ParserID, page.Link, tempTable)
						while ParserManager.check(tempTable) do
							coroutine.yield(false)
						end
						Threads.insertTask(tempTable, {Type = "FileDownload", Link = tempTable.Link, Path = tmp, OnComplete = function()
							finishSave(tmp, base)
						end})
					end
				})
			elseif page.Link then
				Threads.insertTask(tempTable, {Type = "FileDownload", Link = page.Link, Path = tmp, OnComplete = function()
					finishSave(tmp, base)
				end})
			end
		end
	end
end

---Opens the reader menu for `manga` at `page`
function Extra.setChapters(manga, chapter, page, selected)
	if not manga or not page then
		return
	end
	local LS = Language[Settings.Language]
	local cs = CuSettings.load(manga)
	local items = {
		{label = LS.SETTINGS.ReaderOrientation, sub = LS.READER[cs.Orientation], value = "orientation"},
		{label = LS.SETTINGS.ReaderDirection, sub = LS.READER[cs.ReaderDirection], value = "direction"},
		{label = LS.SETTINGS.ZoomReader, sub = LS.READER[cs.ZoomReader], value = "zoom"}
	}
	if manga.ParserID ~= "IMPORTED" then
		items[#items + 1] = {label = LS.SETTINGS.SetPageAsCover, value = "cover"}
	end
	items[#items + 1] = {label = LS.SETTINGS.DownloadImageToMemory, value = "save"}
	Dialog.menu(manga.Name, items, function(item, index)
		local v = item.value
		if v == "orientation" or v == "direction" or v == "zoom" then
			if v == "orientation" then
				CuSettings.changeOrientation(manga)
			elseif v == "direction" then
				CuSettings.changeDirection(manga)
			else
				CuSettings.changeZoom(manga)
			end
			Reader.updateSettings()
			-- stay in the menu so the value can be cycled again
			Extra.setChapters(manga, chapter, page, index)
		else
			pageAction(v, manga)
		end
	end, selected)
end
