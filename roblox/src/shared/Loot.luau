--!strict
--[[
	Loot tables for searchable containers. Besides inventory items, a roll can
	produce two pseudo-items that never enter the bag:
	  "coins" - added to the finder's coins
	  "ammo"  - each unit refills 15% of every owned weapon's reserve
]]

export type Entry = { weight: number, min: number, max: number }
export type Table = { label: string, rolls: { number }, entries: { [string]: Entry } }

local TABLES: { [string]: Table } = {
	car = {
		label = "Car",
		rolls = { 2, 3 },
		entries = {
			scrap = { weight = 3, min = 1, max = 3 },
			parts = { weight = 2, min = 1, max = 2 },
			cloth = { weight = 1, min = 1, max = 2 },
			gunpowder = { weight = 1, min = 1, max = 2 },
			ammo = { weight = 2, min = 1, max = 2 },
			coins = { weight = 1, min = 10, max = 30 },
			bandage = { weight = 0.5, min = 1, max = 1 },
		},
	},
	bus = {
		label = "Bus",
		rolls = { 3, 4 },
		entries = {
			scrap = { weight = 3, min = 2, max = 4 },
			parts = { weight = 2, min = 1, max = 3 },
			cloth = { weight = 2, min = 1, max = 3 },
			gunpowder = { weight = 1, min = 1, max = 2 },
			ammo = { weight = 2, min = 1, max = 2 },
			coins = { weight = 1, min = 20, max = 45 },
			bandage = { weight = 1, min = 1, max = 2 },
			pipebomb = { weight = 0.3, min = 1, max = 1 },
		},
	},
	crate = {
		label = "Crates",
		rolls = { 2, 3 },
		entries = {
			wood = { weight = 3, min = 2, max = 3 },
			scrap = { weight = 2, min = 1, max = 2 },
			cloth = { weight = 1, min = 1, max = 2 },
			gunpowder = { weight = 1.5, min = 1, max = 2 },
			ammo = { weight = 2, min = 1, max = 2 },
		},
	},
	dumpster = {
		label = "Dumpster",
		rolls = { 2, 4 },
		entries = {
			scrap = { weight = 2, min = 1, max = 3 },
			cloth = { weight = 3, min = 1, max = 3 },
			wood = { weight = 1, min = 1, max = 2 },
			parts = { weight = 1, min = 1, max = 1 },
			coins = { weight = 1, min = 5, max = 20 },
			bandage = { weight = 1, min = 1, max = 1 },
		},
	},
	trash = {
		label = "Trash",
		rolls = { 1, 2 },
		entries = {
			cloth = { weight = 3, min = 1, max = 2 },
			scrap = { weight = 2, min = 1, max = 2 },
			coins = { weight = 1, min = 5, max = 15 },
			bandage = { weight = 0.5, min = 1, max = 1 },
		},
	},
}

type RngLike = {
	int: (any, number, number) -> number,
	weighted: (any, { [string]: number }) -> string,
	chance: (any, number) -> boolean,
}

-- Rolls a container's contents for the given wave. Returns { [id] = count }.
local function roll(rng: RngLike, kind: string, wave: number): { [string]: number }
	local t = TABLES[kind]
	assert(t, `unknown loot kind {kind}`)
	local weights: { [string]: number } = {}
	for id, e in t.entries do
		weights[id] = e.weight
	end
	local out: { [string]: number } = {}
	-- Later waves are a little more generous.
	local rolls = rng:int(t.rolls[1], t.rolls[2]) + math.floor(math.max(0, wave - 1) / 5)
	for _ = 1, rolls do
		local id = rng:weighted(weights)
		local e = t.entries[id]
		out[id] = (out[id] or 0) + rng:int(e.min, e.max)
	end
	return out
end

return {
	tables = TABLES,
	roll = roll,
	-- Chance that an emptied (or partly looted) container restocks at each grace period.
	RESTOCK_CHANCE = 0.65,
	AMMO_FRACTION = 0.15,
	SEARCH_SECONDS = 1.2,
}
