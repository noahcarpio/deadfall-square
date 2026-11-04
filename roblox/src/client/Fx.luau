--[[
	Client visual effects driven by server events and local prediction:
	tracers, muzzle flashes, goo bursts and splats (green, per Roblox content
	rules), explosions, acid globs and puddles, boss shockwave rings and
	telegraphs, grenades, structure hits and floating damage numbers.
]]
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Weapons = require(Shared.Config.Weapons)

local Context = require(script.Parent.Context)
local Audio = require(script.Parent.Audio)
local ZombieView = require(script.Parent.ZombieView)

local S = Constants.STUDS
local GUN_Y = 1.2 * S
local MAX_NUMBERS = 40

local Fx = {}

local folder = Instance.new("Folder")
folder.Name = "Fx"
folder.Parent = Workspace

local emitterHost = Instance.new("Part")
emitterHost.Name = "FxEmitters"
emitterHost.Anchored = true
emitterHost.CanCollide = false
emitterHost.CanQuery = false
emitterHost.CanTouch = false
emitterHost.Transparency = 1
emitterHost.Size = Vector3.one
emitterHost.Position = Vector3.zero
emitterHost.Parent = folder

local function makeEmitter(
	color: ColorSequence,
	size: NumberSequence,
	speed: NumberRange,
	lifetime: NumberRange,
	light: number?
): (Attachment, ParticleEmitter)
	local att = Instance.new("Attachment")
	att.Parent = emitterHost
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Color = color
	e.Size = size
	e.Speed = speed
	e.Lifetime = lifetime
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, -60, 0)
	e.Drag = 2
	e.LightEmission = light or 0
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = att
	return att, e
end

local gooAtt, gooEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(80, 170, 40), Color3.fromRGB(40, 110, 20)),
	NumberSequence.new(0.5, 0.1),
	NumberRange.new(10, 26),
	NumberRange.new(0.4, 0.8)
)
local sparkAtt, sparkEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 140, 40)),
	NumberSequence.new(0.35, 0),
	NumberRange.new(14, 30),
	NumberRange.new(0.1, 0.25),
	1
)
local fireAtt, fireEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 90, 20)),
	NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) }),
	NumberRange.new(10, 30),
	NumberRange.new(0.25, 0.6),
	1
)
fireEmitter.Acceleration = Vector3.new(0, 12, 0)
local smokeAtt, smokeEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(90, 86, 82)),
	NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
	NumberRange.new(4, 12),
	NumberRange.new(0.8, 1.6)
)
smokeEmitter.Acceleration = Vector3.new(0, 6, 0)
local dustAtt, dustEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(150, 138, 120)),
	NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) }),
	NumberRange.new(4, 14),
	NumberRange.new(0.4, 0.9)
)
dustEmitter.Acceleration = Vector3.zero
local acidAtt, acidEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(150, 255, 70)),
	NumberSequence.new(0.5, 0.1),
	NumberRange.new(6, 18),
	NumberRange.new(0.3, 0.6),
	0.6
)

-- Directed flamethrower jet.
local flameAtt, flameEmitter = makeEmitter(
	ColorSequence.new(Color3.fromRGB(255, 220, 110), Color3.fromRGB(255, 80, 20)),
	NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 4.5) }),
	NumberRange.new(36, 44),
	NumberRange.new(0.5, 0.65),
	1
)
flameEmitter.SpreadAngle = Vector2.new(10, 10)
flameEmitter.EmissionDirection = Enum.NormalId.Front
flameEmitter.Acceleration = Vector3.new(0, 8, 0)
flameEmitter.Drag = 1

local function emit(att: Attachment, emitter: ParticleEmitter, x: number, y: number, z: number, count: number)
	att.WorldPosition = Vector3.new(x, y, z)
	emitter:Emit(count)
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = folder
	return p
end

local function fadeAndRemove(p: BasePart, duration: number, props: { [string]: any }?)
	local goal = props or {}
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, duration + 0.05)
end

-- Flat disc on the ground (a short vertical cylinder).
local function disc(
	x: number,
	z: number,
	radius: number,
	color: Color3,
	transparency: number,
	material: Enum.Material?
): BasePart
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.12, radius * 2 * S, radius * 2 * S),
		CFrame = CFrame.new(x * S, 0.12, z * S) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Transparency = transparency,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

------------------------------------------------------------------ public

