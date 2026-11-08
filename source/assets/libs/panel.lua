---Table of Panel functions
Panel = {}

---Table of actions
local hints = {}
local status = "HIDE"

---Textures for PS Buttons
ButtonsIcons = {
	Cross = Image:new(Graphics.loadImage("app0:assets/images/cross_button.png")),
	Triangle = Image:new(Graphics.loadImage("app0:assets/images/triangle_button.png")),
	Square = Image:new(Graphics.loadImage("app0:assets/images/square_button.png")),
	Circle = Image:new(Graphics.loadImage("app0:assets/images/circle_button.png")),
	DPad = Image:new(Graphics.loadImage("app0:assets/images/dpad.png")),
	Select = Image:new(Graphics.loadImage("app0:assets/images/select_button.png")),
	Start = Image:new(Graphics.loadImage("app0:assets/images/start_button.png")),
	R = Image:new(Graphics.loadImage("app0:assets/images/r_button.png")),
	L = Image:new(Graphics.loadImage("app0:assets/images/l_button.png"))
}

---Icon of a button, following the confirm-button setting (O confirms on Japanese consoles)
function ButtonIcon(name)
	if Settings.KeyType == "JP" then
		if name == "Cross" then
			return ButtonsIcons.Circle
		elseif name == "Circle" then
			return ButtonsIcons.Cross
		end
	end
	return ButtonsIcons[name]
end

---Draws `{{button, text}, ...}` right-aligned so the last hint ends at `xRight` (same look as the hint bar)
function DrawButtonHints(xRight, y, list, color)
	local width = 0
	for i, h in ipairs(list) do
		local icon = ButtonIcon(h[1])
		width = width + (icon and Graphics.getImageWidth(icon.e) + 4 or 0) + Font.getTextWidth(FONT13, h[2]) + (i > 1 and 16 or 0)
	end
	local x = xRight - width
	for _, h in ipairs(list) do
		local icon = ButtonIcon(h[1])
		if icon then
			Graphics.drawImage(x, y + 1, icon.e)
			x = x + Graphics.getImageWidth(icon.e) + 4
		end
		Font.print(FONT13, x, y, h[2], color or COLOR_SUBFONT)
		x = x + Font.getTextWidth(FONT13, h[2]) + 16
	end
end

---Hides Panel
function Panel.hide()
	if status ~= "SHOW" then
		return
	end
	status = "HIDE"
end

---Shows Panel
function Panel.show()
	if status ~= "HIDE" then
		return
	end
	status = "SHOW"
end

---@param buttons table
---Sets table of actions
function Panel.set(buttons)
	hints = buttons
end

---Local variable used as vertical offset of panel
local y = 23

---Updates Panel Animation
function Panel.update()
	if status == "HIDE" then
		y = math.min(23, y + (23 - y) / 4)
	elseif status == "SHOW" then
		y = math.max(0, y - y / 4)
	end
end

---Draws Panel on screen
function Panel.draw()
	if y >= 23 then
		return
	end
	Graphics.fillRect(0, 960, 523 + y, 544, COLOR_RAIL)
	Graphics.fillRect(0, 960, 523 + y, 524 + y, COLOR_DIVIDER)
	local x = 14
	local hintColor = COLOR_SUBFONT
	for i = 1, #hints do
		local v = hints[i]
		if hints[v] then
			if ButtonsIcons[v] then
				local icon = ButtonIcon(v)
				Graphics.drawImage(x, 527 + y, icon.e)
				x = x + Graphics.getImageWidth(icon.e) + 4
			elseif v == "L\\R" then
				Graphics.drawImage(x, 527 + y, ButtonsIcons.L.e)
				x = x + Graphics.getImageWidth(ButtonsIcons.L.e) + 2
				Graphics.drawImage(x, 527 + y, ButtonsIcons.R.e)
				x = x + Graphics.getImageWidth(ButtonsIcons.R.e) + 4
			else
				Font.print(FONT13, x, 526 + y, v, hintColor)
				x = x + Font.getTextWidth(FONT13, v) + 5
			end
			Font.print(FONT13, x, 526 + y, hints[v], hintColor)
			x = x + Font.getTextWidth(FONT13, hints[v]) + 16
		end
	end
	if FrameStats.show then
		local t = string.format("%d fps", FrameStats.fps)
		Font.print(FONT13, 946 - Font.getTextWidth(FONT13, t), 526 + y, t, hintColor)
	end
end
