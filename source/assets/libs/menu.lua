---Navigation rail + screen routing.
Menu = {}

StarIcon = Image:new(Graphics.loadImage("app0:assets/icons/star.png"))
MiniStarIcon = Image:new(Graphics.loadImage("app0:assets/icons/mini_star.png"))
HistoryIcon = Image:new(Graphics.loadImage("app0:assets/icons/history.png"))
ImportIcon = Image:new(Graphics.loadImage("app0:assets/icons/import.png"))
HotIcon = Image:new(Graphics.loadImage("app0:assets/icons/hot.png"))
SearchIcon = Image:new(Graphics.loadImage("app0:assets/icons/search.png"))
AZIcon = Image:new(Graphics.loadImage("app0:assets/icons/az.png"))
LetterAIcon = Image:new(Graphics.loadImage("app0:assets/icons/a.png"))
TagIcon = Image:new(Graphics.loadImage("app0:assets/icons/tag.png"))
BackIcon = Image:new(Graphics.loadImage("app0:assets/icons/back.png"))
RefreshIcon = Image:new(Graphics.loadImage("app0:assets/icons/refresh.png"))

CheckboxIcon = Image:new(Graphics.loadImage("app0:assets/icons/checkbox.png"))
CheckboxCheckedIcon = Image:new(Graphics.loadImage("app0:assets/icons/checkbox_checked.png"))
CheckboxCrossedIcon = Image:new(Graphics.loadImage("app0:assets/icons/checkbox_crossed.png"))
RadioIcon = Image:new(Graphics.loadImage("app0:assets/icons/radio.png"))
RadioCheckedIcon = Image:new(Graphics.loadImage("app0:assets/icons/radio_checked.png"))
ShowIcon = Image:new(Graphics.loadImage("app0:assets/icons/show.png"))
HideIcon = Image:new(Graphics.loadImage("app0:assets/icons/hide.png"))

DownloadIcon = Image:new(Graphics.loadImage("app0:assets/icons/download.png"))
OptionsIcon = Image:new(Graphics.loadImage("app0:assets/icons/options.png"))

local NAV = {
	{mode = "LIBRARY", icon = "nav_library", label = "LIBRARY"},
	{mode = "UPDATES", icon = "nav_updates", label = "UPDATES"},
	{mode = "HISTORY", icon = "nav_history", label = "HISTORY"},
	{mode = "CATALOGS", icon = "nav_browse", label = "BROWSE"},
	{mode = "EXTENSIONS", icon = "nav_extensions", label = "EXTENSIONS"},
	{mode = "DOWNLOAD", icon = "nav_downloads", label = "DOWNLOADS"},
	{mode = "IMPORT", icon = "nav_import", label = "IMPORT"},
	{mode = "SETTINGS", icon = "nav_more", label = "MORE"}
}
for _, item in ipairs(NAV) do
	item.image = Image:new(Graphics.loadImage("app0:assets/icons/" .. item.icon .. ".png"))
end

local NAV_INDEX = {}
for i, item in ipairs(NAV) do
	NAV_INDEX[item.mode] = i
end
NAV_INDEX.GLOBALSEARCH = NAV_INDEX.CATALOGS
NAV_INDEX.MANGA = NAV_INDEX.CATALOGS

local ITEM_H = 63
local RAIL_TOP = 4
local RAIL_W = Config.RAIL_WIDTH

---@type string
local mode
local pillY = RAIL_TOP

local function isScreen(m)
	return Screens[m] ~= nil
end

function Menu.getMode()
	return mode
end

---@param newMode string
---Sets menu mode
function Menu.setMode(newMode)
	if mode == newMode then
		return
	end
	if mode and isScreen(mode) and Screens[mode].onLeave then
		Screens[mode].onLeave()
	end
	if not isScreen(newMode) then
		Catalogs.setStatus(newMode)
	elseif mode and not isScreen(mode) then
		-- leaving a Catalogs screen: release its covers
		Catalogs.setStatus("NONE")
	end
	mode = newMode
	if isScreen(mode) and Screens[mode].onEnter then
		Screens[mode].onEnter()
	end
