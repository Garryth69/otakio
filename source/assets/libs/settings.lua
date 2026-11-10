Settings = {
	Language = "Default",
	Theme = "Otakio",
	Version = Config.VERSION,
	NSFW = false,
	Orientation = "Horizontal",
	ZoomReader = "Smart",
	DoubleTapReader = true,
	PressEdgesToChangePage = false,
	KeyType = "EU",
	ReaderDirection = "RIGHT",
	HideInOffline = true,
	SkipFontLoad = false,
	ParserLanguage = "DIF",
	LibrarySorting = "Date added",
	ChapterSorting = "1->N",
	RefreshLibAtStart = false,
	ChangingPageButtons = "LR",
	LeftStickDeadZone = 30,
	LeftStickSensitivity = 1,
	RightStickDeadZone = 30,
	RightStickSensitivity = 1,
	SilentDownloads = false,
	UseProxy = false,
	ProxyIP = "192.168.0.1",
	ProxyPort = "8080",
	UseProxyAuth = false,
	ProxyAuth = "login:password",
	SkipCacheChapterChecking = true,
	ConnectionTime = 10,
	FavouriteParsers = {},
	SaveDataPath = "ux0",
	LoadSummary = true,
	-- Otakio
	ImageProxy = "Auto",
	DataSaver = false,
	PreloadPages = 3,
	SaveImageFormat = "Original",
	AutoUpdateExtensions = false,
	CheckExtUpdatesAtStart = true,
	AppAutoUpdate = true,
	AutoDownloadNew = false,
	Incognito = false,
	LibraryFilter = "All",
	Categories = {},
	ExtLanguages = {},
	ShowFPS = false,
	ReaderLook = {} -- page colors: readersheet.lua (ReaderLook.get completes it)
}

NSFWLock = System.doesFileExist("ux0:data/otakio/.lock")

local settingsDefaults = table.clone(Settings)

DeadZoneValues = { 20, 30, 40, 50, 90 }
SensitivityValues = { 0.25, 0.50, 0.75, 1, 1.25, 1.5, 1.75 }

local settings = Settings

local cross = SCE_CTRL_CROSS
local circle = SCE_CTRL_CIRCLE
local writeFile = System.writeFile
local closeFile = System.closeFile
local deleteFile = System.deleteFile
local openFile = System.openFile
local readFile = System.readFile
local sizeFile = System.sizeFile
local doesFileExist = System.doesFileExist
local doesDirExist = System.doesDirExist
local createDirectory = System.createDirectory

local is_app_updating = false

---@return boolean
---Gives true if app is updating
function settings.isAppUpdating()
	return is_app_updating
end

local copyFile = CopyFile

---Sets colors from Themes[Settings.Theme] to their values
local function setTheme(name)
	if Themes[name] then
		for k, v in pairs(Themes[name]) do
			_G[k] = v
		end
	end
end

function Settings.toggleFavouriteParser(Parser)
	if Parser and Parser.ID then
		settings.FavouriteParsers[Parser.ID] = not settings.FavouriteParsers[Parser.ID] and true or nil
		ChangeNSFW()
		Settings.save()
	end
end

function Settings.getSaveDrivePath()
	if settings.SaveDataPath == "uma0" and not doesDirExist("uma0:data/otakio") then
		return "ux0"
	else
		return settings.SaveDataPath
	end
end

