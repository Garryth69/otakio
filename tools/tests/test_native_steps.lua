-- The engine's JSON and HTML decoders run in steps inside a coroutine; the step size follows the time each step
-- takes (json.lua, html.lua). Fake decoders here: each step costs time on a fake clock in proportion to its size.
local root = ...
string.rawsub = string.sub
local now = 0
Timer = {new = function() return {} end, getTime = function() return now end}
local MS_PER_UNIT = 0.02 -- a step of 4000 values = 80 ms, about what the Vita showed for MangaDex lists
local jsonSteps = {}
JsonNative = {new = function(str, null)
	local left = 20000
	return {step = function(self, budget)
		local n = budget and math.min(budget, left) or left
		jsonSteps[#jsonSteps + 1] = n
		now = now + n * MS_PER_UNIT
		left = left - n
		if left <= 0 then
			return true, {ok = str}
		end
		return false
	end}
end}
local htmlSteps = {}
HtmlNative = {new = function(html, Node, unescape)
	local left = #html
	return {step = function(self, budget)
		local n = budget and math.min(budget, left) or left
		htmlSteps[#htmlSteps + 1] = n
		now = now + n * 0.004 -- 32 KB = 131 ms
		left = left - n
		if left <= 0 then
			return setmetatable({children = {}, attrs = {}}, {__index = Node})
		end
	end}
end}
dofile(root .. "/source/assets/libs/json.lua")
dofile(root .. "/source/assets/libs/html.lua")
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": expected [" .. tostring(b) .. "] got [" .. tostring(a) .. "]", 2) end end

-- outside a coroutine: one call, whole result
eq(Json.decode("x", 2000).ok, "x", "json main thread")
eq(#jsonSteps, 1, "json main thread is one step")

-- inside one: steps shrink until each is near 12 ms, and the result is the same
jsonSteps = {}
local result
local co = coroutine.create(function() result = Json.decode("y", 2000) end)
local resumes, worst = 0, 0
while coroutine.status(co) ~= "dead" do
	local t0 = now
	assert(coroutine.resume(co))
	resumes = resumes + 1
	worst = math.max(worst, now - t0)
end
eq(result.ok, "y", "json result in coroutine")
assert(worst <= 31, "first JSON step too long: " .. worst .. " ms")
local last = jsonSteps[#jsonSteps - 1] -- the final one may be a short remainder
assert(last * MS_PER_UNIT <= 18, "JSON steps did not adapt: " .. last)
-- a second decode starts from what was learned
jsonSteps = {}
co = coroutine.create(function() result = Json.decode("z", 2000) end)
worst = 0
while coroutine.status(co) ~= "dead" do
	local t0 = now
	assert(coroutine.resume(co))
	worst = math.max(worst, now - t0)
end
assert(worst <= 18, "learned JSON step not kept: " .. worst .. " ms")

-- HTML: same, from 16 KB down to what takes ~12 ms
local doc = Html.parse(string.rep("a", 100000), "https://x/")
eq(doc.isDocument, true, "html main thread")
htmlSteps = {}
co = coroutine.create(function() doc = Html.parse(string.rep("b", 200000), "https://y/") end)
worst = 0
while coroutine.status(co) ~= "dead" do
	local t0 = now
	assert(coroutine.resume(co))
	worst = math.max(worst, now - t0)
end
eq(doc.baseUrl, "https://y/", "html result in coroutine")
local total = 0
for _, n in ipairs(htmlSteps) do total = total + n end
eq(total, 200000, "html steps cover the whole page")
assert(worst <= 66, "first HTML step too long: " .. worst .. " ms")
assert(htmlSteps[#htmlSteps - 1] * 0.004 <= 18, "HTML steps did not adapt: " .. htmlSteps[#htmlSteps - 1])
print("native step tests OK")
