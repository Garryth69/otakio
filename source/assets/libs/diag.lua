---Automatic diagnostics in ux0:data/otakio/log.txt (through ExtLog), with nothing for the user to do:
---  * errors: everything sent to Console.error (cleaned, the same message not repeated for a while)
---  * trail: screens, dialogs, chapters opened, so the last lines show where the app was if it closes
---    (a GPU crash kills the app without any Lua error)
---  * crashes: system crash dumps (ux0:data/psp2core-*.psp2dmp) that appeared since the last session
---  * memory: free RAM / GPU memory / Lua heap whenever they change a lot
---Log lines are cleaned first: query strings of URLs, e-mail and IP addresses, tokens, cookies and passwords.
Diag = {}

-- captured at load: System leaves the global scope after startup (extension sandbox)
local getFreeRam = System.getFreeRamMemory
local listDirectory = System.listDirectory
local getFirmware = System.getVersion

local SEEN_DUMPS = Config.DATA .. "crash_dumps_seen.txt"
local MAX_ERRORS = 60 -- per session
local REPEAT_MS = 30000 -- the same error again within this time is only counted

local clock = Timer.new()
local errorsLogged = 0
local lastError = {} -- message -> {at = ms, repeats = n}
local lastCrumb = {}

---Removes what could identify the user or an account from a line
function Diag.clean(line)
	line = tostring(line or "")
	line = line:gsub("(https?://[^%s%?#\"'<>]+)[%?#][^%s\"'<>]*", "%1?...")
	line = line:gsub("[%w%._%%%+%-]+@[%w%.%-]+%.%a%a+", "<e-mail>")
	line = line:gsub("%d+%.%d+%.%d+%.%d+", "<ip>")
	for _, key in ipairs({"[Tt]oken", "[Cc]ookie", "[Pp]assword", "[Pp]ass", "[Aa]uth%a*", "[Ss]ession%a*", "[Kk]ey"}) do
		line = line:gsub("(" .. key .. "%s*[=:]%s*)[^%s,;&]+", "%1<hidden>")
	end
	return line
end

local function log(text)
	if ExtLog then
		pcall(ExtLog, text)
	end
end

---An error worth keeping (Console.error ends up here)
function Diag.error(message)
	local text = Diag.clean(message):gsub("%s+", " ")
	if #text > 400 then
		text = (string.rawsub or string.sub)(text, 1, 400) .. "..."
	end
	local now = Timer.getTime(clock)
	local seen = lastError[text]
	if seen and now - seen.at < REPEAT_MS then
		seen.repeats = seen.repeats + 1
		return
	end
	if errorsLogged >= MAX_ERRORS then
		return
	end
	errorsLogged = errorsLogged + 1
	local suffix = seen and seen.repeats > 0 and (" (and " .. seen.repeats .. " more times)") or ""
	lastError[text] = {at = now, repeats = 0}
	log("error: " .. text .. suffix)
end

---A step of the trail ("screen", "dialog", "reader"...): logged only when it changes
function Diag.trail(kind, text)
	text = Diag.clean(text)
	if lastCrumb[kind] == text then
		return
	end
	lastCrumb[kind] = text
	log("> " .. kind .. ": " .. text)
end

-- Console.error (net.lua, parsers, extensions...) also goes to the log
local consoleError = Console.error
function Console.error(message, mode)
	consoleError(message, mode)
	Diag.error(message)
end

local function mb(bytes)
	return bytes and string.format("%.0f MB", bytes / 1024 / 1024) or "?"
end

local function memoryLine()
	local okRam, ram = pcall(getFreeRam)
	local okGpu, gpu = pcall(Graphics.getFreeMemory)
	return okRam and ram, okGpu and gpu, collectgarbage("count")
end

