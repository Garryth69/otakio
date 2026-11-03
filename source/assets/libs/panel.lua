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
				local icon = ButtonsIcons[v]
				if v == "Cross" and Settings.KeyType == "JP" then
					icon = ButtonsIcons.Circle
				elseif v == "Circle" and Settings.KeyType == "JP" then
					icon = ButtonsIcons.Cross
				end
				Graphics.drawImage(x, 526 + y, icon.e)
				x = x + Graphics.getImageWidth(icon.e) + 4
			elseif v == "L\\R" then
				Graphics.drawImage(x, 526 + y, ButtonsIcons.L.e)
				x = x + 26
				Graphics.drawImage(x, 526 + y, ButtonsIcons.R.e)
				x = x + 28
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
