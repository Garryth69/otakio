ConnectMessage = {}

local yOffset = 544
local yFinal = 0
local str

local easingFunction = EaseInOutCubic
local animationTimer = Timer.new()
local connectionTimer = Timer.new()

local is_active = false

local lines = {}
local LINE_H = 24
local PAD = 22

local function boxHeight()
	return #lines * LINE_H + PAD * 2
end

function ConnectMessage.show()
	str = Language[Settings.Language].MESSAGE.LOST_CONNECTION
	lines = ToLines(str)
	is_active = true
	yFinal = 544 / 2 - boxHeight() / 2
	Timer.reset(animationTimer)
end

function ConnectMessage.input(pad)
	if Controls.check(pad, SCE_CTRL_REAL_CROSS) and is_active and yOffset == yFinal then
		ChapterSaver.clearDownloadingList()
		is_active = false
		return SCE_CTRL_REAL_CROSS
	end
end

function ConnectMessage.update()
	local time = Timer.getTime(animationTimer)
	if is_active then
		time = math.max(1 - time / 800, 0)
		if Timer.getTime(connectionTimer) > 1000 then
			if Threads.isOnline() then
				is_active = false
			end
			Timer.reset(connectionTimer)
		end
	else
		time = math.min(time / 800, 1)
		Timer.reset(connectionTimer)
	end
	yOffset = yFinal + 544 * easingFunction(time)
end

function ConnectMessage.draw()
	if str and yOffset < 544 then
		-- a card in the theme's colors, like the other dialogs; ✕ is the physical Cross here (SCE_CTRL_REAL_CROSS)
		local shade = math.max(0, math.min(1, 1 - (yOffset - yFinal) / 544))
		Graphics.fillRect(0, 960, 0, 544, Color.new(0, 0, 0, math.floor(150 * shade)))
		UI.roundRect(100, yOffset, 860, yOffset + boxHeight(), 16, COLOR_SURFACE)
		for i, line in ipairs(lines) do
			local font, color = FONT16, COLOR_SUBFONT
			if i == 1 then
				font, color = BONT16, COLOR_FONT
			end
			UI.textCenterButtons(font, 480, yOffset + PAD + (i - 1) * LINE_H, line, color, true)
		end
	end
end

function ConnectMessage.isActive()
	return is_active
end
