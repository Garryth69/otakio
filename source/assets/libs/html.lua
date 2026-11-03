---Otakio HTML: tolerant HTML parser + CSS selector engine with a Jsoup-like API.
---Designed so Mihon/Tachiyomi (Kotlin + Jsoup) sources can be ported to Lua almost line by line:
---  local doc = Html.parse(body, baseUrl)
---  for _, el in ipairs(doc:select("div.page-item-detail")) do
---      local a = el:selectFirst(".post-title a")
---      print(a:text(), a:attr("abs:href"))
---  end
Html = {}

local byte, sub, find, lower, gsub, match, gmatch = string.byte, (string.rawsub or string.sub), string.find, string.lower, string.gsub, string.match, string.gmatch
local concat, insert = table.concat, table.insert
local tonumber, type, setmetatable, ipairs = tonumber, type, setmetatable, ipairs
local floor = math.floor
local co_running, co_yield = coroutine.running, coroutine.yield

local VOID = {
	area = true, base = true, br = true, col = true, embed = true, hr = true, img = true, input = true,
	link = true, meta = true, param = true, source = true, track = true, wbr = true
}

local RAW_TEXT = {script = true, style = true, textarea = true, title = true}

local CLOSES_P = {
	address = true, article = true, aside = true, blockquote = true, div = true, dl = true, fieldset = true,
	footer = true, form = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true, header = true,
	hr = true, main = true, nav = true, ol = true, p = true, pre = true, section = true, table = true, ul = true
}

local ENTITIES = {
	amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", hellip = "…", mdash = "—", ndash = "–",
	laquo = "«", raquo = "»", lsquo = "‘", rsquo = "’", ldquo = "“", rdquo = "”", copy = "©", reg = "®",
	trade = "™", middot = "·", bull = "•", deg = "°", times = "×", eacute = "é", egrave = "è", aacute = "á",
	agrave = "à", atilde = "ã", acirc = "â", ccedil = "ç", ecirc = "ê", iacute = "í", oacute = "ó", ocirc = "ô",
	otilde = "õ", uacute = "ú", uuml = "ü", ntilde = "ñ", Eacute = "É", Aacute = "Á", Ccedil = "Ç", ouml = "ö",
	auml = "ä", szlig = "ß"
}

