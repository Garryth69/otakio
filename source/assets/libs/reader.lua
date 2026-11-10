Reader = {}

local CreatePoint = CreatePoint

local allPages = {
	Page = 0
}

local velX, velY = 0, 0

local TOUCH_IDLE = 0
local TOUCH_MULTI = 1
local TOUCH_MOVE = 2
local TOUCH_READ = 3
local TOUCH_SWIPE = 4
local TOUCH_LOCK = 5
local touchMode = TOUCH_IDLE

local PAGE_NONE = 0
local PAGE_LEFT = 1
local PAGE_RIGHT = 2
local pageMode = PAGE_NONE

local STATE_LOADING = 0
local STATE_READING = 1
local currentState = STATE_LOADING

local maxZoom = 3

local currentPageOffset = CreatePoint(0, 0)
local touchTemp = CreatePoint(0, 0)

local startPage

local orientation
local is_down
local is_webtoon -- reading direction "WEBTOON": continuous vertical scrolling (see the Webtoon mode section)
local autozoom

local hideCounterTimer = Timer.new()

local doubleClickTimer = Timer.new()
local lastClickPoint = {x = -100, y = -100}
local gestureZoom = false

local ContextMenu = false
local MenuFade = 0
local toggleContextMenu = false
local ToggleContextMenuTimer = Timer.new()
local OnTouchMenu = false
local CursorIndex = -1
local CursorFade = 0
local CursorPoint = CreatePoint(0, 0)
local CursorDestination = CreatePoint(0, 0)
local CursorPlaces = {CreatePoint(32 + 12, 40), CreatePoint(960 - 88 - 88 + 32 + 12, 40), CreatePoint(960 - 32 - 12, 40), CreatePoint(32 + 12, 544 - 40), CreatePoint(0, 0), CreatePoint(960 - 32 - 12, 544 - 40)}

local mangaNameTickerTimer = Timer.new()
local chapterNameTickerTimer = Timer.new()

local leftArrowIcon = Image:new(Graphics.loadImage("app0:assets/icons/left.png"))
local rightArrowIcon = Image:new(Graphics.loadImage("app0:assets/icons/right.png"))

local readDirection = Settings.ReaderDirection

local function gesture_touch_input(touch, oldtouch, page)
	if Settings.DoubleTapReader then
		if gestureZoom then
			touchMode = TOUCH_IDLE
		end
		if not page or not page.Zoom then
			return
		end
		if touch.x == nil and oldtouch.x ~= nil and (not ContextMenu or (oldtouch.y >= 80 and oldtouch.y <= 544 - 80)) and not gestureZoom and touchMode == TOUCH_READ then
			gestureZoom = false
			local update_last = true
			if Timer.getTime(doubleClickTimer) < 300 then
				local len = math.sqrt((lastClickPoint.x - oldtouch.x) * (lastClickPoint.x - oldtouch.x) + (lastClickPoint.y - oldtouch.y) * (lastClickPoint.y - oldtouch.y))
				if len < 80 then
					toggleContextMenu = false
					if page.Zoom >= maxZoom - (maxZoom - page.min_Zoom) / 2 then
						gestureZoom = {
							Zoom = page.start_Zoom,
							x = 480,
							y = 272
						}
					else
						gestureZoom = {
							Zoom = math.min(maxZoom, maxZoom - (maxZoom - page.min_Zoom) / 2),
							x = oldtouch.x,
							y = oldtouch.y
						}
					end
					touchMode = TOUCH_LOCK
					Console.write(gestureZoom.Zoom)
					Console.write(allPages[allPages.Page].Zoom)
					update_last = false
					lastClickPoint = {x = -100, y = -100}
				end
			end
			Timer.reset(doubleClickTimer)
			if update_last then
				lastClickPoint = {x = oldtouch.x, y = oldtouch.y}
			end
		end
	end
end

local function gesture_touch_update()
	if Settings.DoubleTapReader then
		if gestureZoom and allPages[allPages.Page] and currentState == STATE_READING then
			local stop = false
			local old_Zoom = allPages[allPages.Page].Zoom
			if math.abs((allPages[allPages.Page].Zoom - gestureZoom.Zoom) / 4) < 0.01 then
				allPages[allPages.Page].Zoom = gestureZoom.Zoom
				stop = true
			else
				allPages[allPages.Page].Zoom = (allPages[allPages.Page].Zoom + (gestureZoom.Zoom - allPages[allPages.Page].Zoom) / 4)
			end
			allPages[allPages.Page].y = 272 + ((allPages[allPages.Page].y - 272) / old_Zoom) * allPages[allPages.Page].Zoom
			allPages[allPages.Page].x = 480 + ((allPages[allPages.Page].x - 480) / old_Zoom) * allPages[allPages.Page].Zoom
			local n = allPages[allPages.Page].Zoom / old_Zoom
			allPages[allPages.Page].y = allPages[allPages.Page].y - (gestureZoom.y - 272) * (n - 1)
			allPages[allPages.Page].x = allPages[allPages.Page].x - (gestureZoom.x - 480) * (n - 1)
			if stop then
				gestureZoom = false
			end
		end
		if Timer.getTime(doubleClickTimer) > 300 then
			lastClickPoint = {x = -100, y = -100}
		end
	end
end

local Chapters = {}
local currentChapterNumber = 1

local function updateMeasurements()
	for i = 1, #allPages do
		allPages[i].Zoom = nil
	end
end

local function scale(dZoom, Page)
	if math.abs(1 - dZoom) < 0.005 or not Page.Zoom then
		return
	end
	local oldZoom = Page.Zoom
	Page.Zoom = Page.Zoom * dZoom
	if Page.Zoom < Page.min_Zoom then
		Page.Zoom = Page.min_Zoom
	elseif Page.Zoom > maxZoom then
		Page.Zoom = maxZoom
	end
	Page.y = 272 + ((Page.y - 272) / oldZoom) * Page.Zoom
	Page.x = 480 + ((Page.x - 480) / oldZoom) * Page.Zoom
end


-------------------------------------------------------------------------------
-- Otakio page prefetcher: downloads the next pages to disk in the background so
-- turning pages only needs a (fast) local decode.
-------------------------------------------------------------------------------
local Prefetch = {files = {}, count = 0}
local PREFETCH_DIR = "ux0:data/otakio/temp/prefetch/"
local getPictureResolution = System.getPictureResolution
local doesFileExist_ = System.doesFileExist
local deleteFile_ = System.deleteFile
local listDirectory_ = System.listDirectory

local function entryUrl(entry)
	if type(entry) == "table" then
		entry = entry.Link
	end
	if type(entry) == "string" and entry:find("^https?://") then
		return entry
	end
end

