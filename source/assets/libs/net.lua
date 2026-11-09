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
	-- .gif: lpp-vita's GIF decoder crashes the app on malformed/animated files, wsrv returns the first frame as JPEG
	return (not ImageProxy.nativeWebp and lower:find("%.webp$") ~= nil) or lower:find("%.avif$") ~= nil or lower:find("%.jxl$") ~= nil or lower:find("%.gif$") ~= nil
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

-- tall pages up to this size load at full resolution (in 4096 px slices); bigger ones load at half resolution
local TALL_FULL_MAX = 48 * 1024 * 1024
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
local current = nil -- task holding the async slot
local uniques = {} -- uniqueKey -> task (pending or running)
local bytes = 0
local is_net_inited = false
local idleFrames = 0
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
		local ok, err = coroutine.resume(co)
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
	Console.error("NET: " .. tostring(reason) .. " (" .. describeLink(task.RawLink or task.Path or "") .. ")")
	if current == task then
		current = nil
	end
	task.Retry = task.Retry - 1
	if task.Retry > 0 and not task.Cancelled then
		task.Type = task.Kind
		task.Stage = nil
		enqueue(task, false)
	else
		release(task)
	end
end

-------------------------------------------------------------------------------
-- image loading (decides resolution with the texture budget)
-------------------------------------------------------------------------------

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
	-- GIFs never reach lpp-vita's decoder: it takes the whole app down (data abort in "Image loader Thread")
	local isGif = width and width > 0 and getImageFormat(path) == "gif"
	if not width or width <= 0 or isGif then
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
		if path == IMAGE_CACHE_PATH then
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
	current = task
	task.StartedAt = now()
	-- a retried task gets a fresh deadline (and stall clock)
	task.TimedOut, task.SlowLogged, task.LastBytes, task.LastProgressAt = nil, nil, nil, nil
	-- like NOBORU: an image download is "final" only once its texture exists
	task.Final = task.Kind ~= "ImageDownload"
	local t = task.Type
	if t == "StringRequest" then
		if not task.Link or task.Link == "" then
			Console.error("No Link given")
			return finish(task)
		end
		task.Stage = "string"
		Network.requestStringAsync(task.Link, userAgentFor(task.Link), task.HttpMethod, task.PostData, task.ContentType, task.Cookie, task.Header1, task.Header2, task.Header3, task.Header4, task.Proxy, task.ProxyAuth)
	elseif t == "FileDownload" or t == "ImageDownload" then
		if not task.Link or task.Link == "" then
			Console.error("No Link given")
			return finish(task)
		end
		if doesFileExist(task.Path) then
			deleteFile(task.Path)
		end
		task.Stage = "download"
		Network.downloadFileAsync(task.Link, task.Path, userAgentFor(task.Link), task.HttpMethod, task.PostData, task.ContentType, task.Cookie, task.Header1, task.Header2, task.Header3, task.Header4, task.Proxy, task.ProxyAuth)
	elseif t == "Image" then
		return decodeImage(task)
	elseif t == "ImageSlice" then
		local plan, k = task.Plan, task.Slice
		if not plan or plan[k] or not doesFileExist(plan.Path) then
			return finish(task)
		end
		local sliceHeight = math.floor(plan.RealHeight / plan.Parts)
		local h = k == plan.Parts and (plan.RealHeight - (k - 1) * sliceHeight) or sliceHeight
		local shown = plan.RealWidth / plan.Width
		if not Textures.ensure(img2bytes(plan.RealWidth, h, shown)) then
			Console.error("Not enough texture memory for a page slice")
			return finish(task)
		end
		task.Stage = "slice"
		Graphics.loadPartImageAsync(plan.Path, 0, sliceHeight * (k - 1), plan.RealWidth, h)
	elseif t == "UnZip" then
		if not task.DestPath or not task.Path then
			Console.error("UnZip: missing paths")
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
			return finish(task)
		end
		task.Stage = "unzip"
		System.extractFromZipAsync(task.Path, task.Extract, task.DestPath)
	else
		-- "function" and unknown types: their turn in the queue is the event (OnComplete runs now)
		return finish(task)
	end
end

local function freeAsyncImage()
	local img = getAsyncResult()
	if img then
		Textures.release(img)
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
		current = nil
		return
	end
	if task.TimedOut then
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
		task.Table[task.Index] = body
		bytes = bytes + #body
		return finish(task)
	elseif stage == "download" then
		if task.Kind == "ImageDownload" then
			task.Type = "Image"
			return decodeImage(task)
		end
		if doesFileExist(task.Path) then
			local handle = openFile(task.Path, FREAD)
			bytes = bytes + sizeFile(handle)
			closeFile(handle)
		end
		return finish(task)
	elseif stage == "decode" then
		local img = Image:new(getAsyncResult(), FILTER_LINEAR)
		if not img then
			return fail(task, "image decode failed")
		end
		task.Table[task.Index] = img
		task.Final = true
		return finish(task)
	elseif stage == "parts" then
		task.Part = task.Part + 1
		local img = Image:new(getAsyncResult(), FILTER_LINEAR)
		if not img then
			task.Result:free()
			return fail(task, "image slice decode failed")
		end
		task.Result[task.Part] = img
		return startNext(task)
	elseif stage == "slice" then
		local img = Image:new(getAsyncResult(), FILTER_LINEAR)
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

