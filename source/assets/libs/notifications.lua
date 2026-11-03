Notifications = {}

---Order of notification messages
local order = {}

---Active notification message
local notification = nil

---Easing function that used here
local easingFunction = EaseInOutCubic
local animationTimer = Timer.new()

---@param message string
---@param ms number
---Adds notification with given message that will be shown on screen
function Notifications.push(message, ms)
	order[#order + 1] = {
		ToLines(message),
		ms or 800,
		message
	}
end

---@param message string
---@param ms number
---Adds unique notification (if `message` is not in order) with given message that will be shown on screen
function Notifications.pushUnique(message, ms)
	if notification and notification[3] == message then
		return
	end
	for i = 1, #order do
		if order[i][3] == message then
			return
		end
	end
	order[#order + 1] = {
		ToLines(message),
		ms or 800,
		message
	}
end

---Updates notification animation
function Notifications.update()
	if not notification or Timer.getTime(animationTimer) > 1000 + notification[2] then
		notification = table.remove(order, 1)
		Timer.reset(animationTimer)
	end
end

---Draws notification on screen (toast card above the hint bar)
function Notifications.draw()
	if not notification then
		return
	end
	local time = Timer.getTime(animationTimer)
	local fade = 0
	if time < 300 then
		fade = time / 300
	elseif time < 300 + notification[2] + 400 then
		fade = 1
	elseif time < 1000 + notification[2] then
		fade = 1 - (time - 700 - notification[2]) / 300
	end
	fade = math.max(0, math.min(1, easingFunction(math.max(0, math.min(1, fade)))))
	local lines = notification[1]
	local width = 0
	for i = 1, #lines do
		width = math.max(width, Font.getTextWidth(FONT20, lines[i]))
	end
	width = math.min(width + 40, 900)
	local height = #lines * 26 + 16
	local x0 = 480 - width / 2
	local y0 = 544 - 34 - height * fade - 8 * fade
	local a = 255 * fade
	UI.roundRect(x0, y0, x0 + width, y0 + height, 12, WithAlpha(COLOR_SURFACE2, a))
	Graphics.fillRect(x0 + 6, x0 + 10, y0 + 10, y0 + height - 10, WithAlpha(COLOR_ACCENT, a))
	for i = 1, #lines do
		Font.print(FONT20, x0 + 22, y0 + 8 + (i - 1) * 26, lines[i], WithAlpha(COLOR_FONT, a))
	end
end
