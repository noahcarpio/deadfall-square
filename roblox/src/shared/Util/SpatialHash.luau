--!strict
--[[
	Uniform-grid spatial hash for points on the XZ plane, rebuilt every
	simulation step. Items are integer ids; an intrusive linked list keeps
	insert/clear allocation-free.
]]

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type SpatialHash = typeof(setmetatable(
	{} :: {
		cellSize: number,
		minX: number,
		minZ: number,
		cols: number,
		rows: number,
		heads: { number },
		nextId: { number },
		xs: { number },
		zs: { number },
	},
	SpatialHash
))

function SpatialHash.new(minX: number, minZ: number, maxX: number, maxZ: number, cellSize: number): SpatialHash
	local cols = math.ceil((maxX - minX) / cellSize)
	local rows = math.ceil((maxZ - minZ) / cellSize)
	local self = setmetatable({
		cellSize = cellSize,
		minX = minX,
		minZ = minZ,
		cols = cols,
		rows = rows,
		heads = table.create(cols * rows, 0),
		nextId = {},
		xs = {},
		zs = {},
	}, SpatialHash)
	return self
end

function SpatialHash.clear(self: SpatialHash)
	table.clear(self.heads)
	for i = 1, self.cols * self.rows do
		self.heads[i] = 0
	end
end

function SpatialHash.cellIndex(self: SpatialHash, x: number, z: number): number
	local cx = math.clamp(math.floor((x - self.minX) / self.cellSize), 0, self.cols - 1)
	local cz = math.clamp(math.floor((z - self.minZ) / self.cellSize), 0, self.rows - 1)
	return cz * self.cols + cx + 1
end

-- Inserts item `id` (a positive integer) at a position.
function SpatialHash.insert(self: SpatialHash, id: number, x: number, z: number)
	local c = self:cellIndex(x, z)
	self.xs[id] = x
	self.zs[id] = z
	self.nextId[id] = self.heads[c]
	self.heads[c] = id
end

-- Writes ids within `radius` of (x, z) into `out` (cleared first) and returns the count.
function SpatialHash.query(self: SpatialHash, x: number, z: number, radius: number, out: { number }): number
	table.clear(out)
	local count = 0
	local r2 = radius * radius
	local cs = self.cellSize
	local x0 = math.max(0, math.floor((x - radius - self.minX) / cs))
	local x1 = math.min(self.cols - 1, math.floor((x + radius - self.minX) / cs))
	local z0 = math.max(0, math.floor((z - radius - self.minZ) / cs))
	local z1 = math.min(self.rows - 1, math.floor((z + radius - self.minZ) / cs))
	for cz = z0, z1 do
		for cx = x0, x1 do
			local id = self.heads[cz * self.cols + cx + 1]
			while id ~= 0 do
				local dx = self.xs[id] - x
				local dz = self.zs[id] - z
				if dx * dx + dz * dz <= r2 then
					count += 1
					out[count] = id
				end
				id = self.nextId[id]
			end
		end
	end
	return count
end

return SpatialHash
