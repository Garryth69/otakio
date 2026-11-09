---Data migrations: keeps ux0:data/otakio readable by every new version.
---
---ux0:data/otakio/data_version.txt holds the version of the data on the memory card. At startup, before anything is
---loaded, each step newer than it runs in order. Step N turns version N-1 data into version N, and must be safe to run
---twice. Before the first real step the data files are copied to backups/pre-migration-<N>/. If a step fails, they
---are copied back, the version stays where it was, and the app starts with the data untouched (details in log.txt).
---A card written by a newer Otakio (version above CURRENT) is left alone.
---
---To change a data format later: bump CURRENT, add STEPS[CURRENT] = {name = "...", run = function(dir) ... end}.
Migrations = {}

Migrations.CURRENT = 1

local STEPS = {
	-- 1.1.2: first numbered version. Data written by Otakio 1.0 - 1.1.2 already is in this format.
	[1] = {name = "baseline", baseline = true, run = function()
	end}
}

-- files and folders whose top-level files hold the data a migration may rewrite (chapters and images are never touched)
local DATA_FOLDERS = {"", "cache/", "cusettings/"}

local function log(msg)
	if ExtLog then
		pcall(ExtLog, "data: " .. msg)
	end
end

local function readVersion(dir)
	local text = FS.read(dir .. "data_version.txt")
	return text and tonumber(text:match("%d+")) or nil
end

local function writeVersion(dir, v)
	FS.write(dir .. "data_version.txt", tostring(v) .. "\n")
end

local function snapshot(dir, to)
	FS.mkdir(to)
	for _, sub in ipairs(DATA_FOLDERS) do
		if sub ~= "" then
			FS.mkdir(to .. sub)
		end
		for _, f in ipairs(FS.list(dir .. sub)) do
			if not f.directory then
				FS.copy(dir .. sub .. f.name, to .. sub .. f.name)
			end
		end
	end
end

local function restoreSnapshot(dir, from)
	for _, sub in ipairs(DATA_FOLDERS) do
		for _, f in ipairs(FS.list(from .. sub)) do
			if not f.directory then
				FS.copy(from .. sub .. f.name, dir .. sub .. f.name)
			end
		end
	end
end

---@param opts table|nil {dir = data folder, steps = table, current = number} (tests pass their own)
---@return string result "fresh" | "current" | "migrated" | "failed" | "newer"
function Migrations.run(opts)
	opts = opts or {}
	local dir = opts.dir or Config.DATA
	local steps = opts.steps or STEPS
	local current = opts.current or Migrations.CURRENT
	local stored = readVersion(dir)
	if not stored then
		if not FS.exists(dir .. "settings.ini") then
			-- fresh install: nothing to convert
			writeVersion(dir, current)
			return "fresh"
		end
		stored = 0 -- data from before versioned data (Otakio 1.0 - 1.1.1)
	end
	if stored == current then
		return "current"
	elseif stored > current then
		log("data version " .. stored .. " is newer than this app (" .. current .. "): left as it is")
		Migrations.newer = true
		return "newer"
	end
	local backupDir = nil
	for v = stored + 1, current do
		local step = steps[v]
		if step and not step.baseline and not backupDir then
			backupDir = dir .. "backups/pre-migration-" .. v .. "/"
			snapshot(dir, backupDir)
			log("copied the data to " .. backupDir)
		end
		local ok, err = true, nil
		if step then
			ok, err = pcall(step.run, dir)
		end
		if not ok then
			log("step " .. v .. " (" .. tostring(step.name) .. ") failed: " .. tostring(err))
			if backupDir then
				restoreSnapshot(dir, backupDir)
				log("restored the data from " .. backupDir)
			end
			Migrations.failed = true
			return "failed"
		end
		writeVersion(dir, v)
		log("updated the data to version " .. v .. (step and step.name and (" (" .. step.name .. ")") or ""))
	end
	return "migrated"
end

---After startup: tells the user when the data could not be updated (once)
function Migrations.notify()
	if Migrations.failed and Notifications and Language then
		Migrations.failed = nil
		local O = Language[Settings.Language].OTAKIO
		Notifications.push(O.DATA_MIGRATION_FAILED or "Couldn't update your data; it was kept as it was (see log.txt)", 8000)
	end
end
