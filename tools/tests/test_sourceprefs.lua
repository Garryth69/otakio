-- Source settings (sourceprefs.lua): saved filters, the extension's own preferences (parser:pref) and the site address
-- that replaces a source's own in every request (and in Referer/Origin headers)
local root = ...
local files = {}
FS = {
	read = function(path) return files[path] end,
	write = function(path, data) files[path] = data return true end
}
System = {}
Console = {write = function() end, error = function() end}
LAUNCHED = false
Settings = {NSFW = false, FavouriteParsers = {}, ParserLanguage = "DIF"}
Engines = {toParserLang = function(iso) return string.upper(iso) end}
dofile(root .. "/source/assets/libs/json.lua")
dofile(root .. "/source/assets/libs/parser.lua")
dofile(root .. "/source/assets/libs/sourceprefs.lua")

local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end

local p = Parser:new("Site", "https://old.example", "ENG", "SITE", 1)
p.Preferences = {
	{Key = "quality", Name = "Image quality", Type = "radio", Tags = {"High", "Low"}},
	{Key = "lang", Name = "Language", Type = "radio", Tags = {"en", "es"}, Default = "es"}
}

-- preferences: defaults, then stored values
eq(p:pref("quality"), "High", "radio default is the first tag")
eq(p:pref("lang"), "es", "declared default")
eq(p:pref("missing"), nil, "unknown key")
SourcePrefs.setPref("SITE", "quality", "Low")
eq(p:pref("quality"), "Low", "stored value")

-- filters are kept per source
SourcePrefs.setFilters("SITE", {["Sort By"] = "Rating", Genres = {"Action"}})
eq(SourcePrefs.getFilters("SITE")["Sort By"], "Rating", "saved filter")
eq(SourcePrefs.getFilters("OTHER"), nil, "other sources have none")

-- site address: requests to the old host go to the new one, path and query kept
eq(SourcePrefs.rewrite("https://old.example/manga/x?page=2"), "https://old.example/manga/x?page=2", "no override yet")
SourcePrefs.setCache("SITE", "genres", {{"action", "Action"}})
eq(SourcePrefs.setDomain("SITE", "https://old.example", "new.example"), true, "bare host accepted")
eq(SourcePrefs.getDomain("SITE"), "https://new.example", "https added")
eq(SourcePrefs.getCache("SITE", "genres"), nil, "the old address's genre list is forgotten")
eq(SourcePrefs.rewrite("https://old.example/manga/x?page=2"), "https://new.example/manga/x?page=2", "rewritten")
eq(SourcePrefs.rewrite("https://OLD.example/a"), "https://new.example/a", "host match ignores case")
eq(SourcePrefs.rewrite("https://cdn.old.example/img.jpg"), "https://cdn.old.example/img.jpg", "other hosts kept")
eq(SourcePrefs.rewrite("https://other.example/old.example"), "https://other.example/old.example", "only the host part")
eq(SourcePrefs.rewriteHeader("Referer: https://old.example/"), "Referer: https://new.example/", "referer")
eq(SourcePrefs.rewriteHeader("Cookie: a=https://old.example"), "Cookie: a=https://old.example", "other headers kept")
eq(SourcePrefs.setDomain("SITE", "https://old.example", "ftp://x.example"), false, "only http(s)")
eq(SourcePrefs.getDomain("SITE"), "https://new.example", "a refused address changes nothing")

-- the file round-trips: a fresh load sees the same settings
local saved = files["ux0:data/otakio/source_prefs.json"]
assert(saved and saved:find("new.example", 1, true), "written to the card")
dofile(root .. "/source/assets/libs/sourceprefs.lua")
eq(SourcePrefs.getDomain("SITE"), "https://new.example", "reloaded")
eq(SourcePrefs.rewrite("https://old.example/x"), "https://new.example/x", "rewrite after reload")

-- back to the default
SourcePrefs.setDomain("SITE", "https://old.example", "")
eq(SourcePrefs.getDomain("SITE"), nil, "cleared")
eq(SourcePrefs.rewrite("https://old.example/x"), "https://old.example/x", "no rewrite once cleared")
print("source prefs tests OK")