---Crash dumps written by the system since the last session (any app; the time tells if it was Otakio)
local function newCrashDumps()
	local seen = {}
	for name in (FS.read(SEEN_DUMPS) or ""):gmatch("[^\n]+") do
		seen[name] = true
	end
	local current, fresh = {}, {}
	local ok, list = pcall(listDirectory, "ux0:data")
	for _, f in ipairs(ok and list or {}) do
		local name = f.name or ""
		if not f.directory and name:find("^psp2core%-") and name:find("%.psp2dmp$") then
			current[#current + 1] = name
			if not seen[name] then
				fresh[#fresh + 1] = name
			end
		end
	end
	FS.write(SEEN_DUMPS, table.concat(current, "\n") .. "\n")
	return fresh, next(seen) == nil
end

---Startup: version, firmware, memory, and crashes since the last time
function Diag.startup()
	local okFw, fw = pcall(getFirmware)
	local ram, gpu, lua = memoryLine()
	log(string.format("session: Otakio %s, firmware %s, free RAM %s, free GPU %s, Lua %d KB", Config.VERSION_NAME,
		okFw and tostring(fw) or "?", mb(ram), mb(gpu), lua))
	local fresh, firstTime = newCrashDumps()
	if not firstTime then
		for _, name in ipairs(fresh) do
			-- psp2core-<time>-<process>-<cause>.psp2dmp: GPUCRASH, or the module that faulted
			log("crash dump since the last session: " .. name)
		end
	end
end

local hitches, hitchWorst, hitchWorstWhere, hitchWhere = 0, 0, "", {}
local slowCalls = {} -- label -> {n = count, max = ms}

---Milliseconds since the app started (to time a call from outside)
function Diag.now()
	return Timer.getTime(clock)
end

---A step that ran for `ms` on the main thread (one coroutine resume, one call): kept when it was over 50 ms
function Diag.slow(label, ms)
	if ms < 50 then
		return
	end
	local e = slowCalls[label]
	if not e then
		e = {n = 0, max = 0}
		slowCalls[label] = e
	end
	e.n = e.n + 1
	if ms > e.max then
		e.max = ms
	end
end

local steps = {} -- this frame: step label -> ms (main.lua)
local stepClock = Timer.new()

---Starts timing one step of the frame (update of a module, the draw...), see Diag.stepEnd
function Diag.stepStart()
	Timer.reset(stepClock)
end

---Ends the step started by Diag.stepStart, under `label`
function Diag.stepEnd(label)
	steps[label] = (steps[label] or 0) + Timer.getTime(stepClock)
end

---Forgets the steps of the frame (main.lua, at the start of every frame)
function Diag.stepsReset()
	for k in pairs(steps) do
		steps[k] = nil
	end
end

local excused = false

---The current frame waited on purpose (the system keyboard was open): it is not a hitch
function Diag.excuseFrame()
	excused = true
end

---A frame that took longer than 50 ms (main.lua): counted with the screen, what was running at the time and the
---step of the frame that took the most of it
function Diag.hitch(ms, fontWarmup)
	if excused then
		excused = false
		return
	end
	hitches = hitches + 1
	local where = AppMode == READER and "reader" or tostring(Menu and Menu.getMode and Menu.getMode())
	local heavy, heavyMs = nil, 0
	for k, v in pairs(steps) do
		if v > heavyMs then
			heavy, heavyMs = k, v
		end
	end
	if heavy and heavyMs >= ms * 0.5 then
		where = where .. "@" .. heavy
	elseif ms >= 1000 then
		where = where .. "@elsewhere" -- no step holds it: input, vblank or the app paused by the system
	end
	local tags = {}
	local stage = Threads and Threads.currentStage and Threads.currentStage()
	if stage then
		tags[#tags + 1] = "net:" .. tostring(stage)
	end
	if ParserManager and ParserManager.isBusy and ParserManager.isBusy() then
		tags[#tags + 1] = "parser"
	end
	if Extensions and Extensions.isWorking and Extensions.isWorking() then
		tags[#tags + 1] = "extensions"
	end
	if fontWarmup then
		tags[#tags + 1] = "fonts"
	end
	local key = where .. (#tags > 0 and ("/" .. table.concat(tags, "+")) or "")
	hitchWhere[key] = (hitchWhere[key] or 0) + 1
	if ms > hitchWorst then
		hitchWorst, hitchWorstWhere = ms, key
	end
end

local function hitchReport()
	if hitches == 0 then
		return
	end
	local keys = {}
	for k in pairs(hitchWhere) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		return hitchWhere[a] > hitchWhere[b]
	end)
	local parts = {}
	for i = 1, math.min(4, #keys) do
		parts[#parts + 1] = keys[i] .. " x" .. hitchWhere[keys[i]]
	end
	log(string.format("hitches: %d frames over 50 ms (worst %d ms in %s): %s", hitches, hitchWorst, hitchWorstWhere,
		table.concat(parts, ", ")))
	hitches, hitchWorst, hitchWorstWhere, hitchWhere = 0, 0, "", {}
	local labels = {}
	for k in pairs(slowCalls) do
		labels[#labels + 1] = k
	end
	if #labels > 0 then
		table.sort(labels, function(a, b)
			return slowCalls[a].max > slowCalls[b].max
		end)
		local items = {}
		for i = 1, math.min(5, #labels) do
			local e = slowCalls[labels[i]]
			items[#items + 1] = string.format("%s %d ms x%d", labels[i], e.max, e.n)
		end
		log("slow steps: " .. table.concat(items, "; "))
		slowCalls = {}
	end
end

local ready = {n = 0, sum = 0, max = 0, instant = 0}
---Reader: `ms` from reaching a page to its image on screen (under 50 ms counts as instant: it was ready)
function Diag.pageReady(ms)
	ready.n = ready.n + 1
	ready.sum = ready.sum + ms
	if ms > ready.max then
		ready.max = ms
	end
	if ms < 50 then
		ready.instant = ready.instant + 1
	end
end

local function readyReport()
	if ready.n == 0 then
		return
	end
	log(string.format("page ready: %d pages, avg %d ms, worst %d ms, %d instant", ready.n, ready.sum / ready.n, ready.max, ready.instant))
	ready = {n = 0, sum = 0, max = 0, instant = 0}
end

local hosts = {} -- host -> {n, ms, bytes, gz, errors}
---Network: one finished request (engine 2+ reports time, bytes on the wire and compression)
function Diag.request(host, ms, bytes, compressed, failed)
	if not host then
		return
	end
	local h = hosts[host]
	if not h then
		h = {n = 0, ms = 0, bytes = 0, gz = 0, errors = 0}
		hosts[host] = h
	end
	h.n = h.n + 1
	h.ms = h.ms + (ms or 0)
	h.bytes = h.bytes + (bytes or 0)
	if compressed then
		h.gz = h.gz + 1
	end
	if failed then
		h.errors = h.errors + 1
	end
end

local function netReport()
	local list = {}
	for host, h in pairs(hosts) do
		list[#list + 1] = {host = host, h = h}
	end
	if #list == 0 then
		return
	end
	table.sort(list, function(a, b)
		return a.h.n > b.h.n
	end)
	local parts = {}
	for i = 1, math.min(#list, 5) do
		local e, h = list[i], list[i].h
		parts[#parts + 1] = string.format("%s %d req avg %d ms %d KB%s%s", e.host, h.n, h.ms / h.n, h.bytes / 1024,
			h.gz > 0 and (" gzip " .. h.gz) or "", h.errors > 0 and (" failed " .. h.errors) or "")
	end
	log("net: " .. table.concat(parts, "; ") .. (#list > 5 and (" (+" .. (#list - 5) .. " sites)") or ""))
	hosts = {}
end

local lastRam, lastGpu, lastCheck = nil, nil, 0
---Called every frame: every 30 s logs the slow frames, and memory when it moved by 8 MB or more
function Diag.update()
	local now = Timer.getTime(clock)
	if now - lastCheck < 30000 then
		return
	end
	lastCheck = now
	hitchReport()
	readyReport()
	netReport()
	local ram, gpu, lua = memoryLine()
	if not ram or not gpu then
		return
	end
	if not lastRam or math.abs(ram - lastRam) >= 8 * 1024 * 1024 or math.abs(gpu - lastGpu) >= 8 * 1024 * 1024 then
		lastRam, lastGpu = ram, gpu
		log(string.format("memory: free RAM %s, free GPU %s, Lua %d KB", mb(ram), mb(gpu), lua))
	end
end
