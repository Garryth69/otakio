-- Browse language filter (parser.lua): follows the languages chosen in Extensions, multi-language sources serve
-- every language, Portuguese covers pt-BR and pt sources
local root = ...
System = {}
Console = {write = function() end, error = function() end}
LAUNCHED = false
Settings = {NSFW = false, FavouriteParsers = {}, ParserLanguage = "DIF"}
local LANG_MAP = {all = "DIF", en = "ENG", ["pt-BR"] = "BRA", pt = "PRT", tr = "TUR", ja = "JAP"}
Engines = {toParserLang = function(iso) return LANG_MAP[iso] or string.upper(iso) end}
dofile(root .. "/source/assets/libs/parser.lua")

local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end
local function sorted(csv)
	local t = {}
	for x in tostring(csv):gmatch("[^,]+") do
		t[#t + 1] = x
	end
	table.sort(t)
	return table.concat(t, ",")
end
local function eqset(a, b, msg) eq(sorted(a), sorted(b), msg) end
local function src(id, iso)
	local p = Parser:new(id, "https://" .. id, Engines.toParserLang(iso), id, 1)
	p.IsoLang = iso
	return p
end
local function names()
	local t = {}
	for _, p in ipairs(GetParserList()) do
		t[#t + 1] = p.ID
	end
	table.sort(t)
	return table.concat(t, ",")
end
local function refresh()
	ChangeNSFW()
end

-- the user's case on the Vita: Portuguese and English chosen, only multi-language and English sources installed
src("multib", "all")
src("multia", "all")
src("ensite", "en")
Settings.ExtLanguages = {pt = true, en = true}
eq(table.concat(GetParserLanguages(), ","), "DIF,ENG,PRT", "chosen languages without own sources")

Settings.ParserLanguage = "PRT"
refresh()
eqset(names(), "multia,multib", "Portuguese shows the multi-language sources")
eq(table.concat(BrowseLanguageIsos(), ","), "pt-br,pt,en", "multi-language source asks for Portuguese")

-- Portuguese covers Brazil and Portugal sources; English sources stay out
src("brsite", "pt-BR")
src("ptsite", "pt")
refresh()
eqset(names(), "brsite,multia,ptsite,multib", "Portuguese filter")
eq(table.concat(GetParserLanguages(), ","), "DIF,ENG,PRT", "no duplicate Portuguese")

Settings.ParserLanguage = "ENG"
refresh()
eqset(names(), "multia,multib,ensite", "English filter")

-- an old saved "BRA" becomes "PRT"
Settings.ParserLanguage = "BRA"
refresh()
eqset(names(), "brsite,multia,ptsite,multib", "saved BRA")
eq(Settings.ParserLanguage, "PRT", "BRA migrated")

-- a language turned off resets the filter to all languages
Settings.ExtLanguages = {en = true}
refresh()
eqset(names(), "multia,multib,ensite", "Portuguese turned off")
eq(Settings.ParserLanguage, "DIF", "reset to all")
eq(BrowseLanguageIsos(), nil, "all languages -> no preference")

-- "other" languages list the installed codes
src("trsite", "tr")
Settings.ExtLanguages = {en = true, other = true}
refresh()
eq(table.concat(GetParserLanguages(), ","), "DIF,ENG,TUR", "other languages")
Settings.ParserLanguage = "TUR"
refresh()
eqset(names(), "multia,trsite,multib", "Turkish filter")

-- no choice made: languages of the installed sources (Portuguese once)
Settings.ExtLanguages = {}
Settings.ParserLanguage = "DIF"
refresh()
eq(table.concat(GetParserLanguages(), ","), "DIF,ENG,PRT,TUR", "no choice")
-- every language chosen, sources in each language (raw Japanese/Chinese too)
for _, iso in ipairs({"es", "fr", "de", "it", "ru", "ja", "zh"}) do
	LANG_MAP[iso] = ({es = "ESP", fr = "FRA", de = "DEU", it = "ITA", ru = "RUS", ja = "JAP", zh = "CHN"})[iso]
	src(iso .. "site", iso)
end
local raw = Parser:new("rawsite", "https://rawsite", "RAW", "rawsite", 1)
Settings.ExtLanguages = {en = true, pt = true, es = true, fr = true, de = true, it = true, ru = true, ja = true, zh = true, other = true}
Settings.ParserLanguage = "DIF"
refresh()
eq(table.concat(GetParserLanguages(), ","), "DIF,ENG,PRT,ESP,FRA,DEU,ITA,RUS,JAP,CHN,TUR", "every language")
local expect = {
	ENG = {"multia,multib,ensite", "en"},
	PRT = {"brsite,multia,ptsite,multib", "pt-br,pt,en"},
	ESP = {"essite,multia,multib", "es-la,es,en"},
	FRA = {"frsite,multia,multib", "fr,en"},
	DEU = {"desite,multia,multib", "de,en"},
	ITA = {"itsite,multia,multib", "it,en"},
	RUS = {"multia,rusite,multib", "ru,en"},
	JAP = {"jasite,multia,rawsite,multib", "ja,en"},
	CHN = {"multia,rawsite,multib,zhsite", "zh,zh-hk,en"},
	TUR = {"multia,trsite,multib", nil}
}
for code, e in pairs(expect) do
	Settings.ParserLanguage = code
	refresh()
	eqset(names(), e[1], code .. " sources")
	local isos = BrowseLanguageIsos()
	eq(isos and table.concat(isos, ",") or nil, e[2], code .. " multi-language source languages")
end
-- only Japanese chosen: raw sources still show, Chinese ones don't
Settings.ExtLanguages = {ja = true}
Settings.ParserLanguage = "JAP"
refresh()
eq(table.concat(GetParserLanguages(), ","), "DIF,JAP", "Japanese only")
eqset(names(), "jasite,multia,rawsite,multib", "Japanese only sources")
-- an extension with one source per language (the per-language extension: en, es, fr, de)
LANG_MAP.es, LANG_MAP.fr, LANG_MAP.de = "ESP", "FRA", "DEU"
CURRENT_EXTENSION_ID = "otakio.multib"
local pl = {}
for _, l in ipairs({"es", "fr", "en", "de"}) do
	pl[l] = src("PL_" .. l:upper(), l)
end
CURRENT_EXTENSION_ID = "otakio.multisrc2"
local md = src("MULTI2", "all")
CURRENT_EXTENSION_ID = nil
local function groups(set)
	local t = {}
	for g in pairs(set or {}) do
		t[#t + 1] = g
	end
	table.sort(t)
	return table.concat(t, ",")
end
eq(groups(GetExtensionLangGroups("otakio.multib")), "de,en,es,fr", "the per-language extension languages")
eq(GetExtensionLangGroups("otakio.multisrc2"), nil, "multi-language source: every language")
eq(GetExtensionLangGroups("nothing"), nil, "unknown extension")

Settings.ExtLanguages = {pt = true, en = true}
Settings.ParserLanguage = "DIF"
refresh()
eq(GetParserOfExtension("otakio.multib"), pl.en, "opens English by default (not a random one)")
eq(GetParserOfExtension("otakio.multib", "es"), pl.es, "Spanish chip opens Spanish")
eq(GetParserOfExtension("otakio.multib", "pt"), pl.en, "no Portuguese: English")
Settings.ExtLanguages = {fr = true}
Settings.ParserLanguage = "FRA"
refresh()
eq(GetParserOfExtension("otakio.multib"), pl.fr, "Browse filter French opens French")
Settings.ParserLanguage = "DIF"
refresh()
eq(GetParserOfExtension("otakio.multib"), pl.fr, "an active language before English")
Settings.ExtLanguages = {fr = true, en = true}
eq(GetParserOfExtension("otakio.multib"), pl.en, "English first among active languages")
Settings.ExtLanguages = {pt = true}
eq(GetParserOfExtension("otakio.multib"), pl.en, "none of its languages active: English")
eq(GetParserOfExtension("otakio.multisrc2", "es"), md, "single source")
for _ = 1, 20 do
	eq(GetParserOfExtension("otakio.multib", "it"), pl.en, "always the same")
end

-- the first-run "Install recommended sources" filter
Settings.ExtLanguages = {pt = true}
eq(IsExtensionLangEnabled("all", {"en", "es", "fr", "de"}), false, "the per-language extension not recommended to a Portuguese reader")
eq(IsExtensionLangEnabled("all", nil), true, "multi-language source recommended")
eq(IsExtensionLangEnabled("pt-BR", nil), true, "Portuguese source")
eq(IsExtensionLangEnabled("en", nil), false, "English source")
Settings.ExtLanguages = {pt = true, es = true}
eq(IsExtensionLangEnabled("all", {"en", "es", "fr", "de"}), true, "the per-language extension for a Spanish reader")
Settings.ExtLanguages = {}
eq(IsExtensionLangEnabled("all", {"en"}), true, "no choice made: everything")
print("browse language tests OK")