-- the page being shown goes first: prefetching starts once it is on screen (or after a short delay if it can't load),
-- otherwise pages resolved through the parser (most native sources) lose the race against the prefetch downloads
local prefetchPending = nil -- {page =, direction =}
local prefetchTimer = Timer.new()

local function prefetchClear()
	prefetchPending = nil
	for _, f in pairs(Prefetch.files) do
		Threads.remove(f)
	end
	Prefetch.files = {}
	Prefetch.count = 0
	for _, f in ipairs(listDirectory_(PREFETCH_DIR) or {}) do
		if not f.directory then
			deleteFile_(PREFETCH_DIR .. f.name)
		end
	end
end

---@return string|nil path of a fully prefetched, decodable page
local function prefetchedPath(entry)
	local url = entryUrl(entry)
	local f = url and Prefetch.files[url]
	if f and f.done and doesFileExist_(f.path) then
		local w = getPictureResolution(f.path)
		if w and w > 0 then
			return f.path
		end
	end
end

local function prefetchFrom(page, direction)
	local n = Settings.PreloadPages or 3
	if n <= 0 or not Chapters or not Chapters[currentChapterNumber] then
		return
	end
	if ChapterSaver.check(Chapters[currentChapterNumber]) then
		return
	end
	for k = 2, n + 1 do
		local p = allPages[page + k * direction]
		if p and not p.Image and not p.Path and p.Link ~= "LoadNext" and p.Link ~= "LoadPrev" then
			local entry = p.Link or p[1]
			local url = entryUrl(entry)
			if url and not Prefetch.files[url] then
				Prefetch.count = Prefetch.count + 1
				local f = {path = PREFETCH_DIR .. Prefetch.count .. ".img", done = false}
				Prefetch.files[url] = f
				Threads.addTask(f, {
					Type = "FileDownload",
					ImageFile = true,
					Link = entry,
					Path = f.path,
					Priority = Threads.NORMAL + 1, -- after covers, before background work
					OnComplete = function()
						f.done = true
					end
				})
			end
		end
	end
end

---Loads a page that still needs to be resolved/downloaded, using the prefetch cache when possible
local function requestRemotePage(pageTable, insert)
	local path = prefetchedPath(pageTable.Link or pageTable[1])
	local add = insert and Threads.insertTask or Threads.addTask
	if path then
		add(pageTable, {
			Type = "Image",
			Path = path,
			Table = pageTable,
			Index = "Image"
		})
	elseif pageTable.Link then
		add(pageTable, {
			Type = "ImageDownload",
			Link = pageTable.Link,
			Table = pageTable,
			Index = "Image"
		})
	else
		ParserManager.loadPageImage(Chapters[currentChapterNumber].Manga.ParserID, pageTable[1], pageTable, insert)
	end
end

local function deletePageImage(page)
	if allPages[page].Image then
		if type(allPages[page].Image.e or allPages[page].Image) == "table" then
			Threads.remove(allPages[page])
			ParserManager.remove(allPages[page])
			if allPages[page].Image.Lazy then
				allPages[page].Image:free()
			elseif allPages[page].Image.Parts then
				for i = 1, allPages[page].Image.Parts do
					if allPages[page].Image[i] and allPages[page].Image[i].free then
						allPages[page].Image[i]:free()
					end
				end
			else
				for i = 1, #allPages[page].Image do
					if allPages[page].Image[i] and allPages[page].Image[i].Image and allPages[page].Image[i].Image.free then
						allPages[page].Image[i].Image:free()
					end
				end
			end
		else
			if allPages[page].Image and allPages[page].Image.free then
				allPages[page].Image:free()
			end
		end
		allPages[page].Image = nil
		Console.write("Removed " .. tostring(page))
	else
		ParserManager.remove(allPages[page])
		Threads.remove(allPages[page])
	end
end

-- texture budget short of memory: every decoded page except the one on screen can go (it reloads from disk)
Textures.register("reader-pages", 2, function()
	if not allPages or not allPages.Page then
		return
	end
	for i = 1, #allPages do
		if i ~= allPages.Page and allPages[i] and allPages[i].Image then
			deletePageImage(i)
		end
	end
end)

---@param page integer
---@param urgent boolean|nil false: queued behind the current work (a page ahead of the view in webtoon mode)
local function loadPageImage(page, urgent)
	local PageTable = allPages[page]
	local add = urgent == false and Threads.addTask or Threads.insertTask
	if not PageTable.Image and not (PageTable.Link == "LoadPrev" or PageTable.Link == "LoadNext") then
		if PageTable.Extract then
			add(
				PageTable,
				{
					Type = "UnZipFile",
					Path = PageTable.Path,
					Extract = PageTable.Extract,
					DestPath = "ux0:data/otakio/temp/cache.image",
					OnComplete = function()
						Threads.insertTask(
							PageTable,
							{
								Type = "Image",
								Table = PageTable,
								Path = "temp/cache.image",
								Index = "Image"
							}
						)
					end
				}
			)
		elseif PageTable.Path then
			add(
				PageTable,
				{
					Type = "Image",
					Path = PageTable.Path,
					Table = PageTable,
					Index = "Image"
				}
			)
		else
			requestRemotePage(PageTable, urgent ~= false)
		end
	end
end
---@param page integer
local function changePage(page)
	if page < 0 and currentChapterNumber > 1 or page > #allPages then
		return false
	end
	allPages.PrevPage = allPages.Page
	allPages.Page = page
	if allPages[allPages.Page].Link == "LoadNext" or allPages[allPages.Page].Link == "LoadPrev" then
		return true
	end
	local o = {0}
	for k = 1, #o do
		local p = page + o[k]
		if allPages[p] then
			loadPageImage(p)
		end
	end
	prefetchPending = {page = page, direction = (readDirection == "LEFT" and not is_down) and -1 or 1}
	Timer.reset(prefetchTimer)
	for i = page - 2, page + 2, 4 do
		if i > 0 and i <= #allPages then
			deletePageImage(i)
			local OldOne = allPages[i][1]
			local OldLink = allPages[i].Link
			local OldPath = allPages[i].Path
			local OldExtr = allPages[i].Extract
			for k, _ in pairs(allPages[i]) do
				allPages[i][k] = nil
			end
			allPages[i][1] = OldOne
			allPages[i].Link = OldLink
			allPages[i].Path = OldPath
			allPages[i].Extract = OldExtr
			allPages[i].x = 0
			allPages[i].y = 0
		end
	end
	return true
end

local buttonTimer = Timer.new()
local buttonTimeSpace = 800

---@param direction string | '"LEFT"' | '"RIGHT"'
---Turns the page according to the `direction`
local function swipe(direction)
	if orientation == "Horizontal" then
		if direction == "LEFT" then
			if is_down then
				if allPages.Page ~= #allPages and changePage(allPages.Page + 1) then
					currentPageOffset.y = 544 + currentPageOffset.y
					local page = allPages[allPages.Page - 1]
					if page and page.Zoom then
						if page.Zoom * page.Height >= 544 then
							page.y = -page.Height * page.Zoom / 2
						else
							page.y = -272
						end
					end
				end
			else
				if allPages.Page ~= #allPages and changePage(allPages.Page + 1) then
					currentPageOffset.x = 960 + currentPageOffset.x
					local page = allPages[allPages.Page - 1]
					if page and page.Zoom then
						if page.Zoom * page.Width >= 960 then
							page.x = -page.Width * page.Zoom / 2
						else
							page.x = -480
						end
					end
				end
			end
		elseif direction == "RIGHT" then
			if is_down then
				if allPages[allPages.Page - 1] and changePage(allPages.Page - 1) then
					currentPageOffset.y = -544 + currentPageOffset.y
					local page = allPages[allPages.Page + 1]
					if page and page.Zoom then
						if page.Zoom * page.Height >= 544 then
							page.y = 544 + page.Height * page.Zoom / 2
						else
							page.y = 544 + 272
						end
					end
				end
			else
				if allPages[allPages.Page - 1] and changePage(allPages.Page - 1) then
					currentPageOffset.x = -960 + currentPageOffset.x
					local page = allPages[allPages.Page + 1]
					if page and page.Zoom then
						if page.Zoom * page.Width >= 960 then
							page.x = 960 + page.Width * page.Zoom / 2
						else
							page.x = 960 + 480
						end
					end
				end
			end
		end
	elseif orientation == "Vertical" then
		if direction == "LEFT" then
			if is_down then
				if allPages.Page ~= #allPages and changePage(allPages.Page + 1) then
					currentPageOffset.x = -960 + currentPageOffset.x
					local page = allPages[allPages.Page - 1]
					if page and page.Zoom then
						if page.Zoom * page.Height >= 960 then
							page.x = 960 + page.Height * page.Zoom / 2
						else
							page.x = 960 + 480
						end
					end
				end
			else
				if allPages.Page ~= #allPages and changePage(allPages.Page + 1) then
					currentPageOffset.y = 544 + currentPageOffset.y
					local page = allPages[allPages.Page - 1]
					if page and page.Zoom then
						if page.Zoom * page.Width >= 544 then
							page.y = -page.Width * page.Zoom / 2
						else
							page.y = -272
						end
					end
				end
			end
		elseif direction == "RIGHT" then
			if is_down then
				if allPages[allPages.Page - 1] and changePage(allPages.Page - 1) then
					currentPageOffset.x = 960 + currentPageOffset.x
					local page = allPages[allPages.Page + 1]
					if page and page.Zoom then
						if page.Zoom * page.Height >= 960 then
							page.x = -page.Height * page.Zoom / 2
						else
							page.x = -480
						end
					end
				end
			else
				if allPages[allPages.Page - 1] and changePage(allPages.Page - 1) then
					currentPageOffset.y = -544 + currentPageOffset.y
					local page = allPages[allPages.Page + 1]
					if page and page.Zoom then
						if page.Zoom * page.Width >= 544 then
							page.y = 544 + page.Width * page.Zoom / 2
						else
							page.y = 544 + 272
						end
					end
				end
			end
		end
	end
end

---A page taller than the screen (a webtoon strip) is read by screens: the page-turn buttons and the edge taps first
---move the view along the page, about one screen at a time with a little of the previous view kept for the eye, and
---turn the page only once its end is on screen. Going back does the same in reverse. Pages that fit the screen turn
---at once, as before.
local STEP_KEEP = 0.15 -- part of the screen kept visible between two steps

---Where the current page stands along its height: the axis, its top and its end positions on that axis
local function pageScroll(page)
	local extent = page.Height * page.Zoom
	if orientation == "Horizontal" then
		if extent <= 545 then
			return nil
		end
		-- the page is centered at page.y: its top is on screen at extent / 2, its end at 544 - extent / 2
		return "y", 544, extent / 2, 544 - extent / 2
	end
	if extent <= 961 then
		return nil
	end
	-- drawn rotated: the top of the page is on the right (page.x = 960 - extent / 2), its end on the left
	return "x", 960, 960 - extent / 2, extent / 2
end

---@return boolean true when the view moved along the page instead of turning it
local function scrollPage(direction)
	local page = allPages[allPages.Page]
	if not page or not page.Zoom or not page.Image then
		return false
	end
	local axis, screen, topPos, endPos = pageScroll(page)
	if not axis then
		return false
	end
	local pos = page[axis]
	local target = direction == "LEFT" and endPos or topPos
	if math.abs(pos - target) < 1 then
		return false
	end
	local step = screen * (1 - STEP_KEEP)
	if target < pos then
		page[axis] = math.max(pos - step, target)
	else
		page[axis] = math.min(pos + step, target)
	end
	return true
end

---Page-turn buttons and edge taps: one more screen of a tall page, else the next/previous page
local function turnPage(direction)
	if not scrollPage(direction) then
		swipe(direction)
	end
end

-------------------------------------------------------------------------------
-- Webtoon mode (reading direction "WEBTOON"): the pages of the chapter sit one under the other and the view scrolls
-- over them like on the sites; at the ends, scrolling on changes the chapter. The view is kept as (page, offset into
-- that page): a page that loads above the view (its height was unknown) doesn't move what is being read.
-------------------------------------------------------------------------------
-- the view in reading coordinates: 960x544 holding the Vita sideways, 544x960 in the Vertical orientation (drawn turned)
local WT_W, WT_H = 960, 544
local WT_MIN_ZOOM, WT_MAX_ZOOM = 0.4, 3
local wtVertical = false
local WT_PLACEHOLDER = 544 -- height of a page while its image is unknown
local WT_END_ZONE = 160 -- scrolling this far past an end changes the chapter
local wt = {page = 1, offset = 0, zoom = 1, x = 0, vel = 0, glide = 0, push = 0, overTop = 0, overEnd = 0, atTop = true, atEnd = false, stickEnd = false}
local wtTouch = {active = false}
local wtClock = Timer.new()

---@return number|nil width, number|nil height of the decoded image of `page`
local function wtImageSize(page)
	local img = page.Image
	if not img then
		return nil
	end
	if img.Width and img.Height then
		return img.Width, img.Height
	end
	if img[1] and img[1].Image then -- animated image: a list of frames
		return img[1].Image.Width, img[1].Image.Height
	end
	return nil
end

---Scale of `page` on screen: the page fills the screen width, times the user's zoom
local function wtScale(page)
	local w = wtImageSize(page)
	if not w or w <= 0 then
		return wt.zoom
	end
	return WT_W * wt.zoom / w
end

---Height of `page` on screen (a placeholder while its image is unknown)
local function wtHeight(page)
	local w, h = wtImageSize(page)
	if not w or not h or w <= 0 then
		return WT_PLACEHOLDER
	end
	return h * WT_W * wt.zoom / w
end

---Moves to the neighbouring pages when the offset leaves the current one
local function wtSettle()
	local count = allPages.Count or 0
	while wt.page < count and wt.offset >= wtHeight(allPages[wt.page]) do
		wt.offset = wt.offset - wtHeight(allPages[wt.page])
		wt.page = wt.page + 1
	end
	while wt.page > 1 and wt.offset < 0 do
		wt.page = wt.page - 1
		wt.offset = wt.offset + wtHeight(allPages[wt.page])
	end
end

---Keeps the view inside the chapter. Past an end only while the user pushes that way (`push`: this frame's own
---scrolling, positive = down), up to WT_END_ZONE: that is how the next/previous chapter is reached.
local function wtNormalize(push)
	local count = allPages.Count or 0
	if count == 0 or not allPages[1] then
		return
	end
	wtSettle()
	local above = 0
	for p = 1, wt.page - 1 do
		above = above + wtHeight(allPages[p])
	end
	local contentH = above
	for p = wt.page, count do
		contentH = contentH + wtHeight(allPages[p])
	end
	local scroll = above + wt.offset
	-- past the last page lies a transition screen (the chapter note), like the sites' and Mihon's: the end of the
	-- chapter is reached once it fills the screen
	local maxContent = math.max(0, contentH - WT_H)
	local maxScroll = contentH
	if wt.stickEnd then
		-- came back from the next chapter: the last page's end on screen, until that page is measured
		scroll = maxContent
		if allPages[count].Image then
			wt.stickEnd = false
		end
	end
	local zoneTop = (currentChapterNumber > 1 and push < 0) and WT_END_ZONE or 0
	local zoneEnd = (currentChapterNumber < #Chapters and push > 0) and WT_END_ZONE or 0
	if scroll < -zoneTop then
		scroll = -zoneTop
		wt.vel = 0
	elseif scroll > maxScroll + zoneEnd then
		scroll = math.max(-zoneTop, maxScroll + zoneEnd)
		wt.vel = 0
	end
	wt.overTop = scroll < 0 and -scroll or 0
	wt.overEnd = scroll > maxScroll and scroll - maxScroll or 0
	wt.atTop = scroll <= 0
	wt.atEnd = scroll >= maxScroll
	wt.page, wt.offset = 1, scroll
	wtSettle()
	local maxX = math.max(0, WT_W / 2 * (wt.zoom - 1))
	wt.x = math.max(-maxX, math.min(maxX, wt.x))
end

---The page at the middle of the screen: counter, bookmark, prefetch
local function wtCurrentPage()
	local y = -wt.offset
	for p = wt.page, allPages.Count or 0 do
		y = y + wtHeight(allPages[p])
		if y > WT_H / 2 then
			return p
		end
	end
	return math.max(1, math.min(wt.page, allPages.Count or 1))
end

---Jumps to the top of page `p` (the bars' slider and arrows)
local function wtGoTo(p)
	local count = allPages.Count or 0
	if count == 0 then
		return
	end
	wt.page = math.max(1, math.min(count, p))
	wt.offset, wt.vel, wt.glide, wt.stickEnd = 0, 0, 0, false
end

---Zooms by `f` around the middle of the screen (1 = the page fills the width; less shows more of the strip)
local function wtZoomBy(f)
	local new = math.max(WT_MIN_ZOOM, math.min(WT_MAX_ZOOM, wt.zoom * f))
	f = new / wt.zoom
	if f == 1 then
		return
	end
	wt.zoom = new
	wt.offset = (wt.offset + WT_H / 2) * f - WT_H / 2
	wt.x = wt.x * f
end

local function wtNextChapter()
	if currentChapterNumber < #Chapters then
		if Cache.isCached(Chapters[currentChapterNumber].Manga) then
			Cache.setBookmark(Chapters[currentChapterNumber], true)
		end
		Reader.loadChapter(currentChapterNumber + 1)
	end
end

local function wtPrevChapter()
	if currentChapterNumber > 1 then
		if Cache.isCached(Chapters[currentChapterNumber].Manga) then
			Cache.setBookmark(Chapters[currentChapterNumber], nil)
		end
		startPage = false
		Reader.loadChapter(currentChapterNumber - 1)
	end
end

---One screen down or up (a bit of the previous view kept); at an end, on to the next/previous chapter
local function wtStep(direction)
	local step = WT_H * (1 - STEP_KEEP)
	if direction > 0 then
		if wt.atEnd and wt.glide == 0 then
			wt.push = WT_END_ZONE
			wt.offset = wt.offset + WT_END_ZONE
		else
			wt.glide = wt.glide + step -- eased in over the next frames (webtoonUpdate)
		end
	elseif wt.atTop and wt.glide == 0 then
		wt.push = -WT_END_ZONE
		wt.offset = wt.offset - WT_END_ZONE
	else
		wt.glide = wt.glide - step
	end
	wt.vel = 0
end

---The bars' slider arrows: in webtoon mode a jump to the next/previous page, else the usual page turn
local function wtTurn(direction)
	if is_webtoon then
		wtGoTo((allPages.Page or 1) + (direction == "LEFT" and 1 or -1))
	else
		swipe(direction)
	end
end

---Requests the images of the pages around the view (the ones on screen first) and frees the ones far from it
local function wtManageImages()
	local count = allPages.Count or 0
	local first, above = wt.page, 0
	while first > 1 and above < WT_H do
		first = first - 1
		above = above + wtHeight(allPages[first])
	end
	local last, below = wt.page, -wt.offset
	while last < count and below < WT_H * 2 do
		below = below + wtHeight(allPages[last])
		last = last + 1
	end
	local now = Timer.getTime(wtClock)
	local y = -wt.offset
	for p = first, last do
		local pg = allPages[p]
		if pg and not pg.Image and pg.Link ~= "LoadPrev" and pg.Link ~= "LoadNext" and (not pg.WtAsked or now - pg.WtAsked > 4000) then
			pg.WtAsked = now
			loadPageImage(p, p >= wt.page and y < WT_H)
		end
		if p >= wt.page then
			y = y + wtHeight(pg)
		end
	end
	for p = 1, count do
		local pg = allPages[p]
		if (p < first - 1 or p > last + 1) and pg and (pg.Image or pg.WtAsked) then
			deletePageImage(p)
			pg.WtAsked = nil
		end
	end
end

---Start of a chapter in webtoon mode (after the pages are known): at the bookmark, or at the end when coming back
local function wtStart()
	wtVertical = orientation == "Vertical"
	WT_W, WT_H = wtVertical and 544 or 960, wtVertical and 960 or 544
	wt.page = math.max(1, math.min(allPages.Page or 1, allPages.Count or 1))
	wt.offset, wt.vel, wt.glide, wt.x, wt.push = 0, 0, 0, 0, 0
	wt.stickEnd = (allPages.PrevPage or 0) > (allPages.Page or 0)
	wtTouch.active = false
end

---Webtoon mode input: sticks and d-pad scroll (sideways when zoomed), L/R step a screen, Triangle/Square and the
---right stick zoom; on the page, a drag scrolls with inertia, a pinch zooms, a tap shows the bars (or steps a screen on
---the top/bottom edges). The bars themselves are handled by the shared code.
local function webtoonInput(oldPad, pad, oldTouch, touch, oldTouch2, touch2)
	wt.push = 0
	local sx, sy = Controls.readLeftAnalog()
	sx, sy = sx - 127, sy - 127
	if wtVertical then
		-- the Vita held upright: the stick's left is the reading down, its down the reading right
		sx, sy = sy, -sx
	end
	-- touch points in reading coordinates
	local function rt(t)
		if wtVertical and t.x then
			return {x = t.y, y = 960 - t.x}
		end
		return t
	end
	local pTouch = touch
	touch, oldTouch, touch2, oldTouch2 = rt(touch), rt(oldTouch), rt(touch2), rt(oldTouch2)
	local down, up, left, right = SCE_CTRL_DOWN, SCE_CTRL_UP, SCE_CTRL_LEFT, SCE_CTRL_RIGHT
	if wtVertical then
		down, up, left, right = SCE_CTRL_LEFT, SCE_CTRL_RIGHT, SCE_CTRL_UP, SCE_CTRL_DOWN
	end
	if math.abs(sy) > SCE_LEFT_STICK_DEADZONE then
		local d = SCE_LEFT_STICK_SENSITIVITY * 25 * (sy - SCE_LEFT_STICK_DEADZONE * math.sign(sy)) / (128 - SCE_LEFT_STICK_DEADZONE)
		wt.offset, wt.push, wt.vel = wt.offset + d, wt.push + d, 0
	end
	if wt.zoom > 1 and math.abs(sx) > SCE_LEFT_STICK_DEADZONE then
		wt.x = wt.x - SCE_LEFT_STICK_SENSITIVITY * 25 * (sx - SCE_LEFT_STICK_DEADZONE * math.sign(sx)) / (128 - SCE_LEFT_STICK_DEADZONE)
	end
	if not ContextMenu then
		if Controls.check(pad, down) then
			wt.offset, wt.push, wt.vel = wt.offset + 20, wt.push + 20, 0
		elseif Controls.check(pad, up) then
			wt.offset, wt.push, wt.vel = wt.offset - 20, wt.push - 20, 0
		end
		if wt.zoom > 1 then
			if Controls.check(pad, left) then
				wt.x = wt.x + 20
			elseif Controls.check(pad, right) then
				wt.x = wt.x - 20
			end
		end
		if Controls.check(pad, SCE_CTRL_RIGHTPAGE) and not Controls.check(oldPad, SCE_CTRL_RIGHTPAGE) then
			wtStep(1)
		elseif Controls.check(pad, SCE_CTRL_LEFTPAGE) and not Controls.check(oldPad, SCE_CTRL_LEFTPAGE) then
			wtStep(-1)
		end
		local dz = 1
		if Controls.check(pad, SCE_CTRL_TRIANGLE) then
			dz = 1.03
		elseif Controls.check(pad, SCE_CTRL_SQUARE) then
			dz = 1 / 1.03
		end
		local rx, ry = Controls.readRightAnalog()
		ry = ry - 127
		if wtVertical then
			ry = 127 - rx
		end
		if math.abs(ry) > SCE_RIGHT_STICK_DEADZONE then
			ry = (ry - SCE_RIGHT_STICK_DEADZONE * math.sign(ry)) / (128 - SCE_RIGHT_STICK_DEADZONE)
			dz = dz * (1 - SCE_LEFT_STICK_SENSITIVITY * ry * 0.03)
		end
		if dz ~= 1 then
			wtZoomBy(dz)
		end
	end
	-- the bars are drawn sideways in both orientations: checked on the screen's own coordinates
	local onPage = pTouch.x and (not ContextMenu or (pTouch.y > 80 and pTouch.y < 544 - 80))
	if onPage then
		if not wtTouch.active then
			wtTouch.active, wtTouch.moved = true, false
			wtTouch.startX, wtTouch.startY, wtTouch.lastX, wtTouch.lastY = touch.x, touch.y, touch.x, touch.y
			wt.vel = 0
			touchMode = TOUCH_READ
		else
			if touch2.x and oldTouch2.x and oldTouch.x then
				local d = math.sqrt((touch.x - touch2.x) ^ 2 + (touch.y - touch2.y) ^ 2)
				local d0 = math.sqrt((oldTouch.x - oldTouch2.x) ^ 2 + (oldTouch.y - oldTouch2.y) ^ 2)
				if d0 > 0 then
					wtZoomBy(d / d0)
				end
				wtTouch.moved = true
			else
				local dy, dx = touch.y - wtTouch.lastY, touch.x - wtTouch.lastX
				if not wtTouch.moved and (math.abs(touch.y - wtTouch.startY) > 10 or math.abs(touch.x - wtTouch.startX) > 10) then
					wtTouch.moved = true
					touchMode = TOUCH_MOVE
				end
				if wtTouch.moved then
					wt.offset, wt.push, wt.vel = wt.offset - dy, wt.push - dy, -dy
					if wt.zoom > 1 then
						wt.x = wt.x + dx
					end
				end
			end
			wtTouch.lastX, wtTouch.lastY = touch.x, touch.y
		end
	elseif wtTouch.active then
		wtTouch.active = false
		touchMode = TOUCH_IDLE
		if not wtTouch.moved and oldTouch.x then
			if Settings.PressEdgesToChangePage and oldTouch.y > WT_H / 2 + 120 then
				wtStep(1)
			elseif Settings.PressEdgesToChangePage and oldTouch.y < WT_H / 2 - 120 then
				wtStep(-1)
			else
				toggleContextMenu = true
				Timer.reset(ToggleContextMenuTimer)
			end
		end
	end
end

---Webtoon mode, every frame: inertia, limits, chapter change at the ends, the current page, the images around
local function webtoonUpdate()
	if not wtTouch.active and wt.vel ~= 0 then
		wt.offset = wt.offset + wt.vel
		wt.vel = wt.vel * 0.93
		if math.abs(wt.vel) < 0.3 then
			wt.vel = 0
		end
	end
	if wt.glide ~= 0 then
		-- a screen step glides in (a quarter of what is left per frame); it stops at the ends, never past them
		local d = wt.glide / 4
		if math.abs(d) < 2 then
			d = wt.glide
		end
		wt.offset = wt.offset + d
		wt.glide = wt.glide - d
	end
	wtNormalize(wt.push)
	if (wt.atEnd and wt.glide > 0) or (wt.atTop and wt.glide < 0) then
		wt.glide = 0
	end
	local push = wt.push
	wt.push = 0
	if wt.overEnd >= WT_END_ZONE - 1 and push > 0 then
		wtNextChapter()
		return
	elseif wt.overTop >= WT_END_ZONE - 1 and push < 0 then
		wtPrevChapter()
		return
	end
	local current = wtCurrentPage()
	if current ~= allPages.Page then
		allPages.PrevPage = allPages.Page
		allPages.Page = current
		prefetchPending = {page = current, direction = 1}
		Timer.reset(prefetchTimer)
	end
	wtManageImages()
end

local function exit()
	for i = 1, #allPages do
		deletePageImage(i)
	end
	prefetchClear()
	allPages = {
		Page = 0
	}
	ParserManager.remove((((Chapters or {})[currentChapterNumber or 0] or {}).Pages) or 0)
	collectgarbage("step", 1024)
	AppMode = MENU
	ContextMenu = false
	MenuFade = 0
	toggleContextMenu = false
end

---Reader settings sheet (readersheet.lua). Always available while a chapter is open; the page actions (cover, save)
---are offered only when the current page can be used for them
local function openSettings()
	local chapter = Chapters[currentChapterNumber]
	if not chapter or not chapter.Manga then
		return
	end
	local page = allPages[allPages.Page or -1]
	if not (page and (page.Link or page.Path)) then
		page = nil
	end
	Extra.setChapters(chapter.Manga, chapter, page)
end

function Reader.input(oldPad, pad, oldTouch, touch, oldTouch2, touch2)
	-- Select: reader settings (layout, page colors, page actions), from any state of the reader
	if Controls.check(pad, SCE_CTRL_SELECT) and not Controls.check(oldPad, SCE_CTRL_SELECT) then
		openSettings()
		return
	end
	if Controls.check(pad, SCE_CTRL_CIRCLE) or ContextMenu and touch.x and touch.x < 88 and touch.y < 80 * MenuFade and not oldTouch.x then
		if allPages.Page > 0 then
			local bookmark
			if readDirection == "LEFT" then
				bookmark = allPages.Count - allPages.Page + 1
			else
				bookmark = allPages.Page
			end
			if bookmark == 1 then
				bookmark = nil
			elseif bookmark == allPages.Count then
				bookmark = true
			end
			if Cache.isCached(Chapters[currentChapterNumber].Manga) then
				Cache.setBookmark(Chapters[currentChapterNumber], bookmark)
			end
		end
		exit()
	end
	if currentState == STATE_READING and allPages[allPages.Page] then
		if ContextMenu then
			if touch.x and touch.y < 80 * MenuFade and not oldTouch.x then
				if touch.x > 960 - 88 then
					openSettings()
				elseif touch.x > 960 - 88 - 88 then
					if allPages[allPages.Page or -1] then
						deletePageImage(allPages.Page)
						loadPageImage(allPages.Page)
					end
				end
			end
		end
		if touch.x ~= nil or pad ~= 0 then
			Timer.reset(hideCounterTimer)
		end
		if is_webtoon then
			webtoonInput(oldPad, pad, oldTouch, touch, oldTouch2, touch2)
		else
			local page = allPages[allPages.Page]
			gesture_touch_input(touch, oldTouch, allPages[allPages.Page])
			if page.Zoom then
				local x, y = Controls.readLeftAnalog()
				x = x - 127
				y = y - 127
				if math.abs(x) > SCE_LEFT_STICK_DEADZONE then
					page.x = page.x - SCE_LEFT_STICK_SENSITIVITY * 25 * (x - SCE_LEFT_STICK_DEADZONE * math.sign(x)) / (128 - SCE_LEFT_STICK_DEADZONE)
				end
				if math.abs(y) > SCE_LEFT_STICK_DEADZONE then
					page.y = page.y - SCE_LEFT_STICK_SENSITIVITY * 25 * (y - SCE_LEFT_STICK_DEADZONE * math.sign(y)) / (128 - SCE_LEFT_STICK_DEADZONE)
				end
				if not ContextMenu then
					if Settings.ChangingPageButtons == "LR" then
						if Controls.check(pad, SCE_CTRL_UP) then
							page.y = page.y + 20
						elseif Controls.check(pad, SCE_CTRL_DOWN) then
							page.y = page.y - 20
						end
						if Controls.check(pad, SCE_CTRL_LEFT) then
							page.x = page.x + 20
						elseif Controls.check(pad, SCE_CTRL_RIGHT) then
							page.x = page.x - 20
						end
					end
				end
			end
			if math.abs(currentPageOffset.x) < 80 and math.abs(currentPageOffset.y) < 80 then
				if not ContextMenu then
					if not (Controls.check(pad, SCE_CTRL_RIGHTPAGE) or Controls.check(pad, SCE_CTRL_LEFTPAGE) or (Settings.ChangingPageButtons == "DPAD" and (Controls.check(pad, SCE_CTRL_DOWN) or Controls.check(pad, SCE_CTRL_UP)))) then
						buttonTimeSpace = 800
					end
					local right_page_button = Settings.ChangingPageButtons == "DPAD" and (orientation == "Horizontal" and (is_down and SCE_CTRL_DOWN or SCE_CTRL_RIGHT) or (orientation == "Vertical" and (is_down and SCE_CTRL_LEFT or SCE_CTRL_DOWN))) or SCE_CTRL_RIGHTPAGE
					local left_page_button = Settings.ChangingPageButtons == "DPAD" and (orientation == "Horizontal" and (is_down and SCE_CTRL_UP or SCE_CTRL_LEFT) or (orientation == "Vertical" and (is_down and SCE_CTRL_RIGHT or SCE_CTRL_UP))) or SCE_CTRL_LEFTPAGE
					if Controls.check(pad, right_page_button) and (buttonTimeSpace < Timer.getTime(buttonTimer) or not Controls.check(oldPad, right_page_button)) then
						turnPage("LEFT")
						buttonTimeSpace = math.max(buttonTimeSpace / 2, 10)
						Timer.reset(buttonTimer)
					elseif Controls.check(pad, left_page_button) and (buttonTimeSpace < Timer.getTime(buttonTimer) or not Controls.check(oldPad, left_page_button)) then
						turnPage("RIGHT")
						buttonTimeSpace = math.max(buttonTimeSpace / 2, 10)
						Timer.reset(buttonTimer)
					elseif Controls.check(pad, SCE_CTRL_SQUARE) then
						scale(0.95, page)
					elseif Controls.check(pad, SCE_CTRL_TRIANGLE) then
						scale(1.05, page)
					end
				end
				local x, y = Controls.readRightAnalog()
				if orientation == "Horizontal" then
					y = y - 127
					if math.abs(y) > SCE_RIGHT_STICK_DEADZONE then
						y = (y - SCE_RIGHT_STICK_DEADZONE * math.sign(y)) / (128 - SCE_RIGHT_STICK_DEADZONE)
						scale(1 - SCE_LEFT_STICK_SENSITIVITY * y * 0.05, page)
					end
				elseif orientation == "Vertical" then
					x = x - 127
					if math.abs(x) > SCE_RIGHT_STICK_DEADZONE then
						x = (x - SCE_RIGHT_STICK_DEADZONE * math.sign(x)) / (128 - SCE_RIGHT_STICK_DEADZONE)
						scale(1 + SCE_LEFT_STICK_SENSITIVITY * x * 0.05, page)
					end
				end
			end
			if touch.y and oldTouch.y and (not ContextMenu or touch.y < 544 - 80 and touch.y > 80 and oldTouch.y < 544 - 80 and oldTouch.y > 80) then
				if touchMode ~= TOUCH_MULTI then
					if touchMode == TOUCH_IDLE then
						touchTemp.x = touch.x
						touchTemp.y = touch.y
						touchMode = TOUCH_READ
					end
					velX = touch.x - oldTouch.x
					velY = touch.y - oldTouch.y
				end
				if touch2.x and oldTouch2.x and page.Zoom then
					touchMode = TOUCH_MULTI
					local old_Zoom = page.Zoom
					local center = {
						x = (touch.x + touch2.x) / 2,
						y = (touch.y + touch2.y) / 2
					}
					local n = (math.sqrt((touch.x - touch2.x) * (touch.x - touch2.x) + (touch.y - touch2.y) * (touch.y - touch2.y)) / math.sqrt((oldTouch.x - oldTouch2.x) * (oldTouch.x - oldTouch2.x) + (oldTouch.y - oldTouch2.y) * (oldTouch.y - oldTouch2.y)))
					scale(n, page)
					n = page.Zoom / old_Zoom
					page.y = page.y - (center.y - 272) * (n - 1)
					page.x = page.x - (center.x - 480) * (n - 1)
				end
			elseif ContextMenu and ((touch.y and (touch.y >= 544 - 80 or touch.y <= 80)) or (oldTouch.y and (oldTouch.y >= 544 - 80 or oldTouch.y <= 80))) then
				do
				end
			else
				if touchMode == TOUCH_SWIPE then
					if currentPageOffset.x > 90 or currentPageOffset.y > 90 then
						if orientation == "Vertical" and is_down then
							swipe("LEFT")
						else
							swipe("RIGHT")
						end
					elseif currentPageOffset.x < -90 or currentPageOffset.y < -90 then
						if orientation == "Vertical" and is_down then
							swipe("RIGHT")
						else
							swipe("LEFT")
						end
					end
					velX = 0
					velY = 0
					pageMode = PAGE_NONE
				end
				if touchMode ~= TOUCH_LOCK then
					if touchMode == TOUCH_READ then
						if Settings.PressEdgesToChangePage then
							if touchMode == TOUCH_READ and not touch.x and oldTouch.x then
								if orientation == "Vertical" then
									if is_down then
										if oldTouch.x > 480 + 180 then
											turnPage("RIGHT")
										elseif oldTouch.x < 480 - 180 then
											turnPage("LEFT")
										else
											toggleContextMenu = true
											Timer.reset(ToggleContextMenuTimer)
										end
									else
										if oldTouch.y > 272 + 120 then
											turnPage("LEFT")
										elseif oldTouch.y < 272 - 120 then
											turnPage("RIGHT")
										else
											toggleContextMenu = true
											Timer.reset(ToggleContextMenuTimer)
										end
									end
								elseif orientation == "Horizontal" then
									if is_down then
										if oldTouch.y > 272 + 120 then
											turnPage("LEFT")
										elseif oldTouch.y < 272 - 120 then
											turnPage("RIGHT")
										else
											toggleContextMenu = true
											Timer.reset(ToggleContextMenuTimer)
										end
									else
										if oldTouch.x > 480 + 180 then
											turnPage("LEFT")
										elseif oldTouch.x < 480 - 180 then
											turnPage("RIGHT")
										else
											toggleContextMenu = true
											Timer.reset(ToggleContextMenuTimer)
										end
									end
								end
							end
						else
							toggleContextMenu = true
							Timer.reset(ToggleContextMenuTimer)
						end
					end
					touchMode = TOUCH_IDLE
				end
			end
			if touchMode == TOUCH_READ and touchTemp.x and touch.x then
				local len = math.sqrt((touchTemp.x - touch.x) * (touchTemp.x - touch.x) + (touchTemp.y - touch.y) * (touchTemp.y - touch.y))
				if len > 10 then
					if orientation == "Horizontal" then
						if is_down then
							if not page.Zoom or (page.Width * page.Zoom < 961 or math.abs(touch.y - touchTemp.y) > math.abs(touch.x - touchTemp.x) * 1.5) and ((bit32.band(pageMode, PAGE_RIGHT) ~= 0 and touchTemp.y > touch.y) or (bit32.band(pageMode, PAGE_LEFT) ~= 0 and touchTemp.y < touch.y)) then
								touchMode = TOUCH_SWIPE
							else
								touchMode = TOUCH_MOVE
							end
						else
							if not page.Zoom or (page.Height * page.Zoom < 545 or math.abs(touch.x - touchTemp.x) > math.abs(touch.y - touchTemp.y) * 1.5) and ((bit32.band(pageMode, PAGE_RIGHT) ~= 0 and touchTemp.x > touch.x) or (bit32.band(pageMode, PAGE_LEFT) ~= 0 and touchTemp.x < touch.x)) then
								touchMode = TOUCH_SWIPE
							else
								touchMode = TOUCH_MOVE
							end
						end
					elseif orientation == "Vertical" then
						if is_down then
							if not page.Zoom or (page.Width * page.Zoom < 545 or math.abs(touch.x - touchTemp.x) > math.abs(touch.y - touchTemp.y) * 1.5) and ((bit32.band(pageMode, PAGE_RIGHT) ~= 0 and touchTemp.x > touch.x) or (bit32.band(pageMode, PAGE_LEFT) ~= 0 and touchTemp.x < touch.x)) then
								touchMode = TOUCH_SWIPE
							else
								touchMode = TOUCH_MOVE
							end
						else
							if not page.Zoom or (page.Height * page.Zoom < 961 or math.abs(touch.y - touchTemp.y) > math.abs(touch.x - touchTemp.x) * 1.5) and ((bit32.band(pageMode, PAGE_RIGHT) ~= 0 and touchTemp.y > touch.y) or (bit32.band(pageMode, PAGE_LEFT) ~= 0 and touchTemp.y < touch.y)) then
								touchMode = TOUCH_SWIPE
							else
								touchMode = TOUCH_MOVE
							end
						end
					end
				end
			end
		end
	elseif currentState == STATE_LOADING then
		if touch.x == nil and oldTouch.x ~= nil and (not ContextMenu or (oldTouch.y <= 544 - 80 and oldTouch.y >= 80)) then
			toggleContextMenu = true
			Timer.reset(ToggleContextMenuTimer)
		end
	end
	if ContextMenu and ((touch.y and (touch.y >= 544 - 80 or touch.y <= 80)) or (oldTouch.y and (oldTouch.y >= 544 - 80 or oldTouch.y <= 80))) then
		if (touch.y and touch.y >= 544 - 80 or oldTouch.y and oldTouch.y >= 544 - 80) and (touchMode == TOUCH_IDLE or touchMode == TOUCH_READ) then
			if touch.x and touch.x > 180 and touch.x < 780 and allPages.Count and allPages.Count > 1 then
				local newPage = math.min(math.max(1, math.floor((touch.x - 200) / (560 / (allPages.Count - 1)) + 1)), allPages.Count)
				if is_down and orientation == "Vertical" then
					newPage = allPages.Count - newPage + 1
				end
				if is_webtoon then
					wtGoTo(newPage)
				elseif newPage < allPages.Page then
					repeat
						swipe("RIGHT")
					until newPage == allPages.Page
					if readDirection == "LEFT" then
						allPages.PrevPage = allPages.Page + 1
					else
						allPages.PrevPage = allPages.Page - 1
					end
				elseif newPage > allPages.Page then
					repeat
						swipe("LEFT")
					until newPage == allPages.Page
					if readDirection == "LEFT" then
						allPages.PrevPage = allPages.Page + 1
					else
						allPages.PrevPage = allPages.Page - 1
					end
				end
			elseif not oldTouch.x and touch.x then
				if readDirection == "LEFT" or is_down and orientation == "Vertical" then
					if touch.x < 88 and currentChapterNumber < #Chapters then
						if Cache.isCached(Chapters[currentChapterNumber].Manga) then
							Cache.setBookmark(Chapters[currentChapterNumber], true)
						end
						Reader.loadChapter(currentChapterNumber + 1)
					elseif touch.x > 960 - 88 and currentChapterNumber > 1 then
						Reader.loadChapter(currentChapterNumber - 1)
						startPage = false
					end
				else
					if touch.x < 88 and currentChapterNumber > 1 then
						Reader.loadChapter(currentChapterNumber - 1)
						startPage = false
					elseif touch.x > 960 - 88 and currentChapterNumber < #Chapters then
						if Cache.isCached(Chapters[currentChapterNumber].Manga) then
							Cache.setBookmark(Chapters[currentChapterNumber], true)
						end
						Reader.loadChapter(currentChapterNumber + 1)
					end
				end
			end
		end
		OnTouchMenu = true
	else
		OnTouchMenu = false
	end
	if ContextMenu then
		if CursorIndex == -1 and (Controls.check(pad, SCE_CTRL_LEFT) or Controls.check(pad, SCE_CTRL_RIGHT) or Controls.check(pad, SCE_CTRL_UP) or Controls.check(pad, SCE_CTRL_DOWN)) then
			CursorIndex = 0
			CursorPoint = CreatePoint(32 + 12, 35)
			CursorDestination = CreatePoint(32 + 12, 35)
		elseif CursorIndex >= 0 and CursorIndex < #CursorPlaces then
			if not Controls.check(pad, SCE_CTRL_CROSS) then
				if currentState == STATE_READING then
					if CursorIndex > 2 then
						if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldPad, SCE_CTRL_UP) then
							CursorIndex = CursorIndex - 3
						elseif Controls.check(pad, SCE_CTRL_LEFT) and not Controls.check(oldPad, SCE_CTRL_LEFT) and CursorIndex > 3 then
							CursorIndex = CursorIndex - 1
						elseif Controls.check(pad, SCE_CTRL_RIGHT) and not Controls.check(oldPad, SCE_CTRL_RIGHT) and CursorIndex < 5 then
							CursorIndex = CursorIndex + 1
						end
					else
						if Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldPad, SCE_CTRL_DOWN) then
							CursorIndex = CursorIndex + 3
							if CursorIndex == 4 then
								CursorIndex = 5
							end
						elseif Controls.check(pad, SCE_CTRL_LEFT) and not Controls.check(oldPad, SCE_CTRL_LEFT) and CursorIndex > 0 then
							CursorIndex = CursorIndex - 1
						elseif Controls.check(pad, SCE_CTRL_RIGHT) and not Controls.check(oldPad, SCE_CTRL_RIGHT) and CursorIndex < 2 then
							CursorIndex = CursorIndex + 1
						end
					end
				elseif currentState == STATE_LOADING then
					if CursorIndex > 2 then
						if Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldPad, SCE_CTRL_UP) then
							CursorIndex = 0
						end
					else
						if Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldPad, SCE_CTRL_DOWN) then
							CursorIndex = 3
						elseif Controls.check(pad, SCE_CTRL_LEFT) and not Controls.check(oldPad, SCE_CTRL_LEFT) then
							CursorIndex = 3
						elseif Controls.check(pad, SCE_CTRL_RIGHT) and not Controls.check(oldPad, SCE_CTRL_RIGHT) then
							CursorIndex = 5
						end
					end
				end
			end
			if CursorIndex >= 0 then
				if Controls.check(pad, SCE_CTRL_CROSS) then
					if CursorIndex == 4 then
						if not (Controls.check(pad, SCE_CTRL_RIGHT) or Controls.check(pad, SCE_CTRL_LEFT)) then
							buttonTimeSpace = 400
						end
						local left = is_down and orientation == "Vertical" and SCE_CTRL_RIGHT or SCE_CTRL_LEFT
						local right = is_down and orientation == "Vertical" and SCE_CTRL_LEFT or SCE_CTRL_RIGHT
						if allPages.Page < allPages.Count and Controls.check(pad, right) and (buttonTimeSpace < Timer.getTime(buttonTimer) or not Controls.check(oldPad, right)) then
							wtTurn("LEFT")
							buttonTimeSpace = math.max(buttonTimeSpace / 2, 10)
							Timer.reset(buttonTimer)
						elseif allPages.Page > 1 and Controls.check(pad, left) and (buttonTimeSpace < Timer.getTime(buttonTimer) or not Controls.check(oldPad, left)) then
							wtTurn("RIGHT")
							buttonTimeSpace = math.max(buttonTimeSpace / 2, 10)
							Timer.reset(buttonTimer)
						end
					elseif not Controls.check(oldPad, SCE_CTRL_CROSS) then
						if CursorIndex == 0 then
							if allPages.Page > 0 then
								local bookmark
								if readDirection == "LEFT" then
									bookmark = allPages.Count - allPages.Page + 1
								else
									bookmark = allPages.Page
								end
								if bookmark == 1 then
									bookmark = nil
								elseif bookmark == allPages.Count then
									bookmark = true
								end
								if Cache.isCached(Chapters[currentChapterNumber].Manga) then
									Cache.setBookmark(Chapters[currentChapterNumber], bookmark)
								end
							end
							exit()
						elseif CursorIndex == 1 and currentState == STATE_READING then
							if allPages[allPages.Page or -1] then
								deletePageImage(allPages.Page)
								loadPageImage(allPages.Page)
							end
						elseif CursorIndex == 2 and currentState == STATE_READING then
							openSettings()
						else
							if readDirection == "LEFT" or is_down and orientation == "Vertical" then
								if CursorIndex == 3 and currentChapterNumber < #Chapters then
									if Cache.isCached(Chapters[currentChapterNumber].Manga) then
										Cache.setBookmark(Chapters[currentChapterNumber], true)
									end
									Reader.loadChapter(currentChapterNumber + 1)
								elseif CursorIndex == 5 and currentChapterNumber > 1 then
									Reader.loadChapter(currentChapterNumber - 1)
									startPage = false
								end
							else
								if CursorIndex == 3 and currentChapterNumber > 1 then
									Reader.loadChapter(currentChapterNumber - 1)
									startPage = false
								elseif CursorIndex == 5 and currentChapterNumber < #Chapters then
									if Cache.isCached(Chapters[currentChapterNumber].Manga) then
										Cache.setBookmark(Chapters[currentChapterNumber], true)
									end
									Reader.loadChapter(currentChapterNumber + 1)
								end
							end
						end
					end
				end
				if CursorIndex == 4 and currentState == STATE_READING then
					local current_page = allPages.Page
					current_page = math.max(1, math.min(current_page, allPages.Count))
					local point = 0
					if allPages.Count == 1 then
						point = 560
					else
						point = ((current_page - 1) * 560 / (allPages.Count - 1))
					end
					if readDirection == "LEFT" then
						CursorDestination = CreatePoint(200 + point, 544 - 40)
					elseif orientation == "Vertical" and is_down then
						if allPages.Count == 1 then
							point = 560
						else
							point = (((allPages.Count - allPages.Page + 1) - 1) * 560 / (allPages.Count - 1))
						end
						CursorDestination = CreatePoint(200 + point, 544 - 40)
					else
						CursorDestination = CreatePoint(200 + point, 544 - 40)
					end
				else
					CursorDestination = CursorPlaces[CursorIndex + 1]
				end
				CursorPoint.x = CursorPoint.x + (CursorDestination.x - CursorPoint.x) / 4
				CursorPoint.y = CursorPoint.y + (CursorDestination.y - CursorPoint.y) / 4
			end
		end
	end
	if touch.x or not ContextMenu then
		CursorIndex = -1
	end
	if Controls.check(pad, SCE_CTRL_START) and not Controls.check(oldPad, SCE_CTRL_START) then
		ContextMenu = not ContextMenu
	end
