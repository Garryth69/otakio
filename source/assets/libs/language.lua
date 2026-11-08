---Interface languages. Each one lives in lang_<code>.lua; English is the reference and
---fills any key another language doesn't translate.
Language = {}
for _, code in ipairs({"en", "pt", "es", "fr", "de", "it", "ru", "ja", "zhs", "zht"}) do
	loadlib("lang_" .. code)
end

local ORDER = {"English", "PortugueseBR", "Spanish", "French", "German", "Italian", "Russian", "Japanese", "ChineseSimplified", "ChineseTraditional"}
local NATIVE = {English = "English", PortugueseBR = "Português (Brasil)", Spanish = "Español", French = "Français", German = "Deutsch", Italian = "Italiano", Russian = "Русский", Japanese = "日本語", ChineseSimplified = "简体中文", ChineseTraditional = "繁體中文"}
local SYSTEM = {English = "System", PortugueseBR = "Sistema", Spanish = "Sistema", French = "Système", German = "System", Italian = "Sistema", Russian = "Системный", Japanese = "システム", ChineseSimplified = "系统", ChineseTraditional = "系統"}

---LanguageNames[lang][lang] is the native name, LanguageNames.English[lang] the English one
LanguageNames = {English = {PortugueseBR = "Portuguese (Brazil)", Spanish = "Spanish", French = "French", German = "German", Italian = "Italian", Russian = "Russian", Japanese = "Japanese", ChineseSimplified = "Chinese (Simplified)", ChineseTraditional = "Chinese (Traditional)"}}
for _, name in ipairs(ORDER) do
	LanguageNames[name] = LanguageNames[name] or {}
	LanguageNames[name][name] = NATIVE[name]
	LanguageNames[name].Default = SYSTEM[name]
end
LanguageNames.English.English = "English"

local function fallback(t, ref)
	for k, v in pairs(ref) do
		if type(v) == "table" then
			if type(t[k]) ~= "table" then
				t[k] = {}
			end
			fallback(t[k], v)
		end
	end
	setmetatable(t, {__index = ref})
end

for _, name in ipairs(ORDER) do
	if name ~= "English" then
		fallback(Language[name], Language.English)
	end
end

-- PS Vita system language ids (sceAppUtil): 0 Japanese, 1/18 English, 2 French, 3 Spanish, 4 German, 5 Italian, 7/17 Portuguese,
-- 8 Russian, 10 Chinese (Traditional), 11 Chinese (Simplified)
local SYSTEM_LANGUAGE = {[0] = "Japanese", [2] = "French", [3] = "Spanish", [4] = "German", [5] = "Italian", [7] = "PortugueseBR", [8] = "Russian", [10] = "ChineseTraditional", [11] = "ChineseSimplified", [17] = "PortugueseBR"}
local systemName = SYSTEM_LANGUAGE[System.getLanguage()] or "English"
Language.Default = Language[systemName]
LanguageNames.Default = {Default = SYSTEM[systemName] .. " (" .. NATIVE[systemName] .. ")"}
LanguageNames.English.Default = "System"

---Name of the language selected by the system ("Default" resolves to it)
function GetSystemLanguageName()
	return systemName
end

function GetLanguages()
	return ORDER
end
