---@class Image
Image = {
	__gc = function(self)
		self:free()
	end
}

local function setmt__gc(t, mt)
	local prox = newproxy(true)
	getmetatable(prox).__gc = function()
		mt.__gc(t)
	end
	t[prox] = true
	return setmetatable(t, mt)
end

---Variable to count used memory by textures
local textureMemoryUsed = 0
local liveImages = 0

---@param image integer
---@return Image|nil
---Creates Image Object
function Image:new(image, filter)
	if not image then
		return nil
	end
	local p = {
		e = image,
		Width = Graphics.getImageWidth(image),
		Height = Graphics.getImageHeight(image),
		Type = "image"
	}
	if filter then
		Graphics.setImageFilters(image, filter, filter)
	end
	p.Memory = bit32.band(p.Width + 7, bit32.bnot(7)) * p.Height * 4 + 1024
	textureMemoryUsed = textureMemoryUsed + p.Memory
	liveImages = liveImages + 1
	setmt__gc(p, self)
	self.__index = self
	return p
end

---Free image
function Image:free()
	if not self.e then
		return
	end
	Graphics.freeImage(self.e)
	self.e = nil
	self.Type = "table"
	textureMemoryUsed = textureMemoryUsed - self.Memory
	liveImages = liveImages - 1
end

---Get used memory by textures
function GetGPUMemoryUsed()
	return textureMemoryUsed
end

-------------------------------------------------------------------------------
-- Texture budget
-- The Vita has roughly 100+ MB for textures and nothing warns before an allocation fails, so every big texture
-- (covers, reader pages) asks the budget first. When the budget is short, registered owners free what is least
-- useful (covers far from the viewport first, then reader pages away from the current one).
-------------------------------------------------------------------------------
Textures = {
	BUDGET = 80 * 1024 * 1024, -- textures created through Image:new
	RESERVE = 12 * 1024 * 1024 -- always left free for fonts, UI and the engine
}

local owners = {} -- {name = string, priority = number, reclaim = function(bytesNeeded)}

---Registers something that holds textures and can release them on demand.
---Lower priority = asked first.
---@param name string
---@param priority number
---@param reclaim function(bytesNeeded)
function Textures.register(name, priority, reclaim)
	for i = #owners, 1, -1 do
		if owners[i].name == name then
			table.remove(owners, i)
		end
	end
	owners[#owners + 1] = {name = name, priority = priority, reclaim = reclaim}
	table.sort(owners, function(a, b)
		return a.priority < b.priority
	end)
end

local function freeMemory()
	local ok, free = pcall(Graphics.getFreeMemory)
	return ok and free or math.huge
end

---@param bytes number
---@return boolean true when a texture of this size fits the budget and leaves the reserve free
function Textures.canAfford(bytes)
	return textureMemoryUsed + bytes <= Textures.BUDGET and freeMemory() - bytes >= Textures.RESERVE
end

---Asks the owners, least important first, to free textures until `bytes` fit
---@param bytes number
function Textures.reclaim(bytes)
	for _, owner in ipairs(owners) do
		if Textures.canAfford(bytes) then
			return true
		end
		local ok, err = pcall(owner.reclaim, bytes)
		if not ok and Console then
			Console.error("texture reclaim (" .. owner.name .. "): " .. tostring(err))
		end
	end
	return Textures.canAfford(bytes)
end

---@param bytes number
---@return boolean true when the texture fits now or after reclaiming
function Textures.ensure(bytes)
	return Textures.canAfford(bytes) or Textures.reclaim(bytes)
end

---@return table {used, budget, free, images}
function Textures.stats()
	return {used = textureMemoryUsed, budget = Textures.BUDGET, free = freeMemory(), images = liveImages}
end