end

local counterShift = 0

function Reader.update()
	if toggleContextMenu and Timer.getTime(ToggleContextMenuTimer) > 300 then
		Timer.reset(chapterNameTickerTimer)
		Timer.reset(mangaNameTickerTimer)
		ContextMenu = not ContextMenu
		toggleContextMenu = false
	end
	if currentState == STATE_LOADING then
		if Chapters[currentChapterNumber].Pages.Done then
			if #Chapters[currentChapterNumber].Pages == 0 then
				Console.error("Error loading chapter")
				ParserManager.remove((((Chapters or {})[currentChapterNumber or 0] or {}).Pages) or 0)
				collectgarbage("collect")
				if Threads.isOnline() then
					Notifications.push(Language[Settings.Language].OTAKIO.NO_PAGES or "This chapter has no pages yet")
				else
					Notifications.push("Unknown error (No Connection?)")
				end
				AppMode = MENU
				return
			end
			currentState = STATE_READING
			local chapter = Chapters[currentChapterNumber]
			allPages.Count = #chapter.Pages
			if readDirection ~= "LEFT" then
				for i = 1, #chapter.Pages do
					allPages[#allPages + 1] = {
						chapter.Pages[i],
						Path = chapter.Pages[i].Path,
						Extract = chapter.Pages[i].Extract,
						x = 0,
						y = 0
					}
				end
			elseif readDirection == "LEFT" then
				for i = #chapter.Pages, 1, -1 do
					allPages[#allPages + 1] = {
						chapter.Pages[i],
						Path = chapter.Pages[i].Path,
						Extract = chapter.Pages[i].Extract,
						x = 0,
						y = 0
					}
				end
			end
			if readDirection ~= "LEFT" then
				startPage = startPage and startPage > 0 and startPage <= allPages.Count and startPage or startPage == false and -1 or nil
				if startPage == -1 then
					startPage = false
				end
				if currentChapterNumber ~= 1 then
					allPages[0] = {
						Link = "LoadPrev",
						x = 0,
						y = 0
					}
				end
				if currentChapterNumber < #Chapters then
					allPages[#allPages + 1] = {
						Link = "LoadNext",
						x = 0,
						y = 0
					}
				end
				if startPage then
					allPages.Page = startPage - 1
					changePage(startPage)
				elseif startPage == false then
					allPages.Page = allPages.Count + 1
					changePage(allPages.Count)
				else
					allPages.Page = 0
					changePage(1)
				end
				startPage = nil
			elseif readDirection == "LEFT" then
				startPage = startPage and startPage > 0 and startPage <= allPages.Count and startPage or startPage == false and -1 or nil
				if startPage == -1 then
					startPage = false
				end
				if currentChapterNumber < #Chapters then
					allPages[0] = {
						Link = "LoadNext",
						x = 0,
						y = 0
					}
				end
				if currentChapterNumber ~= 1 then
					allPages[#allPages + 1] = {
						Link = "LoadPrev",
						x = 0,
						y = 0
					}
				end
				if startPage then
					allPages.Page = allPages.Count - startPage + 2
					changePage(allPages.Count + 1 - startPage)
				elseif startPage == false then
					allPages.Page = 0
					changePage(1)
				else
					allPages.Page = allPages.Count + 1
					changePage(allPages.Count)
				end
				startPage = nil
			end
			if is_webtoon then
				wtStart()
			end
			Timer.reset(hideCounterTimer)
		end
	elseif currentState == STATE_READING then
		if not allPages[allPages.Page] then
			return
		end
		if prefetchPending then
			local shown = allPages[prefetchPending.page]
			if prefetchPending.page ~= allPages.Page then
				prefetchPending.page = allPages.Page
			elseif (shown and shown.Image) or Timer.getTime(prefetchTimer) > 2500 then
				prefetchFrom(prefetchPending.page, prefetchPending.direction)
				prefetchPending = nil
			end
		end
		if is_webtoon then
			webtoonUpdate()
			return
		end
		gesture_touch_update()
		if allPages.PrevPage and allPages.PrevPage ~= allPages.Page and (((is_down and currentPageOffset.y or currentPageOffset.x) >= 0 and allPages.PrevPage > allPages.Page or (is_down and currentPageOffset.y or currentPageOffset.x) <= 0 and allPages.PrevPage < allPages.Page) and orientation == "Horizontal" or ((is_down and -currentPageOffset.x or currentPageOffset.y) >= 0 and allPages.PrevPage > allPages.Page or (is_down and -currentPageOffset.x or currentPageOffset.y) <= 0 and allPages.PrevPage < allPages.Page) and orientation == "Vertical") then
			if allPages.PrevPage > 0 and allPages.PrevPage <= #allPages then
				deletePageImage(allPages.PrevPage)
			end
			local p = allPages.Page + math.sign(allPages.Page - allPages.PrevPage)
			if p > 0 and p <= #allPages then
				if not allPages[p].Image and not (allPages[p].Link == "LoadPrev" or allPages[p].Link == "LoadNext") then
					if allPages[p].Extract then
						local new_page = allPages[p]
						Threads.addTask(
							new_page,
							{
								Type = "UnZipFile",
								Path = new_page.Path,
								Extract = new_page.Extract,
								DestPath = "ux0:data/otakio/temp/cache.image",
								OnComplete = function()
									Threads.insertTask(
										new_page,
										{
											Type = "Image",
											Table = new_page,
											Path = "temp/cache.image",
											Index = "Image"
										}
									)
								end
							}
						)
					elseif allPages[p].Path then
						Threads.addTask(
							allPages[p],
							{
								Type = "Image",
								Path = allPages[p].Path,
								Table = allPages[p],
								Index = "Image"
							}
						)
					else
						requestRemotePage(allPages[p], false)
					end
				end
			end
		end
		local o = readDirection == "LEFT" and {1, -1, 0} or {-1, 1, 0}
		for k = 1, #o do
			local i = o[k]
			local page = allPages[allPages.Page + i]
			if page and not page.Zoom and page.Image then
				local Image = page.Image
				if orientation == "Horizontal" then
					if is_down then
						page.Width, page.Height, page.x, page.y = Image.Width, Image.Height, 480, 272 + i * 544
						Console.write("Added " .. allPages.Page + i)
						if autozoom == "Smart" then
							if page.Width < page.Height then
								page.Zoom = 960 / page.Width
							else
								page.Zoom = 544 / page.Height
							end
						elseif autozoom == "Width" then
							page.Zoom = 960 / page.Width
						elseif autozoom == "Height" then
							page.Zoom = 544 / page.Height
						else
							page.Zoom = 960 / page.Width
						end
						if page.Height * page.Zoom >= 544 then
							if i == 0 then
								if allPages.PrevPage > allPages.Page then
									page.y = page.y + (544 - page.Height * page.Zoom) / 2
								elseif allPages.PrevPage < allPages.Page then
									page.y = page.y - (544 - page.Height * page.Zoom) / 2
								end
							else
								page.y = page.y - i * (544 - page.Height * page.Zoom) / 2
							end
						end
						page.min_Zoom = math.min(544 / page.Height, 960 / page.Width)
						if page.Zoom * page.Width > 960 then
							page.x = 960 - (page.Width * page.Zoom) / 2
						end
						page.start_Zoom = page.Zoom
					else
						page.Width, page.Height, page.x, page.y = Image.Width, Image.Height, 480 + i * 960, 272
						Console.write("Added " .. allPages.Page + i)
						if autozoom == "Smart" then
							if page.Width > page.Height then
								page.Zoom = 544 / page.Height
							else
								page.Zoom = 960 / page.Width
							end
						elseif autozoom == "Width" then
							page.Zoom = 960 / page.Width
						elseif autozoom == "Height" then
							page.Zoom = 544 / page.Height
						end
						if page.Width * page.Zoom >= 960 then
							if i == 0 then
								if allPages.PrevPage > allPages.Page then
									page.x = page.x + (960 - page.Width * page.Zoom) / 2
								elseif allPages.PrevPage < allPages.Page then
									page.x = page.x - (960 - page.Width * page.Zoom) / 2
								end
							else
								page.x = page.x - i * (960 - page.Width * page.Zoom) / 2
							end
						end
						page.min_Zoom = math.min(544 / page.Height, 960 / page.Width)
						if page.Zoom * page.Height > 544 then
							page.y = page.Zoom * page.Height / 2
						end
						page.start_Zoom = page.Zoom
					end
				elseif orientation == "Vertical" then
					if is_down then
						page.Width, page.Height, page.x, page.y = Image.Width, Image.Height, 480 - i * 960, 272
						Console.write("Added " .. allPages.Page + i)
						if autozoom == "Smart" then
							if page.Width > page.Height then
								page.Zoom = 960 / page.Height
							else
								page.Zoom = 544 / page.Width
							end
						elseif autozoom == "Width" then
							page.Zoom = 544 / page.Width
						elseif autozoom == "Height" then
							page.Zoom = 960 / page.Height
						else
							page.Zoom = 544 / page.Width
						end
						if page.Height * page.Zoom >= 960 then
							if i == 0 then
								if allPages.PrevPage > allPages.Page then
									page.x = page.x - (960 - page.Height * page.Zoom) / 2
								elseif allPages.PrevPage < allPages.Page then
									page.x = page.x + (960 - page.Height * page.Zoom) / 2
								end
							else
								page.x = page.x + i * (960 - page.Height * page.Zoom) / 2
							end
						end
						page.min_Zoom = math.min(960 / page.Height, 544 / page.Width)
						if page.Zoom * page.Width > 544 then
							page.y = 544 - (page.Zoom * page.Width) / 2
						end
						page.start_Zoom = page.Zoom
					else
						page.Width, page.Height, page.x, page.y = Image.Width, Image.Height, 480, 272 + i * 544
						Console.write("Added " .. allPages.Page + i)
						if autozoom == "Smart" then
							if page.Width > page.Height then
								page.Zoom = 960 / page.Height
							else
								page.Zoom = 544 / page.Width
							end
						elseif autozoom == "Width" then
							page.Zoom = 544 / page.Width
						elseif autozoom == "Height" then
							page.Zoom = 960 / page.Height
						end
						if page.Width * page.Zoom >= 544 then
							if i == 0 then
								if allPages.PrevPage > allPages.Page then
									page.y = page.y + (544 - page.Width * page.Zoom) / 2
								elseif allPages.PrevPage < allPages.Page then
									page.y = page.y - (544 - page.Width * page.Zoom) / 2
								end
							else
								page.y = page.y - i * (544 - page.Width * page.Zoom) / 2
							end
						end
						page.min_Zoom = math.min(960 / page.Height, 544 / page.Width)
						if page.Zoom * page.Height > 960 then
							page.x = 960 - (page.Zoom * page.Height) / 2
						end
						page.start_Zoom = page.Zoom
					end
				end
			end
		end
		if touchMode == TOUCH_IDLE or touchMode == TOUCH_MOVE then
			local page = allPages[allPages.Page]
			if page and page.Zoom then
				page.x = page.x + velX
				page.y = page.y + velY
			end
			if touchMode == TOUCH_IDLE or OnTouchMenu then
				velY = velY * 0.9
				velX = velX * 0.9
			end
		elseif touchMode == TOUCH_SWIPE then
			if (orientation == "Horizontal" and not is_down) or (orientation == "Vertical" and is_down) then
				if orientation == "Vertical" then
					currentPageOffset.x = currentPageOffset.x + velX
					if currentPageOffset.x < 0 and not allPages[allPages.Page - 1] then
						currentPageOffset.x = 0
					elseif currentPageOffset.x > 0 and allPages.Page == #allPages then
						currentPageOffset.x = 0
					end
				else
					currentPageOffset.x = currentPageOffset.x + velX
					if currentPageOffset.x > 0 and not allPages[allPages.Page - 1] then
						currentPageOffset.x = 0
					elseif currentPageOffset.x < 0 and allPages.Page == #allPages then
						currentPageOffset.x = 0
					end
				end
			else
				currentPageOffset.y = currentPageOffset.y + velY
				if currentPageOffset.y > 0 and not allPages[allPages.Page - 1] then
					currentPageOffset.y = 0
				elseif currentPageOffset.y < 0 and allPages.Page == #allPages then
					currentPageOffset.y = 0
				end
			end
		end
		if touchMode ~= TOUCH_SWIPE then
			local dir = "x"
			if orientation == "Vertical" and not is_down or orientation == "Horizontal" and is_down then
				dir = "y"
			end
			currentPageOffset[dir] = currentPageOffset[dir] / 1.3
			if math.abs(currentPageOffset[dir]) < 1 then
				currentPageOffset[dir] = 0
				if allPages[allPages.Page] and allPages[allPages.Page].Link == "LoadNext" then
					Cache.setBookmark(Chapters[currentChapterNumber], true)
					Reader.loadChapter(currentChapterNumber + 1)
					return
				end
				if allPages[allPages.Page] and allPages[allPages.Page].Link == "LoadPrev" then
					Cache.setBookmark(Chapters[currentChapterNumber], nil)
					startPage = false
					Reader.loadChapter(currentChapterNumber - 1)
					return
				end
			end
		end
		local page = allPages[allPages.Page]
		if orientation == "Horizontal" then
			if is_down then
				if page.Zoom then
					if page.Width * page.Zoom < 960 then
						page.x = 480
					elseif page.x - page.Width / 2 * page.Zoom > 0 then
						page.x = page.Width / 2 * page.Zoom
					elseif page.x + page.Width / 2 * page.Zoom < 960 then
						page.x = 960 - page.Width / 2 * page.Zoom
					end
					if page.Zoom * page.Height > 545 then
						if page.y - page.Height / 2 * page.Zoom >= 0 then
							page.y = page.Height / 2 * page.Zoom
							if allPages[allPages.Page - 1] then
								pageMode = PAGE_LEFT
							else
								pageMode = PAGE_NONE
							end
						elseif page.y + page.Height / 2 * page.Zoom <= 544 then
							page.y = 544 - page.Height / 2 * page.Zoom
							if allPages.Page ~= #allPages then
								pageMode = PAGE_RIGHT
							else
								pageMode = PAGE_NONE
							end
						else
							pageMode = PAGE_NONE
						end
					else
						page.y = 272
						pageMode = PAGE_LEFT + PAGE_RIGHT
					end
				else
					pageMode = PAGE_LEFT + PAGE_RIGHT
				end
			else
				if page.Zoom then
					if page.Height * page.Zoom < 544 then
						page.y = 272
					elseif page.y - page.Height / 2 * page.Zoom > 0 then
						page.y = page.Height / 2 * page.Zoom
					elseif page.y + page.Height / 2 * page.Zoom < 544 then
						page.y = 544 - page.Height / 2 * page.Zoom
					end
					if page.Zoom * page.Width > 961 then
						if page.x - page.Width / 2 * page.Zoom >= 0 then
							page.x = page.Width / 2 * page.Zoom
							if allPages[allPages.Page - 1] then
								pageMode = PAGE_LEFT
							else
								pageMode = PAGE_NONE
							end
						elseif page.x + page.Width / 2 * page.Zoom <= 960 then
							page.x = 960 - page.Width / 2 * page.Zoom
							if allPages.Page ~= #allPages then
								pageMode = PAGE_RIGHT
							else
								pageMode = PAGE_NONE
							end
						else
							pageMode = PAGE_NONE
						end
					else
						page.x = 480
						pageMode = PAGE_LEFT + PAGE_RIGHT
					end
				else
					pageMode = PAGE_LEFT + PAGE_RIGHT
				end
			end
		elseif orientation == "Vertical" then
			if is_down then
				if page.Zoom then
					if page.Width * page.Zoom < 544 then
						page.y = 272
					elseif page.y - page.Width / 2 * page.Zoom > 0 then
						page.y = page.Width / 2 * page.Zoom
					elseif page.y + page.Width / 2 * page.Zoom < 544 then
						page.y = 544 - page.Width / 2 * page.Zoom
					end
					if page.Zoom * page.Height > 961 then
						if page.x - page.Height / 2 * page.Zoom >= 0 then
							page.x = page.Height / 2 * page.Zoom
							if allPages.Page ~= #allPages then
								pageMode = PAGE_LEFT
							else
								pageMode = PAGE_NONE
							end
						elseif page.x + page.Height / 2 * page.Zoom <= 960 then
							page.x = 960 - page.Height / 2 * page.Zoom
							if allPages[allPages.Page - 1] then
								pageMode = PAGE_RIGHT
							else
								pageMode = PAGE_NONE
							end
						else
							pageMode = PAGE_NONE
						end
					else
						page.x = 480
						pageMode = PAGE_LEFT + PAGE_RIGHT
					end
				else
					pageMode = PAGE_LEFT + PAGE_RIGHT
				end
			else
				if page.Zoom then
					if page.Height * page.Zoom < 960 then
						page.x = 480
					elseif page.x - page.Height / 2 * page.Zoom > 0 then
						page.x = page.Height / 2 * page.Zoom
					elseif page.x + page.Height / 2 * page.Zoom < 960 then
						page.x = 960 - page.Height / 2 * page.Zoom
					end
					if page.Zoom * page.Width > 545 then
						if page.y - page.Width / 2 * page.Zoom >= 0 then
							page.y = page.Width / 2 * page.Zoom
							if allPages[allPages.Page - 1] then
								pageMode = PAGE_LEFT
							else
								pageMode = PAGE_NONE
							end
						elseif page.y + page.Width / 2 * page.Zoom <= 544 then
							page.y = 544 - page.Width / 2 * page.Zoom
							if allPages.Page ~= #allPages then
								pageMode = PAGE_RIGHT
							else
								pageMode = PAGE_NONE
							end
						else
							pageMode = PAGE_NONE
						end
					else
						page.y = 272
						pageMode = PAGE_LEFT + PAGE_RIGHT
					end
				else
					pageMode = PAGE_LEFT + PAGE_RIGHT
				end
			end
		end
		if Timer.getTime(hideCounterTimer) > 1500 or MenuFade > 0 then
			counterShift = math.max(counterShift - 1.5, -30)
		else
			counterShift = math.min(counterShift + 1.5, 0)
		end
	end
	if ContextMenu then
		MenuFade = math.min(MenuFade + 0.1, 1)
	else
		MenuFade = math.max(MenuFade - 0.1, 0)
	end
	if CursorIndex >= 0 then
		CursorFade = math.min(CursorFade + 0.1, 1)
	else
		CursorFade = math.max(CursorFade - 0.1, 0)
	end