---Table of all available options
local settingsListTree = {
	"Language",
	"ChangeUI",
	"Library",
	"Catalogs",
	"ExtensionsSettings",
	"Reader",
	"Network",
	"Data",
	"Other",
	"Controls",
	"About",
	Library = {
		"LibrarySorting",
		"LibraryFilter",
		"EditCategories",
		"RefreshLibAtStart",
		"AutoDownloadNew"
	},
	Catalogs = {
		"ShowNSFW",
		"SourceLanguages",
		"HideInOffline",
		"PreferredCatalogLanguage"
	},
	ExtensionsSettings = {
		"SourceLanguages",
		"ExtensionRepos",
		"CheckExtUpdatesAtStart",
		"AutoUpdateExtensions",
		"ImportNoboruParsers"
	},
	Reader = {
		"ReaderOrientation",
		"ZoomReader",
		"ReaderDirection",
		"DoubleTapReader",
		"PressEdgesToChangePage",
		"PreloadPages",
		"Incognito",
		"SaveImageFormat"
	},
	Network = {
		"ConnectionTime",
		"ImageProxy",
		"DataSaver",
		"Proxy"
	},
	Data = {
		"CreateBackup",
		"RestoreBackup",
		"ImportNoboruData",
		"SaveDataPath",
		"ClearLibrary",
		"ClearCache",
		"ClearAllCache",
		"ClearChapters",
		"ResetAllSettings"
	},
	Other = {
		"SkipFontLoading",
		"ChapterSorting",
		"SilentDownloads",
		"SkipCacheChapterChecking",
		"LoadSummary",
		"ShowFPS"
	},
	About = {
		"ShowVersion",
		"AppAutoUpdate",
		"CheckAppUpdate"
	},
	Controls = {
		"SwapXO",
		"ChangingPageButtons",
		"LeftStickDeadZone",
		"LeftStickSensitivity",
		"RightStickDeadZone",
		"RightStickSensitivity"
	}
}

-- importing from NOBORU only makes sense when its data folder is on the memory card
if not doesDirExist("ux0:data/noboru") then
	for _, node in ipairs({settingsListTree.ExtensionsSettings, settingsListTree.Data}) do
		for i = #node, 1, -1 do
			if node[i] == "ImportNoboruParsers" or node[i] == "ImportNoboruData" then
				table.remove(node, i)
			end
		end
	end
end

---Table of current options
local settingsListCurrentNode = settingsListTree
local settingsListCurrentPath = {}
local settingsListCurrentNodeName = "MainSettingsMenu"
local settingsListCurrentPathNames = {}

---@param source table
---@param settingName string
---@param values table
---Sets `settings[setting_name]` value to `source[setting_name]` if value is in `values` table
---
---Example:
---
---`setSetting(new_settings, "SpeedOfScrolling", {1,5,10}) ->`
---
---`sets Settings.SpeedOfScrolling to new_settings.SpeedOfScrolling if it is 1, 5 or 10 else sets to nil`
local function setSetting(source, settingName, values)
	local newValue = source[settingName]
	if newValue == nil then
		return
	end
	if #values == 0 then
		settings[settingName] = newValue
	end
	for _, v in pairs(values) do
		if newValue == v then
			settings[settingName] = newValue
			return
		end
	end
	if values[newValue] then
		settings[settingName] = newValue
	end
end

local SETTINGS_SAVE_PATH = "ux0:data/otakio/settings.ini"