local function utf8char(code)
	local char = string.char
	if code <= 0x7F then
		return char(code)
	elseif code <= 0x7FF then
		return char(0xC0 + floor(code / 0x40), 0x80 + (code % 0x40))
	elseif code <= 0xFFFF then
		return char(0xE0 + floor(code / 0x1000), 0x80 + (floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
	elseif code <= 0x10FFFF then
		return char(0xF0 + floor(code / 0x40000), 0x80 + (floor(code / 0x1000) % 0x40), 0x80 + (floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
	end
	return "?"
end

local function decodeEntity(e)
	if byte(e, 1) == 35 then
		local code
		if byte(e, 2) == 120 or byte(e, 2) == 88 then
			code = tonumber(sub(e, 3), 16)
		else
			code = tonumber(sub(e, 2))
		end
		return code and utf8char(code) or ("&" .. e .. ";")
	end
	return ENTITIES[e] or ("&" .. e .. ";")
end

---@param s string
---@return string
function Html.unescape(s)
	if not s or not find(s, "&", 1, true) then
		return s
	end
	return (gsub(s, "&(#?[%w]+);", decodeEntity))
end
local unescape = Html.unescape

-------------------------------------------------------------------------------
-- Node
-------------------------------------------------------------------------------

local Node = {}
Node.__index = Node
Html.Node = Node

local Elements = {}
Elements.__index = Elements
Html.Elements = Elements

local function newElement(tag, attrs, parent)
	return setmetatable({tag = tag, attrs = attrs, children = {}, parent = parent}, Node)
end

-------------------------------------------------------------------------------
-- Parser
-------------------------------------------------------------------------------

local function parseAttributes(s)
	local attrs = {}
	local pos = 1
	local len = #s
	while pos <= len do
		local ns, ne, name = find(s, "^[%s/]*([^%s=/>\"']+)", pos)
		if not ns then
			break
		end
		pos = ne + 1
		name = lower(name)
		local es, ee = find(s, "^%s*=%s*", pos)
		if es then
			pos = ee + 1
			local q = byte(s, pos)
			local value
			if q == 34 or q == 39 then
				local close = find(s, q == 34 and '"' or "'", pos + 1, true)
				if not close then
					close = len + 1
				end
				value = sub(s, pos + 1, close - 1)
				pos = close + 1
			else
				local vs, ve, v = find(s, "^([^%s>]+)", pos)
				value = v or ""
				pos = (ve or pos) + 1
			end
			if attrs[name] == nil then
				attrs[name] = unescape(value)
			end
		elseif attrs[name] == nil then
			attrs[name] = ""
		end
	end
	return attrs
end

---@param html string
---@param baseUrl string|nil
---@return table document
function Html.parse(html, baseUrl)
	html = html or ""
	local doc = newElement("#document", {}, nil)
	doc.baseUrl = baseUrl or ""
	doc.isDocument = true
	local stack = {doc}
	local top = doc
	local pos = 1
	local len = #html
	local tagCount = 0
	local canYield = co_running() ~= nil

	local function addText(text)
		if text ~= "" then
			local children = top.children
			children[#children + 1] = {t = text, parent = top}
		end
	end

	local function closeUntil(tag)
		for i = #stack, 2, -1 do
			if stack[i].tag == tag then
				for j = #stack, i, -1 do
					stack[j] = nil
				end
				top = stack[#stack]
				return true
			end
		end
		return false
	end

	local function inStack(tag, stopTags)
		for i = #stack, 2, -1 do
			local t = stack[i].tag
			if t == tag then
				return true
			end
			if stopTags and stopTags[t] then
				return false
			end
		end
		return false
	end

	local LIST_STOP = {ul = true, ol = true}
	local TABLE_STOP = {table = true}

	while pos <= len do
		local lt = find(html, "<", pos, true)
		if not lt then
			addText(sub(html, pos))
			break
		end
		if lt > pos then
			addText(sub(html, pos, lt - 1))
		end
		local c = byte(html, lt + 1)
		if c == 33 then -- <!
			if sub(html, lt, lt + 3) == "<!--" then
				local ce = find(html, "-->", lt + 4, true)
				pos = ce and ce + 3 or len + 1
			else
				local ce = find(html, ">", lt + 2, true)
				pos = ce and ce + 1 or len + 1
			end
		elseif c == 47 then -- </
			local s, e, tag = find(html, "^</%s*([%w:%-]+)[^>]*>", lt)
			if s then
				closeUntil(lower(tag))
				pos = e + 1
			else
				addText("<")
				pos = lt + 1
			end
		else
			local s, e, tag, rest = find(html, "^<([%a][%w:%-]*)(.-)>", lt)
			if not s then
				addText("<")
				pos = lt + 1
			else
				-- handle '>' inside quoted attribute values
				local q1 = select(2, gsub(rest, '"', ""))
				local q2 = select(2, gsub(rest, "'", ""))
				while (q1 % 2 == 1 or q2 % 2 == 1) do
					local ne = find(html, ">", e + 1, true)
					if not ne then
						break
					end
					rest = sub(html, lt + 1 + #tag, ne - 1)
					e = ne
					q1 = select(2, gsub(rest, '"', ""))
					q2 = select(2, gsub(rest, "'", ""))
				end
				tag = lower(tag)
				pos = e + 1
				local selfClosing = byte(rest, -1) == 47
				local attrs = parseAttributes(rest)
				-- implicit closes
				if tag == "li" and inStack("li", LIST_STOP) then
					closeUntil("li")
				elseif (tag == "td" or tag == "th") and (inStack("td", TABLE_STOP) or inStack("th", TABLE_STOP)) then
					if not closeUntil("td") then
						closeUntil("th")
					end
				elseif tag == "tr" and inStack("tr", TABLE_STOP) then
					closeUntil("tr")
				elseif tag == "option" and top.tag == "option" then
					closeUntil("option")
				elseif CLOSES_P[tag] and inStack("p", {div = true, li = true, td = true, th = true, body = true}) then
					closeUntil("p")
				end
				local el = newElement(tag, attrs, top)
				local children = top.children
				children[#children + 1] = el
				if RAW_TEXT[tag] and not selfClosing then
					local cs, ce2 = find(html, "</" .. tag .. "%s*>", pos)
					if not cs then
						cs, ce2 = find(lower(sub(html, pos)), "</" .. tag .. "%s*>")
						if cs then
							cs, ce2 = cs + pos - 1, ce2 + pos - 1
						end
					end
					local raw = sub(html, pos, (cs or len + 1) - 1)
					if raw ~= "" then
						el.children[1] = {t = raw, parent = el, raw = (tag == "script" or tag == "style") or nil}
					end
					pos = (ce2 or len) + 1
				elseif not (VOID[tag] or selfClosing) then
					stack[#stack + 1] = el
					top = el
				end
				tagCount = tagCount + 1
				if canYield and tagCount % 600 == 0 then
					co_yield(false)
				end
			end
		end
	end
	return doc
end

-------------------------------------------------------------------------------
-- Text helpers
-------------------------------------------------------------------------------

local function normalize(s)
	-- NBSP is the two-byte sequence C2 A0: replace it as a whole. A byte set like [\194\160] would also eat
	-- the A0 byte of "à" (C3 A0) and leave broken UTF-8 behind.
	s = gsub(s, "\194\160", " ")
	s = gsub(s, "%s+", " ")
	s = gsub(s, "^ ", "")
	return (gsub(s, " $", ""))
end

local function collectText(node, out)
	local children = node.children
	for i = 1, #children do
		local child = children[i]
		if child.t then
			if not child.raw then
				out[#out + 1] = child.t
			end
		elseif child.tag == "br" then
			out[#out + 1] = " "
		elseif child.tag ~= "script" and child.tag ~= "style" then
			collectText(child, out)
		end
	end
end

---Full normalized text of element and descendants (Jsoup `text()`)
function Node:text()
	local out = {}
	collectText(self, out)
	return normalize(unescape(concat(out, " ")))
end

---Text of element itself, without children elements (Jsoup `ownText()`)
function Node:ownText()
	local out = {}
	for _, child in ipairs(self.children) do
		if child.t and not child.raw then
			out[#out + 1] = child.t
		end
	end
	return normalize(unescape(concat(out, " ")))
end

---Text with line breaks kept for <br> and <p> (good for descriptions)
function Node:wholeText()
	local out = {}
	local function walk(node)
		for _, child in ipairs(node.children) do
			if child.t then
				if not child.raw then
					out[#out + 1] = gsub(child.t, "%s+", " ")
				end
			elseif child.tag == "br" then
				out[#out + 1] = "\n"
			elseif child.tag ~= "script" and child.tag ~= "style" then
				local block = child.tag == "p" or child.tag == "div" or child.tag == "li"
				walk(child)
				if block then
					out[#out + 1] = "\n"
				end
			end
		end
	end
	walk(self)
	local s = unescape(concat(out))
	s = gsub(s, " *\n *", "\n")
	s = gsub(s, "\n\n\n+", "\n\n")
	return (gsub(gsub(s, "^%s+", ""), "%s+$", ""))
end

---Raw inner data (script contents etc.)
function Node:data()
	local out = {}
	for _, child in ipairs(self.children) do
		if child.t then
			out[#out + 1] = child.t
		end
	end
	return concat(out)
end

local function serialize(node, out)
	if node.t then
		out[#out + 1] = node.t
		return
	end
	out[#out + 1] = "<" .. node.tag
	for k, v in pairs(node.attrs) do
		out[#out + 1] = " " .. k .. '="' .. gsub(v, '"', "&quot;") .. '"'
	end
	out[#out + 1] = ">"
	if not VOID[node.tag] then
		for _, child in ipairs(node.children) do
			serialize(child, out)
		end
		out[#out + 1] = "</" .. node.tag .. ">"
	end
end

function Node:html()
	local out = {}
	for _, child in ipairs(self.children) do
		serialize(child, out)
	end
	return concat(out)
end

function Node:outerHtml()
	local out = {}
	serialize(self, out)
	return concat(out)
end

-------------------------------------------------------------------------------
-- Attributes / navigation
-------------------------------------------------------------------------------

local function getDocument(node)
	while node.parent do
		node = node.parent
	end
	return node
end

---Resolves `url` against `base`
---@param base string
---@param url string
---@return string
function Html.absUrl(base, url)
	if not url or url == "" then
		return ""
	end
	url = gsub(url, "^%s+", "")
	url = gsub(url, "%s+$", "")
	if find(url, "^%a[%w+.-]*:") then
		return url
	end
	base = base or ""
	local scheme, host = match(base, "^(%a[%w+.-]*):%/%/([^/?#]*)")
	if not scheme then
		return url
	end
	if sub(url, 1, 2) == "//" then
		return scheme .. ":" .. url
	end
	if byte(url, 1) == 47 then
		return scheme .. "://" .. host .. url
	end
	if byte(url, 1) == 63 then
		return (match(base, "^([^?#]*)") or base) .. url
	end
	local path = match(base, "^%a[%w+.-]*:%/%/[^/?#]*(/[^?#]*)") or "/"
	path = gsub(path, "[^/]*$", "")
	local full = path .. url
	-- resolve ./ and ../
	local parts = {}
	for seg in gmatch(full, "[^/]+") do
		if seg == ".." then
			parts[#parts] = nil
		elseif seg ~= "." then
			parts[#parts + 1] = seg
		end
	end
	local trailing = sub(full, -1) == "/" and "/" or ""
	return scheme .. "://" .. host .. "/" .. concat(parts, "/") .. (#parts > 0 and trailing or "")
end

---Gets attribute value. Supports Jsoup style "abs:href".
function Node:attr(name)
	if not self.attrs then
		return ""
	end
	if sub(name, 1, 4) == "abs:" then
		local v = self.attrs[lower(sub(name, 5))]
		if not v or v == "" then
			return ""
		end
		return Html.absUrl(getDocument(self).baseUrl, v)
	end
	return self.attrs[lower(name)] or ""
end

function Node:absUrl(name)
	return self:attr("abs:" .. name)
end

function Node:hasAttr(name)
	if sub(name, 1, 4) == "abs:" then
		name = sub(name, 5)
	end
	return self.attrs ~= nil and self.attrs[lower(name)] ~= nil
end

local function classSet(node)
	local set = node._classes
	if not set then
		set = {}
		local cls = node.attrs and node.attrs.class
		if cls then
			for c in gmatch(cls, "%S+") do
				set[c] = true
			end
		end
		node._classes = set
	end
	return set
end

function Node:hasClass(name)
	return classSet(self)[name] == true
end

function Node:tagName()
	return self.tag
end

function Node:id()
	return self.attrs and self.attrs.id or ""
end

---Element children (no text nodes)
function Node:childrenElements()
	local out = setmetatable({}, Elements)
	for _, child in ipairs(self.children) do
		if child.tag then
			out[#out + 1] = child
		end
	end
	return out
end

function Node:parentElement()
	local p = self.parent
	if p and not p.isDocument then
		return p
	end
end

local function elementIndex(node)
	local p = node.parent
	if not p then
		return 1, 1
	end
	local idx, total = 0, 0
	for _, child in ipairs(p.children) do
		if child.tag then
			total = total + 1
			if child == node then
				idx = total
			end
		end
	end
	return idx, total
end

function Node:nextElementSibling()
	local p = self.parent
	if not p then
		return nil
	end
	local found = false
	for _, child in ipairs(p.children) do
		if found and child.tag then
			return child
		end
		if child == self then
			found = true
		end
	end
end

function Node:previousElementSibling()
	local p = self.parent
	if not p then
		return nil
	end
	local prev
	for _, child in ipairs(p.children) do
		if child == self then
			return prev
		end
		if child.tag then
			prev = child
		end
	end
end

-------------------------------------------------------------------------------
-- Selector compiler
-------------------------------------------------------------------------------

local selectorCache = setmetatable({}, {__mode = "v"})

local parseSelectorGroup

local function trim(s)
	return (gsub(gsub(s, "^%s+", ""), "%s+$", ""))
end

---Splits on top-level commas (ignores commas inside () or [])
local function splitTopLevel(s, sepByte)
	local parts = {}
	local depth = 0
	local quote = nil
	local start = 1
	for i = 1, #s do
		local c = byte(s, i)
		if quote then
			if c == quote then
				quote = nil
			end
		elseif c == 34 or c == 39 then
			quote = c
		elseif c == 40 or c == 91 then
			depth = depth + 1
		elseif c == 41 or c == 93 then
			depth = depth - 1
		elseif c == sepByte and depth == 0 then
			parts[#parts + 1] = sub(s, start, i - 1)
			start = i + 1
		end
	end
	parts[#parts + 1] = sub(s, start)
	return parts
end

local function readParen(s, i)
	-- s[i] == "(" ; returns content and index after ")"
	local depth = 0
	local quote
	for j = i, #s do
		local c = byte(s, j)
		if quote then
			if c == quote then
				quote = nil
			end
		elseif c == 34 or c == 39 then
			quote = c
		elseif c == 40 then
			depth = depth + 1
		elseif c == 41 then
			depth = depth - 1
			if depth == 0 then
				return sub(s, i + 1, j - 1), j + 1
			end
		end
	end
	return sub(s, i + 1), #s + 1
end

local function unquote(v)
	v = trim(v)
	local q = byte(v, 1)
	if (q == 34 or q == 39) and byte(v, -1) == q then
		return sub(v, 2, -2)
	end
	return v
end

---Parses a compound selector (e.g. `div.foo#bar[x^=y]:not(.z)`) into a list of tests
local function parseCompound(s)
	local tests = {}
	local i = 1
	local len = #s
	local tagMatch = match(s, "^([%w%-%*_|]+)")
	if tagMatch then
		if tagMatch ~= "*" then
			tests.tag = lower(tagMatch)
		end
		i = #tagMatch + 1
	end
	while i <= len do
		local c = sub(s, i, i)
		if c == "." then
			local name = match(s, "^([%w%-_]+)", i + 1)
			if not name then
				break
			end
			tests[#tests + 1] = {"class", name}
			i = i + 1 + #name
		elseif c == "#" then
			local name = match(s, "^([%w%-_:]+)", i + 1)
			if not name then
				break
			end
			tests[#tests + 1] = {"id", name}
			i = i + 1 + #name
		elseif c == "[" then
			local close = find(s, "]", i, true)
			local inner = sub(s, i + 1, (close or len + 1) - 1)
			local name, op, value = match(inner, "^%s*([^%s~|%^%$%*!=]+)%s*([~|%^%$%*!]?=)%s*(.-)%s*$")
			if name then
				tests[#tests + 1] = {"attr", lower(name), op, unquote(value)}
			else
				tests[#tests + 1] = {"attr", lower(trim(inner))}
			end
			i = (close or len) + 1
		elseif c == ":" then
			local name = match(s, "^([%w%-]+)", i + 1)
			if not name then
				break
			end
			i = i + 1 + #name
			local arg
			if sub(s, i, i) == "(" then
				arg, i = readParen(s, i)
			end
			name = lower(name)
			if name == "not" then
				tests[#tests + 1] = {"not", parseSelectorGroup(arg or "")}
			elseif name == "has" then
				tests[#tests + 1] = {"has", parseSelectorGroup(arg or "")}
			elseif name == "contains" or name == "containsown" then
				tests[#tests + 1] = {name, lower(unquote(arg or ""))}
			elseif name == "matches" or name == "matchesown" then
				tests[#tests + 1] = {name, unquote(arg or "")}
			elseif name == "first-child" then
				tests[#tests + 1] = {"nth", 1}
			elseif name == "last-child" then
				tests[#tests + 1] = {"nthlast", 1}
			elseif name == "nth-child" then
				tests[#tests + 1] = {"nth", tonumber(arg) or arg}
			elseif name == "nth-last-child" then
				tests[#tests + 1] = {"nthlast", tonumber(arg) or 1}
			elseif name == "eq" then
				tests[#tests + 1] = {"eq", (tonumber(arg) or 0) + 1}
			elseif name == "lt" then
				tests[#tests + 1] = {"lt", (tonumber(arg) or 0) + 1}
			elseif name == "gt" then
				tests[#tests + 1] = {"gt", (tonumber(arg) or 0) + 1}
			elseif name == "empty" then
				tests[#tests + 1] = {"empty"}
			end
		else
			i = i + 1
		end
	end
	return tests
end

local matchGroup

local function nthMatch(expr, idx)
	if type(expr) == "number" then
		return idx == expr
	end
	if expr == "odd" then
		return idx % 2 == 1
	elseif expr == "even" then
		return idx % 2 == 0
	end
	local a, b = match(expr or "", "^%s*([%+%-]?%d*)n%s*([%+%-]?%s*%d*)%s*$")
	if a then
		a = (a == "" or a == "+") and 1 or (a == "-" and -1) or tonumber(a)
		b = tonumber((gsub(b, "%s", ""))) or 0
		if a == 0 then
			return idx == b
		end
		local n = (idx - b) / a
		return n >= 0 and floor(n) == n
	end
	return false
end

local function matchCompound(node, tests)
	if not node.tag or node.isDocument then
		return false
	end
	if tests.tag and node.tag ~= tests.tag then
		return false
	end
	for k = 1, #tests do
		local t = tests[k]
		local kind = t[1]
		if kind == "class" then
			if not classSet(node)[t[2]] then
				return false
			end
		elseif kind == "id" then
			if node.attrs.id ~= t[2] then
				return false
			end
		elseif kind == "attr" then
			local v = node.attrs[t[2]]
			if v == nil then
				return false
			end
			local op, val = t[3], t[4]
			if op then
				if op == "=" then
					if v ~= val then
						return false
					end
				elseif op == "^=" then
					if val == "" or sub(v, 1, #val) ~= val then
						return false
					end
				elseif op == "$=" then
					if val == "" or sub(v, -#val) ~= val then
						return false
					end
				elseif op == "*=" then
					if val == "" or not find(v, val, 1, true) then
						return false
					end
				elseif op == "~=" then
					local ok = false
					for w in gmatch(v, "%S+") do
						if w == val then
							ok = true
							break
						end
					end
					if not ok then
						return false
					end
				elseif op == "|=" then
					if v ~= val and sub(v, 1, #val + 1) ~= val .. "-" then
						return false
					end
				elseif op == "!=" then
					if v == val then
						return false
					end
				end
			end
		elseif kind == "not" then
			if matchGroup(node, t[2]) then
				return false
			end
		elseif kind == "has" then
			if not node:selectFirstCompiled(t[2]) then
				return false
			end
		elseif kind == "contains" then
			if not find(lower(node:text()), t[2], 1, true) then
				return false
			end
		elseif kind == "containsown" then
			if not find(lower(node:ownText()), t[2], 1, true) then
				return false
			end
		elseif kind == "matches" then
			if not find(node:text(), t[2]) then
				return false
			end
		elseif kind == "matchesown" then
			if not find(node:ownText(), t[2]) then
				return false
			end
		elseif kind == "nth" then
			local idx = elementIndex(node)
			if not nthMatch(t[2], idx) then
				return false
			end
		elseif kind == "nthlast" then
			local idx, total = elementIndex(node)
			if total - idx + 1 ~= t[2] then
				return false
			end
		elseif kind == "empty" then
			for _, child in ipairs(node.children) do
				if child.tag or (child.t and find(child.t, "%S")) then
					return false
				end
			end
		end
		-- eq/lt/gt are applied on results list, see select()
	end
	return true
end

---Parses complex selector "a > b c + d" into steps (right-to-left matching)
local function parseComplex(s)
	s = trim(s)
	local steps = {}
	local i = 1
	local len = #s
	local combinator = nil
	local buf = {}
	local depth = 0
	local quote
	local function flush()
		local text = concat(buf)
		buf = {}
		if text ~= "" then
			steps[#steps + 1] = {tests = parseCompound(text), comb = combinator}
			combinator = nil
		end
	end
	while i <= len do
		local c = byte(s, i)
		local ch = sub(s, i, i)
		if quote then
			buf[#buf + 1] = ch
			if c == quote then
				quote = nil
			end
		elseif c == 34 or c == 39 then
			quote = c
			buf[#buf + 1] = ch
		elseif c == 40 or c == 91 then
			depth = depth + 1
			buf[#buf + 1] = ch
		elseif c == 41 or c == 93 then
			depth = depth - 1
			buf[#buf + 1] = ch
		elseif depth == 0 and (ch == ">" or ch == "+" or ch == "~") then
			flush()
			combinator = ch
		elseif depth == 0 and (ch == " " or ch == "\t" or ch == "\n") then
			if #buf > 0 then
				flush()
				combinator = combinator or " "
			end
		else
			if #buf == 0 and combinator == nil and #steps > 0 then
				combinator = " "
			end
			buf[#buf + 1] = ch
		end
		i = i + 1
	end
	flush()
	-- the combinator stored on a step relates it to the previous step
	return steps
end

parseSelectorGroup = function(s)
	local cached = selectorCache[s]
	if cached then
		return cached
	end
	local group = {}
	for _, part in ipairs(splitTopLevel(s, 44)) do
		part = trim(part)
		if part ~= "" then
			local steps = parseComplex(part)
			-- leading combinator like "> li" (relative to context)
			if steps[1] and steps[1].comb then
				steps.relative = steps[1].comb
				steps[1].comb = nil
			end
			-- result filters :eq/:lt/:gt on last step
			local last = steps[#steps]
			if last then
				for _, t in ipairs(last.tests) do
					if t[1] == "eq" or t[1] == "lt" or t[1] == "gt" then
						steps.filter = t
					end
				end
			end
			group[#group + 1] = steps
		end
	end
	selectorCache[s] = group
	return group
end

local function matchSteps(node, steps, idx, root)
	local step = steps[idx]
	if not matchCompound(node, step.tests) then
		return false
	end
	if idx == 1 then
		if steps.relative == ">" then
			return node.parent == root
		end
		return true
	end
	local comb = step.comb or " "
	if comb == " " then
		local p = node.parent
		while p and p ~= root do
			if matchSteps(p, steps, idx - 1, root) then
				return true
			end
			p = p.parent
		end
		if root and not root.isDocument and p == root and idx - 1 >= 1 and not steps.relative then
			return false
		end
		return false
	elseif comb == ">" then
		local p = node.parent
		return p ~= nil and p ~= root and matchSteps(p, steps, idx - 1, root)
	elseif comb == "+" then
		local prev = node:previousElementSibling()
		return prev ~= nil and matchSteps(prev, steps, idx - 1, root)
	elseif comb == "~" then
		local prev = node:previousElementSibling()
		while prev do
			if matchSteps(prev, steps, idx - 1, root) then
				return true
			end
			prev = prev:previousElementSibling()
		end
		return false
	end
	return false
end

matchGroup = function(node, group)
	for g = 1, #group do
		local steps = group[g]
		if #steps > 0 and matchSteps(node, steps, #steps, nil) then
			return true
		end
	end
	return false
end

local function walk(root, fn)
	local stack = {}
	local children = root.children
	for i = #children, 1, -1 do
		stack[#stack + 1] = children[i]
	end
	while #stack > 0 do
		local node = stack[#stack]
		stack[#stack] = nil
		if node.tag then
			if fn(node) then
				return node
			end
			local ch = node.children
			for i = #ch, 1, -1 do
				stack[#stack + 1] = ch[i]
			end
		end
	end
end

local function selectCompiled(root, group, firstOnly)
	local results = setmetatable({}, Elements)
	local seen = #group > 1 and {} or nil
	local found = walk(
		root,
		function(node)
			for g = 1, #group do
				local steps = group[g]
				if #steps > 0 and not steps.filter and matchSteps(node, steps, #steps, root) then
					if seen then
						if not seen[node] then
							seen[node] = true
							results[#results + 1] = node
						end
					else
						results[#results + 1] = node
					end
					return firstOnly
				end
			end
			return false
		end
	)
	-- groups with :eq/:lt/:gt filters
	for g = 1, #group do
		local steps = group[g]
		if steps.filter then
			local matched = {}
			walk(
				root,
				function(node)
					if matchSteps(node, steps, #steps, root) then
						matched[#matched + 1] = node
					end
				end
			)
			local f = steps.filter
			for i, node in ipairs(matched) do
				if (f[1] == "eq" and i == f[2]) or (f[1] == "lt" and i < f[2]) or (f[1] == "gt" and i > f[2]) then
					results[#results + 1] = node
				end
			end
		end
	end
	if firstOnly then
		return results[1]
	end
	return results
end

---@param css string
---@return table Elements
function Node:select(css)
	return selectCompiled(self, parseSelectorGroup(css), false)
end

---@param css string
---@return table|nil
function Node:selectFirst(css)
	return selectCompiled(self, parseSelectorGroup(css), true)
end

function Node:selectFirstCompiled(group)
	return selectCompiled(self, group, true)
end

---@param css string
---@return boolean
function Node:is(css)
	return matchGroup(self, parseSelectorGroup(css))
end

-------------------------------------------------------------------------------
-- Elements (list) helpers, Jsoup-like
-------------------------------------------------------------------------------

function Elements:first()
	return self[1]
end

function Elements:last()
	return self[#self]
end

function Elements:size()
	return #self
end

function Elements:isEmpty()
	return #self == 0
end

function Elements:attr(name)
	for i = 1, #self do
		if self[i]:hasAttr(name) then
			return self[i]:attr(name)
		end
	end
	return ""
end

function Elements:text()
	local out = {}
	for i = 1, #self do
		out[#out + 1] = self[i]:text()
	end
	return concat(out, " ")
end

function Elements:eachText()
	local out = {}
	for i = 1, #self do
		local t = self[i]:text()
		if t ~= "" then
			out[#out + 1] = t
		end
	end
	return out
end

function Elements:eachAttr(name)
	local out = {}
	for i = 1, #self do
		if self[i]:hasAttr(name) then
			out[#out + 1] = self[i]:attr(name)
		end
	end
	return out
end

function Elements:select(css)
	local out = setmetatable({}, Elements)
	local seen = {}
	local group = parseSelectorGroup(css)
	for i = 1, #self do
		local found = selectCompiled(self[i], group, false)
		for j = 1, #found do
			if not seen[found[j]] then
				seen[found[j]] = true
				out[#out + 1] = found[j]
			end
		end
	end
	return out
end

function Elements:selectFirst(css)
	local group = parseSelectorGroup(css)
	for i = 1, #self do
		local found = selectCompiled(self[i], group, true)
		if found then
			return found
		end
	end
end
