-- Headless mock of the LuaPlayerPlus Vita API used by Otakio.
-- Lets the whole app boot and run frame-by-frame on a PC under LuaJIT.
local ROOT, TMP = ...
SIM = {trace = debug.traceback, frame = 0, maxFrames = 600, script = {}, keyboardText = "", log = {}, draws = 0, wifi = false}

local function mapPath(p)
	if type(p) ~= "string" then
		return p
	end
	p = p:gsub("^app0:/?", ROOT .. "/source/")
	p = p:gsub("^ux0:/?", TMP .. "/ux0/")
	p = p:gsub("^uma0:/?", TMP .. "/uma0_missing/")
	return p
end
SIM.mapPath = mapPath

local realDofile, realLoadfile, realIoOpen = dofile, loadfile, io.open
function dofile(p)
	return realDofile(mapPath(p))
end
function loadfile(p, ...)
	return realLoadfile(mapPath(p), ...)
end

bit32 = {
	band = bit.band, bor = bit.bor, bnot = bit.bnot, bxor = bit.bxor, lshift = bit.lshift, rshift = bit.rshift
}

-- constants
SCE_CTRL_SELECT, SCE_CTRL_START, SCE_CTRL_UP, SCE_CTRL_RIGHT, SCE_CTRL_DOWN, SCE_CTRL_LEFT = 0x1, 0x8, 0x10, 0x20, 0x40, 0x80
SCE_CTRL_LTRIGGER, SCE_CTRL_RTRIGGER, SCE_CTRL_TRIANGLE, SCE_CTRL_CIRCLE, SCE_CTRL_CROSS, SCE_CTRL_SQUARE = 0x100, 0x200, 0x1000, 0x2000, 0x4000, 0x8000
SCE_CTRL_PSBUTTON = 0x10000
FREAD, FWRITE, FCREATE, FRDWR = 1, 2, 3, 4
GET_METHOD, POST_METHOD, HEAD_METHOD = 0, 1, 2
XWWW, JSON = 0, 1
TYPE_DEFAULT, TYPE_LATIN, TYPE_NUMBER, TYPE_EXT_NUMBER = 0, 1, 2, 3
MODE_TEXT, MODE_PASSWORD = 0, 1
OPT_NO_AUTOCAP, OPT_MULTILINE = 1, 2
RUNNING, FINISHED, CANCELED = 1, 2, 3
FILTER_LINEAR, FILTER_POINT = 1, 0

-- Color: packed integer like lpp-vita
Color = {}
function Color.new(r, g, b, a)
	a = a or 255
	local function c(v)
		v = math.floor(v or 0)
		return v < 0 and 0 or (v > 255 and 255 or v)
	end
	return c(r) + c(g) * 256 + c(b) * 65536 + c(a) * 16777216
end
function Color.getR(c) return c % 256 end
function Color.getG(c) return math.floor(c / 256) % 256 end
function Color.getB(c) return math.floor(c / 65536) % 256 end
function Color.getA(c) return math.floor(c / 16777216) % 256 end

local function checkNum(name, ...)
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v ~= nil and type(v) ~= "number" then
			error(name .. ": argument " .. i .. " expected number, got " .. type(v), 3)
		end
		if v ~= v then
			error(name .. ": argument " .. i .. " is NaN", 3)
		end
	end
end

local images = {}
local nextImage = 1
local function newImage(w, h, path)
	local id = nextImage
	nextImage = nextImage + 1
	if path and SIM.imageSize then
		local iw, ih = SIM.imageSize(path)
		if iw and iw > 0 then
			w, h = iw, ih
		end
	end
	images[id] = {w = w or 64, h = h or 96, path = path}
	if path and SIM.onImageLoad then
		SIM.onImageLoad(id, path)
		images[id].path = "#" .. id
	end
	return id
end

