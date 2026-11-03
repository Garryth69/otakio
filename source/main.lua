loadlib("perf")
loadlib("config")
loadlib("image")
local logo = Image:new(Graphics.loadImage("app0:assets/images/logo.png"))

Graphics.initBlend()
Screen.clear(Color.new(16, 17, 26))
if logo then
	Graphics.drawImage(480 - 666 / 2, 272 - 172 / 2, logo.e)
end
Graphics.termBlend()

local doesDirExist = System.doesDirExist
local listDirectory = System.listDirectory
local createDirectory = System.createDirectory
loadlib("utils")
loadlib("fs")
loadlib("json")
loadlib("html")
loadlib("globals")
loadlib("ui")
loadlib("customsettings")
loadlib("customcovers")
loadlib("catalogmodes")
loadlib("conmessage")
loadlib("selector")
loadlib("console")
loadlib("language")
loadlib("themes")
loadlib("loading")
loadlib("net")
loadlib("http")
loadlib("parserhandler")
loadlib("settings")
loadlib("database")
loadlib("parser")
loadlib("engines")
loadlib("engines_extra")
loadlib("extensions")
loadlib("sourcestatus")
loadlib("appupdate")
loadlib("updates")
loadlib("dialog")
loadlib("catalogs")
loadlib("screens")
loadlib("backup")
loadlib("extra")
loadlib("details")
loadlib("menu")
loadlib("panel")
loadlib("notifications")
loadlib("debug")
loadlib("chsaver")
loadlib("cache")
loadlib("reader")
loadlib("import")

-- Sandbox: extensions don't get raw access to the OS / file system
os = nil
debug = nil
package = nil
require = nil
RemoveDirectory = nil
CopyFile = nil

System = {
	getLanguage = System.getLanguage,
	extractZipAsync = System.extractZipAsync,
	getAsyncState = System.getAsyncState,
	getPictureResolution = System.getPictureResolution,
	extractFromZipAsync = System.extractFromZipAsync
}

-- Extensions (Otakio repository format) + legacy NOBORU parsers folder
Extensions.loadInstalled()

local legacyPath = "ux0:data/otakio/parsers/"
if doesDirExist(legacyPath) then
	local files = listDirectory(legacyPath) or {}
	for i = 1, #files do
		local file = files[i]
		if not file.directory and file.name:find("%.lua$") then
			local suc, err = pcall(dofile, legacyPath .. file.name)
			if not suc then
				Console.error("Can't load " .. legacyPath .. file.name .. ":" .. err)
			end
		end
	end
else
	createDirectory("ux0:data/otakio/parsers")
end

local fonts = {
	FONT13,
	FONT16,
	FONT20,
	FONT26,
	BONT30,
	BONT16
}

local FIRST_RUN_FLAG = "ux0:data/otakio/.firstrun_v2"

