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
type GearItem = { uid: number, id: string, kind: string, rarity: string, power: number, traits: { string } }

export type Action = {
	kind: string, -- see STATION below
	weapon: string?,
	upgrade: string?,
	id: string?,
	structure: string?,
	uid: number?, -- gear piece for salvage / reinforce / reroll / sell
	count: number?, -- items to sell
}

export type Offer = {
	cost: number, -- coins
	items: { [string]: number }?, -- materials
	available: boolean,
	reason: string,
	tier: number,
	maxTier: number,
	gain: number?, -- coins received (selling)
}

-- Which station sells each kind of action.
local STATION: { [string]: string } = {
	buyWeapon = "merchant",
	ammo = "merchant",
	playerUpgrade = "merchant",
	heal = "merchant",
	buyItem = "merchant",
	buyGear = "merchant",
	sellGun = "merchant",
	sellGear = "merchant",
	sellItem = "merchant",
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
		find: (number) -> GearItem?,
		stashFull: () -> boolean,
		give: (GearItem) -> boolean,
		remove: (number) -> boolean,
		newUid: () -> number,
		rng: any,
		inStash: ((number) -> boolean)?,
	}?,
	-- Removes a sold gun (the arsenal and its attuned gear).
	removeGun: ((string) -> ())?,
}

-- Selling returns about 40% of what something cost, more for rarer, stronger pieces.
local SELL_SHARE = 0.4
local RARITY_SELL: { [string]: number } = { common = 1, rare = 1.6, unique = 2.4 }
-- Base value of gear kinds the merchant doesn't stock.
local GEAR_BASE: { [string]: number } = { gun = 200, melee = 200, armor = 200, gadget = 200 }
local ITEM_SELL_PRICES: { [string]: number } = { pipebomb = 120 }

-- Coins for one item of `id`.
local function itemSellValue(id: string): number
	local price = Shop.itemPrices[id] or ITEM_SELL_PRICES[id] or 0
	return math.floor(price * SELL_SHARE + 0.5)
end

-- Coins for a gear piece (stash) of the given def id, rarity and power.
local function gearSellValue(item: GearItem): number
	local d = Gear.defs[item.id]
	local base = if d.kind == "gun"
		then math.max(150, Weapons.defs[item.id].price)
		elseif d.price > 0 then d.price
		else GEAR_BASE[d.kind] or 150
	return math.floor(base * SELL_SHARE * (RARITY_SELL[item.rarity] or 1) * item.power + 0.5)
end

-- Coins for an owned gun: its price, the upgrades bought for it, and its attuned gear.
local function gunSellValue(id: string, w: any): number
	local def = Weapons.defs[id]
	if def.price <= 0 then
		return 0 -- the pistol is never sold
	end
	local spent = def.price
	for kind, tier in w.upgrades do
		for t = 0, tier - 1 do
			spent += Shop.weaponUpgradeCost(id, kind, t)
		end
	end
	local value = spent * SELL_SHARE
	if w.gear then
		value *= (RARITY_SELL[w.gear.rarity] or 1) * w.gear.power
	end
	return math.floor(value + 0.5)
end

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
	elseif a.kind == "sellGun" then
		local id = a.weapon :: string
		local w = ctx.arsenal:get(id)
		if not w or Weapons.defs[id] == nil then
			return offer(0, false, "NOT OWNED", 0, 0)
		end
		local value = gunSellValue(id, w)
		if value <= 0 then
			return offer(0, false, "KEEP", 0, 0)
		end
		local o = offer(0, true, "", 0, 0)
		o.gain = value
		return o
	elseif a.kind == "sellGear" then
		local g = ctx.gear
		local item = if g and a.uid then g.find(a.uid) else nil
		if not item then
			return offer(0, false, "INVALID", 0, 0)
		end
		if g and g.inStash and not g.inStash(item.uid) then
			return offer(0, false, "EQUIPPED", 0, 0)
		end
		local o = offer(0, true, "", 0, 0)
		o.gain = gearSellValue(item)
		return o
	elseif a.kind == "sellItem" then
		local id = a.id :: string
		local count = math.floor(a.count or 1)
		local value = itemSellValue(id)
		if Items.defs[id] == nil or value <= 0 then
			return offer(0, false, "INVALID", 0, 0)
		end
		if count < 1 or ctx.inventory:count(id) < count then
			return offer(0, false, "NONE", 0, 0)
		end
		local o = offer(0, true, "", 0, 0)
		o.gain = value * count
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
	if o.gain then
		ctx.economy:addCoins(o.gain)
	end
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
	elseif a.kind == "sellGun" then
		if ctx.removeGun then
			ctx.removeGun(a.weapon :: string)
		else
			ctx.arsenal:remove(a.weapon :: string)
		end
	elseif a.kind == "sellGear" then
		if not (ctx.gear :: any).remove(a.uid) then
			return false
		end
	elseif a.kind == "sellItem" then
		ctx.inventory:remove(a.id :: string, math.floor(a.count or 1))
	elseif a.kind == "salvage" then
		local g = ctx.gear :: any
		local item = g.find(a.uid) :: GearItem
		if not g.remove(item.uid) then
			return false -- equipped pieces can't be salvaged
		end
		for id, n in Gear.salvageValue(item) do
			ctx.inventory:add(id, n)
		end
	elseif a.kind == "reinforce" then
		local item = (ctx.gear :: any).find(a.uid) :: GearItem
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
	itemSellValue = itemSellValue,
	gearSellValue = gearSellValue,
	gunSellValue = gunSellValue,
}
