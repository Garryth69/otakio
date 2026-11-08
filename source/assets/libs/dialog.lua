---Modal dialog: menus, single/multi choice lists and confirmations.
---  Dialog.menu(title, items, onSelect[, selectedIndex])   items = {{label=, sub=, value=}}
---  Dialog.choice(title, items, selectedIndex, onSelect)
---  Dialog.checklist(title, items, onConfirm)     items = {{label=, checked=}}
---  Dialog.confirm(title, message, onYes)
Dialog = {}

local state = nil
local fade = 0
local ROW = 46
local MAX_ROWS = 7
local WIDTH = 560

local function L()
	return Language[Settings.Language].OTAKIO
end

local function open(t)
	t.selected = t.selected or 1
	t.scroll = 0
	t.openTime = Timer.getTime(GlobalTimer)
	state = t
end

function Dialog.isOpen()
	return state ~= nil
end

function Dialog.close()
	-- clear first: onClose may open the next dialog (setup wizard going back a step)
	local s = state
	state = nil
	if s and s.onClose then
		s.onClose()
	end
end

function Dialog.menu(title, items, onSelect, selectedIndex)
	open({kind = "menu", title = title, items = items, onSelect = onSelect, selected = selectedIndex})
end

function Dialog.choice(title, items, selectedIndex, onSelect)
	for i, item in ipairs(items) do
		item.checked = i == selectedIndex
	end
	open({kind = "single", title = title, items = items, selected = selectedIndex or 1, onSelect = onSelect})
end

function Dialog.checklist(title, items, onConfirm)
	open({kind = "multi", title = title, items = items, onConfirm = onConfirm})
end

---Step of a wizard: a list with an explanatory message.
---  t = {title, message, items, selected, onSelect(item, i), onBack(), multi = bool, onConfirm(items)}
---With `multi`, items are checkboxes and Circle/Triangle/Start confirm; otherwise Circle calls onBack.
function Dialog.wizard(t)
	if t.multi then
		open({kind = "multi", title = t.title, message = t.message, items = t.items, onConfirm = t.onConfirm})
		return
	end
	for i, item in ipairs(t.items) do
		item.checked = i == t.selected
	end
	open({kind = "single", title = t.title, message = t.message, items = t.items, selected = t.selected or 1, onSelect = t.onSelect, onClose = t.onBack})
end

function Dialog.confirm(title, message, onYes)
	open({kind = "confirm", title = title, message = message, items = {{label = L().YES, value = true}, {label = L().NO, value = false}}, selected = 2, onSelect = function(item)
		if item.value and onYes then
			onYes()
		end
	end})
end

