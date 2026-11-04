--[[
	Server-side zombie simulation (no Parts, no physics): pooled zombie records
	moved by flow-field steering, crowd separation through a spatial hash,
	obstacle push-out, and per-type AI (walker, runner, brute, spitter,
	exploder, boss). Clients receive compact snapshots and render the horde
	themselves.

	Every zombie hunts the nearest living target (players, plus the bell on a
	defend floor) through the player flow field.
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local ZombiesConfig = require(Shared.Config.Zombies)
local MathUtil = require(Shared.Util.MathUtil)
local SpatialHash = require(Shared.Util.SpatialHash)
local Net = require(Shared.Net)

local SPITTER = ZombiesConfig.spitter
local BOSS = ZombiesConfig.boss
local MAX = Constants.MAX_ZOMBIES
local TOPPLE_TIME = 0.45
local SPAWN_TIME = 0.7
local STUCK_LIMIT = 8
local damp = MathUtil.damp
local angleDamp = MathUtil.angleDamp

local ZombieSim = {}
ZombieSim.__index = ZombieSim

function ZombieSim.new(W)
	local self = setmetatable({
		W = W,
		list = {}, -- active (alive or dying) zombies
		free = {},
		byId = {},
		aliveCount = 0,
		hash = SpatialHash.new(
			-Constants.WORLD_HALF,
			-Constants.WORLD_HALF,
			Constants.WORLD_HALF,
			Constants.WORLD_HALF,
			2
		),
		near = {},
		snapshotTimer = 0,
		records = {},
	}, ZombieSim)
	for id = MAX, 1, -1 do
		table.insert(self.free, id)
	end
	return self
end

function ZombieSim.clear(self)
	for _, z in self.list do
		table.insert(self.free, z.id)
		self.byId[z.id] = nil
	end
	table.clear(self.list)
	self.aliveCount = 0
end

function ZombieSim.capacityLeft(self): number
	return #self.free
end

-- Spawns a zombie; `scaling` = { hp, damage, speed } multipliers.
function ZombieSim.spawn(self, ztype: string, x: number, z: number, scaling)
	local id = table.remove(self.free)
	if not id then
		return nil
	end
	local rng = self.W.rng
	local def = ZombiesConfig.defs[ztype]
	local speedVar = 0.88 + rng:next() * 0.24
	local zombie = {
		id = id,
		type = ztype,
		def = def,
		x = x,
		z = z,
		vx = 0,
		vz = 0,
		kx = 0,
		kz = 0,
		dirX = 0,
		dirZ = 1,
		facing = 0,
		maxHp = def.hp * scaling.hp,
		hp = def.hp * scaling.hp,
		speed = def.speed * scaling.speed * speedVar,
		damage = def.damage * scaling.damage,
		radius = def.radius,
		state = "spawning",
		stateTime = 0,
		attackCooldown = 0.5,
		rangedCooldown = 1 + rng:next() * 1.5,
		losTimer = rng:next() * 0.3,
		hasLos = false,
		target = nil,
		burnTime = 0,
		burnDps = 0,
		burnAccum = 0,
		flameCooldown = 0,
		blockedBy = nil,
		attackTarget = nil,
		chargeDirX = 0,
		chargeDirZ = 0,
		hitDuringCharge = false,
		bossCooldown = 3,
		summonCooldown = 8,
		enraged = false,
		dying = false,
		deathT = 0,
		checkX = x,
		checkZ = z,
		checkTimer = 2,
		stuckTime = 0,
		lastAttacker = nil,
	}
	table.insert(self.list, zombie)
	self.byId[id] = zombie
	self.aliveCount += 1
	self.W.remotes.ZombieSpawn:FireAllClients(id, ztype, x, z)
	return zombie
end

function ZombieSim.setState(z, state: string)
	z.state = state
	z.stateTime = 0
end

local setState = ZombieSim.setState

-- Marks a zombie dead (Combat decides rewards); it is removed after the topple.
function ZombieSim.markDying(self, z, dirX: number, dirZ: number)
	if z.dying then
		return
	end
	z.dying = true
	z.deathT = 0
	z.burnTime = 0
	self.aliveCount -= 1
	local len = math.max(math.sqrt(dirX * dirX + dirZ * dirZ), 1e-3)
	self.W.remotes.ZombieDeath:FireAllClients(z.id, dirX / len, dirZ / len)
end

-- Alive zombies within `radius` of a point (uses the per-step hash).
function ZombieSim.queryRadius(self, x: number, zc: number, radius: number, out: { any }): number
	table.clear(out)
	local ids = self.near
	local n = self.hash:query(x, zc, radius + 1.4, ids)
	local count = 0
	for i = 1, n do
		local z = self.byId[ids[i]]
		if z and not z.dying then
			local dx, dz = z.x - x, z.z - zc
			local rr = radius + z.radius
			if dx * dx + dz * dz <= rr * rr then
				count += 1
				out[count] = z
			end
		end
	end
	return count
end

-- Alive zombies hit by a ray, sorted by distance: { { z, t } }.
function ZombieSim.raycast(self, ox: number, oz: number, dx: number, dz: number, maxDist: number)
	local hits = {}
	for _, z in self.list do
		if not z.dying and not (z.state == "spawning" and z.stateTime < 0.25) then
			local px, pz = z.x - ox, z.z - oz
			local proj = px * dx + pz * dz
			if proj >= -z.radius and proj <= maxDist + z.radius then
				local t = MathUtil.rayCircle(ox, oz, dx, dz, z.x, z.z, z.radius + 0.08)
				if t >= 0 and t <= maxDist then
					table.insert(hits, { z = z, t = t })
				end
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.t < b.t
	end)
	return hits
end

function ZombieSim.rebuildHash(self)
	self.hash:clear()
	for _, z in self.list do
		if not z.dying then
			self.hash:insert(z.id, z.x, z.z)
		end
	end
end

--------------------------------------------------------------------- AI

local out = { x = 0, z = 0, face = nil :: number? }

local function nearestTarget(W, z)
	local best, bestD = nil, math.huge
	for _, ps in W.targets do
		local d = (ps.x - z.x) ^ 2 + (ps.z - z.z) ^ 2
		if d < bestD then
			bestD = d
			best = ps
		end
	end
	return best
end

-- Updates z.dirX/dirZ toward the target; returns straight-line distance.
local function steer(W, z, dt: number): number
	local t = z.target
	if not t then
		return math.huge
	end
	local dx, dz = t.x - z.x, t.z - z.z
	local dist = math.max(math.sqrt(dx * dx + dz * dz), 1e-4)
	z.losTimer -= dt
	if z.losTimer <= 0 then
		z.losTimer = 0.2 + (z.id % 7) * 0.02
		z.hasLos = dist < 16 and W.nav:lineOfSight(z.x, z.z, t.x, t.z, false)
	end
	local wx, wz
	if z.hasLos or dist < 1.6 then
		wx, wz = dx / dist, dz / dist
	else
		local fx, fz = W.flow:sample(z.x, z.z)
		if fx then
			wx, wz = fx, fz
		else
			wx, wz = dx / dist, dz / dist
		end
	end
	z.dirX = damp(z.dirX, wx, 10, dt)
	z.dirZ = damp(z.dirZ, wz, 10, dt)
	local len = math.max(math.sqrt(z.dirX * z.dirX + z.dirZ * z.dirZ), 1e-6)
	z.dirX /= len
	z.dirZ /= len
	return dist
end

local function faceTarget(z): number
	local t = z.target
	if not t then
		return z.facing
	end
	return math.atan2(t.x - z.x, t.z - z.z)
end

-- Clock for this update (slows from "Chilling" gear, stuns from the Shock Beacon).
local clockNow = 0

local function move(z, factor: number)
	local slow = if z.slowUntil and z.slowUntil > clockNow then 0.6 else 1
	out.x = z.dirX * z.speed * factor * slow
	out.z = z.dirZ * z.speed * factor * slow
end

local function tryMelee(_W, z, edge: number): boolean
	if z.attackCooldown > 0 then
		return false
	end
	if z.blockedBy then
		z.attackTarget = z.blockedBy
		setState(z, "windup")
		return true
	end
	if z.target and edge < z.def.reach then
		z.attackTarget = z.target
		setState(z, "windup")
		return true
	end
	return false
end

local function meleeStates(W, z, edge: number): boolean
	if z.state == "windup" then
		move(z, 0.12)
		if z.attackTarget == z.target then
			out.face = faceTarget(z)
		end
		if z.stateTime >= z.def.windup then
			local target = z.attackTarget
			if target and target == z.target then
				local angle = faceTarget(z)
				local diff = math.abs(MathUtil.wrapAngle(angle - z.facing))
				if edge < z.def.reach + 0.5 and diff < 1.3 then
					W.combat:zombieMeleePlayer(z, target)
				end
			elseif target then
				W.combat:zombieMeleeStructure(z, target)
			end
			z.attackTarget = nil
			z.attackCooldown = z.def.attackCooldown
			setState(z, "recover")
		end
		return true
	elseif z.state == "recover" then
		move(z, 0.35)
		if z.stateTime > 0.35 then
			setState(z, "chase")
		end
		return true
	end
	return false
end

local function updateWalker(W, z, edge)
	if meleeStates(W, z, edge) then
		return
	end
	if z.state == "chase" and tryMelee(W, z, edge) then
		return
	end
	move(z, 1)
end

local function updateSpitter(W, z, dist, edge)
	if meleeStates(W, z, edge) then
		return
	end
	local t = z.target
	if z.state == "ranged" then
		out.face = faceTarget(z)
		if z.stateTime >= z.def.windup and t then
			local flight = dist / SPITTER.projectileSpeed
			W.hazards:spitAcid(z.x, z.z, t.x + t.vx * flight * 0.6, t.z + t.vz * flight * 0.6, z.damage)
			z.rangedCooldown = z.def.attackCooldown * (0.8 + W.rng:next() * 0.4)
			setState(z, "recover")
		end
		return
	end
	if z.state ~= "chase" then
		move(z, 1)
		return
	end
	if tryMelee(W, z, edge) then
		return
	end
	local canSpit = t ~= nil and z.hasLos
	if canSpit and dist <= SPITTER.preferredMax and z.rangedCooldown <= 0 then
		setState(z, "ranged")
		W.fx("spit", { id = z.id })
		return
	end
	if canSpit and dist < SPITTER.preferredMin then
		move(z, -0.75)
		out.face = faceTarget(z)
	elseif canSpit and dist <= SPITTER.preferredMax then
		local side = if z.id % 2 == 0 then 1 else -1
		out.x = -z.dirZ * side * z.speed * 0.55
		out.z = z.dirX * side * z.speed * 0.55
		out.face = faceTarget(z)
	else
		move(z, 1)
	end
end

local function updateExploder(W, z, edge)
	if z.state == "fuse" then
		move(z, 0.55)
		if z.stateTime >= z.def.windup then
			W.combat:detonate(z)
		end
		return
	end
	if z.state ~= "chase" then
		move(z, 1)
		return
	end
	if (z.target and edge < 1.5) or z.blockedBy then
		setState(z, "fuse")
		W.fx("fuse", { id = z.id })
		return
	end
	move(z, 1)
end

local function updateBoss(W, z, dt, dist, edge)
	local t = z.target
	z.bossCooldown -= dt
	z.summonCooldown -= dt
	if not z.enraged and z.hp < z.maxHp * BOSS.enrageThreshold then
		z.enraged = true
		z.speed *= 1.2
		W.combat:bossEnrage(z)
	end
	local rate = if z.enraged then 1.35 else 1
	local s = z.state
	if s == "chargeTelegraph" then
		out.face = math.atan2(z.chargeDirX, z.chargeDirZ)
		if t and z.stateTime < BOSS.chargeTelegraph * 0.7 / rate then
			local dx, dz = t.x - z.x, t.z - z.z
			local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
			z.chargeDirX, z.chargeDirZ = dx / len, dz / len
		end
		if z.stateTime >= BOSS.chargeTelegraph / rate then
			z.hitDuringCharge = false
			setState(z, "charging")
			W.fx("roar", { x = z.x, z = z.z })
		end
		return
	elseif s == "charging" then
		out.x = z.chargeDirX * BOSS.chargeSpeed * rate
		out.z = z.chargeDirZ * BOSS.chargeSpeed * rate
		out.face = math.atan2(z.chargeDirX, z.chargeDirZ)
		if not z.hitDuringCharge then
			for _, ps in W.targets do
				local d = math.sqrt((ps.x - z.x) ^ 2 + (ps.z - z.z) ^ 2) - z.radius - Constants.PLAYER_RADIUS
				if d < 0.6 then
					z.hitDuringCharge = true
					W.combat:bossChargeHit(z, ps)
				end
			end
		end
		if z.stateTime >= BOSS.chargeDuration then
			z.bossCooldown = 2.6 / rate
			setState(z, "recover")
		end
		return
	elseif s == "stunned" then
		if z.stateTime >= 1.3 then
			z.bossCooldown = 1.2
			setState(z, "chase")
		end
		return
	elseif s == "slamTelegraph" then
		out.face = faceTarget(z)
		if z.stateTime >= BOSS.slamTelegraph / rate then
			W.combat:bossSlam(z)
			z.bossCooldown = 2.8 / rate
			setState(z, "recover")
		end
		return
	elseif s == "summon" then
		out.face = faceTarget(z)
		if z.stateTime >= 1.0 then
			W.combat:bossSummon(z)
			z.summonCooldown = 14
			z.bossCooldown = 2.2 / rate
			setState(z, "recover")
		end
		return
	end

	if meleeStates(W, z, edge) then
		return
	end
	if z.state ~= "chase" then
		move(z, 1)
		return
	end
	if tryMelee(W, z, edge) then
		return
	end
	move(z, 1)
	if z.bossCooldown > 0 or not t then
		return
	end
	local roll = W.rng:next()
	if z.summonCooldown <= 0 and roll < 0.3 then
		setState(z, "summon")
		W.fx("roar", { x = z.x, z = z.z })
	elseif dist < 8.5 then
		setState(z, "slamTelegraph")
		W.fx("telegraph", { id = z.id, shape = "circle", radius = 3.2, duration = BOSS.slamTelegraph / rate })
	elseif z.hasLos then
		local dx, dz = t.x - z.x, t.z - z.z
		local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
		z.chargeDirX, z.chargeDirZ = dx / len, dz / len
		setState(z, "chargeTelegraph")
		W.fx("telegraph", {
			id = z.id,
			shape = "line",
			length = 20,
			width = z.radius * 2,
			duration = BOSS.chargeTelegraph / rate,
		})
	else
		z.bossCooldown = 0.5
	end
end

local function think(W, z, dt: number)
	out.x, out.z, out.face = 0, 0, nil
	z.target = nearestTarget(W, z)
	local dist = steer(W, z, dt)
	if z.state == "spawning" then
		move(z, 0.6)
		return
	end
	if z.state == "stunned" and z.type ~= "boss" then
		if z.stateTime > (z.stunTime or 0.6) then
			z.stunTime = nil
			setState(z, "chase")
		end
		return
	end
	local edge = dist - z.radius - Constants.PLAYER_RADIUS
	local ztype: string = z.type
	if not z.target then
		-- No one to hunt: keep walking, and claw at structures in the way.
		if ztype == "exploder" then
			updateExploder(W, z, edge)
		else
			updateWalker(W, z, edge)
		end
		return
	end
	if ztype == "spitter" then
		updateSpitter(W, z, dist, edge)
	elseif ztype == "exploder" then
		updateExploder(W, z, edge)
	elseif ztype == "boss" then
		updateBoss(W, z, dt, dist, edge)
	else
		updateWalker(W, z, edge)
	end
end

------------------------------------------------------------------ update

function ZombieSim.relocate(self, z)
	local best, bestD = nil, math.huge
	for _, sp in self.W.spawns do
		local d = if z.x == z.x then (sp.x - z.x) ^ 2 + (sp.z - z.z) ^ 2 else 0
		if d < bestD then
			bestD = d
			best = sp
		end
	end
	if not best then
		return
	end
	z.x, z.z = best.x, best.z
	z.vx, z.vz, z.kx, z.kz = 0, 0, 0, 0
	z.checkX, z.checkZ = z.x, z.z
	z.stuckTime = 0
	setState(z, "spawning")
end

-- Guarantees waves can always end: zombies that stop making progress return to an alley.
function ZombieSim.watchdog(self, z, dt: number)
	if z.x ~= z.x or z.z ~= z.z then -- NaN guard
		self:relocate(z)
		return
	end
	z.checkTimer -= dt
	if z.checkTimer > 0 then
		return
	end
	z.checkTimer = 2
	local moved = math.sqrt((z.x - z.checkX) ^ 2 + (z.z - z.checkZ) ^ 2)
	local t = z.target
	local far = t == nil or math.sqrt((t.x - z.x) ^ 2 + (t.z - z.z) ^ 2) > z.radius + 3
	local idle = z.state == "chase" or z.state == "spawning"
	if idle and far and moved < 0.4 and not z.blockedBy and t ~= nil then
		z.stuckTime += 2
	else
		z.stuckTime = 0
	end
	z.checkX, z.checkZ = z.x, z.z
	if z.stuckTime >= STUCK_LIMIT then
		self:relocate(z)
	end
end

function ZombieSim.update(self, dt: number)
	local W = self.W
	clockNow = os.clock()
	self:rebuildHash()
	local ids = self.near
	local removals = {}

	for i = #self.list, 1, -1 do
		local z = self.list[i]
		z.stateTime += dt
		if z.dying then
			z.deathT += dt
			z.kx = damp(z.kx, 0, 5, dt)
			z.kz = damp(z.kz, 0, 5, dt)
			if z.deathT >= TOPPLE_TIME + 1.2 then
				table.insert(removals, i)
			end
			continue
		end
		if z.state == "spawning" and z.stateTime >= SPAWN_TIME then
			setState(z, "chase")
		end
		if z.burnTime > 0 then
			z.burnTime -= dt
			W.combat:applyBurn(z, dt)
			if z.dying then
				continue
			end
		end
		if z.bleedTime and z.bleedTime > 0 then
			W.combat:applyBleed(z, dt)
			if z.dying then
				continue
			end
		end
		z.flameCooldown = math.max(0, z.flameCooldown - dt)
		z.attackCooldown -= dt
		z.rangedCooldown -= dt

		think(W, z, dt)
		if z.dying then
			continue
		end

		-- Crowd separation (heavier zombies shove lighter ones).
		local sepX, sepZ = 0, 0
		local n = self.hash:query(z.x, z.z, z.radius + 1.4, ids)
		for k = 1, n do
			local other = self.byId[ids[k]]
			if other and other ~= z and not other.dying then
				local dx, dz = z.x - other.x, z.z - other.z
				local minD = z.radius + other.radius
				local d2 = dx * dx + dz * dz
				if d2 < minD * minD and d2 > 1e-8 then
					local d = math.sqrt(d2)
					local overlap = (minD - d) / minD
					local massRatio = other.def.mass / (z.def.mass + other.def.mass)
					sepX += dx / d * overlap * 12 * massRatio
					sepZ += dz / d * overlap * 12 * massRatio
				end
			end
		end
		-- Zombies never walk through players.
		for _, ps in W.targets do
			local dx, dz = z.x - ps.x, z.z - ps.z
			local minD = z.radius + Constants.PLAYER_RADIUS
			local d2 = dx * dx + dz * dz
			if d2 < minD * minD and d2 > 1e-8 then
				local d = math.sqrt(d2)
				sepX += dx / d * (minD - d) * 10
				sepZ += dz / d * (minD - d) * 10
			end
		end

		local accel = if z.state == "charging" then 30 else 9
		z.vx = damp(z.vx, out.x, accel, dt)
		z.vz = damp(z.vz, out.z, accel, dt)
		z.kx = damp(z.kx, 0, 7, dt)
		z.kz = damp(z.kz, 0, 7, dt)
		local nx = z.x + (z.vx + z.kx + sepX) * dt
		local nz = z.z + (z.vz + z.kz + sepZ) * dt
		local rx, rz, touched = W.collision:resolveCircle(nx, nz, z.radius)
		z.x, z.z = rx, rz
		z.blockedBy = if touched and W.structures:isStructureCollider(touched) then touched.owner else nil
		if touched and z.state == "charging" then
			W.combat:bossChargeImpact(z, touched)
		end

		local moveSpeed = math.sqrt(z.vx * z.vx + z.vz * z.vz)
		if out.face ~= nil then
			z.facing = angleDamp(z.facing, out.face, 10, dt)
		elseif moveSpeed > 0.2 then
			z.facing = angleDamp(z.facing, math.atan2(z.vx, z.vz), 8, dt)
		end
		self:watchdog(z, dt)
	end

	table.sort(removals, function(a, b)
		return a > b
	end)
	for _, i in removals do
		local z = self.list[i]
		self.list[i] = self.list[#self.list]
		self.list[#self.list] = nil
		self.byId[z.id] = nil
		table.insert(self.free, z.id)
	end
	self:rebuildHash()

	self.snapshotTimer -= dt
	if self.snapshotTimer <= 0 then
		self.snapshotTimer = 1 / Constants.SNAPSHOT_HZ
		self:sendSnapshot()
	end
end

-- Broadcasts positions/states of every zombie in unreliable packets.
function ZombieSim.sendSnapshot(self)
	local records = self.records
	table.clear(records)
	for _, z in self.list do
		if not z.dying then
			local flags = 0
			if z.burnTime > 0 then
				flags += Net.FLAG_BURNING
			end
			if z.enraged then
				flags += Net.FLAG_ENRAGED
			end
			if z.elite then
				flags += Net.FLAG_ELITE
			end
			flags += ZombiesConfig.code[z.type] * Net.TYPE_SHIFT
			table.insert(records, {
				id = z.id,
				x = z.x,
				z = z.z,
				facing = z.facing,
				state = Net.STATE_CODE[z.state] or 2,
				hp = z.hp / z.maxHp,
				flags = flags,
			})
		end
	end
	if #records == 0 then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local first = 1
	while first <= #records do
		local count = math.min(Net.MAX_PER_PACKET, #records - first + 1)
		self.W.remotes.Snapshot:FireAllClients(Net.pack(records, first, count, now))
		first += count
	end
end

return ZombieSim
