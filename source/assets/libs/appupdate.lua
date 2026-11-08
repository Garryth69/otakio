---App updates from the project's GitHub releases, installed inside the app.
---The latest release's tag (e.g. "v1.1.0") is compared with Config.VERSION_NAME. When it is newer, Otakio downloads
---the release's .vpk to ux0:data/otakio/update/, extracts it, checks it is Otakio (TITLE_ID in param.sfo) and hands it
---to the system installer (System.installApp, the same promoter VitaShell uses), then restarts. ux0:data/otakio is
---never touched, so the library and settings survive. If anything fails, the VPK is left in ux0:/vpk/ for VitaShell.
---Settings > About > "Check for app updates at startup" (AppAutoUpdate) turns the startup check and prompt off.
AppUpdate = {}

-- System and RemoveDirectory leave the global scope after startup (extension sandbox): keep them as upvalues
local doesFileExist = System.doesFileExist
local doesDirExist = System.doesDirExist
local deleteFile = System.deleteFile
local createDirectory = System.createDirectory
local rename = System.rename
local openFile, sizeFile, closeFile = System.openFile, System.sizeFile, System.closeFile
local getFreeSpace = System.getFreeSpace
local installApp = System.installApp
local launchApp = System.launchApp
local exitApp = System.exit
local removeDirectory = RemoveDirectory
local rawsub = string.rawsub or string.sub -- byte offsets (string.sub is UTF-8 aware in Otakio)

local function L()
	return Language[Settings.Language].OTAKIO
end

local API = "https://api.github.com/repos/%s/releases/latest"
local VPK_DIR = "ux0:/vpk/"
local UPDATE_DIR = Config.DATA .. "update/"
local MB = 1024 * 1024

local job = nil -- running coroutine
local state = "idle" -- idle | checking | none | available | downloading | installing | installed | error
local latest = nil -- {version = "1.1.0", url = "https://...vpk", name = "Otakio-1.1.0.vpk", size = 12345678}
local notified = false
local downloadKey, unzipKey = {}, {}

