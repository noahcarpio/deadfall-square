--[[
	Client side of shooting. Predicts fire-rate, ammo and reloads with a local
	copy of the shared Arsenal (corrected by server syncs), generates pellet
	spread, applies light aim assist on touch/gamepad, draws the player's own
	tracers and muzzle flash immediately, and sends each trigger pull to the
	server, which resolves the actual hits.
]]
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Collision = require(Shared.Collision)
local Constants = require(Shared.Config.Constants)
local PlayerStats = require(Shared.PlayerStats)
local Weapons = require(Shared.Config.Weapons)
local MathUtil = require(Shared.Util.MathUtil)

local Context = require(script.Parent.Context)
local Audio = require(script.Parent.Audio)
local Fx = require(script.Parent.Fx)
local InputController = require(script.Parent.InputController)
local ZombieView = require(script.Parent.ZombieView)

local S = Constants.STUDS

local WeaponClient = {}

-- Arena obstacles for local tracer prediction (structures aren't included).
local collision = Collision.new(
	-Constants.WORLD_HALF - 4,
	-Constants.WORLD_HALF - 4,
	Constants.WORLD_HALF + 4,
	Constants.WORLD_HALF + 4
)
for _, c in ArenaLayout.generate().colliders do
	collision:insert(table.clone(c) :: any)
end

-- Approximately normal random in about [-2, 2].
local function gaussian(): number
	return (math.random() + math.random() + math.random() - 1.5) * 1.33
end

local function aimAssist(px: number, pz: number, ax: number, az: number): (number, number, number?)
	local best, bestScore = nil, math.huge
	for _, z in ZombieView.list() do
		local dx, dz = z.x - px, z.z - pz
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 0.01 and d < 18 then
			local cos = (dx * ax + dz * az) / d
			if cos > 0.94 then
				local score = d * (2 - cos)
				if score < bestScore then
					bestScore = score
					best = { dx / d, dz / d, d }
				end
			end
		end
	end
	if best then
		return best[1], best[2], best[3]
	end
	return ax, az, nil
end

-- Local tracer end: first arena obstacle or zombie along the ray.
local function predictEnd(ox: number, oz: number, dx: number, dz: number, range: number): (number, number)
	local t = collision:raycast(ox, oz, dx, dz, range, Constants.BULLET_HEIGHT)
	for _, z in ZombieView.list() do
		local hit = MathUtil.rayCircle(ox, oz, dx, dz, z.x, z.z, 0.5)
		if hit >= 0 and hit < t then
			t = hit
		end
	end
	return ox + dx * t, oz + dz * t
end

function WeaponClient.start()
	local remotes = Context.remotes
	local arsenal = Context.arsenal

	remotes.ArsenalSync.OnClientEvent:Connect(function(data, serverClock: number)
		local localNext = arsenal.nextShot
		arsenal:applySerialized(data)
		arsenal.nextShot = localNext
		if data.reloadEnd > 0 then
			arsenal.reloadEnd = os.clock() + (data.reloadEnd - serverClock)
		end
		Context.signals.arsenalChanged:fire()
	end)

	remotes.StatsSync.OnClientEvent:Connect(function(stats, perks, tiers)
		Context.stats = stats
		Context.perks = perks
		Context.tiers = tiers
		Context.stamina = math.min(Context.stamina, stats.maxStamina)
		Context.signals.statsChanged:fire()
	end)

	InputController.onReload:connect(function()
		if Context.downed() or Context.menuOpen then
			return
		end
		if arsenal:startReload(os.clock(), Context.stats.reloadSpeed) then
			remotes.Reload:FireServer()
			Audio.play("reload")
			Context.signals.arsenalChanged:fire()
		end
	end)

	InputController.onSwitch:connect(function(slot: number?, direction: number?)
		if Context.menuOpen then
			return
		end
		local now = os.clock()
		if slot then
			for _, w in arsenal:list() do
				if Weapons.defs[w.id].slot == slot and arsenal:switchTo(w.id, now) then
					remotes.Switch:FireServer(w.id)
				end
			end
		elseif direction and arsenal:cycle(direction, now) then
			remotes.Switch:FireServer(arsenal.current)
		end
		Context.signals.arsenalChanged:fire()
	end)

	RunService.Heartbeat:Connect(function()
		local character = Context.character()
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local def = Weapons.defs[arsenal.current]
		local speed01 = 0
		if root then
			local v = root.AssemblyLinearVelocity
			local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude
			speed01 = math.min(1, horizontal / (Context.stats.speed * PlayerStats.BASE.sprintMultiplier * S))
		end
		Context.spread = def.spread + def.moveSpread * speed01 + (if Context.sprinting then 0.05 else 0)

		if arsenal.reloadEnd > 0 and arsenal:finishReload(os.clock()) then
			Context.signals.arsenalChanged:fire()
		end
		if not root or not Context.firing or Context.rolling or Context.downed() or Context.phase() == "lobby" then
			return
		end
		local result = arsenal:tryFire(os.clock(), 0, Context.stats.reloadSpeed)
		if result == "empty" then
			local w = arsenal:currentState()
			if w.reserve <= 0 then
				Audio.play("dryFire")
			else
				Audio.play("reload")
			end
			Context.signals.arsenalChanged:fire()
			return
		elseif result ~= "fired" then
			return
		end

		local px, pz = root.Position.X / S, root.Position.Z / S
		local ax, az, dist = Context.aimX, Context.aimZ, Context.aimDistance
		if Context.device ~= "mouse" then
			local assistDist
			ax, az, assistDist = aimAssist(px, pz, ax, az)
			dist = assistDist or dist
		end
		local aim = math.atan2(ax, az)
		local dirs = {}
		local spread = Context.spread
		for i = 1, def.pellets do
			local a
			if def.kind == "flame" then
				a = aim + (math.random() - 0.5) * 2 * spread
			else
				a = aim + gaussian() * spread * (if def.pellets > 1 then 0.6 else 0.5)
			end
			dirs[i] = { math.sin(a), math.cos(a) }
		end
		remotes.Fire:FireServer(def.id, dirs, dist)

		-- Immediate local feedback.
		local gun = character and character:FindFirstChild("Gun")
		local muzzleAtt = gun and gun:FindFirstChild("Muzzle", true) :: Attachment?
		local muzzle = if muzzleAtt then muzzleAtt.WorldPosition else root.Position + Vector3.new(ax, 0, az) * 2.5
		local color = Fx.weaponColor(def.id)
		Context.shake(def.shake)
		if def.kind == "hitscan" then
			Fx.muzzle(muzzle, color, def.id == "shotgun" or def.id == "sniper")
			for _, d in dirs do
				local ex, ez = predictEnd(px, pz, d[1], d[2], def.range)
				Fx.tracer(muzzle.X, muzzle.Y, muzzle.Z, ex, ez, color, if def.id == "sniper" then 0.35 else 0.18)
			end
			Audio.play(def.id)
		elseif def.kind == "flame" then
			Fx.muzzle(muzzle, color, false)
			Fx.flame(muzzle, dirs[1][1], dirs[1][2])
			Audio.play("flamer", nil, nil, 0.5)
		else
			Fx.muzzle(muzzle, color, true)
		end
		Context.signals.arsenalChanged:fire()
	end)
end

return WeaponClient
