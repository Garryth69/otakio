Threads = {}

---Image proxy: converts formats the Vita can't decode (WebP/AVIF) to JPEG and can
---downscale huge pages. Modes (Settings.ImageProxy): "Auto" (only when needed), "Off"
ImageProxy = {}

---The rebuilt Otakio engine (LuaJIT 2.1 + curl/OpenSSL 1.1.1) speaks TLS 1.3 itself
ENGINE_VERSION = type(jit) == "table" and jit.version or _VERSION

---Threads' native request functions treat '%' specially, so links are stored with
---doubled percent signs (same escaping NOBORU always used)
local function escapeLink(link)
	link = link:match("^(.-)%s*$") or ""
	-- raw UTF-8 in URLs (e.g. Thai/Japanese file names) must be percent-encoded
	link = link:gsub("[\128-\255]", function(c)
		return string.format("%%%02X", c:byte())
	end)
	return (link:gsub("([^%%])%%([^%%])", "%1%%%%%2"):gsub(" ", "%%%%20"):gsub("([^%%])%%$", "%1%%%%"):gsub("^%%([^%%])", "%%%%%1"))
end

local function linkUrl(link)
	if type(link) == "table" then
		return link.Link
	end
	return link
end

function ImageProxy.isProxied(link)
	local url = linkUrl(link)
	return type(url) == "string" and url:find("wsrv.nl", 1, true) ~= nil
end

---The Otakio engine decodes WebP itself (libwebp); the old NOBORU engine needs the converting proxy
ImageProxy.nativeWebp = false
pcall(function()
	ImageProxy.nativeWebp = System.getImageFormat("app0:assets/images/probe.webp") == "webp"
end)

function ImageProxy.needsConversion(link)
	local url = linkUrl(link)
	if type(url) ~= "string" then
		return false
	end
	local lower = url:lower():gsub("[?#].*$", "")
	local engine = OTAKIO_ENGINE or {}
	-- .gif: the old engine's GIF decoder crashed the app on malformed/animated files (engine 2 reads the first frame
	-- safely); .avif: decoded by engine 2 (dav1d); wsrv returns either as JPEG for older engines
	return (not ImageProxy.nativeWebp and lower:find("%.webp$") ~= nil) or (not engine.avif and lower:find("%.avif$") ~= nil)
		or lower:find("%.jxl$") ~= nil or (not engine.gif and lower:find("%.gif$") ~= nil)
end

function ImageProxy.shouldProxy(link)
	local mode = Settings.ImageProxy or "Auto"
	if mode == "Off" or ImageProxy.isProxied(link) then
		return false
	end
	return ImageProxy.needsConversion(link)
end

---@param link string|table
---@param maxWidth number|nil
---@return string|table
function ImageProxy.wrap(link, maxWidth)
	local url = linkUrl(link)
	if type(url) ~= "string" or url == "" or ImageProxy.isProxied(url) or (Settings.ImageProxy or "Auto") == "Off" then
		return link
	end
	url = url:gsub("^//", "https://")
	local proxied = string.format(Config.IMAGE_PROXY, Http.encode(url))
	if maxWidth then
		proxied = proxied .. "&w=" .. math.floor(maxWidth)
	elseif Settings.DataSaver then
		proxied = proxied .. "&w=960"
	end
	return proxied
end

---Sites that reject browser-impersonating clients (some return an HTML block page for "Chrome" user agents) get an
---honest app identification instead.
local APP_USERAGENT = "Otakio/" .. tostring(Config.VERSION_NAME or Config.VERSION)
local APP_UA_HOSTS = {"mangadex%.org", "mangadex%.network", "desu%.uno", "desu%.me"}
local function userAgentFor(link)
	if type(link) == "string" then
		for _, pattern in ipairs(APP_UA_HOSTS) do
			if link:find(pattern) then
				return APP_USERAGENT
			end
		end
	end
	return USERAGENT
end


-------------------------------------------------------------------------------
-- Task queue
-- lpp-vita has a single asynchronous slot (System.getAsyncState): one download, request, unzip or image decode at a
-- time. This queue feeds it:
--   * priorities: what the user is looking at (Threads.URGENT) before normal work before background work
--   * deadlines: a request that hangs is stopped and retried, so the queue never stays blocked
--   * real cancellation: removed tasks leave the queue; a cancelled running task frees whatever it produced
--   * image loads ask the texture budget (Textures, image.lua) for room and pick the resolution that fits
-- Public API kept from NOBORU: insertTask, addTask, check, remove, getProgress, update, clear, terminate, ...
-------------------------------------------------------------------------------

local IMAGE_CACHE_PATH = "ux0:data/otakio/temp/cache.image"

MAX_VRAM_MEMORY = 88 * 1024 * 1024

Threads.URGENT = 1
Threads.NORMAL = 3
Threads.BACKGROUND = 5

---Priority given to tasks created while this is set (ParserManager sets it around background jobs)
Threads.defaultPriority = nil

local getAsyncResult = System.getAsyncResult
local getAsyncState = System.getAsyncState
local closeFile = System.closeFile
local deleteFile = System.deleteFile
local openFile = System.openFile
local sizeFile = System.sizeFile
local readFile = System.readFile
local doesFileExist = System.doesFileExist
local removeDirectory = RemoveDirectory
local getImageFormat = System.getImageFormat
local getPictureResolution = System.getPictureResolution
local renameFile = System.rename
local doesDirExist = System.doesDirExist
local createDirectory = System.createDirectory
local listZip = System.listZip