function Fx.tracer(x0: number, y0: number, z0: number, x1: number, z1: number, color: Color3, width: number)
	local a = Vector3.new(x0, y0, z0)
	local b = Vector3.new(x1 * S, GUN_Y, z1 * S)
	local len = (b - a).Magnitude
	if len < 0.1 then
		return
	end
	local p = part({
		Size = Vector3.new(width, width, len),
		CFrame = CFrame.lookAt(a:Lerp(b, 0.5), b),
		Color = color,
		Transparency = 0.1,
	})
	fadeAndRemove(p, 0.09)
end

function Fx.muzzle(position: Vector3, color: Color3, big: boolean)
	local p = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (if big then 1.6 else 0.9),
		Position = position,
		Color = color,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = if big then 22 else 14
	light.Brightness = 3
	light.Parent = p
	fadeAndRemove(p, 0.06, { Size = Vector3.one * 0.2 })
end

function Fx.flame(from: Vector3, dirX: number, dirZ: number)
	flameAtt.WorldCFrame = CFrame.lookAt(from, from + Vector3.new(dirX, 0, dirZ))
	flameEmitter:Emit(2)
end

function Fx.goo(x: number, y: number, z: number, amount: number)
	emit(gooAtt, gooEmitter, x * S, y * S, z * S, amount)
end

function Fx.splat(x: number, z: number, radius: number)
	local p = disc(x, z, radius, Color3.fromRGB(58, 120, 32), 0.35, Enum.Material.Glass)
	p.Position += Vector3.new(0, -0.08 + math.random() * 0.04, 0)
	task.delay(10, function()
		if p.Parent then
			fadeAndRemove(p, 3)
		end
	end)
end

function Fx.sparks(x: number, z: number)
	emit(sparkAtt, sparkEmitter, x * S, GUN_Y, z * S, 4)
end

function Fx.explosion(x: number, z: number, radius: number)
	local ball = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * S * 0.6,
		Position = Vector3.new(x * S, 1.5 * S, z * S),
		Color = Color3.fromRGB(255, 150, 50),
		Transparency = 0.1,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 60)
	light.Range = 40
	light.Brightness = 6
	light.Parent = ball
	fadeAndRemove(ball, 0.35, { Size = Vector3.one * radius * S * 2 })
	emit(fireAtt, fireEmitter, x * S, 2, z * S, 30)
	emit(smokeAtt, smokeEmitter, x * S, 3, z * S, 12)
	local scorch = disc(x, z, radius * 0.65, Color3.fromRGB(20, 17, 15), 0.25)
	task.delay(12, function()
		if scorch.Parent then
			fadeAndRemove(scorch, 3)
		end
	end)
	local character = Context.character()
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local d = if root
		then (Vector3.new(x * S, 0, z * S) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude / S
		else 99
	Context.shake(math.max(0.1, 0.7 - d / 30))
	Audio.play("explosion", x, z)
end

function Fx.dust(x: number, z: number, count: number)
	emit(dustAtt, dustEmitter, x * S, 0.6, z * S, count)
end

-- Floating damage / reward text above a world position (metres).
local numberCount = 0
function Fx.floatText(text: string, x: number, y: number, z: number, color: Color3, size: number)
	if numberCount >= MAX_NUMBERS then
		return
	end
	numberCount += 1
	local att = Instance.new("Attachment")
	att.WorldPosition = Vector3.new(x * S + (math.random() - 0.5) * 1.5, y * S, z * S)
	att.Parent = emitterHost
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 40)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = att
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Bangers
	label.TextSize = size
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = att
	local info = TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(att, info, { WorldPosition = att.WorldPosition + Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.8, function()
		att:Destroy()
		numberCount -= 1
	end)
end

------------------------------------------------------------- animated fx

type Animated = { update: (number) -> boolean } -- returns false when finished
local animations: { Animated } = {}

local function animate(a: Animated)
	table.insert(animations, a)
end

local function acidGlob(x0: number, z0: number, x1: number, z1: number, duration: number)
	local blob = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, Color = Color3.fromRGB(157, 255, 74) })
	local t = 0
	animate({
		update = function(dt)
			t += dt
			local k = math.min(1, t / duration)
			local y = 1.6 * (1 - k) + 0.2 + math.sin(k * math.pi) * math.min(4, duration * 4)
			blob.Position = Vector3.new((x0 + (x1 - x0) * k) * S, y * S, (z0 + (z1 - z0) * k) * S)
			if k >= 1 then
				blob:Destroy()
				emit(acidAtt, acidEmitter, x1 * S, 1, z1 * S, 16)
				local puddle = disc(x1, z1, 1.7, Color3.fromRGB(80, 175, 30), 0.3, Enum.Material.Neon)
				task.delay(4, function()
					if puddle.Parent then
						fadeAndRemove(puddle, 0.5)
					end
				end)
				return false
			end
			return true
		end,
	})
