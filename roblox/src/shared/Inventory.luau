--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	A weight-limited bag of items (counts by item id). Pure data so the
	server, the client display and the unit tests share the same rules.
]]
local Items = if script then require(script.Parent.Config.Items) else require("./Config/Items")

local EPSILON = 1e-6

local Inventory = {}
Inventory.__index = Inventory

export type Inventory = typeof(setmetatable({} :: { items: { [string]: number }, capacity: number }, Inventory))

function Inventory.new(capacity: number): Inventory
	return setmetatable({ items = {} :: { [string]: number }, capacity = capacity }, Inventory)
end

function Inventory.count(self: Inventory, id: string): number
	return self.items[id] or 0
end

function Inventory.weight(self: Inventory): number
	local total = 0
	for id, n in self.items do
		local def = Items.defs[id]
		if def then
			total += def.weight * n
		end
	end
	return total
end

-- How many of `id` fit (up to `wanted`).
function Inventory.fits(self: Inventory, id: string, wanted: number): number
	local def = Items.defs[id]
	if not def or wanted <= 0 then
		return 0
	end
	local free = self.capacity - self:weight()
	return math.clamp(math.floor((free + EPSILON) / def.weight), 0, wanted)
end

-- Adds as many as fit; returns how many were added.
function Inventory.add(self: Inventory, id: string, n: number): number
	local added = self:fits(id, n)
	if added > 0 then
		self.items[id] = self:count(id) + added
	end
	return added
end

function Inventory.remove(self: Inventory, id: string, n: number): boolean
	local have = self:count(id)
	if n <= 0 or have < n then
		return false
	end
	if have == n then
		(self.items :: any)[id] = nil
	else
		self.items[id] = have - n
	end
	return true
end

-- True if the bag holds every { [id] = count } in `cost`.
function Inventory.has(self: Inventory, cost: { [string]: number }?): boolean
	if not cost then
		return true
	end
	for id, n in cost do
		if self:count(id) < n then
			return false
		end
	end
	return true
end

-- Removes a whole cost atomically. Returns false (and changes nothing) if short.
function Inventory.take(self: Inventory, cost: { [string]: number }?): boolean
	if not self:has(cost) then
		return false
	end
	if cost then
		for id, n in cost do
			if n > 0 then
				self:remove(id, n)
			end
		end
	end
	return true
end

function Inventory.serialize(self: Inventory): { items: { [string]: number }, capacity: number }
	return { items = table.clone(self.items), capacity = self.capacity }
end

function Inventory.load(self: Inventory, data: { items: { [string]: number }, capacity: number })
	self.items = table.clone(data.items)
	self.capacity = data.capacity
end

return Inventory
