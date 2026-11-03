--[[
	Server-authoritative weapons. Clients send trigger pulls with the pellet
	directions they predicted; the server checks ownership, fire rate and ammo,
	sanity-checks the spread, then resolves hits itself (2D ray casts against
	zombie circles and bullet-blocking obstacles). Also runs flamethrower
	particles, grenades and turret shots.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Weapons = require(Shared.Config.Weapons)
local MathUtil = require(Shared.Util.MathUtil)

local MAX_FLAMES = 300

local WeaponService = {}
WeaponService.__index = WeaponService

function WeaponService.new(W)
	return setmetatable({ W = W, flames = {}, grenades = {}, near = {} }, WeaponService)
end

function WeaponService.clear(self)
	table.clear(self.flames)
	table.clear(self.grenades)
end

local function fireToOthers(remote: RemoteEvent, except: Player?, ...)
	for _, p in Players:GetPlayers() do
		if p ~= except then
			remote:FireClient(p, ...)
		end
	end
end

--[[
	One hitscan ray. Damages up to pierce+1 zombies in order and stops at the
	first bullet-blocking obstacle. Returns (hitAnything, endX, endZ).
	p = { ox, oz, dirX, dirZ, range, damage, pierce, knock, source, attacker,
	      falloff?, critChance?, allowIncendiary? }
]]
function WeaponService.hitscan(self, p): (boolean, number, number)
	local W = self.W
	local wallT = W.collision:raycast(p.ox, p.oz, p.dirX, p.dirZ, p.range, Constants.BULLET_HEIGHT)
	local hits = W.zombies:raycast(p.ox, p.oz, p.dirX, p.dirZ, wallT)
	local remaining = p.pierce + 1
	local damage = p.damage
	local endT = wallT
	local any = false
	for _, h in hits do
		if remaining <= 0 then
			break
		end
		local z = h.z
		if not z.dying then
			local falloff = 1
			if p.falloff and p.falloff < 1 then
				falloff = 1 - (1 - p.falloff) * math.min(1, h.t / p.range)
			end
			local crit = W.rng:next() < (p.critChance or 0)
			W.combat:damageZombie(z, damage * falloff * (if crit then 2 else 1), {
				dirX = p.dirX,
				dirZ = p.dirZ,
				knock = p.knock,
				source = p.source,
				crit = crit,
				attacker = p.attacker,
				allowIncendiary = p.allowIncendiary,
			})
			any = true
			remaining -= 1
			damage *= 0.8
			if remaining <= 0 then
				endT = h.t
			end
		end
	end
	return any, p.ox + p.dirX * endT, p.oz + p.dirZ * endT
end

local function normalise(x: number, z: number): (number, number)
	local len = math.sqrt(x * x + z * z)
	if len < 1e-6 or len ~= len then
		return 0, 1
	end
	return x / len, z / len
end

-- Validates client pellet directions; rebuilds them server-side if implausible.
function WeaponService.checkDirs(self, def, dirs): { { number } }
	local mx, mz = 0, 0
	local clean = {}
	if type(dirs) == "table" then
		for i = 1, math.min(#dirs, def.pellets) do
			local d = dirs[i]
			if type(d) == "table" and type(d[1]) == "number" and type(d[2]) == "number" then
				local x, z = normalise(d[1], d[2])
				table.insert(clean, { x, z })
				mx += x
				mz += z
			end
		end
	end
	if #clean == 0 then
		return {}
	end
	mx, mz = normalise(mx, mz)
	local aim = math.atan2(mx, mz)
	local limit = def.spread * 2.5 + def.moveSpread + 0.08
	local valid = #clean == def.pellets
	for _, d in clean do
		if math.abs(MathUtil.wrapAngle(math.atan2(d[1], d[2]) - aim)) > limit then
			valid = false
		end
	end
	if valid then
		return clean
	end
	local out = {}
	for i = 1, def.pellets do
		local a = aim + (self.W.rng:next() - 0.5) * def.spread * 1.2
		out[i] = { math.sin(a), math.cos(a) }
	end
	return out
end

function WeaponService.onFire(self, ps, weaponId: any, dirs: any, aimDistance: any)
	local W = self.W
	if ps.downed or not ps.hasBody or type(weaponId) ~= "string" then
		return
	end
	if weaponId ~= ps.arsenal.current then
		W.players:syncArsenal(ps)
		return
	end
	local now = os.clock()
	local result = ps.arsenal:tryFire(now, 0.35, ps.stats.reloadSpeed)
	if result ~= "fired" then
		if result == "empty" then
			W.players:syncArsenal(ps)
		end
		return
	end
	local def = Weapons.defs[weaponId]
	local w = ps.arsenal:currentState()
	local damage = Weapons.damageOf(def, w.upgrades)
	local list = self:checkDirs(def, dirs)
	if #list == 0 then
		return
	end
	local ox, oz = ps.x, ps.z

	if def.kind == "hitscan" then
		local ends = {}
		local pierce = def.pierce + ps.perks:level("piercing")
		for _, d in list do
			ps.shotsFired += 1
			local hit, ex, ez = self:hitscan({
				ox = ox,
				oz = oz,
				dirX = d[1],
				dirZ = d[2],
				range = def.range,
				damage = damage,
				pierce = pierce,
				knock = def.knockback,
				source = def.id,
				attacker = ps,
				falloff = if def.id == "shotgun" then 0.35 else 1,
				critChance = Weapons.CRIT_CHANCE,
				allowIncendiary = true,
			})
			if hit then
				ps.shotsHit += 1
			end
			table.insert(ends, { ex, ez })
		end
		fireToOthers(W.remotes.Shot, ps.player, ps.userId, def.id, ox, oz, ends)
	elseif def.kind == "flame" then
		local speed = def.projectileSpeed or 12
		for _, d in list do
			if #self.flames < MAX_FLAMES then
				local life = def.range / speed
				table.insert(self.flames, {
					x = ox + d[1] * 0.8,
					z = oz + d[2] * 0.8,
					vx = d[1] * speed + ps.vx * 0.5,
					vz = d[2] * speed + ps.vz * 0.5,
					life = life,
					maxLife = life,
					damage = damage,
					attacker = ps,
				})
			end
		end
		fireToOthers(W.remotes.Shot, ps.player, ps.userId, def.id, ox, oz, { { list[1][1], list[1][2] } })
	else
		local d = list[1]
		local dist = math.clamp(if type(aimDistance) == "number" then aimDistance else 10, 4, def.range)
		local x1, z1 = ox + d[1] * dist, oz + d[2] * dist
		local duration = dist / (def.projectileSpeed or 20) + 0.15
		ps.shotsFired += 1
		table.insert(self.grenades, {
			x0 = ox,
			z0 = oz,
			x1 = x1,
			z1 = z1,
			t = 0,
			duration = duration,
			damage = damage,
			radius = def.blastRadius or 4,
			attacker = ps,
		})
		W.fx("grenade", { x0 = ox, z0 = oz, x1 = x1, z1 = z1, duration = duration })
	end
end

function WeaponService.onReload(self, ps)
	if ps.downed then
		return
	end
	if ps.arsenal:startReload(os.clock(), ps.stats.reloadSpeed) then
		self.W.players:syncArsenal(ps)
	end
end

function WeaponService.onSwitch(self, ps, arg: any)
	local now = os.clock()
	local changed = false
	if type(arg) == "string" and Weapons.defs[arg] then
		changed = ps.arsenal:switchTo(arg, now)
	elseif type(arg) == "number" then
		changed = ps.arsenal:cycle(arg, now)
	end
	if changed then
		self.W.players:updateGunModel(ps)
	end
	self.W.players:syncArsenal(ps)
end

function WeaponService.update(self, dt: number)
	local W = self.W
	local now = os.clock()
	for _, ps in W.players:list() do
		if ps.arsenal:finishReload(now) then
			W.players:syncArsenal(ps)
		end
	end

	-- Flames: short-lived particles that damage and ignite what they touch.
	local near = self.near
	for i = #self.flames, 1, -1 do
		local f = self.flames[i]
		f.life -= dt
		f.x += f.vx * dt
		f.z += f.vz * dt
		if f.life <= 0 or W.collision:overlapsCircle(f.x, f.z, 0.15) then
			table.remove(self.flames, i)
		else
			local age = 1 - f.life / f.maxLife
			local n = W.zombies:queryRadius(f.x, f.z, 0.35 + age * 0.9, near)
			for k = 1, n do
				local z = near[k]
				if z.flameCooldown <= 0 then
					z.flameCooldown = 0.1
					W.combat:damageZombie(z, f.damage, {
						dirX = f.vx * 0.05,
						dirZ = f.vz * 0.05,
						knock = 0.4,
						source = "flamer",
						crit = false,
						attacker = f.attacker,
					})
					W.combat:ignite(z, f.damage * 1.4, 2.5)
				end
			end
		end
	end

	-- Grenades: ballistic arc, detonating on landing, obstacles or zombies.
	for i = #self.grenades, 1, -1 do
		local g = self.grenades[i]
		g.t += dt
		local t = math.min(1, g.t / g.duration)
		local x = g.x0 + (g.x1 - g.x0) * t
		local z = g.z0 + (g.z1 - g.z0) * t
		local y = 1.2 * (1 - t) + 0.15 + math.sin(t * math.pi) * math.min(3.5, g.duration * 3)
		local boom = t >= 1
		if not boom and y < 2.2 then
			boom = W.collision:overlapsCircle(x, z, 0.15) or W.zombies:queryRadius(x, z, 0.25, near) > 0
		end
		if boom then
			table.remove(self.grenades, i)
			local hits = W.combat:explosion(x, z, g.radius, g.damage, 0, 40, "launcher", g.attacker)
			if hits > 0 and g.attacker then
				g.attacker.shotsHit += 1
			end
		end
	end
end

return WeaponService
