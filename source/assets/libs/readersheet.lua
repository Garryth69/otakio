---Reader look (page colors, Mihon-style) and the reader settings sheet.
---
---ReaderLook: background color, brightness and a color filter applied while drawing pages. The engine has no shaders,
---so the filter is done with what vita2d offers for free: "Multiply" tints the page textures as they are drawn (same
---draw call, no extra cost) and "Default" lays one translucent full-screen rectangle over them. Brightness below 100%
---is part of the tint. Grayscale and inverted colors would need an engine shader and are not offered.
---
---ReaderSheet: side panel opened from the reader's menu icon (or Triangle): this manga's layout, colors (with live
---preview: the page stays visible on the left), reader options and page actions. Up/Down move, Left/Right change,
---Cross toggles or runs, Circle/Triangle close.
ReaderLook = {}
ReaderSheet = {}

local DEFAULT = {
	Background = "Theme", -- Theme | Black | Gray | White
	Brightness = 0, -- -75..0 (percent darker)
	Filter = false,
	Preset = "Warm", -- Custom | Sepia | Paper | Warm | Night
	Mode = "Default", -- Default (overlay) | Multiply
	R = 255, G = 150, B = 60, A = 25, -- A: 0..100 (percent)
	PageNumber = true
}

local PRESETS = {
	Sepia = {Mode = "Multiply", R = 255, G = 222, B = 170, A = 80},
	Paper = {Mode = "Multiply", R = 255, G = 244, B = 222, A = 100},
	Warm = {Mode = "Default", R = 255, G = 150, B = 60, A = 25},
	Night = {Mode = "Multiply", R = 255, G = 170, B = 110, A = 70}
}
local PRESET_ORDER = {"Custom", "Sepia", "Paper", "Warm", "Night"}
local BACKGROUNDS = {"Theme", "Black", "Gray", "White"}
local MODES = {"Default", "Multiply"}

local function clamp(v, lo, hi)
	v = tonumber(v) or lo
	return v < lo and lo or (v > hi and hi or v)
end

local function oneOf(v, list, default)
	for _, x in ipairs(list) do
		if x == v then
			return v
		end
	end
	return default
end

local checkedTable = nil -- the Settings.ReaderLook table already completed and checked

---Settings.ReaderLook, completed and checked (it comes from settings.ini, written by older or newer versions)
function ReaderLook.get()
	local t = Settings.ReaderLook
	if type(t) ~= "table" then
		t = {}
		Settings.ReaderLook = t
	end
	if t ~= checkedTable then
		t.Background = oneOf(t.Background, BACKGROUNDS, DEFAULT.Background)
		t.Brightness = clamp(t.Brightness or 0, -75, 0)
		t.Filter = t.Filter == true
		t.Preset = oneOf(t.Preset, PRESET_ORDER, DEFAULT.Preset)
		t.Mode = oneOf(t.Mode, MODES, DEFAULT.Mode)
		for _, k in ipairs({"R", "G", "B"}) do
			t[k] = math.floor(clamp(t[k] or DEFAULT[k], 0, 255))
		end
		t.A = math.floor(clamp(t.A or DEFAULT.A, 0, 100))
		t.PageNumber = t.PageNumber ~= false
		checkedTable = t
	end
	return t
end

---Cached colors, rebuilt only when a value changes (the reader asks every frame)
local cache = nil

function ReaderLook.changed()
	cache = nil
end

local function build()
	local t = ReaderLook.get()
	local c = {}
	if t.Background == "Black" then
		c.back = Color.new(0, 0, 0)
	elseif t.Background == "Gray" then
		c.back = Color.new(48, 48, 52)
	elseif t.Background == "White" then
		c.back = Color.new(255, 255, 255)
	end
	-- multiply tint: brightness (gray) times the filter color pulled toward white by its opacity
	local k = 1 + t.Brightness / 100
	local r, g, b = 255 * k, 255 * k, 255 * k
	local a = t.A / 100
	if t.Filter and t.Mode == "Multiply" then
		r = r * (1 - a + a * t.R / 255)
		g = g * (1 - a + a * t.G / 255)
		b = b * (1 - a + a * t.B / 255)
	end
	if r < 254.5 or g < 254.5 or b < 254.5 then
		c.tint = Color.new(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5), 255)
	end
	if t.Filter and t.Mode == "Default" and t.A > 0 then
		c.overlay = Color.new(t.R, t.G, t.B, math.floor(255 * a + 0.5))
	end
	c.pageNumber = t.PageNumber
	cache = c
	return c
end

