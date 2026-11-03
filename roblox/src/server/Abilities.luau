--[[
	Gadget abilities: three equipped gadgets per player, each on its own
	cooldown (kept here, on the server). Power and the "Amplified" trait
	scale the effect; "Quick Recharge" shortens the cooldown.

	  chargeStrike - dash forward (the client moves), smashing what's in the path
	  medBurst     - heal yourself and nearby teammates
	  shockBeacon  - stun nearby zombies (bosses are only slowed)
	  scrapDrone   - a temporary turret for 15 seconds
	  flare        - thrown lure that pulls zombies in and sets them alight
	  adrenal      - +30% speed and fire rate for a few seconds
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Gear = require(Shared.Gear)

local Abilities = {}
Abilities.__index = Abilities

local CHARGE_DISTANCE = 6
local DRONE_SECONDS = 15
local ADRENAL_SECONDS = 6

function Abilities.new(W)
	return setmetatable({ W = W, near = {}, boosts = {} }, Abilities)
end

function Abilities.clear(self)
	for ps in self.boosts do
		ps.arsenal.rateMul = 1
	end
	table.clear(self.boosts)
end

local function readyTimes(ps): { [number]: number }
	if not ps.abilityReady then
		ps.abilityReady = {}
	end
	return ps.abilityReady
end

-- Sends the slot's next-ready time (server clock) to the player.
function Abilities.sync(self, ps, slot: number, effect: string?, data: any?)
	local readyAt = readyTimes(ps)[slot] or 0
	local serverReady = Workspace:GetServerTimeNow() + math.max(0, readyAt - os.clock())
	self.W.remotes.AbilitySync:FireClient(ps.player, slot, serverReady, effect, data)
end

-- Stuns or slows zombies within `radius`.
function Abilities.stun(self, x: number, z: number, radius: number, seconds: number)
	local W = self.W
	local n = W.zombies:queryRadius(x, z, radius, self.near)
	for i = 1, n do
		local zombie = self.near[i]
		if zombie.type == "boss" then
			zombie.slowUntil = os.clock() + seconds
		elseif not zombie.dying then
			zombie.stunTime = seconds
			W.zombies.setState(zombie, "stunned")
		end
	end
end

function Abilities.use(self, ps, slot: any, aimX: any, aimZ: any, aimDistance: any)
	local W = self.W
	if type(slot) ~= "number" or ps.downed or not ps.hasBody then
		return
	end
	local item = ps.gear.gadgets[slot]
	if not item then
		return
	end
	local now = os.clock()
	local ready = readyTimes(ps)
	if now < (ready[slot] or 0) - 0.1 then
		self:sync(ps, slot)
		return
	end
	local ax = if type(aimX) == "number" and aimX == aimX then aimX else 0
	local az = if type(aimZ) == "number" and aimZ == aimZ then aimZ else 1
	local len = math.sqrt(ax * ax + az * az)
	if len < 1e-3 then
		ax, az, len = 0, 1, 1
	end
	ax, az = ax / len, az / len
	local dist = if type(aimDistance) == "number" and aimDistance == aimDistance then aimDistance else 8
	local amp = item.power * (if Gear.has(item, "amplified") then 1.3 else 1)
	local effect = item.id
	local data = nil

	if item.id == "chargeStrike" then
		-- Damage along the dash line (stopping at walls); the client moves the character.
		local reach = CHARGE_DISTANCE
		local step = 0.25
		local d = step
		while d <= CHARGE_DISTANCE do
			if W.collision:overlapsCircle(ps.x + ax * d, ps.z + az * d, 0.4) then
				reach = math.max(0, d - step)
				break
			end
			d += step
		end
		local hit = {}
		local s = 0
		while s <= reach do
			local n = W.zombies:queryRadius(ps.x + ax * s, ps.z + az * s, 1.3, self.near)
			for i = 1, n do
				hit[self.near[i]] = true
			end
			s += 0.75
		end
		for zombie in hit do
			W.combat:damageZombie(zombie, 45 * amp, {
				dirX = ax,
				dirZ = az,
				knock = 9,
				source = "melee",
				crit = false,
				attacker = ps,
			})
		end
		ps.invulnUntil = math.max(ps.invulnUntil, now + 0.35)
		data = { dirX = ax, dirZ = az, distance = reach }
		W.fx("slam", { x = ps.x + ax * reach, z = ps.z + az * reach, small = true })
		W.noise(ps.x, ps.z, 8)
	elseif item.id == "medBurst" then
		local heal = 40 * amp
		for _, other in W.players:list() do
			if not other.downed and (other.x - ps.x) ^ 2 + (other.z - ps.z) ^ 2 <= 36 then
				W.players:heal(other, heal)
				W.notify(other.player, `+{math.floor(heal + 0.5)} health`, "good")
			end
		end
		W.fx("heal", { x = ps.x, z = ps.z, radius = 6 })
	elseif item.id == "shockBeacon" then
		local radius = 6 * (if Gear.has(item, "amplified") then 1.3 else 1)
		self:stun(ps.x, ps.z, radius, 2.5 * math.min(1.6, item.power))
		W.fx("shockwave", { x = ps.x, z = ps.z, delay = 0, speed = 30, maxRadius = radius })
		W.noise(ps.x, ps.z, 12)
	elseif item.id == "scrapDrone" then
		local placed = nil
		for _, offset in { { 0, 0 }, { 1.5, 0 }, { -1.5, 0 }, { 0, 1.5 }, { 0, -1.5 }, { 1.5, 1.5 }, { -1.5, -1.5 } } do
			local x = ps.x + ax * 1.6 + offset[1]
			local z = ps.z + az * 1.6 + offset[2]
			local sx, sz = W.structures:snap("turret", false, x, z)
			local ok = W.structures:canPlace(ps, "turret", false, sx, sz, true)
			if ok then
				placed = W.structures:place(ps, "turret", false, sx, sz)
				break
			end
		end
		if not placed then
			W.notify(ps.player, "No room for the drone here", "bad")
			return
		end
		placed.temporary = true
		placed.expires = now + DRONE_SECONDS * (if Gear.has(item, "amplified") then 1.3 else 1)
	elseif item.id == "flare" then
		if not W.throwables:throw(ps, ax, az, dist, "flare") then
			return
		end
	elseif item.id == "adrenal" then
		local seconds = ADRENAL_SECONDS * (if Gear.has(item, "amplified") then 1.3 else 1)
		ps.arsenal.rateMul = 1.3
		self.boosts[ps] = now + seconds
		W.players:syncArsenal(ps)
		data = { seconds = seconds }
	end
	ready[slot] = now + Gear.cooldownOf(item)
	self:sync(ps, slot, effect, data)
end

function Abilities.update(self, _dt: number)
	local now = os.clock()
	for ps, untilTime in self.boosts do
		if now >= untilTime then
			self.boosts[ps] = nil
			ps.arsenal.rateMul = 1
			if ps.player.Parent then
				self.W.players:syncArsenal(ps)
			end
		end
	end
end

return Abilities
