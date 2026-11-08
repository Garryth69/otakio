local doesDirExist = System.doesDirExist
local listDirectory = System.listDirectory
local deleteFile = System.deleteFile
local deleteDirectory = System.deleteDirectory

DRAW_PHASE = false

local oldInit = Graphics.initBlend
local oldTerm = Graphics.termBlend

function Graphics.initBlend()
	DRAW_PHASE = true
	oldInit()
end

function Graphics.termBlend()
	DRAW_PHASE = false
	oldTerm()
end

---@param path string
---DFS directory removing
local function removeDirectory(path)
	if doesDirExist(path) then
		local dir = listDirectory(path) or {}
		for i = 1, #dir do
			local f = dir[i]
			if f.directory then
				removeDirectory(path .. "/" .. f.name)
			else
				deleteFile(path .. "/" .. f.name)
			end
		end
		deleteDirectory(path)
	end
end

RemoveDirectory = removeDirectory

-- app management stays out of reach of extensions; only the updater (appupdate.lua) takes these, then clears AppTools
AppTools = {checkApp = System.checkApp, removeApp = System.removeApp}
System.removeApp = nil
System.checkApp = nil

local df = dofile
function loadlib(str)
	df("app0:assets/libs/" .. str .. ".lua")
end

local suc, err = xpcall(dofile, debug.traceback, "app0:main.lua")
if not suc then
	if DRAW_PHASE then
		oldTerm()
	end
	error(err)
end