---lpp-vita's extractor only creates folders that have their own entry in the zip; for a file in a missing folder
---it writes to a NULL file and the app crashes. Every folder is created up front from the zip's listing.
local function makeZipFolders(zipPath, dest)
	local made = {}
	for _, e in ipairs(listZip and listZip(zipPath) or {}) do
		local name = type(e) == "table" and e.name or e
		local dir = type(name) == "string" and name:match("^(.*)/[^/]*$")
		if dir and dir ~= "" and not made[dir] then
			local path = dest
			for part in dir:gmatch("[^/]+") do
				path = path .. "/" .. part
				if not made[path] and not doesDirExist(path) then
					createDirectory(path)
				end
				made[path] = true
			end
			made[dir] = true
		end
	end
end

-- tall pages keep their file here while open: slices are decoded from it on demand (the reader's prefetch folder,
-- emptied whenever a chapter is opened)
local LAZY_DIR = "ux0:data/otakio/temp/prefetch/"
local lazyCount = 0

local function img2bytes(width, height, dScale)
	return bit32.band(width + 7, bit32.bnot(7)) * height * 4 / (dScale * dScale) + 1024
end

local MAX_TEXTURE_SIDE = 4096

-- milliseconds a stage may keep the async slot before it is stopped (network) or reported (decode)
local DEADLINE = {
	string = 30000,
	download = 30000, -- without a new byte (a download that keeps receiving is never stopped)
	unzip = 60000,
	decode = 30000,
	parts = 30000,
	slice = 30000
}

local queue = {} -- pending tasks, ordered by Priority (stable)
local current = nil -- task holding the async slot (downloads, requests, zips; images too with older engines)
-- Engine 2 decodes images in a lane of its own (Graphics.getAsyncState/getAsyncResult): the next page downloads while
-- the current one decodes. Image and ImageSlice tasks then wait in the same queue for that lane.
local LANE = OTAKIO_ENGINE and OTAKIO_ENGINE.imageLane and Graphics.getAsyncState and true or false
local decoding = nil -- task holding the image lane
local getImageState = LANE and Graphics.getAsyncState or System.getAsyncState
local getImageResult = LANE and Graphics.getAsyncResult or System.getAsyncResult
local tempCount = 0 -- downloaded images get their own temporary file: two can be in flight at once

---@return boolean the task runs in the image lane
local function isImageTask(task)
	return LANE and (task.Type == "Image" or task.Type == "ImageSlice")
end
local uniques = {} -- uniqueKey -> task (pending or running)
-- image links that failed for good this session: not asked again (the cover of a title that comes back on every
-- screen would be downloaded, refused and retried over and over); a page's retry (reader, `Force`) still may
local failedLinks = {}
local bytes = 0
local is_net_inited = false
local clock = Timer.new()

local function now()
	return Timer.getTime(clock)
end

local function enqueue(task, front)
	task.QueuedAt = task.QueuedAt or now()
	local p = task.Priority
	local pos
	if front then
		pos = 1
		while queue[pos] and queue[pos].Priority < p do
			pos = pos + 1
		end
	else
		pos = #queue + 1
		while pos > 1 and queue[pos - 1].Priority > p do
			pos = pos - 1
		end
	end
	table.insert(queue, pos, task)
end

local function dequeue(task)
	for i = 1, #queue do
		if queue[i] == task then
			table.remove(queue, i)
			return true
		end
	end
	return false
end

local function release(task)
	if uniques[task.UniqueKey] == task then
		uniques[task.UniqueKey] = nil
	end
end

-- "function" tasks: their OnComplete may wait (coroutine.yield) for ParserManager or other tasks, so it runs as a
-- coroutine resumed once per frame instead of inline
local jobs = {}

local function resumeJobs()
	for i = #jobs, 1, -1 do
		local co = jobs[i]
		local t0 = Diag and Diag.now and Diag.now()
		local ok, err = coroutine.resume(co)
		if t0 then
			Diag.slow("task job", Diag.now() - t0)
		end
		if not ok then
			Console.error("Threads job: " .. tostring(err))
		end
		if coroutine.status(co) == "dead" then
			table.remove(jobs, i)
		end
	end
end

---Task ended (successfully or with a final soft failure): callbacks run like in NOBORU
local function finish(task)
	if current == task then
		current = nil
	end
	if decoding == task then
		decoding = nil
	end
	release(task)
	if task.Cancelled then
		return
	end
	if task.Kind == "function" then
		local onComplete, onFinal = task.OnComplete, task.Final and task.OnFinalComplete
		if onComplete or onFinal then
			jobs[#jobs + 1] = coroutine.create(function()
				if onComplete then
					onComplete()
				end
				if onFinal then
					onFinal()
				end
			end)
		end
		return
	end
	if task.OnComplete then
		local ok, err = pcall(task.OnComplete)
		if not ok then
			Console.error("OnComplete: " .. tostring(err))
		end
	end
	if task.Final and task.OnFinalComplete then
		local ok, err = pcall(task.OnFinalComplete)
		if not ok then
			Console.error("OnFinalComplete: " .. tostring(err))
		end
	end
end

