---Otakio performance helpers.

-- utils.lua replaces string.sub with a UTF-8 aware version that has different semantics
-- (third argument is a length). Keep the original byte-based function for new code.
string.rawsub = string.rawsub or string.sub
---Loaded before every other UI library, so all existing code benefits automatically.

-- Overclock: 444MHz CPU / 222MHz bus / 222MHz GPU makes decoding, Lua and rendering
-- noticeably faster (same profile used by most Vita homebrew emulators).
pcall(function()
	if System.setCpuSpeed then
		System.setCpuSpeed(444)
	end
	if System.setBusSpeed then
		System.setBusSpeed(222)
	end
	if System.setGpuSpeed then
		System.setGpuSpeed(222)
	end
	if System.setGpuXbarSpeed then
		System.setGpuXbarSpeed(166)
	end
end)

-- Text measurement is a C call that rasterizes glyph metrics every time. The UI asks for
-- the width of the same strings every frame, so memoize it per font.
do
	local rawWidth = Font.getTextWidth
	local rawHeight = Font.getTextHeight
	local widthCache = {}
	local heightCache = {}
	local entries = 0
	local MAX_ENTRIES = 6000
	local tostring = tostring

	local function reset()
		widthCache = {}
		heightCache = {}
		entries = 0
	end

	function Font.getTextWidth(font, text)
		text = tostring(text)
		local fc = widthCache[font]
		if not fc then
			fc = {}
			widthCache[font] = fc
		end
		local w = fc[text]
		if not w then
			w = rawWidth(font, text)
			fc[text] = w
			entries = entries + 1
			if entries > MAX_ENTRIES then
				reset()
			end
		end
		return w
	end

	function Font.getTextHeight(font, text)
		text = tostring(text)
		local fc = heightCache[font]
		if not fc then
			fc = {}
			heightCache[font] = fc
		end
		local h = fc[text]
		if not h then
			h = rawHeight(font, text)
			fc[text] = h
			entries = entries + 1
			if entries > MAX_ENTRIES then
				reset()
			end
		end
		return h
	end

	Font.clearMetricsCache = reset
end

-- Colors with alpha are created every frame for fades. Cache them (Color.new is a C call
-- returning an integer, so caching by components is safe).
do
	local rawNew = Color.new
	local cache = {}
	local count = 0
	local floor = math.floor
	function ColorA(r, g, b, a)
		a = floor(a or 255)
		if a < 0 then
			a = 0
		elseif a > 255 then
			a = 255
		end
		local key = ((r * 256 + g) * 256 + b) * 256 + a
		local c = cache[key]
		if not c then
			c = rawNew(r, g, b, a)
			cache[key] = c
			count = count + 1
			if count > 4096 then
				cache = {}
				count = 0
			end
		end
		return c
	end
	---Same color with another alpha (cached)
	function WithAlpha(color, a)
		return ColorA(Color.getR(color), Color.getG(color), Color.getB(color), a)
	end
end

-- Incremental GC tuned for a 60fps UI: small steps every frame instead of long pauses
collectgarbage("setpause", 120)
collectgarbage("setstepmul", 300)

FrameStats = {fps = 60, frameMs = 16, lastTime = 0}
