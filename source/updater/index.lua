-- Otakio Updater (title OTAK00002): installs an Otakio update while Otakio itself is closed.
-- The Vita's installer can't replace an app that is running, so Otakio prepares the package, installs this small
-- helper (same engine, this script), opens it and quits. The helper installs the package, checks the installed
-- version, writes the result for Otakio and reopens it. Otakio then removes the helper.
--
-- Job file (written by Otakio, source/assets/libs/appupdate.lua):
--   line 1: package folder (extracted VPK)   line 2: expected APP_VER   line 3: VPK file (kept for VitaShell on failure)
--   line 4: VPK file name for ux0:/vpk/   line 5: version name shown on screen (e.g. 1.1.1)

local OTAKIO = "OTAK00001"
local DIR = "ux0:data/otakio/update/"
local JOB = DIR .. "job.txt"
local RESULT = "ux0:data/otakio/update_result.txt"

local BG = Color.new(20, 13, 34)
local ACCENT = Color.new(176, 140, 255)
local TEXT = Color.new(236, 232, 250)
local DIM = Color.new(160, 150, 190)

local function show(title, line1, line2)
	-- both buffers, so the message stays while the installer blocks
	for _ = 1, 2 do
		Graphics.initBlend()
		Screen.clear(BG)
		Graphics.debugPrint(60, 200, title, ACCENT, 1.6)
		if line1 then
			Graphics.debugPrint(60, 260, line1, TEXT)
		end
		if line2 then
			Graphics.debugPrint(60, 292, line2, DIM)
		end
		Graphics.termBlend()
		Screen.flip()
		Screen.waitVblankStart()
	end
end

local function readFile(path)
	if not System.doesFileExist(path) then
		return nil
	end
	local fh = System.openFile(path, FREAD)
	local size = System.sizeFile(fh)
	local data = size > 0 and System.readFile(fh, size) or ""
	System.closeFile(fh)
	return data
end

local function writeFile(path, data)
	if System.doesFileExist(path) then
		System.deleteFile(path)
	end
	local fh = System.openFile(path, FCREATE)
	System.writeFile(fh, data, #data)
	System.closeFile(fh)
end

local function removeTree(path)
	if not System.doesDirExist(path) then
		return
	end
	for _, f in ipairs(System.listDirectory(path) or {}) do
		local p = path .. "/" .. f.name
		if f.directory then
			removeTree(p)
		else
			System.deleteFile(p)
		end
	end
	System.deleteDirectory(path)
end

local function installedVersion()
	local sfo = "ux0:app/" .. OTAKIO .. "/sce_sys/param.sfo"
	if not System.doesFileExist(sfo) then
		return nil
	end
	local ok, info = pcall(System.extractSfo, sfo)
	return ok and type(info) == "table" and info.version or nil
end

local function finish(result)
	writeFile(RESULT, result)
	System.wait(1500000)
	System.launchApp(OTAKIO)
	System.exit()
end

local job = readFile(JOB)
if not job then
	show("Otakio Updater", "Nothing to install.", "Opening Otakio...")
	finish("none")
end
local lines = {}
for l in job:gmatch("[^\r\n]+") do
	lines[#lines + 1] = l
end
local pkg, expected, vpk, vpkName = lines[1], lines[2], lines[3], lines[4]
local shown = lines[5] or expected or ""

show("Installing Otakio " .. shown, "Please don't turn off the system.", "Otakio reopens when it's done.")
-- give Otakio a moment to close completely
System.wait(2000000)

local installed = false
for attempt = 1, 3 do
	if pkg and System.doesDirExist(pkg) then
		pcall(System.installApp, pkg)
	end
	-- the installer may still be finishing: watch the installed version for a few seconds
	for _ = 1, 10 do
		if installedVersion() == expected then
			installed = true
			break
		end
		System.wait(500000)
	end
	if installed then
		break
	end
	show("Installing Otakio " .. shown, "Retrying (" .. attempt .. "/3)...", "Please don't turn off the system.")
	System.wait(2000000)
end

if installed then
	removeTree(DIR)
	show("Otakio updated", "Version " .. shown .. " installed.", "Opening Otakio...")
	finish("ok " .. expected)
else
	-- leave the VPK where VitaShell finds it
	if vpk and vpkName and System.doesFileExist(vpk) then
		if not System.doesDirExist("ux0:/vpk") then
			System.createDirectory("ux0:/vpk")
		end
		local dest = "ux0:/vpk/" .. vpkName
		if System.doesFileExist(dest) then
			System.deleteFile(dest)
		end
		System.rename(vpk, dest)
	end
	removeTree(DIR)
	show("Update not installed", "The VPK is in ux0:/vpk/ - install it with VitaShell.", "Opening Otakio...")
	System.wait(3000000)
	finish("failed")
end
