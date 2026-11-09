---First-run setup: a short sequence of dialogs for the essential settings
---(app language, source language, adult content, reading direction, orientation, confirm button, theme).
---Circle goes back one step; every choice is saved as soon as it is made.
Setup = {}

local DONE_FLAG = "ux0:data/otakio/.setup_done"
local active = false

local function LS()
	return Language[Settings.Language]
end

local function T(key)
	return LS().OTAKIO[key] or Language.English.OTAKIO[key] or key
end

local steps = {}

---App language -> source language group ticked by default
APP_LANG_GROUP = {
	English = "en", PortugueseBR = "pt", Spanish = "es", French = "fr", German = "de", Italian = "it",
	Russian = "ru", Japanese = "ja", ChineseSimplified = "zh", ChineseTraditional = "zh"
}
local current = 0

local function finish()
	FS.write(DONE_FLAG, Config.VERSION_NAME)
	Settings.save()
	Dialog.wizard({
		title = T("SETUP_DONE_TITLE"),
		message = T("SETUP_DONE"),
		items = {
			{label = T("SETUP_INSTALL_RECOMMENDED"), sub = T("SETUP_INSTALL_RECOMMENDED_SUB"), value = "rec"},
			{label = T("SETUP_FINISH"), value = "close"}
		},
		selected = 1,
		onBack = function()
			active = false
		end,
		onSelect = function(item)
			active = false
			if item.value == "rec" then
				-- the user asked for it: add the Otakio extension repository (Mihon model: nothing is preinstalled),
				-- then install its native sources for the active languages
				Extensions.installOfficial()
				Screens.EXTENSIONS.tab = 1
				Menu.setMode("EXTENSIONS")
			end
		end
	})
end

local function show(i)
	-- steps whose `skip()` is true (e.g. adult content locked) are jumped over in both directions
	local dir = i >= current and 1 or -1
	while steps[i] and steps[i].skip and steps[i].skip() do
		i = i + dir
	end
	if i < 1 then
		i = 1
		while steps[i] and steps[i].skip and steps[i].skip() do
			i = i + 1
		end
	end
	current = i
	local step = steps[i]
	if not step then
		finish()
		return
	end
	local visible = 0
	local index = 0
	for k, s in ipairs(steps) do
		if not (s.skip and s.skip()) then
			visible = visible + 1
			if k == i then
				index = visible
			end
		end
	end
	local title = string.format(T("SETUP_STEP"), index, visible) .. "  ·  " .. step.title()
	if step.multi then
		Dialog.wizard({
			multi = true,
			title = title,
			message = step.hint and T(step.hint) or nil,
			items = step.items(),
			onConfirm = function(result)
				step.apply(result)
				Settings.save()
				show(i + 1)
			end
		})
		return
	end
	local items, selected = step.items()
	Dialog.wizard({
		title = title,
		message = step.hint and T(step.hint) or nil,
		items = items,
		selected = selected,
		onSelect = function(item)
			step.apply(item.value)
			Settings.save()
			show(i + 1)
		end,
		onBack = function()
			if i > 1 then
				show(i - 1)
			else
				show(1)
			end
		end
	})
end

---Builds `items, selectedIndex` for a list of values
local function choices(values, current, label)
	local items, sel = {}, 1
	for k, v in ipairs(values) do
		local text, sub = label(v)
		items[k] = {label = text, sub = sub, value = v}
		if v == current then
			sel = k
		end
	end
	return items, sel
end