local function preloadData()
	coroutine.yield("Loading settings")
	local suc, err = pcall(Settings.load, Settings)
	if not suc then
		Console.error(err)
	end
	pcall(ExtLog, "engine: " .. tostring(ENGINE_VERSION))
	if not Settings.SkipFontLoad then
		local loadFontString = '1234567890AaBbCcDdEeFf\nGgHhIiJjKkLlMmNnOoPpQqRr\nSsTtUuVvWwXxYyZzАаБб\nВвГгДдЕеЁёЖжЗзИиЙйКкЛлМм\nНнОоПпРрСсТтУуФфХхЦцЧчШшЩщ\nЫыЪъЬьЭэЮюЯя!@#$%^&*()\n_+-=[]"\\/.,{}:;\'|? №~<>`\r—…·›✓↓♥⚠\nÁáÀàÂâÃãÉéÊêÍíÓóÔôÕõÚúÇç'
		-- accents of the interface languages (French, German, Italian, Spanish)
		loadFontString = loadFontString .. '\nÈèËëÎîÏïÛûÙùŒœÄäÖöÜüßÑñ¿¡«»„“”•'
		for langName, _ in pairs(Language) do
			loadFontString = loadFontString .. (LanguageNames and LanguageNames[langName] and LanguageNames[langName][langName] or "")
		end
		for k, v in ipairs(fonts) do
			coroutine.yield("Loading fonts " .. k .. "/" .. #fonts)
			Font.print(v, 0, 0, loadFontString, COLOR_BLACK)
		end
	end
	coroutine.yield("Loading cache, checking existing data")
	suc, err = pcall(Cache.load)
	if not suc then
		Console.error(err)
	end
	coroutine.yield("Loading history")
	suc, err = pcall(Cache.loadHistory)
	if not suc then
		Console.error(err)
	end
	coroutine.yield("Loading library")
	suc, err = pcall(Database.load)
	if not suc then
		Console.error(err)
	end
	suc, err = pcall(Updates.load)
	if not suc then
		Console.error(err)
	end
	coroutine.yield("Checking saved chapters")
	suc, err = pcall(ChapterSaver.load)
	if not suc then
		Console.error(err)
	end
	coroutine.yield("Loading custom covers")
	suc, err = pcall(CustomCovers.load)
	if not suc then
		Console.error(err)
	end
	Menu.setMode("LIBRARY")
	Panel.show()
	coroutine.yield("Checking for updates")
	-- first run starts with no extensions: the user picks the sources in the Extensions tab
	if not FS.exists(FIRST_RUN_FLAG) then
		FS.write(FIRST_RUN_FLAG, Config.VERSION_NAME)
		Extensions.refresh(true)
	elseif Settings.CheckExtUpdatesAtStart then
		Extensions.refresh(true)
	end
	-- new Otakio release on GitHub? (silent when offline or up to date)
	AppUpdate.check(true)
end

Screen.flip()
Screen.waitVblankStart()

MENU = 0
READER = 1
AppMode = MENU

local is_touch_locked = false

local LoadingTimer = Timer.new()

local f = coroutine.create(preloadData)
while coroutine.status(f) ~= "dead" do
	Graphics.initBlend()
	Screen.clear(Color.new(16, 17, 26))
	local _, text, prog
	Timer.reset(LoadingTimer)
	repeat
		_, text, prog = coroutine.resume(f)
	until Timer.getTime(LoadingTimer) > 8 or coroutine.status(f) == "dead"
	if not _ then
		Console.error(text)
	end
	if text then
		Font.print(FONT16, 960 / 2 - Font.getTextWidth(FONT16, text) / 2, 272 + 172 / 2 + 10, text, Color.new(150, 152, 175))
	end
	if prog and not Settings.SkipCacheChapterChecking then
		Graphics.fillRect(150, 150 + 660, 272 + 172 / 2 + 42, 272 + 172 / 2 + 45, Color.new(60, 60, 80))
		Graphics.fillRect(150, 150 + 660 * prog, 272 + 172 / 2 + 42, 272 + 172 / 2 + 45, Color.new(150, 120, 255))
	end
	if logo then
		Graphics.drawImage(480 - 666 / 2, 272 - 172 / 2, logo.e)
	end
	Graphics.termBlend()
	Screen.flip()
end
Timer.destroy(LoadingTimer)

if Settings.RefreshLibAtStart then
	ParserManager.updateCounters()
end

local pad, oldPad = Controls.read()
local oldTouch, touch = {}, {}
local oldTouch2, touch2 = {}, {}

if Controls.check(pad, SCE_CTRL_SELECT) then
	Debug.upgradeDebugMenu()
end

local fade = 1

local function input()
	oldPad, pad = pad, Controls.read()
	oldTouch.x, oldTouch.y, oldTouch2.x, oldTouch2.y, touch.x, touch.y, touch2.x, touch2.y = touch.x, touch.y, touch2.x, touch2.y, Controls.readTouch()

	Debug.input()

	if ConnectMessage.isActive() then
		if touch.x or pad ~= 0 then
			oldPad = ConnectMessage.input(pad) or 0
		end
		pad = oldPad
		is_touch_locked = true
	end

	if touch2.x and AppMode ~= READER then
		is_touch_locked = true
	elseif not touch.x then
		is_touch_locked = false
	end

	if is_touch_locked then
		touch.x = nil
		touch.y = nil
		oldTouch.x = nil
		oldTouch.y = nil
		touch2.x = nil
		touch2.y = nil
		oldTouch2.x = nil
		oldTouch2.y = nil
	end

	if Keyboard.getState() ~= RUNNING then
		if Dialog.isOpen() then
			Dialog.input(oldPad, pad, oldTouch, touch)
		elseif AppMode == MENU then
			Menu.input(oldPad, pad, oldTouch, touch)
		elseif AppMode == READER then
			Reader.input(oldPad, pad, oldTouch, touch, oldTouch2, touch2)
		end
	end
end

local function update()
	UI.tick()
	Debug.update()
	if fade == 0 then
		Panel.update()
		Threads.update()
		ParserManager.update()
		ChapterSaver.update()
		Extensions.update()
		SourceStatus.update()
		AppUpdate.update()
		Backup.update()
		ConnectMessage.update()
	end
	if fade > 0 then
		fade = fade - fade / 6
		if fade < 1 / 254 then
			fade = 0
		end
	end
	if AppMode == MENU then
		Menu.update()
		if Details.getStatus() == "END" and CatalogModes.getStatus() == "END" then
			Panel.show()
		else
			Panel.hide()
		end
	elseif AppMode == READER then
		Reader.update()
		Panel.hide()
	end
	Dialog.update()
	Notifications.update()
end

local fpsTimer = Timer.new()
local fpsFrames = 0

local function draw()
	Graphics.initBlend()
	if AppMode == MENU then
		Menu.draw()
	elseif AppMode == READER then
		Reader.draw()
	end
	Loading.draw()
	if fade > 0 then
		Graphics.fillRect(0, 960, 0, 544, Color.new(16, 17, 26, 255 * fade))
		if logo then
			Graphics.drawImage(480 - 666 / 2, 272 - 172 / 2, logo.e, Color.new(255, 255, 255, 255 * fade))
		end
	elseif logo and logo.free then
		logo:free()
		logo = nil
	else
		ConnectMessage.draw()
	end
	Dialog.draw()
	Notifications.draw()
	Panel.draw()
	Debug.draw()
	Graphics.termBlend()
	Screen.flip()
	Screen.waitVblankStart()
	fpsFrames = fpsFrames + 1
	local t = Timer.getTime(fpsTimer)
	if t >= 1000 then
		FrameStats.fps = fpsFrames * 1000 / t
		fpsFrames = 0
		Timer.reset(fpsTimer)
	end
end

LAUNCHED = true

while true do
	input()
	update()
	draw()
end
