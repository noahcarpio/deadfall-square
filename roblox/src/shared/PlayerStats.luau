--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
local Shop = if script then require(script.Parent.Config.Shop) else require("./Config/Shop")
local Items = if script then require(script.Parent.Config.Items) else require("./Config/Items")

local BASE = {
	maxHealth = 100,
	maxArmor = 50,
	speed = 5.2,
	sprintMultiplier = 1.55,
	maxStamina = 100,
	staminaDrain = 24,
	staminaRegen = 20,
	rollCost = 24,
	rollDuration = 0.42,
	rollInvulnerable = 0.34,
	rollCooldown = 0.25,
}

export type Stats = {
	maxHealth: number,
	maxArmor: number,
	speed: number,
	maxStamina: number,
	staminaRegen: number,
	rollCost: number,
	damageTaken: number,
	reloadSpeed: number,
	dropChance: number,
	magnetRadius: number,
	carryCapacity: number,
	hazardTaken: number, -- acid and fire damage multiplier
}

export type Tiers = { maxHealth: number, armor: number, speed: number, stamina: number, backpack: number? }

type PerkLevels = { level: (any, string) -> number, has: (any, string) -> boolean }

-- Equipped-armor effects (Gear.bonus); optional.
export type GearBonus = { defense: number, speed: number, hazard: number, drop: number, carry: number }

local function compute(tiers: Tiers, perks: PerkLevels, gear: GearBonus?): Stats
	local g: GearBonus = gear or { defense = 0, speed = 0, hazard = 0, drop = 0, carry = 0 }
	local e = Shop.effects
	local marathon = perks:has("marathon")
	return {
		maxHealth = BASE.maxHealth + e.maxHealthPerTier * tiers.maxHealth,
		maxArmor = BASE.maxArmor + e.armorPerTier * tiers.armor,
		speed = BASE.speed * (1 + e.speedPerTier * tiers.speed + g.speed),
		maxStamina = BASE.maxStamina * (1 + e.staminaPerTier * tiers.stamina + (if marathon then 0.4 else 0)),
		staminaRegen = BASE.staminaRegen * (1 + 0.25 * tiers.stamina + (if marathon then 0.3 else 0)),
		rollCost = BASE.rollCost * (if marathon then 0.7 else 1),
		damageTaken = 0.88 ^ perks:level("thickSkin") * (1 - g.defense),
		reloadSpeed = 1 + 0.3 * perks:level("quickHands"),
		dropChance = 1 + 0.5 * perks:level("scavenger") + g.drop,
		magnetRadius = 2.5 + 1.5 * perks:level("scavenger"),
		carryCapacity = Items.BASE_CAPACITY + Items.CAPACITY_PER_BACKPACK * (tiers.backpack or 0) + g.carry,
		hazardTaken = 1 - g.hazard,
	}
end

-- Armor absorbs 70% of each hit while it lasts. Returns new (health, armor).
local function applyArmor(health: number, armor: number, damage: number): (number, number)
	if damage <= 0 then
		return health, armor
	end
	local absorbed = math.min(armor, damage * 0.7)
	return health - (damage - absorbed), armor - absorbed
end

return { BASE = BASE, compute = compute, applyArmor = applyArmor }
