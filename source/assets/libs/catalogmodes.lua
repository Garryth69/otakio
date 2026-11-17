CatalogModes = {}
local status = "END"

local fade = 0
local oldFade = 0

local animationTimer = Timer.new()

local modes = {}
local modesFade = {}
local Name = ""

local currentFilters = {}
local currentChecked = {}
local currentLetters = {}
local currentLettersIndex = 1
local currentFinalLetter = 1
local currentTags = {}
local currentTagsIndex = 1
local currentFinalTag = 1
local currentFinalTagsData = {}

local itemsToDraw = {}

local nowMode = 1
local TOUCH_MODES = TOUCH_MODES
local slider = CreateSlider()
local selectedIndex = 0
local controlTimer = Timer.new()
local controlInterval = 400
local searchData = ""
local currentParser = nil

local function LO()
	return Language[Settings.Language].OTAKIO
end

---Common filter words ("Sort By", "Completed"...) in the interface language; anything else as the extension wrote it
local function tr(text)
	local words = Language[Settings.Language].FILTER_WORDS
	return words and words[text] or text
end

local function setFinalTags()
	local filter = {}
	for j = 1, #currentFilters do
		local f = currentFilters[j]
		if f.Setting then
			-- source settings are not search filters
		elseif f.Type == "check" then
			local list = {}
			for i = 1, #currentChecked[j] do
				if currentChecked[j][i] then
					list[#list + 1] = f.Tags[i]
				end
			end
			filter[#filter + 1] = list
			filter[f.Name] = list
		elseif f.Type == "checkcross" then
			local include = {}
			for i = 1, #currentChecked[j] do
				if currentChecked[j][i] == true then
					include[#include + 1] = f.Tags[i]
				end
			end
			local exclude = {}
			for i = 1, #currentChecked[j] do
				if currentChecked[j][i] == "cross" then
					exclude[#exclude + 1] = f.Tags[i]
				end
			end
			filter[#filter + 1] = {
				include = include,
				exclude = exclude
			}
			filter[f.Name] = filter[#filter]
		elseif f.Type == "radio" then
			filter[#filter + 1] = f.Tags[currentChecked[j]] or ""
			filter[f.Name] = f.Tags[currentChecked[j]] or ""
		end
	end
	currentFinalTagsData = filter
end

local function updateItemsDraw()
	itemsToDraw = {}
	for k = 1, #currentFilters do
		local f = currentFilters[k]
		itemsToDraw[#itemsToDraw + 1] = {
			data = f,
			type = "filter"
		}
		if f.visible then
			for i = 1, #f.Tags do
				itemsToDraw[#itemsToDraw + 1] = {
					data = f.Tags[i],
					type = "tag",
					k = k,
					i = i,
					f = f
				}
			end
		end
	end
end

local function getFiltersHeight()
	local h = 0
	for i = 1, #currentFilters do
		local f = currentFilters[i]
		h = h + 50
		if f.visible then
			h = h + 50 * #f.Tags
		end
	end
	return h
end

local function countFilterElements()
	local c = 0
	for i = 1, #currentFilters do
		local f = currentFilters[i]
		c = c + 1
		if f.visible then
			c = c + #f.Tags
		end
	end
	return c
end

---Updates scrolling movement
local function scrollUpdate()
	slider.Y = slider.Y + slider.V
	slider.V = slider.V / 1.12
	if math.abs(slider.V) < 0.1 then
		slider.V = 0
	end
	if slider.Y < 0 then
		slider.Y = 0
		slider.V = 0
	elseif slider.Y > (getFiltersHeight() - 544 + 40 + #modes * 50 + 8 + 6) then
		slider.Y = math.max(0, getFiltersHeight() - 544 + 40 + #modes * 50 + 8 + 6)
	end
end


---The value a filter group holds now, by name (radio: tag; check: {tags}; checkcross: {include, exclude})
local function groupValue(k)
	local f, c = currentFilters[k], currentChecked[k]
	if f.Type == "radio" then
		return f.Tags[c]
	elseif f.Type == "check" then
		local list = {}
		for i = 1, #f.Tags do
			if c[i] then
				list[#list + 1] = f.Tags[i]
			end
		end
		return list
	elseif f.Type == "checkcross" then
		local include, exclude = {}, {}
		for i = 1, #f.Tags do
			if c[i] == "cross" then
				exclude[#exclude + 1] = f.Tags[i]
			elseif c[i] then
				include[#include + 1] = f.Tags[i]
			end
		end
		return {include = include, exclude = exclude}
	end
end

---Sets a filter group from a value saved by groupValue (tags the source no longer has are ignored)
local function setGroup(k, value)
	local f = currentFilters[k]
	if f.Type == "radio" then
		currentChecked[k] = 1
		for e = 1, #f.Tags do
			if f.Tags[e] == value then
				currentChecked[k] = e
			end
		end
	elseif f.Type == "check" or f.Type == "checkcross" then
		local c = {}
		for e = 1, #f.Tags do
			c[e] = false
		end
		local include = f.Type == "checkcross" and type(value) == "table" and value.include or value
		local exclude = f.Type == "checkcross" and type(value) == "table" and value.exclude or {}
		for _, name in ipairs(type(include) == "table" and include or {}) do
			for e = 1, #f.Tags do
				if f.Tags[e] == name then
					c[e] = true
				end
			end
		end
		for _, name in ipairs(type(exclude) == "table" and exclude or {}) do
			for e = 1, #f.Tags do
				if f.Tags[e] == name then
					c[e] = "cross"
				end
			end
		end
		currentChecked[k] = c
	end
end

local function isFilter(f)
	return not f.Setting and (f.Type == "radio" or f.Type == "check" or f.Type == "checkcross")
end

---The search filters as chosen now are kept for this source (SourcePrefs)
local function saveFilters()
	if not currentParser then
		return
	end
	local saved = {}
	for k = 1, #currentFilters do
		if isFilter(currentFilters[k]) then
			saved[currentFilters[k].Name] = groupValue(k)
		end
	end
	SourcePrefs.setFilters(currentParser.ID, saved)
end

local function saveSetting(k)
	local f = currentFilters[k]
	if currentParser and f.Setting and f.Key then
		SourcePrefs.setPref(currentParser.ID, f.Key, groupValue(k))
	end
end

local function hostOf(url)
	return tostring(url or ""):match("^%a+://([^/:?#]+)") or tostring(url or "")
end

local function editDomain()
	local parser = currentParser
	if not parser then
		return
	end
	local current = SourcePrefs.getDomain(parser.ID) or SourcePrefs.movedTo(parser.Link) or parser.Link or ""
	local text = TextInput(string.format(LO().SOURCE_DOMAIN_PROMPT, parser.Name or ""), current, 256, TYPE_DEFAULT)
	if text == nil then
		return
	end
	text = text:match("^%s*(.-)%s*$")
	if text == "" or text:gsub("/+$", "") == tostring(parser.Link or ""):gsub("/+$", "") then
		SourcePrefs.setDomain(parser.ID, parser.Link, nil)
		Notifications.push(LO().SOURCE_DOMAIN_CLEARED)
	elseif SourcePrefs.setDomain(parser.ID, parser.Link, text) then
		Notifications.push(string.format(LO().SOURCE_DOMAIN_SET, hostOf(SourcePrefs.getDomain(parser.ID))))
	else
		Notifications.push(LO().SOURCE_DOMAIN_INVALID)
		return
	end
	Catalogs.terminate() -- the list loads again from the new address
end

local buildFilters

local function resetFilters()
	if currentParser then
		SourcePrefs.setFilters(currentParser.ID, nil)
		buildFilters()
		Notifications.push(LO().FILTERS_RESET)
	end
end

---Filter groups of the source (its Filters, then extraFilters: lists an engine learned from the site, like genres),
---then the source settings: its own Preferences, the site address and "reset filters". Saved choices are restored.
buildFilters = function()
	local parser = currentParser
	local list = {}
	for _, f in ipairs(type(parser.Filters) == "table" and parser.Filters or {}) do
		list[#list + 1] = f
	end
	if parser.extraFilters then
		local ok, extra = pcall(parser.extraFilters, parser)
		if ok and type(extra) == "table" then
			for _, f in ipairs(extra) do
				list[#list + 1] = f
			end
		end
	end
	local filterCount = #list
	list[#list + 1] = {Type = "section", Name = LO().SOURCE_SETTINGS, Tags = {}}
	for _, pf in ipairs(type(parser.Preferences) == "table" and parser.Preferences or {}) do
		if pf.Key and (pf.Type == "radio" or pf.Type == "check") and type(pf.Tags) == "table" then
			local stored = SourcePrefs.getPref(parser.ID, pf.Key)
			list[#list + 1] = {Name = pf.Name or pf.Key, Type = pf.Type, Tags = pf.Tags, Key = pf.Key, Setting = true,
				Default = stored ~= nil and stored or pf.Default}
		end
	end
	list[#list + 1] = {Type = "action", Name = LO().SOURCE_DOMAIN, Tags = {}, Run = editDomain, Value = function()
		local d = SourcePrefs.getDomain(parser.ID)
		if d then
			return hostOf(d)
		end
		-- moved by the catalog: the new address, marked as automatic
		local moved = SourcePrefs.movedTo(parser.Link)
		return moved and (hostOf(moved) .. " (" .. LO().SOURCE_DOMAIN_AUTO .. ")") or LO().SOURCE_DOMAIN_DEFAULT
	end}
	if filterCount > 0 then
		list[#list + 1] = {Type = "action", Name = LO().RESET_FILTERS, Tags = {}, Run = resetFilters}
	end
	currentFilters = list
	currentChecked = {}
	for k = 1, #currentFilters do
		local f = currentFilters[k]
		f.visible = false
		f.Tags = f.Tags or {}
		if f.Type == "check" or f.Type == "checkcross" or f.Type == "radio" then
			local default = f.Default
			if f.Type == "checkcross" and type(default) == "table" and not default.include then
				default = {include = default, exclude = {}}
			end
			setGroup(k, default)
		end
	end
	local saved = SourcePrefs.getFilters(parser.ID)
	if type(saved) == "table" then
		for k = 1, #currentFilters do
			local f = currentFilters[k]
			if isFilter(f) and saved[f.Name] ~= nil then
				setGroup(k, saved[f.Name])
			end
		end
	end
	setFinalTags()
	updateItemsDraw()
end

---A row of the filter list chosen (Cross or a tap): opens/closes a group, runs an action, or toggles an option
local function activate(id)
	for i = 1, #currentFilters do
		local f = currentFilters[i]
		id = id - 1
		if id == 0 then
			if f.Type == "action" then
				if f.Run then
					f.Run()
				end
			elseif f.Type ~= "section" then
				f.visible = not f.visible
				updateItemsDraw()
			end
			return
		end
		if f.visible then
			if id <= #f.Tags then
				if f.Type == "check" then
					currentChecked[i][id] = not currentChecked[i][id]
				elseif f.Type == "radio" then
					currentChecked[i] = id
				elseif f.Type == "checkcross" then
					if currentChecked[i][id] == "cross" then
						currentChecked[i][id] = false
					elseif currentChecked[i][id] == false then
						currentChecked[i][id] = true
					elseif currentChecked[i][id] == true then
						currentChecked[i][id] = "cross"
					end
				end
				if f.Setting then
					saveSetting(i)
				else
					saveFilters()
					setFinalTags()
				end
				return
			end
			id = id - #f.Tags
		end
	end
end

local easingFunction = EaseInOutCubic

local function animationUpdate()
	if status == "START" then
		fade = easingFunction(math.min((Timer.getTime(animationTimer) / 500), 1))
	elseif status == "WAIT" then
		if fade == 0 then
			status = "END"
		end
		fade = 1 - easingFunction(math.min((Timer.getTime(animationTimer) / 500), 1))
	end
end

function CatalogModes.load(parser)
	if parser and parser.ID and parser.ID ~= "IMPORTED" then
		modes = {}
		Name = parser.Name
		currentFinalLetter = 1
		currentFinalTagsData = {}
		if parser.getPopularManga then
			modes[#modes + 1] = "Popular"
		end
		if parser.getLatestManga then
			modes[#modes + 1] = "Latest"
		end
		if parser.getAZManga then
			modes[#modes + 1] = "Alphabet"
		end
		if parser.getLetterManga and type(parser.Letters) == "table" then
			modes[#modes + 1] = "ByLetter"
			currentLetters = parser.Letters
			currentLettersIndex = 1
		end
		if parser.getTagManga and type(parser.Tags) == "table" then
			modes[#modes + 1] = "ByTag"
			currentTags = parser.Tags
			currentTagsIndex = 1
		end
		if parser.searchManga then
			modes[#modes + 1] = "Search"
		end
		modesFade = {}
		for i = 1, #modes do
			modesFade[modes[i]] = 0
		end
		currentParser = parser
		buildFilters()
		nowMode = 1
		searchData = ""
		slider.Y = -50
		updateItemsDraw()
	end
end

function CatalogModes.show()
	if currentParser then
		buildFilters()
	end
	status = "START"
	oldFade = 1
	Timer.reset(animationTimer)
	selectedIndex = 0
end

local function setMode(id)
	if nowMode ~= id or modes[id] == "Search" or modes[id] == "ByLetter" or modes[id] == "ByTag" then
		if modes[id] == "Search" then
			Keyboard.show(Language[Settings.Language].APP.SEARCH, searchData, 128, TYPE_DEFAULT, MODE_TEXT, OPT_NO_AUTOCAP)
			setFinalTags()
		else
			nowMode = id
			currentFinalLetter = currentLettersIndex
			currentFinalTag = currentTagsIndex
			status = "WAIT"
			Timer.reset(animationTimer)
			oldFade = fade
			Catalogs.terminate()
		end
	end
end

function CatalogModes.input(pad, oldpad, touch, oldtouch)
	if status == "START" then
		if TOUCH_MODES.MODE == TOUCH_MODES.NONE and oldtouch.x and touch.x and touch.x > 240 then
			TOUCH_MODES.MODE = TOUCH_MODES.READ
			slider.TouchY = touch.y
		elseif TOUCH_MODES.MODE ~= TOUCH_MODES.NONE and not touch.x then
			if TOUCH_MODES.MODE == TOUCH_MODES.READ and oldtouch.x then
				if oldtouch.x > 960 - 350 * fade * oldFade then
					if oldtouch.y > 40 + 8 + 50 * #modes then
						local id = math.floor((slider.Y + oldtouch.y - (40 + 8 + 50 * #modes)) / 50) + 1
						if id > 0 then
							activate(id)
						end
					else
						local id = math.floor((oldtouch.y - 40) / 50) + 1
						if id > 0 and id <= #modes then
							setMode(id)
						end
					end
				end
			end
			TOUCH_MODES.MODE = TOUCH_MODES.NONE
		elseif touch.x then
			if touch.x < 960 - 350 * fade * oldFade then
				status = "WAIT"
				Timer.reset(animationTimer)
				oldFade = fade
			end
		end
		if Controls.check(pad, SCE_CTRL_CIRCLE) and not Controls.check(oldpad, SCE_CTRL_CIRCLE) or Controls.check(pad, SCE_CTRL_SQUARE) and not Controls.check(oldpad, SCE_CTRL_SQUARE) then
			status = "WAIT"
			Timer.reset(animationTimer)
			oldFade = fade
		elseif Controls.check(pad, SCE_CTRL_CROSS) and not Controls.check(oldpad, SCE_CTRL_CROSS) then
			if selectedIndex > 0 then
				if selectedIndex <= #modes then
					setMode(selectedIndex)
				else
					local id = selectedIndex - #modes
					if id > 0 then
						activate(id)
					end
				end
			end
		end
		if touch.x then
			selectedIndex = 0
			controlInterval = 400
		elseif Timer.getTime(controlTimer) > controlInterval or (Controls.check(pad, SCE_CTRL_DOWN) and not Controls.check(oldpad, SCE_CTRL_DOWN) or Controls.check(pad, SCE_CTRL_UP) and not Controls.check(oldpad, SCE_CTRL_UP) or ((modes[selectedIndex] == "ByLetter" or modes[selectedIndex] == "ByTag") and (Controls.check(pad, SCE_CTRL_LEFT) and not Controls.check(oldpad, SCE_CTRL_LEFT) or Controls.check(pad, SCE_CTRL_RIGHT) and not Controls.check(oldpad, SCE_CTRL_RIGHT)))) then
			if Controls.check(pad, SCE_CTRL_DOWN + SCE_CTRL_UP + SCE_CTRL_LEFT + SCE_CTRL_RIGHT) then
				if Controls.check(pad, SCE_CTRL_UP) then
					if selectedIndex == 0 then
						selectedIndex = 1
					elseif selectedIndex > 1 then
						selectedIndex = selectedIndex - 1
					end
				elseif Controls.check(pad, SCE_CTRL_DOWN) then
					if selectedIndex == 0 then
						selectedIndex = 1
					elseif selectedIndex < #modes + countFilterElements() then
						selectedIndex = selectedIndex + 1
					end
				elseif Controls.check(pad, SCE_CTRL_RIGHT) then
					if modes[selectedIndex] == "ByLetter" then
						currentLettersIndex = currentLettersIndex + 1
						if currentLettersIndex > #currentLetters then
							currentLettersIndex = 1
						end
					elseif modes[selectedIndex] == "ByTag" then
						currentTagsIndex = currentTagsIndex + 1
						if currentTagsIndex > #currentTags then
							currentTagsIndex = 1
						end
					end
				elseif Controls.check(pad, SCE_CTRL_LEFT) then
					if modes[selectedIndex] == "ByLetter" then
						currentLettersIndex = currentLettersIndex - 1
						if currentLettersIndex < 1 then
							currentLettersIndex = #currentLetters
						end
					elseif modes[selectedIndex] == "ByTag" then
						currentTagsIndex = currentTagsIndex - 1
						if currentTagsIndex < 1 then
							currentTagsIndex = #currentTags
						end
					end
				end
				if controlInterval > 50 then
					controlInterval = math.max(50, controlInterval / 2)
				end
				Timer.reset(controlTimer)
			else
				controlInterval = 400
			end
		end
		if TOUCH_MODES.MODE == TOUCH_MODES.READ then
			if math.abs(slider.V) > 0.1 or math.abs(touch.y - slider.TouchY) > 10 then
				TOUCH_MODES.MODE = TOUCH_MODES.SLIDE
			end
		elseif TOUCH_MODES.MODE == TOUCH_MODES.SLIDE then
			if touch.x and oldtouch.x then
				slider.V = oldtouch.y - touch.y
			end
		end
	end
end

function CatalogModes.update()
	if status ~= "END" then
		if selectedIndex > 0 then
			slider.Y = slider.Y + ((selectedIndex - #modes) * 50 - 160 - slider.Y) / 5
		end
		animationUpdate()
		for i = 1, #modes do
			local v = modes[i]
			if nowMode == i then
				modesFade[v] = math.min(modesFade[v] + 0.1, 1)
			elseif selectedIndex == i then
				if modesFade[v] > 0.3 then
					modesFade[v] = math.max(modesFade[v] - 0.1, 0.3)
				else
					modesFade[v] = math.min(modesFade[v] + 0.1, 0.3)
				end
			else
				modesFade[v] = math.max(modesFade[v] - 0.1, 0)
			end
		end
		scrollUpdate()
		if Keyboard.getState() ~= RUNNING then
			if Keyboard.getState() == FINISHED then
				local data = Keyboard.getInput()
				Console.write('Searching for "' .. data .. '"')
				Catalogs.terminate()
				for i = 1, #modes do
					if modes[i] == "Search" then
						nowMode = i
						break
					end
				end
				searchData = data
				status = "WAIT"
				Timer.reset(animationTimer)
				oldFade = fade
				if data:gsub("%s", "") ~= "" then
					Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.SEARCHING, data))
				end
			end
			Keyboard.clear()
		end
	end
end

local MODE_ICONS = {
	Popular = "HotIcon", Latest = "HistoryIcon", Search = "SearchIcon", ByLetter = "LetterAIcon", ByTag = "TagIcon",
	Alphabet = "AZIcon"
}

---Source panel (modes and filters). Same geometry as before (input and touch use it); colors, type and highlights
---follow the theme like the other side sheets (reader settings), and look the same for every extension.
function CatalogModes.draw()
	if status == "END" then
		return
	end
	local M = oldFade * fade
	local PX = 960 - M * 350 -- left edge of the panel
	local listTop = 40 + 8 + 50 * #modes
	local DANGER = COLOR_DANGER or Color.new(240, 80, 100)
	Graphics.fillRect(0, 960, 0, 544, Color.new(0, 0, 0, 150 * M))
	-- filters: drawn first, they scroll under the header
	Graphics.fillRect(PX, 960, listTop, 544, COLOR_SURFACE)
	local start_i = math.floor((slider.Y - listTop) / 50) + 1
	local y = 40 + 50 * #modes + 17 - slider.Y + (math.max(1, start_i) - 1) * 50
	for n = math.max(1, start_i), math.min(#itemsToDraw, start_i + 12) do
		local item = itemsToDraw[n]
		if y - 1 > 544 then
			break
		end
		if item.type == "filter" then
			local f = item.data
			if f.Type == "section" then
				UI.text(FONT13, PX + 20, y + 6, f.Name or "", COLOR_ACCENT, 310)
			elseif f.Type == "action" then
				local value = f.Value and f.Value() or nil
				local vw = value and math.min(Font.getTextWidth(FONT16, value), 150) or 0
				UI.text(FONT16, PX + 20, y, f.Name or "", COLOR_FONT, 300 - vw - 20)
				if value then
					UI.text(FONT16, PX + 330 - vw, y, value, COLOR_SUBFONT, 150)
				end
			else
				UI.text(BONT16, PX + 52, y, tr(f.Name or ""), COLOR_FONT, 280)
				Graphics.drawImage(PX + 14, y - 1, (f.visible and HideIcon or ShowIcon).e, COLOR_SUBFONT)
			end
		elseif item.type == "tag" and y - 1 + 24 > 8 + 50 * #modes + 8 then
			local f, k, i, v = item.f, item.k, item.i, item.data
			local checked = currentChecked[k]
			local crossed = type(checked) == "table" and checked[i] == "cross"
			local icon, tint = CheckboxIcon, COLOR_SUBFONT
			if f.Type == "check" or f.Type == "checkcross" then
				if crossed then
					icon, tint = CheckboxCrossedIcon, DANGER
				elseif type(checked) == "table" and checked[i] then
					icon, tint = CheckboxCheckedIcon, COLOR_ACCENT
				end
			elseif f.Type == "radio" then
				if checked == i then
					icon, tint = RadioCheckedIcon, COLOR_ACCENT
				else
					icon = RadioIcon
				end
			end
			Graphics.drawImage(PX + 34, y - 1, icon.e, tint)
			UI.text(FONT16, PX + 72, y, tr(v or ""), crossed and COLOR_SUBFONT or COLOR_FONT, 260)
		end
		y = y + 50
	end
	-- header and modes
	Graphics.fillRect(PX, 960, 0, listTop, COLOR_SURFACE)
	for i = 1, #modes do
		local v = modes[i]
		local f = modesFade[v] or 0
		local ry = 42 + (i - 1) * 50
		-- the mode in use: soft accent background (inactive modes rest at 0.3)
		local on = math.max(0, (f - 0.3) / 0.7)
		if on > 0.01 then
			UI.roundRect(PX + 5, ry + 2, PX + 340, ry + 51, 10, WithAlpha(COLOR_ACCENT_SOFT, 255 * on * M))
		end
		local icon = _G[MODE_ICONS[v] or ""]
		if icon and icon.e then
			Graphics.drawImage(PX + 14, 17 + 40 + (i - 1) * 50 - 1, icon.e, COLOR_GRADIENT(COLOR_SUBFONT, COLOR_ACCENT, on))
		end
		local text = Language[Settings.Language].MODES[v] or v or ""
		if v == "Search" and searchData:gsub("%s", "") ~= "" then
			text = text .. ": " .. searchData
		elseif v == "ByLetter" then
			text = text .. "  ‹ " .. tostring(currentLetters[currentLettersIndex]) .. " ›"
		elseif v == "ByTag" then
			text = text .. "  ‹ " .. tostring(currentTags[currentTagsIndex]) .. " ›"
		end
		UI.text(FONT16, PX + 52, 17 + 40 + (i - 1) * 50, text, COLOR_GRADIENT(COLOR_SUBFONT, COLOR_FONT, f), 280)
		if i == selectedIndex then
			UI.selectionRing(PX + 5, ry + 2, PX + 340, ry + 51, M)
		end
	end
	if #itemsToDraw > 0 then
		Graphics.fillRect(PX + 16, PX + 334, listTop - 2, listTop - 1, COLOR_DIVIDER)
	end
	if selectedIndex > #modes then
		local sy = 40 + 50 * #modes - slider.Y + 50 * (selectedIndex - #modes - 1) + 2
		if sy + 51 > listTop then
			UI.selectionRing(PX + 5, math.max(sy + 2, listTop), PX + 340, sy + 51, M)
		end
	end
	UI.scrollbar(PX + 342, listTop + 4, 540, slider.Y, getFiltersHeight(), 544 - listTop)
	-- edge and title, like the other side sheets
	Graphics.fillRect(PX, PX + 1, 0, 544, COLOR_DIVIDER)
	UI.text(BONT16, PX + 20, 14, Name or "", COLOR_FONT, 310)
end

function CatalogModes.getStatus()
	return status
end

function CatalogModes.getFade()
	return fade * oldFade
end

function CatalogModes.getMangaMode()
	return modes[nowMode]
end

function CatalogModes.getSearchData()
	return searchData
end

function CatalogModes.getTagsData()
	return currentFinalTagsData
end

function CatalogModes.getLetter()
	return currentLetters[currentFinalLetter] or ""
end

function CatalogModes.getTag()
	return currentTags[currentFinalTag] or ""
end

---Asks for a query and searches inside the current source (Triangle in a source catalog)
function CatalogModes.searchPrompt()
	local hasSearch = false
	for i = 1, #modes do
		hasSearch = hasSearch or modes[i] == "Search"
	end
	if not hasSearch then
		Notifications.push(Language[Settings.Language].OTAKIO.NO_SOURCE_SEARCH)
		return
	end
	local query = TextInput(Language[Settings.Language].APP.SEARCH, searchData, 128, TYPE_DEFAULT)
	if query and query:gsub("%s", "") ~= "" then
		CatalogModes.setSearch(query)
		Notifications.push(string.format(Language[Settings.Language].NOTIFICATIONS.SEARCHING, query))
	end
end

---Switches the current source to Search mode with `query` (used by global search)
function CatalogModes.setSearch(query)
	for i = 1, #modes do
		if modes[i] == "Search" then
			nowMode = i
			searchData = query or ""
			Catalogs.terminate()
			return true
		end
	end
	return false
end
