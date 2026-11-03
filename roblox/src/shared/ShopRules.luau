--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Prices, availability and effects of everything players can buy or craft.
	Pure logic over a context, so the server validates every action and
	clients display the same offers.

	There are two stations, used during the grace period between waves:
	  merchant  - coins:     weapons, ammo, medkit, survivor upgrades, supplies
	  workbench - materials: crafting, hand-loaded ammo, weapon upgrades
	              (which also cost coins), repairs and structures
]]
local Shop = if script then require(script.Parent.Config.Shop) else require("./Config/Shop")
local Weapons = if script then require(script.Parent.Config.Weapons) else require("./Config/Weapons")
local Items = if script then require(script.Parent.Config.Items) else require("./Config/Items")
local Gear = if script then require(script.Parent.Gear) else require("./Gear")

export type Action = {
	kind: string, -- see STATION below
	weapon: string?,
	upgrade: string?,
	id: string?,
	structure: string?,
	uid: number?, -- gear piece for salvage / reinforce / reroll
}

export type Offer = {
	cost: number, -- coins
	items: { [string]: number }?, -- materials
	available: boolean,
	reason: string,
	tier: number,
	maxTier: number,
}

-- Which station sells each kind of action.
local STATION: { [string]: string } = {
	buyWeapon = "merchant",
	ammo = "merchant",
	playerUpgrade = "merchant",
	heal = "merchant",
	buyItem = "merchant",
	buyGear = "merchant",
	salvage = "workbench",
	reinforce = "workbench",
	reroll = "workbench",
	weaponUpgrade = "workbench",
	craft = "workbench",
	handload = "workbench",
	repair = "workbench",
	structure = "workbench",
}

-- What the rules need to read from / do to the run.
export type Context = {
	economy: any,
	arsenal: any,
	inventory: any, -- Inventory (or a read-only mirror with the same methods)
	health: number,
	maxHealth: number,
	tiers: { [string]: number },
	structureCount: (string) -> number,
	structuresMissingHp: number,
	applyPlayerUpgrade: (string) -> (),
	healFull: () -> (),
	repairStructures: () -> (),
	-- Gear access (stash, equipped and gun gear); optional for contexts without gear.
	gear: {
		find: (number) -> Gear.Item?,
		stashFull: () -> boolean,
		give: (Gear.Item) -> boolean,
		remove: (number) -> boolean,
		newUid: () -> number,
		rng: any,
	}?,
}

local function offer(cost: number, available: boolean, reason: string, tier: number, maxTier: number): Offer
	return { cost = cost, items = nil, available = available, reason = reason, tier = tier, maxTier = maxTier }
end

local function costWeight(cost: { [string]: number }): number
	local w = 0
	for id, n in cost do
		w += Items.defs[id].weight * n
	end
	return w
end

