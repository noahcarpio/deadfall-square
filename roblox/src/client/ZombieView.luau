--[[
	Renders the server-simulated horde locally. Each zombie is a rig of
	anchored, non-colliding parts posed procedurally every frame (walk cycle,
	attack wind-ups, boss telegraph poses) and moved in one BulkMoveTo call.
	Positions are interpolated between 15 Hz snapshots, rendered slightly in
	the past for smoothness. Deaths topple along the killing blow, then fade.
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local ZombiesConfig = require(Shared.Config.Zombies)
local MeshLibrary = require(Shared.MeshLibrary)
local Net = require(Shared.Net)

local Context = require(script.Parent.Context)
local Audio = require(script.Parent.Audio)

local S = Constants.STUDS
local DELAY = Constants.INTERP_DELAY

type Rig = {
	parts: { BasePart },
	-- index into parts for each named limb
	legL: BasePart,
	legR: BasePart,
	torso: BasePart,
	head: BasePart,
	armL: BasePart,
	armR: BasePart,
	eyes: BasePart,
	extra: BasePart?,
	colors: { Color3 },
}

type View = {
	id: number,
	type: string,
	def: any,
	rig: Rig,
	-- snapshot history: { t, x, z, facing }
	prev: { number }?,
	next: { number }?,
	state: string,
	hp: number,
	flags: number,
	x: number,
	z: number,
	facing: number,
	speed: number,
	stateTime: number,
	animPhase: number,
	flash: number,
	spawnT: number,
	dying: boolean,
	deathT: number,
	deathDirX: number,
	deathDirZ: number,
	fire: Fire?,
	slot: number,
}

local ZombieView = {}

local views: { [number]: View } = {}
local folder = Instance.new("Folder")
folder.Name = "ZombieViews"
folder.Parent = Workspace

local WHITE = Color3.new(1, 1, 1)

-- Uses the imported mesh `meshName` when available, otherwise a plain block.
local function newPart(
	size: Vector3,
	color: Color3,
	material: Enum.Material?,
	shadow: boolean?,
	meshName: string?
): BasePart
	local mesh = if meshName then MeshLibrary.clone(meshName, size) else nil
	local p: BasePart = mesh or Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = shadow == true
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = folder
	return p
end

local function buildRig(def): Rig
	local b = def.body
	local sc = def.scale * S
	local skin = Color3.fromHex(def.colors.skin)
	local shirt = Color3.fromHex(def.colors.shirt)
	local pants = Color3.fromHex(def.colors.pants)
	local function v(base: { number }, w: number, h: number, d: number): Vector3
		return Vector3.new(w * base[1], h * base[2], d * base[3]) * sc
	end
	local rig = {
		legL = newPart(v(b.legs, 0.22, 0.82, 0.24), pants, nil, false, "ZombieLeg"),
		legR = newPart(v(b.legs, 0.22, 0.82, 0.24), pants, nil, false, "ZombieLeg"),
		torso = newPart(v(b.torso, 0.6, 0.76, 0.36), shirt, Enum.Material.Fabric, true, "ZombieTorso"),
		head = newPart(v(b.head, 0.38, 0.38, 0.38), skin, nil, true, "ZombieHead"),
		armL = newPart(v(b.arms, 0.17, 0.74, 0.19), skin, nil, false, "ZombieArm"),
		armR = newPart(v(b.arms, 0.17, 0.74, 0.19), skin, nil, false, "ZombieArm"),
		eyes = newPart(
			Vector3.new(0.26, 0.06, 0.04) * sc * b.head[1],
			Color3.fromHex(def.colors.eyes),
			Enum.Material.Neon,
			false
		),
		extra = nil :: BasePart?,
	} :: any
	if def.type == "exploder" then
		local ball = newPart(Vector3.one * 0.84 * sc, Color3.fromHex("#ff7a1a"), Enum.Material.Neon, false)
		ball.Shape = Enum.PartType.Ball
		rig.extra = ball
	elseif def.type == "spitter" then
		local sac = newPart(Vector3.one * 0.6 * sc, Color3.fromHex("#8cff3a"), Enum.Material.Neon, false)
		sac.Shape = Enum.PartType.Ball
		rig.extra = sac
	elseif def.type == "boss" then
		rig.extra = newPart(Vector3.new(0.5, 0.9, 0.5) * sc, Color3.fromHex("#d8cfb4"), Enum.Material.Slate, true)
	end
	rig.parts = { rig.legL, rig.legR, rig.torso, rig.head, rig.armL, rig.armR, rig.eyes }
	if rig.extra then
		table.insert(rig.parts, rig.extra)
	end
	rig.colors = {}
	for i, p in rig.parts do
		rig.colors[i] = p.Color
		p.Transparency = 1
	end
	return rig
end

local function create(id: number, ztype: string, x: number, z: number): View
	local existing = views[id]
	if existing then
		ZombieView.destroy(existing)
	end
	local def = ZombiesConfig.defs[ztype] or ZombiesConfig.defs.walker
	local view: View = {
		id = id,
		type = def.type,
		def = def,
		rig = buildRig(def),
		prev = nil,
		next = nil,
		state = "spawning",
		hp = 1,
		flags = 0,
		x = x,
		z = z,
		facing = 0,
		speed = 0,
		stateTime = 0,
		animPhase = math.random() * 6,
		flash = 0,
		spawnT = 0,
		dying = false,
		deathT = 0,
		deathDirX = 0,
		deathDirZ = 1,
		fire = nil,
		slot = id,
	}
	views[id] = view
	return view
end

function ZombieView.destroy(view: View)
	for _, p in view.rig.parts do
		p:Destroy()
	end
	views[view.id] = nil
end

-- Live zombies for the minimap / aim assist: { { x, z, type } }.
function ZombieView.list(): { { x: number, z: number, type: string } }
	local out = {}
	for _, v in views do
		if not v.dying then
			table.insert(out, { x = v.x, z = v.z, type = v.type })
		end
	end
	return out
end

function ZombieView.get(id: number): View?
	return views[id]
end

------------------------------------------------------------------ posing

-- pose() writes one rig's CFrames into `scratch`; they are appended to the
-- bulk lists so the whole horde moves in a single BulkMoveTo call.
local scratch: { CFrame } = {}
local bulkCFrames: { CFrame } = {}
local partsList: { BasePart } = {}

local function lerpAngle(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (math.pi * 2) - math.pi
	return a + d * t
end

local function pose(v: View, t: number)
	local def = v.def
	local b = def.body
	local sc = def.scale * S
	local rig = v.rig
	local moving = if v.dying then 0 else math.min(1.4, v.speed / math.max(0.8, def.speed))
	local swingAmp = (if v.type == "runner" then 0.9 else 0.55) * moving
	local swing = math.sin(v.animPhase) * swingAmp
	local hipY = 0.82 * b.legs[2] * sc
	local bob = math.abs(math.cos(v.animPhase)) * 0.05 * moving * sc

	local lean = b.hunch + (if v.type == "runner" then 0.25 * moving else 0)
	local armPitch = -1.3 + math.sin(v.animPhase * 0.5 + v.slot) * 0.15
	local armSpread = 0.08
	local headPitch = 0.15
	local legL, legR = swing, -swing
	local p = v.stateTime
	local s = v.state
	if s == "windup" then
		local k = math.min(1, p / math.max(0.05, def.windup))
		armPitch = -1.3 - k * 1.5
		lean = b.hunch - 0.25 * k
	elseif s == "recover" then
		armPitch = -0.5 - math.min(1, p / 0.35) * 0.8
	elseif s == "ranged" then
		local k = math.min(1, p / math.max(0.05, def.windup))
		headPitch = 0.15 - k * 0.6
		lean = b.hunch - 0.3 * k
	elseif s == "chargeTelegraph" or s == "charging" then
		lean = if s == "charging" then 0.75 else 0.6
		armPitch = -0.6
		armSpread = 0.45
	elseif s == "slamTelegraph" or s == "summon" then
		local k = math.min(1, p / 0.6)
		armPitch = -1.3 - k * 1.6
		armSpread = 0.3 + k * 0.3
		lean = b.hunch - 0.35 * k
	elseif s == "stunned" then
		lean = 0.9
		armPitch = -0.2
		headPitch = 0.6 + math.sin(t * 8) * 0.2
	end
	if v.dying then
		local k = math.min(1, v.deathT / 0.45)
		armPitch = -1.3 + k * 2.6
		armSpread = 0.2 + k * 0.6
		headPitch = 0.6 * k
	end

	-- Root: yaw so local +Z faces the movement/facing direction.
	local root = CFrame.new(v.x * S, 0, v.z * S) * CFrame.Angles(0, v.facing, 0)
	if v.dying then
		local k = math.min(1, v.deathT / 0.45)
		local a = (1 - (1 - k) ^ 3) * math.pi / 2 * 0.96
		local axis = Vector3.new(v.deathDirZ, 0, -v.deathDirX)
		if axis.Magnitude > 1e-3 then
			root = CFrame.new(root.Position + Vector3.new(0, math.sin(a) * 0.15 * sc, 0))
				* CFrame.fromAxisAngle(axis.Unit, a)
				* (root - root.Position)
		end
	end

	local legX = 0.14 * b.torso[1] * sc
	local legH = 0.82 * b.legs[2] * sc
	scratch[1] = root * CFrame.new(-legX, hipY, 0) * CFrame.Angles(legL, 0, 0) * CFrame.new(0, -legH / 2, 0)
	scratch[2] = root * CFrame.new(legX, hipY, 0) * CFrame.Angles(legR, 0, 0) * CFrame.new(0, -legH / 2, 0)
	local sway = math.sin(v.animPhase) * 0.06 * moving
	local frame = root * CFrame.new(0, hipY + bob, 0) * CFrame.fromEulerAnglesYXZ(lean, 0, sway)
	local torsoH = 0.76 * b.torso[2] * sc
	scratch[3] = frame * CFrame.new(0, torsoH / 2, 0)
	local tilt = math.sin(t * 1.3 + v.slot * 1.7) * 0.12
	local headSize = 0.38 * b.head[2] * sc
	local headFrame = frame * CFrame.new(0, torsoH, 0.04 * sc) * CFrame.fromEulerAnglesYXZ(headPitch, tilt * 0.5, tilt)
	scratch[4] = headFrame * CFrame.new(0, headSize / 2, 0)
	local shoulderX = (0.3 * b.torso[1] + 0.08 * b.arms[1]) * sc
	local shoulderY = 0.68 * b.torso[2] * sc
	local armH = 0.74 * b.arms[2] * sc
	local armSwing = math.sin(v.animPhase + 0.5) * 0.18 * moving
	scratch[5] = frame
		* CFrame.new(-shoulderX, shoulderY, 0)
		* CFrame.fromEulerAnglesYXZ(armPitch + armSwing, 0, -armSpread)
		* CFrame.new(0, -armH / 2, 0)
	scratch[6] = frame
		* CFrame.new(shoulderX, shoulderY, 0)
		* CFrame.fromEulerAnglesYXZ(armPitch - armSwing, 0, armSpread)
		* CFrame.new(0, -armH / 2, 0)
	scratch[7] = headFrame * CFrame.new(0, headSize * 0.58, 0.19 * b.head[3] * sc + 0.03)
	if rig.extra then
		if v.type == "exploder" then
			local fusing = s == "fuse"
			local k = if fusing then math.min(1, p / def.windup) else 0
			local pulse = 1
				+ math.sin(t * (if fusing then 30 else 4) + v.slot) * (if fusing then 0.12 else 0.05)
				+ k * 0.35
			rig.extra.Size = Vector3.one * 0.84 * sc * pulse
			rig.extra.Color = if fusing and math.sin(t * 40) > 0 then WHITE else rig.colors[8]
			scratch[8] = frame * CFrame.new(0, 0.36 * b.torso[2] * sc, 0.17 * b.torso[3] * sc)
		elseif v.type == "spitter" then
			scratch[8] = frame * CFrame.new(0, 0.62 * b.torso[2] * sc, -0.24 * sc)
		else
			scratch[8] = frame
				* CFrame.new(0, 0.6 * b.torso[2] * sc, -0.22 * b.torso[3] * sc)
				* CFrame.Angles(-0.6, 0, 0)
		end
	end
end

------------------------------------------------------------------ start

function ZombieView.start()
	local remotes = Context.remotes

	remotes.ZombieSpawn.OnClientEvent:Connect(function(id: number, ztype: string, x: number, z: number)
		create(id, ztype, x, z)
	end)

	remotes.ZombieDeath.OnClientEvent:Connect(function(id: number, dirX: number, dirZ: number)
		local v = views[id]
		if v and not v.dying then
			v.dying = true
			v.deathT = 0
			v.deathDirX, v.deathDirZ = dirX, dirZ
			if v.fire then
				v.fire:Destroy()
				v.fire = nil
			end
			Context.signals.notify:fire("death", v.x, v.z, v.type)
			Audio.play("zombieDeath", v.x, v.z)
		end
	end)

	remotes.ZombieHits.OnClientEvent:Connect(function(hits)
		for _, h in hits do
			local v = views[h[1]]
			if v then
				v.flash = 1
				Context.signals.notify:fire("hit", v.x, v.z, v.def.scale, h[2], h[3])
			end
		end
	end)

	remotes.Snapshot.OnClientEvent:Connect(function(packet: buffer)
		local time, records = Net.unpack(packet)
		for _, r in records do
			local v = views[r.id]
			local code = r.flags // Net.TYPE_SHIFT
			local ztype = ZombiesConfig.types[code]
			if (not v or v.dying or v.type ~= ztype) and ztype then
				v = create(r.id, ztype, r.x, r.z)
			end
			if v then
				v.prev = v.next or { time - 0.066, r.x, r.z, r.facing }
				v.next = { time, r.x, r.z, r.facing }
				local state = Net.STATES[r.state] or "chase"
				if state ~= v.state then
					v.state = state
					v.stateTime = 0
				end
				v.hp = r.hp
				v.flags = r.flags
			end
		end
	end)

	local groanTimer = 2
	RunService.RenderStepped:Connect(function(dt)
		local now = Workspace:GetServerTimeNow()
		local renderTime = now - DELAY
		local t = os.clock()
		table.clear(partsList)
		table.clear(bulkCFrames)
		local n = 0
		for _, v in views do
			v.stateTime += dt
			v.flash = math.max(0, v.flash - dt * 8)
			if v.dying then
				v.deathT += dt
				if v.deathT > 1.7 then
					ZombieView.destroy(v)
					continue
				end
			elseif v.prev and v.next then
				local a, b = v.prev, v.next
				local span = math.max(1e-3, b[1] - a[1])
				local k = math.clamp((renderTime - a[1]) / span, 0, 1.5)
				local nx = a[2] + (b[2] - a[2]) * k
				local nz = a[3] + (b[3] - a[3]) * k
				v.speed = math.sqrt((nx - v.x) ^ 2 + (nz - v.z) ^ 2) / math.max(dt, 1e-3)
				v.x, v.z = nx, nz
				v.facing = lerpAngle(a[4], b[4], math.min(k, 1))
			end
			v.animPhase += dt * (1.5 + v.speed * 2.4 / math.max(0.7, v.def.scale))

			-- Spawn fade-in, death fade-out, hit flash, burning.
			local transparency = 0
			if v.state == "spawning" and not v.dying then
				v.spawnT += dt
				transparency = math.max(0, 1 - v.spawnT / 0.7)
			elseif v.dying then
				transparency = math.clamp((v.deathT - 0.45) / 1.2, 0, 1)
			end
			local burning = bit32.band(v.flags, Net.FLAG_BURNING) ~= 0 and not v.dying
			if burning and not v.fire then
				local f = Instance.new("Fire")
				f.Size = 4 * v.def.scale
				f.Heat = 6
				f.Parent = v.rig.torso
				v.fire = f
			elseif not burning and v.fire then
				v.fire:Destroy()
				v.fire = nil
			end
			local enraged = bit32.band(v.flags, Net.FLAG_ENRAGED) ~= 0
			for i, part in v.rig.parts do
				part.Transparency = transparency
				local base = v.rig.colors[i]
				if enraged and i ~= 7 then
					base = base:Lerp(Color3.fromHex("#a83a2a"), 0.45)
				end
				if burning and i ~= 7 then
					base = base:Lerp(Color3.new(0.1, 0.08, 0.07), 0.4)
				end
				if v.flash > 0 and i ~= 7 then
					part.Color = base:Lerp(WHITE, v.flash)
				elseif part.Color ~= base and not (v.type == "exploder" and i == 8) then
					part.Color = base
				end
			end

			pose(v, t)
			for i, part in v.rig.parts do
				n += 1
				partsList[n] = part
				bulkCFrames[n] = scratch[i]
			end
		end
		if n > 0 then
			Workspace:BulkMoveTo(partsList, bulkCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- Ambient groans from a random nearby zombie.
		groanTimer -= dt
		if groanTimer <= 0 then
			local list = ZombieView.list()
			groanTimer = if #list > 0 then math.max(0.6, 3.5 - #list * 0.05) * (0.6 + math.random() * 0.8) else 2
			if #list > 0 then
				local z = list[math.random(1, #list)]
				Audio.play("groan", z.x, z.z)
			end
		end
	end)
end

return ZombieView
