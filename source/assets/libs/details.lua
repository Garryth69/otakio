Details = {}

local status = "END"
local selectedManga = nil

local slider = CreateSlider()
local deleteFile = System.deleteFile
local doesFileExist = System.doesFileExist
local isCJK = IsCJK

local descriptionString = nil
local descriptionWordList = {}

local MANGA_COVER_CENTER_POINT = CreatePoint(140, 326 / 2 + 85)
local TOUCH_MODES = TOUCH_MODES
local DESCRIPTION_WIDTH = 670
local LINE_HEIGHT = 22

local chaptersMaxHeightOffset = 0
local descriptionMaxHeightOffset = 0

local fade = 0
local oldFade = 1

local crossIcon = Image:new(Graphics.loadImage("app0:assets/icons/cross.png"))
local menuIcon = Image:new(Graphics.loadImage("app0:assets/icons/menu.png"))
local sortIcons = {
	["N->1"] = Image:new(Graphics.loadImage("app0:assets/icons/sort-9-1.png")),
	["1->N"] = Image:new(Graphics.loadImage("app0:assets/icons/sort-1-9.png"))
}

local maxMangaNameTickerTimeMs = 0
local maxMangaNameOffset = 0
local maxChapterNameTickerTimeMs = 0
local maxChapterNameOffset = 0

local fadeTimer = Timer.new()
local mangaNameTickerTimer = Timer.new()
local chapterNameTickerTimer = Timer.new()

local is_notification_showed = false
local is_description_expanded = false
local is_chapter_list_loaded_offline = false
local is_chapter_list_ready = false

local chaptersList = {}
local continueChapterNumber
local detailsSelector =
	Selector:new(
	-1,
	1,
	-3,
	3,
	function()
		return math.floor((slider.Y - 20 + 90) / 80)
	end
)

