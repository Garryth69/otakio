---App updates from the project's GitHub releases.
---The latest release's tag (e.g. "v1.1") is compared with Config.VERSION_NAME; when it is newer the user is
---told once per session and can download its .vpk asset to ux0:/vpk/ (installed with VitaShell, which keeps
---ux0:data/otakio, so the library and settings survive the update).
AppUpdate = {}

local doesFileExist = System.doesFileExist
local doesDirExist = System.doesDirExist
local createDirectory = System.createDirectory

local function L()
	return Language[Settings.Language].OTAKIO
end

local API = "https://api.github.com/repos/%s/releases/latest"
local VPK_DIR = "ux0:/vpk/"

local job = nil -- running coroutine
local state = "idle" -- idle | checking | none | available | downloading | done | error
local latest = nil -- {version = "1.1", url = "https://...vpk", name = "Otakio-1.1.vpk"}
local notified = false
local downloadKey = {}

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

local function check(silent)
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
		latest = {version = version, url = asset.browser_download_url, name = asset.name}
		state = "available"
		if not notified then
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

local function start(fn)
	if not job then
		job = coroutine.create(fn)
	end
end

---Checks the latest release in the background (silent = no message when up to date or offline)
function AppUpdate.check(silent)
	if (Config.GITHUB_REPO or "") == "" then
		return
	end
	start(function()
		local ok, err = pcall(check, silent)
		if not ok then
			state = "error"
			Console.error("app update: " .. tostring(err))
		end
	end)
end

local function download()
	if not latest then
		return
	end
	state = "downloading"
	if not doesDirExist(VPK_DIR) then
		createDirectory(VPK_DIR)
	end
	local path = VPK_DIR .. latest.name
	Notifications.push(string.format(L().APP_UPDATE_DOWNLOADING, latest.version))
	Threads.insertTask(downloadKey, {Type = "FileDownload", Link = latest.url, Path = path})
	while Threads.check(downloadKey) do
		coroutine.yield(false)
	end
	if doesFileExist(path) then
		state = "done"
		Notifications.push(string.format(L().APP_UPDATE_DONE, path), 6000)
	else
		state = "error"
		Notifications.push(L().APP_UPDATE_FAILED)
	end
end

---Settings > About > "Check for app updates": checks, then offers the download when a newer version exists
function AppUpdate.menuAction()
	if state == "checking" or state == "downloading" then
		return
	end
	if state == "available" and latest then
		Dialog.confirm(string.format(L().APP_UPDATE_Q, latest.version), L().APP_UPDATE_HINT, function()
			start(download)
		end)
		return
	end
	AppUpdate.check(false)
end

---Text shown next to the settings item
function AppUpdate.status()
	if state == "checking" or state == "downloading" then
		return L().CHECKING
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
