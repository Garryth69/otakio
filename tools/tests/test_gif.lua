-- run after vita_mock with a real fs: GIF files (even behind a .jpg link) must never reach Graphics.loadImageAsync,
-- lpp-vita's GIF decoder crashes the app (psp2core data abort in "Image loader Thread")
local ROOT = ...
string.rawsub = string.sub
dofile(ROOT .. "/source/assets/libs/utils.lua")
dofile(ROOT .. "/source/assets/libs/config.lua")
dofile(ROOT .. "/source/assets/libs/http.lua")
Console = {write = function() end, error = function() end}
Settings = {ImageProxy = "Auto", UseProxy = false}
dofile(ROOT .. "/source/assets/libs/net.lua")
local GIF = "GIF89a" .. string.rep("\0", 64)
local JPG = "\255\216\255\224" .. string.rep("\0", 64)
local seen, loaded = {}, 0
local realLoad = Graphics.loadImageAsync
Graphics.loadImageAsync = function(...) loaded = loaded + 1 return realLoad(...) end
SIM.download = function(url, path)
	seen[#seen + 1] = url
	SIM.fs.mkdir((path:gsub("/[^/]*$", "")))
	local f = assert(io.open(path, "wb"))
	f:write(url:find("wsrv.nl", 1, true) and JPG or GIF)
	f:close()
end
local function run(link)
	Threads.clear()
	Threads.update()
	seen, loaded = {}, 0
	local t = {}
	Threads.addTask(t, {Type = "ImageDownload", Link = link, Table = t, Index = "img"})
	for _ = 1, 40 do
		Threads.update()
	end
	return t.img
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local img = run("https://cdn.site/disguised.jpg")
check(#seen == 2 and seen[2]:find("wsrv.nl", 1, true), "GIF content should be re-downloaded through the proxy, got " .. #seen .. " downloads")
check(loaded == 1, "converted JPEG should be loaded once, loaded=" .. loaded)
Settings.ImageProxy = "Off"
img = run("https://cdn.site/disguised2.jpg")
check(loaded == 0, "with the proxy off a GIF must be dropped, not decoded")
print("gif guard tests OK")