local asyncResult = nil
SIM.ops = nil -- list of draw ops for the current frame when capturing
local function rec(op)
	if SIM.ops then
		SIM.ops[#SIM.ops + 1] = op
	end
end

Graphics = {
	initBlend = function() end,
	termBlend = function() end,
	fillRect = function(...) checkNum("fillRect", ...) SIM.draws = SIM.draws + 1 rec({"rect", ...}) end,
	fillEmptyRect = function(...) checkNum("fillEmptyRect", ...) rec({"orect", ...}) end,
	fillCircle = function(...) checkNum("fillCircle", ...) rec({"circle", ...}) end,
	drawLine = function(...) checkNum("drawLine", ...) end,
	drawImage = function(x, y, img, color)
		checkNum("drawImage", x, y, color)
		if not images[img] then error("drawImage: invalid image", 2) end
		rec({"img", images[img].path or "", x, y, color or false})
	end,
	drawScaleImage = function(x, y, img, sx, sy, color)
		checkNum("drawScaleImage", x, y, sx, sy, color)
		if not images[img] then error("drawScaleImage: invalid image", 2) end
		rec({"simg", images[img].path or "", x, y, sx, sy, color or false})
	end,
	drawRotateImage = function(x, y, img, rad, color) checkNum("drawRotateImage", x, y, rad, color) end,
	drawPartialImage = function(...) end,
	drawImageExtended = function(x, y, img, sx, sy, w, h, rad, scx, scy, color)
		checkNum("drawImageExtended", x, y, sx, sy, w, h, rad, scx, scy, color)
		if not images[img] then error("drawImageExtended: invalid image", 2) end
		rec({"ximg", images[img].path or "", x, y, sx, sy, w, h, scx, scy, color or false})
	end,
	loadImage = function(path)
		local f = realIoOpen(mapPath(path), "rb")
		if not f then
			error("loadImage: missing " .. tostring(path), 2)
		end
		f:close()
		return newImage(64, 64, mapPath(path))
	end,
	-- like lpp-vita: the decoder downscales by `scale` (power of two)
	loadImageAsync = function(path, scale)
		local id = newImage(160, 240, mapPath(path))
		scale = scale or 1
		if scale > 1 then
			images[id].w = math.ceil(images[id].w / scale)
			images[id].h = math.ceil(images[id].h / scale)
		end
		asyncResult = id
	end,
	-- a slice of a tall image; slices taller than the 4096 px texture limit come back at half size
	loadPartImageAsync = function(path, x, y, w, h)
		w, h = w or 160, h or 240
		if h > 4096 then
			w, h = math.ceil(w / 2), math.ceil(h / 2)
		end
		asyncResult = newImage(w, h)
	end,
	loadGifAsync = function(path) asyncResult = nil end,
	returnGif = function() return nil end,
	getImageWidth = function(img) return images[img] and images[img].w or 0 end,
	getImageHeight = function(img) return images[img] and images[img].h or 0 end,
	freeImage = function(img)
		if not images[img] then error("freeImage: double free", 2) end
		images[img] = nil
	end,
	setImageFilters = function() end,
	-- the Vita has roughly 112 MB for textures once the app is running
	getFreeMemory = function() return math.max(0, 112 * 1024 * 1024 - (GetGPUMemoryUsed and GetGPUMemoryUsed() or 0)) end,
	initRescaler = function() end,
	termRescaler = function() end
}

local fontCount = 0
Font = {
	load = function(path) fontCount = fontCount + 1 return {id = fontCount, size = 16, bold = path:find("robboto") ~= nil} end,
	setPixelSizes = function(f, s) f.size = s end,
	print = function(f, x, y, text, color)
		checkNum("Font.print", x, y, color)
		if type(text) ~= "string" and type(text) ~= "number" then
			error("Font.print: text must be string, got " .. type(text), 2)
		end
		rec({"text", f.size, f.bold, x, y, tostring(text), color})
	end,
	getTextWidth = function(f, text)
		if SIM.textWidth then
			return SIM.textWidth(f.size, f.bold, tostring(text))
		end
		return #tostring(text) * math.floor(f.size * 0.5)
	end,
	getTextHeight = function(f, text) return f.size end,
	unload = function() end
}

Screen = {
	clear = function(color) checkNum("Screen.clear", color) rec({"clear", color or 0}) end,
	waitVblankStart = function() end,
	flip = function()
		if SIM.ops and SIM.onCapture then
			SIM.onCapture(SIM.frame, SIM.ops)
		end
		SIM.ops = nil
		SIM.frame = SIM.frame + 1
		if SIM.capture and SIM.capture[SIM.frame] then
			SIM.ops = {}
		end
		if SIM.onFrame then
			SIM.onFrame(SIM.frame)
		end
		if SIM.frame >= SIM.maxFrames then
			error("SIM_DONE", 0)
		end
	end
}

local currentPad = 0
local currentTouch = nil
Controls = {
	read = function()
		local s = SIM.script[SIM.frame]
		currentPad = s and s.pad or 0
		currentTouch = s and s.touch or nil
		return currentPad
	end,
	readTouch = function()
		if currentTouch then
			return currentTouch[1], currentTouch[2]
		end
		return nil
	end,
	check = function(pad, btn)
		return bit.band(pad, btn) ~= 0
	end,
	readLeftAnalog = function() return 128, 128 end,
	readRightAnalog = function() return 128, 128 end,
	rumble = function() end
}

Timer = {
	new = function() return {start = SIM.frame} end,
	getTime = function(t) return (SIM.frame - t.start) * 16.7 end,
	reset = function(t) t.start = SIM.frame end,
	destroy = function() end,
	pause = function() end,
	resume = function() end
}

-- file system ---------------------------------------------------------------
local lfs = SIM.fs -- provided by python
local handles = {}
System = {
	doesFileExist = function(p) return SIM.fs.isfile(mapPath(p)) end,
	doesDirExist = function(p) return SIM.fs.isdir(mapPath(p)) end,
	createDirectory = function(p) SIM.fs.mkdir(mapPath(p)) end,
	deleteFile = function(p) SIM.fs.remove(mapPath(p)) end,
	deleteDirectory = function(p) SIM.fs.rmdir(mapPath(p)) end,
	rename = function(a, b) SIM.fs.rename(mapPath(a), mapPath(b)) end,
	listDirectory = function(p)
		local list = SIM.fs.listdir(mapPath(p))
		if not list then return nil end
		local out = {}
		for i = 1, #list do
			out[i] = {name = list[i].name, directory = list[i].directory, size = list[i].size}
		end
		return out
	end,
	openFile = function(p, mode)
		local path = mapPath(p)
		local f
		if mode == FREAD then
			f = realIoOpen(path, "rb")
		elseif mode == FCREATE then
			f = realIoOpen(path, "wb")
		else
			f = realIoOpen(path, "r+b") or realIoOpen(path, "wb")
		end
		if not f then
			error("openFile failed: " .. tostring(p), 2)
		end
		handles[f] = true
		return f
	end,
	readFile = function(f, n) return f:read(n) or "" end,
	writeFile = function(f, data, n)
		-- byte-exact: the app replaces string.sub with a UTF-8 aware version (binary data would be mangled)
		local s = tostring(data)
		if n and n < #s then
			s = (string.rawsub or string.sub)(s, 1, n)
		end
		f:write(s)
	end,
	closeFile = function(f) f:close() handles[f] = nil end,
	sizeFile = function(f)
		local cur = f:seek()
		local size = f:seek("end")
		f:seek("set", cur)
		return size
	end,
	statFile = function(p) return {directory = SIM.fs.isdir(mapPath(p))} end,
	getPictureResolution = function(p)
		if SIM.fs.isfile(mapPath(p)) then
			local w, h = nil, nil
			if SIM.imageSize then
				w, h = SIM.imageSize(mapPath(p))
			end
			if w and w > 0 then
				return w, h
			end
			return 160, 240
		end
		return -1, -1
	end,
	getImageFormat = function(p)
		-- by magic bytes, with the names lpp-vita returns ("jpeg", not "jpg"); unknown files give nil
		local f = io.open(mapPath(p), "rb")
		local head = f and f:read(12) or ""
		if f then f:close() end
		if head:find("^RIFF") and head:find("WEBP", 9, true) == 9 then return "webp" end
		if head:find("^GIF") then return "gif" end
		local b1, b2, b3, b4 = head:byte(1, 4)
		if b1 == 0x89 and b2 == 0x50 and b3 == 0x4E and b4 == 0x47 then return "png" end
		if head:find("^BM") then return "bmp" end
		if b1 == 0xFF and b2 == 0xD8 then return "jpeg" end
		return nil
	end,
	convertImage = function(src, dst, fmt)
		return SIM.fs.convert and SIM.fs.convert(mapPath(src), mapPath(dst), fmt or "jpg") or false
	end,
	getLanguage = function() return SIM.language or 1 end,
	getAsyncState = function() return 1 end,
	getAsyncResult = function() local r = asyncResult asyncResult = nil return r end,
	extractZipAsync = function(zip, dst) PYFS.extractall(mapPath(zip), mapPath(dst)) end,
	extractFromZipAsync = function(zip, name, dst) PYFS.extract(mapPath(zip), name, mapPath(dst)) end,
	extractFromZip = function(zip, name, dst) return PYFS.extract(mapPath(zip), name, mapPath(dst)) end,
	listZip = function(p)
		local out = {}
		for name in tostring(SIM.fs.listzip and SIM.fs.listzip(mapPath(p)) or ""):gmatch("[^\n]+") do
			out[#out + 1] = {name = name, directory = false}
		end
		return out
	end,
	executeUri = function() end,
	launchApp = function(id) SIM.launched = id end,
	installApp = function(dir)
		SIM.installedFrom = dir
		if SIM.installFails then
			return true -- the real promoter returns success even when it fails
		end
		return PYFS.promote(mapPath(dir), mapPath("ux0:app/OTAK00001"))
	end,
	exit = function() SIM.exited = true end,
	checkApp = function() return false end,
	removeApp = function() end,
	getFreeSpace = function() return 1024 * 1024 * 1024 end,
	setCpuSpeed = function() end,
	setBusSpeed = function() end,
	setGpuSpeed = function() end,
	setGpuXbarSpeed = function() end,
	getTime = function() return 12, 0, 0 end,
	getDate = function() return 1, 1, 1, 2026 end,
	takeScreenshot = function() end,
	wait = function() end,
	getFreeRamMemory = function() return 128 * 1024 * 1024 end,
	getVersion = function() return "3.65" end
}

Network = {
	init = function() end,
	term = function() end,
	isWifiEnabled = function() return SIM.wifi end,
	requestStringAsync = function(url, ua, method, post, ctype, cookie, h1, h2, h3, h4)
		asyncResult = SIM.http and SIM.http(url, ua, method, post, ctype, cookie, h1, h2, h3, h4) or ""
	end,
	downloadFileAsync = function(url, path, ua, method, post, ctype, cookie, h1, h2, h3, h4)
		if SIM.download then
			SIM.download(url, mapPath(path), ua, method, post, ctype, cookie, h1, h2, h3, h4)
		end
	end,
	requestString = function() return "" end,
	downloadFile = function() end,
	getDownloadedBytes = function() return 0 end,
	getTotalBytes = function() return 1 end,
	stopCurrentDownload = function() end,
	setConnectionTime = function() end
}

local kbState = 0
Keyboard = {
	show = function(title, default)
		SIM.log[#SIM.log + 1] = "keyboard: " .. tostring(title)
		kbState = FINISHED
	end,
	getState = function() return kbState == 0 and CANCELED or kbState end,
	getInput = function() return SIM.keyboardText end,
	clear = function() kbState = 0 end
}

Sound = {}

-- debugging aid: fields of the Threads task being started (finds the net.lua 'start' frame)
local dbg = debug
function SIM.dumpTask()
	for level = 2, 30 do
		local info = dbg.getinfo(level, "S")
		if not info then break end
		if info.short_src:find("net.lua", 1, true) then
			local name, task = dbg.getlocal(level, 1)
			if name == "task" and type(task) == "table" then
				local out = {}
				for k, v in pairs(task) do
					if type(v) ~= "function" then out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
				end
				local tb = task.Table
				if type(tb) == "table" then
					for k, v in pairs(tb) do out[#out + 1] = "Table." .. tostring(k) .. "=" .. tostring(v) end
					if type(tb[1]) == "table" then for k, v in pairs(tb[1]) do out[#out + 1] = "Table[1]." .. tostring(k) .. "=" .. tostring(v) end end
				end
				return table.concat(out, "\n")
			end
		end
	end
	return "?"
end