local function getOffer(ctx: Context, a: Action): Offer
	if a.kind == "weaponUpgrade" then
		local id = a.weapon :: string
		local kind = a.upgrade :: string
		local max = Weapons.upgradeLimits[kind]
		if max == nil or Weapons.defs[id] == nil then
			return offer(0, false, "INVALID", 0, 0)
		end
		local w = ctx.arsenal:get(id)
		if not w then
			return offer(0, false, "NOT OWNED", 0, max)
		end
		local tier = w.upgrades[kind]
		if tier >= max then
			return offer(0, false, "MAX", tier, max)
		end
		local o = offer(Shop.weaponUpgradeCost(id, kind, tier), true, "", tier, max)
		o.items = Shop.weaponUpgradeMaterials(kind, tier)
		return o
	elseif a.kind == "buyWeapon" then
		local id = a.weapon :: string
		local def = Weapons.defs[id]
		if def == nil or def.price <= 0 then
			return offer(0, false, "INVALID", 0, 1)
		end
		if ctx.arsenal:owns(id) then
			return offer(0, false, "OWNED", 1, 1)
		end
		return offer(def.price, true, "", 0, 1)
	elseif a.kind == "ammo" or a.kind == "handload" then
		local id = a.weapon :: string
		local w = ctx.arsenal:get(id)
		local def = Weapons.defs[id]
		if not w or def == nil or def.reserveMax == math.huge then
			return offer(0, false, "-", 0, 0)
		end
		if w.reserve >= def.reserveMax then
			return offer(0, false, "FULL", 0, 0)
		end
		if a.kind == "handload" then
			local o = offer(0, true, "", 0, 0)
			o.items = Shop.handload.cost
			return o
		end
		local missing = 1 - w.reserve / def.reserveMax
		local c = Shop.consumables
		return offer(
			math.max(c.ammoMinPrice, math.floor(def.price * c.ammoPriceFactor * missing + 0.5)),
			true,
			"",
			0,
			0
		)
	elseif a.kind == "playerUpgrade" then
		local id = a.id :: string
		local def = Shop.playerUpgrades[id]
		if def == nil then
			return offer(0, false, "INVALID", 0, 0)
		end
		local tier = ctx.tiers[id] or 0
		if tier >= def.maxTier then
			return offer(0, false, "MAX", tier, def.maxTier)
		end
		return offer(Shop.playerUpgradeCost(id, tier), true, "", tier, def.maxTier)
	elseif a.kind == "heal" then
		local missing = ctx.maxHealth - ctx.health
		if missing < 1 then
			return offer(0, false, "FULL", 0, 0)
		end
		local c = Shop.consumables
		return offer(math.floor(c.healBase + missing * c.healPerHp + 0.5), true, "", 0, 0)
	elseif a.kind == "buyItem" then
		local id = a.id :: string
		local price = Shop.itemPrices[id]
		if price == nil or Items.defs[id] == nil then
			return offer(0, false, "INVALID", 0, 0)
		end
		if ctx.inventory:fits(id, 1) < 1 then
			return offer(price, false, "BAG FULL", 0, 0)
		end
		return offer(price, true, "", 0, 0)
	elseif a.kind == "craft" then
		local recipe = Shop.recipes[a.id :: string]
		if recipe == nil then
			return offer(0, false, "INVALID", 0, 0)
		end
		local o = offer(0, true, "", 0, 0)
		o.items = recipe.cost
		local gain = Items.defs[recipe.item].weight * recipe.count - costWeight(recipe.cost)
		if gain > ctx.inventory.capacity - ctx.inventory:weight() + 1e-6 then
			o.available = false
			o.reason = "BAG FULL"
		end
		return o
	elseif a.kind == "buyGear" then
		local d = Gear.defs[a.id :: string]
		if d == nil or d.price <= 0 then
			return offer(0, false, "INVALID", 0, 0)
		end
		if not ctx.gear or ctx.gear.stashFull() then
			return offer(d.price, false, "STASH FULL", 0, 0)
		end
		return offer(d.price, true, "", 0, 0)
	elseif a.kind == "salvage" or a.kind == "reinforce" or a.kind == "reroll" then
		local item = if ctx.gear and a.uid then ctx.gear.find(a.uid) else nil
		if not item then
			return offer(0, false, "INVALID", 0, 0)
		end
		if a.kind == "salvage" then
			return offer(0, true, "", 0, 0)
		elseif a.kind == "reinforce" then
			if item.power >= 3 then
				return offer(0, false, "MAX", 0, 0)
			end
			local coins, mats = Gear.reinforceCost(item)
			local o = offer(coins, true, "", 0, 0)
			o.items = mats
			return o
		else
			if item.rarity == "common" or #item.traits == 0 then
				return offer(0, false, "NO TRAITS", 0, 0)
			end
			local coins, mats = Gear.rerollCost(item)
			local o = offer(coins, true, "", 0, 0)
			o.items = mats
			return o
		end
	elseif a.kind == "structure" then
		local def = Shop.structures[a.structure :: string]
		if def == nil then
			return offer(0, false, "INVALID", 0, 0)
		end
		local n = ctx.structureCount(def.type)
		local o = offer(0, n < def.maxCount, if n < def.maxCount then "" else "LIMIT", n, def.maxCount)
		o.items = def.materials
		return o
	elseif a.kind == "repair" then
		local missing = ctx.structuresMissingHp
		if missing < 1 then
			return offer(0, false, "NONE", 0, 0)
		end
		local o = offer(0, true, "", 0, 0)
		o.items = { wood = math.max(1, math.ceil(missing / Shop.repairHpPerWood)) }
		return o
	end
	return offer(0, false, "INVALID", 0, 0)