---What a link points at, for the log: the image behind the converting proxy rather than the proxy, and no query
---string (the log cleaner would hide the whole proxy query, target included)
local function describeLink(link)
	local url = type(link) == "table" and link.Link or link
	if type(url) ~= "string" then
		return tostring(url)
	end
	url = url:gsub("%%%%", "%%")
	local target = ImageProxy.isProxied(url) and url:match("[?&]url=([^&]+)")
	if target then
		target = target:gsub("%%(%x%x)", function(h)
			return string.char(tonumber(h, 16))
		end)
		return (target:gsub("[?#].*$", "")) .. " (via proxy)"
	end
	return (url:gsub("[?#].*$", ""))
end

---For the log: what a downloaded file that is not an image holds (an HTML block page, nothing...) and its size
---true when a downloaded "image" is really a page or text (a 404 page served with status 200 and an image type)
local function isTextFile(path)
	local fh = openFile(path, FREAD)
	if not fh then
		return false
	end
	local size = sizeFile(fh) or 0
	local head = size > 0 and readFile(fh, math.min(size, 64)) or ""
	closeFile(fh)
	return size == 0 or head:find("^%s*[<{]") ~= nil
end

local function fileNote(path)
	local fh = openFile(path, FREAD)
	if not fh then
		return ""
	end
	local size = sizeFile(fh) or 0
	local head = size > 0 and readFile(fh, math.min(size, 64)) or ""
	closeFile(fh)
	local kind = "unknown data"
	if size == 0 then
		kind = "empty"
	elseif head:find("^%s*<") then
		kind = "HTML"
	elseif head:find("^%s*{") then
		kind = "JSON"
	end
	return string.format(": %s, %d bytes", kind, size)
end

---Task failed this attempt: retried while it has attempts left, otherwise dropped (waiters see an empty result)
local function fail(task, reason)
	if task.Preempted then
		-- stopped to let something the user is waiting for go first: back in the queue as it was
		task.Preempted, task.TimedOut = nil, nil
		task.Retry = task.Retry + 1
	else
		Console.error("NET: " .. tostring(reason) .. " (" .. describeLink(task.RawLink or task.Path or "") .. ")")
	end
	if current == task then
		current = nil
	end
	if decoding == task then
		decoding = nil
	end
	task.Retry = task.Retry - 1
	if task.Retry > 0 and not task.Cancelled then
		task.Type = task.Kind
		task.Stage = nil
		enqueue(task, false)
	else
		if not task.Cancelled and type(task.Table) == "table" and task.Index == "Image" then
			task.Table.LoadFailed = tostring(reason) -- the reader shows it with a way to try again
		end
		if not task.Cancelled and (task.Kind == "ImageDownload" or task.ImageFile) and task.RawLink then
			failedLinks[task.RawLink] = tostring(reason)
		end
		release(task)
	end
end

-------------------------------------------------------------------------------
-- image loading (decides resolution with the texture budget)
-------------------------------------------------------------------------------

local PAGE_MIN_SIDE = 1000 -- reader pages: the shorter side never goes under this when decoded smaller

local function pow2Scale(scale)
	local s = 1
	while s < scale and s < 64 do
		s = s * 2
	end
	return s
end

local startNext

