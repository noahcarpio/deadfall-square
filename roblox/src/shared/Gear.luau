--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Gear: guns, melee weapons, armor and gadgets found during the climb.
	Every piece has a rarity (common / rare / unique), a power level that grows
	with the floor it was found on, and rarer pieces carry traits.

	Pure data and rules, shared by the server (authoritative), the client
	(display) and the unit tests.
]]
local Weapons = if script then require(script.Parent.Config.Weapons) else require("./Config/Weapons")

export type Item = {
	uid: number,
	id: string,
	kind: string, -- gun | melee | armor | gadget
	rarity: string, -- common | rare | unique
	power: number,
	traits: { string },
}

export type RarityDef = { id: string, name: string, color: string, power: number, traits: number }

local RARITIES: { [string]: RarityDef } = {
	common = { id = "common", name = "Common", color = "#c8c4bb", power = 1, traits = 0 },
	rare = { id = "rare", name = "Rare", color = "#4aa8ff", power = 1.15, traits = 1 },
	unique = { id = "unique", name = "Unique", color = "#ffc23a", power = 1.3, traits = 2 },
}
local RARITY_ORDER = { "common", "rare", "unique" }

export type MeleeDef = {
	damage: number,
	rate: number, -- swings per second
	range: number, -- metres
	arc: number, -- full cone angle, radians
	knock: number,
	stagger: boolean,
}

export type ArmorDef = { defense: number, speed: number, hazard: number }

export type GadgetDef = { cooldown: number }

export type GearDef = {
	id: string,
	kind: string,
	name: string,
	description: string,
	weight: number, -- roll weight within its kind
	price: number, -- merchant price for a common one (0 = not sold)
	melee: MeleeDef?,
	armor: ArmorDef?,
	gadget: GadgetDef?,
}

local DEFS: { [string]: GearDef } = {}
local ORDER: { string } = {}

local function def(d: GearDef)
	DEFS[d.id] = d
	table.insert(ORDER, d.id)
end

-- Guns: the existing arsenal, as gear.
for _, id in Weapons.order do
	local w = Weapons.defs[id]
	def({
		id = id,
		kind = "gun",
		name = w.name,
		description = w.description,
		weight = if id == "pistol" then 0.6 else 1,
		price = 0,
	})
end

def({
	id = "machete",
	kind = "melee",
	name = "Machete",
	description = "Quick slashes, deadly up close.",
	weight = 1.2,
	price = 150,
	melee = { damage = 26, rate = 2.6, range = 2.1, arc = math.rad(110), knock = 2.5, stagger = false },
})
def({
	id = "fireaxe",
	kind = "melee",
	name = "Fire Axe",
	description = "Wide cleaving swings that hit a whole crowd.",
	weight = 1,
	price = 260,
	melee = { damage = 44, rate = 1.6, range = 2.4, arc = math.rad(150), knock = 5, stagger = false },
})
def({
	id = "sledge",
	kind = "melee",
	name = "Sledgehammer",
	description = "Slow, crushing blows that send zombies flying and stagger them.",
	weight = 0.8,
	price = 380,
	melee = { damage = 82, rate = 0.95, range = 2.3, arc = math.rad(120), knock = 12, stagger = true },
})
def({
	id = "bat",
	kind = "melee",
	name = "Baseball Bat",
	description = "Cheap and sturdy. Heavy hits knock zombies off balance.",
	weight = 1.1,
	price = 90,
	melee = { damage = 30, rate = 1.9, range = 2.2, arc = math.rad(120), knock = 6, stagger = true },
})
def({
	id = "spear",
	kind = "melee",
	name = "Spear",
	description = "Long reach in a narrow line. Keep them at arm's length.",
	weight = 0.9,
	price = 240,
	melee = { damage = 40, rate = 1.5, range = 3.3, arc = math.rad(50), knock = 3, stagger = false },
})

def({
	id = "jacket",
	kind = "armor",
	name = "Leather Jacket",
	description = "Light protection. You move a little faster.",
	weight = 1.2,
	price = 140,
	armor = { defense = 0.1, speed = 0.05, hazard = 0 },
})
def({
	id = "riotvest",
	kind = "armor",
	name = "Riot Vest",
	description = "Heavy plates: much less damage, a little slower.",
	weight = 1,
	price = 300,
	armor = { defense = 0.22, speed = -0.05, hazard = 0 },
})
def({
	id = "hazmat",
	kind = "armor",
	name = "Hazmat Suit",
	description = "Halves damage from acid and exploding zombies.",
	weight = 0.9,
	price = 240,
	armor = { defense = 0.12, speed = 0, hazard = 0.5 },
})