end

-- True if the player can pay an available offer (coins and materials).
local function affordable(ctx: Context, o: Offer): boolean
	return o.available and ctx.economy.coins >= o.cost and ctx.inventory:has(o.items)
end

--[[
	Attempts an action. Structures are paid for at placement time instead
	(see payForStructure).
]]
local function purchase(ctx: Context, a: Action): boolean
	if a.kind == "structure" or STATION[a.kind] == nil then
		return false
	end
	local o = getOffer(ctx, a)
	if not affordable(ctx, o) then
		return false
	end
	if not ctx.economy:spend(o.cost) then
		return false
	end
	ctx.inventory:take(o.items)
	if a.kind == "weaponUpgrade" then
		local id = a.weapon :: string
		local w = ctx.arsenal:get(id)
		local before = ctx.arsenal:magSize(id)
		w.upgrades[a.upgrade :: string] += 1
		if a.upgrade == "magazine" then
			-- A bigger magazine is delivered full.
			w.mag += ctx.arsenal:magSize(id) - before
		end
	elseif a.kind == "buyWeapon" then
		ctx.arsenal:give(a.weapon :: string)
	elseif a.kind == "ammo" then
		ctx.arsenal:refill(a.weapon :: string)
	elseif a.kind == "handload" then
		local id = a.weapon :: string
		local w = ctx.arsenal:get(id)
		local max = Weapons.defs[id].reserveMax
		w.reserve = math.min(max, w.reserve + math.floor(max * Shop.handload.fraction + 0.5))
	elseif a.kind == "playerUpgrade" then
		ctx.applyPlayerUpgrade(a.id :: string)
	elseif a.kind == "heal" then
		ctx.healFull()
	elseif a.kind == "buyItem" then
		ctx.inventory:add(a.id :: string, 1)
	elseif a.kind == "craft" then
		local recipe = Shop.recipes[a.id :: string]
		ctx.inventory:add(recipe.item, recipe.count)
	elseif a.kind == "repair" then
		ctx.repairStructures()
	elseif a.kind == "buyGear" then
		local g = ctx.gear :: any
		g.give(Gear.common(a.id :: string, g.newUid()))
	elseif a.kind == "salvage" then
		local g = ctx.gear :: any
		local item = g.find(a.uid) :: Gear.Item
		if not g.remove(item.uid) then
			return false -- equipped pieces can't be salvaged
		end
		for id, n in Gear.salvageValue(item) do
			ctx.inventory:add(id, n)
		end
	elseif a.kind == "reinforce" then
		local item = (ctx.gear :: any).find(a.uid) :: Gear.Item
		item.power = math.floor((item.power + 0.1) * 100 + 0.5) / 100
	elseif a.kind == "reroll" then
		local g = ctx.gear :: any
		Gear.rerollTrait(g.rng, g.find(a.uid))
	end
	return true
end

-- Takes a structure's materials when it is placed. Returns false if short or at the limit.
local function payForStructure(ctx: Context, stype: string): boolean
	local o = getOffer(ctx, { kind = "structure", structure = stype })
	if not affordable(ctx, o) then
		return false
	end
	return ctx.inventory:take(o.items)
end

return {
	STATION = STATION,
	getOffer = getOffer,
	affordable = affordable,
	purchase = purchase,
	payForStructure = payForStructure,
}