---Words of a "<button> word   <button> [/ <button>] word" hint string
local hintCache = {}
function hintWords(str)
	local c = hintCache[str]
	if not c then
		local parts = {}
		for part in (str .. "   "):gmatch("(.-)   +") do
			part = part:gsub("^%S+%s+/%s+%S+%s+", ""):gsub("^%S+%s+", "")
			parts[#parts + 1] = part
		end
		c = {parts[1] or "", parts[2] or ""}
		hintCache[str] = c
	end
	return c[1], c[2]
end

local function geometry()
	local rows = math.min(MAX_ROWS, #state.items)
	local msgH = 0
	if state.message then
		state.lines = state.lines or ToLines(state.message)
		msgH = #state.lines * 22 + 12
	end
	local h = 64 + msgH + rows * ROW + 44
	local x0 = 480 - WIDTH / 2
	local y0 = 272 - h / 2
	return x0, y0, x0 + WIDTH, y0 + h, rows, msgH
end

local function activate(index)
	local item = state.items[index]
	if not item then
		return
	end
	if state.kind == "multi" then
		item.checked = not item.checked
		return
	end
	local s = state
	state = nil
	if s.kind == "single" then
		for i, it in ipairs(s.items) do
			it.checked = i == index
		end
	end
	if s.onSelect then
		s.onSelect(item, index)
	end
end

local function confirmMulti()
	local s = state
	state = nil
	if s.onConfirm then
		s.onConfirm(s.items)
	end
end

function Dialog.input(oldPad, pad, oldTouch, touch)
	if not state then
		return
	end
	local function pressed(btn)
		return Controls.check(pad, btn) and not Controls.check(oldPad, btn)
	end
	local n = #state.items
	if pressed(SCE_CTRL_UP) then
		state.selected = state.selected > 1 and state.selected - 1 or n
	elseif pressed(SCE_CTRL_DOWN) then
		state.selected = state.selected < n and state.selected + 1 or 1
	elseif pressed(SCE_CTRL_CROSS) then
		activate(state.selected)
	elseif pressed(SCE_CTRL_CIRCLE) then
		if state and state.kind == "multi" then
			confirmMulti()
		else
			Dialog.close()
		end
	elseif state.kind == "multi" and (pressed(SCE_CTRL_TRIANGLE) or pressed(SCE_CTRL_START)) then
		confirmMulti()
	end
	if not state then
		return
	end
	-- touch: tap a row, tap outside closes
	if oldTouch.x and not touch.x and Timer.getTime(GlobalTimer) - state.openTime > 250 then
		local x0, y0, x1, y1, rows, msgH = geometry()
		local tx, ty = oldTouch.x, oldTouch.y
		if tx < x0 or tx > x1 or ty < y0 or ty > y1 then
			if state.kind == "multi" then
				confirmMulti()
			else
				Dialog.close()
			end
		else
			local listY = y0 + 56 + msgH
			local idx = math.floor((ty - listY) / ROW) + 1 + state.scroll
			if ty >= listY and idx >= 1 and idx <= n and idx <= state.scroll + rows then
				state.selected = idx
				activate(idx)
			elseif ty > y1 - 44 and state and state.kind == "multi" then
				confirmMulti()
			end
		end
	end
end

function Dialog.update()
	if state then
		fade = math.min(1, fade + 0.2)
		local _, _, _, _, rows = geometry()
		if state.selected - state.scroll > rows then
			state.scroll = state.selected - rows
		elseif state.selected - state.scroll < 1 then
			state.scroll = state.selected - 1
		end
	else
		fade = 0
	end
end

function Dialog.draw()
	if not state then
		return
	end
	Graphics.fillRect(0, 960, 0, 544, ColorA(0, 0, 0, 150 * fade))
	local x0, y0, x1, y1, rows, msgH = geometry()
	local dy = (1 - fade) * 30
	y0, y1 = y0 + dy, y1 + dy
	UI.roundRect(x0, y0, x1, y1, 16, COLOR_SURFACE)
	UI.text(BONT16, x0 + 24, y0 + 18, state.title or "", COLOR_FONT, WIDTH - 48)
	if state.lines then
		for i, line in ipairs(state.lines) do
			UI.text(FONT16, x0 + 24, y0 + 46 + (i - 1) * 22, line, COLOR_SUBFONT, WIDTH - 48)
		end
	end
	local listY = y0 + 56 + msgH
	for r = 1, rows do
		local i = r + state.scroll
		local item = state.items[i]
		if item then
			local ry = listY + (r - 1) * ROW
			if i == state.selected then
				UI.roundRect(x0 + 12, ry, x1 - 12, ry + ROW - 4, 10, COLOR_ACCENT_SOFT)
			end
			local tx = x0 + 28
			if state.kind == "multi" or state.kind == "single" then
				local icon
				if state.kind == "multi" then
					icon = item.checked and CheckboxCheckedIcon or CheckboxIcon
				else
					icon = item.checked and RadioCheckedIcon or RadioIcon
				end
				UI.icon(icon, tx, ry + 9, item.checked and COLOR_ACCENT or COLOR_SUBFONT)
				tx = tx + 34
			end
			local color = item.danger and COLOR_DANGER or COLOR_FONT
			if item.sub then
				UI.text(FONT16, tx, ry + 2, item.label, color, x1 - tx - 30)
				UI.text(FONT13, tx, ry + 23, item.sub, COLOR_SUBFONT, x1 - tx - 30)
			else
				UI.text(FONT20, tx, ry + 10, item.label, color, x1 - tx - 30)
			end
		end
	end
	if #state.items > rows then
		UI.scrollbar(x1 - 10, listY, listY + rows * ROW, state.scroll * ROW, #state.items * ROW, rows * ROW)
	end
	-- footer hints: button icons + the words of HINT_* ("X toggle   O / △ apply" -> "toggle", "apply")
	local first, second = hintWords(state.kind == "multi" and L().HINT_TOGGLE_APPLY or L().HINT_SELECT_BACK)
	DrawButtonHints(x1 - 24, y1 - 30, {{"Cross", first}, {"Circle", second}})
end
