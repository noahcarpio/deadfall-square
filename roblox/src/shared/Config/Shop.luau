--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
local Weapons = if script then require(script.Parent.Weapons) else require("./Weapons")

local PLAYER_UPGRADES = {
	maxHealth = {
		id = "maxHealth",
		name = "Vitality",
		description = "+20 max health",
		maxTier = 5,
		baseCost = 110,
		growth = 0.55,
	},
	armor = {
		id = "armor",
		name = "Kevlar Plating",
		description = "+25 max armor and refills armor",
		maxTier = 4,
		baseCost = 130,
		growth = 0.5,
	},
	speed = {
		id = "speed",
		name = "Running Shoes",
		description = "+6% movement speed",
		maxTier = 4,
		baseCost = 140,
		growth = 0.6,
	},
	stamina = {
		id = "stamina",
		name = "Endurance",
		description = "+25% stamina and regen",
		maxTier = 3,
		baseCost = 90,
		growth = 0.6,
	},
}

local UPGRADE_ORDER = { "maxHealth", "armor", "speed", "stamina" }

local STRUCTURES = {
	barricade = {
		type = "barricade",
		name = "Barricade",
		description = "Spiked wooden wall. Blocks and distracts zombies.",
		cost = 70,
		maxCount = 8,
		hp = 320,
		footprint = { 3, 1 },
	},
	turret = {
		type = "turret",
		name = "Auto-Turret",
		description = "Shoots nearby zombies automatically.",
		cost = 320,
		maxCount = 3,
		hp = 260,
		footprint = { 2, 2 },
	},
}

local function playerUpgradeCost(id: string, tier: number): number
	local def = PLAYER_UPGRADES[id]
	return math.floor(def.baseCost * (1 + def.growth * tier) + 0.5)
end

local function weaponUpgradeCost(weapon: string, kind: string, tier: number): number
	local base = if kind == "damage" then 90 elseif kind == "fireRate" then 80 else 60
	local factor = 1 + Weapons.defs[weapon].price / 1200
	return math.floor(base * factor * (1 + 0.6 * tier) + 0.5)
end

return {
	playerUpgrades = PLAYER_UPGRADES,
	upgradeOrder = UPGRADE_ORDER,
	effects = { maxHealthPerTier = 20, armorPerTier = 25, speedPerTier = 0.06, staminaPerTier = 0.25 },
	structures = STRUCTURES,
	structureOrder = { "barricade", "turret" },
	turret = { range = 15, fireRate = 6, damage = 11, turnSpeed = 8 },
	consumables = { healBase = 20, healPerHp = 0.9, ammoPriceFactor = 0.22, ammoMinPrice = 35 },
	repairCostPerHp = 0.12,
	playerUpgradeCost = playerUpgradeCost,
	weaponUpgradeCost = weaponUpgradeCost,
}
