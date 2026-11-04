--!strict
--[[
	Walkability grid (1 m cells). Obstacles are rasterised with an inflation
	radius so paths keep zombie bodies clear of corners. Cell indices are
	1-based: index = row * cols + col + 1.
]]
local NavGrid = {}
NavGrid.__index = NavGrid

NavGrid.FREE = 0
NavGrid.SOLID = 1
-- Player-built structure: passable at a cost (zombies break through if they must).
NavGrid.STRUCTURE = 2

export type NavGrid = typeof(setmetatable(
	{} :: { minX: number, minZ: number, cols: number, rows: number, size: number, cells: { number } },
	NavGrid
))

function NavGrid.new(minX: number, minZ: number, maxX: number, maxZ: number): NavGrid
	local cols = math.floor(maxX - minX + 0.5)
	local rows = math.floor(maxZ - minZ + 0.5)
	return setmetatable({
		minX = minX,
		minZ = minZ,
		cols = cols,
		rows = rows,
		size = cols * rows,
		cells = table.create(cols * rows, 0),
	}, NavGrid)
end

function NavGrid.col(self: NavGrid, x: number): number
	return math.floor(x - self.minX)
end

function NavGrid.row(self: NavGrid, z: number): number
	return math.floor(z - self.minZ)
end

function NavGrid.inBounds(self: NavGrid, c: number, r: number): boolean
	return c >= 0 and r >= 0 and c < self.cols and r < self.rows
end

function NavGrid.indexAt(self: NavGrid, x: number, z: number): number
	local c = math.clamp(self:col(x), 0, self.cols - 1)
	local r = math.clamp(self:row(z), 0, self.rows - 1)
	return r * self.cols + c + 1
end

function NavGrid.centerX(self: NavGrid, c: number): number
	return self.minX + c + 0.5
end

function NavGrid.centerZ(self: NavGrid, r: number): number
	return self.minZ + r + 0.5
end

function NavGrid.get(self: NavGrid, c: number, r: number): number
	if not self:inBounds(c, r) then
		return NavGrid.SOLID
	end
	return self.cells[r * self.cols + c + 1]
end

local function write(self: NavGrid, i: number, value: number)
	if self.cells[i] ~= NavGrid.SOLID then
		self.cells[i] = value
	end
end

-- Rasterises colliders (inflated). `isStructure(collider)` tags player-built obstacles.
function NavGrid.rebuild(self: NavGrid, colliders: { any }, inflate: number, isStructure: (any) -> boolean)
	for i = 1, self.size do
		self.cells[i] = NavGrid.FREE
	end
	for _, c in colliders do
		local value = if isStructure(c) then NavGrid.STRUCTURE else NavGrid.SOLID
		if c.kind == "box" then
			-- A cell is blocked when its centre lies inside the inflated rectangle.
			local c0 = math.max(0, math.ceil(c.minX - inflate - self.minX - 0.5))
			local c1 = math.min(self.cols - 1, math.floor(c.maxX + inflate - self.minX - 0.5))
			local r0 = math.max(0, math.ceil(c.minZ - inflate - self.minZ - 0.5))
			local r1 = math.min(self.rows - 1, math.floor(c.maxZ + inflate - self.minZ - 0.5))
			for r = r0, r1 do
				for q = c0, c1 do
					write(self, r * self.cols + q + 1, value)
				end
			end
		else
			local radius = c.r + inflate
			local c0 = math.max(0, self:col(c.x - radius))
			local c1 = math.min(self.cols - 1, self:col(c.x + radius))
			local r0 = math.max(0, self:row(c.z - radius))
			local r1 = math.min(self.rows - 1, self:row(c.z + radius))
			for r = r0, r1 do
				for q = c0, c1 do
					local dx = self:centerX(q) - c.x
					local dz = self:centerZ(r) - c.z
					if dx * dx + dz * dz <= radius * radius then
						write(self, r * self.cols + q + 1, value)
					end
				end
			end
		end
	end
end

-- Grid line of sight, sampled every quarter cell.
function NavGrid.lineOfSight(
	self: NavGrid,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	structuresBlock: boolean
): boolean
	local dx = bx - ax
	local dz = bz - az
	local steps = math.ceil(math.sqrt(dx * dx + dz * dz) / 0.25)
	for i = 1, steps - 1 do
		local t = i / steps
		local v = self:get(self:col(ax + dx * t), self:row(az + dz * t))
		if v == NavGrid.SOLID or (structuresBlock and v == NavGrid.STRUCTURE) then
			return false
		end
	end
	return true
end

return NavGrid
