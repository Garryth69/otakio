-- Automatic diagnostics (diag.lua): what is removed from lines before they go into log.txt
local root = ...
string.rawsub = string.sub
Config = {DATA = "ux0:data/otakio/"}
System = {}
Timer = {new = function() return {} end, getTime = function() return 0 end}
Console = {error = function() end}
Graphics = {}
dofile(root .. "/source/assets/libs/diag.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end
local function hasnt(s, part, msg) if s:find(part, 1, true) then error((msg or "") .. ": [" .. part .. "] still in [" .. s .. "]", 2) end end

local c = Diag.clean
eq(c("GET https://api.site.com/v1/chapter?id=5&token=abc123 failed"), "GET https://api.site.com/v1/chapter?... failed", "query string")
eq(c("img https://cdn.site.com/a/b.jpg#frag"), "img https://cdn.site.com/a/b.jpg?...", "fragment")
eq(c("plain https://site.com/manga/one-piece"), "plain https://site.com/manga/one-piece", "clean URL kept")
local l = c("login user.name+x@example.com from 10.20.30.40 cookie=sess99; password: hunter2 token:xyz Authorization: Bearer")
hasnt(l, "example.com", "e-mail")
hasnt(l, "10.20.30", "ip")
hasnt(l, "sess99", "cookie")
hasnt(l, "hunter2", "password")
hasnt(l, "xyz", "token")
eq(c("install otakio.mangadex v1"), "install otakio.mangadex v1", "ordinary line untouched")

-- the input line: presses, touches, and what held touches back (a touch problem shows in the log)
local logged = {}
ExtLog = function(t) logged[#logged + 1] = t end
local now = 0
Timer.getTime = function() return now end
System.getFreeRamMemory = nil
Diag.input(true, false)
Diag.input(false, true, nil, "CATALOGS")
Diag.input(false, true, "finger kept from before", "HISTORY+details")
now = 31000
Diag.update()
local line
for _, t in ipairs(logged) do
	if t:find("^input:") then
		line = t
	end
end
eq(line, "input: 1 presses, 2 touches (held back: finger kept from before x1), last touch in HISTORY+details", "input line")
logged = {}
now = 62000
Diag.update()
for _, t in ipairs(logged) do
	hasnt(t, "input:", "quiet period")
end
print("diag tests OK")