steps = {
	{
		title = function()
			return LS().SETTINGS.Language
		end,
		hint = "SETUP_LANG_HINT",
		items = function()
			local codes = {}
			for k in pairs(Language) do
				if k ~= "Default" and LanguageNames.English[k] then
					codes[#codes + 1] = k
				end
			end
			table.sort(codes, function(a, b)
				return (LanguageNames[a] and LanguageNames[a][a] or a) < (LanguageNames[b] and LanguageNames[b][b] or b)
			end)
			table.insert(codes, 1, "Default")
			return choices(codes, Settings.Language, function(k)
				local native = LanguageNames[k] and LanguageNames[k][k] or LanguageNames.English[k] or k
				local english = LanguageNames.English[k]
				return native, english ~= native and english or nil
			end)
		end,
		apply = function(v)
			Settings.Language = v
			GenPanels()
		end
	},
	{
		-- active source languages (checklist): only these show up as chips in Extensions and in Browse
		multi = true,
		title = function()
			return LS().SETTINGS.SourceLanguages or Language.English.SETTINGS.SourceLanguages
		end,
		hint = "SETUP_EXTLANG_HINT",
		items = function()
			local set = Settings.ExtLanguages
			local preset = type(set) == "table" and next(set) ~= nil
			local mine = APP_LANG_GROUP[Settings.Language] or (Settings.Language == "Default" and APP_LANG_GROUP[GetSystemLanguageName and GetSystemLanguageName() or ""]) or "en"
			local items = {}
			for _, g in ipairs(Screens.EXTENSIONS.langGroups()) do
				local checked
				if preset then
					checked = set[g.id] == true
				else
					checked = g.id == mine
				end
				items[#items + 1] = {label = LS().OTAKIO[g.label] or Language.English.OTAKIO[g.label] or g.id, value = g.id, checked = checked}
			end
			return items
		end,
		apply = function(result)
			local set = {}
			for _, item in ipairs(result) do
				if item.checked then
					set[item.value] = true
				end
			end
			Settings.ExtLanguages = set
			Screens.EXTENSIONS.languagesChanged()
		end
	},
	{
		title = function()
			return LS().SETTINGS.ShowNSFW
		end,
		hint = "SETUP_NSFW_HINT",
		skip = function()
			return NSFWLock
		end,
		items = function()
			return choices({false, true}, Settings.NSFW, function(v)
				return LS().NSFW[v]
			end)
		end,
		apply = function(v)
			if Settings.NSFW ~= v then
				Settings.NSFW = v
				ChangeNSFW()
			end
		end
	},
	{
		title = function()
			return LS().SETTINGS.ReaderDirection
		end,
		hint = "SETUP_DIRECTION_HINT",
		items = function()
			return choices({"LEFT", "RIGHT", "DOWN"}, Settings.ReaderDirection, function(v)
				return LS().READER[v]
			end)
		end,
		apply = function(v)
			Settings.ReaderDirection = v
		end
	},
	{
		title = function()
			return LS().SETTINGS.ReaderOrientation
		end,
		hint = "SETUP_ORIENTATION_HINT",
		items = function()
			return choices({"Horizontal", "Vertical"}, Settings.Orientation, function(v)
				return LS().READER[v]
			end)
		end,
		apply = function(v)
			Settings.Orientation = v
		end
	},
	{
		title = function()
			return LS().SETTINGS.SwapXO
		end,
		hint = "SETUP_KEYS_HINT",
		items = function()
			return choices({"EU", "JP"}, Settings.KeyType, function(v)
				return LS().SETTINGS[v]
			end)
		end,
		apply = function(v)
			Settings.setKeyType(v)
		end
	},
	{
		title = function()
			return LS().SETTINGS.ChangeUI
		end,
		items = function()
			return choices(GetThemes(), Settings.Theme, function(name)
				return LS().THEME[name] or name
			end)
		end,
		apply = function(v)
			Settings.Theme = v
			Settings.applyTheme(v)
		end
	}
}

---True on a fresh install that hasn't gone through the setup yet
function Setup.needed(firstRun)
	return firstRun and not FS.exists(DONE_FLAG)
end

function Setup.start()
	active = true
	current = 0
	show(1)
end

---True from the first setup screen until its last one is answered (the app update prompt waits for it)
function Setup.isActive()
	return active
end