---Loads settings from `ux0:data/otakio/settings.ini`
function settings.load()
	if doesFileExist(SETTINGS_SAVE_PATH) then
		local fh = openFile(SETTINGS_SAVE_PATH, FREAD)
		local suc = load("local " .. readFile(fh, sizeFile(fh)) .. " return Settings")
		if suc then
			local new = suc()
			if type(new) == "table" then
				setSetting(new, "Language", Language)
				if Language[settings.Language] == nil then
					settings.Language = "Default"
				end
				if NSFWLock then
					setSetting(new, "NSFW", { false })
					if settingsListTree and settingsListTree.Catalogs and settingsListTree.Catalogs[1] then
						table.remove(settingsListTree.Catalogs, 1)
						for k, v in pairs(Language) do
							Language[k].SETTINGS_DESCRIPTION.Catalogs = nil
						end
					end
				else
					setSetting(new, "NSFW", { true, false })
				end
				setSetting(new, "SkipFontLoad", { true, false })
				setSetting(new, "Orientation", { "Horizontal", "Vertical" })
				setSetting(new, "ZoomReader", { "Width", "Height", "Smart" })
				setSetting(new, "ReaderDirection", { "LEFT", "RIGHT", "DOWN", "WEBTOON" })
				setSetting(new, "KeyType", { "JP", "EU" })
				setSetting(new, "HideInOffline", { true, false })
				setSetting(new, "DoubleTapReader", { true, false })
				setSetting(new, "Theme", Themes)
				setSetting(new, "ChapterSorting", { "1->N", "N->1" })
				setSetting(new, "RefreshLibAtStart", { true, false })
				setSetting(new, "ChangingPageButtons", { "DPAD", "LR" })
				setSetting(new, "LeftStickDeadZone", DeadZoneValues)
				setSetting(new, "LeftStickSensitivity", SensitivityValues)
				setSetting(new, "RightStickDeadZone", DeadZoneValues)
				setSetting(new, "RightStickSensitivity", SensitivityValues)
				setSetting(new, "SilentDownloads", { true, false })
				setSetting(new, "UseProxy", { true, false })
				setSetting(new, "ProxyIP", {})
				setSetting(new, "ProxyPort", {})
				setSetting(new, "UseProxyAuth", { true, false })
				setSetting(new, "ProxyAuth", {})
				setSetting(new, "SkipCacheChapterChecking", { true, false })
				setSetting(new, "ConnectionTime", {})
				setSetting(new, "FavouriteParsers", {})
				setSetting(new, "SaveDataPath", { "ux0", "uma0" })
				setSetting(new, "PressEdgesToChangePage", { true, false })
				setSetting(new, "LoadSummary", { true, false })
				setSetting(new, "LibrarySorting", Database.SORT_MODES)
				setSetting(new, "LibraryFilter", Database.FILTERS)
				setSetting(new, "ImageProxy", { "Auto", "Off" })
				setSetting(new, "DataSaver", { true, false })
				setSetting(new, "PreloadPages", { 0, 1, 2, 3, 5, 8 })
				setSetting(new, "SaveImageFormat", { "Original", "PNG", "JPEG", "WebP" })
				setSetting(new, "AutoUpdateExtensions", { true, false })
				setSetting(new, "CheckExtUpdatesAtStart", { true, false })
				setSetting(new, "AppAutoUpdate", { true, false })
				setSetting(new, "AutoDownloadNew", { true, false })
				setSetting(new, "Incognito", { true, false })
				setSetting(new, "ShowFPS", { true, false })
				if type(new.ExtLanguages) == "table" then
					local set = {}
					for _, id in ipairs(SOURCE_LANG_GROUPS) do
						if new.ExtLanguages[id] == true then
							set[id] = true
						end
					end
					settings.ExtLanguages = set
				end
				-- the Browse language filter is checked after the chosen source languages are loaded (it depends on them);
				-- "BRA" saved by older versions is now "PRT" (Portuguese covers pt-BR and pt sources)
				if new.ParserLanguage == "BRA" then
					new.ParserLanguage = "PRT"
				end
				setSetting(new, "ParserLanguage", GetParserLanguages())
				if type(new.Categories) == "table" then
					settings.Categories = new.Categories
				end
				if type(new.ReaderLook) == "table" then
					settings.ReaderLook = new.ReaderLook -- checked by ReaderLook.get
				end
			end
		end
		closeFile(fh)
	end
	settings.save()
	GenPanels()
	Network.setConnectionTime(settings.ConnectionTime or 10)
	SCE_CTRL_CROSS = settings.KeyType == "JP" and circle or cross
	SCE_CTRL_CIRCLE = settings.KeyType == "JP" and cross or circle
	SCE_CTRL_RIGHTPAGE = settings.ChangingPageButtons == "DPAD" and SCE_CTRL_RIGHT or SCE_CTRL_RTRIGGER
	SCE_CTRL_LEFTPAGE = settings.ChangingPageButtons == "DPAD" and SCE_CTRL_LEFT or SCE_CTRL_LTRIGGER
	SCE_LEFT_STICK_DEADZONE = settings.LeftStickDeadZone
	SCE_LEFT_STICK_SENSITIVITY = settings.LeftStickSensitivity
	SCE_RIGHT_STICK_DEADZONE = settings.RightStickDeadZone
	SCE_RIGHT_STICK_SENSITIVITY = settings.RightStickSensitivity
	if not Themes[settings.Theme] then
		settings.Theme = "Otakio"
	end
	setTheme(settings.Theme)
	FrameStats.show = settings.ShowFPS