end

local function grenade(x0: number, z0: number, x1: number, z1: number, duration: number)
	local g = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 0.9,
		Color = Color3.fromRGB(61, 74, 44),
		Material = Enum.Material.Metal,
	})
	local t = 0
	animate({
		update = function(dt)
			t += dt
			local k = math.min(1, t / duration)
			local y = 1.2 * (1 - k) + 0.15 + math.sin(k * math.pi) * math.min(3.5, duration * 3)
			g.Position = Vector3.new((x0 + (x1 - x0) * k) * S, y * S, (z0 + (z1 - z0) * k) * S)
			if math.random() < 0.5 then
				emit(smokeAtt, smokeEmitter, g.Position.X, g.Position.Y, g.Position.Z, 1)
			end
			if k >= 1 then
				g:Destroy()
				return false
			end
			return true
		end,
	})
end

local function shockwave(x: number, z: number, delay: number, speed: number, maxRadius: number)
	local SEGMENTS = 36
	local segs = {}
	for i = 1, SEGMENTS do
		segs[i] = part({ Size = Vector3.new(1.4, 2.4, 0.6), Color = Color3.fromRGB(255, 138, 58), Transparency = 1 })
	end
	local t = -delay
	animate({
		update = function(dt)
			t += dt
			if t < 0 then
				return true
			end
			local r = 0.5 + speed * t
			if r >= maxRadius then
				for _, s in segs do
					s:Destroy()
				end
				return false
			end
			local alpha = 0.15 + 0.8 * (r / maxRadius)
			local seg = (2 * math.pi * r * S) / SEGMENTS
			for i, s in segs do
				local a = (i / SEGMENTS) * math.pi * 2
				s.Size = Vector3.new(seg + 0.2, 2.4 * (1 - r / maxRadius * 0.6), 0.6)
				s.CFrame = CFrame.new((x + math.cos(a) * r) * S, 1.2, (z + math.sin(a) * r) * S)
					* CFrame.Angles(0, -a + math.pi / 2, 0)
				s.Transparency = alpha
			end
			if math.random() < 0.5 then
				local a = math.random() * math.pi * 2
				emit(dustAtt, dustEmitter, (x + math.cos(a) * r) * S, 0.6, (z + math.sin(a) * r) * S, 1)
			end
			return true
		end,
	})
end

local function telegraph(id: number, shape: string, data)
	local outer = part({ Color = Color3.fromRGB(255, 42, 26), Transparency = 0.7, Size = Vector3.new(1, 0.1, 1) })
	local inner = part({ Color = Color3.fromRGB(255, 90, 42), Transparency = 0.5, Size = Vector3.new(1, 0.12, 1) })
	if shape == "circle" then
		for _, p in { outer, inner } do
			p.Shape = Enum.PartType.Cylinder
		end
	end
	local t = 0
	animate({
		update = function(dt)
			t += dt
			local view = ZombieView.get(id)
			if t >= data.duration or not view or view.dying then
				outer:Destroy()
				inner:Destroy()
				return false
			end
			local k = t / data.duration
			local pulse = 0.65 + math.sin(t * 18) * 0.12
			outer.Transparency = pulse
			local x, z = view.x * S, view.z * S
			if shape == "line" then
				local dir = Vector3.new(math.sin(view.facing), 0, math.cos(view.facing))
				local len = data.length * S
				local w = data.width * S
				outer.Size = Vector3.new(w, 0.1, len)
				outer.CFrame =
					CFrame.lookAt(Vector3.new(x, 0.15, z) + dir * len / 2, Vector3.new(x, 0.15, z) + dir * len)
				inner.Size = Vector3.new(w, 0.12, math.max(0.1, len * k))
				inner.CFrame =
					CFrame.lookAt(Vector3.new(x, 0.16, z) + dir * len * k / 2, Vector3.new(x, 0.16, z) + dir * len)
			else
				local d = data.radius * 2 * S
				outer.Size = Vector3.new(0.1, d, d)
				outer.CFrame = CFrame.new(x, 0.15, z) * CFrame.Angles(0, 0, math.pi / 2)
				inner.Size = Vector3.new(0.12, math.max(0.1, d * k), math.max(0.1, d * k))
				inner.CFrame = CFrame.new(x, 0.16, z) * CFrame.Angles(0, 0, math.pi / 2)
			end
			return true
		end,
	})
