--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	A player's weapons: ownership, ammo, reloading and fire-rate gating.
	Time-based (callers pass the current time) so the same module runs on the
	server (authoritative) and on the client (prediction).
]]
local Weapons = if script then require(script.Parent.Config.Weapons) else require("./Config/Weapons")

export type WeaponState = {
	id: string,
	mag: number,
	reserve: number,
	upgrades: { damage: number, fireRate: number, magazine: number },
	-- Gear attuned to this gun (rarity, power, traits); nil for a plain gun.
	gear: GunGear?,
}

export type GunGear = { uid: number, rarity: string, power: number, traits: { string } }

local Arsenal = {}
Arsenal.__index = Arsenal

-- Guns carried besides the pistol (slots 2 and 3; the pistol is always slot 1).
Arsenal.MAX_GUNS = 2

export type Arsenal = typeof(setmetatable(
	{} :: {
		owned: { [string]: WeaponState },
		current: string,
		reloadEnd: number,
		reloadDuration: number,
		nextShot: number,
		rateMul: number,
		-- Shots fired so far in the current burst (burst guns only).
		burstIndex: number,
	},
	Arsenal
))

function Arsenal.new(): Arsenal
	local self = setmetatable(
		{ owned = {}, current = "pistol", reloadEnd = 0, reloadDuration = 0, nextShot = 0, rateMul = 1, burstIndex = 0 },
		Arsenal
	)
	self:give("pistol")
	return self
end

function Arsenal.get(self: Arsenal, id: string): WeaponState?
	return self.owned[id]
end

function Arsenal.owns(self: Arsenal, id: string): boolean
	return self.owned[id] ~= nil
end

function Arsenal.currentState(self: Arsenal): WeaponState
	return self.owned[self.current] :: WeaponState
end

function Arsenal.magSize(self: Arsenal, id: string): number
	local w = self.owned[id]
	local def = Weapons.defs[id]
	return if w then Weapons.magSizeOf(def, w.upgrades) else def.magSize
end

-- Guns owned besides the pistol.
function Arsenal.gunCount(self: Arsenal): number
	local n = 0
	for id in self.owned do
		if id ~= "pistol" then
			n += 1
		end
	end
	return n
end

-- True if `id` is owned or there's a free slot for it.
function Arsenal.hasRoomFor(self: Arsenal, id: string): boolean
	return self.owned[id] ~= nil or self:gunCount() < Arsenal.MAX_GUNS
end

-- The gun given up to make room for a new one: the gun in hand, else the one in slot 2.
function Arsenal.swapTarget(self: Arsenal): string?
	if self.current ~= "pistol" and self.owned[self.current] then
		return self.current
	end
	local list = self:list()
	return if list[2] then list[2].id else nil
end

-- The weapon in slot `n` (1 = pistol), if any.
function Arsenal.inSlot(self: Arsenal, n: number): string?
	local w = self:list()[n]
	return if w then w.id else nil
end

-- Owned weapons in slot order: the pistol, then the others in Weapons.order.
function Arsenal.list(self: Arsenal): { WeaponState }
	local out = {}
	for _, id in Weapons.order do
		local w = self.owned[id]
		if w then
			table.insert(out, w)
		end
	end
	return out
end

-- Gives a weapon; owning it already grants half a reserve of ammo instead.
-- "full" (and nothing changes) when every gun slot is taken: make room first.
function Arsenal.give(self: Arsenal, id: string): "new" | "ammo" | "full"
	if self.owned[id] then
		self:addAmmoFraction(id, 0.5)
		return "ammo"
	end
	if not self:hasRoomFor(id) then
		return "full"
	end
	local def = Weapons.defs[id]
	self.owned[id] = {
		id = id,
		mag = def.magSize,
		reserve = def.startReserve,
		upgrades = { damage = 0, fireRate = 0, magazine = 0 },
	}
	return "new"
end

function Arsenal.addAmmoFraction(self: Arsenal, id: string, fraction: number): number
	local w = self.owned[id]
	if not w then
		return 0
	end
	local max = Weapons.defs[id].reserveMax
	if max == math.huge then
		return 0
	end
	local before = w.reserve
	w.reserve = math.min(max, w.reserve + math.ceil(max * fraction))
	return w.reserve - before
end

function Arsenal.refill(self: Arsenal, id: string)
	local w = self.owned[id]
	if w then
		w.reserve = Weapons.defs[id].reserveMax
		w.mag = self:magSize(id)
	end
end

function Arsenal.lowOnAmmo(self: Arsenal, fraction: number): boolean
	for id, w in self.owned do
		local max = Weapons.defs[id].reserveMax
		if max ~= math.huge and w.reserve + w.mag < max * fraction then
			return true
		end
	end
	return false
end

function Arsenal.isReloading(self: Arsenal, now: number): boolean
	return now < self.reloadEnd
end

function Arsenal.switchTo(self: Arsenal, id: string, now: number): boolean
	if not self.owned[id] or id == self.current then
		return false
	end
	self.current = id
	self.reloadEnd = 0
	self.burstIndex = 0
	self.nextShot = math.max(self.nextShot, now + 0.18)
	return true
end