---Updates scrolling movement
local function updateScrolling()
	local selectedItem = detailsSelector.getSelected()
	if selectedItem ~= 0 then
		slider.Y = slider.Y + (selectedItem * 80 - (544 - chaptersMaxHeightOffset) / 2 - slider.Y) / 5
	end
	slider.Y = slider.Y + slider.V
	slider.V = slider.V / 1.12
	if math.abs(slider.V) < 0.1 then
		slider.V = 0
	end
	if slider.Y < -15 then
		slider.Y = -15
		slider.V = 0
	elseif slider.Y > (#chaptersList * 80 - 464 + chaptersMaxHeightOffset) then
		slider.Y = math.max(-15, #chaptersList * 80 - 464 + chaptersMaxHeightOffset)
		slider.V = 0
	end
end

local easingFunction = EaseInOutCubic

---Updates animation of fade in or out
local function updateAnimations()
	if status == "START" then
		fade = easingFunction(math.min((Timer.getTime(fadeTimer) / 500), 1))
	elseif status == "WAIT" then
		if fade == 0 then
			status = "END"
		end
		fade = 1 - easingFunction(math.min((Timer.getTime(fadeTimer) / 500), 1))
	end
	if Timer.getTime(mangaNameTickerTimer) > 3500 + maxMangaNameTickerTimeMs then
		Timer.reset(mangaNameTickerTimer)
	end
	if Timer.getTime(chapterNameTickerTimer) > 3500 + maxChapterNameTickerTimeMs then
		Timer.reset(chapterNameTickerTimer)
	end
	if ParserManager.check(chaptersList) then
		Loading.setStatus("WHITE", 580, 250)
	else
		Loading.setStatus("NONE")
	end
end

---Updates `chaptersMaxHeightOffset` depending on if description is expanded
local function updateMangaDescriptionMaxHeight()
	if #descriptionWordList > 0 then
		local linesCount = is_description_expanded and #descriptionWordList or math.min(2, #descriptionWordList)
		local finalOffset = linesCount * LINE_HEIGHT + LINE_HEIGHT + 10
		if linesCount ~= #descriptionWordList or linesCount > 2 then
			finalOffset = finalOffset + LINE_HEIGHT
			chaptersMaxHeightOffset = math.max(LINE_HEIGHT * 4 + 10, math.min(chaptersMaxHeightOffset + (math.min(LINE_HEIGHT * (linesCount + 2) + 10, 544 - 95) - chaptersMaxHeightOffset) / 8, math.min(LINE_HEIGHT * (#descriptionWordList + 2) + 10, 544 - 95)))
			if not is_description_expanded then
				descriptionMaxHeightOffset = descriptionMaxHeightOffset - descriptionMaxHeightOffset / 8
			end
		else
			chaptersMaxHeightOffset = finalOffset
		end
	else
		chaptersMaxHeightOffset = 0
	end
end

---@param newDescription string
---Updates `descriptionString` and `descriptionWordList`
---This function analizing `newDescription` and creates data to make something like `align-text:justify` on css
local function updateMangaDescription(newDescription)
	descriptionString = (newDescription or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local wordList = {}
	for word in descriptionString:gmatch("[^ ]+") do
		local newWord = ""
		-- one UTF-8 character at a time (string.sub is UTF-8 aware but restarts from the first character on each call)
		for s in it_utf8(word) do
			if isCJK(s) or s == "\n" then
				if newWord ~= "" then
					wordList[#wordList + 1] = newWord
					newWord = ""
				end
				wordList[#wordList + 1] = s
			else
				if s:match("[%.,]") then
					newWord = newWord .. s
					wordList[#wordList + 1] = newWord
					newWord = ""
				else
					newWord = newWord .. s
				end
			end
		end
		if newWord ~= "" then
			wordList[#wordList + 1] = newWord
		end
	end
	local lines = {}
	if #wordList > 0 then
		local w = 0
		lines[1] = {}
		for n = 1, #wordList do
			local word = wordList[n]
			local wordWidth = Font.getTextWidth(FONT16, word)
			if word == "\n" then
				w = 0
				lines[#lines].SpaceWidth = 4
				lines[#lines + 1] = {}
			elseif w + wordWidth + 4 > DESCRIPTION_WIDTH then
				w = wordWidth
				local spaceWidth = 0
				for i = 1, #lines[#lines] do
					spaceWidth = spaceWidth + lines[#lines][i].Width
				end
				spaceWidth = (DESCRIPTION_WIDTH - spaceWidth) / #lines[#lines]
				lines[#lines].SpaceWidth = spaceWidth
				lines[#lines + 1] = {}
			else
				w = w + wordWidth + 4
			end
			if word ~= "\n" then
				lines[#lines][#lines[#lines] + 1] = {Word = word, Width = wordWidth}
			end
		end
		lines[#lines].SpaceWidth = 4
	end
	descriptionWordList = lines
end

---Updates `chaptersList` when it's ready
local function updateChaptersList()
	if not is_chapter_list_loaded_offline and not ParserManager.check(chaptersList) then
		if #chaptersList > 0 then
			if Cache.isCached(chaptersList[1].Manga) then
				is_chapter_list_loaded_offline = true
				Cache.saveChapters(chaptersList[1].Manga, chaptersList)
			end
			local manga = chaptersList[1].Manga
			local function linkKey(l)
				return type(l) == "table" and l.Link or l
			end
			if manga.NewImageLink and not CustomCovers.hasCustomCover(manga) and linkKey(manga.NewImageLink) ~= linkKey(selectedManga.ImageLink) then
				local cover_path = "ux0:data/otakio/cache/" .. Cache.getKey(selectedManga) .. "/cover.image"
				if doesFileExist(cover_path) then
					deleteFile(cover_path)
				end
				selectedManga.ImageLink = manga.NewImageLink
				selectedManga.ImageDownload = nil
				collectgarbage("collect")
			end
		end
	end
	if not is_chapter_list_ready and not ParserManager.check(chaptersList) then
		is_chapter_list_ready = true
		if Settings.LoadSummary then
			updateMangaDescription(chaptersList.Description or "")
		else
			updateMangaDescription("")
		end
	end
end

---Sets Continue button to latest read chapter in given `Manga`
local function updateContinueChapterNumber()
	if AppMode == MENU and not continueChapterNumber and not ParserManager.check(chaptersList) then
		continueChapterNumber = 0
		if #chaptersList > 0 then
			chaptersList[1].Manga.Counter = #chaptersList
			local latestChapter = Cache.getLatestBookmark(selectedManga)
			for i = 1, #chaptersList do
				local key = chaptersList[i].Link:gsub("%p", "")
				if latestChapter == key then
					local bookmark = Cache.getBookmark(chaptersList[i])
					if bookmark == true then
						continueChapterNumber = i + 1
						if not chaptersList[continueChapterNumber] then
							continueChapterNumber = i
						end
						chaptersList[1].Manga.Counter = #chaptersList - i
					else
						continueChapterNumber = i
						chaptersList[1].Manga.Counter = #chaptersList - i + 1
					end
					break
				end
			end
			if continueChapterNumber > 0 then
				local continueChapterName = chaptersList[continueChapterNumber].Name or ("Chapter " .. continueChapterNumber)
				maxChapterNameTickerTimeMs = 25 * string.len(continueChapterName)
				maxChapterNameOffset = math.max(Font.getTextWidth(FONT16, continueChapterName) - 220, 0)
				Timer.reset(chapterNameTickerTimer)
			end
		end
	end
end

---@param manga table
---Sets `manga` to details
function Details.setManga(manga)
	if manga then
		selectedManga = manga
		status = "START"
		oldFade = 1
		slider.Y = -50

		maxMangaNameTickerTimeMs = 50 * string.len(manga.Name)
		maxMangaNameOffset = math.max(Font.getTextWidth(BONT30, manga.Name) - 960 + 88 + 88 + 88, 0)

		chaptersList = {}
		detailsSelector:resetSelected()

		if Cache.isCached(selectedManga) and not Cache.BookmarksLoaded(selectedManga) then
			Cache.loadBookmarks(selectedManga)
		elseif Database.check(selectedManga) then
			Cache.addManga(selectedManga, chaptersList)
		end

		continueChapterNumber = nil

		if Threads.isOnline() and GetParserByID(manga.ParserID) then
			ParserManager.getChaptersAsync(manga, chaptersList)
			is_chapter_list_loaded_offline = false
		else
			chaptersList = Cache.loadChapters(manga)
			is_chapter_list_loaded_offline = true
		end
		is_chapter_list_ready = false
		is_notification_showed = false
		is_description_expanded = false

		descriptionWordList = {}
		descriptionMaxHeightOffset = 0

		Timer.reset(fadeTimer)
		Timer.reset(mangaNameTickerTimer)
	end
end

---Adds / Removes Manga from library
local function addToLibrary()
	if Database.check(selectedManga) then
		Database.removeManga(selectedManga)
		Notifications.push(Language[Settings.Language].NOTIFICATIONS.REMOVED_FROM_LIBRARY)
	else
		Database.addManga(selectedManga)
		Cache.addManga(selectedManga)
		Notifications.push(Language[Settings.Language].NOTIFICATIONS.ADDED_TO_LIBRARY)
		if #Database.getCategories() > 0 then
			CategoryEditor.assign(selectedManga)
		end
	end
end

---@param item integer
---Download / Stop Download / Delete `chapterList[item]` Chapter
local function downloadChapter(item)
	local is_wifi_enabled = Threads.isOnline()
	item = chaptersList[item]
	if item then
		Cache.addManga(selectedManga, chaptersList)
		Cache.makeHistory(selectedManga)
		if not ChapterSaver.check(item) then
			if ChapterSaver.is_downloading(item) then
				ChapterSaver.stop(item)
			elseif is_wifi_enabled then
				ChapterSaver.downloadChapter(item)
			else
				Notifications.pushUnique(Language[Settings.Language].SETTINGS.NoConnection)
			end
		else
			ChapterSaver.delete(item)
		end
	end
end

---@param item integer
---Opens Reader and loads `chapterList` and `item` chapter in
local function readChapter(item)
	if chaptersList[item] then
		Catalogs.shrink()
		Cache.addManga(selectedManga, chaptersList)
		Cache.makeHistory(selectedManga)
		Reader.load(chaptersList, item)
		AppMode = READER
		continueChapterNumber = nil
	end
end

---@param oldPad table
---@param pad table
---@param oldTouch table
---@param touch table
---Updates input for Details menu
function Details.input(oldPad, pad, oldTouch, touch)
	if status == "START" then
		local oldTouchMode = TOUCH_MODES.MODE
		if TOUCH_MODES.MODE == TOUCH_MODES.NONE and oldTouch.x and touch.x and touch.x > 240 then
			TOUCH_MODES.MODE = TOUCH_MODES.READ
			slider.TouchY = touch.y
		elseif TOUCH_MODES.MODE ~= TOUCH_MODES.NONE and not touch.x then
			if TOUCH_MODES.MODE == TOUCH_MODES.READ and oldTouch.x then
				if oldTouch.x > 320 and oldTouch.x < 955 and oldTouch.y > 90 + chaptersMaxHeightOffset then
					local id = math.floor((slider.Y + oldTouch.y - 20 - chaptersMaxHeightOffset) / 80)
					if Settings.ChapterSorting == "N->1" then
						id = #chaptersList - id + 1
					end
					if oldTouch.x < 866 or selectedManga.ParserID == "IMPORTED" then
						readChapter(id)
					else
						downloadChapter(id)
					end
				elseif oldTouch.x > 270 and oldTouch.x < 960 and oldTouch.y > 90 and oldTouch.y <= 90 + chaptersMaxHeightOffset then
					is_description_expanded = not is_description_expanded
				end
			end
			TOUCH_MODES.MODE = TOUCH_MODES.NONE
		end
		local is_description_scrollable = not (is_description_expanded and #descriptionWordList >= 13)
		if is_description_scrollable then
			detailsSelector:input(#chaptersList, oldPad, pad, touch.x)
		else
			if Controls.check(pad, SCE_CTRL_UP) then
				descriptionMaxHeightOffset = math.max(descriptionMaxHeightOffset - 3, 0)
			elseif Controls.check(pad, SCE_CTRL_DOWN) then
				descriptionMaxHeightOffset = math.min(descriptionMaxHeightOffset + 3, math.max(0, #descriptionWordList * LINE_HEIGHT - (544 - 95 - 24 - 24 - 10)))
			end
		end
		if oldTouch.x and not touch.x then
			if oldTouch.x > 20 and oldTouch.x < 260 and oldTouch.y > 416 and oldTouch.y < 475 then
				addToLibrary()
			elseif oldTouch.x > 20 and oldTouch.x < 260 and oldTouch.y > 480 then
				if continueChapterNumber then
					readChapter(continueChapterNumber > 0 and continueChapterNumber or 1)
				end
			elseif oldTouch.x > 960 - 88 and oldTouch.y < 90 and is_chapter_list_ready and oldTouchMode == TOUCH_MODES.READ then
				Details.actionsMenu()
			elseif oldTouch.x > 960 - 88 - 88 and oldTouch.y < 90 and oldTouchMode == TOUCH_MODES.READ then
				SettingsFunctions.ChapterSorting()
				Settings.save()
			end
		elseif Controls.check(pad, SCE_CTRL_TRIANGLE) and not Controls.check(oldPad, SCE_CTRL_TRIANGLE) then
			addToLibrary()
		elseif is_description_scrollable and Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldPad, SCE_CTRL_CROSS) then
			local id = detailsSelector.getSelected()
			if Settings.ChapterSorting == "N->1" then
				id = #chaptersList - id + 1
			end
			readChapter(id)
		elseif Controls.check(pad, SCE_CTRL_CIRCLE) and not Controls.check(oldPad, SCE_CTRL_CIRCLE) or (touch.x and not oldTouch.x and touch.x < 88 and touch.y < 90) then
			status = "WAIT"
			Loading.setStatus("NONE")
			ParserManager.remove(chaptersList)
			Timer.reset(fadeTimer)
			oldFade = fade
		elseif is_description_scrollable and Controls.check(pad, SCE_CTRL_SQUARE) and not Controls.check(oldPad, SCE_CTRL_SQUARE) and selectedManga.ParserID ~= "IMPORTED" then
			local id = detailsSelector.getSelected()
			if Settings.ChapterSorting == "N->1" then
				id = #chaptersList - id + 1
			end
			downloadChapter(id)
		elseif Controls.check(pad, SCE_CTRL_SELECT) and not Controls.check(oldPad, SCE_CTRL_SELECT) then
			if continueChapterNumber then
				readChapter(continueChapterNumber > 0 and continueChapterNumber or 1)
			end
		elseif Controls.check(pad, SCE_CTRL_START) and not Controls.check(oldPad, SCE_CTRL_START) and is_chapter_list_ready then
			Details.actionsMenu()
		elseif Controls.check(pad, SCE_CTRL_RTRIGGER) and not Controls.check(oldPad, SCE_CTRL_RTRIGGER) and is_chapter_list_ready then
			SettingsFunctions.ChapterSorting()
			Settings.save()
		elseif Controls.check(pad, SCE_CTRL_LTRIGGER) and not Controls.check(oldPad, SCE_CTRL_LTRIGGER) and is_chapter_list_ready then
			is_description_expanded = not is_description_expanded
		end
		local newItemID = 0
		if TOUCH_MODES.MODE == TOUCH_MODES.READ then
			if math.abs(slider.V) > 0.1 or math.abs(touch.y - slider.TouchY) > 10 then
				TOUCH_MODES.MODE = TOUCH_MODES.SLIDE
			else
				if oldTouch.x > 320 and oldTouch.x < 900 and oldTouch.y > 90 + chaptersMaxHeightOffset then
					local id = math.floor((slider.Y - 20 + oldTouch.y - chaptersMaxHeightOffset) / 80)
					if Settings.ChapterSorting == "N->1" then
						id = #chaptersList - id + 1
					end
					if chaptersList[id] then
						newItemID = id
					end
				end
			end
		elseif TOUCH_MODES.MODE == TOUCH_MODES.SLIDE then
			if touch.x and oldTouch.x then
				slider.V = oldTouch.y - touch.y
			end
		end
		if slider.ItemID > 0 and newItemID > 0 and slider.ItemID ~= newItemID then
			TOUCH_MODES.MODE = TOUCH_MODES.SLIDE
		else
			slider.ItemID = newItemID
		end
	end
end

---Updates Animations and Events for Details menu
function Details.update()
	if status ~= "END" then
		updateAnimations()
		updateMangaDescriptionMaxHeight()
		updateScrolling()
		updateChaptersList()
		updateContinueChapterNumber()
	end
end

---Draws Details menu
function Details.draw()
	if status ~= "END" then
		local M = oldFade * fade
		local Alpha = 255 * M

		local backgroundColor = WithAlpha(COLOR_BACK, Alpha)
		local textColor = WithAlpha(COLOR_FONT, Alpha)
		local secondTextColor = WithAlpha(COLOR_SUBFONT, Alpha)
		local addMangaButtonColor = WithAlpha(COLOR_SURFACE2, Alpha)
		local removeMangaButtonColor = WithAlpha(COLOR_DANGER, Alpha)
		local continueButtonColor = WithAlpha(COLOR_ACCENT, Alpha)
		local accentColor = WithAlpha(COLOR_ACCENT, Alpha)

		Graphics.fillRect(20, 260, 90, 544, backgroundColor)
		local start = math.max(1, math.floor(slider.Y / 80) + 1)
		local shift = (1 - M) * 544
		local y = shift - slider.Y + start * 80 + chaptersMaxHeightOffset
		local color, text = addMangaButtonColor, Language[Settings.Language].DETAILS.ADD_TO_LIBRARY

		if Database.check(selectedManga) then
			color = removeMangaButtonColor
			text = Language[Settings.Language].DETAILS.REMOVE_FROM_LIBRARY
		end
		UI.roundRect(20, shift + 418, 260, shift + 474, 12, color)
		Font.print(FONT20, 140 - Font.getTextWidth(FONT20, text) / 2, shift + 444 - Font.getTextHeight(FONT20, text) / 2, text, textColor)
		if continueChapterNumber then
			if #chaptersList > 0 then
				UI.roundRect(20, shift + 480, 260, shift + 538, 12, continueButtonColor)
				local continueButtonText = Language[Settings.Language].DETAILS.START
				local chapterName
				local dy = 0
				if continueChapterNumber > 0 and chaptersList[continueChapterNumber] and (continueChapterNumber == 1 and Cache.getBookmark(chaptersList[continueChapterNumber]) or continueChapterNumber ~= 1) then
					continueButtonText = Language[Settings.Language].DETAILS.CONTINUE
					dy = -10
					chapterName = chaptersList[continueChapterNumber].Name or ("Chapter " .. continueChapterNumber)
				end
				local continueButtonTextWidth = Font.getTextWidth(FONT20, continueButtonText)
				local continueButtonTextHeight = Font.getTextHeight(FONT20, continueButtonText)
				Font.print(FONT20, 140 - continueButtonTextWidth / 2, shift + 505 - continueButtonTextHeight / 2 + dy, continueButtonText, textColor)
				if chapterName then
					continueButtonTextWidth = math.min(Font.getTextWidth(FONT16, chapterName), 220)
					local chapterNameTickerX = maxChapterNameOffset * math.min(math.max(0, Timer.getTime(chapterNameTickerTimer) - 1500), maxChapterNameTickerTimeMs) / maxChapterNameTickerTimeMs
					Font.print(FONT16, 140 - continueButtonTextWidth / 2 - chapterNameTickerX, shift + 505 - continueButtonTextHeight / 2 + 18, chapterName, textColor)
				end
			end
		end
		Graphics.fillRect(0, 20, 90, 544, backgroundColor)
		if continueChapterNumber and #chaptersList > 0 then
			Graphics.drawImage(0, shift + 472, ButtonsIcons.Select.e)
		end
		Graphics.drawImageExtended(20, shift + 420, ButtonsIcons.Triangle.e, 0, 0, 16, 16, 0, 1, 1)
		DrawDetailsManga(MANGA_COVER_CENTER_POINT.x, MANGA_COVER_CENTER_POINT.y + 544 * (1 - M), selectedManga, 326 / MANGA_HEIGHT)
		Graphics.fillRect(260, 955, 90, 95, backgroundColor)
		Graphics.fillRect(260, 955, 95 + chaptersMaxHeightOffset, 544, backgroundColor)
		local listCount = #chaptersList
		-- selection / touch highlight sits under the row text
		local selectedItem = detailsSelector.getSelected()
		for _, highlighted in ipairs({selectedItem, slider.ItemID}) do
			if highlighted and highlighted ~= 0 then
				local row = Settings.ChapterSorting ~= "N->1" and highlighted or listCount - highlighted + 1
				local hy = shift - slider.Y + row * 80 + chaptersMaxHeightOffset
				if hy + 80 > 95 + chaptersMaxHeightOffset and hy < 544 then
					UI.listHighlight(270, math.max(hy + 3, 95 + chaptersMaxHeightOffset), 950, hy + 77, highlighted == selectedItem)
				end
			end
		end
		for n = start, math.min(listCount, start + 8) do
			if y + 80 > 95 + chaptersMaxHeightOffset then
				local i = Settings.ChapterSorting ~= "N->1" and n or listCount - n + 1
				local bookmark = Cache.getBookmark(chaptersList[i])
				local chapterName = UI.ellipsize(BONT16, chaptersList[i].Name or ("Chapter " .. i), 540)
				local date = chaptersList[i].Date
				if bookmark ~= nil and bookmark ~= true then
					Font.print(BONT16, 290, y + 14, chapterName, textColor)
					Font.print(FONT16, 290, y + 44, Language[Settings.Language].DETAILS.PAGE .. bookmark .. (date and ("  ·  " .. date) or ""), accentColor)
				elseif bookmark == true then
					Font.print(BONT16, 290, y + 14, chapterName, secondTextColor)
					Font.print(FONT16, 290, y + 44, Language[Settings.Language].DETAILS.DONE .. (date and ("  ·  " .. date) or ""), secondTextColor)
				else
					Graphics.fillRect(276, 282, y + 24, y + 30, accentColor)
					if date then
						Font.print(BONT16, 290, y + 14, chapterName, textColor)
						Font.print(FONT16, 290, y + 44, date, secondTextColor)
					else
						Font.print(BONT16, 290, y + 28, chapterName, textColor)
					end
				end
			end
			y = y + 80
			if y > 544 then
				break
			end
		end
		y = shift - slider.Y + start * 80 + chaptersMaxHeightOffset
		for n = start, math.min(listCount, start + 8) do
			if y + 80 > 95 + chaptersMaxHeightOffset then
				local i = Settings.ChapterSorting ~= "N->1" and n or listCount - n + 1
				if selectedManga.ParserID ~= "IMPORTED" then
					if ChapterSaver.check(chaptersList[i]) then
						Graphics.drawImage(920 - 14 - 18, y + 40 - 12, crossIcon.e, WithAlpha(COLOR_SUCCESS, Alpha))
					else
						local chapterDownloadInfo = ChapterSaver.is_downloading(chaptersList[i])
						if chapterDownloadInfo then
							local downloadProgressPercentageText = "0%"
							if chapterDownloadInfo.page_count and chapterDownloadInfo.page_count > 0 then
								downloadProgressPercentageText = math.ceil(100 * chapterDownloadInfo.page / chapterDownloadInfo.page_count) .. "%"
							end
							local width = Font.getTextWidth(FONT20, downloadProgressPercentageText)
							Font.print(FONT20, 920 - width / 2 - 18, y + 26, downloadProgressPercentageText, accentColor)
						else
							Graphics.drawImage(920 - 14 - 18, y + 40 - 12, DownloadIcon.e, textColor)
						end
					end
				end
			end
			y = y + 80
		end
		if status == "START" and #chaptersList == 0 and not ParserManager.check(chaptersList) and not is_notification_showed then
			is_notification_showed = true
			Notifications.push(Language[Settings.Language].WARNINGS.NO_CHAPTERS)
		end
		local item = detailsSelector.getSelected()
		if item ~= 0 then
			y = shift - slider.Y + item * 80 + chaptersMaxHeightOffset
			if y + 80 > 95 + chaptersMaxHeightOffset and selectedManga.ParserID ~= "IMPORTED" then
				Graphics.drawImage(929, y + 7, ButtonsIcons.Square.e)
			end
		end
		if #descriptionWordList > 0 and chaptersMaxHeightOffset > 0 then
			local descriptionLinesCount = is_description_expanded and #descriptionWordList or math.min(2, #descriptionWordList)
			if descriptionLinesCount ~= #descriptionWordList or descriptionLinesCount > 2 then
				Graphics.fillRect(260, 955, 95, 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10, backgroundColor)
			else
				Graphics.fillRect(260, 955, 95, 95 + chaptersMaxHeightOffset, backgroundColor)
			end
			local descriptionYOffset = 95 - descriptionMaxHeightOffset
			Graphics.fillRect(270, 274, descriptionYOffset + 3, descriptionYOffset + 19, accentColor)
			Font.print(BONT16, 282, descriptionYOffset, Language[Settings.Language].DETAILS.SUMMARY, accentColor)
			descriptionYOffset = descriptionYOffset + LINE_HEIGHT
			for i = 1, #descriptionWordList do
				if descriptionYOffset + LINE_HEIGHT >= 95 then
					local line = descriptionWordList[i]
					local x = 270
					for j = 1, #line do
						Font.print(FONT16, x, descriptionYOffset, line[j].Word, textColor)
						x = x + line.SpaceWidth + line[j].Width
					end
				end
				descriptionYOffset = descriptionYOffset + LINE_HEIGHT
				if descriptionLinesCount ~= #descriptionWordList or descriptionLinesCount > 2 then
					if descriptionYOffset >= 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10 then
						break
					end
				end
			end
			if descriptionLinesCount ~= #descriptionWordList or descriptionLinesCount > 2 then
				Graphics.fillRect(260, 955, 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10, 95 + chaptersMaxHeightOffset, backgroundColor)
				if descriptionLinesCount ~= #descriptionWordList then
					Font.print(BONT16, 270, 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10, Language[Settings.Language].DETAILS.EXPAND, accentColor)
					Graphics.drawImage(math.ceil(270 + Font.getTextWidth(BONT16, Language[Settings.Language].DETAILS.EXPAND) + 8), 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10, ButtonsIcons.L.e)
				elseif descriptionLinesCount > 2 then
					Font.print(BONT16, 270, 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10, Language[Settings.Language].DETAILS.SHRINK, accentColor)
					Graphics.drawImage(math.ceil(270 + Font.getTextWidth(BONT16, Language[Settings.Language].DETAILS.SHRINK) + 8), 95 + chaptersMaxHeightOffset - LINE_HEIGHT - 10, ButtonsIcons.L.e)
				end
			end
		end
		Graphics.fillRect(88, 960 - 88 - 88, 0, 90, backgroundColor)
		local mangaNameTickerX = maxMangaNameOffset * math.min(math.max(0, Timer.getTime(mangaNameTickerTimer) - 1500), maxMangaNameTickerTimeMs) / maxMangaNameTickerTimeMs
		Font.print(BONT30, 88 - mangaNameTickerX, 70 * M - 63, selectedManga.Name, textColor)
		-- source and chapter count (the raw URL stays available in the actions menu)
		local parser = GetAnyParserByID(selectedManga.ParserID)
		local subtitle = parser and parser.Name or ""
		if #chaptersList > 0 then
			subtitle = subtitle .. (subtitle ~= "" and "  ·  " or "") .. string.format(Language[Settings.Language].OTAKIO.N_CHAPTERS or "%d", #chaptersList)
		end
		Font.print(FONT16, 88, 70 * M - 22, UI.ellipsize(FONT16, subtitle, 960 - 88 - 88 - 88 - 16), secondTextColor)
		Graphics.fillRect(0, 88, 0, 90, backgroundColor)
		Graphics.drawImage(32, 90 * M - 50 - 12, BackIcon.e, textColor)
		Graphics.fillRect(960 - 88 - 88, 960, 0, 90, backgroundColor)
		if sortIcons[Settings.ChapterSorting] then
			Graphics.drawImage(960 - 88 - 32 - 24, 33, sortIcons[Settings.ChapterSorting].e, textColor)
			Graphics.drawImage(960 - 88 - 32 - 24, 5 - (1 - M) * 32, ButtonsIcons.R.e)
		end
		if is_chapter_list_ready then
			Graphics.drawImage(960 - 32 - 24, 33, menuIcon.e, textColor)
			Graphics.drawImage(960 - 32 - 24 - 12, 5 - (1 - M) * 32, ButtonsIcons.Start.e)
		end
		Graphics.fillRect(955, 960, 90, 544, backgroundColor)
		if status == "START" and #chaptersList > 5 then
			local h = #chaptersList * 80 / 454
			Graphics.fillRect(955, 960, 90 + (slider.Y + 20) / h, 90 + (slider.Y + 464) / h, secondTextColor)
		end
	end
end

---@return '"START"' | '"WAIT"' | '"END"'
---Gives status of Details menu
function Details.getStatus()
	return status
end

---@return number
---Gives fade
function Details.getFade()
	return fade * oldFade
end

---@return table
---Gives `seletctedManga` loaded in Details menu
function Details.getManga()
	return selectedManga
end

---@return integer|nil index of the highlighted chapter in chapter list order
function Details.getSelectedChapterIndex()
	local id = detailsSelector.getSelected()
	if id == 0 then
		return nil
	end
	if Settings.ChapterSorting == "N->1" then
		id = #chaptersList - id + 1
	end
	return id
end

---Forces "Continue" button & counters to be recalculated (after marking chapters)
function Details.refreshProgress()
	continueChapterNumber = nil
end


---Mihon-like chapter actions (Start button / menu icon)
function Details.actionsMenu()
	if not selectedManga then
		return
	end
	local O = Language[Settings.Language].OTAKIO
	local E = Language[Settings.Language].EXTRA
	local imported = selectedManga.ParserID == "IMPORTED"
	local selectedIndex = Details.getSelectedChapterIndex()
	local items = {}
	if Database.check(selectedManga) then
		items[#items + 1] = {label = O.SET_CATEGORIES, value = "categories"}
	end
	items[#items + 1] = {label = O.MARK_ALL_READ, value = "allread"}
	items[#items + 1] = {label = O.MARK_ALL_UNREAD, value = "allunread"}
	if selectedIndex and chaptersList[selectedIndex] then
		items[#items + 1] = {label = O.MARK_PREVIOUS_READ, sub = chaptersList[selectedIndex].Name, value = "prevread"}
	end
	if not imported then
		items[#items + 1] = {label = O.DOWNLOAD_NEXT_5, value = "next5"}
		items[#items + 1] = {label = O.DOWNLOAD_UNREAD, value = "unread"}
		items[#items + 1] = {label = E.DownloadAll or "Download all", value = "all"}
		items[#items + 1] = {label = E.CancelAll or "Cancel downloads", value = "cancel"}
		items[#items + 1] = {label = E.RemoveAll or "Remove downloads", value = "remove", danger = true}
		items[#items + 1] = {label = Language[Settings.Language].SETTINGS.ResetCover or "Reset cover", value = "cover"}
	end
	local function download(filter, limit)
		local is_wifi_enabled = Threads.isOnline()
		if not is_wifi_enabled then
			Notifications.pushUnique(Language[Settings.Language].SETTINGS.NoConnection)
			return
		end
		Cache.addManga(selectedManga, chaptersList)
		local n = 0
		for i = 1, #chaptersList do
			local chapter = chaptersList[i]
			if filter(chapter) and not ChapterSaver.is_downloading(chapter) and not ChapterSaver.check(chapter) then
				ChapterSaver.downloadChapter(chapter, true)
				n = n + 1
				if limit and n >= limit then
					break
				end
			end
		end
		Notifications.push(string.format(O.QUEUED_N, n))
	end
	local function isUnread(chapter)
		return Cache.getBookmark(chapter) ~= true
	end
	Dialog.menu(selectedManga.Name, items, function(item)
		local v = item.value
		if v == "categories" then
			CategoryEditor.assign(selectedManga)
		elseif v == "allread" then
			Cache.markChapters(chaptersList, true)
		elseif v == "allunread" then
			Cache.markChapters(chaptersList, nil)
		elseif v == "prevread" then
			local list = {}
			for i = 1, selectedIndex do
				list[i] = chaptersList[i]
			end
			Cache.markChapters(list, true)
		elseif v == "next5" then
			download(isUnread, 5)
		elseif v == "unread" then
			download(isUnread)
		elseif v == "all" then
			download(function() return true end)
		elseif v == "cancel" then
			ChapterSaver.stopList(chaptersList, true)
		elseif v == "remove" then
			Dialog.confirm(E.RemoveAll or "Remove", selectedManga.Name, function()
				ChapterSaver.stopList(chaptersList, true)
				for i = 1, #chaptersList do
					ChapterSaver.delete(chaptersList[i], true)
				end
			end)
		elseif v == "cover" then
			local key = Cache.getKey(selectedManga)
			for _, name in ipairs({"cover.image", "custom_cover.image"}) do
				local path = "ux0:data/otakio/cache/" .. key .. "/" .. name
				if doesFileExist(path) then
					deleteFile(path)
				end
			end
			CustomCovers.setMangaCover(selectedManga, nil)
			selectedManga.ImageDownload = nil
			collectgarbage("collect")
			Notifications.push(Language[Settings.Language].NOTIFICATIONS.COVER_SET_COMPLETED)
		end
		if v == "allread" or v == "allunread" or v == "prevread" then
			Details.refreshProgress()
			ParserManager.recount(selectedManga, chaptersList)
		end
	end)
end
