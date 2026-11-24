-- Image proxy fallback (net.lua): after several failures in a row the next proxy of Config.IMAGE_PROXIES takes over,
-- a success resets the count, and links through any listed proxy count as proxied
local root = ...
local logged = {}
ExtLog = function(msg) logged[#logged + 1] = msg end
Config = {IMAGE_PROXY = "https://one.example/?u=%s", IMAGE_PROXIES = {"https://one.example/?u=%s", "https://two.example/?u=%s"}}
Settings = {ImageProxy = "Auto"}
-- net.lua only needs the engine's functions at load time; everything else is called later
System = setmetatable({}, {__index = function() return function() end end})
Network = System
Graphics, Timer, Screen, Threads = System, System, System, nil
local ok, err = pcall(dofile, root .. "/source/assets/libs/net.lua")
assert(ok, err)

local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end

eq(ImageProxy.isProxied("https://two.example/?u=x"), true, "second proxy recognised")
eq(ImageProxy.isProxied("https://site.example/a.jpg"), false, "a plain link is not proxied")
for _ = 1, 3 do
	ImageProxy.noteResult(false)
end
ImageProxy.noteResult(true)
for _ = 1, 3 do
	ImageProxy.noteResult(false)
end
eq(Config.IMAGE_PROXY, "https://one.example/?u=%s", "a success resets the count")
ImageProxy.noteResult(false)
eq(Config.IMAGE_PROXY, "https://two.example/?u=%s", "four failures in a row: the next proxy")
for _ = 1, 4 do
	ImageProxy.noteResult(false)
end
eq(Config.IMAGE_PROXY, "https://one.example/?u=%s", "wraps around")
assert(logged[1]:find("switched to two.example", 1, true), logged[1])
print("proxy switch tests OK")
