--!strict
local Shop = if script then require(script.Parent.Config.Shop) else require("./Config/Shop")

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
}

export type Tiers = { maxHealth: number, armor: number, speed: number, stamina: number }

type PerkLevels = { level: (any, string) -> number, has: (any, string) -> boolean }

local function compute(tiers: Tiers, perks: PerkLevels): Stats
	local e = Shop.effects
	local marathon = perks:has("marathon")
	return {
		maxHealth = BASE.maxHealth + e.maxHealthPerTier * tiers.maxHealth,
		maxArmor = BASE.maxArmor + e.armorPerTier * tiers.armor,
		speed = BASE.speed * (1 + e.speedPerTier * tiers.speed),
		maxStamina = BASE.maxStamina * (1 + e.staminaPerTier * tiers.stamina + (if marathon then 0.4 else 0)),
		staminaRegen = BASE.staminaRegen * (1 + 0.25 * tiers.stamina + (if marathon then 0.3 else 0)),
		rollCost = BASE.rollCost * (if marathon then 0.7 else 1),
		damageTaken = 0.88 ^ perks:level("thickSkin"),
		reloadSpeed = 1 + 0.3 * perks:level("quickHands"),
		dropChance = 1 + 0.5 * perks:level("scavenger"),
		magnetRadius = 2.5 + 1.5 * perks:level("scavenger"),
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
