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

---A frame that took longer than 50 ms (main.lua): counted with the screen and what was running at the time
function Diag.hitch(ms, fontWarmup)
	hitches = hitches + 1
	local where = AppMode == READER and "reader" or tostring(Menu and Menu.getMode and Menu.getMode())
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
	local ram, gpu, lua = memoryLine()
	if not ram or not gpu then
		return
	end
	if not lastRam or math.abs(ram - lastRam) >= 8 * 1024 * 1024 or math.abs(gpu - lastGpu) >= 8 * 1024 * 1024 then
		lastRam, lastGpu = ram, gpu
		log(string.format("memory: free RAM %s, free GPU %s, Lua %d KB", mb(ram), mb(gpu), lua))
	end
end
