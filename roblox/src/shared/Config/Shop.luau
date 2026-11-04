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
	backpack = {
		id = "backpack",
		name = "Bigger Backpack",
		description = "+5 kg carrying capacity",
		maxTier = 3,
		baseCost = 100,
		growth = 0.7,
	},
}

local UPGRADE_ORDER = { "maxHealth", "armor", "speed", "stamina", "backpack" }

-- Merchant prices (coins) for single items.
local ITEM_PRICES: { [string]: number } =
	{ scrap = 20, wood = 15, cloth = 12, parts = 35, gunpowder = 30, bandage = 45 }
local ITEM_SHOP_ORDER = { "bandage", "scrap", "wood", "cloth", "parts", "gunpowder" }

-- Workbench recipes that make an inventory item.
export type Recipe = { id: string, item: string, count: number, cost: { [string]: number } }
local RECIPES: { [string]: Recipe } = {
	bandage = { id = "bandage", item = "bandage", count = 1, cost = { cloth = 2 } },
	pipebomb = { id = "pipebomb", item = "pipebomb", count = 1, cost = { scrap = 2, gunpowder = 2, parts = 1 } },
}
local RECIPE_ORDER = { "bandage", "pipebomb" }

-- Materials for hand-loading ammo (refills a share of one weapon's reserve).
local HANDLOAD: { cost: { [string]: number }, fraction: number } =
	{ cost = { gunpowder = 2, scrap = 1 }, fraction = 0.4 }

-- One plank repairs this much structure health.
local REPAIR_HP_PER_WOOD = 80

export type StructureDef = {
	type: string,
	name: string,
	description: string,
	materials: { [string]: number },
	maxCount: number,
	hp: number,
	footprint: { number },
}
local STRUCTURES: { [string]: StructureDef } = {
	barricade = {
		type = "barricade",
		name = "Barricade",
		description = "Spiked wooden wall. Blocks and distracts zombies.",
		materials = { wood = 4, scrap = 1 },
		maxCount = 8,
		hp = 320,
		footprint = { 3, 1 },
	},
	turret = {
		type = "turret",
		name = "Auto-Turret",
		description = "Shoots nearby zombies automatically.",
		materials = { scrap = 6, parts = 3, gunpowder = 2 },
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

-- Materials a weapon upgrade needs on top of its coin cost.
local function weaponUpgradeMaterials(kind: string, tier: number): { [string]: number }
	local cost: { [string]: number } = { scrap = 1 + tier }
	if tier > 0 or kind == "fireRate" then
		cost.parts = math.max(1, tier)
	end
	return cost
end

return {
	playerUpgrades = PLAYER_UPGRADES,
	upgradeOrder = UPGRADE_ORDER,
	effects = { maxHealthPerTier = 20, armorPerTier = 25, speedPerTier = 0.06, staminaPerTier = 0.25 },
	structures = STRUCTURES,
	structureOrder = { "barricade", "turret" },
	turret = { range = 15, fireRate = 6, damage = 11, turnSpeed = 8 },
	consumables = { healBase = 20, healPerHp = 0.9, ammoPriceFactor = 0.22, ammoMinPrice = 35 },
	repairHpPerWood = REPAIR_HP_PER_WOOD,
	itemPrices = ITEM_PRICES,
	itemShopOrder = ITEM_SHOP_ORDER,
	recipes = RECIPES,
	recipeOrder = RECIPE_ORDER,
	handload = HANDLOAD,
	playerUpgradeCost = playerUpgradeCost,
	weaponUpgradeCost = weaponUpgradeCost,
	weaponUpgradeMaterials = weaponUpgradeMaterials,
}
