--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Multi-source Dijkstra flow field: every zombie samples a direction toward
	the *nearest* living player in O(1), so one search per update serves the
	whole horde in co-op.
]]
local NavGrid = if script then require(script.Parent.NavGrid) else require("./NavGrid")

local SQRT2 = math.sqrt(2)
local STRUCTURE_COST = 14

-- { dc, dr, cost }
local NEIGHBOURS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, SQRT2 },
	{ 1, -1, SQRT2 },
	{ -1, 1, SQRT2 },
	{ -1, -1, SQRT2 },
}

local FlowField = {}
FlowField.__index = FlowField
FlowField.STRUCTURE_COST = STRUCTURE_COST

export type FlowField = typeof(setmetatable(
	{} :: {
		grid: any,
		dist: { number },
		dirX: { number },
		dirZ: { number },
		heapKeys: { number },
		heapVals: { number },
		version: number,
	},
	FlowField
))

function FlowField.new(grid: any): FlowField
	return setmetatable({
		grid = grid,
		dist = table.create(grid.size, math.huge),
		dirX = table.create(grid.size, 0),
		dirZ = table.create(grid.size, 0),
		heapKeys = {},
		heapVals = {},
		version = 0,
	}, FlowField)
end

-- Binary min-heap (1-based) stored in two parallel arrays.
local function push(keys: { number }, vals: { number }, n: number, key: number, val: number): number
	n += 1
	local i = n
	while i > 1 do
		local p = i // 2
		if keys[p] <= key then
			break
		end
		keys[i] = keys[p]
		vals[i] = vals[p]
		i = p
	end
	keys[i] = key
	vals[i] = val
	return n
end

local function pop(keys: { number }, vals: { number }, n: number): (number, number, number)
	local topKey = keys[1]
	local topVal = vals[1]
	local key = keys[n]
	local val = vals[n]
	n -= 1
	if n > 0 then
		local i = 1
		while true do
			local c = i * 2
			if c > n then
				break
			end
			if c + 1 <= n and keys[c + 1] < keys[c] then
				c += 1
			end
			if keys[c] >= key then
				break
			end
			keys[i] = keys[c]
			vals[i] = vals[c]
			i = c
		end
		keys[i] = key
		vals[i] = val
	end
	return topKey, topVal, n
end

-- Recomputes distances from all targets ({ {x, z}, ... } in metres).
function FlowField.compute(self: FlowField, targets: { { number } })
	local g = self.grid
	local cols, rows, cells = g.cols, g.rows, g.cells
	local dist = self.dist
	for i = 1, g.size do
		dist[i] = math.huge
	end
	local keys, vals = self.heapKeys, self.heapVals
	local n = 0
	for _, t in targets do
		local start = g:indexAt(t[1], t[2])
		dist[start] = 0
		n = push(keys, vals, n, 0, start)
	end
	while n > 0 do
		local d, i
		d, i, n = pop(keys, vals, n)
		if d <= dist[i] then
			local c = (i - 1) % cols
			local r = (i - 1 - c) // cols
			for _, nb in NEIGHBOURS do
				local nc = c + nb[1]
				local nr = r + nb[2]
				if nc >= 0 and nr >= 0 and nc < cols and nr < rows then
					local ni = nr * cols + nc + 1
					local cell = cells[ni]
					local ok = cell ~= NavGrid.SOLID
					if ok and nb[1] ~= 0 and nb[2] ~= 0 then
						-- No diagonal corner cutting.
						ok = cells[r * cols + nc + 1] ~= NavGrid.SOLID and cells[nr * cols + c + 1] ~= NavGrid.SOLID
					end
					if ok then
						local nd = d + nb[3] + (if cell == NavGrid.STRUCTURE then STRUCTURE_COST else 0)
						if nd < dist[ni] then
							dist[ni] = nd
							n = push(keys, vals, n, nd, ni)
						end
					end
				end
			end
		end
	end
	self:buildDirections()
	self.version += 1
end

function FlowField.buildDirections(self: FlowField)
	local g = self.grid
	local cols, rows, cells, dist = g.cols, g.rows, g.cells, self.dist
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local i = r * cols + c + 1
			local best = dist[i]
			local bx, bz = 0, 0
			for _, nb in NEIGHBOURS do
				local nc = c + nb[1]
				local nr = r + nb[2]
				if nc >= 0 and nr >= 0 and nc < cols and nr < rows then
					local ok = true
					if nb[1] ~= 0 and nb[2] ~= 0 then
						ok = cells[r * cols + nc + 1] ~= NavGrid.SOLID and cells[nr * cols + c + 1] ~= NavGrid.SOLID
					end
					local nd = dist[nr * cols + nc + 1]
					if ok and nd < best then
						best = nd
						bx, bz = nb[1], nb[2]
					end
				end
			end
			local len = math.sqrt(bx * bx + bz * bz)
			if len > 0 then
				self.dirX[i] = bx / len
				self.dirZ[i] = bz / len
			else
				self.dirX[i] = 0
				self.dirZ[i] = 0
			end
		end
	end
end

function FlowField.distanceAt(self: FlowField, x: number, z: number): number
	return self.dist[self.grid:indexAt(x, z)]
end

--[[
	Steering direction at a world position. Inside a blocked cell (agents get
	shoved into the inflated margin) it steers toward the best reachable
	neighbouring cell. Returns nil at a target or when unreachable.
]]
function FlowField.sample(self: FlowField, x: number, z: number): (number?, number?)
	local g = self.grid
	local i = g:indexAt(x, z)
	local d = self.dist[i]
	if d == 0 then
		return nil, nil
	end
	if d ~= math.huge then
		local dx, dz = self.dirX[i], self.dirZ[i]
		if dx == 0 and dz == 0 then
			return nil, nil
		end
		return dx, dz
	end
	local c = math.clamp(g:col(x), 0, g.cols - 1)
	local r = math.clamp(g:row(z), 0, g.rows - 1)
	local best = math.huge
	local tx, tz = 0, 0
	for dr = -2, 2 do
		for dc = -2, 2 do
			local nc, nr = c + dc, r + dr
			if g:inBounds(nc, nr) then
				local nd = self.dist[nr * g.cols + nc + 1] + math.sqrt(dc * dc + dr * dr)
				if nd < best then
					best = nd
					tx = g:centerX(nc)
					tz = g:centerZ(nr)
				end
			end
		end
	end
	if best == math.huge then
		return nil, nil
	end
	local dx, dz = tx - x, tz - z
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-6)
	return dx / len, dz / len
end

return FlowField