end

---Saves settings in `ux0:data/otakio/settings.ini`
function settings.save()
	if doesFileExist(SETTINGS_SAVE_PATH) then
		deleteFile(SETTINGS_SAVE_PATH)
	end
	local fh = openFile(SETTINGS_SAVE_PATH, FCREATE)
	local copiedSettings = {}
	for k, v in pairs(settings) do
		if type(v) ~= "function" and k ~= "Version" then
			copiedSettings[k] = v
		end
	end
	local saveSettingsContent = "Settings = " .. table.serialize(copiedSettings)
	writeFile(fh, saveSettingsContent, #saveSettingsContent)
	closeFile(fh)
end

---@return table
---Return list of available options
function settings.list()
	return settingsListCurrentNode
end

---@param mode string
---@return boolean
---Checks if setting is submenu
function settings.isTab(mode)
	return settingsListCurrentNode[mode] ~= nil
end

---@param mode string
---Sets settings menu as submenu `mode`
function settings.setTab(mode)
	if settingsListCurrentNode[mode] then
		settingsListCurrentPath[#settingsListCurrentPath + 1] = settingsListCurrentNode
		settingsListCurrentNode = settingsListCurrentNode[mode]
		settingsListCurrentPathNames[#settingsListCurrentPathNames + 1] = settingsListCurrentNodeName
		settingsListCurrentNodeName = mode
	end
end

---@return boolean
---Checks if settings not in main settings menu (subsettings screen)
function settings.inTab()
	return #settingsListCurrentPath > 0
end

---@return string
---Returns tab name of settings that user is in
function settings.getTab()
	return settingsListCurrentNodeName
end

---Throws in main settings menu
function settings.back()
	if #settingsListCurrentPath > 0 then
		settingsListCurrentNode = settingsListCurrentPath[#settingsListCurrentPath]
		settingsListCurrentPath[#settingsListCurrentPath] = nil
		settingsListCurrentNodeName = settingsListCurrentPathNames[#settingsListCurrentPathNames]
		settingsListCurrentPathNames[#settingsListCurrentPathNames] = nil
	end
end

---Applies a theme by name (used by the first-run setup too)
function Settings.applyTheme(name)
	setTheme(name)
end

---"EU" = X confirms, "JP" = O confirms
function Settings.setKeyType(v)
	settings.KeyType = v
	SCE_CTRL_CROSS = v == "JP" and circle or cross
	SCE_CTRL_CIRCLE = v == "JP" and cross or circle
end

---Checklist of the source languages kept active in Extensions and Browse (none ticked = all languages)
function Settings.chooseSourceLanguages(onDone)
	local LS = Language[settings.Language]
	local items = {}
	for _, g in ipairs(Screens.EXTENSIONS.langGroups()) do
		local set = settings.ExtLanguages
		items[#items + 1] = {label = LS.OTAKIO[g.label] or Language.English.OTAKIO[g.label] or g.id, value = g.id,
			checked = type(set) == "table" and set[g.id] == true}
	end
	Dialog.checklist(LS.SETTINGS.SourceLanguages or Language.English.SETTINGS.SourceLanguages, items, function(result)
		local set = {}
		for _, item in ipairs(result) do
			if item.checked then
				set[item.value] = true
			end
		end
		settings.ExtLanguages = set
		Screens.EXTENSIONS.languagesChanged()
		settings.save()
		if onDone then
			onDone()
		end
	end)
end

---Short text of the active source languages ("EN, PT" or "All")
function Settings.sourceLanguagesText()
	local LS = Language[settings.Language]
	local out = {}
	for _, id in ipairs(SOURCE_LANG_GROUPS) do
		if type(settings.ExtLanguages) == "table" and settings.ExtLanguages[id] then
			out[#out + 1] = string.upper(id)
		end
	end
	if #out == 0 then
		return LS.OTAKIO.ALL or "All"
	end
	return table.concat(out, ", ")
end

---Table with Option Names and their Functions
SettingsFunctions = {
	SourceLanguages = function()
		Settings.chooseSourceLanguages()
	end,
	Language = function()
		local codes = {}
		for k in pairs(Language) do
			if k ~= "Default" and LanguageNames.English[k] then
				codes[#codes + 1] = k
			end
		end
		table.sort(codes)
		table.insert(codes, 1, "Default")
		local items, sel = {}, 1
		for i, k in ipairs(codes) do
			local native = LanguageNames[k] and LanguageNames[k][k] or LanguageNames.English[k]
			items[i] = {label = native, sub = native ~= LanguageNames.English[k] and LanguageNames.English[k] or nil, value = k}
			if k == settings.Language then
				sel = i
			end
		end
		Dialog.choice(Language[settings.Language].SETTINGS.Language, items, sel, function(item)
			settings.Language = item.value
			GenPanels()
			settings.save()
		end)
	end,
	SkipFontLoading = function()
		settings.SkipFontLoad = not settings.SkipFontLoad
	end,
	ChangeUI = function()
		local items, sel = {}, 1
		for i, name in ipairs(GetThemes()) do
			local t = Themes[name]
			items[i] = {label = Language[settings.Language].THEME[name] or name, value = name,
				swatches = {t.COLOR_BACK, t.COLOR_SURFACE2, t.COLOR_ACCENT}}
			if name == settings.Theme then
				sel = i
			end
		end
		-- the whole app previews the theme under the cursor; Circle goes back to the one in use
		Dialog.choice(Language[settings.Language].SETTINGS.ChangeUI, items, sel, function(item)
			settings.Theme = item.value
			setTheme(settings.Theme)
			settings.save()
		end, {
			onMove = function(item)
				setTheme(item.value)
			end,
			onCancel = function()
				setTheme(settings.Theme)
			end
		})
	end,
	ShowNSFW = function()
		ChangeNSFW()
		settings.NSFW = not settings.NSFW
	end,
	HideInOffline = function()
		settings.HideInOffline = not settings.HideInOffline
	end,
	ReaderOrientation = function()
		settings.Orientation = table.next(settings.Orientation, { "Horizontal", "Vertical" })
	end,
	ZoomReader = function()
		settings.ZoomReader = table.next(settings.ZoomReader, { "Width", "Height", "Smart" })
	end,
	ReaderDirection = function()
		settings.ReaderDirection = table.next(settings.ReaderDirection, { "LEFT", "RIGHT", "DOWN", "WEBTOON" })
	end,
	DoubleTapReader = function()
		settings.DoubleTapReader = not settings.DoubleTapReader
	end,
	ClearLibrary = function()
		Database.clear()
		Notifications.push(Language[settings.Language].NOTIFICATIONS.LIBRARY_CLEARED)
	end,
	ClearCache = function()
		Cache.clear()
		Notifications.push(Language[settings.Language].NOTIFICATIONS.CACHE_CLEARED)
	end,
	ClearAllCache = function()
		Cache.clear("all")
		Notifications.push(Language[settings.Language].NOTIFICATIONS.CACHE_CLEARED)
	end,
	ClearChapters = function()
		ChapterSaver.clear()
	end,
	SwapXO = function()
		Settings.setKeyType(table.next(settings.KeyType, { "JP", "EU" }))
	end,
	PreferredCatalogLanguage = function()
		settings.ParserLanguage = table.next(settings.ParserLanguage, GetParserLanguages())
		ChangeNSFW()
	end,
	LibrarySorting = function()
		settings.LibrarySorting = table.next(settings.LibrarySorting, Database.SORT_MODES)
		Database.touch()
	end,
	LibraryFilter = function()
		settings.LibraryFilter = table.next(settings.LibraryFilter or "All", Database.FILTERS)
		Database.touch()
	end,
	EditCategories = function()
		CategoryEditor.open()
	end,
	AutoDownloadNew = function()
		settings.AutoDownloadNew = not settings.AutoDownloadNew
	end,
	ExtensionRepos = function()
		Screens.EXTENSIONS.repoMenu()
	end,
	CheckExtUpdatesAtStart = function()
		settings.CheckExtUpdatesAtStart = not settings.CheckExtUpdatesAtStart
	end,
	AppAutoUpdate = function()
		settings.AppAutoUpdate = not settings.AppAutoUpdate
	end,
	AutoUpdateExtensions = function()
		settings.AutoUpdateExtensions = not settings.AutoUpdateExtensions
	end,
	ImportNoboruParsers = function()
		local n = Extensions.importNoboruParsers()
		Notifications.push(string.format(Language[settings.Language].OTAKIO.IMPORTED_N, n))
	end,
	PreloadPages = function()
		settings.PreloadPages = table.next(settings.PreloadPages or 3, { 0, 1, 2, 3, 5, 8 })
	end,
	Incognito = function()
		settings.Incognito = not settings.Incognito
	end,
	SaveImageFormat = function()
		settings.SaveImageFormat = table.next(settings.SaveImageFormat or "Original", { "Original", "PNG", "JPEG", "WebP" })
	end,
	ImageProxy = function()
		settings.ImageProxy = table.next(settings.ImageProxy or "Auto", { "Auto", "Off" })
	end,
	DataSaver = function()
		settings.DataSaver = not settings.DataSaver
	end,
	ShowFPS = function()
		settings.ShowFPS = not settings.ShowFPS
		FrameStats.show = settings.ShowFPS
	end,
	CreateBackup = function()
		Backup.create()
	end,
	CheckAppUpdate = function()
		AppUpdate.menuAction()
	end,
	RestoreBackup = function()
		Backup.restoreMenu()
	end,
	ImportNoboruData = function()
		Backup.importNoboru()
	end,
	ChapterSorting = function()
		settings.ChapterSorting = table.next(settings.ChapterSorting, { "1->N", "N->1" })
	end,
	RefreshLibAtStart = function()
		settings.RefreshLibAtStart = table.next(settings.RefreshLibAtStart, { true, false })
	end,
	ChangingPageButtons = function()
		settings.ChangingPageButtons = table.next(settings.ChangingPageButtons, { "DPAD", "LR" })
		SCE_CTRL_RIGHTPAGE = settings.ChangingPageButtons == "DPAD" and SCE_CTRL_RIGHT or SCE_CTRL_RTRIGGER
		SCE_CTRL_LEFTPAGE = settings.ChangingPageButtons == "DPAD" and SCE_CTRL_LEFT or SCE_CTRL_LTRIGGER
	end,
	LeftStickDeadZone = function()
		settings.LeftStickDeadZone = table.next(settings.LeftStickDeadZone, DeadZoneValues)
		SCE_LEFT_STICK_DEADZONE = settings.LeftStickDeadZone
	end,
	LeftStickSensitivity = function()
		settings.LeftStickSensitivity = table.next(settings.LeftStickSensitivity, SensitivityValues)
		SCE_LEFT_STICK_SENSITIVITY = settings.LeftStickSensitivity
	end,
	RightStickDeadZone = function()
		settings.RightStickDeadZone = table.next(settings.RightStickDeadZone, DeadZoneValues)
		SCE_RIGHT_STICK_DEADZONE = settings.RightStickDeadZone
	end,
	RightStickSensitivity = function()
		settings.RightStickSensitivity = table.next(settings.RightStickSensitivity, SensitivityValues)
		SCE_RIGHT_STICK_SENSITIVITY = settings.RightStickSensitivity
	end,
	ResetAllSettings = function()
		for k, v in pairs(settingsDefaults) do
			if k ~= "FavouriteParsers" and k ~= "Language" and k ~= "Theme" and k ~= "Categories" then
				settings[k] = v
			end
		end
		Notifications.push(Language[Settings.Language].NOTIFICATIONS.SETTINGS_RESET)
	end,
	SilentDownloads = function()
		settings.SilentDownloads = not settings.SilentDownloads
	end,
	Proxy = function(selected)
		local LS = Language[settings.Language]
		local O = LS.OTAKIO
		local items = {
			{label = LS.SETTINGS.UseProxy, sub = settings.UseProxy and O.YES or O.NO, value = "use"},
			{label = O.PROXY_ADDRESS, sub = settings.ProxyIP .. ":" .. settings.ProxyPort, value = "address"},
			{label = LS.SETTINGS.UseProxyAuth, sub = settings.UseProxyAuth and O.YES or O.NO, value = "useauth"},
			{label = LS.SETTINGS.ProxyAuth, sub = settings.ProxyAuth, value = "auth"}
		}
		Dialog.menu(LS.SETTINGS.Proxy, items, function(item, index)
			if item.value == "use" then
				settings.UseProxy = not settings.UseProxy
			elseif item.value == "address" then
				local value = TextInput(O.PROXY_ADDRESS, settings.ProxyIP .. ":" .. settings.ProxyPort, 64, TYPE_LATIN)
				if value then
					local host, port = value:gsub("%s", ""):match("^([^:]+):?(%d*)$")
					if host then
						settings.ProxyIP = host
						settings.ProxyPort = port ~= "" and port or settings.ProxyPort
					end
				end
			elseif item.value == "useauth" then
				settings.UseProxyAuth = not settings.UseProxyAuth
			elseif item.value == "auth" then
				local value = TextInput(LS.SETTINGS.ProxyAuth, settings.ProxyAuth, 128, TYPE_LATIN)
				if value then
					settings.ProxyAuth = value
				end
			end
			settings.save()
			SettingsFunctions.Proxy(index)
		end, selected)
	end,
	SkipCacheChapterChecking = function()
		settings.SkipCacheChapterChecking = not settings.SkipCacheChapterChecking
	end,
	ConnectionTime = function()
		Keyboard.show(Language[settings.Language].SETTINGS.InputValue, settings.ConnectionTime, 128, TYPE_NUMBER, MODE_TEXT, OPT_NO_AUTOCAP)
		while Keyboard.getState() == RUNNING do
			Graphics.initBlend()
			Screen.clear()
			Graphics.termBlend()
			Screen.waitVblankStart()
			Screen.flip()
		end
		if Keyboard.getState() == FINISHED then
			local new_time = tonumber(Keyboard.getInput())
			if new_time and new_time > 0 then
				settings.ConnectionTime = Keyboard.getInput()
				Network.setConnectionTime(settings.ConnectionTime or 10)
			end
		end
		Keyboard.clear()
	end,
	PressEdgesToChangePage = function()
		settings.PressEdgesToChangePage = not settings.PressEdgesToChangePage
	end,
	SaveDataPath = function()
		settings.SaveDataPath = table.next(settings.SaveDataPath, { "ux0", "uma0" })
	end,
	LoadSummary = function()
		settings.LoadSummary = not settings.LoadSummary
	end
}