end

------------------------------------------------------------------- start

local COLORS: { [string]: Color3 } = {}
for id, def in Weapons.defs do
	COLORS[id] = Color3.fromHex(def.color)
end
COLORS.turret = Color3.fromRGB(154, 216, 255)

function Fx.weaponColor(id: string): Color3
	return COLORS[id] or Color3.new(1, 1, 1)
end

function Fx.start()
	local remotes = Context.remotes

	-- Shots by other players and turrets (our own are drawn instantly by WeaponClient).
	-- Piercing shots (sniper, revolver, DMR) draw a thicker tracer; turrets have no def.
	local function pierceOf(weaponId: string): number
		local def = Weapons.defs[weaponId]
		return if def and def.kind == "hitscan" then def.pierce else 0
	end
	remotes.Shot.OnClientEvent:Connect(function(_userId: number, weaponId: string, ox: number, oz: number, ends)
		local color = Fx.weaponColor(weaponId)
		if weaponId == "flamer" then
			local d = ends[1]
			Fx.flame(Vector3.new(ox * S + d[1] * 2.5, GUN_Y, oz * S + d[2] * 2.5), d[1], d[2])
			return
		end
		for _, e in ends do
			Fx.tracer(ox * S, GUN_Y, oz * S, e[1], e[2], color, if pierceOf(weaponId) >= 1 then 0.35 else 0.18)
		end
		Audio.play(weaponId, ox, oz, 0.7)
	end)

	remotes.Fx.OnClientEvent:Connect(function(kind: string, data)
		if kind == "explosion" then
			Fx.explosion(data.x, data.z, data.radius)
		elseif kind == "acid" then
			acidGlob(data.x0, data.z0, data.x1, data.z1, data.duration)
			Audio.play("spit", data.x0, data.z0)
		elseif kind == "shockwave" then
			shockwave(data.x, data.z, data.delay, data.speed, data.maxRadius)
			Context.shake(0.5)
		elseif kind == "telegraph" then
			telegraph(data.id, data.shape, data)
		elseif kind == "grenade" then
			grenade(data.x0, data.z0, data.x1, data.z1, data.duration)
			if not data.silent then
				Audio.play("launcher", data.x0, data.z0)
			end
		elseif kind == "slam" then
			Fx.dust(data.x, data.z, if data.small then 8 else 24)
			Context.shake(if data.small then 0.35 else 0.7)
		elseif kind == "roar" then
			Context.shake(if data.enrage then 0.6 else 0.25)
			Audio.play("bossRoar", data.x, data.z)
		elseif kind == "heal" then
			Fx.dust(data.x, data.z, 10)
		elseif kind == "build" or kind == "structureBreak" then
			Fx.dust(data.x, data.z, if kind == "build" then 12 else 20)
		elseif kind == "structureHit" then
			Fx.dust(data.x, data.z, 2)
		end
		Context.signals.notify:fire("fx", kind, data)
	end)

	-- Zombie hits / deaths (from ZombieView) -> goo and numbers.
	Context.signals.notify:connect(function(kind: string, a, b, c, d, e)
		if kind == "hit" then
			-- a=x, b=z, c=scale, d=damage, e=crit
			Fx.goo(a, 1.1 * c, b, if e then 6 else 3)
			if Context.settings.damageNumbers then
				Fx.floatText(
					tostring(d),
					a,
					1.9 * c,
					b,
					if e then Color3.fromRGB(255, 178, 58) else Color3.new(1, 1, 1),
					if e then 30 else 22
				)
			end
			Audio.play("hit", a, b, 0.6)
		elseif kind == "death" then
			-- a=x, b=z, c=type
			Fx.goo(a, 1.2, b, 14)
			Fx.splat(a, b, if c == "boss" or c == "brute" then 2.2 else 1.3)
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
		for i = #animations, 1, -1 do
			if not animations[i].update(dt) then
				table.remove(animations, i)
			end
		end
	end)
end

return Fx
