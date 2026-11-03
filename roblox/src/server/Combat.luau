--[[
	Central damage rules: zombie damage and death (perks, rewards, drops),
	player damage (via PlayerService), queued explosions so chain reactions
	resolve safely, and the boss's special attacks.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ZombiesConfig = require(Shared.Config.Zombies)
local Stealth = require(Shared.Config.Stealth)

local EXPLODER = ZombiesConfig.exploder
local BRUTE = ZombiesConfig.brute
local BOSS = ZombiesConfig.boss
local MAX_EXPLOSIONS_PER_STEP = 24

local Combat = {}
Combat.__index = Combat

function Combat.new(W)
	return setmetatable({ W = W, pending = {}, hits = {}, near = {} }, Combat)
end

function Combat.reset(self)
	table.clear(self.pending)
	table.clear(self.hits)
end

--[[
	opts = { dirX, dirZ, knock, source, crit, attacker (PState?), allowIncendiary }
	Returns true if the zombie died.
]]
function Combat.damageZombie(self, z, amount: number, opts): boolean
	if z.dying or amount <= 0 then
		return false
	end
	local W = self.W
	local attacker = opts.attacker
	if attacker and (z.type == "brute" or z.type == "boss") then
		amount *= 1 + 0.35 * attacker.perks:level("bigGame")
	end
	local dealt = math.min(amount, z.hp)
	z.hp -= amount
	z.kx += opts.dirX * opts.knock / z.def.mass
	z.kz += opts.dirZ * opts.knock / z.def.mass
	z.lastAttacker = attacker
	W.zombies.alert(z)
	if attacker then
		attacker.damageDealt += dealt
		if attacker.perks:has("vampire") and not attacker.downed then
			W.players:heal(attacker, dealt * 0.03 * attacker.perks:level("vampire"))
		end
		if
			opts.allowIncendiary
			and attacker.perks:has("incendiary")
			and W.rng:chance(0.25 * attacker.perks:level("incendiary"))
		then
			self:ignite(z, 9, 2.5)
		end
	end
	table.insert(self.hits, { z.id, math.floor(amount + 0.5), opts.crit == true })
	if z.hp <= 0 then
		self:killZombie(z, opts.source, opts.dirX, opts.dirZ, attacker)
		return true
	end
	return false
end

function Combat.ignite(_self, z, dps: number, duration: number)
	if z.dying then
		return
	end
	z.burnDps = math.max(if z.burnTime > 0 then z.burnDps else 0, dps)
	z.burnTime = math.max(z.burnTime, duration)
end

function Combat.applyBurn(self, z, dt: number)
	z.burnAccum += z.burnDps * dt
	if z.burnAccum >= 4 or (z.burnTime <= 0 and z.burnAccum > 0) then
		local amount = z.burnAccum
		z.burnAccum = 0
		self:damageZombie(
			z,
			amount,
			{ dirX = 0, dirZ = 0, knock = 0, source = "burn", crit = false, attacker = z.lastAttacker }
		)
	end
end

function Combat.killZombie(self, z, source: string, dirX: number, dirZ: number, attacker)
	if z.dying then
		return
	end
	local W = self.W
	if dirX == 0 and dirZ == 0 and attacker then
		dirX, dirZ = z.x - attacker.x, z.z - attacker.z
	end
	W.zombies:markDying(z, dirX, dirZ)
	z.kx += dirX * 3
	z.kz += dirZ * 3
	W.waves:onZombieKilled(z)

	if attacker then
		local _, coins = attacker.economy:registerKill(z.def.score * (1 + W.waves.wave * 0.05), z.def.coins)
		attacker.kills[z.type] += 1
		W.remotes.Notify:FireClient(attacker.player, `+{coins}`, "coin", z.x, z.z)
		if attacker.perks:has("adrenaline") and not attacker.downed then
			W.remotes.Adrenaline:FireClient(attacker.player)
		end
	end
	if z.type ~= "boss" then
		W.pickups:rollDrop(z, attacker)
	end

	if z.type == "exploder" then
		self:queueExplosion(
			z.x,
			z.z,
			EXPLODER.blastRadius,
			EXPLODER.zombieDamage,
			z.damage,
			EXPLODER.structureDamage,
			"exploder",
			attacker
		)
	elseif
		attacker
		and source ~= "perkBlast"
		and attacker.perks:has("explosiveKills")
		and W.rng:chance(0.2 * attacker.perks:level("explosiveKills"))
	then
		self:queueExplosion(z.x, z.z, 2.6, 45 * (1 + W.waves.wave * 0.05), 0, 0, "perkBlast", attacker)
	end

	if z.type == "boss" then
		-- Every player shares the boss reward.
		for _, ps in W.players:list() do
			if ps ~= attacker then
				ps.economy:addCoins(z.def.coins)
			end
		end
		W.fx("explosion", { x = z.x, z = z.z, radius = 5 })
		for i = 0, 5 do
			local a = i / 6 * math.pi * 2
			W.pickups:spawn(
				if i == 0 then "weapon" elseif i % 2 == 1 then "health" else "ammo",
				z.x + math.cos(a) * 2,
				z.z + math.sin(a) * 2
			)
		end
		W.waves.boss = nil
		W.notifyAll("BOSS DEFEATED", "good")
	end
end

-- Exploder fuse ran out: it blows itself up.
function Combat.detonate(self, z)
	self:killZombie(z, "self", 0, 0, nil)
end

-------------------------------------------------------------- players

function Combat.zombieMeleePlayer(self, z, ps)
	local knock = if z.type == "brute" then BRUTE.knockback elseif z.type == "boss" then 12 else 2.5
	self.W.players:damage(ps, z.damage, z.x, z.z, knock, z.type)
	if z.type == "brute" then
		self.W.fx("slam", { x = z.x + math.sin(z.facing) * 1.2, z = z.z + math.cos(z.facing) * 1.2, small = true })
	end
end

function Combat.zombieMeleeStructure(self, z, structure)
	self.W.structures:damage(structure, z.damage * (if z.type == "brute" then 3 else 1.6))
end

----------------------------------------------------------- explosions

function Combat.queueExplosion(self, x, z, radius, zombieDamage, playerDamage, structureDamage, source, attacker)
	table.insert(self.pending, {
		x = x,
		z = z,
		radius = radius,
		zombieDamage = zombieDamage,
		playerDamage = playerDamage,
		structureDamage = structureDamage,
		source = source,
		attacker = attacker,
	})
end

function Combat.processExplosions(self)
	local processed = 0
	while #self.pending > 0 and processed < MAX_EXPLOSIONS_PER_STEP do
		local e = table.remove(self.pending, 1)
		self:explosion(e.x, e.z, e.radius, e.zombieDamage, e.playerDamage, e.structureDamage, e.source, e.attacker)
		processed += 1
	end
end

-- Immediate explosion. Returns the number of zombies damaged.
function Combat.explosion(self, x, zc, radius, zombieDamage, playerDamage, structureDamage, source, attacker): number
	local W = self.W
	local victims = {}
	local n = W.zombies:queryRadius(x, zc, radius, self.near)
	for i = 1, n do
		victims[i] = self.near[i]
	end
	local hits = 0
	for _, v in victims do
		if not v.dying then
			local dx, dz = v.x - x, v.z - zc
			local d = math.sqrt(dx * dx + dz * dz)
			local k = 1 - math.min(1, d / (radius + v.radius)) * 0.6
			local len = math.max(d, 1e-3)
			self:damageZombie(v, zombieDamage * k, {
				dirX = dx / len,
				dirZ = dz / len,
				knock = 10 * k,
				source = source,
				crit = false,
				attacker = attacker,
			})
			hits += 1
		end
	end
	if playerDamage > 0 then
		for _, ps in W.players:list() do
			local d = math.sqrt((ps.x - x) ^ 2 + (ps.z - zc) ^ 2)
			if d < radius + 0.45 then
				local k = 1 - math.min(1, d / (radius + 0.45)) * 0.5
				W.players:damage(ps, playerDamage * k, x, zc, 10 * k, source)
			end
		end
	end
	if structureDamage > 0 then
		W.structures:damageInRadius(x, zc, radius, structureDamage)
	end
	W.fx("explosion", { x = x, z = zc, radius = radius })
	W.noise(x, zc, Stealth.NOISE.explosion)
	return hits
end

------------------------------------------------------------------ boss

function Combat.bossChargeHit(self, z, ps)
	self.W.players:damage(ps, z.damage * 1.15, z.x, z.z, 18, "boss")
end

function Combat.bossChargeImpact(self, z, collider)
	local W = self.W
	if z.stateTime < 0.12 then
		return
	end
	if W.structures:isStructureCollider(collider) then
		W.structures:damage(collider.owner, 400)
		return
	end
	z.state = "stunned"
	z.stateTime = 0
	z.vx, z.vz = 0, 0
	W.fx("slam", { x = z.x + z.chargeDirX * 1.5, z = z.z + z.chargeDirZ * 1.5 })
	W.notifyAll("Boss stunned!", "info")
end

function Combat.bossSlam(self, z)
	local W = self.W
	local scale = z.damage / ZombiesConfig.defs.boss.damage
	W.hazards:shockwave(z.x, z.z, BOSS.slamDamage * scale, 0)
	if z.enraged then
		W.hazards:shockwave(z.x, z.z, BOSS.slamDamage * scale, 0.45)
	end
	for _, ps in W.players:list() do
		if math.sqrt((ps.x - z.x) ^ 2 + (ps.z - z.z) ^ 2) < 3.4 then
			W.players:damage(ps, z.damage, z.x, z.z, 14, "boss")
		end
	end
	W.structures:damageInRadius(z.x, z.z, 4, 200)
	W.fx("slam", { x = z.x, z = z.z })
end

function Combat.bossSummon(self, z)
	local W = self.W
	local count = BOSS.summonCount + (if z.enraged then 2 else 0)
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local x, zz = z.x + math.cos(a) * 2.6, z.z + math.sin(a) * 2.6
		if not W.collision:overlapsCircle(x, zz, 0.4) then
			W.waves:spawnExtra("runner", x, zz)
		end
	end
	W.fx("slam", { x = z.x, z = z.z, small = true })
end

function Combat.bossEnrage(self, z)
	self.W.fx("roar", { x = z.x, z = z.z, enrage = true })
	self.W.notifyAll("THE ABOMINATION IS ENRAGED", "boss")
end

-- Sends batched hit numbers to clients once per tick.
function Combat.flushHits(self)
	if #self.hits > 0 then
		self.W.remotes.ZombieHits:FireAllClients(self.hits)
		self.hits = {}
	end
end

return Combat
