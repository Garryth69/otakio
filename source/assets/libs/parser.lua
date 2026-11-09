---@class Parser
Parser = {
	getLatestManga = nil,
	getPopularManga = nil,
	getChapters = nil,
	prepareChapter = nil,
	loadChapterPage = nil,
	getMangaUrl = nil
}

---Hash table with all parsers
local parserTable = {}
---Cached Parser List
local cachedList = {}

---Local variable used in Parser functions
local is_parsers_list_updated = false

local listDirectory = System.listDirectory
local doesDirExist = System.doesDirExist
local deleteFile = System.deleteFile

---@param Name string
---@param Link string
---@param Lang string
---@param ID integer
---@return Parser
---Creates/Updates Parser Object
function Parser:new(Name, Link, Lang, ID, Version)
	local p = {
		Name = Name,
		Link = Link,
		Lang = Lang,
		ID = ID,
		Version = Version or 0,
		isChanged = 0,
		Disabled = false,
		ExtensionID = CURRENT_EXTENSION_ID
	}
	setmetatable(p, self)
	self.__index = self
	if parserTable[ID] and parserTable[ID].Version < p.Version then
		p.isUpdated = true
		p.isChanged = 1
	elseif parserTable[ID] == nil and LAUNCHED then
		p.isNew = true
		p.isChanged = 2
	end
	if Console then
		Console.write('Parser "' .. tostring(Name) .. '" ' .. (parserTable[ID] and "updated" or "loaded"))
	end
	parserTable[ID] = p
	is_parsers_list_updated = true
	return p
end

---@param extensionID string
---Disables every parser created by an extension (used on uninstall/update)
function DisableParsersOfExtension(extensionID)
	for _, v in pairs(parserTable) do
		if v.ExtensionID == extensionID then
			v.Disabled = true
		end
	end
	is_parsers_list_updated = true
end

---@return integer
function CountParsers()
	local n = 0
	for _, v in pairs(parserTable) do
		if not v.Disabled then
			n = n + 1
		end
	end
	return n
end

---@param ID integer
---@return Parser
---Gives Parser Object by `ID`
function GetParserByID(ID)
	local p = parserTable[ID]
	if p and p.Disabled then
		return nil
	end
	return p
end

---Like GetParserByID but also returns disabled parsers (for names in history/library)
function GetAnyParserByID(ID)
	return parserTable[ID]
end

local parserGroup -- defined below (language group of a parser)

---The source an installed extension opens with, ignoring the Browse language filter. An extension with one source per
---language (EN, ES, FR, DE...) opens the one in `preferGroup` (the Extensions language chip), else in the Browse
---filter's language, else a multi-language one, else one in an active language (English first), else English; ties by ID,
---so it's always the same.
---@param extensionId string
---@param preferGroup string|nil language group ("pt", "es"...)
---@return table|nil
function GetParserOfExtension(extensionId, preferGroup)
	local browseGroup = SourceLangGroupOfCode(Settings and Settings.ParserLanguage or "DIF")
	local best, bestScore
	for _, v in pairs(parserTable) do
		if v.ExtensionID == extensionId and not v.Disabled then
			local g = v.Lang == "DIF" and "all" or parserGroup(v)
			local score = 0
			if preferGroup and g == preferGroup then
				score = 5
			elseif browseGroup and browseGroup ~= "all" and g == browseGroup then
				score = 4
			elseif g == "all" then
				score = 3
			elseif IsSourceLangEnabled(g) then
				score = g == "en" and 2.5 or 2 -- an active language (English first)
			elseif g == "en" then
				score = 1
			end
			if not best or score > bestScore or (score == bestScore and tostring(v.ID) < tostring(best.ID)) then
				best, bestScore = v, score
			end
		end
	end
	return best
end

---Language groups an installed extension really has sources in (e.g. en, es, fr, de)
---@return table|nil set of groups; nil when one of its sources is multi-language (or it has none)
function GetExtensionLangGroups(extensionId)
	local set, any = {}, false
	for _, v in pairs(parserTable) do
		if v.ExtensionID == extensionId and not v.Disabled then
			if v.Lang == "DIF" then
				return nil
			end
			any = true
			if v.Lang == "RAW" then
				set.ja, set.zh = true, true
			else
				set[parserGroup(v)] = true
			end
		end
	end
	return any and set or nil