---Starts decoding task.Path into a texture (or slices), or ends the task when it can't
local function decodeImage(task)
	local path = task.Path
	if not doesFileExist(path) then
		if task.Link and task.Kind == "ImageDownload" then
			return fail(task, "image file missing after download")
		end
		Console.error("(Image) file not found " .. tostring(path))
		return finish(task)
	end
	local width, height = getPictureResolution(path)
	-- with the old engine GIFs never reach its decoder: it took the whole app down (data abort in "Image loader Thread")
	local isGif = width and width > 0 and not (OTAKIO_ENGINE and OTAKIO_ENGINE.gif) and getImageFormat(path) == "gif"
	if not width or width <= 0 or isGif then
		-- a page instead of an image (a "soft" 404): the converting proxy would only fetch the same page again
		if task.Link and not isGif and isTextFile(path) then
			task.Retry = math.min(task.Retry, 1) -- and asking again brings the same page: no more tries
			return fail(task, "downloaded file is not an image" .. fileNote(path))
		end
		if task.Link and not task.Proxied and (Settings.ImageProxy or "Auto") ~= "Off" then
			-- WebP/AVIF/GIF the engine can't read: retry through the converting proxy (it always returns JPEG)
			task.Proxied = true
			task.RawLink = ImageProxy.wrap(task.RawLink or "", task.MaxHeight and task.MaxHeight / 1.5 or nil)
			task.Link = escapeLink(task.RawLink)
			task.Header1, task.Header2, task.Header3, task.Header4 = "", "", "", ""
			task.Kind = "ImageDownload"
			task.Retry = task.Retry + 1
			return fail(task, "unsupported image format, retrying through proxy")
		elseif task.Link and not isGif then
			return fail(task, "downloaded file is not an image" .. fileNote(path))
		end
		Console.error(isGif and "GIF images are not supported" or "File isn't a picture")
		if ExtLog and not isGif then
			ExtLog("image failed: " .. tostring(task.RawLink or task.Link or path))
		end
		return finish(task)
	end
	local tall = height > MAX_TEXTURE_SIDE and height / width > 2 and not task.MaxHeight
	if tall then
		-- long strip (webtoon) page: nothing is decoded now. The reader asks for the 4096 px slices near the screen
		-- ("ImageSlice" tasks) and frees the ones that scroll away, so a 15000 px page never sits whole in memory.
		if path == IMAGE_CACHE_PATH or path == task.TempPath then
			-- the shared download file is overwritten by the next page: give this one its own file
			if not doesDirExist(LAZY_DIR) then
				createDirectory(LAZY_DIR)
			end
			lazyCount = lazyCount + 1
			local own = LAZY_DIR .. "page_" .. lazyCount .. ".img"
			if doesFileExist(own) then
				deleteFile(own)
			end
			renameFile(path, own)
			path = own
		end
		-- very wide strips decode at half resolution (each slice stays under ~24 MB)
		local half = width * MAX_TEXTURE_SIDE * 4 > 24 * 1024 * 1024
		local parts = math.ceil(height / (half and MAX_TEXTURE_SIDE * 2 or MAX_TEXTURE_SIDE))
		local shown = half and 2 or 1
		local result = {
			Lazy = true,
			Path = path,
			Parts = parts,
			RealWidth = width,
			RealHeight = height,
			Width = width / shown,
			Height = height / shown,
			SliceHeight = math.floor(height / shown / parts),
			Keys = {}
		}
		result.free = function(self)
			for i = 1, self.Parts do
				if self.Keys[i] then
					Threads.remove(self.Keys[i])
				end
				if self[i] and self[i].free then
					self[i]:free()
				end
				self[i] = nil
			end
		end
		task.Table[task.Index] = result
		task.Final = true
		return finish(task)
	else
		local scale = 1
		if task.MaxWidth and task.MaxHeight then
			scale = width > height and width / task.MaxWidth or height / task.MaxHeight
		elseif task.MaxWidth then
			scale = width / task.MaxWidth
		elseif task.MaxHeight then
			scale = height / task.MaxHeight
		end
		scale = pow2Scale(math.max(1, scale))
		if not task.MaxWidth and not task.MaxHeight and task.Index == "Image" then
			-- a reader page far bigger than the screen (raws of 2500 px and more): decoded at half (or a quarter) size
			-- while its shorter side stays at 1000 px or more, still above the screen when zoomed in. A 2500x3500 page
			-- is 35 MB of texture whole and 9 MB at half, and the JPEG decoder is faster at a reduced scale
			while math.min(width, height) / (scale * 2) >= PAGE_MIN_SIDE and scale < 8 do
				scale = scale * 2
			end
		end
		-- the GPU can't hold a texture side above 4096 px
		while math.max(width, height) / scale > MAX_TEXTURE_SIDE and scale < 64 do
			scale = scale * 2
		end
		-- not enough room: try a lower resolution before giving up (covers can go down to 1/8)
		while not Textures.ensure(img2bytes(width, height, scale)) do
			if scale >= 8 then
				Console.error("Not enough texture memory for " .. width .. "x" .. height)
				return finish(task)
			end
			scale = scale * 2
		end
		task.Stage = "decode"
		task.StartedAt = now()
		Graphics.loadImageAsync(path, scale)
		return
	end
	-- first slice
	return startNext(task)
end

---Loads the next slice of a tall image (task.Stage == "parts")
startNext = function(task)
	local plan = task.Plan
	if task.Part >= plan.Parts then
		task.Table[task.Index] = task.Result
		task.Final = true
		return finish(task)
	end
	local sliceHeight = math.floor(plan.RealHeight / plan.Parts)
	local h = sliceHeight
	if task.Part == plan.Parts - 1 then
		h = plan.RealHeight - task.Part * sliceHeight
	end
	task.StartedAt = now()
	Graphics.loadPartImageAsync(task.Path, 0, sliceHeight * task.Part, plan.RealWidth, h)
end

-------------------------------------------------------------------------------
-- starting and completing stages
-------------------------------------------------------------------------------