end

local PI = math.pi

---Tall (webtoon) pages are "lazy": only the slices within a screen of the viewport are decoded, the ones two
---screens away are freed. `center`/`half` are the slice center and half size on the scroll axis, `axis` the
---screen size on that axis.
local function lazySliceTick(image, k, center, half, axis)
	local slice = image[k]
	if center + half > -axis and center - half < axis * 2 then
		if not slice and not (image.Keys[k] and Threads.check(image.Keys[k])) then
			image.Keys[k] = image.Keys[k] or {}
			local visible = center + half > 0 and center - half < axis
			Threads.insertTask(image.Keys[k], {Type = "ImageSlice", Plan = image, Slice = k, Priority = visible and Threads.URGENT or Threads.NORMAL})
		end
	elseif center + half < -axis * 2 or center - half > axis * 3 then
		if slice and slice.free then
			slice:free()
			image[k] = nil
		elseif image.Keys[k] then
			Threads.remove(image.Keys[k])
		end
	end
end

---Page textures go through the reader look (readersheet.lua): tinted when brightness or a Multiply filter is set
local drawImageExtended = Graphics.drawImageExtended
local pageTint = nil
local function drawPage(x, y, tex, sx, sy, w, h, rot, zx, zy)
	if pageTint then
		drawImageExtended(x, y, tex, sx, sy, w, h, rot, zx, zy, pageTint)
	else
		drawImageExtended(x, y, tex, sx, sy, w, h, rot, zx, zy)
	end