function Arsenal.cycle(self: Arsenal, direction: number, now: number): boolean
	local ids = {}
	local index = 1
	for _, w in self:list() do
		table.insert(ids, w.id)
		if w.id == self.current then
			index = #ids
		end
	end
	if #ids < 2 then
		return false
	end
	local nextIndex = ((index - 1 + (if direction > 0 then 1 else -1)) % #ids) + 1
	return self:switchTo(ids[nextIndex], now)
end

function Arsenal.canReload(self: Arsenal, now: number): boolean
	local w = self:currentState()
	return not self:isReloading(now) and w.mag < self:magSize(w.id) and w.reserve > 0
end

function Arsenal.startReload(self: Arsenal, now: number, speed: number): boolean
	if not self:canReload(now) then
		return false
	end
	self.reloadDuration = Weapons.defs[self.current].reloadTime / speed
	self.reloadEnd = now + self.reloadDuration
	self.burstIndex = 0
	return true
end

-- Completes a reload whose time has passed. Returns true if one finished.
function Arsenal.finishReload(self: Arsenal, now: number): boolean
	if self.reloadEnd == 0 or now < self.reloadEnd then
		return false
	end
	local w = self:currentState()
	local take = math.min(self:magSize(w.id) - w.mag, w.reserve)
	w.mag += take
	if w.reserve ~= math.huge then
		w.reserve -= take
	end
	self.reloadEnd = 0
	return true
end

--[[
	Attempts one trigger pull at `now`. `tolerance` (0..1) allows shots slightly
	early, absorbing network jitter on the server. Returns "fired", "empty"
	(reload started or dry fire) or "blocked" (cooling down / reloading).
]]
function Arsenal.tryFire(
	self: Arsenal,
	now: number,
	tolerance: number,
	reloadSpeed: number
): "fired" | "empty" | "blocked"
	self:finishReload(now)
	if self:isReloading(now) then
		return "blocked"
	end
	local w = self:currentState()
	local def = Weapons.defs[w.id]
	-- One cycle per 1 / fireRate; burst guns fire `burst` shots `burstGap` apart inside it.
	local cycle = 1 / (Weapons.fireRateOf(def, w.upgrades) * self:rateBonus(w))
	local burst = def.burst or 1
	local gap = math.min(def.burstGap or 0, cycle / burst)
	local interval = if burst > 1 and self.burstIndex > 0 then gap else cycle - gap * (burst - 1)
	-- Tolerance scales with the whole cycle, so network jitter can't drop shots inside a burst.
	if now < self.nextShot - (if burst > 1 then cycle else interval) * tolerance then
		return "blocked"
	end
	if w.mag <= 0 then
		self:startReload(now, reloadSpeed)
		self.nextShot = now + interval
		return "empty"
	end
	w.mag -= 1
	self.burstIndex = (self.burstIndex + 1) % burst
	local wait = if self.burstIndex > 0 then gap else cycle - gap * (burst - 1)
	-- Carry over at most a frame of lateness, so holding the trigger keeps the full rate but a shot
	-- after a pause can't be followed by an instant second one.
	self.nextShot = math.max(self.nextShot, now - math.min(wait * 0.5, 1 / 60)) + wait
	if w.mag == 0 then
		self:startReload(now + interval, reloadSpeed)
	end
	return "fired"
end

-- Removes a gun (sold or dropped). The pistol is never removed; holding it again if needed.
function Arsenal.remove(self: Arsenal, id: string): boolean
	if id == "pistol" or not self.owned[id] then
		return false
	end
	self.owned[id] = nil
	if self.current == id then
		self.current = "pistol"
		self.reloadEnd = 0
	end
	return true
end

-- Fire-rate multiplier from the gun's gear ("Rapid") and temporary boosts.
function Arsenal.rateBonus(self: Arsenal, w: WeaponState): number
	local k = self.rateMul
	if w.gear and table.find(w.gear.traits, "rapid") then
		k *= 1.15
	end
	return k
end

-- Damage multiplier from the gun's gear power.
function Arsenal.powerOf(self: Arsenal, id: string): number
	local w = self.owned[id]
	return if w and w.gear then w.gear.power else 1
end

-- Attunes gear to a gun (giving the gun if it isn't owned yet). False when there's no slot for it.
function Arsenal.attune(self: Arsenal, id: string, gear: GunGear): boolean
	if not self.owned[id] and self:give(id) == "full" then
		return false
	end
	local w = self.owned[id]
	w.gear = { uid = gear.uid, rarity = gear.rarity, power = gear.power, traits = table.clone(gear.traits) }
	return true
end

-- Reloads every weapon from reserve (free top-up between waves).
function Arsenal.reloadAll(self: Arsenal)
	for id, w in self.owned do
		local take = math.min(self:magSize(id) - w.mag, w.reserve)
		w.mag += take
		if w.reserve ~= math.huge then
			w.reserve -= take
		end
	end
	self.reloadEnd = 0
end

-- Network-friendly copy (math.huge is encoded as -1).
function Arsenal.serialize(self: Arsenal): { [string]: any }
	local weapons = {}
	for id, w in self.owned do
		weapons[id] = {
			mag = w.mag,
			reserve = if w.reserve == math.huge then -1 else w.reserve,
			upgrades = table.clone(w.upgrades),
			gear = w.gear,
		}
	end
	return {
		current = self.current,
		weapons = weapons,
		reloadEnd = self.reloadEnd,
		reloadDuration = self.reloadDuration,
		rateMul = self.rateMul,
	}
end

function Arsenal.applySerialized(self: Arsenal, data: { [string]: any })
	table.clear(self.owned)
	for id, w in data.weapons do
		self.owned[id] = {
			id = id,
			mag = w.mag,
			reserve = if w.reserve < 0 then math.huge else w.reserve,
			upgrades = { damage = w.upgrades.damage, fireRate = w.upgrades.fireRate, magazine = w.upgrades.magazine },
			gear = w.gear,
		}
	end
	self.current = data.current
	self.reloadEnd = data.reloadEnd
	self.reloadDuration = data.reloadDuration
	self.rateMul = data.rateMul or self.rateMul
end

return Arsenal
