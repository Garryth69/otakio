---Otakio UI kit: drawing primitives and small widgets shared by every screen.
UI = {}

local fillRect = Graphics.fillRect
local fillCircle = Graphics.fillCircle
local drawImage = Graphics.drawImage
local print = Font.print
local getTextWidth = Font.getTextWidth
local floor, min, max, abs, sin, cos, pi = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.pi

UI.time = 0

---Called once per frame by main loop
function UI.tick()
	UI.time = Timer.getTime(GlobalTimer)
end

function UI.lerp(a, b, t)
	return a + (b - a) * t
end

---Frame-rate independent exponential approach (speed ~ 0.2 = snappy)
function UI.approach(current, target, speed)
	local d = target - current
	if abs(d) < 0.5 then
		return target
	end
	return current + d * (speed or 0.25)
end

---Filled rounded rectangle (opaque colors look best)
function UI.roundRect(x0, y0, x1, y1, r, color)
	x0, y0, x1, y1 = floor(x0), floor(y0), floor(x1), floor(y1)
	r = min(r or 8, floor((x1 - x0) / 2), floor((y1 - y0) / 2))
	if r <= 1 or not fillCircle then
		fillRect(x0, x1, y0, y1, color)
		return
	end
	fillRect(x0 + r, x1 - r, y0, y1, color)
	fillRect(x0, x0 + r, y0 + r, y1 - r, color)
	fillRect(x1 - r, x1, y0 + r, y1 - r, color)
	fillCircle(x0 + r, y0 + r, r, color)
	fillCircle(x1 - r - 1, y0 + r, r, color)
	fillCircle(x0 + r, y1 - r - 1, r, color)
	fillCircle(x1 - r - 1, y1 - r - 1, r, color)
end

---Rounded outline (2px)
function UI.roundOutline(x0, y0, x1, y1, r, color, thickness)
	thickness = thickness or 2
	for i = 0, thickness - 1 do
		Graphics.fillEmptyRect(x0 + i, x1 - i, y0 + i, y1 - i, color)
	end
end

local ellipsisCache = setmetatable({}, {__mode = "k"})
local ellipsisCount = 0
local ELLIPSIS_MAX = 2000 -- long sessions scroll through thousands of titles: keep the cache bounded

