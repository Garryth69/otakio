-- run after vita_mock: checks that WebP links are routed through the proxy with correct escaping
local ROOT = ...
string.rawsub = string.sub
dofile(ROOT .. "/source/assets/libs/utils.lua")
dofile(ROOT .. "/source/assets/libs/config.lua")
dofile(ROOT .. "/source/assets/libs/http.lua")
Console = {write = function() end, error = print}
Settings = {ImageProxy = "Auto", UseProxy = false}
dofile(ROOT .. "/source/assets/libs/net.lua")
local seen = {}
SIM.fs = {isfile = function() return false end, isdir = function() return true end, remove = function() end}
SIM.download = function(url, path) seen[#seen + 1] = url end
local function run(link)
	Threads.clear()
	Threads.update()
	seen = {}
	local key = {}
	Threads.addTask(key, {Type = "ImageDownload", Link = link, Table = {}, Index = "img"})
	for _ = 1, 3 do
		Threads.update()
	end
	return seen[1]
end
local function eq(a, b) if a ~= b then error("expected\n  " .. tostring(b) .. "\ngot\n  " .. tostring(a), 2) end end
-- lpp-vita un-doubles %% when sending; emulate it
local function sent(u) return (u:gsub("%%%%", "%%")) end
eq(sent(run("https://cdn.site/a%20b.jpg")), "https://cdn.site/a%20b.jpg")
-- Otakio engine: WebP is decoded on the console, no proxy
eq(sent(run("https://cdn.site/x/page 01.webp")), "https://cdn.site/x/page%2001.webp")
-- old NOBORU engine: WebP goes through the converting proxy
ImageProxy.nativeWebp = false
eq(sent(run("https://cdn.site/x/page 01.webp")), "https://wsrv.nl/?url=https%3A%2F%2Fcdn.site%2Fx%2Fpage%2001.webp&output=jpg&q=85&we")
eq(sent(run({Link = "https://cdn.site/c.webp?v=2", Header1 = "Referer: https://site/"})), "https://wsrv.nl/?url=https%3A%2F%2Fcdn.site%2Fc.webp%3Fv%3D2&output=jpg&q=85&we")
Settings.ImageProxy = "Off"
eq(sent(run("https://cdn.site/d.webp")), "https://cdn.site/d.webp")
Settings.ImageProxy = "Auto"
eq(sent(run("https://site.com/up/" .. string.char(224, 184, 128) .. ".jpg")), "https://site.com/up/%E0%B8%80.jpg")
eq(sent(run("https://cdn.site/p/01.GIF")), "https://wsrv.nl/?url=https%3A%2F%2Fcdn.site%2Fp%2F01.GIF&output=jpg&q=85&we")
print("proxy tests OK")
