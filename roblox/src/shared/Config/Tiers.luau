--!strict
--[[
	Difficulty tiers. Winning a climb unlocks the next tier; the party leader
	picks any tier they've unlocked on the Home page. Higher tiers mean a
	bigger, faster, harder-hitting horde (zombie health only creeps up: no
	damage sponges), more coins during the run and more Scrip for winning.
]]
export type Tier = {
	tier: number,
	name: string,
	count: number, -- horde size multiplier
	damage: number,
	speed: number,
	hp: number,
	coins: number,
	scripBoss: number, -- Scrip per boss killed
	scripWin: number, -- Scrip for winning the climb
}

local NAMES = {
	"Survivor",
	"Veteran",
	"Hardened",
	"Nightmare",
	"Apocalypse",
	"Apocalypse II",
	"Apocalypse III",
	"Apocalypse IV",
	"Apocalypse V",
	"Apocalypse VI",
}

local MAX = #NAMES

local function get(t: number?): Tier
	local n = math.clamp(math.floor(t or 1), 1, MAX)
	local k = n - 1
	return {
		tier = n,
		name = NAMES[n],
		count = 1 + 0.25 * k,
		damage = 1 + 0.12 * k,
		speed = math.min(1.25, 1 + 0.04 * k),
		hp = 1 + 0.06 * k,
		coins = 1 + 0.1 * k,
		scripBoss = 10 + 5 * k,
		scripWin = 100 + 50 * k,
	}
end

return {
	MAX = MAX,
	get = get,
	-- The tier a Studio play-test uses (there's no Home page teleport in Studio).
	STUDIO_TIER = 1,
}
