---Otakio HTTP helpers for extensions.
---Every function here must be called from inside a ParserManager coroutine
---(getPopularManga, getChapters, prepareChapter, ...). They yield while the
---request is running, so the UI keeps rendering at full speed.
Http = {}

local concat = table.concat
local format, gsub, byte, char = string.format, string.gsub, string.byte, string.char
local co_yield = coroutine.yield

---Percent-encodes a string (RFC 3986 unreserved characters are kept)
---@param s string
---@return string
function Http.encode(s)
	s = tostring(s or "")
	return (gsub(s, "[^%w%-%._~]", function(c)
		return format("%%%02X", byte(c))
	end))
end

---Builds `a=1&b=2` from a table. Array values produce repeated keys.
---Accepts either a map or an ordered list of {key, value} pairs.
---@param params table
---@return string
function Http.form(params)
	local out = {}
	if params[1] and type(params[1]) == "table" then
		for _, kv in ipairs(params) do
			out[#out + 1] = Http.encode(kv[1]) .. "=" .. Http.encode(kv[2])
		end
	else
		for k, v in pairs(params) do
			if type(v) == "table" then
				for _, item in ipairs(v) do
					out[#out + 1] = Http.encode(k) .. "=" .. Http.encode(item)
				end
			else
				out[#out + 1] = Http.encode(k) .. "=" .. Http.encode(v)
			end
		end
	end
	return concat(out, "&")
end

---Threads escapes '%' in links (it uses gsub internally), so we hand it a link with
---doubled percent signs as the original parsers do.
local function threadSafeLink(url)
	return url
end

local function toHeaderSlots(headers, task)
	local i = 1
	if headers then
		for k, v in pairs(headers) do
			if i > 4 then
				break
			end
			if type(k) == "number" then
				task["Header" .. i] = v
			else
				task["Header" .. i] = k .. ": " .. v
			end
			i = i + 1
		end
	end
	return task
end

---Low level request. Returns response body (string, possibly empty).
---@param options table {url, method="GET"|"POST", body, contentType="form"|"json"|string, headers={}, cookie}
---@return string
function Http.request(options)
	local result = {}
	local task = {
		Type = "StringRequest",
		Link = threadSafeLink(options.url),
		Table = result,
		Index = "body",
		Cookie = options.cookie
	}
	if options.method == "POST" then
		task.HttpMethod = POST_METHOD
		local body = options.body or ""
		if type(body) == "table" then
			if options.contentType == "json" then
				body = Json.encode(body)
			else
				body = Http.form(body)
			end
		end
		task.PostData = body
		if options.contentType == "json" then
			task.ContentType = JSON
		else
			task.ContentType = XWWW
		end
	end
	toHeaderSlots(options.headers, task)
	Threads.insertTask(result, task)
	while Threads.check(result) do
		co_yield(false)
	end
	return result.body or ""
end

---@param url string
---@param headers table|nil
---@return string
function Http.get(url, headers)
	return Http.request({url = url, headers = headers})
end

---@param url string
---@param body table|string
---@param headers table|nil
---@param contentType string|nil "form" (default) or "json"
---@return string
function Http.post(url, body, headers, contentType)
	return Http.request({url = url, method = "POST", body = body, headers = headers, contentType = contentType})
end

---GET and parse as HTML document (see html.lua)
function Http.getDocument(url, headers)
	local body = Http.get(url, headers)
	co_yield(false)
	return Html.parse(body, url), body
end

---POST and parse as HTML document
function Http.postDocument(url, body, headers, baseUrl)
	local response = Http.post(url, body, headers)
	co_yield(false)
	return Html.parse(response, baseUrl or url), response
end

---GET and decode JSON
function Http.getJson(url, headers)
	local body = Http.get(url, headers)
	co_yield(false)
	return Json.decode(body, 2000), body
end

---Image link object understood by Otakio's downloader (lets you attach Referer etc.)
---@param url string
---@param referer string|nil
---@param headers table|nil
---@return table|string
function Http.image(url, referer, headers)
	if not referer and not headers then
		return url
	end
	local t = {Link = url}
	local slots = {}
	if referer then
		slots[#slots + 1] = "Referer: " .. referer
	end
	if headers then
		for k, v in pairs(headers) do
			slots[#slots + 1] = type(k) == "number" and v or (k .. ": " .. v)
		end
	end
	for i = 1, math.min(4, #slots) do
		t["Header" .. i] = slots[i]
	end
	return t
end

---Decodes base64 (needed by some themes that embed page lists in base64 scripts)
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64lookup = {}
for i = 1, #b64chars do
	b64lookup[byte(b64chars, i)] = i - 1
end
b64lookup[byte("-")] = 62
b64lookup[byte("_")] = 63

function Http.base64decode(data)
	data = gsub(data or "", "[^%w%+/%-_=]", "")
	local out = {}
	local bits, bitCount = 0, 0
	for i = 1, #data do
		local c = byte(data, i)
		if c == 61 then
			break
		end
		local v = b64lookup[c]
		if v then
			bits = bits * 64 + v
			bitCount = bitCount + 6
			if bitCount >= 8 then
				bitCount = bitCount - 8
				local b = math.floor(bits / 2 ^ bitCount)
				out[#out + 1] = char(b % 256)
				bits = bits % (2 ^ bitCount)
			end
		end
	end
	return concat(out)
end
