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

---First enabled parser created by an installed extension, ignoring the Browse language filter
---@param extensionId string
---@return table|nil
function GetParserOfExtension(extensionId)
	for _, v in pairs(parserTable) do
		if v.ExtensionID == extensionId and not v.Disabled then
			return v
		end
	end
	return nil
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

local function parserLangEnabled(v)
	if v.Lang == "RAW" then
		return IsSourceLangEnabled("ja") or IsSourceLangEnabled("zh")
	end
	local group = v.IsoLang and SourceLangGroupOfIso(v.IsoLang) or CODE_GROUP[v.Lang] or "other"
	return IsSourceLangEnabled(group)
end

---@return table
---Gives Parser List
function GetParserList()
	if not is_parsers_list_updated then
		return cachedList
	end
	is_parsers_list_updated = false
	local list = {}
	for _, v in pairs(parserTable) do
		if (Settings.NSFW and v.NSFW or not v.NSFW) and not v.Disabled and parserLangEnabled(v) and (Settings.ParserLanguage == "DIF" or v.Lang == Settings.ParserLanguage or v.Lang == "DIF" or ((Settings.ParserLanguage == "CHN" or Settings.ParserLanguage == "JAP") and v.Lang == "RAW")) then
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

function GetParserLanguages()
	local t = {}
	for _, v in pairs(parserTable) do
		if not v.Disabled then
			t[v.Lang] = true
		end
	end
	t["DIF"] = nil
	if t["RAW"] then
		t["CHN"] = true
		t["JAP"] = true
	end
	t["RAW"] = nil
	local newLanguageList = {}
	for k, _ in pairs(t) do
		newLanguageList[#newLanguageList + 1] = k
	end
	table.sort(
		newLanguageList,
		function(a, b)
			return a < b
		end
	)
	table.insert(newLanguageList, 1, "DIF")
	return newLanguageList
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
