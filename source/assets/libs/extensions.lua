---Otakio extension manager (Mihon-style).
---  * Repositories publish an index.json (see repo/ folder + tools/gen_repo.py)
---  * Extensions are Lua files installed to ux0:data/otakio/extensions/
---  * Built-in repository ships inside the VPK, so the app works offline/out of the box
---  * Classic NOBORU parsers are listed too and run unchanged
Extensions = {}

local EXT_DIR = Config.DATA .. "extensions/"
local DB_PATH = Config.DATA .. "extensions.dat"
local REPOS_PATH = Config.DATA .. "repos.dat"

local installed = {} -- id -> metadata
local catalog = {} -- merged list of available extension entries
local catalogById = {}
local repos = {} -- user repositories {name, url}
local repoStatus = {} -- url -> "ok" | "error" | "loading"
local jobs = {}
local installing = {}
local currentJob = nil
local refreshing = false
local lastRefresh = 0
local version = 0 -- bumps whenever lists change (screens cache on it)

local co_create, co_resume, co_status, co_yield = coroutine.create, coroutine.resume, coroutine.status, coroutine.yield

---Diagnostics written to ux0:data/otakio/log.txt (kept short) so problems on real
---hardware can be reported without a debug console
local LOG_PATH = Config.DATA .. "log.txt"
local logLines = nil
function ExtLog(msg)
	if not logLines then
		logLines = {}
		local old = FS.read(LOG_PATH)
		if old then
			for line in old:gmatch("[^\n]+") do
				logLines[#logLines + 1] = line
			end
		end
	end
	local line = (Clock and Clock.date and Clock.date("%Y-%m-%d %H:%M:%S") or "") .. "  " .. tostring(msg)
	logLines[#logLines + 1] = line
	while #logLines > 300 do
		table.remove(logLines, 1)
	end
	FS.write(LOG_PATH, table.concat(logLines, "\n") .. "\n")
	if Console then
		Console.write(line)
	end
end

local function L()
	return Language[Settings.Language].OTAKIO
end

local function touch()
	version = version + 1
end

function Extensions.getVersion()
	return version
end

-------------------------------------------------------------------------------
-- persistence
-------------------------------------------------------------------------------

local function saveInstalled()
	FS.saveTable(DB_PATH, installed)
end

local function saveRepos()
	FS.saveTable(REPOS_PATH, repos)
end

-- the built-in entry exists only in builds that bundle a catalog (app0:repo/) or set an official URL
local hasBuiltin = nil
local function builtinAvailable()
	if hasBuiltin == nil then
		hasBuiltin = (Config.OFFICIAL_REPO_URL or "") ~= "" or FS.exists(Config.BUILTIN_REPO .. "index.json")
	end
	return hasBuiltin
end

function Extensions.getRepos()
	local list = {}
	if builtinAvailable() then
		list[1] = {name = "Otakio", url = Config.OFFICIAL_REPO_URL, builtin = true}
	end
	for _, r in ipairs(repos) do
		list[#list + 1] = r
	end
	return list
end

function Extensions.addRepo(url)
	url = (url or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if url == "" then
		return false
	end
	-- GitHub shorthand: "user/repo" or "github.com/user/repo" -> raw index.json on the main branch
	local owner, name = url:match("^([%w%-_%.]+)/([%w%-_%.]+)/?$")
	if not owner then
		owner, name = url:match("^https?://github%.com/([%w%-_%.]+)/([%w%-_%.]+)/?$")
		if not owner then
			owner, name = url:match("^github%.com/([%w%-_%.]+)/([%w%-_%.]+)/?$")
		end
	end
	if owner and not owner:find("%.") then
		url = "https://raw.githubusercontent.com/" .. owner .. "/" .. name .. "/main/index.json"
	end
	if not url:find("^https?://") then
		url = "https://" .. url
	end
	if not url:find("%.json$") then
		url = url:gsub("/+$", "") .. "/index.json"
	end
	for _, r in ipairs(repos) do
		if r.url == url then
			return false
		end
	end
	repos[#repos + 1] = {name = url:match("^https?://([^/]+)") or url, url = url}
	saveRepos()
	Extensions.refresh(true)
	return true
end

function Extensions.removeRepo(url)
	for i, r in ipairs(repos) do
		if r.url == url then
			table.remove(repos, i)
			saveRepos()
			Extensions.refresh(true)
			return true
		end
	end
	return false
end

---@return boolean true when at least one extension repository is configured
function Extensions.hasRepos()
	return #Extensions.getRepos() > 0
end

function Extensions.getRepoStatus(url)
	return repoStatus[url]
end

-------------------------------------------------------------------------------
-- background jobs (coroutines resumed from the main loop)
-------------------------------------------------------------------------------

local function addJob(name, fn)
	jobs[#jobs + 1] = {name = name, co = co_create(fn)}
end

function Extensions.update()
	if not currentJob then
		currentJob = table.remove(jobs, 1)
		if not currentJob then
			return
		end
	end
	local ok, err = co_resume(currentJob.co)
	if not ok then
		ExtLog("job " .. tostring(currentJob.name) .. " crashed: " .. tostring(err))
		if currentJob.name == "install" then
			for id in pairs(installing) do
				installing[id] = nil
			end
		end
	end
	if co_status(currentJob.co) == "dead" then
		currentJob = nil
	end
end

function Extensions.isBusy(name)
	if currentJob and (not name or currentJob.name == name) then
		return true
	end
	for _, j in ipairs(jobs) do
		if not name or j.name == name then
			return true
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- loading installed extensions
-------------------------------------------------------------------------------

---Loads an extension file, tagging every Parser it creates with the extension id
local function loadExtensionFile(id, path)
	CURRENT_EXTENSION_ID = id
	local ok, err = pcall(dofile, path)
	CURRENT_EXTENSION_ID = nil
	if not ok then
		ExtLog("can't load extension " .. id .. ": " .. tostring(err))
		if installed[id] then
			installed[id].error = tostring(err)
		end
		return false
	end
	if installed[id] then
		installed[id].error = nil
	end
	return true
end

function Extensions.loadInstalled()
	FS.mkdir(EXT_DIR)
	installed = FS.loadTable(DB_PATH) or {}
	repos = FS.loadTable(REPOS_PATH) or {}
	for id, meta in pairs(installed) do
		local path = EXT_DIR .. meta.file
		if FS.exists(path) then
			loadExtensionFile(id, path)
		else
			installed[id] = nil
		end
	end
	touch()
end

function Extensions.getInstalled()
	return installed
end

function Extensions.isInstalled(id)
	return installed[id] ~= nil
end

function Extensions.countInstalled()
	local n = 0
	for _ in pairs(installed) do
		n = n + 1
	end
	return n
end

-------------------------------------------------------------------------------
-- repositories
-------------------------------------------------------------------------------

local function mergeIndex(index, repo, base)
	if type(index) ~= "table" or type(index.extensions) ~= "table" then
		return 0
	end
	if (index.minEngine or 1) > Config.ENGINE_LEVEL then
		Notifications.pushUnique(string.format(L().REPO_NEEDS_UPDATE, repo.name))
	end
	local n = 0
	for _, e in ipairs(index.extensions) do
		if type(e) == "table" and e.id and e.name and (e.file or e.url) then
			local source = e.url or (base .. e.file)
			local entry = {
				id = e.id,
				name = e.name,
				lang = e.lang or "all",
				version = tonumber(e.version) or 1,
				nsfw = e.nsfw and true or false,
				engine = e.engine,
				baseUrl = e.baseUrl,
				source = source,
				origin = e.origin,
				compat = e.compat or "full",
				relay = e.relay and true or nil,
				health = e.health,
				checked = e.checked,
				repo = repo.name,
				repoUrl = repo.url
			}
			local old = catalogById[e.id]
			if not old or entry.version > old.version then
				if old then
					for i, c in ipairs(catalog) do
						if c == old then
							catalog[i] = entry
							break
						end
					end
				else
					catalog[#catalog + 1] = entry
				end
				catalogById[e.id] = entry
			end
			n = n + 1
		end
	end
	return n
end

local function validIndex(index)
	return type(index) == "table" and type(index.extensions) == "table"
end

---Mihon/Tachiyomi repositories (index.min.json) list Android APKs. Otakio can't run those,
---but every source whose site has a Lua equivalent in the catalog is compatible.
---Returns the extension list of a Mihon index in either format:
---  v1 (index.min.json): [{pkg, sources = [{baseUrl}]}]
---  v2 (index.json):     {extensionList = {extensions = [{packageName, sources = [{homeUrl}]}]}}
local function mihonExtensions(index)
	if type(index) ~= "table" then
		return nil
	end
	if type(index[1]) == "table" and index[1].pkg ~= nil and type(index[1].sources) == "table" then
		return index
	end
	local list = type(index.extensionList) == "table" and index.extensionList.extensions
	if type(list) == "table" and type(list[1]) == "table" and type(list[1].sources) == "table" then
		return list
	end
end

local function isMihonIndex(index)
	return mihonExtensions(index) ~= nil
end

local function hostOf(url)
	return ((url or ""):lower():gsub("^%a+://", ""):gsub("^www%.", ""):match("^[^/]+") or "")
end

---@return integer compatible, integer total
local function matchMihonIndex(index, repo)
	local byHost = {}
	for _, e in ipairs(catalog) do
		if e.baseUrl and e.baseUrl ~= "" and e.compat ~= "broken" then
			byHost[hostOf(e.baseUrl)] = byHost[hostOf(e.baseUrl)] or e
		end
	end
	local total, matched = 0, 0
	for _, ext in ipairs(mihonExtensions(index) or {}) do
		for _, src in ipairs(type(ext.sources) == "table" and ext.sources or {}) do
			total = total + 1
			local e = byHost[hostOf(src.baseUrl or src.homeUrl)]
			if e then
				matched = matched + 1
				e.alsoIn = e.alsoIn or {}
				e.alsoIn[repo.name] = true
			end
		end
	end
	return matched, total
end

local function fetchIndex(url)
	local body = Http.get(url)
	if body == "" then
		ExtLog("repo " .. url .. ": empty response")
		return nil
	end
	local index = Json.decode(body, 1500)
	if not validIndex(index) and not isMihonIndex(index) then
		ExtLog("repo " .. url .. ": not a valid index (" .. body:sub(1, 60):gsub("%c", " ") .. ")")
		return nil
	end
	return index
end

---Reloads all repository indexes. `force` ignores the 10 minute cache.
-- NOBORU parsers whose site API is gone, replaced by an Otakio native extension
local REPLACED_BY = {
	["noboru.mangadex"] = "otakio.mangadex",
	["noboru.mangadexdif"] = "otakio.mangadex",
	["noboru.mangakakalot"] = "otakio.mangakakalot",
	["noboru.mangasee"] = "otakio.weebcentral"
}

local function migrateReplaced()
	for old, new in pairs(REPLACED_BY) do
		if installed[old] and catalogById[new] then
			ExtLog("replacing " .. old .. " with " .. new)
			Extensions.uninstall(old)
			if not installed[new] then
				Extensions.install(catalogById[new])
			end
		end
	end
end

function Extensions.refresh(force)
	if refreshing or (not force and lastRefresh > 0 and Clock.now() - lastRefresh < 600) then
		return
	end
	refreshing = true
	addJob("refresh", function()
		local ok, err = pcall(function()
		local newCatalog, newById = {}, {}
		catalog, catalogById = newCatalog, newById
		local first = Extensions.getRepos()[1]
		local official = first and first.builtin and first or nil
		-- 1. the copy bundled in the VPK (test builds) is the baseline (works offline)
		if official then
			local data = FS.read(Config.BUILTIN_REPO .. "index.json")
			co_yield(false)
			local builtin = data and Json.decode(data, 1500)
			if validIndex(builtin) then
				local n = mergeIndex(builtin, official, Config.BUILTIN_REPO)
				repoStatus[official.url] = "offline"
				ExtLog("built-in repo: " .. n .. " extensions")
			else
				repoStatus[official.url] = "error"
				ExtLog("built-in repo unreadable (" .. tostring(data and #data or "missing") .. " bytes)")
			end
		end
		co_yield(false)
		local online = Threads.netActionUnSafe(Network.isWifiEnabled)
		-- 2. official repo online: only adds newer versions on top of the built-in copy
		if online and official and official.url ~= "" then
			local index = fetchIndex(official.url)
			if index then
				mergeIndex(index, official, (official.url:gsub("[^/]+$", "")))
				repoStatus[official.url] = "ok"
			end
		end
		co_yield(false)
		-- 3. user repositories
		for _, repo in ipairs(repos) do
			repoStatus[repo.url] = "loading"
			local index = online and fetchIndex(repo.url)
			if index and isMihonIndex(index) then
				local matched, total = matchMihonIndex(index, repo)
				repoStatus[repo.url] = "mihon:" .. matched .. "/" .. total
				if type(index.name) == "string" and repo.name ~= index.name then
					repo.name = index.name
					saveRepos()
				end
				ExtLog("Mihon repo " .. repo.url .. ": " .. matched .. "/" .. total .. " sources have a Lua equivalent")
			elseif index then
				mergeIndex(index, repo, (repo.url:gsub("[^/]+$", "")))
				repoStatus[repo.url] = "ok"
				if index.name and repo.name ~= index.name then
					repo.name = index.name
					saveRepos()
				end
			else
				repoStatus[repo.url] = "error"
			end
			co_yield(false)
		end
		migrateReplaced()
		table.sort(catalog, function(a, b)
			if a.lang ~= b.lang then
				return a.lang < b.lang
			end
			return a.name:lower() < b.name:lower()
		end)
		lastRefresh = Clock.now()
		local updates = Extensions.countUpdates()
		if updates > 0 then
			Notifications.pushUnique(string.format(L().EXT_UPDATES_AVAILABLE, updates))
			if Settings.AutoUpdateExtensions then
				Extensions.updateAll()
			end
		end
		end)
		if not ok then
			ExtLog("refresh failed: " .. tostring(err))
		end
		refreshing = false
		touch()
	end)
end

function Extensions.isRefreshing()
	return refreshing
end

function Extensions.getCatalog()
	return catalog
end

function Extensions.getEntry(id)
	return catalogById[id]
end

function Extensions.hasUpdate(id)
	local meta, entry = installed[id], catalogById[id]
	return meta ~= nil and entry ~= nil and entry.version > (meta.version or 0)
end

function Extensions.countUpdates()
	local n = 0
	for id in pairs(installed) do
		if Extensions.hasUpdate(id) then
			n = n + 1
		end
	end
	return n
end

-------------------------------------------------------------------------------
-- install / update / uninstall
-------------------------------------------------------------------------------

function Extensions.isInstalling(id)
	return installing[id] == true
end

local function disableParsersOf(id)
	DisableParsersOfExtension(id)
end

local function downloadTo(source, dest)
	if source:find("^app0:") then
		return FS.copy(source, dest)
	end
	local key = {}
	FS.delete(dest)
	Threads.insertTask(key, {Type = "FileDownload", Link = source, Path = dest})
	while Threads.check(key) do
		co_yield(false)
	end
	return FS.exists(dest)
end

local function validate(path)
	local data = FS.read(path) or ""
	if #data < 20 then
		return false
	end
	if not (data:find("Parser:new", 1, true) or data:find("Engines%.")) then
		return false
	end
	return load(data) ~= nil
end

---@param entry table catalog entry
function Extensions.install(entry)
	if not entry or installing[entry.id] then
		return
	end
	installing[entry.id] = true
	touch()
	addJob("install", function()
		local file = entry.id:gsub("[^%w%._%-]", "_") .. ".lua"
		local tmp = EXT_DIR .. file .. ".part"
		local ok = downloadTo(entry.source, tmp)
		local valid = ok and validate(tmp)
		if not ok then
			ExtLog("install " .. entry.id .. ": download failed from " .. tostring(entry.source))
		elseif not valid then
			ExtLog("install " .. entry.id .. ": invalid file (" .. tostring(#(FS.read(tmp) or "")) .. " bytes) from " .. tostring(entry.source))
		end
		if ok and valid then
			local dest = EXT_DIR .. file
			local wasInstalled = installed[entry.id] ~= nil
			if wasInstalled then
				disableParsersOf(entry.id)
			end
			FS.delete(dest)
			FS.copy(tmp, dest)
			FS.delete(tmp)
			installed[entry.id] = {
				id = entry.id,
				name = entry.name,
				lang = entry.lang,
				version = entry.version,
				nsfw = entry.nsfw,
				engine = entry.engine,
				relay = entry.relay,
				origin = entry.origin,
				compat = entry.compat,
				health = entry.health,
				repo = entry.repo,
				file = file,
				date = Clock.now()
			}
			loadExtensionFile(entry.id, dest)
			saveInstalled()
			ExtLog("installed " .. entry.id .. " v" .. tostring(entry.version))
			Notifications.push(string.format(wasInstalled and L().EXT_UPDATED or L().EXT_INSTALLED, entry.name))
		else
			FS.delete(tmp)
			Notifications.push(string.format(L().EXT_INSTALL_FAILED, entry.name))
		end
		installing[entry.id] = nil
		touch()
	end)
end

function Extensions.uninstall(id)
	local meta = installed[id]
	if not meta then
		return
	end
	disableParsersOf(id)
	FS.delete(EXT_DIR .. meta.file)
	installed[id] = nil
	saveInstalled()
	touch()
	Notifications.push(string.format(L().EXT_UNINSTALLED, meta.name))
end

function Extensions.updateAll()
	for id in pairs(installed) do
		if Extensions.hasUpdate(id) then
			Extensions.install(catalogById[id])
		end
	end
end

---Imports parsers from a NOBORU installation (ux0:data/noboru/parsers) as local extensions
function Extensions.importNoboruParsers()
	local dir = "ux0:data/noboru/parsers/"
	local count = 0
	for _, f in ipairs(FS.list(dir)) do
		if not f.directory and f.name:find("%.lua$") then
			local id = "noboru.local." .. f.name:gsub("%.lua$", ""):gsub("[^%w]", ""):lower()
			local file = id .. ".lua"
			if FS.copy(dir .. f.name, EXT_DIR .. file) then
				installed[id] = {id = id, name = f.name:gsub("%.lua$", ""), lang = "all", version = 0, engine = "noboru", origin = "noboru", compat = "full", repo = "Lua", file = file, date = Clock.now()}
				loadExtensionFile(id, EXT_DIR .. file)
				count = count + 1
			end
		end
	end
	saveInstalled()
	touch()
	return count
end

---Languages present in the catalog (for the language filter)
function Extensions.getLanguages()
	local set, list = {}, {}
	for _, e in ipairs(catalog) do
		if not set[e.lang] then
			set[e.lang] = true
			list[#list + 1] = e.lang
		end
	end
	table.sort(list)
	table.insert(list, 1, "*")
	return list
end