---Called every frame from the main loop
function Threads.update()
	if #jobs > 0 then
		resumeJobs()
	end
	if is_net_inited and not current and #queue == 0 then
		idleFrames = idleFrames + 1
		-- keep the network stack alive 60 s after the last request: closing it drops the open connections and the TLS
		-- sessions, and every request after a short pause (turning pages, going back to a list) paid DNS + TCP + TLS again
		if idleFrames > 3600 then
			Network.term()
			is_net_inited = false
			idleFrames = 0
		end
		return
	end
	idleFrames = 0
	if not current and #queue == 0 then
		return
	end
	if not is_net_inited then
		Network.init()
		is_net_inited = true
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
			return
		end
		local task = current
		local ok, err = pcall(complete, task)
		if not ok then
			Console.error("NET: " .. tostring(err))
			if current == task then
				fail(task, err)
			end
		end
		if current then
			return -- the task started another async stage (decode, next slice)
		end
	end
	-- start the next task in the same frame (a few instant ones at most, to keep the frame short)
	local started = 0
	while not current and #queue > 0 and started < 4 do
		started = started + 1
		-- aging: a low-priority task waiting more than 15 s goes first, so background work never starves
		local pick = 1
		local t = now()
		for i = 2, #queue do
			if t - queue[i].QueuedAt > 15000 and queue[i].Priority > queue[1].Priority then
				pick = i
				break
			end
		end
		local task = table.remove(queue, pick)
		local ok, err = pcall(start, task)
		if not ok then
			Console.error("NET: " .. tostring(err))
			if current == task then
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
end

---Gives boolean that is any task is running
---For diagnostics: what the async slot is doing right now ("download", "decode", "slice", ...), or nil
function Threads.currentStage()
	return current and (current.Stage or current.Type) or nil
end

function Threads.isDownloadRunning()
	return getAsyncState() == 0 or #queue ~= 0 or current ~= nil
end

---You can use Network function in here if you sure that your function is safe
function Threads.netActionUnSafe(foo)
	if not is_net_inited then
		Network.init()
		local result = foo()
		Network.term()
		return result
	else
		return foo()
	end
end

---Waits for the async slot, then runs `foo` with the network stack up (only for one-off, short calls)
function Threads.netActionSafe(foo)
	repeat
	until getAsyncState() ~= 0
	return Threads.netActionUnSafe(foo)
end

---Wi-Fi state, cached for a second: checking it may (re)initialize the whole network stack
local wifiCache, wifiTime = nil, -10000
function Threads.isOnline()
	if wifiCache == nil or now() - wifiTime > 1000 then
		wifiCache = Threads.netActionUnSafe(Network.isWifiEnabled) and true or false
		wifiTime = now()
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
		Plan = t.Plan,
		Slice = t.Slice,
		Path = t.Path and (t.Path:find("^...?0:") and t.Path or ("ux0:data/otakio/" .. t.Path)) or IMAGE_CACHE_PATH,
		Retry = 3,
		HttpMethod = t.HttpMethod or GET_METHOD,
		PostData = t.PostData or "",
		ContentType = t.ContentType or XWWW,
		Cookie = t.Cookie or "",
		UniqueKey = uniqueKey,
		Priority = t.Priority or Threads.defaultPriority or (front and Threads.URGENT or Threads.NORMAL)
	}
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
		task.Link = escapeLink(task.Link)
	end
	if (task.Type == "ImageDownload" or task.ImageFile) and task.RawLink and ImageProxy.shouldProxy(task.RawLink) then
		task.RawLink = ImageProxy.wrap(task.RawLink, task.MaxHeight and task.MaxHeight / 1.5 or nil)
		task.Link = escapeLink(task.RawLink)
		task.Header1, task.Header2, task.Header3, task.Header4 = "", "", "", ""
		task.Proxied = true
	end
	task.Proxy = Settings.UseProxy and (Settings.ProxyIP .. ":" .. Settings.ProxyPort) or ""
	task.ProxyAuth = Settings.UseProxyAuth and Settings.ProxyAuth or ""
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
	while current and now() - guard < 5000 do
		if getAsyncState() ~= 0 then
			pcall(complete, current)
			current = nil
		end
	end
	current = nil
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
	else
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
	return #queue + (current and 1 or 0)
end

function Threads.getNonSkipTasksNum()
	return Threads.getTasksNum()
end
