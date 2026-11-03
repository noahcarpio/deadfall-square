--[[
	Enemy hazards: spitter acid globs (and the damaging puddles they leave) and
	the boss's expanding shockwave rings. Visuals are sent to clients as Fx
	events with timings; damage is resolved here.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ZombiesConfig = require(Shared.Config.Zombies)

local SPITTER = ZombiesConfig.spitter
local BOSS = ZombiesConfig.boss

local Hazards = {}
Hazards.__index = Hazards

function Hazards.new(W)
	return setmetatable({ W = W, blobs = {}, puddles = {}, waves = {} }, Hazards)
end

function Hazards.clear(self)
	table.clear(self.blobs)
	table.clear(self.puddles)
	table.clear(self.waves)
end

function Hazards.spitAcid(self, x0: number, z0: number, x1: number, z1: number, damage: number)
	if #self.blobs >= 48 then
		return
	end
	local dist = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local duration = math.max(0.35, dist / SPITTER.projectileSpeed)
	table.insert(self.blobs, { x1 = x1, z1 = z1, t = 0, duration = duration, damage = damage })
	self.W.fx("acid", { x0 = x0, z0 = z0, x1 = x1, z1 = z1, duration = duration })
end

function Hazards.shockwave(self, x: number, z: number, damage: number, delay: number)
	table.insert(self.waves, { x = x, z = z, radius = 0.5, delay = delay, damage = damage, hit = {} })
	self.W.fx("shockwave", { x = x, z = z, delay = delay, speed = BOSS.slamRingSpeed, maxRadius = BOSS.slamRingMaxRadius })
end

function Hazards.update(self, dt: number)
	local W = self.W
	local players = W.players:list()

	for i = #self.blobs, 1, -1 do
		local b = self.blobs[i]
		b.t += dt
		if b.t >= b.duration then
			table.remove(self.blobs, i)
			for _, ps in players do
				if math.sqrt((ps.x - b.x1) ^ 2 + (ps.z - b.z1) ^ 2) < SPITTER.splashRadius + 0.45 then
					W.players:damage(ps, b.damage, b.x1, b.z1, 0, "acid")
				end
			end
			table.insert(self.puddles, {
				x = b.x1,
				z = b.z1,
				r = SPITTER.puddleRadius,
				time = SPITTER.puddleDuration,
				dps = SPITTER.puddleDps * (b.damage / 9),
			})
		end
	end

	for i = #self.puddles, 1, -1 do
		local p = self.puddles[i]
		p.time -= dt
		if p.time <= 0 then
			table.remove(self.puddles, i)
		else
			for _, ps in players do
				if math.sqrt((ps.x - p.x) ^ 2 + (ps.z - p.z) ^ 2) < p.r and os.clock() >= ps.invulnUntil then
					W.players:damage(ps, p.dps * dt, p.x, p.z, 0, "acid")
				end
			end
		end
	end

	for i = #self.waves, 1, -1 do
		local w = self.waves[i]
		if w.delay > 0 then
			w.delay -= dt
		else
			w.radius += BOSS.slamRingSpeed * dt
			if w.radius >= BOSS.slamRingMaxRadius then
				table.remove(self.waves, i)
			else
				for _, ps in players do
					if not w.hit[ps] then
						local d = math.sqrt((ps.x - w.x) ^ 2 + (ps.z - w.z) ^ 2)
						if math.abs(d - w.radius) < BOSS.slamRingWidth * 0.5 + 0.45 then
							w.hit[ps] = true
							-- Rolling through the ring (i-frames) avoids it entirely.
							W.players:damage(ps, w.damage, w.x, w.z, 9, "shockwave")
						end
					end
				end
			end
		end
	end
end

return Hazards
