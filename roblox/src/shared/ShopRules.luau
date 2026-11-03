--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Shop prices, availability and purchases. Pure logic over a context so the
	server can validate every purchase (clients only display offers).
]]
local Shop = if script then require(script.Parent.Config.Shop) else require("./Config/Shop")
local Weapons = if script then require(script.Parent.Config.Weapons) else require("./Config/Weapons")

export type Action = {
	kind: string, -- weaponUpgrade | buyWeapon | ammo | playerUpgrade | heal | structure | repair
	weapon: string?,
	upgrade: string?,
	id: string?,
	structure: string?,
}

export type Offer = { cost: number, available: boolean, reason: string, tier: number, maxTier: number }

-- What the rules need to read from / do to the run.
export type Context = {
	economy: any,
	arsenal: any,
	health: number,
	maxHealth: number,
	tiers: { [string]: number },
	structureCount: (string) -> number,
	structuresMissingHp: number,
	applyPlayerUpgrade: (string) -> (),
	healFull: () -> (),
	repairStructures: () -> (),
}

local function offer(cost: number, available: boolean, reason: string, tier: number, maxTier: number): Offer
	return { cost = cost, available = available, reason = reason, tier = tier, maxTier = maxTier }
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
		return offer(Shop.weaponUpgradeCost(id, kind, tier), true, "", tier, max)
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
	elseif a.kind == "ammo" then
		local id = a.weapon :: string
		local w = ctx.arsenal:get(id)
		local def = Weapons.defs[id]
		if not w or def == nil or def.reserveMax == math.huge then
			return offer(0, false, "-", 0, 0)
		end
		if w.reserve >= def.reserveMax then
			return offer(0, false, "FULL", 0, 0)
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
	elseif a.kind == "structure" then
		local def = Shop.structures[a.structure :: string]
		if def == nil then
			return offer(0, false, "INVALID", 0, 0)
		end
		local n = ctx.structureCount(def.type)
		if n >= def.maxCount then
			return offer(def.cost, false, "LIMIT", n, def.maxCount)
		end
		return offer(def.cost, true, "", n, def.maxCount)
	elseif a.kind == "repair" then
		local missing = ctx.structuresMissingHp
		if missing < 1 then
			return offer(0, false, "NONE", 0, 0)
		end
		return offer(math.max(10, math.floor(missing * Shop.repairCostPerHp + 0.5)), true, "", 0, 0)
	end
	return offer(0, false, "INVALID", 0, 0)
end

-- Attempts a purchase. Structures are paid for at placement time instead.
local function purchase(ctx: Context, a: Action): boolean
	if a.kind == "structure" then
		return false
	end
	local o = getOffer(ctx, a)
	if not o.available or not ctx.economy:spend(o.cost) then
		return false
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
	elseif a.kind == "playerUpgrade" then
		ctx.applyPlayerUpgrade(a.id :: string)
	elseif a.kind == "heal" then
		ctx.healFull()
	elseif a.kind == "repair" then
		ctx.repairStructures()
	end
	return true
end

return { getOffer = getOffer, purchase = purchase }
