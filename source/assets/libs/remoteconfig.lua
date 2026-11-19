---Remote settings: a small JSON file in the app's GitHub repository (remote.json on main) that adjusts the app
---without a new release, for the times nobody can publish one. Read at startup (the last copy is kept on the
---memory card and applied right away, also offline), then downloaded again in the background.
---
---  {
---    "format": 1,
---    "userAgent": "Mozilla/5.0 ...",                 browser identification sent to the sites
---    "imageProxy": "https://wsrv.nl/?url=%s&...",    image converter; one %s for the escaped image address
---    "disabledExtensions": ["kei.en.example"],       extensions whose sources are switched off (harmful or broken)
---    "notice": {"id": "2027-01", "until": "2027-03-01", "text": {"English": "...", "PortugueseBR": "..."}}
---  }
---
---Every field is optional and checked: a wrong value is ignored, never applied.
RemoteConfig = {}

local FILE = "ux0:data/otakio/remote.json"
local SEEN_FILE = "ux0:data/otakio/remote_seen.txt"
local URL = "https://raw.githubusercontent.com/%s/main/remote.json"

local applied = {}

---@return boolean
local function validUserAgent(ua)
	return type(ua) == "string" and #ua >= 20 and #ua <= 300 and ua:find("^Mozilla/5%.0 ") ~= nil and not ua:find("[%c]")
end

---@return boolean
local function validProxy(p)
	if type(p) ~= "string" or #p > 300 or p:find("[%c%s]") or not p:find("^https://[%w%.%-]+/") then
		return false
	end
	local _, count = p:gsub("%%s", "")
	local _, percents = p:gsub("%%", "")
	return count == 1 and percents == 1
end

local function today()
	return Clock and Clock.date and Clock.date("%Y-%m-%d") or ""
end

local function noticeText(notice)
	local text = notice.text
	if type(text) == "string" then
		return text
	end
	if type(text) ~= "table" then
		return nil
	end
	local lang = Settings and Settings.Language or "Default"
	if lang == "Default" and GetSystemLanguageName then
		lang = GetSystemLanguageName()
	end
	local t = text[lang] or text.English
	return type(t) == "string" and t ~= "" and t or nil
end

local function seenNotices()
	local seen = {}
	for id in ((FS and FS.read(SEEN_FILE)) or ""):gmatch("[^\n]+") do
		seen[id] = true
	end
	return seen
end

---Applies a decoded remote.json; returns the list of what changed (for the log)
---@param data table
---@param showNotice boolean
function RemoteConfig.apply(data, showNotice)
	local changes = {}
	if type(data) ~= "table" or (data.format ~= nil and data.format ~= 1) then
		return changes
	end
	if validUserAgent(data.userAgent) and data.userAgent ~= USERAGENT then
		USERAGENT = data.userAgent
		changes[#changes + 1] = "user agent"
	end
	if validProxy(data.imageProxy) and data.imageProxy ~= Config.IMAGE_PROXY then
		Config.IMAGE_PROXY = data.imageProxy
		changes[#changes + 1] = "image proxy"
	end
	if type(data.disabledExtensions) == "table" and DisableParsersOfExtension then
		for _, id in ipairs(data.disabledExtensions) do
			if type(id) == "string" and id ~= "" and not applied[id] then
				applied[id] = true
				DisableParsersOfExtension(id)
				changes[#changes + 1] = "disabled " .. id
			end
		end
	end
	local notice = data.notice
	if showNotice and type(notice) == "table" and type(notice.id) == "string" and notice.id ~= "" and not notice.id:find("[%c]") then
		local untilDate = type(notice.untilDate or notice["until"]) == "string" and (notice.untilDate or notice["until"]) or nil
		local text = noticeText(notice)
		local seen = seenNotices()
		if text and not seen[notice.id] and (not untilDate or today() == "" or today() <= untilDate) then
			if Notifications then
				Notifications.push(text, 6000)
			end
			if FS then
				FS.append(SEEN_FILE, notice.id .. "\n")
			end
			changes[#changes + 1] = "notice " .. notice.id
		end
	end
	return changes
end

---Startup: the copy from last time, before any network
function RemoteConfig.loadCached()
	local ok, data = pcall(function()
		local text = FS and FS.read(FILE)
		return text and Json.decode(text)
	end)
	if ok and data then
		pcall(RemoteConfig.apply, data, false)
	end
end

---Downloads remote.json (inside a coroutine: Http waits by yielding), applies it and keeps it for the next start
function RemoteConfig.fetch()
	if (Config.GITHUB_REPO or "") == "" then
		return
	end
	local body = Http.get(string.format(URL, Config.GITHUB_REPO))
	if type(body) ~= "string" or body == "" or #body > 65536 then
		return
	end
	local data = Json.decode(body)
	if type(data) ~= "table" then
		return
	end
	local changes = RemoteConfig.apply(data, true)
	if FS then
		FS.write(FILE, body)
	end
	if #changes > 0 and Console then
		Console.write("remote config: " .. table.concat(changes, ", "))
	end
end