end

---Webtoon drawing in reading coordinates: (x, y) is the center; in the Vertical orientation it is turned onto the screen
local function wtImage(x, y, tex, w, h, z)
	if wtVertical then
		drawPage(960 - y, x, tex, 0, 0, w, h, PI / 2, z, z)
	else
		drawPage(x, y, tex, 0, 0, w, h, 0, z, z)
	end
end

---A text centered at (x, y) of the reading view (the text itself stays level)
local function wtText(font, x, y, text, color)
	local w = Font.getTextWidth(font, text)
	if wtVertical then
		x, y = 960 - y, x
	end
	Font.print(font, x - w / 2, y - 10, text, color)
end

---A loading bar centered at (x, y) of the reading view
local function wtBar(x, y, progress)
	if wtVertical then
		x, y = 960 - y, x
	end
	Graphics.fillEmptyRect(x - 52, x + 53, y - 6, y + 6, COLOR_FONT)
	Graphics.fillRect(x - 50, x - 50 + 100 * progress, y - 4, y + 3, COLOR_FONT)
end

---Webtoon mode: the pages one under the other from the view's page down, the loading texts, the notes at the ends
local function webtoonDraw()
	local count = allPages.Count or 0
	if count == 0 then
		return
	end
	local R = Language[Settings.Language].READER
	local dots = string.sub("...", 1, math.ceil(Timer.getTime(GlobalTimer) / 250) % 4)
	local cx = WT_W / 2 + wt.x
	local y = -wt.offset
	local p = wt.page
	while p <= count and y < WT_H do
		local page = allPages[p]
		local h = wtHeight(page)
		if y + h > 0 then
			local img = page.Image
			if img and img.Lazy then
				local z = wtScale(page)
				local sh = img.SliceHeight * z
				for k = 1, img.Parts do
					local top = y + (k - 1) * sh
					lazySliceTick(img, k, top + sh / 2, sh / 2, WT_H)
					local slice = img[k]
					if slice and slice.e then
						local hh = Graphics.getImageHeight(slice.e)
						wtImage(cx, top + hh * z / 2, slice.e, img.Width, hh, z)
					elseif top < WT_H and top + sh > 0 then
						wtText(FONT16, cx, math.max(top, 0) + 20, R.LOADING_SEGMENT .. dots, COLOR_FONT)
					end
				end
			elseif img then
				local w, ih = wtImageSize(page)
				local tex = img.e or (img[1] and img[1].Image and img[1].Image.e)
				if tex and w then
					local z = wtScale(page)
					wtImage(cx, y + h / 2, tex, w, ih, z)
				end
			else
				local ty = (math.max(y, 0) + math.min(y + h, WT_H)) / 2
				wtText(FONT16, cx, ty, R.LOADING_PAGE .. dots, COLOR_FONT)
				if wtVertical then
					wtBar(cx + 26, ty, Threads.getProgress(page))
				else
					wtBar(cx, ty + 26, Threads.getProgress(page))
				end
			end
		end
		y = y + h
		p = p + 1
	end
	-- the transition screen after the last page: the next chapter (scroll on or press R) or the end of the title
	if p > count and y < WT_H then
		local text, name
		if currentChapterNumber < #Chapters then
			text, name = R.WT_NEXT, tostring(Chapters[currentChapterNumber + 1].Name or "")
		else
			text = R.WT_LAST
		end
		-- the texts stay level: in the Vertical orientation the next line goes along the reading view's width
		local ty = y + WT_H / 2
		local nx, ny = WT_W / 2, ty + 30
		if wtVertical then
			nx, ny = WT_W / 2 + 30, ty
		end
		wtText(BONT16, WT_W / 2, ty, text, COLOR_FONT)
		if name then
			wtText(FONT16, nx, ny, name, COLOR_SUBFONT)
		end
	end
	if wt.overTop > 0 and currentChapterNumber > 1 then
		local text = R.WT_PREV
		wtText(BONT16, WT_W / 2, wt.overTop / 2, text, COLOR_FONT)
	end
