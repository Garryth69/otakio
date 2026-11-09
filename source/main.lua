-- captured before the sandbox below removes `debug` (used by the error barrier at the end of this file)
local traceback = debug.traceback
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
loadlib("sha256")
loadlib("fs")
loadlib("migrations")
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
loadlib("engines_intl")
loadlib("extensions")
loadlib("diag")
loadlib("sourcestatus")
loadlib("appupdate")
loadlib("updates")
loadlib("dialog")
loadlib("setup")
loadlib("catalogs")
loadlib("screens")
loadlib("backup")
loadlib("readersheet")
loadlib("extra")
loadlib("details")
loadlib("menu")
loadlib("panel")
loadlib("notifications")
loadlib("debug")
loadlib("dlhistory")
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
			local suc, err = pcall(RunSandboxed, legacyPath .. file.name)
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
-- fresh install: the first-run setup opens once the loading screen is gone
local runSetup = false

-- startup timing: each loading stage's time goes to log.txt (one line), to find what makes the start slow
local stageClock = Timer.new()
local stageTimes, stageName = {}, "start"
local function stage(name)
	stageTimes[#stageTimes + 1] = stageName .. " " .. math.floor(Timer.getTime(stageClock)) .. " ms"
	stageName = name
	Timer.reset(stageClock)
end

-- Glyph warm-up. FreeType reads every glyph it renders for the first time from the font files on the memory card
-- (13 MB each, with the CJK ideograms), so pre-rendering the whole character set took about 10 s at start-up. Now the
-- start-up renders only the basic Latin set and the rest is rendered off-screen a few glyphs per frame (within a time
-- budget) once the Library is up; the measured rate goes to log.txt.
FontWarmup = {pending = {}, glyphs = 0, ms = 0, frames = 0}
do
	local clock = Timer.new()
	local BUDGET_MS = 4

	---Queues every character of `text` for each font in `fontList`
	function FontWarmup.queue(fontList, text)
		local chars, seen = {}, {}
		for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			if ch ~= "\n" and ch ~= "\r" and ch ~= " " and not seen[ch] then
				seen[ch] = true
				chars[#chars + 1] = ch
			end
		end
		for _, font in ipairs(fontList) do
			FontWarmup.pending[#FontWarmup.pending + 1] = {font = font, chars = chars, next = 1}
		end
	end

	---Called inside the drawing phase: renders a few more glyphs off-screen, one at a time, within the budget
	function FontWarmup.tick()
		local job = FontWarmup.pending[1]
		if not job then
			return
		end
		Timer.reset(clock)
		FontWarmup.frames = FontWarmup.frames + 1
		repeat
			Font.print(job.font, 0, -200, job.chars[job.next], COLOR_BLACK)
			FontWarmup.glyphs = FontWarmup.glyphs + 1
			job.next = job.next + 1
			if job.next > #job.chars then
				table.remove(FontWarmup.pending, 1)
				job = FontWarmup.pending[1]
			end
		until not job or Timer.getTime(clock) >= BUDGET_MS
		FontWarmup.ms = FontWarmup.ms + Timer.getTime(clock)
		if not job then
			pcall(ExtLog, string.format("font warm-up: %d glyphs in %d ms over %d frames (%.1f ms per glyph)",
				FontWarmup.glyphs, FontWarmup.ms, FontWarmup.frames, FontWarmup.ms / math.max(1, FontWarmup.glyphs)))
		end
	end

	function FontWarmup.isActive()
		return FontWarmup.pending[1] ~= nil
	end
end

local function preloadData()
	-- data written by older versions is converted before anything reads it (migrations.lua)
	local migrated, result = pcall(Migrations.run)
	if not migrated then
		Console.error("migrations: " .. tostring(result))
	end
	stage("settings")
	coroutine.yield("Loading settings")
	local suc, err = pcall(Settings.load, Settings)
	if not suc then
		Console.error(err)
	end
	pcall(ExtLog, "engine: " .. tostring(ENGINE_VERSION))
	pcall(Diag.startup)
	if not Settings.SkipFontLoad then
		local loadFontString = '1234567890AaBbCcDdEeFf\nGgHhIiJjKkLlMmNnOoPpQqRr\nSsTtUuVvWwXxYyZzАаБб\nВвГгДдЕеЁёЖжЗзИиЙйКкЛлМм\nНнОоПпРрСсТтУуФфХхЦцЧчШшЩщ\nЫыЪъЬьЭэЮюЯя!@#$%^&*()\n_+-=[]"\\/.,{}:;\'|? №~<>`\r—…·›✓↓♥⚠\nÁáÀàÂâÃãÉéÊêÍíÓóÔôÕõÚúÇç'
		-- accents of the interface languages (French, German, Italian, Spanish)
		loadFontString = loadFontString .. '\nÈèËëÎîÏïÛûÙùŒœÄäÖöÜüßÑñ¿¡«»„“”•'
		-- Japanese / Chinese: kana and the ideograms of the interface, so the first screens don't stall on glyph loading
		if Settings.Language == "Japanese" or Settings.Language == "ChineseSimplified" or Settings.Language == "ChineseTraditional" or (Settings.Language == "Default" and GetSystemLanguageName and GetSystemLanguageName():find("^[JC]")) then
			loadFontString = loadFontString .. '\nあいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん' ..
				'\nアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンー' ..
				'\n书架浏览设置下载历史导入搜索書櫃瀏覽設定下載紀錄匯入搜尋章节章節話漫画漫畫最新热门熱門全部更新扩展擴充功能' ..
				'\n設定履歴検索拡張機能読む続きライブラリ、。「」（）！？：'
		end
		for langName, _ in pairs(Language) do
			loadFontString = loadFontString .. (LanguageNames and LanguageNames[langName] and LanguageNames[langName][langName] or "")
		end
		stage("fonts")
		-- start-up renders only the basic Latin set, so the Library shows up at once; the full set for the three sizes
		-- most of the interface uses is rendered in the background afterwards (FontWarmup above)
		local basic = '1234567890AaBbCcDdEeFf\nGgHhIiJjKkLlMmNnOoPpQqRr\nSsTtUuVvWwXxYyZz!?.,:;()-/'
		local fontClock = Timer.new()
		local timings = {}
		for k, v in ipairs(fonts) do
			coroutine.yield("Loading fonts " .. k .. "/" .. #fonts)
			Timer.reset(fontClock)
			Font.print(v, 0, 0, basic, COLOR_BLACK)
			timings[#timings + 1] = math.floor(Timer.getTime(fontClock)) .. " ms"
		end
		Timer.destroy(fontClock)
		pcall(ExtLog, "fonts (basic set): " .. table.concat(timings, ", "))
		FontWarmup.queue({FONT16, BONT16, FONT20}, loadFontString)
	end
	stage("cache")
	coroutine.yield("Loading cache, checking existing data")
	suc, err = pcall(Cache.load)
	if not suc then
		Console.error(err)
	end
	stage("history")
	coroutine.yield("Loading history")
	suc, err = pcall(Cache.loadHistory)
	if not suc then
		Console.error(err)
	end
	stage("library")
	coroutine.yield("Loading library")
	suc, err = pcall(Database.load)
	if not suc then
		Console.error(err)
	end
	suc, err = pcall(Updates.load)
	if not suc then
		Console.error(err)
	end
	stage("saved chapters")
	coroutine.yield("Checking saved chapters")
	suc, err = pcall(ChapterSaver.load)
	if not suc then
		Console.error(err)
	end
	stage("covers")
	coroutine.yield("Loading custom covers")
	suc, err = pcall(CustomCovers.load)
	if not suc then
		Console.error(err)
	end
	Menu.setMode("LIBRARY")
	Panel.show()
	stage("extensions")
	coroutine.yield("Checking for updates")
	-- first run starts with no extensions: the user picks the sources in the Extensions tab
	if not FS.exists(FIRST_RUN_FLAG) then
		runSetup = Setup.needed(true)
		FS.write(FIRST_RUN_FLAG, Config.VERSION_NAME)
		Extensions.refresh(true)
	elseif Settings.CheckExtUpdatesAtStart then
		Extensions.refresh(true)
	end
	stage("done")
	pcall(ExtLog, "startup: " .. table.concat(stageTimes, ", "))
	-- new Otakio release on GitHub? asks to install it (unless turned off in Settings > About)
	AppUpdate.startup()
	Migrations.notify()
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

if runSetup then
	Setup.start()
end

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
		if AppUpdate.isBusy() then
			AppUpdate.input(oldPad, pad)
		elseif Dialog.isOpen() then
			Dialog.input(oldPad, pad, oldTouch, touch)
		elseif ReaderSheet.takesInput(pad) then
			ReaderSheet.input(oldPad, pad, oldTouch, touch)
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
		Diag.update()
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
	-- fast clocks while anything happens; the default ones a few seconds after everything went quiet (perf.lua)
	local lx, ly = Controls.readLeftAnalog()
	local rx, ry = Controls.readRightAnalog()
	local stick = math.abs(lx - 128) > 40 or math.abs(ly - 128) > 40 or math.abs(rx - 128) > 40 or math.abs(ry - 128) > 40
	Perf.update(fade > 0 or pad ~= 0 or touch.x ~= nil or stick or Threads.isDownloadRunning() or ParserManager.isBusy()
		or ChapterSaver.is_download_running() or Extensions.isWorking() or AppUpdate.isBusy() or FontWarmup.isActive())
end

local fpsTimer = Timer.new()
local fpsFrames = 0
local frameClock = Timer.new() -- CPU time of the frame (input + update + draw), for the hitch log (diag.lua)

local function draw()
	Graphics.initBlend()
	DRAW_PHASE = true -- textures freed from here to termBlend wait in a queue (image.lua)
	if AppMode == MENU then
		Menu.draw()
	elseif AppMode == READER then
		Reader.draw()
		ReaderSheet.draw()
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
	AppUpdate.draw() -- over the button bar too: the menu doesn't take input meanwhile
	Debug.draw()
	FontWarmup.tick()
	Graphics.termBlend() -- waits for the GPU to finish the frame
	DRAW_PHASE = false
	local frameMs = Timer.getTime(frameClock)
	if frameMs > 50 then
		Diag.hitch(frameMs, FontWarmup.isActive())
	end
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

-- Error barrier: a Lua error in one screen (or in an extension's callback) no longer closes the app. The error goes
-- to log.txt, the reader/dialogs close, textures are released and the app returns to the Library. If errors keep
-- coming back-to-back the original error is raised (the app would only loop on a broken state).
local recoverTimer = Timer.new()
local recoveries = 0

local function recover(err)
	if type(err) == "string" and err:find("SIM_DONE", 1, true) then
		error(err, 0) -- the PC simulator ending a scenario
	end
	if DRAW_PHASE then
		pcall(Graphics.termBlend)
		DRAW_PHASE = false
		pcall(Screen.flip)
	end
	if Timer.getTime(recoverTimer) > 10000 then
		recoveries = 0
	end
	Timer.reset(recoverTimer)
	recoveries = recoveries + 1
	if ExtLog then
		pcall(ExtLog, "recovered from error: " .. tostring(err):sub(1, 600))
	end
	Console.error(err)
	if recoveries > 5 then
		error(err, 0)
	end
	pcall(Dialog.close)
	if AppMode == READER then
		AppMode = MENU
	end
	pcall(Textures.reclaim, math.huge)
	pcall(Menu.setMode, "LIBRARY")
	pcall(Notifications.push, Language[Settings.Language].OTAKIO.ERROR_RECOVERED or "Something went wrong; back to the Library")
end

local function frame()
	Timer.reset(frameClock)
	Textures.flush() -- the GPU finished the previous frame: queued textures can go now
	input()
	update()
	draw()
end

while true do
	local ok, err = xpcall(frame, traceback)
	if not ok then
		recover(err)
	end
end
