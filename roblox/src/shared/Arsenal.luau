--!strict
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
}

local Arsenal = {}
Arsenal.__index = Arsenal

export type Arsenal = typeof(setmetatable(
	{} :: {
		owned: { [string]: WeaponState },
		current: string,
		reloadEnd: number,
		reloadDuration: number,
		nextShot: number,
	},
	Arsenal
))

function Arsenal.new(): Arsenal
	local self = setmetatable({ owned = {}, current = "pistol", reloadEnd = 0, reloadDuration = 0, nextShot = 0 }, Arsenal)
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

-- Owned weapons in slot order.
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
function Arsenal.give(self: Arsenal, id: string): "new" | "ammo"
	if self.owned[id] then
		self:addAmmoFraction(id, 0.5)
		return "ammo"
	end
	local def = Weapons.defs[id]
	self.owned[id] = { id = id, mag = def.magSize, reserve = def.startReserve, upgrades = { damage = 0, fireRate = 0, magazine = 0 } }
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
function Arsenal.tryFire(self: Arsenal, now: number, tolerance: number, reloadSpeed: number): "fired" | "empty" | "blocked"
	self:finishReload(now)
	if self:isReloading(now) then
		return "blocked"
	end
	local w = self:currentState()
	local interval = 1 / Weapons.fireRateOf(Weapons.defs[w.id], w.upgrades)
	if now < self.nextShot - interval * tolerance then
		return "blocked"
	end
	if w.mag <= 0 then
		self:startReload(now, reloadSpeed)
		self.nextShot = now + interval
		return "empty"
	end
	w.mag -= 1
	self.nextShot = math.max(self.nextShot, now - interval) + interval
	if w.mag == 0 then
		self:startReload(now + interval, reloadSpeed)
	end
	return "fired"
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
		}
	end
	return { current = self.current, weapons = weapons, reloadEnd = self.reloadEnd, reloadDuration = self.reloadDuration }
end

function Arsenal.applySerialized(self: Arsenal, data: { [string]: any })
	table.clear(self.owned)
	for id, w in data.weapons do
		self.owned[id] = {
			id = id,
			mag = w.mag,
			reserve = if w.reserve < 0 then math.huge else w.reserve,
			upgrades = { damage = w.upgrades.damage, fireRate = w.upgrades.fireRate, magazine = w.upgrades.magazine },
		}
	end
	self.current = data.current
	self.reloadEnd = data.reloadEnd
	self.reloadDuration = data.reloadDuration
end

return Arsenal