end

function Reader.draw()
	pageTint = ReaderLook.tint()
	Screen.clear(currentState == STATE_READING and ReaderLook.background() or COLOR_BACK)
	if currentState == STATE_LOADING then
		local manga_name = Chapters[currentChapterNumber].Manga.Name
		local prepare_message = Language[Settings.Language].READER.PREPARING_PAGES .. string.sub("...", 1, math.ceil(Timer.getTime(GlobalTimer) / 250) % 4)
		local chapter_name = Chapters[currentChapterNumber].Name
		if Font.getTextWidth(BONT30, manga_name) > 960 then
			Font.print(FONT16, 480 - Font.getTextWidth(FONT16, manga_name) / 2, 242, manga_name, COLOR_FONT)
		else
			Font.print(BONT30, 480 - Font.getTextWidth(BONT30, manga_name) / 2, 232, manga_name, COLOR_FONT)
		end
		Font.print(FONT16, 480 - Font.getTextWidth(FONT16, chapter_name) / 2, 264, chapter_name, COLOR_FONT)
		Font.print(FONT16, 480 - Font.getTextWidth(FONT16, prepare_message) / 2, 284, prepare_message, COLOR_FONT)
	elseif currentState == STATE_READING then
		if is_webtoon then
			webtoonDraw()
		end
		local o = readDirection == "LEFT" and {1, -1, 0} or {-1, 1, 0}
		for j = 1, is_webtoon and 0 or #o do
			local i = o[j]
			local page = allPages[allPages.Page + i]
			if page and page.Image then
				if type(page.Image.e or page.Image) == "table" and page.Image.Parts then
					for k = 1, page.Image.Parts do
						if page.Image.Lazy then
							local half = page.Image.SliceHeight / 2 * page.Zoom
							if orientation == "Horizontal" then
								lazySliceTick(page.Image, k, currentPageOffset.y + page.y + (k - 1) * page.Image.SliceHeight * page.Zoom - page.Height / 2 * page.Zoom + half, half, 544)
							else
								lazySliceTick(page.Image, k, currentPageOffset.x + page.x - (k - 1) * page.Image.SliceHeight * page.Zoom + page.Height / 2 * page.Zoom - half, half, 960)
							end
						end
						if page.Image[k] and page.Image[k].e then
							local Height = Graphics.getImageHeight(page.Image[k].e)
							if orientation == "Horizontal" then
								local x, y = math.ceil((currentPageOffset.x + page.x) * 4) / 4, currentPageOffset.y + page.y + (k - 1) * page.Image.SliceHeight * page.Zoom - page.Height / 2 * page.Zoom + page.Image.SliceHeight / 2 * page.Zoom
								Graphics.fillRect(x - page.Width / 2 * page.Zoom, x + page.Width / 2 * page.Zoom, y - Height / 2 * page.Zoom, y + Height / 2 * page.Zoom, COLOR_BLACK)
								drawPage(x, y, page.Image[k].e, 0, 0, page.Width, Height, 0, page.Zoom, page.Zoom)
							elseif orientation == "Vertical" then
								local x, y = math.ceil((currentPageOffset.x + page.x) * 4) / 4 - (k - 1) * page.Image.SliceHeight * page.Zoom + page.Height / 2 * page.Zoom - page.Image.SliceHeight / 2 * page.Zoom, currentPageOffset.y + page.y
								Graphics.fillRect(x - Height / 2 * page.Zoom, x + Height / 2 * page.Zoom, y - page.Width / 2 * page.Zoom, y + page.Width / 2 * page.Zoom, COLOR_BLACK)
								drawPage(x, y, page.Image[k].e, 0, 0, page.Width, Height, PI / 2, page.Zoom, page.Zoom)
							end
						else
							if orientation == "Horizontal" then
								local loading = Language[Settings.Language].READER.LOADING_SEGMENT .. string.sub("...", 1, math.ceil(Timer.getTime(GlobalTimer) / 250) % 4)
								local Width = Font.getTextWidth(FONT16, loading)
								Font.print(FONT16, currentPageOffset.x + 960 * i + 480 - Width / 2, currentPageOffset.y + page.y + (k - 1) * page.Image.SliceHeight * page.Zoom - page.Height / 2 * page.Zoom + 10 * page.Zoom, loading, COLOR_FONT)
							elseif orientation == "Vertical" then
								local loading = Language[Settings.Language].READER.LOADING_SEGMENT .. string.sub("...", 1, math.ceil(Timer.getTime(GlobalTimer) / 250) % 4)
								local Width = Font.getTextWidth(FONT16, loading)
								Font.print(FONT16, currentPageOffset.x - Width + page.x - ((k - 1) * page.Image.SliceHeight * page.Zoom - page.Height / 2 * page.Zoom + 10 * page.Zoom), currentPageOffset.y + 272 + 544 * i, loading, COLOR_FONT)
							end
						end
					end
				else
					if type(page.Image.e or page.Image) == "table" then
						local all_delay = 0
						for k = 1, #page.Image do
							all_delay = all_delay + page.Image[k].Delay
						end
						local anim_timer = Timer.getTime(GlobalTimer) % all_delay
						local frame = 1
						for k = 1, #page.Image do
							if anim_timer > page.Image[k].Delay then
								frame = frame + 1
								anim_timer = anim_timer - page.Image[k].Delay
							else
								break
							end
						end
						if page.Image[frame] and page.Image[frame].Image and page.Image[frame].Image.e then
							local x, y = math.ceil((currentPageOffset.x + page.x) * 4) / 4, math.ceil((currentPageOffset.y + page.y) * 4) / 4
							if orientation == "Horizontal" then
								Graphics.fillRect(x - page.Width / 2 * page.Zoom, x + page.Width / 2 * page.Zoom, y - page.Height / 2 * page.Zoom, y + page.Height / 2 * page.Zoom, COLOR_BLACK)
								drawPage(x, y, page.Image[frame].Image.e, 0, 0, page.Width, page.Height, 0, page.Zoom, page.Zoom)
							elseif orientation == "Vertical" then
								Graphics.fillRect(x - page.Height / 2 * page.Zoom, x + page.Height / 2 * page.Zoom, y - page.Width / 2 * page.Zoom, y + page.Width / 2 * page.Zoom, COLOR_BLACK)
								drawPage(x, y, page.Image[frame].Image.e, 0, 0, page.Width, page.Height, PI / 2, page.Zoom, page.Zoom)
							end
						end
					else
						local x, y = math.ceil((currentPageOffset.x + page.x) * 4) / 4, math.ceil((currentPageOffset.y + page.y) * 4) / 4
						if orientation == "Horizontal" then
							Graphics.fillRect(x - page.Width / 2 * page.Zoom, x + page.Width / 2 * page.Zoom, y - page.Height / 2 * page.Zoom, y + page.Height / 2 * page.Zoom, COLOR_BLACK)
							drawPage(x, y, page.Image.e, 0, 0, page.Width, page.Height, 0, page.Zoom, page.Zoom)
						elseif orientation == "Vertical" then
							Graphics.fillRect(x - page.Height / 2 * page.Zoom, x + page.Height / 2 * page.Zoom, y - page.Width / 2 * page.Zoom, y + page.Width / 2 * page.Zoom, COLOR_BLACK)
							drawPage(x, y, page.Image.e, 0, 0, page.Width, page.Height, PI / 2, page.Zoom, page.Zoom)
						end
					end
				end
			elseif page then
				local precentage = Threads.getProgress(page)
				local loading = Language[Settings.Language].READER.LOADING_PAGE .. string.sub("...", 1, math.ceil(Timer.getTime(GlobalTimer) / 250) % 4)
				local Width = Font.getTextWidth(FONT16, loading)
				if orientation == "Horizontal" then
					Font.print(FONT16, currentPageOffset.x + 960 * (is_down and 0 or i) + 480 - Width / 2, 272 + currentPageOffset.y + 544 * (is_down and i or 0) - 10, loading, COLOR_FONT)
					Graphics.fillEmptyRect(currentPageOffset.x + 960 * (is_down and 0 or i) + 480 - 52, currentPageOffset.x + 960 * (is_down and 0 or i) + 480 + 53, 272 + currentPageOffset.y + 544 * (is_down and i or 0) + 20, 272 + currentPageOffset.y + 544 * (is_down and i or 0) + 32, COLOR_FONT)
					Graphics.fillRect(currentPageOffset.x + 960 * (is_down and 0 or i) + 480 - 50, currentPageOffset.x + 960 * (is_down and 0 or i) + 480 - 50 + 100 * precentage, 272 + currentPageOffset.y + 544 * (is_down and i or 0) + 22, 272 + currentPageOffset.y + 544 * (is_down and i or 0) + 29, COLOR_FONT)
				elseif orientation == "Vertical" then
					Font.print(FONT16, 960 / 2 - Width / 2 + currentPageOffset.x + 960 * (is_down and i or 0), 272 + currentPageOffset.y + 544 * (is_down and 0 or i) - 10, loading, COLOR_FONT)
					Graphics.fillEmptyRect(currentPageOffset.x + 960 * (is_down and i or 0) + 480 - 52, currentPageOffset.x + 960 * (is_down and i or 0) + 480 + 53, 272 + currentPageOffset.y + 544 * (is_down and 0 or i) + 20, 272 + currentPageOffset.y + 544 * (is_down and 0 or i) + 32, COLOR_FONT)
					Graphics.fillRect(currentPageOffset.x + 960 * (is_down and i or 0) + 480 - 50, currentPageOffset.x + 960 * (is_down and i or 0) + 480 - 50 + 100 * precentage, 272 + currentPageOffset.y + 544 * (is_down and 0 or i) + 22, 272 + currentPageOffset.y + 544 * (is_down and 0 or i) + 29, COLOR_FONT)
				end
			end
		end
		local overlay = ReaderLook.overlay()
		if overlay then
			Graphics.fillRect(0, 960, 0, 544, overlay)
		end
		if ReaderLook.showPageNumber() and allPages.Page <= (allPages.Count or 0) and allPages.Page > 0 then
			local Counter = allPages.Page .. "/" .. allPages.Count
			if readDirection == "LEFT" then
				Counter = (allPages.Count - allPages.Page + 1) .. "/" .. allPages.Count
			end
			local Width = Font.getTextWidth(FONT16, Counter) + 20
			Graphics.fillRect(960 - Width, 960, counterShift, counterShift + Font.getTextHeight(FONT16, Counter) + 4, Color.new(0, 0, 0, 128))
			Font.print(FONT16, 970 - Width, counterShift, Counter, COLOR_WHITE)
		end
	end
	if MenuFade > 0 then
		local BACK_COLOR = CloneColorWithNewAlpha(COLOR_SURFACE, 245 * MenuFade) -- the theme's bars, like the rest of Otakio
		local GRAY_COLOR = CloneColorWithNewAlpha(COLOR_SURFACE2, 255 * MenuFade)
		local BLUE_COLOR = CloneColorWithNewAlpha(COLOR_ACCENT, 255 * MenuFade)
		Graphics.fillRect(88, 960 - 88 - 32 - 24 - 32, 0, 80 * MenuFade, BACK_COLOR)
		Graphics.fillRect(0, 960, 544 - 80 * MenuFade, 544, BACK_COLOR)
		if currentState == STATE_READING then
			local current_page = allPages.Page
			current_page = math.max(1, math.min(current_page, allPages.Count))
			local point = 0
			if allPages.Count == 1 then
				point = 560
			else
				point = ((current_page - 1) * 560 / (allPages.Count - 1))
			end
			if readDirection == "LEFT" then
				Graphics.fillRect(200, 760, 544 - 80 * MenuFade + 39, 544 - 80 * MenuFade + 41, BLUE_COLOR)
				Graphics.fillRect(200, 200 + point, 544 - 80 * MenuFade + 39, 544 - 80 * MenuFade + 41, GRAY_COLOR)
				Graphics.drawImage(200 + point - 6, 544 - 80 * MenuFade + 40 - 6, CircleIcon.e, BLUE_COLOR)
				current_page = (allPages.Count - allPages.Page + 1)
				current_page = math.max(1, math.min(current_page, allPages.Count))
				Font.print(FONT26, 180 - Font.getTextWidth(FONT26, allPages.Count), 544 - 80 * MenuFade + 23, allPages.Count, COLOR_FONT)
				Font.print(FONT26, 780, 544 - 80 * MenuFade + 23, current_page, COLOR_FONT)
			elseif orientation == "Vertical" and is_down then
				if allPages.Count == 1 then
					point = 560
				else
					point = (((allPages.Count - allPages.Page + 1) - 1) * 560 / (allPages.Count - 1))
				end
				Graphics.fillRect(200, 760, 544 - 80 * MenuFade + 39, 544 - 80 * MenuFade + 41, BLUE_COLOR)
				Graphics.fillRect(200, 200 + point, 544 - 80 * MenuFade + 39, 544 - 80 * MenuFade + 41, GRAY_COLOR)
				Graphics.drawImage(200 + point - 6, 544 - 80 * MenuFade + 40 - 6, CircleIcon.e, BLUE_COLOR)
				Font.print(FONT26, 180 - Font.getTextWidth(FONT26, allPages.Count), 544 - 80 * MenuFade + 23, allPages.Count, COLOR_FONT)
				Font.print(FONT26, 780, 544 - 80 * MenuFade + 23, current_page, COLOR_FONT)
			else
				Graphics.fillRect(200, 760, 544 - 80 * MenuFade + 39, 544 - 80 * MenuFade + 41, GRAY_COLOR)
				Graphics.fillRect(200, 200 + point, 544 - 80 * MenuFade + 39, 544 - 80 * MenuFade + 41, BLUE_COLOR)
				Graphics.drawImage(200 + point - 6, 544 - 80 * MenuFade + 40 - 6, CircleIcon.e, BLUE_COLOR)
				Font.print(FONT26, 180 - Font.getTextWidth(FONT26, current_page), 544 - 80 * MenuFade + 23, current_page, COLOR_FONT)
				Font.print(FONT26, 780, 544 - 80 * MenuFade + 23, allPages.Count, COLOR_FONT)
			end
		end
		if currentChapterNumber > 1 and not (orientation == "Vertical" and is_down or readDirection == "LEFT") or currentChapterNumber < #Chapters and (orientation == "Vertical" and is_down or readDirection == "LEFT") then
			Graphics.drawImage(32, 544 - 80 * MenuFade + 40 - 12, leftArrowIcon.e, COLOR_FONT)
		else
			Graphics.drawImage(32, 544 - 80 * MenuFade + 40 - 12, leftArrowIcon.e, COLOR_GRAY)
		end
		if currentChapterNumber < #Chapters and not (orientation == "Vertical" and is_down or readDirection == "LEFT") or currentChapterNumber > 1 and (orientation == "Vertical" and is_down or readDirection == "LEFT") then
			Graphics.drawImage(960 - 32 - 24, 544 - 80 * MenuFade + 40 - 12, rightArrowIcon.e, COLOR_FONT)
		else
			Graphics.drawImage(960 - 32 - 24, 544 - 80 * MenuFade + 40 - 12, rightArrowIcon.e, COLOR_GRAY)
		end
		if Chapters[currentChapterNumber] then
			local manga_name = Chapters[currentChapterNumber].Manga.Name
			local chapter_name = Chapters[currentChapterNumber].Name
			local dif = math.max(Font.getTextWidth(BONT30, manga_name) - 960 + 88 + 32 + 24 + 32 + 24 + 32 + 32, 0)
			local dif_ch = math.max(Font.getTextWidth(FONT16, chapter_name) - 960 + 88 + 32 + 24 + 32 + 24 + 32 + 32, 0)
			local ms = 50 * string.len(manga_name)
			local ms_ch = 50 * string.len(chapter_name)
			local t = math.min(math.max(0, Timer.getTime(mangaNameTickerTimer) - 1500), ms)
			local t_ch = math.min(math.max(0, Timer.getTime(chapterNameTickerTimer) - 1500), ms_ch)
			Font.print(BONT30, 88 - dif * t / ms, 80 * MenuFade - 73, manga_name, COLOR_FONT)
			Font.print(FONT16, 88 - dif_ch * t_ch / ms_ch, 80 * MenuFade - 32, chapter_name, COLOR_FONT)
			Graphics.fillRect(0, 88, 0, 80 * MenuFade, BACK_COLOR)
			Graphics.drawImage(32, 80 * MenuFade - 40 - 12, BackIcon.e, COLOR_FONT)
			Graphics.fillRect(960 - 88 - 32 - 24 - 32, 960, 0, 80 * MenuFade, BACK_COLOR)
			if currentState == STATE_READING then
				Graphics.drawImage(960 - 32 - 24 - 32 - 32 - 24, 80 * MenuFade - 40 - 12, RefreshIcon.e, COLOR_FONT)
				Graphics.drawImage(960 - 32 - 24, 80 * MenuFade - 40 - 12, OptionsIcon.e, COLOR_FONT)
			end
			if Timer.getTime(mangaNameTickerTimer) > 3500 + ms then
				Timer.reset(mangaNameTickerTimer)
			end
			if Timer.getTime(chapterNameTickerTimer) > 3500 + ms_ch then
				Timer.reset(chapterNameTickerTimer)
			end
		else
			Graphics.fillRect(0, 88, 0, 80 * MenuFade, BACK_COLOR)
			Graphics.fillRect(960 - 88 - 32 - 24 - 32, 960, 0, 80 * MenuFade, BACK_COLOR)
		end
		if CursorFade >= 0 then
			local ks = math.ceil(2 * math.sin(Timer.getTime(GlobalTimer) / 100))
			local shift = 80 * (1 - MenuFade)
			for i = ks, ks + 1 do
				if CursorPoint.y > 272 then
					Graphics.fillEmptyRect(CursorPoint.x - 20 - i, CursorPoint.x + 20 + i + 2, CursorPoint.y - 20 - i + shift, CursorPoint.y + 20 + i + 2 + shift, Color.new(255, 0, 51, 255 * CursorFade))
				else
					Graphics.fillEmptyRect(CursorPoint.x - 20 - i, CursorPoint.x + 20 + i + 2, CursorPoint.y - 20 - i - shift, CursorPoint.y + 20 + i + 2 - shift, Color.new(255, 0, 51, 255 * CursorFade))
				end
			end
		end
	end