local function start(task)
	if isImageTask(task) then
		decoding = task
	else
		current = task
	end
	task.StartedAt = now()
	local t0 = Diag and Diag.now and Diag.now()
	local function done()
		if t0 then
			Diag.slow("net start " .. tostring(task.Stage or task.Kind), Diag.now() - t0)
		end
	end
	-- a retried task gets a fresh deadline (and stall clock)
	task.TimedOut, task.SlowLogged, task.LastBytes, task.LastProgressAt = nil, nil, nil, nil
	-- like NOBORU: an image download is "final" only once its texture exists
	task.Final = task.Kind ~= "ImageDownload"
	local t = task.Type
	if t == "StringRequest" then
		if not task.Link or task.Link == "" then
			Console.error("No Link given")
			done()
			return finish(task)
		end
		task.Stage = "string"
		Network.requestStringAsync(task.Link, userAgentFor(task.Link), task.HttpMethod, task.PostData, task.ContentType, task.Cookie, task.Header1, task.Header2, task.Header3, task.Header4, task.Proxy, task.ProxyAuth)
	elseif t == "FileDownload" or t == "ImageDownload" then
		if not task.Link or task.Link == "" then
			Console.error("No Link given")
			done()
			return finish(task)
		end
		if doesFileExist(task.Path) then
			deleteFile(task.Path)
		end
		task.Stage = "download"
		Network.downloadFileAsync(task.Link, task.Path, userAgentFor(task.Link), task.HttpMethod, task.PostData, task.ContentType, task.Cookie, task.Header1, task.Header2, task.Header3, task.Header4, task.Proxy, task.ProxyAuth)
	elseif t == "Image" then
		done()
		return decodeImage(task)
	elseif t == "ImageSlice" then
		local plan, k = task.Plan, task.Slice
		if not plan or plan[k] or not doesFileExist(plan.Path) then
			done()
			return finish(task)
		end
		local sliceHeight = math.floor(plan.RealHeight / plan.Parts)
		local h = k == plan.Parts and (plan.RealHeight - (k - 1) * sliceHeight) or sliceHeight
		local shown = plan.RealWidth / plan.Width
		if not Textures.ensure(img2bytes(plan.RealWidth, h, shown)) then
			Console.error("Not enough texture memory for a page slice")
			done()
			return finish(task)
		end
		task.Stage = "slice"
		Graphics.loadPartImageAsync(plan.Path, 0, sliceHeight * (k - 1), plan.RealWidth, h)
	elseif t == "UnZip" then
		if not task.DestPath or not task.Path then
			Console.error("UnZip: missing paths")
			done()
			return finish(task)
		end
		removeDirectory(task.DestPath)
		createDirectory(task.DestPath)
		makeZipFolders(task.Path, task.DestPath)
		task.Stage = "unzip"
		System.extractZipAsync(task.Path, task.DestPath)
	elseif t == "UnZipFile" then
		if not task.Extract or not task.DestPath or not task.Path then
			Console.error("UnZipFile: missing paths")
			done()
			return finish(task)
		end
		task.Stage = "unzip"
		System.extractFromZipAsync(task.Path, task.Extract, task.DestPath)
	else
		-- "function" and unknown types: their turn in the queue is the event (OnComplete runs now)
		done()
		return finish(task)
	end
	done()
end

local function freeAsyncImage()
	local img = getImageResult()
	if img then
		Textures.release(img)
	end
end

-- Engine 2 (OTAKIO_ENGINE) reports how each request went: HTTP status, curl error, time, bytes and compression
local getLastResponse = Network and Network.getLastResponse
-- curl errors worth another try: transfer cut short, TLS handshake hiccup, empty reply, connection dropped
local TRANSIENT = {[18] = true, [35] = true, [52] = true, [55] = true, [56] = true}

---@return table|nil the engine's report of the request that just finished (also counted for the log's "net:" line)
local function responseOf(task)
	if not getLastResponse then
		return nil
	end
	local ok, r = pcall(getLastResponse)
	if not ok or type(r) ~= "table" then
		return nil
	end
	if Diag and Diag.request then
		local host = type(task.Link) == "string" and task.Link:match("^%a+://([^/:]+)") or nil
		Diag.request(host, (r.seconds or 0) * 1000, r.bytes, r.compressed and (r.bytes or 0) > 0, (r.code or 0) ~= 0 or (r.status or 0) >= 400)
	end
	return r
end

---Reader pages: grayscale/inverted pixels (ReaderLook "Pixels", engine 2) written into the texture before first use
local function pixelFilter(raw)
	local mode = ReaderLook and ReaderLook.pixelFilter and ReaderLook.pixelFilter()
	if mode then
		pcall(Graphics.filterImage, raw, mode)
	end
end

