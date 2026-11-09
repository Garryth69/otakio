-- Otakio Updater (title OTAK00002): installs an Otakio update while Otakio itself is closed.
-- The Vita's installer can't replace an app that is running, so Otakio prepares the package, installs this small
-- helper (same engine, this script), opens it and quits. The helper installs the package, checks the installed
-- version, writes the result for Otakio and reopens it. Otakio then removes the helper.
--
-- Job file (written by Otakio, source/assets/libs/appupdate.lua):
--   line 1: package folder (extracted VPK)   line 2: expected APP_VER   line 3: VPK file (kept for VitaShell on failure)
--   line 4: VPK file name for ux0:data/otakio/vpk/   line 5: version name shown on screen (e.g. 1.1.1)

local OTAKIO = "OTAK00001"
local DIR = "ux0:data/otakio/update/"
local JOB = DIR .. "job.txt"
local RESULT = "ux0:data/otakio/update_result.txt"
local VPK_DIR = "ux0:data/otakio/vpk" -- a VPK that couldn't be installed, for VitaShell

-- Otakio theme colors, and the app's Roboto (cut down to Latin: regular.ttf / bold.ttf, tools/make_updater_fonts.py)
local BG = Color.new(20, 13, 34)
local SURFACE = Color.new(36, 24, 58)
local TRACK = Color.new(52, 36, 80)
local ACCENT = Color.new(168, 120, 255)
local TEXT = Color.new(240, 234, 250)
local DIM = Color.new(168, 152, 198)

local function loadFont(name, size)
	if not System.doesFileExist("app0:" .. name) then
		return nil
	end
	local ok, font = pcall(Font.load, "app0:" .. name)
	if ok and font then
		Font.setPixelSizes(font, size)
		return font
	end
	return nil
end
local TITLE_FONT = loadFont("bold.ttf", 30)
local BODY_FONT = loadFont("regular.ttf", 20)

local function text(font, x, y, str, color, scale)
	if font then
		Font.print(font, x, y, str, color)
	else
		Graphics.debugPrint(x, y, str, color, scale) -- fonts missing: the engine's built-in one
	end
end

-- a card like the app's update panel
local X0, X1, Y0, Y1 = 120, 840, 160, 384

---progress: nil (no bar) or 0-1
local function show(title, line1, line2, progress)
	-- both buffers, so the message stays while the installer blocks
	for _ = 1, 2 do
		Graphics.initBlend()
		Screen.clear(BG)
		Graphics.fillRect(X0, X1, Y0, Y1, SURFACE)
		text(TITLE_FONT, X0 + 28, Y0 + 24, title, TEXT, 1.6)
		if line1 then
			text(BODY_FONT, X0 + 28, Y0 + 80, line1, TEXT)
		end
		if line2 then
			text(BODY_FONT, X0 + 28, Y0 + 110, line2, DIM)
		end
		if progress then
			Graphics.fillRect(X0 + 28, X1 - 28, Y0 + 170, Y0 + 182, TRACK)
			if progress > 0 then
				Graphics.fillRect(X0 + 28, X0 + 28 + (X1 - X0 - 56) * math.min(1, progress), Y0 + 170, Y0 + 182, ACCENT)
			end
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
	System.wait(500000)
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

local clock = Timer.new()
show("Installing Otakio " .. shown, "Step 1 of 2: installing. This takes about a minute.", "Please don't turn off the system. Otakio reopens when it's done.", 0.05)
-- give Otakio a moment to close completely
System.wait(1000000)

local installed = false
for attempt = 1, 3 do
	if pkg and System.doesDirExist(pkg) then
		pcall(System.installApp, pkg)
	end
	show("Installing Otakio " .. shown, "Step 2 of 2: checking the installed version...", "Please don't turn off the system.", 0.85)
	-- the installer may still be finishing: watch the installed version for a few seconds
	for _ = 1, 20 do
		if installedVersion() == expected then
			installed = true
			break
		end
		System.wait(250000)
	end
	if installed then
		break
	end
	show("Installing Otakio " .. shown, "Retrying (" .. attempt .. "/3)...", "Please don't turn off the system.", 0.05)
	System.wait(2000000)
end

if installed then
	removeTree(DIR)
	show("Otakio updated", "Version " .. shown .. " installed.", "Opening Otakio...", 1)
	finish("ok " .. expected .. " " .. math.floor(Timer.getTime(clock)) .. "ms")
else
	-- leave the VPK where VitaShell finds it
	if vpk and vpkName and System.doesFileExist(vpk) then
		if not System.doesDirExist(VPK_DIR) then
			System.createDirectory(VPK_DIR)
		end
		local dest = VPK_DIR .. "/" .. vpkName
		if System.doesFileExist(dest) then
			System.deleteFile(dest)
		end
		System.rename(vpk, dest)
	end
	removeTree(DIR)
	show("Update not installed", "The VPK is in ux0:data/otakio/vpk/ - install it with VitaShell.", "Opening Otakio...")
	System.wait(3000000)
	finish("failed")
end
