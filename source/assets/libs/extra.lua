---Reader page actions (menu icon / Triangle while reading): use the page as cover, save the page to the memory card.
---The menu itself is the reader settings sheet (readersheet.lua)
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
local openFile, readFile, writeFile, closeFile, sizeFile = System.openFile, System.readFile, System.writeFile, System.closeFile, System.sizeFile
local FORMAT_EXT = {PNG = "png", JPEG = "jpg", WebP = "webp"}

---Copies a file 256 KB per frame, inside a Threads job: copying a 2-3 MB page in one go froze the reader
local function copyInSteps(src, dst)
	local fin = openFile(src, FREAD)
	if not fin then
		return false
	end
	local fout = openFile(dst, FCREATE)
	if not fout then
		closeFile(fin)
		return false
	end
	local size = sizeFile(fin) or 0
	local done = 0
	while done < size do
		local chunk = readFile(fin, math.min(262144, size - done))
		if not chunk or #chunk == 0 then
			break
		end
		writeFile(fout, chunk, #chunk)
		done = done + #chunk
		if done < size then
			coroutine.yield(false)
		end
	end
	closeFile(fin)
	closeFile(fout)
	return done >= size
end

---Gives the saved page its final name. By default ("Original") the file is kept as downloaded; PNG/JPEG/WebP in
---Settings.SaveImageFormat convert it at full resolution with the engine (that takes a few seconds on the Vita). If
---the conversion fails the page keeps the source's format
local function finishSave(tmp, base)
	if not doesFileExist(tmp) then
		return
	end
	local format = getImageFormat(tmp)
	local ext = (format == nil or format == "jpeg") and "jpg" or format
	local target = FORMAT_EXT[Settings.SaveImageFormat or "Original"]
	if target and ext ~= target and convertImage and convertImage(tmp, base .. "." .. target, target) then
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
				local src = page.Path:find("^...?0:") and page.Path or ("ux0:data/otakio/" .. page.Path)
				Threads.insertTask(tempTable, {
					Type = "function",
					OnComplete = function()
						copyInSteps(src, tmp)
						finishSave(tmp, base)
					end
				})
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

---Opens the reader settings sheet for `manga` at `page` (layout, page colors, reader options, page actions)
function Extra.setChapters(manga, chapter, page)
	if not manga then
		return
	end
	ReaderSheet.open({manga = manga, chapter = chapter, page = page, onAction = function(action)
		pageAction(action, manga)
	end})
end