def({
	id = "chargeStrike",
	kind = "gadget",
	name = "Charge Strike",
	description = "Dash forward, smashing and knocking back everything in your path.",
	weight = 1,
	price = 180,
	gadget = { cooldown = 8 },
})
def({
	id = "medBurst",
	kind = "gadget",
	name = "Med Burst",
	description = "Heal yourself and teammates close by.",
	weight = 1,
	price = 220,
	gadget = { cooldown = 22 },
})
def({
	id = "shockBeacon",
	kind = "gadget",
	name = "Shock Beacon",
	description = "Stun every zombie around you for a few seconds.",
	weight = 0.9,
	price = 240,
	gadget = { cooldown = 16 },
})
def({
	id = "scrapDrone",
	kind = "gadget",
	name = "Scrap Drone",
	description = "Deploy a small turret that fights for 15 seconds.",
	weight = 0.8,
	price = 300,
	gadget = { cooldown = 30 },
})
def({
	id = "flare",
	kind = "gadget",
	name = "Flare",
	description = "Throw a burning flare that sets nearby zombies alight.",
	weight = 1,
	price = 160,
	gadget = { cooldown = 14 },
})
def({
	id = "adrenal",
	kind = "gadget",
	name = "Adrenal Shot",
	description = "+30% speed and fire rate for 6 seconds.",
	weight = 1,
	price = 200,
	gadget = { cooldown = 18 },
})

export type TraitDef = { id: string, name: string, description: string, kinds: { string } }

local TRAITS: { [string]: TraitDef } = {
	serrated = {
		id = "serrated",
		name = "Serrated",
		description = "Hits make zombies bleed.",
		kinds = { "gun", "melee" },
	},
	hollowPoint = {
		id = "hollowPoint",
		name = "Hollow-Point",
		description = "+12% critical hit chance.",
		kinds = { "gun", "melee" },
	},
	rapid = { id = "rapid", name = "Rapid", description = "+15% attack speed.", kinds = { "gun", "melee" } },
	heavy = { id = "heavy", name = "Heavy", description = "+60% knockback.", kinds = { "gun", "melee" } },
	leeching = {
		id = "leeching",
		name = "Leeching",
		description = "Heal for 3% of damage dealt.",
		kinds = { "gun", "melee" },
	},
	volatile = {
		id = "volatile",
		name = "Volatile",
		description = "15% chance that kills explode.",
		kinds = { "gun", "melee" },
	},
	chilling = {
		id = "chilling",
		name = "Chilling",
		description = "Hits slow zombies for 2 seconds.",
		kinds = { "gun", "melee" },
	},
	padded = { id = "padded", name = "Padded", description = "Take 8% less damage.", kinds = { "armor" } },
	light = { id = "light", name = "Light", description = "+6% movement speed.", kinds = { "armor" } },
	lucky = { id = "lucky", name = "Lucky", description = "+30% item and gear drops.", kinds = { "armor" } },
	scavenger = { id = "scavenger", name = "Scavenger", description = "+4 kg bag capacity.", kinds = { "armor" } },
	quickRecharge = {
		id = "quickRecharge",
		name = "Quick Recharge",
		description = "25% shorter cooldown.",
		kinds = { "gadget" },
	},
	amplified = {
		id = "amplified",
		name = "Amplified",
		description = "+30% gadget effect.",
		kinds = { "gadget" },
	},
}
local TRAIT_ORDER = {
	"serrated",
	"hollowPoint",
	"rapid",
	"heavy",
	"leeching",
	"volatile",
	"chilling",
	"padded",
	"light",
	"lucky",
	"scavenger",
	"quickRecharge",
	"amplified",
}

type RngLike = {
	next: (any) -> number,
	weighted: (any, { [string]: number }) -> string,
}

-- Rarity odds by floor: uniques become common near the top of the climb.
local function rarityWeights(floor: number): { [string]: number }
	return {
		common = math.max(10, 62 - 2 * floor),
		rare = 26 + floor,
		unique = 2 + floor * 0.7,
	}
end

-- Power level of gear found on `floor` (before the rarity bonus).
local function powerFor(floor: number): number
	return 1 + 0.04 * math.max(0, floor - 1)
end

local function traitsFor(kind: string): { string }
	local out = {}
	for _, id in TRAIT_ORDER do
		if table.find(TRAITS[id].kinds, kind) then
			table.insert(out, id)
		end
	end
	return out
end

