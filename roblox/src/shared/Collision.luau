--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Obstacles on the XZ plane (metres) with a broadphase grid: circle push-out
	for movement, ray casts for bullets and overlap tests for placement.
]]
local MathUtil = if script then require(script.Parent.Util.MathUtil) else require("./Util/MathUtil")

export type Collider = {
	kind: "box" | "circle",
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	-- circle data (also mirrored into the box bounds)
	x: number,
	z: number,
	r: number,
	height: number,
	owner: any,
	stamp: number,
}

local Collision = {}
Collision.__index = Collision

local CELL = 4

export type Collision = typeof(setmetatable(
	{} :: {
		colliders: { Collider },
		minX: number,
		minZ: number,
		cols: number,
		rows: number,
		cells: { { Collider } },
		stampCounter: number,
		scratch: { Collider },
	},
	Collision
))

function Collision.new(minX: number, minZ: number, maxX: number, maxZ: number): Collision
	local cols = math.ceil((maxX - minX) / CELL)
	local rows = math.ceil((maxZ - minZ) / CELL)
	local cells = {}
	for i = 1, cols * rows do
		cells[i] = {}
	end
	return setmetatable({
		colliders = {},
		minX = minX,
		minZ = minZ,
		cols = cols,
		rows = rows,
		cells = cells,
		stampCounter = 0,
		scratch = {},
	}, Collision)
end

function Collision.col(self: Collision, x: number): number
	return math.clamp(math.floor((x - self.minX) / CELL), 0, self.cols - 1)
end

function Collision.row(self: Collision, z: number): number
	return math.clamp(math.floor((z - self.minZ) / CELL), 0, self.rows - 1)
end

function Collision.forCells(self: Collision, c: Collider, fn: ({ Collider }) -> ())
	for r = self:row(c.minZ), self:row(c.maxZ) do
		for q = self:col(c.minX), self:col(c.maxX) do
			fn(self.cells[r * self.cols + q + 1])
		end
	end
end

function Collision.insert(self: Collision, c: Collider): Collider
	table.insert(self.colliders, c)
	self:forCells(c, function(cell)
		table.insert(cell, c)
	end)
	return c
end

function Collision.addBox(self: Collision, minX: number, minZ: number, maxX: number, maxZ: number, height: number, owner: any?): Collider
	return self:insert({
		kind = "box",
		minX = minX,
		minZ = minZ,
		maxX = maxX,
		maxZ = maxZ,
		x = (minX + maxX) / 2,
		z = (minZ + maxZ) / 2,
		r = 0,
		height = height,
		owner = owner,
		stamp = 0,
	})
end

function Collision.addCircle(self: Collision, x: number, z: number, r: number, height: number, owner: any?): Collider
	return self:insert({
		kind = "circle",
		minX = x - r,
		minZ = z - r,
		maxX = x + r,
		maxZ = z + r,
		x = x,
		z = z,
		r = r,
		height = height,
		owner = owner,
		stamp = 0,
	})
end

function Collision.remove(self: Collision, c: Collider)
	local i = table.find(self.colliders, c)
	if not i then
		return
	end
	table.remove(self.colliders, i)
	self:forCells(c, function(cell)
		local j = table.find(cell, c)
		if j then
			table.remove(cell, j)
		end
	end)
end

-- Unique colliders whose cells intersect a rectangle (reused list).
function Collision.gather(self: Collision, x0: number, z0: number, x1: number, z1: number): { Collider }
	local out = self.scratch
	table.clear(out)
	self.stampCounter += 1
	local stamp = self.stampCounter
	for r = self:row(z0), self:row(z1) do
		for q = self:col(x0), self:col(x1) do
			for _, c in self.cells[r * self.cols + q + 1] do
				if c.stamp ~= stamp then
					c.stamp = stamp
					table.insert(out, c)
				end
			end
		end
	end
	return out
end

--[[
	Pushes a circle at (x, z) out of all obstacles. Returns the new position and
	the last collider touched (used to detect zombies blocked by barricades).
]]
function Collision.resolveCircle(self: Collision, x: number, z: number, r: number): (number, number, Collider?)
	local touched: Collider? = nil
	for _ = 1, 2 do
		local moved = false
		for _, c in self:gather(x - r, z - r, x + r, z + r) do
			if c.kind == "box" then
				local qx = math.clamp(x, c.minX, c.maxX)
				local qz = math.clamp(z, c.minZ, c.maxZ)
				local dx = x - qx
				local dz = z - qz
				local d2 = dx * dx + dz * dz
				if d2 < r * r then
					if d2 > 1e-10 then
						local d = math.sqrt(d2)
						x += dx / d * (r - d)
						z += dz / d * (r - d)
					else
						local left = x - c.minX
						local right = c.maxX - x
						local down = z - c.minZ
						local up = c.maxZ - z
						local m = math.min(left, right, down, up)
						if m == left then
							x = c.minX - r
						elseif m == right then
							x = c.maxX + r
						elseif m == down then
							z = c.minZ - r
						else
							z = c.maxZ + r
						end
					end
					touched = c
					moved = true
				end
			else
				local dx = x - c.x
				local dz = z - c.z
				local rr = r + c.r
				local d2 = dx * dx + dz * dz
				if d2 < rr * rr then
					local d = math.max(math.sqrt(d2), 1e-5)
					x += dx / d * (rr - d)
					z += dz / d * (rr - d)
					touched = c
					moved = true
				end
			end
		end
		if not moved then
			break
		end
	end
	return x, z, touched
end

function Collision.overlapsCircle(self: Collision, x: number, z: number, r: number): boolean
	for _, c in self:gather(x - r, z - r, x + r, z + r) do
		if c.kind == "box" then
			local dx = x - math.clamp(x, c.minX, c.maxX)
			local dz = z - math.clamp(z, c.minZ, c.maxZ)
			if dx * dx + dz * dz < r * r then
				return true
			end
		else
			local dx = x - c.x
			local dz = z - c.z
			if dx * dx + dz * dz < (r + c.r) * (r + c.r) then
				return true
			end
		end
	end
	return false
end

function Collision.overlapsRect(self: Collision, minX: number, minZ: number, maxX: number, maxZ: number): boolean
	for _, c in self:gather(minX, minZ, maxX, maxZ) do
		if c.kind == "box" then
			if c.minX < maxX and c.maxX > minX and c.minZ < maxZ and c.maxZ > minZ then
				return true
			end
		else
			local dx = c.x - math.clamp(c.x, minX, maxX)
			local dz = c.z - math.clamp(c.z, minZ, maxZ)
			if dx * dx + dz * dz < c.r * c.r then
				return true
			end
		end
	end
	return false
end

-- Ray against obstacles at least `minHeight` tall. Returns hit distance (maxDist if none) and collider.
function Collision.raycast(
	self: Collision,
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	maxDist: number,
	minHeight: number
): (number, Collider?)
	local best = maxDist
	local hit: Collider? = nil
	local ex = ox + dx * maxDist
	local ez = oz + dz * maxDist
	for _, c in self:gather(math.min(ox, ex), math.min(oz, ez), math.max(ox, ex), math.max(oz, ez)) do
		if c.height >= minHeight then
			local t = if c.kind == "box"
				then MathUtil.rayAabb(ox, oz, dx, dz, c.minX, c.minZ, c.maxX, c.maxZ)
				else MathUtil.rayCircle(ox, oz, dx, dz, c.x, c.z, c.r)
			if t >= 0 and t < best then
				best = t
				hit = c
			end
		end
	end
	return best, hit
end

return Collision