---Reader background (nil: the theme's)
function ReaderLook.background()
	return (cache or build()).back
end

---Color to tint page textures with (nil: draw them untouched)
function ReaderLook.tint()
	return (cache or build()).tint
end

---Color of the translucent layer over the pages (nil: none)
function ReaderLook.overlay()
	return (cache or build()).overlay
end

function ReaderLook.showPageNumber()
	return (cache or build()).pageNumber
end

-------------------------------------------------------------------------------
-- the sheet
-------------------------------------------------------------------------------

local open = false
local rows = {}
local selected = 1
local scroll = 0
local ctx = nil -- {manga, chapter, page, onAction}
local dirty = false
local repeatKey, repeatAt = nil, 0

local X0, X1, Y0, Y1 = 520, 944, 16, 528
local ROW = 40
local HEAD_H = 30

local function T()
	return Language[Settings.Language]
end

local function O(key)
	return T().OTAKIO[key] or Language.English.OTAKIO[key] or key
end

local function setLook(key, value)
	local t = ReaderLook.get()
	t[key] = value
	ReaderLook.changed()
	dirty = true
end

---Editing a filter value by hand turns the preset into "Custom"
local function setFilterValue(key, value)
	setLook(key, value)
	setLook("Preset", "Custom")
end

local function applyPreset(name)
	setLook("Preset", name)
	local p = PRESETS[name]
	if p then
		for k, v in pairs(p) do
			setLook(k, v)
		end
	end
end

local function cycle(list, value, dir)
	local i = 1
	for j, v in ipairs(list) do
		if v == value then
			i = j
		end
	end
	i = (i - 1 + dir) % #list + 1
	return list[i]
end

local function buildRows()
	local LS = T()
	local look = ReaderLook.get()
	local manga = ctx and ctx.manga
	local list = {}
	local function add(r)
		list[#list + 1] = r
	end
	if manga then
		local cs = CuSettings.load(manga)
		add({kind = "header", label = O("RS_THIS_MANGA")})
		add({kind = "cycle", label = LS.SETTINGS.ReaderOrientation, value = function() return LS.READER[cs.Orientation] or cs.Orientation end,
			change = function() CuSettings.changeOrientation(manga) Reader.updateSettings() end})
		add({kind = "cycle", label = LS.SETTINGS.ReaderDirection, value = function() return LS.READER[cs.ReaderDirection] or cs.ReaderDirection end,
			change = function() CuSettings.changeDirection(manga) Reader.updateSettings() end})
		add({kind = "cycle", label = LS.SETTINGS.ZoomReader, value = function() return LS.READER[cs.ZoomReader] or cs.ZoomReader end,
			change = function() CuSettings.changeZoom(manga) Reader.updateSettings() end})
	end
	add({kind = "header", label = O("RS_COLORS")})
	add({kind = "cycle", label = O("RS_BACKGROUND"), value = function() return O("RS_BG_" .. ReaderLook.get().Background:upper()) end,
		change = function(dir) setLook("Background", cycle(BACKGROUNDS, ReaderLook.get().Background, dir)) end})
	add({kind = "slider", label = O("RS_BRIGHTNESS"), min = -75, max = 0, step = 5, get = function() return ReaderLook.get().Brightness end,
		set = function(v) setLook("Brightness", v) end, text = function(v) return (100 + v) .. "%" end})
	add({kind = "toggle", label = O("RS_FILTER"), get = function() return ReaderLook.get().Filter end,
		set = function(v) setLook("Filter", v) end, rebuild = true})
	if look.Filter then
		add({kind = "cycle", label = O("RS_PRESET"), value = function() return O("RS_PRESET_" .. ReaderLook.get().Preset:upper()) end,
			change = function(dir) applyPreset(cycle(PRESET_ORDER, ReaderLook.get().Preset, dir)) end, swatch = true})
		add({kind = "cycle", label = O("RS_BLEND"), value = function() return O("RS_BLEND_" .. ReaderLook.get().Mode:upper()) end,
			change = function(dir) setFilterValue("Mode", cycle(MODES, ReaderLook.get().Mode, dir)) end})
		for _, ch in ipairs({{"R", "RS_RED"}, {"G", "RS_GREEN"}, {"B", "RS_BLUE"}}) do
			local key = ch[1]
			add({kind = "slider", label = O(ch[2]), min = 0, max = 255, step = 5, channel = key, get = function() return ReaderLook.get()[key] end,
				set = function(v) setFilterValue(key, v) end, text = function(v) return tostring(v) end})
		end
		add({kind = "slider", label = O("RS_OPACITY"), min = 0, max = 100, step = 5, get = function() return ReaderLook.get().A end,
			set = function(v) setFilterValue("A", v) end, text = function(v) return v .. "%" end})
	end
	add({kind = "action", label = O("RS_RESET"), run = function()
		local keep = ReaderLook.get().PageNumber
		Settings.ReaderLook = {PageNumber = keep}
		ReaderLook.changed()
		dirty = true
	end, rebuild = true})
	add({kind = "header", label = O("RS_READER")})
	add({kind = "toggle", label = O("RS_PAGE_NUMBER"), get = function() return ReaderLook.get().PageNumber end,
		set = function(v) setLook("PageNumber", v) end})
	add({kind = "toggle", label = LS.SETTINGS.DoubleTapReader, get = function() return Settings.DoubleTapReader end,
		set = function(v) Settings.DoubleTapReader = v dirty = true end})
	add({kind = "toggle", label = LS.SETTINGS.PressEdgesToChangePage, get = function() return Settings.PressEdgesToChangePage end,
		set = function(v) Settings.PressEdgesToChangePage = v dirty = true end})
	if ctx and ctx.page and ctx.onAction then
		add({kind = "header", label = O("RS_PAGE")})
		if manga and manga.ParserID ~= "IMPORTED" then
			add({kind = "action", label = LS.SETTINGS.SetPageAsCover, run = function() ctx.onAction("cover") end, close = true})
		end
		add({kind = "action", label = LS.SETTINGS.DownloadImageToMemory, run = function() ctx.onAction("save") end, close = true})
	end
	rows = list
end

local function selectable(i)
	return rows[i] and rows[i].kind ~= "header"
end

local function rowY(i)
	-- headers are shorter than rows
	local y = 0
	for j = 1, i - 1 do
		y = y + (rows[j].kind == "header" and HEAD_H or ROW)
	end
	return y
end

local function contentHeight()
	return rowY(#rows + 1)
end

local LIST_TOP = Y0 + 56
local LIST_BOTTOM = Y1 - 44

local function keepVisible()
	local top, h = rowY(selected), rows[selected].kind == "header" and HEAD_H or ROW
	-- show the header above the first row of a section
	if selected > 1 and rows[selected - 1].kind == "header" then
		top = top - HEAD_H
		h = h + HEAD_H
	end
	local view = LIST_BOTTOM - LIST_TOP
	if top < scroll then
		scroll = top
	elseif top + h > scroll + view then
		scroll = top + h - view
	end
	scroll = math.max(0, math.min(scroll, math.max(0, contentHeight() - view)))
end

local function move(dir)
	local i = selected
	repeat
		i = i + dir
		if i < 1 then
			i = #rows
		elseif i > #rows then
			i = 1
		end
	until selectable(i) or i == selected
	selected = i
	keepVisible()
end

---Opens the sheet. ctx = {manga, chapter, page, onAction(action)} (all optional)
function ReaderSheet.open(c)
	ctx = c or {}
	open = true
	selected = 1
	scroll = 0
	dirty = false
	buildRows()
	if not selectable(selected) then
		move(1)
	end
end

function ReaderSheet.isOpen()
	return open
end

---After closing, the button that closed it (Circle, also "exit" in the reader) is kept from the reader until released
local waitRelease = false

---True while the sheet is open or the closing button is still held
function ReaderSheet.takesInput(pad)
	if open then
		return true
	end
	if waitRelease then
		if Controls.check(pad, SCE_CTRL_CIRCLE) or Controls.check(pad, SCE_CTRL_TRIANGLE) or Controls.check(pad, SCE_CTRL_START) then
			return true
		end
		waitRelease = false
	end
	return false
end

function ReaderSheet.close()
	open = false
	waitRelease = true
	if dirty then
		Settings.save()
		dirty = false
	end
end

local function change(row, dir)
	if row.kind == "cycle" then
		row.change(dir)
	elseif row.kind == "slider" then
		local v = math.max(row.min, math.min(row.max, row.get() + dir * row.step))
		if v ~= row.get() then
			row.set(v)
		end
	elseif row.kind == "toggle" then
		row.set(not row.get())
	end
	if row.rebuild then
		local label = row.label
		buildRows()
		for i, r in ipairs(rows) do
			if r.label == label then
				selected = i
			end
		end
		keepVisible()
	end
end

function ReaderSheet.input(oldPad, pad, oldTouch, touch)
	if not open then
		return
	end
	local function pressed(btn)
		return Controls.check(pad, btn) and not Controls.check(oldPad, btn)
	end
	-- held Up/Down/Left/Right repeat (sliders go 0..255 in steps of 5)
	local now = Timer.getTime(GlobalTimer)
	local function held(btn)
		if pressed(btn) then
			repeatKey, repeatAt = btn, now + 350
			return true
		end
		if repeatKey == btn and Controls.check(pad, btn) and now >= repeatAt then
			repeatAt = now + 60
			return true
		end
		return false
	end
	local row = rows[selected]
	if pressed(SCE_CTRL_CIRCLE) or pressed(SCE_CTRL_TRIANGLE) or pressed(SCE_CTRL_START) then
		ReaderSheet.close()
		return
	end
	if held(SCE_CTRL_UP) then
		move(-1)
	elseif held(SCE_CTRL_DOWN) then
		move(1)
	elseif row and held(SCE_CTRL_LEFT) then
		change(row, -1)
	elseif row and held(SCE_CTRL_RIGHT) then
		change(row, 1)
	elseif row and pressed(SCE_CTRL_CROSS) then
		if row.kind == "action" then
			row.run()
			if row.close then
				ReaderSheet.close()
				return
			end
			if row.rebuild then
				buildRows()
				selected = math.min(selected, #rows)
				if not selectable(selected) then
					move(1)
				end
			end
		else
			change(row, 1)
		end
	end
	-- touch: tap a row to select it (tap again to change), tap the page area to close
	if oldTouch.x and not touch.x then
		local tx, ty = oldTouch.x, oldTouch.y
		if tx < X0 then
			ReaderSheet.close()
		elseif ty >= LIST_TOP and ty < LIST_BOTTOM then
			local y = ty - LIST_TOP + scroll
			for i = 1, #rows do
				local top = rowY(i)
				local h = rows[i].kind == "header" and HEAD_H or ROW
				if y >= top and y < top + h and selectable(i) then
					if i == selected then
						if rows[i].kind == "action" then
							rows[i].run()
							if rows[i].close then
								ReaderSheet.close()
							end
						else
							change(rows[i], 1)
						end
					else
						selected = i
					end
					break
				end
			end
		end
	end
end

local function drawSwitch(x1, y, on)
	local x0 = x1 - 40
	UI.roundRect(x0, y, x1, y + 22, 11, on and COLOR_ACCENT or COLOR_SURFACE2)
	local cx = on and (x1 - 11) or (x0 + 11)
	Graphics.fillCircle(cx, y + 11, 8, COLOR_WHITE)
end

function ReaderSheet.draw()
	if not open then
		return
	end
	UI.roundRect(X0, Y0, X1, Y1, 16, COLOR_SURFACE)
	UI.text(BONT16, X0 + 20, Y0 + 18, O("RS_TITLE"), COLOR_FONT, X1 - X0 - 40)
	local look = ReaderLook.get()
	-- the filter color as it is now, next to the title
	if look.Filter then
		UI.roundRect(X1 - 52, Y0 + 16, X1 - 20, Y0 + 40, 6, Color.new(look.R, look.G, look.B))
	end
	local view = LIST_BOTTOM - LIST_TOP
	local w = X1 - X0
	for i, row in ipairs(rows) do
		local y = LIST_TOP + rowY(i) - scroll
		local h = row.kind == "header" and HEAD_H or ROW
		if y >= LIST_TOP - 1 and y + h <= LIST_BOTTOM + 1 then -- whole rows only: nothing under the title or the hints
			if row.kind == "header" then
				UI.text(FONT13, X0 + 20, y + 10, row.label, COLOR_ACCENT, w - 40)
			else
				if i == selected then
					UI.roundRect(X0 + 10, y + 2, X1 - 10, y + ROW - 2, 10, COLOR_ACCENT_SOFT)
				end
				local labelW = row.kind == "action" and w - 40 or 200
				UI.text(FONT16, X0 + 22, y + 10, row.label, COLOR_FONT, labelW)
				local vx = X1 - 24
				if row.kind == "cycle" then
					local text = row.value()
					local tw = Font.getTextWidth(FONT16, text)
					UI.text(FONT16, vx - tw - 14, y + 10, text, COLOR_FONT)
					if i == selected then
						Font.print(FONT16, vx - tw - 30, y + 10, "‹", COLOR_SUBFONT)
						Font.print(FONT16, vx - 6, y + 10, "›", COLOR_SUBFONT)
					end
					if row.swatch then
						UI.roundRect(vx - tw - 52, y + 12, vx - tw - 36, y + 28, 4, Color.new(look.R, look.G, look.B))
					end
				elseif row.kind == "slider" then
					local v = row.get()
					local text = row.text(v)
					local tw = Font.getTextWidth(FONT13, text)
					UI.text(FONT13, vx - tw, y + 12, text, COLOR_SUBFONT)
					local bx1 = vx - 52
					local bx0 = bx1 - 130
					local fg = COLOR_ACCENT
					if row.channel then
						fg = Color.new(row.channel == "R" and 255 or 60, row.channel == "G" and 220 or 60, row.channel == "B" and 255 or 60)
					end
					UI.progress(bx0, y + 15, bx1, 8, (v - row.min) / (row.max - row.min), COLOR_SURFACE2, fg)
				elseif row.kind == "toggle" then
					drawSwitch(vx, y + 9, row.get())
				end
			end
		end
	end
	if contentHeight() > view then
		UI.scrollbar(X1 - 6, LIST_TOP, LIST_BOTTOM, scroll, contentHeight(), view)
	end
	DrawButtonHints(X1 - 20, Y1 - 30, {{"DPad", O("RS_ADJUST")}, {"Circle", O("RS_CLOSE")}})
end