end

function Reader.loadChapter(chapter)
	currentState = STATE_LOADING
	if not Chapters[chapter] then
		Console.error("Error loading chapter")
		exit()
		return
	end
	if Chapters and Chapters[currentChapterNumber] then
		ParserManager.remove(Chapters[currentChapterNumber].Pages)
	end
	-- free the previous chapter's textures now: the garbage collector doesn't know how much GPU memory they hold
	for i = 1, #allPages do
		if allPages[i] then
			deletePageImage(i)
		end
	end
	currentChapterNumber = chapter
	prefetchClear()
	Chapters[chapter].Pages = {}
	allPages = {
		Page = 0
	}
	collectgarbage("step", 1024)
	if ChapterSaver.check(Chapters[chapter]) then
		Chapters[chapter].Pages = ChapterSaver.getChapter(Chapters[chapter])
	else
		ParserManager.prepareChapter(Chapters[chapter], Chapters[chapter].Pages)
	end
	Timer.reset(chapterNameTickerTimer)
	Timer.reset(mangaNameTickerTimer)
end

function Reader.updateSettings()
	local settings = CuSettings.load(Chapters[1].Manga)
	local old_read_dir = readDirection
	if settings then
		readDirection = settings.ReaderDirection == "Default" and Settings.ReaderDirection or settings.ReaderDirection
		is_down = readDirection == "DOWN"
		is_webtoon = readDirection == "WEBTOON"
		orientation = settings.Orientation == "Default" and Settings.Orientation or settings.Orientation
		autozoom = settings.ZoomReader == "Default" and Settings.ZoomReader or settings.ZoomReader
	end
	if old_read_dir == "LEFT" and readDirection ~= old_read_dir or (old_read_dir == "RIGHT" or old_read_dir == "DOWN" or old_read_dir == "WEBTOON") and readDirection == "LEFT" then
		if allPages and allPages.Count and allPages.Page and allPages.PrevPage then
			local i, j = 1, allPages.Count
			while i < j do
				allPages[i], allPages[j] = allPages[j], allPages[i]
				i = i + 1
				j = j - 1
			end
			local zpage = allPages[0]
			if allPages[#allPages].Link == "LoadNext" or allPages[#allPages].Link == "LoadPrev" then
				allPages[0] = allPages[#allPages]
				allPages[#allPages] = nil
			end
			if zpage then
				allPages[#allPages + 1] = zpage
				if allPages[0] == zpage then
					allPages[0] = nil
				end
			end
			allPages.Page = allPages.Count - allPages.Page + 1
			allPages.PrevPage = allPages.Count - allPages.PrevPage + 1
		end
	end
	updateMeasurements()
	if is_webtoon and currentState == STATE_READING then
		wtStart()
		wt.stickEnd = false
	end
end

function Reader.load(chapters, num)
	local ch = chapters and chapters[num]
	if ch and ch.Manga then
		Diag.trail("reader", tostring(ch.Manga.ParserID) .. " / " .. tostring(ch.Manga.Name) .. " / " .. tostring(ch.Name))
	end
	if not chapters[1] then
		Console.error("Error loading chapter")
		AppMode = MENU
		return
	end
	local settings = CuSettings.load(chapters[1].Manga)
	if settings then
		readDirection = settings.ReaderDirection == "Default" and Settings.ReaderDirection or settings.ReaderDirection
		is_down = readDirection == "DOWN"
		is_webtoon = readDirection == "WEBTOON"
		orientation = settings.Orientation == "Default" and Settings.Orientation or settings.Orientation
		autozoom = settings.ZoomReader == "Default" and Settings.ZoomReader or settings.ZoomReader
	end
	Chapters = chapters
	startPage = Cache.getBookmark(chapters[num])
	if startPage == true or startPage == nil then
		startPage = 1
	end
	Reader.loadChapter(num)
end

---For the simulator: the current page and where it stands (position and size on screen)
function Reader.debugView()
	if is_webtoon then
		return allPages.Page, wt.page, wt.offset, wt.zoom, wt.overEnd
	end
	local page = allPages[allPages.Page]
	if not page or not page.Zoom then
		return allPages.Page
	end
	return allPages.Page, page.x, page.y, page.Width * page.Zoom, page.Height * page.Zoom
end

function Reader.getCurrentPageImageLink()
	local page = allPages[allPages.Page]
	if page then
		if page.Extract then
			return {
				Path = page.Path,
				Extract = page.Extract
			}
		elseif page.Path then
			return {
				Path = page.Path
			}
		elseif page.Link then
			return {
				Link = page.Link
			}
		else
			return {
				ParserID = Chapters[currentChapterNumber].Manga.ParserID,
				Link = page[1]
			}
		end
	end
end
