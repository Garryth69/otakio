-- Remote settings (remoteconfig.lua): only valid values are applied, a notice shows once, the cached copy works offline
local root = ...
local files = {}
FS = {
	read = function(path) return files[path] end,
	write = function(path, data) files[path] = data return true end,
	append = function(path, data) files[path] = (files[path] or "") .. data return true end
}
Console = {write = function() end, error = function() end}
Clock = {date = function() return "2026-12-01" end}
Settings = {Language = "PortugueseBR"}
Config = {GITHUB_REPO = "owner/app", IMAGE_PROXY = "https://wsrv.nl/?url=%s&output=jpg"}
USERAGENT = "Mozilla/5.0 old"
local shown, disabled = {}, {}
Notifications = {push = function(text) shown[#shown + 1] = text end}
function DisableParsersOfExtension(id) disabled[#disabled + 1] = id end
dofile(root .. "/source/assets/libs/json.lua")
dofile(root .. "/source/assets/libs/remoteconfig.lua")

local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end

local UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0 Safari/537.36"

-- invalid values are ignored
RemoteConfig.apply({userAgent = "curl/8", imageProxy = "http://evil/?u=%s"}, true)
eq(USERAGENT, "Mozilla/5.0 old", "a user agent that isn't a browser one is ignored")
eq(Config.IMAGE_PROXY, "https://wsrv.nl/?url=%s&output=jpg", "a non-https proxy is ignored")
RemoteConfig.apply({imageProxy = "https://p.example/?u=%s&x=%d"}, true)
eq(Config.IMAGE_PROXY, "https://wsrv.nl/?url=%s&output=jpg", "a proxy with two format codes is ignored")
RemoteConfig.apply({imageProxy = "https://p.example/?u=%s\n"}, true)
eq(Config.IMAGE_PROXY, "https://wsrv.nl/?url=%s&output=jpg", "control characters are refused")
RemoteConfig.apply({format = 2, userAgent = UA}, true)
eq(USERAGENT, "Mozilla/5.0 old", "an unknown format is not applied")
RemoteConfig.apply("garbage", true)
RemoteConfig.apply({userAgent = 5, disabledExtensions = "x", notice = "y"}, true)

-- valid values
RemoteConfig.apply({format = 1, userAgent = UA, imageProxy = "https://img.example/convert?u=%s&fmt=jpg", disabledExtensions = {"kei.en.bad", 7, ""}}, true)
eq(USERAGENT, UA, "user agent")
eq(Config.IMAGE_PROXY, "https://img.example/convert?u=%s&fmt=jpg", "image proxy")
eq(#disabled, 1, "only string ids are disabled")
eq(disabled[1], "kei.en.bad", "disabled id")
RemoteConfig.apply({disabledExtensions = {"kei.en.bad"}}, true)
eq(#disabled, 1, "an extension is disabled once per session")

-- notice: in the user's language, once, and not after its end date
local notice = {id = "n1", ["until"] = "2027-01-01", text = {English = "Hello", PortugueseBR = "Olá"}}
RemoteConfig.apply({notice = notice}, true)
eq(shown[1], "Olá", "notice in the chosen language")
RemoteConfig.apply({notice = notice}, true)
eq(#shown, 1, "a notice shows once")
RemoteConfig.apply({notice = {id = "n2", ["until"] = "2026-11-30", text = "Old"}}, true)
eq(#shown, 1, "an expired notice doesn't show")
Settings.Language = "German"
RemoteConfig.apply({notice = {id = "n3", text = {English = "Hi"}}}, true)
eq(shown[2], "Hi", "English when the language has no text")
RemoteConfig.apply({notice = {id = "n4", text = {English = "Cached"}}}, false)
eq(#shown, 2, "the cached copy never shows notices")

-- the copy on the card is applied at startup
files["ux0:data/otakio/remote.json"] = '{"format":1,"userAgent":"' .. UA:gsub("140", "141") .. '"}'
RemoteConfig.loadCached()
eq(USERAGENT, UA:gsub("140", "141"), "cached copy applied")
files["ux0:data/otakio/remote.json"] = "{broken"
RemoteConfig.loadCached()

-- the file published in the repository is valid
local published = Json.decode(io.open(root .. "/remote.json"):read("*a"))
eq(type(published), "table", "remote.json parses")
USERAGENT = "x"
Config.IMAGE_PROXY = "x"
RemoteConfig.apply(published, false)
eq(USERAGENT, published.userAgent, "published user agent is valid")
eq(Config.IMAGE_PROXY, published.imageProxy, "published image proxy is valid")
print("remote config tests OK")