-- Picks `n` distinct traits suitable for `kind`.
local function pickTraits(rng: RngLike, kind: string, n: number, keep: { string }?): { string }
	local pool = traitsFor(kind)
	local out = if keep then table.clone(keep) else {}
	while #out < n and #out < #pool do
		local id = pool[math.floor(rng:next() * #pool) + 1]
		if not table.find(out, id) then
			table.insert(out, id)
		end
	end
	return out
end

--[[
	Rolls a gear piece found on `floor`. `kind` restricts the kind, `minRarity`
	sets a floor on the rarity ("rare" guarantees rare or unique).
]]
local function roll(rng: RngLike, floor: number, uid: number, kind: string?, minRarity: string?): Item
	local weights: { [string]: number } = {}
	for _, id in ORDER do
		local d = DEFS[id]
		if (kind == nil or d.kind == kind) and d.weight > 0 then
			weights[id] = d.weight
		end
	end
	local id = rng:weighted(weights)
	local rw = rarityWeights(floor)
	if minRarity == "rare" then
		rw.common = 0
	elseif minRarity == "unique" then
		rw.common, rw.rare = 0, 0
	end
	local rarity = rng:weighted(rw)
	local d = DEFS[id]
	local r = RARITIES[rarity]
	return {
		uid = uid,
		id = id,
		kind = d.kind,
		rarity = rarity,
		power = math.floor(powerFor(floor) * r.power * 100 + 0.5) / 100,
		traits = pickTraits(rng, d.kind, r.traits),
	}
end

-- A fresh common piece (merchant stock and the starting kit).
local function common(id: string, uid: number, floor: number?): Item
	local d = DEFS[id]
	return {
		uid = uid,
		id = id,
		kind = d.kind,
		rarity = "common",
		power = math.floor(powerFor(floor or 1) * 100 + 0.5) / 100,
		traits = {},
	}
end

local function has(item: Item?, trait: string): boolean
	return item ~= nil and table.find(item.traits, trait) ~= nil
end

-- Materials returned when salvaging.
local function salvageValue(item: Item): { [string]: number }
	local k = if item.rarity == "unique" then 3 elseif item.rarity == "rare" then 2 else 1
	local out: { [string]: number } = { scrap = 2 * k }
	if item.kind == "gun" or item.kind == "gadget" then
		out.parts = k
	elseif item.kind == "armor" then
		out.cloth = 2 * k
	else
		out.wood = k
	end
	if item.rarity == "unique" then
		out.gunpowder = 2
	end
	return out
end

-- Coins and materials to add +0.1 power.
local function reinforceCost(item: Item): (number, { [string]: number })
	local steps = math.max(0, math.floor((item.power - 1) * 10 + 0.5))
	return 60 + 25 * steps, { scrap = 2 + steps // 2, parts = 1 }
end

-- Coins and materials to re-roll one trait (rare and unique only).
local function rerollCost(item: Item): (number, { [string]: number })
	return if item.rarity == "unique" then 220 else 140, { parts = 2, gunpowder = 1 }
end

-- Re-rolls the first trait (keeps the others).
local function rerollTrait(rng: RngLike, item: Item)
	local keep = table.clone(item.traits)
	table.remove(keep, 1)
	local pool = traitsFor(item.kind)
	for _ = 1, 20 do
		local id = pool[math.floor(rng:next() * #pool) + 1]
		if not table.find(keep, id) and id ~= item.traits[1] then
			table.insert(keep, 1, id)
			item.traits = keep
			return
		end
	end
end

-- Combined effects of the equipped melee, armor and gadgets on the player.
export type Bonus = { defense: number, speed: number, hazard: number, drop: number, carry: number }

local function bonus(armor: Item?): Bonus
	local b: Bonus = { defense = 0, speed = 0, hazard = 0, drop = 0, carry = 0 }
	if armor then
		local a = DEFS[armor.id].armor
		if a then
			-- Armor power scales its protection (capped well below immunity).
			b.defense = math.min(0.6, a.defense * armor.power)
			b.speed = a.speed
			b.hazard = a.hazard
		end
		if has(armor, "padded") then
			b.defense = math.min(0.65, b.defense + 0.08)
		end
		if has(armor, "light") then
			b.speed += 0.06
		end
		if has(armor, "lucky") then
			b.drop += 0.3
		end
		if has(armor, "scavenger") then
			b.carry += 4
		end
	end
	return b
end

local function cooldownOf(item: Item): number
	local g = DEFS[item.id].gadget
	local cd = if g then g.cooldown else 10
	return cd * (if has(item, "quickRecharge") then 0.75 else 1)
end

-- "Rare Fire Axe" etc.
local function title(item: Item): string
	return `{RARITIES[item.rarity].name} {DEFS[item.id].name}`
end

-- One-line summaries for cards and tooltips.
local function describe(item: Item): { string }
	local d = DEFS[item.id]
	local lines = { `Power {string.format("%.2f", item.power)}` }
	if d.melee then
		table.insert(lines, `{math.floor(d.melee.damage * item.power + 0.5)} damage, {d.melee.rate} swings/s`)
	elseif d.armor then
		table.insert(lines, `{math.floor(bonus(item).defense * 100 + 0.5)}% less damage`)
	elseif d.gadget then
		table.insert(lines, `{math.floor(cooldownOf(item) + 0.5)} s cooldown`)
	elseif d.kind == "gun" then
		table.insert(lines, `x{string.format("%.2f", item.power)} damage`)
	end
	for _, t in item.traits do
		table.insert(lines, `{TRAITS[t].name}: {TRAITS[t].description}`)
	end
	return lines
end

return {
	defs = DEFS,
	order = ORDER,
	rarities = RARITIES,
	rarityOrder = RARITY_ORDER,
	traits = TRAITS,
	rarityWeights = rarityWeights,
	powerFor = powerFor,
	roll = roll,
	common = common,
	has = has,
	salvageValue = salvageValue,
	reinforceCost = reinforceCost,
	rerollCost = rerollCost,
	rerollTrait = rerollTrait,
	bonus = bonus,
	cooldownOf = cooldownOf,
	title = title,
	describe = describe,
	STASH_SIZE = 10,
	GADGET_SLOTS = 3,
}
