---Small JSON decoder/encoder for Otakio extensions and repository indexes.
---Decoder is iterative-friendly: if `yieldEvery` is passed and we're inside a coroutine,
---it yields periodically so huge payloads don't freeze the UI.
Json = {}

local byte, sub, find, char, concat = string.byte, (string.rawsub or string.sub), string.find, string.char, table.concat
local tonumber, tostring, type, pairs, ipairs = tonumber, tostring, type, pairs, ipairs
local floor = math.floor
local co_running, co_yield = coroutine.running, coroutine.yield

Json.null = setmetatable({}, {__tostring = function() return "null" end})

local function utf8char(code)
	if code <= 0x7F then
		return char(code)
	elseif code <= 0x7FF then
		return char(0xC0 + floor(code / 0x40), 0x80 + (code % 0x40))
	elseif code <= 0xFFFF then
		return char(0xE0 + floor(code / 0x1000), 0x80 + (floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
	else
		return char(0xF0 + floor(code / 0x40000), 0x80 + (floor(code / 0x1000) % 0x40), 0x80 + (floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
	end
end

local escapes = {
	[34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f", [110] = "\n", [114] = "\r", [116] = "\t"
}

---@param str string
---@param yieldEvery number|nil
---@return any
function Json.decode(str, yieldEvery)
	if type(str) ~= "string" then
		return nil
	end
	local pos = 1
	local len = #str
	-- a C string terminator left at the end of a response is not trailing garbage
	while len > 0 and byte(str, len) == 0 do
		len = len - 1
	end
	local counter = 0
	local canYield = yieldEvery and co_running() ~= nil

	local function skip()
		local _, e = find(str, "^[ \t\r\n]*", pos)
		pos = e + 1
	end

	local function err(msg)
		error("JSON: " .. msg .. " at " .. pos, 0)
	end

	local parseValue

	local function parseString()
		pos = pos + 1
		local parts = nil
		local start = pos
		while true do
			local s, e = find(str, '["\\]', pos)
			if not s then
				err("unterminated string")
			end
			if byte(str, s) == 34 then
				if parts then
					parts[#parts + 1] = sub(str, start, s - 1)
					pos = s + 1
					return concat(parts)
				end
				pos = s + 1
				return sub(str, start, s - 1)
			end
			parts = parts or {}
			parts[#parts + 1] = sub(str, start, s - 1)
			local c = byte(str, s + 1)
			if c == 117 then
				local code = tonumber(sub(str, s + 2, s + 5), 16) or 63
				local nextPos = s + 6
				if code >= 0xD800 and code <= 0xDBFF and sub(str, s + 6, s + 7) == "\\u" then
					local low = tonumber(sub(str, s + 8, s + 11), 16)
					if low and low >= 0xDC00 and low <= 0xDFFF then
						code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
						nextPos = s + 12
					end
				end
				parts[#parts + 1] = utf8char(code)
				pos = nextPos
			else
				parts[#parts + 1] = escapes[c] or char(c or 63)
				pos = s + 2
			end
			start = pos
		end
	end

	local function parseNumber()
		local s, e = find(str, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not s then
			err("bad number")
		end
		local n = tonumber(sub(str, s, e))
		pos = e + 1
		return n
	end

	local function parseArray()
		pos = pos + 1
		local arr = {}
		skip()
		if byte(str, pos) == 93 then
			pos = pos + 1
			return arr
		end
		local n = 0
		while true do
			n = n + 1
			arr[n] = parseValue()
			skip()
			local c = byte(str, pos)
			if c == 93 then
				pos = pos + 1
				return arr
			elseif c ~= 44 then
				err("expected , or ]")
			end
			pos = pos + 1
		end
	end

	local function parseObject()
		pos = pos + 1
		local obj = {}
		skip()
		if byte(str, pos) == 125 then
			pos = pos + 1
			return obj
		end
		while true do
			skip()
			if byte(str, pos) ~= 34 then
				err("expected key")
			end
			local key = parseString()
			skip()
			if byte(str, pos) ~= 58 then
				err("expected :")
			end
			pos = pos + 1
			local v = parseValue()
			if v ~= Json.null then
				obj[key] = v
			end
			skip()
			local c = byte(str, pos)
			if c == 125 then
				pos = pos + 1
				return obj
			elseif c ~= 44 then
				err("expected , or }")
			end
			pos = pos + 1
		end
	end

	parseValue = function()
		if canYield then
			counter = counter + 1
			if counter >= yieldEvery then
				counter = 0
				co_yield(false)
			end
		end
		skip()
		local c = byte(str, pos)
		if c == 123 then
			return parseObject()
		elseif c == 91 then
			return parseArray()
		elseif c == 34 then
			return parseString()
		elseif c == 116 and sub(str, pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif c == 102 and sub(str, pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif c == 110 and sub(str, pos, pos + 3) == "null" then
			pos = pos + 4
			return Json.null
		elseif c then
			return parseNumber()
		end
		err("unexpected end")
	end

	local ok, result = pcall(function()
		local value = parseValue()
		-- reject trailing garbage: "404: Not Found" must not decode as the number 404
		skip()
		if pos <= len then
			err("unexpected trailing data")
		end
		return value
	end)
	if ok then
		if result == Json.null then
			return nil
		end
		return result
	end
	if Console then
		Console.error(result)
	end
	return nil, result
end

local function encodeString(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		local b = byte(c)
		if c == '"' then return '\\"' end
		if c == "\\" then return "\\\\" end
		if c == "\n" then return "\\n" end
		if c == "\r" then return "\\r" end
		if c == "\t" then return "\\t" end
		return string.format("\\u%04x", b)
	end) .. '"'
end

---@param value any
---@return string
function Json.encode(value)
	local t = type(value)
	if t == "nil" or value == Json.null then
		return "null"
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		if floor(value) == value and value < 1e15 and value > -1e15 then
			return string.format("%d", value)
		end
		return tostring(value)
	elseif t == "string" then
		return encodeString(value)
	elseif t == "table" then
		local n = #value
		if n > 0 or next(value) == nil then
			local out = {}
			for i = 1, n do
				out[i] = Json.encode(value[i])
			end
			return "[" .. concat(out, ",") .. "]"
		end
		local out = {}
		for k, v in pairs(value) do
			if type(v) ~= "function" then
				out[#out + 1] = encodeString(tostring(k)) .. ":" .. Json.encode(v)
			end
		end
		return "{" .. concat(out, ",") .. "}"
	end
	return "null"
end
