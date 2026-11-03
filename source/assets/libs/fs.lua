---File system + clock helpers. System/os are removed from the global scope after
---startup (to sandbox extensions), so everything is captured here as upvalues.
FS = {}

local openFile, closeFile, readFile, writeFile, sizeFile = System.openFile, System.closeFile, System.readFile, System.writeFile, System.sizeFile
local doesFileExist, doesDirExist, deleteFile, createDirectory, listDirectory = System.doesFileExist, System.doesDirExist, System.deleteFile, System.createDirectory, System.listDirectory
local rename = System.rename

function FS.exists(path)
	return doesFileExist(path)
end

function FS.dirExists(path)
	return doesDirExist(path)
end

function FS.read(path)
	if not doesFileExist(path) then
		return nil
	end
	local fh = openFile(path, FREAD)
	if not fh then
		return nil
	end
	local size = sizeFile(fh)
	local data = size > 0 and readFile(fh, size) or ""
	closeFile(fh)
	return data
end

---Writes atomically-ish: temp file first, then replace
function FS.write(path, data)
	local tmp = path .. ".tmp"
	if doesFileExist(tmp) then
		deleteFile(tmp)
	end
	local fh = openFile(tmp, FCREATE)
	if not fh then
		return false
	end
	writeFile(fh, data, #data)
	closeFile(fh)
	if doesFileExist(path) then
		deleteFile(path)
	end
	if rename then
		rename(tmp, path)
	else
		local fh2 = openFile(path, FCREATE)
		writeFile(fh2, data, #data)
		closeFile(fh2)
		deleteFile(tmp)
	end
	return true
end

function FS.delete(path)
	if doesFileExist(path) then
		deleteFile(path)
	end
end

function FS.mkdir(path)
	if not doesDirExist(path) then
		createDirectory(path)
	end
end

function FS.list(path)
	if not doesDirExist(path) then
		return {}
	end
	return listDirectory(path) or {}
end

function FS.copy(src, dest)
	local data = FS.read(src)
	if not data then
		return false
	end
	return FS.write(dest, data)
end

---Serializes a Lua table to disk (fast loading with `load`)
function FS.saveTable(path, t)
	return FS.write(path, "return " .. table.serialize(t, true))
end

function FS.loadTable(path)
	local data = FS.read(path)
	if not data or data == "" then
		return nil
	end
	local fn = load(data)
	if not fn then
		return nil
	end
	local ok, result = pcall(fn)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

Clock = {}
local osTime, osDate = os.time, os.date

function Clock.now()
	return osTime()
end

function Clock.date(fmt, t)
	return osDate(fmt, t)
end

---Human readable relative time ("5 min", "2 d", or the date)
function Clock.relative(t)
	if not t then
		return ""
	end
	local L = Language[Settings.Language].OTAKIO
	local d = osTime() - t
	if d < 60 then
		return L.JUST_NOW
	elseif d < 3600 then
		return string.format(L.MINUTES_AGO, math.floor(d / 60))
	elseif d < 86400 then
		return string.format(L.HOURS_AGO, math.floor(d / 3600))
	elseif d < 86400 * 7 then
		return string.format(L.DAYS_AGO, math.floor(d / 86400))
	end
	return osDate("%d/%m/%Y", t)
end

---Day bucket label for grouped lists (Today, Yesterday, date)
function Clock.dayLabel(t)
	local L = Language[Settings.Language].OTAKIO
	local today = osDate("*t")
	local startToday = osTime({year = today.year, month = today.month, day = today.day, hour = 0})
	if t >= startToday then
		return L.TODAY
	elseif t >= startToday - 86400 then
		return L.YESTERDAY
	end
	return osDate("%d/%m/%Y", t)
end
