---Per-source settings, kept in ux0:data/otakio/source_prefs.json, one entry per parser ID:
---  filters  = {[filter name] = value}   the source panel's last choices (radio: tag, check: {tags}, checkcross: {include, exclude})
---  prefs    = {[key] = value}           the extension's own options (parser.Preferences, read with parser:pref(key))
---  domain   = "https://new.example"     another address for the site; every request to the original host goes there
---  base     = "https://old.example"     the original address the domain replaces
---  cache    = {[key] = value}           data an engine keeps between sessions (a site's genre list...)
---and one shared entry, __moves = {[original host] = "https://new.example"}: the sites the extension catalog says
---moved (index "movedTo", found by the daily check); kept so they apply from the start, before the catalog is fetched
SourcePrefs = {}

local PATH = "ux0:data/otakio/source_prefs.json"
local data = nil
local dirty = false
local rewrites = nil -- original host -> {scheme, host} of the replacement

local function load()
	if data then
		return data
	end
	data = {}
	local raw = FS.read(PATH)
	if raw and raw ~= "" then
		local ok, t = pcall(Json.decode, raw)
		if ok and type(t) == "table" then
			data = t
		end
	end
	return data
end

local function entry(id, create)
	local all = load()
	local key = tostring(id)
	local e = all[key]
	if not e and create then
		e = {}
		all[key] = e
	end
	return e
end

---Writes the file when something changed (cheap to call often)
function SourcePrefs.save()
	if not dirty or not data then
		return
	end
	dirty = false
	local ok, text = pcall(Json.encode, data)
	if ok and text then
		FS.write(PATH, text)
	end
end

local function changed()
	dirty = true
	rewrites = nil
	SourcePrefs.save()
end

-------------------------------------------------------------------------------
-- remembered filters
-------------------------------------------------------------------------------

function SourcePrefs.getFilters(id)
	local e = entry(id)
	return e and e.filters or nil
end

function SourcePrefs.setFilters(id, filters)
	entry(id, true).filters = filters
	changed()
end

-------------------------------------------------------------------------------
-- the extension's own options
-------------------------------------------------------------------------------

function SourcePrefs.getPref(id, key)
	local e = entry(id)
	return e and e.prefs and e.prefs[key]
end

function SourcePrefs.setPref(id, key, value)
	local e = entry(id, true)
	e.prefs = e.prefs or {}
	e.prefs[key] = value
	changed()
end

---parser:pref(key): the stored value of one of the extension's Preferences, else its Default
function Parser:pref(key)
	local v = SourcePrefs.getPref(self.ID, key)
	if v ~= nil then
		return v
	end
	for _, p in ipairs(type(self.Preferences) == "table" and self.Preferences or {}) do
		if p.Key == key then
			if p.Default ~= nil then
				return p.Default
			end
			return p.Type == "radio" and type(p.Tags) == "table" and p.Tags[1] or nil
		end
	end
	return nil
end

-------------------------------------------------------------------------------
-- engine cache (kept across sessions, cleared with the domain)
-------------------------------------------------------------------------------

function SourcePrefs.getCache(id, key)
	local e = entry(id)
	return e and e.cache and e.cache[key]
end

function SourcePrefs.setCache(id, key, value)
	local e = entry(id, true)
	e.cache = e.cache or {}
	e.cache[key] = value
	changed()
end

-------------------------------------------------------------------------------
-- alternative domain
-------------------------------------------------------------------------------

local function splitUrl(url)
	local scheme, host = tostring(url or ""):match("^(%a+)://([^/:?#]+)")
	return scheme and scheme:lower(), host and host:lower()
end

---@return string|nil the address that replaces the source's own, or nil
function SourcePrefs.getDomain(id)
	local e = entry(id)
	return e and e.domain or nil
end

---Sets (or clears, with nil/"") the address used instead of `base` (the parser's Link)
---@return boolean false when `domain` is not an http(s) address
function SourcePrefs.setDomain(id, base, domain)
	domain = tostring(domain or ""):match("^%s*(.-)%s*$")
	local e = entry(id, true)
	if domain == "" then
		e.domain, e.base = nil, nil
	else
		if not domain:find("^%a+://") then
			domain = "https://" .. domain
		end
		local scheme, host = splitUrl(domain)
		if not host or (scheme ~= "http" and scheme ~= "https") then
			return false
		end
		e.domain = scheme .. "://" .. host
		e.base = base
	end
	-- what was learned from the old address (genre lists...) may not hold for the new one
	e.cache = nil
	changed()
	return true
end

local function buildRewrites()
	rewrites = {}
	-- moves the catalog knows about first; an address the user set for a source wins over them
	for from, to in pairs(type(load().__moves) == "table" and load().__moves or {}) do
		local scheme, host = splitUrl(to)
		if host and host ~= from then
			rewrites[from] = {scheme = scheme, host = host}
		end
	end
	for _, e in pairs(load()) do
		if type(e) == "table" and e.domain and e.base then
			local _, from = splitUrl(e.base)
			local scheme, host = splitUrl(e.domain)
			if from and host and from ~= host then
				rewrites[from] = {scheme = scheme, host = host}
			end
		end
	end
end

---The catalog's moves: {[original base address] = new address}. Written only when they change.
function SourcePrefs.setMoves(moves)
	local map, same = {}, true
	local old = type(load().__moves) == "table" and load().__moves or {}
	for from, to in pairs(type(moves) == "table" and moves or {}) do
		local _, fromHost = splitUrl(from)
		local scheme, toHost = splitUrl(to)
		if fromHost and toHost and fromHost ~= toHost and (scheme == "http" or scheme == "https") then
			map[fromHost] = scheme .. "://" .. toHost
			same = same and old[fromHost] == map[fromHost]
		end
	end
	for k in pairs(old) do
		same = same and map[k] ~= nil
	end
	if not same then
		load().__moves = next(map) and map or nil
		changed()
	end
end

---@return string|nil the address the catalog says the site at `base` moved to
function SourcePrefs.movedTo(base)
	local _, host = splitUrl(base)
	local moves = load().__moves
	return host and type(moves) == "table" and moves[host] or nil
end

---A link (or header value) pointing at a source whose address was replaced, pointed at the new address.
---Only the scheme and host change; paths and queries stay.
function SourcePrefs.rewrite(url)
	if type(url) ~= "string" or url == "" then
		return url
	end
	if not rewrites then
		buildRewrites()
	end
	if not next(rewrites) then
		return url
	end
	return (url:gsub("^(%a+)://([^/:?#]+)", function(scheme, host)
		local r = rewrites[host:lower()]
		if r then
			return r.scheme .. "://" .. r.host
		end
	end, 1))
end

---Same for a header line ("Referer: https://old.example/"); other headers are returned unchanged
function SourcePrefs.rewriteHeader(header)
	if type(header) ~= "string" or header == "" then
		return header
	end
	local name, value = header:match("^([%w%-]+):%s*(.*)$")
	if name and (name:lower() == "referer" or name:lower() == "origin") then
		return name .. ": " .. SourcePrefs.rewrite(value)
	end
	return header
end
