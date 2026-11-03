---Interface languages. Each one lives in lang_<code>.lua; English is the reference and
---fills any key another language doesn't translate.
Language = {}
for _, code in ipairs({"en", "pt", "es", "fr", "de", "it"}) do
	loadlib("lang_" .. code)
end

local ORDER = {"English", "PortugueseBR", "Spanish", "French", "German", "Italian"}
local NATIVE = {English = "English", PortugueseBR = "Português (Brasil)", Spanish = "Español", French = "Français", German = "Deutsch", Italian = "Italiano"}
local SYSTEM = {English = "System", PortugueseBR = "Sistema", Spanish = "Sistema", French = "Système", German = "System", Italian = "Sistema"}

---LanguageNames[lang][lang] is the native name, LanguageNames.English[lang] the English one
LanguageNames = {English = {PortugueseBR = "Portuguese (Brazil)", Spanish = "Spanish", French = "French", German = "German", Italian = "Italian"}}
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

-- PS Vita system language ids (sceAppUtil): 1/18 English, 2 French, 3 Spanish, 4 German, 5 Italian, 7/17 Portuguese
local SYSTEM_LANGUAGE = {[2] = "French", [3] = "Spanish", [4] = "German", [5] = "Italian", [7] = "PortugueseBR", [17] = "PortugueseBR"}
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
