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

---Sites that reject browser-impersonating clients (MangaDex returns an HTML block page for
---"Chrome" user agents) get an honest app identification instead.
local APP_USERAGENT = "Otakio/" .. tostring(Config.VERSION_NAME or Config.VERSION)
local APP_UA_HOSTS = {"mangadex%.org", "mangadex%.network"}
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

local IMAGE_CACHE_PATH = "ux0:data/otakio/temp/cache.image"

local orderList = {}
local currentTask = nil

MAX_VRAM_MEMORY = 88 * 1024 * 1024
local TRASH = {
	Type = nil,
	Garbadge = nil
}

local bytes = 0
local uniques = {}

local getAsyncResult = System.getAsyncResult
local closeFile = System.closeFile
local deleteFile = System.deleteFile
local openFile = System.openFile
local sizeFile = System.sizeFile
local doesFileExist = System.doesFileExist
local removeDirectory = RemoveDirectory
local getImageFormat = System.getImageFormat

local function img2bytes(width, height, dScale)
	return bit32.band(width + 7, bit32.bnot(7)) * height * 4 / (dScale * dScale) + 1024
end

local is_net_inited = false

---Updates threads tasks
local idleFrames = 0
function Threads.update()
	if is_net_inited and not currentTask and #orderList == 0 then
		idleFrames = idleFrames + 1
		-- keep the network stack alive ~2s after the last request: avoids re-initializing
		-- libcurl/SSL between every cover/page request
		if idleFrames > 120 then
			Network.term()
			is_net_inited = false
			idleFrames = 0
		end
	else
		idleFrames = 0
	end
	if not is_net_inited and (#orderList ~= 0 or currentTask) then
		Network.init()
		is_net_inited = true
	end
	if (#orderList == 0 and not currentTask) or System.getAsyncState() == 0 then
		return
	end
	if not currentTask then
		local new_order = {}
		for i = 1, #orderList do
			if orderList[i].Type == "Skip" then
				Console.write("NET: Skip", Color.new(255, 255, 0))
			else
				new_order[#new_order + 1] = orderList[i]
			end
		end
		orderList = new_order
		if #orderList == 0 then
			return
		end
		currentTask = table.remove(orderList, 1)
		currentTask.Final = true
		if currentTask.Type == "StringRequest" then
			if currentTask.Link then
				Network.requestStringAsync(currentTask.Link, userAgentFor(currentTask.Link), currentTask.HttpMethod, currentTask.PostData, currentTask.ContentType, currentTask.Cookie, currentTask.Header1, currentTask.Header2, currentTask.Header3, currentTask.Header4, currentTask.Proxy, currentTask.ProxyAuth)
			else
				Console.error("No Link given or internet connection problem")
				uniques[currentTask.UniqueKey] = nil
				currentTask = nil
			end
		elseif currentTask.Type == "FileDownload" or currentTask.Type == "ImageDownload" then
			if doesFileExist(currentTask.Path) then
				deleteFile(currentTask.Path)
			end
			if currentTask.Link then
				if currentTask.Path then
					Network.downloadFileAsync(currentTask.Link, currentTask.Path, userAgentFor(currentTask.Link), currentTask.HttpMethod, currentTask.PostData, currentTask.ContentType, currentTask.Cookie, currentTask.Header1, currentTask.Header2, currentTask.Header3, currentTask.Header4, currentTask.Proxy, currentTask.ProxyAuth)
					if currentTask.Type == "ImageDownload" then
						currentTask.Type = "Image"
						currentTask.Final = false
					end
				else
					Console.error("No Path given")
					uniques[currentTask.UniqueKey] = nil
					currentTask = nil
				end
			else
				Console.error("No Link given or internet connection problem")
				uniques[currentTask.UniqueKey] = nil
				currentTask = nil
			end
		elseif currentTask.Type == "UnZip" then
			if currentTask.DestPath then
				removeDirectory(currentTask.DestPath)
				if currentTask.Path then
					System.extractZipAsync(currentTask.Path, currentTask.DestPath)
				else
					Console.error("No Path given")
					uniques[currentTask.UniqueKey] = nil
					currentTask = nil
				end
			else
				Console.error("No DestPath given")
				uniques[currentTask.UniqueKey] = nil
				currentTask = nil
			end
		elseif currentTask.Type == "UnZipFile" then
			if currentTask.Extract then
				if currentTask.DestPath then
					if currentTask.Path then
						System.extractFromZipAsync(currentTask.Path, currentTask.Extract, currentTask.DestPath)
					else
						Console.error("No Path given")
						uniques[currentTask.UniqueKey] = nil
						currentTask = nil
					end
				else
					Console.error("No DestPath given")
					uniques[currentTask.UniqueKey] = nil
					currentTask = nil
				end
			else
				Console.error("No Extract file path given")
				uniques[currentTask.UniqueKey] = nil
				currentTask = nil
			end
		end
		if currentTask then
			Console.write(string.format("NET: #%s %s", 4 - currentTask.Retry, currentTask.Link or currentTask.Path or currentTask.UniqueKey), Color.new(0, 255, 0))
		end
	else
		Console.write("(" .. currentTask.Type .. ")" .. (currentTask.Link or currentTask.Path or currentTask.UniqueKey), Color.new(0, 255, 0))
		local saveFunction = function()
			TRASH.Type = currentTask.Type
			TRASH.Link = currentTask.Link
			if currentTask.Type == "StringRequest" then
				local body = getAsyncResult() or ""
				-- lpp-vita's string buffer counts its C terminator: drop the trailing NUL byte(s)
				local trimmed = #body
				while trimmed > 0 and string.byte(body, trimmed) == 0 do
					trimmed = trimmed - 1
				end
				if trimmed < #body then
					body = string.rawsub(body, 1, trimmed)
				end
				currentTask.Table[currentTask.Index] = body
				local len = #currentTask.Table[currentTask.Index]
				if len > 0 then
					bytes = bytes + len
					if len < 100 then
						Console.write("NET:" .. currentTask.Table[currentTask.Index])
					end
				end
			elseif currentTask.Type == "Image" then
				if doesFileExist(currentTask.Path) then
					local Width, Height = System.getPictureResolution(currentTask.Path)
					-- GIFs never reach lpp-vita's decoder: it takes the whole app down (data abort in "Image loader Thread")
					local isGif = Width and Width > 0 and getImageFormat(currentTask.Path) == "gif"
					if not Width or Width < 0 or isGif then
						currentTask.Type = currentTask.Link and "ImageDownload" or currentTask.Type
						if currentTask.Type == "ImageDownload" and not currentTask.Proxied and (Settings.ImageProxy or "Auto") ~= "Off" then
							-- WebP/AVIF/GIF: retry through the converting proxy (it always returns JPEG)
							currentTask.Proxied = true
							currentTask.RawLink = ImageProxy.wrap(currentTask.RawLink or "", currentTask.MaxHeight and currentTask.MaxHeight / 1.5 or nil)
							currentTask.Link = escapeLink(currentTask.RawLink)
							currentTask.Header1, currentTask.Header2, currentTask.Header3, currentTask.Header4 = "", "", "", ""
							currentTask.Retry = currentTask.Retry + 1
							error("Unsupported image format, retrying through proxy")
						elseif currentTask.Type == "ImageDownload" and not isGif then
							error("Redownloading file")
						else
							Console.error(isGif and "GIF images are not supported" or "File you loading isn't picture")
							if ExtLog and not isGif then
								ExtLog("image failed: " .. tostring(currentTask.RawLink or currentTask.Link))
							end
							uniques[currentTask.UniqueKey] = nil
							currentTask = nil
							return
						end
					end
					Console.write(Width .. "x" .. Height .. " Image got")
					if img2bytes(Width, Height, 1) > Graphics.getFreeMemory() and Height <= 4096 and Height / Width <= 2 then
						Console.error("No enough memory to load image")
						uniques[currentTask.UniqueKey] = nil
						currentTask = nil
					else
						if Height > 4096 and Height / Width > 2 and not currentTask.MaxHeight then
							if img2bytes(Width, Height, 1) > Graphics.getFreeMemory() then
								if img2bytes(Width, Height, 2) > Graphics.getFreeMemory() then
									Console.error("No enough memory to load image")
									uniques[currentTask.UniqueKey] = nil
									currentTask = nil
								else
									currentTask.Image = {
										Width = Width / 2,
										Height = Height / 2,
										RealWidth = Width,
										RealHeight = Height,
										Parts = math.ceil(Height / 8192)
									}
								end
							else
								currentTask.Image = {
									Width = Width,
									Height = Height,
									RealWidth = Width,
									RealHeight = Height,
									Parts = math.ceil(Height / 4096)
								}
							end
							Console.write(currentTask.Image.Parts)
							currentTask.Type = "ImageLoadTable"
						else
							local scale = 1
							if currentTask.MaxWidth and currentTask.MaxHeight then
								if Width > Height then
									scale = Width / currentTask.MaxWidth
								else
									scale = Height / currentTask.MaxHeight
								end
							elseif currentTask.MaxWidth then
								scale = Width / currentTask.MaxWidth
							elseif currentTask.MaxHeight then
								scale = Height / currentTask.MaxHeight
							end
							if scale <= 1 then
								scale = 1
							elseif scale <= 2 then
								scale = 2
							elseif scale <= 4 then
								scale = 4
							elseif scale <= 8 then
								scale = 8
							elseif scale <= 16 then
								scale = 16
							elseif scale <= 32 then
								scale = 32
							else
								scale = 64
							end
							Graphics.loadImageAsync(currentTask.Path, scale)
							currentTask.Type = "ImageLoad"
						end
					end
				else
					currentTask.Type = currentTask.Link and "ImageDownload" or currentTask.Type
					if currentTask.Type == "ImageDownload" then
						error("(Image)File not found")
					elseif currentTask.Type == "Image" then
						Console.error("(Image)File not found")
						uniques[currentTask.UniqueKey] = nil
						currentTask = nil
						return
					end
				end
				return
			elseif currentTask.Type == "ImageLoad" then
				if doesFileExist(currentTask.Path) then
					currentTask.Table[currentTask.Index] = Image:new(getAsyncResult(), FILTER_LINEAR)
					currentTask.Final = true
				else
					Console.error("(ImageLoad)File not found")
				end
			elseif currentTask.Type == "ImageLoadTable" then
				if not currentTask.Image.i then
					currentTask.Image.i = 0
					currentTask.Table[currentTask.Index] = {}
					currentTask.Table[currentTask.Index].Parts = currentTask.Image.Parts
					currentTask.Table[currentTask.Index].SliceHeight = math.floor(currentTask.Image.Height / currentTask.Image.Parts)
					currentTask.Table[currentTask.Index].Height = currentTask.Image.Height
					currentTask.Table[currentTask.Index].Width = currentTask.Image.Width
					currentTask.Image.free = function(self)
						for i = 1, #self do
							if self[i] and self[i].free then
								self[i]:free()
							end
						end
					end
				elseif currentTask.Image.i < currentTask.Image.Parts then
					currentTask.Image.i = currentTask.Image.i + 1
					if currentTask.Table[currentTask.Index] == TRASH.Garbadge then
						TRASH.Garbadge = Image:new(getAsyncResult())
						TRASH.Type = "ImageLoadTable2"
						return
					end
					currentTask.Table[currentTask.Index][currentTask.Image.i] = Image:new(getAsyncResult(), FILTER_LINEAR)
					if not currentTask.Table[currentTask.Index][currentTask.Image.i] then
						error("error with part function")
					else
						Console.write(string.format("Got %s image", currentTask.Image.i))
					end
				else
					currentTask.Final = true
					uniques[currentTask.UniqueKey] = nil
					currentTask = nil
					return
				end
				local sliceHeight = math.floor(currentTask.Image.RealHeight / currentTask.Image.Parts)
				local Height = sliceHeight
				if currentTask.Image.i == currentTask.Image.Parts - 1 then
					Height = currentTask.Image.RealHeight - (currentTask.Image.i) * Height
				end
				if currentTask.Image.i < currentTask.Image.Parts then
					Console.write(string.format("Getting %s %sx%s Image", sliceHeight * currentTask.Image.i, currentTask.Image.RealWidth, Height))
					Graphics.loadPartImageAsync(currentTask.Path, 0, sliceHeight * currentTask.Image.i, currentTask.Image.RealWidth, Height)
				else
					uniques[currentTask.UniqueKey] = nil
					currentTask = nil
				end
				return
			elseif currentTask.Type == "FileDownload" then
				if doesFileExist(currentTask.Path) then
					local handle = openFile(currentTask.Path, FREAD)
					bytes = bytes + sizeFile(handle)
					closeFile(handle)
				end
			elseif currentTask.Type == "Skip" then
				Console.error("WOW HOW THAT HAPPENED?")
			end
			uniques[currentTask.UniqueKey] = nil
			currentTask = nil
		end
		local tempTask = currentTask
		local success, err = pcall(saveFunction)
		if success then
			if currentTask == nil then
				if tempTask.OnComplete then
					tempTask.OnComplete()
					Console.write("OnComplete executing for " .. tempTask.Type .. " " .. (tempTask.Link or tempTask.Path or tempTask.UniqueKey))
				end
				if tempTask.Final then
					if tempTask.OnFinalComplete then
						tempTask.OnFinalComplete()
					end
				end
			end
		elseif currentTask ~= nil then
			Console.error("NET: " .. err)
			currentTask.Retry = currentTask.Retry - 1
			if currentTask.Retry > 0 and currentTask.Table ~= TRASH then
				table.insert(orderList, currentTask)
			else
				uniques[currentTask.UniqueKey] = nil
			end
			currentTask = nil
		end
	end
	if TRASH.Garbadge then
		if TRASH.Type == "ImageLoad" then
			Console.write("NET:(Freeing Image)", Color.new(255, 0, 255))
			if TRASH.Garbadge and TRASH.Garbadge.free then
				TRASH.Garbadge:free()
			end
		elseif TRASH.Type == "ImageLoadTable2" then
			Console.write("NET:(Freeing Table Image)", Color.new(255, 0, 255))
			if TRASH.Garbadge and TRASH.Garbadge.free then
				TRASH.Garbadge:free()
			end
		end
		TRASH.Garbadge = nil
	end
end

---Delete all traces
function Threads.clear()
	orderList = {}
	uniques = {}
	if currentTask ~= nil then
		currentTask.Table = TRASH
		currentTask.Index = "Garbadge"
		Network.stopCurrentDownload()
	end
end

---Gives boolean that is any task is running
function Threads.isDownloadRunning()
	return System.getAsyncState() == 0 or #orderList ~= 0 or currentTask ~= nil
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

---Add Network function that uses curl in Task and execute it
function Threads.netActionSafe(foo)
	repeat
	until System.getAsyncState() ~= 0
	return Threads.netActionUnSafe(foo)
end

---Checks if given parameters is enough to execute task
local function taskcheck(t)
	local task = t
	if task.Type == "FileDownload" then
		if task.Link and task.Path then
			return true
		end
	else
		return true
	end
	return false
end

---@param uniqueKey any
---@param t table of parameters
---@param foo function
---Adds task to order with given `t` parameters
local function taskete(uniqueKey, t, foo)
	if uniqueKey and uniques[uniqueKey] and taskcheck(t) or not uniqueKey then
		return false
	end
	local newTask = {
		Type = t.Type,
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
		Path = t.Path and (t.Path:find("^...?0:") and t.Path or ("ux0:data/otakio/" .. t.Path)) or IMAGE_CACHE_PATH,
		Retry = 3,
		HttpMethod = t.HttpMethod or GET_METHOD,
		PostData = t.PostData or "",
		ContentType = t.ContentType or XWWW,
		Cookie = t.Cookie or "",
		UniqueKey = uniqueKey
	}
	if type(newTask.Link) == "table" then
		local t = newTask.Link
		newTask.Link = t.Link
		newTask.Header1 = t.Header1 or newTask.Header1 or ""
		newTask.Header2 = t.Header2 or newTask.Header2 or ""
		newTask.Header3 = t.Header3 or newTask.Header3 or ""
		newTask.Header4 = t.Header4 or newTask.Header4 or ""
		newTask.HttpMethod = t.HttpMethod or newTask.HttpMethod or GET_METHOD
		newTask.PostData = t.PostData or newTask.PostData or ""
		newTask.ContentType = t.ContentType or newTask.ContentType or XWWW
		newTask.Cookie = t.Cookie or newTask.Cookie or ""
	end
	if type(newTask.Link) == "string" then
		newTask.RawLink = newTask.Link:match("^(.-)%s*$") or ""
		newTask.Link = escapeLink(newTask.Link)
	end
	if (newTask.Type == "ImageDownload" or newTask.ImageFile) and newTask.RawLink and ImageProxy.shouldProxy(newTask.RawLink) then
		newTask.RawLink = ImageProxy.wrap(newTask.RawLink, newTask.MaxHeight and newTask.MaxHeight / 1.5 or nil)
		newTask.Link = escapeLink(newTask.RawLink)
		newTask.Header1, newTask.Header2, newTask.Header3, newTask.Header4 = "", "", "", ""
		newTask.Proxied = true
	end
	newTask.Proxy = Settings.UseProxy and (Settings.ProxyIP .. ":" .. Settings.ProxyPort) or ""
	newTask.ProxyAuth = Settings.UseProxyAuth and Settings.ProxyAuth or ""
	foo(newTask)
	uniques[uniqueKey] = newTask
	return true
end

local function taskinsert(task)
	table.insert(orderList, 1, task)
end

---@param uniqueKey string
---@param t table
---@return boolean
---Inserts task to threads
function Threads.insertTask(uniqueKey, t)
	return taskete(uniqueKey, t, taskinsert)
end

local function task_add(task)
	orderList[#orderList + 1] = task
end

---@param uniqueKey string
---@param t table
---@return boolean
---Adds task to threads
function Threads.addTask(uniqueKey, t)
	return taskete(uniqueKey, t, task_add)
end

---Terminates Threads functions and net features
function Threads.terminate()
	if is_net_inited then
		Threads.clear()
		while currentTask do
			Threads.update()
		end
		Network.term()
		is_net_inited = false
	end
end

function Threads.getProgress(uniqueKey)
	local task = uniques[uniqueKey]
	if task then
		if currentTask == task then
			if task.Type == "ImageDownload" or task.Type == "StringRequest" or task.Type == "FileDownload" or (task.Type == "Image" and task.Link) then
				return math.max(math.min(1, Network.getDownloadedBytes() / Network.getTotalBytes()), 0)
			else
				return 1
			end
		else
			return 0
		end
	end
	return 0
end

---@param uniqueKey string
---Removes task by `UniqueKey`
function Threads.remove(uniqueKey)
	if uniques[uniqueKey] then
		if currentTask == uniques[uniqueKey] then
			currentTask.Table, currentTask.Index = TRASH, "Garbadge"
			Network.stopCurrentDownload()
		else
			uniques[uniqueKey].Type = "Skip"
		end
		uniques[uniqueKey] = nil
	end
end

---@param uniqueKey string
---Checks if task is in order by `UniqueKey`
function Threads.check(uniqueKey)
	return uniques[uniqueKey] ~= nil
end

---@return number
---Returns count of bytes downloaded by Threads functions
function Threads.getMemoryDownloaded()
	return bytes
end

---@return integer number of tasks
---Returns quantity of tasks in order
function Threads.getTasksNum()
	return #orderList + (currentTask and 1 or 0)
end

function Threads.getNonSkipTasksNum()
	local c = 0
	for i = 1, #orderList do
		if orderList[i].Type ~= "Skip" then
			c = c + 1
		end
	end
	return c + (currentTask and currentTask.Type ~= "Skip" and 1 or 0)
end
