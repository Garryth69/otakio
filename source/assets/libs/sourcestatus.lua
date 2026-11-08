---Per-source health shown as a small colored dot:
---  "ok" (green) works, "unstable" (yellow) works sometimes or only partly, "broken" (red) doesn't work.
---What the console itself observes (listing, chapters, pages) takes priority over the PC health check
---shipped in the repository index. Only the latest results count, so a source that breaks or comes back
---changes color by itself; installed sources are also re-checked quietly in the background.
SourceStatus = {}

local PATH = Config.DATA .. "sources.dat"
local records = nil -- extension id -> {ok = n, fail = n, last = "ok"|"fail", streak = consecutive fails, recent = "1101", t = Clock.now()}
local RECENT = 6 -- results kept per source
local RECHECK = 6 * 3600 -- background re-check interval per installed source (seconds)
local dirty = false
local saveTimer = Timer.new()

local function load()
	if not records then
		records = FS.loadTable(PATH) or {}
	end
	return records
end

---@param parser table|nil
---@return string|nil extension id (or the parser ID for classic parsers)
local function keyOf(parser)
	return parser and (parser.ExtensionID or parser.ID)
end

---Records the outcome of a parser call made by the app
---@param parser table
---@param success boolean
function SourceStatus.record(parser, success)
	local key = keyOf(parser)
	if not key then
		return
	end
	local r = load()[key]
	if not r then
		r = {ok = 0, fail = 0, streak = 0}
		records[key] = r
	end
	if success then
		r.ok = math.min(r.ok + 1, 999)
		r.streak = 0
		r.last = "ok"
	else
		r.fail = math.min(r.fail + 1, 999)
		r.streak = r.streak + 1
		r.last = "fail"
	end
	r.recent = string.rawsub((r.recent or "") .. (success and "1" or "0"), -RECENT)
	r.t = Clock.now()
	dirty = true
end

-- background check: one installed source at a time, only while the app is otherwise idle
local probe = nil -- {parser =, list =}
local probeTimer = Timer.new()
-- every installed source is checked once right after the app opens, then every RECHECK seconds
local launchTime = nil
local tried = {} -- key -> time of the last background attempt (a cancelled check doesn't record a result)

local function nextStale()
	local now = Clock.now()
	launchTime = launchTime or now
	local best, bestT = nil, nil
	for _, p in ipairs(GetAllParsers and GetAllParsers() or {}) do
		local key = keyOf(p)
		local r = key and load()[key]
		local t = r and r.t or 0
		if key and not (tried[key] and now - tried[key] < RECHECK) and p.getPopularManga and (not p.NSFW or Settings.NSFW) and (t < launchTime or now - t > RECHECK) and (not bestT or t < bestT) then
			best, bestT = p, t
		end
	end
	return best
end

local function backgroundCheck()
	if probe then
		if not ParserManager.check(probe.list) then
			probe = nil
			Timer.reset(probeTimer)
		end
		return
	end
	-- wait a bit between sources and stay out of the way of the reader and real requests
	if Timer.getTime(probeTimer) < 1500 or AppMode == READER or ParserManager.isBusy and ParserManager.isBusy() then
		return
	end
	Timer.reset(probeTimer)
	if not Threads.isOnline() then
		return
	end
	local p = nextStale()
	if p then
		tried[keyOf(p)] = Clock.now()
		probe = {parser = p, list = {}}
		ParserManager.getMangaListAsync("Popular", p, 1, probe.list)
		ParserManager.setBackground(probe.list)
	end
end

---Saves at most every few seconds (called from the main loop)
function SourceStatus.update()
	backgroundCheck()
	if dirty and Timer.getTime(saveTimer) > 5000 then
		FS.saveTable(PATH, records)
		dirty = false
		Timer.reset(saveTimer)
	end
end

local FROM_HEALTH = {ok = "ok", partial = "unstable", relay = "unstable", dead = "broken"}

---@param id string extension id
---@param entry table|nil catalog/installed metadata (health, compat)
---@return string "ok" | "unstable" | "broken"
function SourceStatus.of(id, entry)
	local r = id and load()[id]
	if r and r.recent and r.recent ~= "" then
		local last2 = string.rawsub(r.recent, -2)
		if last2 == "11" or (r.recent == "1") then
			-- the latest attempts worked: green, unless it failed a lot just before
			return select(2, string.gsub(r.recent, "0", "")) >= 2 and "unstable" or "ok"
		end
		if last2 == "00" and not string.find(r.recent, "1", 1, true) then
			return "broken"
		end
		if string.rawsub(r.recent, -3) == "000" then
			return "broken"
		end
		return "unstable"
	elseif r then
		-- records saved before the recent history existed
		if r.streak >= 2 and r.ok == 0 then
			return "broken"
		end
		if r.ok > 0 and r.fail == 0 then
			return "ok"
		end
		if r.ok > 0 then
			return (r.streak >= 3) and "broken" or "unstable"
		end
	end
	if entry then
		if entry.compat == "broken" then
			return "broken"
		end
		local h = FROM_HEALTH[entry.health or ""]
		if h then
			return h
		end
	end
	-- never checked: may work
	return "unstable"
end

---Small status dot (radius 6) centered at cx, cy
function SourceStatus.drawDot(cx, cy, status)
	local color = (status == "ok" and COLOR_SUCCESS) or (status == "broken" and COLOR_DANGER) or COLOR_WARNING
	Graphics.fillCircle(cx, cy, 7, COLOR_SURFACE)
	Graphics.fillCircle(cx, cy, 5, color)
end

---Sort weight: working sources first
function SourceStatus.rank(status)
	return (status == "ok" and 0) or (status == "unstable" and 1) or 2
end
