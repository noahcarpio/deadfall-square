--[[
	Runs the floors of the tower climb. Each floor builds a horde from the
	wave curves (the floor number is the wave), adjusted by its modifier, and
	tracks its objective:

	  clear   - kill everything
	  holdout - survive a timer while the horde keeps coming
	  defend  - protect the alarm bell (it gets health; zombies go for it)
	  elite   - kill the glowing elite; the horde keeps coming until then
	  boss    - the Abomination plus a horde; kill everything

	Groups spawn from alleys away from players under a concurrency cap.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Floors = require(Shared.Config.Floors)
local Waves = require(Shared.Config.Waves)
local WaveComposition = require(Shared.WaveComposition)

local WaveDirector = {}
WaveDirector.__index = WaveDirector

function WaveDirector.new(W)
	local self = setmetatable({ W = W }, WaveDirector)
	self:reset()
	return self
end

function WaveDirector.reset(self)
	self.wave = 0 -- current floor
	self.active = false
	self.elapsed = 0
	self.queue = {}
	self.total = 0
	self.killed = 0
	self.boss = nil
	self.bossPending = false
	self.spawnTimer = 0
	self.players = 1
	self.plan = nil
	self.objective = "clear"
	self.modifier = Floors.modifiers.none
	self.duration = 0
	self.bell = nil -- defend: { x, z, hp, maxHp, isBell }
	self.bellBroken = false
	self.elite = nil
	self.elitePending = false
end

-- The current floor's entry from the climb plan.
function WaveDirector.floorInfo(self, floor: number?)
	local f = floor or self.wave
	return self.plan and self.plan[f]
end

function WaveDirector.scaling(self)
	local w = math.max(1, self.wave)
	local m = self.modifier
	return {
		hp = Waves.hpMultiplier(w) * m.hp,
		damage = Waves.damageMultiplier(w),
		speed = Waves.speedMultiplier(w) * m.speed,
	}
end

-- Zombies left to kill (clear / boss floors) or currently alive (the rest).
function WaveDirector.remaining(self): number
	if self.objective == "holdout" or self.objective == "elite" or self.objective == "defend" then
		return self.W.zombies.aliveCount
	end
	return #self.queue + self.W.zombies.aliveCount + (if self.bossPending then 1 else 0)
end

-- Seconds left on a hold-out floor.
function WaveDirector.timeLeft(self): number
	return if self.objective == "holdout" then math.max(0, self.duration - self.elapsed) else 0
end

-- Applies the floor modifier to a composition.
function WaveDirector.compose(self, players: number): { string }
	local W = self.W
	local queue = WaveComposition.build(self.wave, W.rng, players)
	local m = self.modifier
	if m.brutes > 0 then
		for i, t in queue do
			if t == "walker" and W.rng:chance(m.brutes) then
				queue[i] = "brute"
			end
		end
	end
	if m.count > 1 then
		local extra = math.floor(#queue * (m.count - 1) + 0.5)
		for _ = 1, extra do
			table.insert(queue, if W.rng:chance(0.6) then "walker" else "runner")
		end
		W.rng:shuffle(queue)
	elseif m.count < 1 then
		local keep = math.max(3, math.floor(#queue * m.count + 0.5))
		while #queue > keep do
			table.remove(queue)
		end
	end
	return queue
end

function WaveDirector.start(self, players: number)
	local W = self.W
	self.wave += 1
	self.players = math.max(1, players)
	local info = self:floorInfo()
	self.objective = if info then info.objective else "clear"
	self.modifier = Floors.modifiers[if info then info.modifier else "none"]
	self.active = true
	self.elapsed = 0
	self.queue = self:compose(self.players)
	self.bossPending = self.objective == "boss" or (info == nil and Waves.isBossWave(self.wave))
	self.total = #self.queue + (if self.bossPending then 1 else 0)
	self.killed = 0
	self.spawnTimer = 0.5
	self.duration = if self.objective == "holdout" then Floors.holdoutSeconds(self.wave) else 0
	self.elite = nil
	self.elitePending = self.objective == "elite"
	self.bellBroken = false
	self.bell = nil
	if self.objective == "defend" then
		local hp = Floors.bellHp(self.wave, self.players)
		local bx, bz = W.stations:position("bell")
		self.bell = { x = bx, z = bz - 1.1, vx = 0, vz = 0, hp = hp, maxHp = hp, isBell = true, crouching = false }
		W.zombies:setHome(self.bell.x, self.bell.z)
	else
		W.zombies:setHome(nil, nil)
	end
end

-- Living things zombies hunt: players, plus the bell on a defend floor.
function WaveDirector.extraTargets(self)
	if self.active and self.bell and self.bell.hp > 0 then
		return self.bell
	end
	return nil
end

function WaveDirector.damageBell(self, amount: number)
	local bell = self.bell
	if not bell or bell.hp <= 0 then
		return
	end
	bell.hp = math.max(0, bell.hp - amount)
	self.W.fx("structureHit", { x = bell.x, z = bell.z })
	if bell.hp <= 0 then
		self.bellBroken = true
		self.W.fx("structureBreak", { x = bell.x, z = bell.z })
		self.W.notifyAll("The bell is broken! No reward for this floor.", "bad")
		self.W.zombies:setHome(nil, nil)
	end
end

function WaveDirector.onZombieKilled(self, z)
	if self.active then
		self.killed += 1
	end
	if z == self.boss then
		self.boss = nil
	end
	if z == self.elite then
		self.elite = nil
	end
end

function WaveDirector.spawnExtra(self, ztype: string, x: number, z: number)
	local zombie = self.W.zombies:spawn(ztype, x, z, self:scaling())
	if zombie and self.active then
		self.total += 1
	end
	return zombie
end

-- Picks a spawn alley at least `minDist` from every player when possible.
function WaveDirector.pickSpawn(self, minDist: number)
	local W = self.W
	local far = {}
	for _, sp in W.spawns do
		local ok = true
		for _, ps in W.players:targets() do
			if math.sqrt((sp.x - ps.x) ^ 2 + (sp.z - ps.z) ^ 2) < minDist then
				ok = false
				break
			end
		end
		if ok then
			table.insert(far, sp)
		end
	end
	return W.rng:pick(if #far > 0 then far else W.spawns)
end

-- Ends a timed or elite floor: the rest of the horde collapses.
function WaveDirector.collapse(self)
	local W = self.W
	table.clear(self.queue)
	for _, z in table.clone(W.zombies.list) do
		if not z.dying then
			W.zombies:markDying(z, 0, 0)
		end
	end
end

-- Returns true on the step the floor is completed.
function WaveDirector.update(self, dt: number): boolean
	if not self.active then
		return false
	end
	local W = self.W
	self.elapsed += dt
	if self.bossPending and self.elapsed > 1.5 then
		self.bossPending = false
		local sp = self:pickSpawn(25)
		local boss = W.zombies:spawn("boss", sp.x, sp.z, self:scaling())
		if boss then
			boss.maxHp *= Waves.bossHpMultiplier(self.wave, self.players)
			if self.wave >= Floors.FLOORS then
				boss.maxHp *= 1.5 -- the top of the climb
			end
			boss.hp = boss.maxHp
			self.boss = boss
			W.fx("roar", { x = boss.x, z = boss.z })
			W.notifyAll("The Abomination has arrived!", "boss")
		end
	end
	if self.elitePending and self.elapsed > 2 then
		self.elitePending = false
		local sp = self:pickSpawn(22)
		local ztype = if self.wave >= 6 then "brute" elseif self.wave >= 3 then "runner" else "walker"
		local elite = W.zombies:spawn(ztype, sp.x, sp.z, self:scaling())
		if elite then
			elite.elite = true
			elite.maxHp *= Floors.ELITE.hp * (1 + 0.4 * (self.players - 1))
			elite.hp = elite.maxHp
			elite.damage *= Floors.ELITE.damage
			elite.speed *= Floors.ELITE.speed
			self.elite = elite
			W.notifyAll("An elite has entered the square!", "boss")
		end
	end
	-- Endless floors keep the horde coming.
	local endless = self.objective == "holdout"
		or (self.objective == "elite" and (self.elite or self.elitePending))
		or (self.objective == "defend" and self.elapsed < 70)
	if #self.queue == 0 and endless then
		self.queue = self:compose(self.players)
	end
	if #self.queue > 0 then
		self.spawnTimer -= dt
		if self.spawnTimer <= 0 then
			self.spawnTimer = Waves.spawnInterval(self.wave) / math.sqrt(self.players) * (0.7 + W.rng:next() * 0.6)
			local cap = Waves.maxAlive(self.wave, W.aliveCap) * math.min(2, 1 + 0.25 * (self.players - 1))
			local group = math.min(Waves.spawnGroupSize(self.wave), #self.queue)
			local sp = self:pickSpawn(18)
			local scaling = self:scaling()
			for _ = 1, group do
				if W.zombies.aliveCount >= cap or W.zombies:capacityLeft() == 0 then
					break
				end
				local ztype = table.remove(self.queue) :: string
				local side = (W.rng:next() - 0.5) * 2.4
				local back = W.rng:next() * 2.5
				W.zombies:spawn(
					ztype,
					sp.x - sp.dirZ * side - sp.dirX * back,
					sp.z + sp.dirX * side - sp.dirZ * back,
					scaling
				)
			end
		end
	end

	local done = false
	if self.objective == "holdout" then
		done = self.elapsed >= self.duration
	elseif self.objective == "elite" then
		done = not self.elitePending and self.elite == nil
	else
		-- clear / boss / defend (defend stops spawning after 70 s, then clear the rest)
		done = #self.queue == 0 and not self.bossPending and W.zombies.aliveCount == 0
	end
	if done then
		if self.objective == "holdout" or self.objective == "elite" then
			self:collapse()
		end
		self.active = false
		W.zombies:setHome(nil, nil)
		return true
	end
	return false
end

return WaveDirector
