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
Textures = {
	BUDGET = 80 * 1024 * 1024, -- textures created through Image:new
	RESERVE = 12 * 1024 * 1024 -- always left free for fonts, UI and the engine
}
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

-- Textures are never freed while a frame is being drawn: the GPU may still read a texture drawn earlier in the same
-- frame (freeing it then is a GPU crash). Image:free() and the garbage collector only queue the texture; the queue is
-- emptied outside the draw phase (main.lua sets DRAW_PHASE between initBlend and termBlend, and termBlend waits for
-- the GPU), at the start of every frame or when the texture budget needs room.
local pending, pendingMemory = {}, 0

---Queues an engine texture handle to be freed when the GPU is idle
---@param handle integer
---@param memory number|nil bytes it counts in the texture budget
function Textures.release(handle, memory)
	if handle then
		pending[#pending + 1] = handle
		pendingMemory = pendingMemory + (memory or 0)
	end
end

---Frees the queued textures (no-op while drawing)
function Textures.flush()
	if DRAW_PHASE or #pending == 0 then
		return
	end
	for i = 1, #pending do
		pcall(Graphics.freeImage, pending[i])
		pending[i] = nil
	end
	textureMemoryUsed = textureMemoryUsed - pendingMemory
	pendingMemory = 0
end

---Free image (the texture itself goes when the GPU is idle, see Textures.release)
function Image:free()
	if not self.e then
		return
	end
	Textures.release(self.e, self.Memory)
	self.e = nil
	self.Type = "table"
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
		Textures.flush() -- what the owner gave back counts now (outside the draw phase)
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
	return {used = textureMemoryUsed, budget = Textures.BUDGET, free = freeMemory(), images = liveImages, pending = #pending}
end