end

---@return table every enabled parser, whatever the language filter
function GetAllParsers()
	local list = {}
	for _, v in pairs(parserTable) do
		if not v.Disabled then
			list[#list + 1] = v
		end
	end
	return list
end

---Source language groups the user can switch on/off (Extensions chips and Browse). "all" = multi-language sources.
SOURCE_LANG_GROUPS = {"en", "pt", "es", "fr", "de", "it", "ru", "ja", "zh", "other"}

---NOBORU/Otakio catalog code -> language group id
local CODE_GROUP = {ENG = "en", BRA = "pt", PRT = "pt", ESP = "es", FRA = "fr", DEU = "de", ITA = "it", RUS = "ru", JAP = "ja", CHN = "zh", DIF = "all"}

---Language group of a Mihon/ISO code ("pt-BR" -> "pt", "all" -> "all", unknown -> "other")
function SourceLangGroupOfIso(iso)
	return CODE_GROUP[Engines.toParserLang(iso or "all")] or "other"
end

---@return boolean whether sources of this language group are shown (no choice made = every language)
function IsSourceLangEnabled(group)
	local set = Settings.ExtLanguages
	if group == "all" or type(set) ~= "table" or next(set) == nil then
		return true
	end
	return set[group] == true
end

---@return boolean whether an extension has a source in an active language: its "lang", or for a multi-language one
---("all") that lists its languages ("langs": {"en", "es"...}), any of those
function IsExtensionLangEnabled(lang, langs)
	local g = SourceLangGroupOfIso(lang or "all")
	if g == "all" and type(langs) == "table" and #langs > 0 then
		for _, l in ipairs(langs) do
			local lg = SourceLangGroupOfIso(l)
			if lg == "all" or IsSourceLangEnabled(lg) then
				return true
			end
		end
		return false
	end
	return IsSourceLangEnabled(g)
end

parserGroup = function(v)
	return v.IsoLang and SourceLangGroupOfIso(v.IsoLang) or CODE_GROUP[v.Lang] or "other"
end

---Language group of a Browse filter code ("BRA"/"PRT" -> "pt", "DIF" -> "all", other codes -> "other")
function SourceLangGroupOfCode(code)
	return CODE_GROUP[code] or "other"
end

local function parserLangEnabled(v)
	if v.Lang == "RAW" then
		return IsSourceLangEnabled("ja") or IsSourceLangEnabled("zh")
	end
	return IsSourceLangEnabled(parserGroup(v))
end

---Browse filter code of each language group (Portuguese covers both pt-BR "BRA" and pt "PRT" sources)
local GROUP_CODE = {en = "ENG", pt = "PRT", es = "ESP", fr = "FRA", de = "DEU", it = "ITA", ru = "RUS", ja = "JAP", zh = "CHN"}

---Browse filter code -> the one code its group uses ("BRA" -> "PRT"); codes outside the groups stay as they are
local function browseCode(code)
	local g = CODE_GROUP[code]
	return g and GROUP_CODE[g] or code
end

---@return boolean whether a source shows under the Browse language filter `code`
local function matchesBrowseLang(v, code)
	if code == "DIF" or v.Lang == "DIF" then
		return true
	end
	if v.Lang == "RAW" then
		return code == "CHN" or code == "JAP"
	end
	local g = CODE_GROUP[code]
	if g and g ~= "all" then
		return parserGroup(v) == g
	end
	return v.Lang == code
end

-- Browse filter -> content languages a multi-language source should ask for (first = preferred)
local BROWSE_ISOS = {
	ENG = {"en"}, PRT = {"pt-br", "pt", "en"}, ESP = {"es-la", "es", "en"}, FRA = {"fr", "en"}, DEU = {"de", "en"},
	ITA = {"it", "en"}, RUS = {"ru", "en"}, JAP = {"ja", "en"}, CHN = {"zh", "zh-hk", "en"}
}

---@return table|nil ISO codes of the Browse language filter (nil = all languages): multi-language extensions use it
---to list content in the chosen language
function BrowseLanguageIsos()
	local list = BROWSE_ISOS[browseCode(Settings.ParserLanguage or "DIF")]
	if not list then
		return nil
	end
	local copy = {}
	for i, l in ipairs(list) do
		copy[i] = l
	end
	return copy
end

---@return table
---Gives Parser List
function GetParserList()
	if not is_parsers_list_updated then
		return cachedList
	end
	is_parsers_list_updated = false
	ValidParserLanguage()
	is_parsers_list_updated = false
	local list = {}
	for _, v in pairs(parserTable) do
		if (Settings.NSFW and v.NSFW or not v.NSFW) and not v.Disabled and parserLangEnabled(v) and matchesBrowseLang(v, Settings.ParserLanguage or "DIF") then
			list[#list + 1] = v
		end
	end
	cachedList = list
	-- pinned first, then grouped by language (English, Portuguese, Spanish, multi), then name
	local LANG_ORDER = {ENG = 1, BRA = 2, PRT = 2, ESP = 3, DIF = 4}
	table.sort(
		list,
		function(a, b)
			local fa, fb = Settings.FavouriteParsers[a.ID] == true, Settings.FavouriteParsers[b.ID] == true
			if fa ~= fb then
				return fa
			end
			local la, lb = LANG_ORDER[a.Lang] or 5, LANG_ORDER[b.Lang] or 5
			if la ~= lb then
				return la < lb
			end
			return string.upper(a.Name or a.ID) < string.upper(b.Name or b.ID)
		end
	)
	return list
end

---Languages the Browse language filter cycles through, with "DIF" (all) first:
---  * languages chosen in More > Extensions > Source languages: each active language, even without a source of its
---    own (multi-language sources serve it), plus the codes of installed sources in "other" languages;
---  * no choice made: the languages of the installed sources.
function GetParserLanguages()
	local t = {}
	local set = Settings.ExtLanguages
	local chosen = type(set) == "table" and next(set) ~= nil
	local list = {"DIF"}
	if chosen then
		for _, g in ipairs(SOURCE_LANG_GROUPS) do
			if set[g] and GROUP_CODE[g] then
				list[#list + 1] = GROUP_CODE[g]
			end
		end
	end
	for _, v in pairs(parserTable) do
		if not v.Disabled and parserLangEnabled(v) and (Settings.NSFW or not v.NSFW) then
			if v.Lang == "RAW" then
				if not chosen then
					t["CHN"], t["JAP"] = true, true
				end
			elseif v.Lang ~= "DIF" and (not chosen or parserGroup(v) == "other") then
				t[browseCode(v.Lang)] = true
			end
		end
	end
	local extra = {}
	for k, _ in pairs(t) do
		extra[#extra + 1] = k
	end
	table.sort(extra)
	for _, k in ipairs(extra) do
		list[#list + 1] = k
	end
	return list
end

---The Browse language filter, back to "all" when its language is no longer active (or has no source left)
function ValidParserLanguage()
	local current = browseCode(Settings.ParserLanguage or "DIF")
	if current ~= Settings.ParserLanguage then
		Settings.ParserLanguage = current -- saved "BRA" (Portuguese (Brazil)) is now "PRT", which covers both
		is_parsers_list_updated = true
	end
	for _, l in ipairs(GetParserLanguages()) do
		if l == current then
			return current
		end
	end
	Settings.ParserLanguage = "DIF"
	is_parsers_list_updated = true
	return "DIF"
end

---Sets update flag to `true`, for regenerating parsers list
function ChangeNSFW()
	is_parsers_list_updated = true
end

---Deletes all parsers and their files
function ClearParsers()
	if doesDirExist("ux0:data/otakio/parsers") then
		local list = listDirectory("ux0:/data/otakio/parsers") or {}
		for i = 1, #list do
			local v = list[i]
			if not v.directory then
				deleteFile("ux0:data/otakio/parsers/" .. v.name)
			end
		end
	end
	--[[
    parserTable = {}
    cachedList = {}]]
	for _, v in pairs(parserTable) do
		v.Disabled = true
	end
	is_parsers_list_updated = true
end