---@return integer[] numeric parts of "v1.2.3"
local function parts(v)
	local out = {}
	for n in tostring(v or ""):gmatch("%d+") do
		out[#out + 1] = tonumber(n)
	end
	return out
end

---@return boolean true when version a is newer than b
local function newer(a, b)
	local x, y = parts(a), parts(b)
	for i = 1, math.max(#x, #y) do
		local p, q = x[i] or 0, y[i] or 0
		if p ~= q then
			return p > q
		end
	end
	return false
end
AppUpdate.newer = newer

local function fileSize(path)
	local fh = doesFileExist(path) and openFile(path, FREAD)
	if not fh then
		return 0
	end
	local n = sizeFile(fh)
	closeFile(fh)
	return n or 0
end

---Reads one string value (e.g. "APP_VER", "TITLE_ID") from a param.sfo (PSF) file's contents
local function sfoValue(data, key)
	if type(data) ~= "string" or rawsub(data, 1, 4) ~= "\0PSF" then
		return nil
	end
	local function u16(o)
		local a, b = data:byte(o + 1, o + 2)
		return a + b * 256
	end
	local function u32(o)
		local a, b, c, d = data:byte(o + 1, o + 4)
		return a + b * 256 + c * 65536 + d * 16777216
	end
	local keyStart, dataStart, count = u32(8), u32(12), u32(16)
	for i = 0, count - 1 do
		local e = 20 + i * 16
		local k = keyStart + u16(e)
		local name = data:match("^[^%z]*", k + 1)
		if name == key then
			local len, off = u32(e + 4), dataStart + u32(e + 12)
			return (rawsub(data, off + 1, off + len):gsub("%z+$", ""))
		end
	end
	return nil
end
AppUpdate.sfoValue = sfoValue

local function waitTask(key)
	while Threads.check(key) do
		coroutine.yield(false)
	end
end

local function cleanup()
	if removeDirectory and doesDirExist(UPDATE_DIR) then
		removeDirectory(UPDATE_DIR)
	end
end

---Installing inside the app didn't work: leave the VPK where VitaShell finds it
local function fallback(vpk)
	state = "error"
	if not doesDirExist(VPK_DIR) then
		createDirectory(VPK_DIR)
	end
	local dest = VPK_DIR .. latest.name
	if doesFileExist(dest) then
		deleteFile(dest)
	end
	if doesFileExist(vpk) and rename then
		rename(vpk, dest)
	end
	cleanup()
	if doesFileExist(dest) then
		Notifications.push(string.format(L().APP_UPDATE_MANUAL, dest), 8000)
	else
		Notifications.push(L().APP_UPDATE_FAILED)
	end
end

local function restart()
	if launchApp then
		pcall(launchApp, Config.TITLE_ID)
	end
	if exitApp then
		exitApp()
	end
end

local function install()
	if not latest then
		return
	end
	local need = (latest.size or 16 * MB) * 3 + 8 * MB -- zip + extracted copy + the installer's own copy
	if getFreeSpace and getFreeSpace("ux0:") < need then
		state = "error"
		Notifications.push(string.format(L().APP_UPDATE_NO_SPACE, math.ceil(need / MB)), 6000)
		return
	end
	cleanup()
	createDirectory(UPDATE_DIR)
	local vpk = UPDATE_DIR .. "otakio.vpk"
	local pkg = UPDATE_DIR .. "pkg"

	state = "downloading"
	Notifications.push(string.format(L().APP_UPDATE_DOWNLOADING, latest.version))
	Threads.insertTask(downloadKey, {Type = "FileDownload", Link = latest.url, Path = vpk})
	waitTask(downloadKey)
	local size = fileSize(vpk)
	if size == 0 or (latest.size and size ~= latest.size) then
		-- incomplete or corrupted download: nothing to install
		state = "error"
		cleanup()
		Notifications.push(L().APP_UPDATE_DL_FAILED)
		return
	end

	state = "installing"
	Notifications.push(string.format(L().APP_UPDATE_INSTALLING, latest.version), 60000)
	Threads.insertTask(unzipKey, {Type = "UnZip", Path = vpk, DestPath = pkg})
	waitTask(unzipKey)
	local sfo = FS.read(pkg .. "/sce_sys/param.sfo")
	local newVer = sfoValue(sfo, "APP_VER")
	if not doesFileExist(pkg .. "/eboot.bin") or sfoValue(sfo, "TITLE_ID") ~= Config.TITLE_ID or not newVer then
		-- not a complete Otakio package: never hand it to the installer
		Console.error("app update: package check failed")
		return fallback(vpk)
	end
	-- the system installer blocks for a while: let the "installing" message reach the screen first
	for _ = 1, 20 do
		coroutine.yield(false)
	end
	local ok = installApp and installApp(pkg)
	-- the promoter doesn't report failures: the installed app must now carry the new version
	local installed = sfoValue(FS.read("ux0:app/" .. Config.TITLE_ID .. "/sce_sys/param.sfo"), "APP_VER")
	if not ok or installed ~= newVer then
		Console.error("app update: install failed (" .. tostring(ok) .. ")")
		return fallback(vpk)
	end
	cleanup()
	state = "installed"
	Notifications.push(string.format(L().APP_UPDATE_INSTALLED, latest.version), 60000)
	-- the files of the running app were replaced: restart into the new version
	for _ = 1, 90 do
		coroutine.yield(false)
	end
	restart()
end

local function start(fn)
	if not job then
		job = coroutine.create(fn)
	end
end

---Asks before installing (startup prompt and the About item); waits for the menu to be free (not reading, no dialog)
local function offer()
	while Dialog.isOpen() or AppMode ~= MENU do
		coroutine.yield(false)
	end
	Dialog.confirm(string.format(L().APP_UPDATE_Q, latest.version), L().APP_UPDATE_HINT, function()
		job = nil
		start(install)
	end)
end

local function check(silent, prompt)
	state = "checking"
	local body = Http.get(string.format(API, Config.GITHUB_REPO), {Accept = "application/vnd.github+json"})
	coroutine.yield(false)
	local data = Json.decode(body, 1500)
	if type(data) ~= "table" or type(data.tag_name) ~= "string" then
		state = "error"
		if not silent then
			Notifications.push(L().APP_UPDATE_FAILED)
		end
		return
	end
	local asset = nil
	for _, a in ipairs(type(data.assets) == "table" and data.assets or {}) do
		if type(a.name) == "string" and a.name:lower():find("%.vpk$") and type(a.browser_download_url) == "string" then
			asset = a
			break
		end
	end
	local version = data.tag_name:gsub("^[vV]", "")
	if asset and newer(version, Config.VERSION_NAME) then
		latest = {version = version, url = asset.browser_download_url, name = asset.name, size = tonumber(asset.size)}
		state = "available"
		if prompt then
			offer()
		elseif not notified then
			notified = true
			Notifications.push(string.format(L().APP_UPDATE_AVAILABLE, version))
		end
	else
		state = "none"
		if not silent then
			Notifications.push(L().APP_UP_TO_DATE)
		end
	end
end

---Checks the latest release in the background.
---silent: no message when up to date or offline; prompt: ask right away to install a newer version
function AppUpdate.check(silent, prompt)
	if (Config.GITHUB_REPO or "") == "" then
		return
	end
	start(function()
		local ok, err = pcall(check, silent, prompt)
		if not ok then
			state = "error"
			Console.error("app update: " .. tostring(err))
		end
	end)
end

---Startup: only when "Check for app updates at startup" is on
function AppUpdate.startup()
	if Settings.AppAutoUpdate ~= false then
		AppUpdate.check(true, true)
	end
end

---Settings > About > "Check for app updates": checks (and asks to install a newer version)
function AppUpdate.menuAction()
	if state == "checking" or state == "downloading" or state == "installing" or state == "installed" then
		return
	end
	if state == "available" and latest then
		start(offer)
		return
	end
	AppUpdate.check(false, true)
end

---Text shown next to the settings item
function AppUpdate.status()
	if state == "checking" then
		return L().CHECKING
	elseif state == "downloading" or state == "installing" then
		return string.format(L().APP_UPDATE_INSTALLING, latest and latest.version or "")
	elseif state == "available" and latest then
		return string.format(L().APP_UPDATE_AVAILABLE, latest.version)
	elseif state == "none" then
		return L().APP_UP_TO_DATE
	end
	return ""
end

---Resumed from the main loop
function AppUpdate.update()
	if job then
		local ok, err = coroutine.resume(job)
		if not ok then
			Console.error("app update: " .. tostring(err))
			job = nil
		elseif coroutine.status(job) == "dead" then
			job = nil
		end
	end
end