end

local function step(delta)
	local idx = NAV_INDEX[mode] or 1
	idx = math.max(1, math.min(#NAV, idx + delta))
	Menu.setMode(NAV[idx].mode)
end

function Menu.input(oldPad, pad, oldTouch, touch)
	if Details.getStatus() ~= "END" then
		Details.input(oldPad, pad, oldTouch, touch)
		return
	end
	if CatalogModes.getStatus() ~= "END" then
		CatalogModes.input(pad, oldPad, touch, oldTouch)
		return
	end
	if Controls.check(pad, SCE_CTRL_RTRIGGER) and not Controls.check(oldPad, SCE_CTRL_RTRIGGER) then
		step(1)
	elseif Controls.check(pad, SCE_CTRL_LTRIGGER) and not Controls.check(oldPad, SCE_CTRL_LTRIGGER) then
		step(-1)
	end
	if touch.x and not oldTouch.x and touch.x < RAIL_W then
		local idx = math.floor((touch.y - RAIL_TOP) / ITEM_H) + 1
		if NAV[idx] then
			Menu.setMode(NAV[idx].mode)
		end
	end
	if isScreen(mode) then
		Screens[mode].input(oldPad, pad, oldTouch, touch)
	else
		Catalogs.input(oldPad, pad, oldTouch, touch)
	end
end

function Menu.update()
	if isScreen(mode) then
		Screens[mode].update()
	else
		Catalogs.update()
	end
	Details.update()
	CatalogModes.update()
	local target = RAIL_TOP + ((NAV_INDEX[mode] or 1) - 1) * ITEM_H
	pillY = UI.approach(pillY, target, 0.3)
end

local function badgeFor(item)
	if item.mode == "UPDATES" then
		return Updates.getUnseen()
	elseif item.mode == "EXTENSIONS" then
		return Extensions.countUpdates()
	elseif item.mode == "DOWNLOAD" then
		return #ChapterSaver.getDownloadingList()
	end
	return 0
end

local function drawRail()
	local O = Language[Settings.Language].OTAKIO
	Graphics.fillRect(0, RAIL_W, 0, 544, COLOR_RAIL)
	-- sliding selection pill
	local cx = RAIL_W / 2
	UI.roundRect(cx - 28, pillY + 6, cx + 28, pillY + 38, 16, COLOR_ACCENT_SOFT)
	local current = NAV_INDEX[mode] or 1
	for i, item in ipairs(NAV) do
		local y = RAIL_TOP + (i - 1) * ITEM_H
		local active = i == current
		UI.icon(item.image, cx - 14, y + 8, active and COLOR_ACCENT or COLOR_SUBFONT)
		local label = O.NAV[item.label] or item.label
		UI.textCenter(FONT13, cx, y + 42, label, active and COLOR_FONT or COLOR_SUBFONT, RAIL_W - 6)
		local b = badgeFor(item)
		if b > 0 then
			local bg = item.mode == "DOWNLOAD" and COLOR_ACCENT or COLOR_DANGER
			UI.badge(cx + 18, y + 10, b, bg, COLOR_WHITE)
		end
	end
	if Settings.Incognito then
		UI.roundRect(4, 530, RAIL_W - 4, 543, 6, COLOR_SURFACE2)
	end
	Graphics.fillRect(RAIL_W - 1, RAIL_W, 0, 544, COLOR_DIVIDER)
end

function Menu.draw()
	Screen.clear(COLOR_BACK)
	if Details.getFade() ~= 1 then
		if isScreen(mode) then
			Graphics.fillRect(RAIL_W, 960, 0, 544, COLOR_BACK)
			Screens[mode].draw()
		else
			Catalogs.draw()
		end
		drawRail()
	end
	CatalogModes.draw()
	Details.draw()
end
