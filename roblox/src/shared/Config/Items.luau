--!strict
-- Inventory items: crafting materials found while looting, plus usable items.
-- Weights are in kilograms; the bag's capacity comes from PlayerStats.

export type ItemDef = {
	id: string,
	name: string,
	weight: number,
	description: string,
	use: string?, -- "bandage" | "throw" for usable items
	key: string?, -- keyboard hint shown in the HUD
}

local ITEMS: { [string]: ItemDef } = {
	scrap = { id = "scrap", name = "Scrap Metal", weight = 0.5, description = "Bent metal. Used in most recipes." },
	wood = { id = "wood", name = "Planks", weight = 0.8, description = "Builds barricades and repairs them." },
	cloth = { id = "cloth", name = "Rags", weight = 0.2, description = "Makes bandages." },
	parts = { id = "parts", name = "Electronics", weight = 0.3, description = "Turrets, pipe bombs and upgrades." },
	gunpowder = { id = "gunpowder", name = "Gunpowder", weight = 0.25, description = "Hand-loaded ammo and bombs." },
	bandage = {
		id = "bandage",
		name = "Bandage",
		weight = 0.1,
		description = "Restores 35 health.",
		use = "bandage",
		key = "B",
	},
	pipebomb = {
		id = "pipebomb",
		name = "Pipe Bomb",
		weight = 0.6,
		description = "Beeps loudly to lure zombies, then explodes.",
		use = "throw",
		key = "G",
	},
}

return {
	defs = ITEMS,
	order = { "scrap", "wood", "cloth", "parts", "gunpowder", "bandage", "pipebomb" },
	materials = { "scrap", "wood", "cloth", "parts", "gunpowder" },
	BASE_CAPACITY = 10,
	CAPACITY_PER_BACKPACK = 5,
	BANDAGE_HEAL = 35,
	PIPEBOMB = { fuse = 4, radius = 4.5, damage = 220, noise = 30, range = 14 },
}
