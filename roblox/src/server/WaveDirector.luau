--[[
	Runs waves: builds the composition (scaled by player count), spawns groups
	from alleys away from players under a concurrency cap, spawns the boss every
	fifth wave and reports when a wave is cleared.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
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
	self.wave = 0
	self.active = false
	self.elapsed = 0
	self.queue = {}
	self.total = 0
	self.killed = 0
	self.boss = nil
	self.bossPending = false
	self.spawnTimer = 0
	self.players = 1
end

function WaveDirector.scaling(self)
	local w = math.max(1, self.wave)
	return { hp = Waves.hpMultiplier(w), damage = Waves.damageMultiplier(w), speed = Waves.speedMultiplier(w) }
end

function WaveDirector.remaining(self): number
	return #self.queue + self.W.zombies.aliveCount + (if self.bossPending then 1 else 0)
end

function WaveDirector.start(self, players: number)
	local W = self.W
	self.wave += 1
	self.players = math.max(1, players)
	self.active = true
	self.elapsed = 0
	self.queue = WaveComposition.build(self.wave, W.rng, self.players)
	self.bossPending = Waves.isBossWave(self.wave)
	self.total = #self.queue + (if self.bossPending then 1 else 0)
	self.killed = 0
	self.spawnTimer = 0.5
end

function WaveDirector.onZombieKilled(self, z)
	if self.active then
		self.killed += 1
	end
	if z == self.boss then
		self.boss = nil
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

-- Returns true on the step the wave is cleared.
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
			boss.hp = boss.maxHp
			self.boss = boss
			W.fx("roar", { x = boss.x, z = boss.z })
			W.notifyAll("The Abomination has arrived!", "boss")
		end
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
				W.zombies:spawn(ztype, sp.x - sp.dirZ * side - sp.dirX * back, sp.z + sp.dirX * side - sp.dirZ * back, scaling)
			end
		end
	end
	if #self.queue == 0 and not self.bossPending and W.zombies.aliveCount == 0 then
		self.active = false
		return true
	end
	return false
end

return WaveDirector
