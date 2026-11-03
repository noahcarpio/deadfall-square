--!strict
--[[
	The tower climb: a run is a climb of FLOORS floors on the town square.
	Every floor has an objective and may have a modifier; every fifth floor is
	a boss floor and the last floor is the final boss. Floor numbers feed the
	existing wave curves (Config/Waves) as the wave number.
]]

export type Objective = {
	id: string,
	name: string,
	description: string,
	weight: number,
	minFloor: number,
}

export type Modifier = {
	id: string,
	name: string,
	description: string,
	weight: number,
	minFloor: number,
	count: number, -- horde size multiplier
	hp: number,
	speed: number,
	coins: number,
	sight: number, -- zombie sight range multiplier
	fog: number, -- extra atmosphere density
	brutes: number, -- share of walkers turned into brutes
}

local OBJECTIVES: { [string]: Objective } = {
	clear = {
		id = "clear",
		name = "Clear the floor",
		description = "Kill every zombie on this floor.",
		weight = 3,
		minFloor = 1,
	},
	holdout = {
		id = "holdout",
		name = "Hold out",
		description = "Survive until the timer runs out. They keep coming.",
		weight = 2,
		minFloor = 2,
	},
	defend = {
		id = "defend",
		name = "Defend the bell",
		description = "Zombies go for the alarm bell. If it breaks, this floor gives no reward.",
		weight = 1.5,
		minFloor = 3,
	},
	elite = {
		id = "elite",
		name = "Elite hunt",
		description = "A glowing elite leads the horde. Kill it to clear the floor.",
		weight = 2,
		minFloor = 2,
	},
	boss = {
		id = "boss",
		name = "Boss floor",
		description = "The Abomination is here. Kill it and everything with it.",
		weight = 0,
		minFloor = 1,
	},
}

local function mod(
	id: string,
	name: string,
	description: string,
	weight: number,
	minFloor: number,
	effects: { [string]: number }
): Modifier
	return {
		id = id,
		name = name,
		description = description,
		weight = weight,
		minFloor = minFloor,
		count = effects.count or 1,
		hp = effects.hp or 1,
		speed = effects.speed or 1,
		coins = effects.coins or 1,
		sight = effects.sight or 1,
		fog = effects.fog or 0,
		brutes = effects.brutes or 0,
	}
end

local MODIFIERS: { [string]: Modifier } = {
	none = mod("none", "", "", 3, 1, {}),
	fog = mod("fog", "Thick Fog", "You can't see far, and neither can they.", 1, 2, { fog = 0.35, sight = 0.7 }),
	bloodMoon = mod(
		"bloodMoon",
		"Blood Moon",
		"Faster zombies, half again the coins.",
		1,
		4,
		{ speed = 1.15, coins = 1.5 }
	),
	swarm = mod("swarm", "Swarm", "Far more zombies, but each one is weaker.", 1, 3, { count = 1.5, hp = 0.7 }),
	armored = mod("armored", "Armored", "Brutes everywhere, and tougher skin.", 1, 6, { hp = 1.1, brutes = 0.25 }),
	calm = mod("calm", "Calm", "Fewer zombies and fewer coins.", 0.8, 2, { count = 0.7, coins = 0.8 }),
}

return {
	FLOORS = 25,
	BOSS_EVERY = 5,
	-- Seconds to survive on a hold-out floor (plus a little per floor).
	holdoutSeconds = function(floor: number): number
		return math.min(110, 60 + floor * 2)
	end,
	-- The bell's health on a defend floor.
	bellHp = function(floor: number, players: number): number
		return math.floor((500 + floor * 45) * (1 + 0.3 * (math.max(1, players) - 1)))
	end,
	-- Elite multipliers.
	ELITE = { hp = 7, damage = 1.4, speed = 1.12 },
	objectives = OBJECTIVES,
	objectiveOrder = { "clear", "holdout", "defend", "elite" },
	modifiers = MODIFIERS,
	modifierOrder = { "none", "fog", "bloodMoon", "swarm", "armored", "calm" },
	-- Seconds to choose a reward after a floor (then the grace period starts).
	REWARD_SECONDS = 15,
}