---Returns `text` cut with "…" to fit `maxWidth`
function UI.ellipsize(font, text, maxWidth)
	text = tostring(text or "")
	if getTextWidth(font, text) <= maxWidth then
		return text
	end
	local fc = ellipsisCache[font]
	if not fc then
		fc = {}
		ellipsisCache[font] = fc
	end
	local key = maxWidth .. "\0" .. text
	local cached = fc[key]
	if cached then
		return cached
	end
	local chars = {}
	for c in it_utf8(text) do
		chars[#chars + 1] = c
	end
	local lo, hi = 0, #chars
	while lo < hi do
		local mid = floor((lo + hi + 1) / 2)
		if getTextWidth(font, table.concat(chars, "", 1, mid) .. "…") <= maxWidth then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local result = table.concat(chars, "", 1, lo) .. "…"
	ellipsisCount = ellipsisCount + 1
	if ellipsisCount > ELLIPSIS_MAX then
		ellipsisCache = setmetatable({}, {__mode = "k"})
		ellipsisCount = 0
		fc = {}
		ellipsisCache[font] = fc
	end
	fc[key] = result
	return result
end

---Prints text clipped with ellipsis
function UI.text(font, x, y, text, color, maxWidth)
	if maxWidth then
		text = UI.ellipsize(font, text, maxWidth)
	end
	print(font, x, y, text, color)
end

function UI.textCenter(font, cx, y, text, color, maxWidth)
	if maxWidth then
		text = UI.ellipsize(font, text, maxWidth)
	end
	print(font, cx - floor(getTextWidth(font, text) / 2), y, text, color)
end

function UI.textRight(font, x1, y, text, color)
	print(font, x1 - getTextWidth(font, text), y, text, color)
end

---Pill / chip. Returns its width.
function UI.chip(x, y, text, selected, font)
	font = font or FONT16
	local w = getTextWidth(font, text) + 24
	local h = 30
	if selected then
		UI.roundRect(x, y, x + w, y + h, 15, COLOR_ACCENT)
		print(font, x + 12, y + 4, text, COLOR_ON_ACCENT)
	else
		UI.roundRect(x, y, x + w, y + h, 15, COLOR_SURFACE2)
		print(font, x + 12, y + 4, text, COLOR_SUBFONT)
	end
	return w
end

---Small count badge centered at x,y
function UI.badge(x, y, count, bg, fg)
	if not count or count == 0 then
		return
	end
	local text = count > 999 and "999+" or tostring(count)
	local w = max(20, getTextWidth(BONT16, text) + 10)
	UI.roundRect(x - w / 2, y - 10, x + w / 2, y + 10, 10, bg or COLOR_DANGER)
	print(BONT16, x - getTextWidth(BONT16, text) / 2, y - 10, text, fg or COLOR_WHITE)
end

---Label tag on a cover corner (e.g. unread count). Returns width
function UI.tag(x, y, text, bg, fg)
	local w = getTextWidth(BONT16, text) + 12
	UI.roundRect(x, y, x + w, y + 22, 6, bg)
	print(BONT16, x + 6, y + 1, text, fg)
	return w
end

---Horizontal progress bar
function UI.progress(x0, y, x1, h, value, bg, fg)
	value = max(0, min(1, value or 0))
	UI.roundRect(x0, y, x1, y + h, floor(h / 2), bg or COLOR_SURFACE2)
	if value > 0 then
		UI.roundRect(x0, y, x0 + max(h, (x1 - x0) * value), y + h, floor(h / 2), fg or COLOR_ACCENT)
	end
end

---Material-like circular spinner made of fading dots
function UI.spinner(cx, cy, r, color)
	color = color or COLOR_ACCENT
	local t = UI.time / 90
	local cr, cg, cb = Color.getR(color), Color.getG(color), Color.getB(color)
	for i = 0, 7 do
		local a = (i / 8) * 2 * pi + t * 0.35
		local alpha = 255 * (((i + floor(t)) % 8) + 1) / 8
		if fillCircle then
			fillCircle(cx + cos(a) * r, cy + sin(a) * r, 3, ColorA(cr, cg, cb, alpha))
		else
			fillRect(cx + cos(a) * r - 2, cx + cos(a) * r + 2, cy + sin(a) * r - 2, cy + sin(a) * r + 2, ColorA(cr, cg, cb, alpha))
		end
	end
end

---Animated placeholder for loading covers
function UI.shimmer(x0, y0, x1, y1)
	fillRect(x0, x1, y0, y1, COLOR_COVER)
	local w = x1 - x0
	local phase = (UI.time % 1400) / 1400
	local sx = x0 - w * 0.6 + phase * w * 2.2
	local bandW = w * 0.35
	local a0, a1 = max(x0, sx), min(x1, sx + bandW)
	if a1 > a0 then
		fillRect(a0, a1, y0, y1, ColorA(255, 255, 255, THEME_IS_DARK and 14 or 40))
	end
end

---Toggle switch (on/off), x,y = top-left. 40x22
function UI.toggle(x, y, on)
	if on then
		UI.roundRect(x, y, x + 40, y + 22, 11, COLOR_ACCENT)
		if fillCircle then
			fillCircle(x + 29, y + 11, 8, COLOR_ON_ACCENT)
		end
	else
		UI.roundRect(x, y, x + 40, y + 22, 11, COLOR_SURFACE2)
		if fillCircle then
			fillCircle(x + 11, y + 11, 8, COLOR_SUBFONT)
		end
	end
end

---Centered empty state message with a kaomoji
function UI.emptyState(cx, cy, title, subtitle, face)
	if face then
		UI.textCenter(FONT26, cx, cy - 60, face, COLOR_SUBFONT)
	end
	UI.textCenter(BONT16, cx, cy - 10, title or "", COLOR_FONT, 640)
	if subtitle then
		local lines = ToLines(subtitle)
		for i, line in ipairs(lines) do
			UI.textCenter(FONT16, cx, cy + 14 + (i - 1) * 22, line, COLOR_SUBFONT, 680)
		end
	end
end

---Selection highlight used by lists (soft accent fill + accent bar)
function UI.listHighlight(x0, y0, x1, y1, focused)
	local pulse = 0.5 + 0.5 * sin(UI.time / 260)
	UI.roundRect(x0, y0, x1, y1, 10, focused and COLOR_ACCENT_SOFT or COLOR_SURFACE2)
	if focused then
		fillRect(x0 + 2, x0 + 6, y0 + 10, y1 - 10, WithAlpha(COLOR_ACCENT, 160 + 95 * pulse))
	end
end

---Selection outline for menus and side panels (accent colored, softly breathing)
---@param alpha number|nil 0..1 fade multiplier
function UI.selectionRing(x0, y0, x1, y1, alpha)
	local pulse = 0.5 + 0.5 * sin(UI.time / 260)
	local c = WithAlpha(COLOR_ACCENT, (170 + 85 * pulse) * (alpha or 1))
	UI.roundOutline(x0, y0, x1, y1, 10, c, 2)
end

---Focus ring around covers
function UI.focusRing(x0, y0, x1, y1)
	local pulse = 0.5 + 0.5 * sin(UI.time / 260)
	local c = WithAlpha(COLOR_ACCENT, 170 + 85 * pulse)
	for i = 1, 3 do
		Graphics.fillEmptyRect(x0 - i, x1 + i, y0 - i, y1 + i, c)
	end
end

---Screen header (title + optional subtitle), drawn inside content area
function UI.header(title, subtitle, x)
	x = x or (Config.RAIL_WIDTH + 16)
	print(BONT30, x, 10, title or "", COLOR_FONT)
	if subtitle and subtitle ~= "" then
		print(FONT16, x + getTextWidth(BONT30, title or "") + 12, 22, subtitle, COLOR_SUBFONT)
	end
end

---Draws an icon tinted
function UI.icon(img, x, y, color)
	if img and img.e then
		drawImage(x, y, img.e, color or COLOR_FONT)
	end
end

---Vertical scrollbar on the right edge of content
function UI.scrollbar(x, y0, y1, offset, contentHeight, viewHeight)
	if contentHeight <= viewHeight then
		return
	end
	local h = y1 - y0
	local barH = max(24, h * viewHeight / contentHeight)
	local pos = y0 + (h - barH) * max(0, min(1, offset / (contentHeight - viewHeight)))
	UI.roundRect(x, pos, x + 4, pos + barH, 2, WithAlpha(COLOR_SUBFONT, 150))
end

---Shows the system keyboard and blocks until the user finishes.
---@return string|nil text (nil if cancelled)
function TextInput(title, default, maxLen, kbType)
	Keyboard.show(title or "", tostring(default or ""), maxLen or 128, kbType or TYPE_DEFAULT, MODE_TEXT, OPT_NO_AUTOCAP)
	while Keyboard.getState() == RUNNING do
		Graphics.initBlend()
		Screen.clear(COLOR_BACK)
		Graphics.termBlend()
		Screen.waitVblankStart()
		Screen.flip()
	end
	local result = nil
	if Keyboard.getState() == FINISHED then
		result = Keyboard.getInput()
	end
	Keyboard.clear()
	return result
end