---The async slot finished the current stage
local function complete(task)
	local stage = task.Stage
	if task.Cancelled then
		if stage == "decode" or stage == "parts" or stage == "slice" then
			freeAsyncImage()
		end
		if task.Result and task.Result.free then
			task.Result:free()
		end
		if current == task then
			current = nil
		end
		if decoding == task then
			decoding = nil
		end
		return
	end
	if task.TimedOut or task.Preempted then
		if task.Preempted and stage == "download" and task.Path then
			deleteFile(task.Path) -- a partial file must not pass for the image
		end
		return fail(task, "timed out")
	end
	if stage == "string" then
		local body = getAsyncResult() or ""
		-- lpp-vita's string buffer counts its C terminator: drop the trailing NUL byte(s)
		local trimmed = #body
		while trimmed > 0 and string.byte(body, trimmed) == 0 do
			trimmed = trimmed - 1
		end
		if trimmed < #body then
			body = string.rawsub(body, 1, trimmed)
		end
		local r = responseOf(task)
		if r then
			local where = describeLink(task.RawLink or task.Link or "")
			if (r.code or 0) ~= 0 then
				-- curl keeps the first message of a transfer: a harmless notice (an unverified certificate) can stand in
				-- for the real failure, so the curl code goes along (7 no connection, 28 timeout, 35 TLS, 52 empty,
				-- 56 connection dropped)
				local why = "request failed (curl " .. tostring(r.code) .. "): " .. tostring(r.error)
				if TRANSIENT[r.code] then
					return fail(task, why)
				end
				Console.error("NET: " .. why .. " (" .. where .. ")")
			elseif (r.status or 0) >= 400 then
				Console.error("NET: HTTP " .. r.status .. " (" .. where .. ")")
			elseif body == "" and task.HttpMethod ~= HEAD_METHOD and r.status ~= 204 then
				Console.error("NET: empty response, HTTP " .. tostring(r.status) .. " (" .. where .. ")")
			end
			if task.WantResponse and type(task.Table) == "table" then
				task.Table[task.Index .. "Response"] = r
			end
		end
		task.Table[task.Index] = body
		bytes = bytes + #body
		return finish(task)
	elseif stage == "download" then
		local r = responseOf(task)
		if r and task.Kind == "ImageDownload" then
			if (r.code or 0) ~= 0 then
				if not TRANSIENT[r.code] and r.code ~= 28 then
					task.Retry = 1
				end
				return fail(task, "download failed: " .. tostring(r.error))
			elseif (r.status or 0) >= 400 then
				-- a missing or refused image stays so: only rate limits, timeouts and server errors are asked again
				if r.status < 500 and r.status ~= 429 and r.status ~= 408 then
					task.Retry = 1
				end
				return fail(task, "HTTP " .. r.status)
			end
		elseif r and ((r.code or 0) ~= 0 or (r.status or 0) >= 400) then
			Console.error("NET: download " .. ((r.code or 0) ~= 0 and ("failed: " .. tostring(r.error)) or ("HTTP " .. r.status)) .. " (" .. describeLink(task.RawLink or task.Link or "") .. ")")
		end
		if task.Kind == "ImageDownload" then
			task.Type = "Image"
			if LANE then
				-- the network slot is free again: the image waits (at the front of its priority) for the image lane
				current = nil
				task.Stage = nil
				enqueue(task, true)
				return
			end
			return decodeImage(task)
		end
		if doesFileExist(task.Path) then
			local handle = openFile(task.Path, FREAD)
			bytes = bytes + sizeFile(handle)
			closeFile(handle)
		end
		return finish(task)
	elseif stage == "decode" then
		local raw = getImageResult()
		if raw and task.Index == "Image" and not task.MaxWidth and not task.MaxHeight then
			pixelFilter(raw)
		end
		local img = Image:new(raw, FILTER_LINEAR)
		if not img then
			return fail(task, "image decode failed")
		end
		task.Table[task.Index] = img
		task.Final = true
		return finish(task)
	elseif stage == "parts" then
		task.Part = task.Part + 1
		local raw = getImageResult()
		if raw and task.Index == "Image" then
			pixelFilter(raw)
		end
		local img = Image:new(raw, FILTER_LINEAR)
		if not img then
			task.Result:free()
			return fail(task, "image slice decode failed")
		end
		task.Result[task.Part] = img
		return startNext(task)
	elseif stage == "slice" then
		local raw = getImageResult()
		if raw then
			pixelFilter(raw) -- slices only come from reader pages
		end
		local img = Image:new(raw, FILTER_LINEAR)
		if img then
			if task.Plan[task.Slice] and task.Plan[task.Slice].free then
				task.Plan[task.Slice]:free()
			end
			task.Plan[task.Slice] = img
		end
		return finish(task)
	elseif stage == "unzip" then
		return finish(task)
	end
	return finish(task)
end

---Brings the network stack up, once per session, and logs how long the engine took. It is a synchronous call
---(sceNet, NetCtl, sceHttp, curl); the stack used to be closed after 2 s without requests and brought up again on the
---next one, which paused the app after every short pause and dropped the open connections and TLS sessions.
local netInits = 0
local function netInit()
	if is_net_inited then
		return
	end
	local t = now()
	Network.init()
	is_net_inited = true
	netInits = netInits + 1
	if ExtLog then
		pcall(ExtLog, string.format("network init #%d: %d ms", netInits, now() - t))
	end
end

local HOST_GAP = 300 -- ms between two requests to the same site
local hostLast = {} -- host -> time of its last request

---@return string|nil the site a task goes to over the network (nil: decode, unzip, function...)
local function taskHost(task)
	local k = task.Kind
	if k ~= "StringRequest" and k ~= "FileDownload" and k ~= "ImageDownload" then
		return nil
	end
	return type(task.Link) == "string" and task.Link:match("^%a+://([^/:]+)") or nil
end

local function hostReady(task, t)
	local host = taskHost(task)
	return not host or not hostLast[host] or t - hostLast[host] >= HOST_GAP
end

