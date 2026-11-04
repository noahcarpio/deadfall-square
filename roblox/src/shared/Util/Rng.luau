--!strict
--[[
	Seedable PRNG (mulberry32), identical to the browser version so wave
	compositions match for a given seed. All gameplay randomness on the server
	goes through this.
]]

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number?): Rng
	local s = seed or math.floor(os.clock() * 1e6) % 4294967296
	return setmetatable({ state = s % 4294967296 }, Rng)
end

local function imul(a: number, b: number): number
	-- 32-bit integer multiply (wraps like Math.imul, as an unsigned value).
	local aHi = bit32.rshift(a, 16)
	local aLo = bit32.band(a, 0xffff)
	local bHi = bit32.rshift(b, 16)
	local bLo = bit32.band(b, 0xffff)
	local lo = aLo * bLo
	local mid = bit32.band(aHi * bLo + aLo * bHi, 0xffff)
	return bit32.band(lo + bit32.lshift(mid, 16), 0xffffffff)
end

-- Uniform float in [0, 1).
function Rng.next(self: Rng): number
	self.state = bit32.band(self.state + 0x6d2b79f5, 0xffffffff)
	local t = self.state
	t = imul(bit32.bxor(t, bit32.rshift(t, 15)), bit32.bor(t, 1))
	t = bit32.bxor(t, bit32.band(t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(t, 61)), 0xffffffff))
	return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
end

function Rng.range(self: Rng, min: number, max: number): number
	return min + (max - min) * self:next()
end

-- Uniform integer in [min, max] inclusive.
function Rng.int(self: Rng, min: number, max: number): number
	return min + math.floor(self:next() * (max - min + 1))
end

function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.pick<T>(self: Rng, items: { T }): T
	assert(#items > 0, "Rng.pick on empty list")
	return items[math.floor(self:next() * #items) + 1]
end

-- Picks a key from a map of non-negative weights. Keys are visited in sorted
-- order so results are deterministic across runs.
function Rng.weighted(self: Rng, weights: { [string]: number }): string
	local keys = {}
	local total = 0
	for k, w in weights do
		if w > 0 then
			table.insert(keys, k)
			total += w
		end
	end
	assert(total > 0, "Rng.weighted with zero total weight")
	table.sort(keys)
	local r = self:next() * total
	for _, k in keys do
		local w = weights[k]
		if r < w then
			return k
		end
		r -= w
	end
	return keys[#keys]
end

function Rng.shuffle<T>(self: Rng, items: { T }): { T }
	for i = #items, 2, -1 do
		local j = math.floor(self:next() * i) + 1
		items[i], items[j] = items[j], items[i]
	end
	return items
end

return Rng