---Called every frame from the main loop
function Threads.update()
	if #jobs > 0 then
		resumeJobs()
	end
	if not current and not decoding and #queue == 0 then
		return
	end
	netInit()
	-- image lane (engine 2): the decode, slice or next part of a tall image finished
	if decoding and getImageState() ~= 0 then
		local task = decoding
		local ok, err = pcall(complete, task)
		if not ok then
			Console.error("NET: " .. tostring(err))
			if decoding == task then
				fail(task, err)
			end
		end
	end
	if current then
		if getAsyncState() == 0 then
			-- still running: enforce the deadline
			local limit = DEADLINE[current.Stage or ""]
			local since = current.StartedAt or now()
			if current.Stage == "download" then
				-- a download is stopped only when it stalls: a big file on slow Wi-Fi keeps going while bytes arrive
				local got = Network.getDownloadedBytes() or 0
				if got ~= current.LastBytes then
					current.LastBytes = got
					current.LastProgressAt = now()
				end
				since = current.LastProgressAt or since
			end
			-- something the user is waiting for (urgent) is queued behind a background transfer running for a while (a
			-- slow cover...): stop it, it goes back to the queue untouched and runs again later
			if not current.Preempted and not current.TimedOut and (current.Priority or Threads.NORMAL) > Threads.URGENT
				and (current.Stage == "string" or current.Stage == "download") and now() - (current.StartedAt or now()) > 2000 then
				local q = queue[1]
				if q and q.Priority == Threads.URGENT and not isImageTask(q) then
					current.Preempted = true
					Network.stopCurrentDownload()
				end
			end
			if limit and not current.TimedOut and now() - since > limit then
				if current.Stage == "string" or current.Stage == "download" then
					current.TimedOut = true
					current.Retry = math.min(current.Retry, 2)
					Network.stopCurrentDownload()
					Console.error("NET: deadline reached, stopping " .. tostring(current.RawLink))
				elseif not current.SlowLogged then
					current.SlowLogged = true
					Console.error("NET: slow " .. tostring(current.Stage) .. " " .. tostring(current.Path))
				end
			end
		else
			local task = current
			local ok, err = pcall(complete, task)
			if not ok then
				Console.error("NET: " .. tostring(err))
				if current == task then
					fail(task, err)
				end
			end
		end
	end
	-- start the next tasks in the same frame, one per free lane (a few instant ones at most, to keep the frame short)
	local started = 0
	while #queue > 0 and started < 4 do
		local netFree, imageFree = not current, LANE and not decoding
		if not netFree and not imageFree then
			return
		end
		started = started + 1
		-- good neighbour: the same site at most once every HOST_GAP ms; a task for a site asked just now waits while
		-- one for another site (or work that needs no network) goes first
		local t = now()
		local function eligible(q)
			if isImageTask(q) then
				return imageFree
			end
			return netFree and hostReady(q, t)
		end
		local pick = nil
		for i = 1, #queue do
			if eligible(queue[i]) then
				pick = i
				break
			end
		end
		if not pick then
			return
		end
		-- aging: a low-priority task waiting more than 15 s goes first, so background work never starves. Never ahead
		-- of an urgent task (what the user just asked for): after a global search dozens of old searches and covers
		-- kept winning over the chapter list of the manga just opened
		for i = (queue[pick].Priority > Threads.URGENT and pick + 1 or #queue + 1), #queue do
			local q = queue[i]
			if t - q.QueuedAt > 15000 and q.Priority > queue[pick].Priority and eligible(q) then
				pick = i
				break
			end
		end
		local task = table.remove(queue, pick)
		local host = not isImageTask(task) and taskHost(task)
		if host then
			hostLast[host] = t
		end
		local ok, err = pcall(start, task)
		if not ok then
			Console.error("NET: " .. tostring(err))
			if current == task or decoding == task then
				fail(task, err)
			else
				release(task)
			end
		end
	end
end

---Drops every pending task and cancels the running one
function Threads.clear()
	for _, task in ipairs(queue) do
		task.Cancelled = true
	end
	queue = {}
	uniques = {}
	if current then
		current.Cancelled = true
		if current.Stage == "string" or current.Stage == "download" then
			Network.stopCurrentDownload()
		end
	end
	if decoding then
		decoding.Cancelled = true
	end
end

---Gives boolean that is any task is running
---For diagnostics: what the async slot is doing right now ("download", "decode", "slice", ...), or nil
function Threads.currentStage()
	local a = current and (current.Stage or current.Type) or nil
	local b = decoding and (decoding.Stage or decoding.Type) or nil
	if a and b then
		return a .. "+" .. b
	end
	return a or b
end

function Threads.isDownloadRunning()
	return getAsyncState() == 0 or #queue ~= 0 or current ~= nil or decoding ~= nil
end

---You can use Network function in here if you sure that your function is safe
function Threads.netActionUnSafe(foo)
	netInit() -- and the stack stays up (see netInit)
	return foo()
end

---Wi-Fi state, cached for a second: checking it may (re)initialize the whole network stack
local wifiCache, wifiTime = nil, -10000
function Threads.isOnline()
	if wifiCache == nil or now() - wifiTime > 1000 then
		local t0 = Diag and Diag.now and Diag.now()
		wifiCache = Threads.netActionUnSafe(Network.isWifiEnabled) and true or false
		wifiTime = now()
		if t0 then
			Diag.slow("wifi state", Diag.now() - t0)
		end
	end
	return wifiCache
end

---@param uniqueKey any
---@param t table of parameters
---@param front boolean
local function newTask(uniqueKey, t, front)
	if not uniqueKey or uniques[uniqueKey] then
		return false
	end
	if t.Type == "FileDownload" and not (t.Link and t.Path) then
		return false
	end
	local task = {
		Type = t.Type,
		Kind = t.Type,
		Link = t.Link,
		Table = t.Table,
		Index = t.Index,
		DestPath = t.DestPath,
		Header1 = t.Header1 or "",
		Header2 = t.Header2 or "",
		Header3 = t.Header3 or "",
		Header4 = t.Header4 or "",
		MaxHeight = t.MaxHeight,
		MaxWidth = t.MaxWidth,
		OnComplete = t.OnComplete,
		OnFinalComplete = t.OnFinalComplete,
		Extract = t.Extract,
		ImageFile = t.ImageFile,
		WantResponse = t.WantResponse,
		Plan = t.Plan,
		Slice = t.Slice,
		Path = t.Path and (t.Path:find("^...?0:") and t.Path or ("ux0:data/otakio/" .. t.Path)) or nil,
		Retry = 3,
		HttpMethod = t.HttpMethod or GET_METHOD,
		PostData = t.PostData or "",
		ContentType = t.ContentType or XWWW,
		Cookie = t.Cookie or "",
		UniqueKey = uniqueKey,
		Priority = t.Priority or Threads.defaultPriority or (front and Threads.URGENT or Threads.NORMAL)
	}
	if not task.Path then
		if LANE and task.Type == "ImageDownload" then
			tempCount = tempCount % 32 + 1
			task.Path = "ux0:data/otakio/temp/img_" .. tempCount .. ".tmp"
			task.TempPath = task.Path
		else
			task.Path = IMAGE_CACHE_PATH
		end
	end
	if type(task.Link) == "table" then
		local l = task.Link
		task.Link = l.Link
		task.Header1 = l.Header1 or task.Header1
		task.Header2 = l.Header2 or task.Header2
		task.Header3 = l.Header3 or task.Header3
		task.Header4 = l.Header4 or task.Header4
		task.HttpMethod = l.HttpMethod or task.HttpMethod
		task.PostData = l.PostData or task.PostData
		task.ContentType = l.ContentType or task.ContentType
		task.Cookie = l.Cookie or task.Cookie
	end
	if type(task.Link) == "string" then
		task.RawLink = task.Link:match("^(.-)%s*$") or ""
		-- a source whose site moved (source settings > site address): its requests go to the new address
		if SourcePrefs then
			task.RawLink = SourcePrefs.rewrite(task.RawLink)
			for h = 1, 4 do
				task["Header" .. h] = SourcePrefs.rewriteHeader(task["Header" .. h])
			end
		end
		task.Link = escapeLink(task.RawLink)
	end
	if (task.Type == "ImageDownload" or task.ImageFile) and task.RawLink and ImageProxy.shouldProxy(task.RawLink) then
		task.RawLink = ImageProxy.wrap(task.RawLink, task.MaxHeight and task.MaxHeight / 1.5 or nil)
		task.Link = escapeLink(task.RawLink)
		task.Header1, task.Header2, task.Header3, task.Header4 = "", "", "", ""
		task.Proxied = true
	end
	task.Proxy = Settings.UseProxy and (Settings.ProxyIP .. ":" .. Settings.ProxyPort) or ""
	task.ProxyAuth = Settings.UseProxyAuth and Settings.ProxyAuth or ""
	if (task.Kind == "ImageDownload" or task.ImageFile) and task.RawLink and failedLinks[task.RawLink] and not t.Force then
		if type(task.Table) == "table" and task.Index == "Image" then
			task.Table.LoadFailed = failedLinks[task.RawLink]
		end
		return false
	end
	enqueue(task, front)
	uniques[uniqueKey] = task
	return true
end

---Queues a task ahead of the others of its priority (default priority: URGENT)
---@return boolean
function Threads.insertTask(uniqueKey, t)
	return newTask(uniqueKey, t, true)
end

---Queues a task after the others of its priority (default priority: NORMAL)
---@return boolean
function Threads.addTask(uniqueKey, t)
	return newTask(uniqueKey, t, false)
end

---Terminates Threads functions and net features
function Threads.terminate()
	Threads.clear()
	local guard = now()
	while (current or decoding) and now() - guard < 5000 do
		if current and getAsyncState() ~= 0 then
			pcall(complete, current)
			current = nil
		end
		if decoding and getImageState() ~= 0 then
			pcall(complete, decoding)
			decoding = nil
		end
	end
	current = nil
	decoding = nil
	if is_net_inited then
		Network.term()
		is_net_inited = false
	end
end

function Threads.getProgress(uniqueKey)
	local task = uniques[uniqueKey]
	if task and task == current then
		if task.Stage == "string" or task.Stage == "download" then
			local total = Network.getTotalBytes()
			if not total or total <= 0 then
				return 0
			end
			return math.max(math.min(1, Network.getDownloadedBytes() / total), 0)
		end
		return 1
	end
	if task and task == decoding then
		return 1
	end
	return 0
end

---Bytes received so far by a running download, and its total (0 when the server didn't say)
---@return integer downloaded, integer total
function Threads.getBytes(uniqueKey)
	local task = uniques[uniqueKey]
	if task and task == current and task.Stage == "download" then
		return Network.getDownloadedBytes() or 0, Network.getTotalBytes() or 0
	end
	return 0, 0
end

---Removes task by `UniqueKey` (cancels it when it is running)
function Threads.remove(uniqueKey)
	local task = uniques[uniqueKey]
	if not task then
		return
	end
	uniques[uniqueKey] = nil
	task.Cancelled = true
	if task == current then
		if task.Stage == "string" or task.Stage == "download" then
			Network.stopCurrentDownload()
		end
	elseif task ~= decoding then -- a decode can't be stopped: its texture is freed when it ends (Cancelled)
		dequeue(task)
	end
end

---Checks if a task is queued or running by `UniqueKey`
function Threads.check(uniqueKey)
	return uniques[uniqueKey] ~= nil
end

---@return number bytes downloaded by Threads
function Threads.getMemoryDownloaded()
	return bytes
end

---@return integer number of tasks (queued + running)
function Threads.getTasksNum()
	return #queue + (current and 1 or 0) + (decoding and 1 or 0)
end

function Threads.getNonSkipTasksNum()
	return Threads.getTasksNum()
end
