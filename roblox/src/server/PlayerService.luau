--[[
	Server-side state for every player: vitals (health/armor, downed & revive),
	position in simulation metres, arsenal, coins/score, perks, upgrades and
	run statistics. Exposes values to clients through Player attributes and
	sync remotes; the server is authoritative for all of it.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Weapons = require(Shared.Config.Weapons)
local Zombies = require(Shared.Config.Zombies)
local Arsenal = require(Shared.Arsenal)
local Economy = require(Shared.Economy)
local PerkState = require(Shared.PerkState)
local PlayerStats = require(Shared.PlayerStats)

local S = Constants.STUDS

local PlayerService = {}
PlayerService.__index = PlayerService

export type PState = {
	player: Player,
	userId: number,
	arsenal: any,
	economy: any,
	perks: any,
	tiers: { maxHealth: number, armor: number, speed: number, stamina: number },
	stats: PlayerStats.Stats,
	hp: number,
	armor: number,
	downed: boolean,
	invulnUntil: number,
	lastRoll: number,
	secondWindWave: number,
	x: number,
	z: number,
	vx: number,
	vz: number,
	hasBody: boolean,
	root: BasePart?,
	humanoid: Humanoid?,
	prompt: ProximityPrompt?,
	flashlight: SpotLight?,
	gun: Model?,
	ready: boolean,
	perkOffer: { string },
	kills: { [string]: number },
	shotsFired: number,
	shotsHit: number,
	damageDealt: number,
	damageTaken: number,
	revives: number,
	lastHurtNotify: number,
	connections: { RBXScriptConnection },
}

function PlayerService.new(W)
	local self = setmetatable({ W = W, states = {} :: { [Player]: PState } }, PlayerService)
	Players.PlayerAdded:Connect(function(p)
		self:add(p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		self:remove(p)
	end)
	for _, p in Players:GetPlayers() do
		self:add(p)
	end
	return self
end

local function freshRunState(ps: PState)
	ps.arsenal = Arsenal.new()
	ps.economy = Economy.new()
	ps.perks = PerkState.new()
	ps.tiers = { maxHealth = 0, armor = 0, speed = 0, stamina = 0 }
	ps.stats = PlayerStats.compute(ps.tiers, ps.perks)
	ps.hp = ps.stats.maxHealth
	ps.armor = 0
	ps.downed = false
	ps.invulnUntil = 0
	ps.lastRoll = 0
	ps.secondWindWave = -1
	ps.perkOffer = {}
	ps.kills = {}
	for _, t in Zombies.types do
		ps.kills[t] = 0
	end
	ps.shotsFired = 0
	ps.shotsHit = 0
	ps.damageDealt = 0
	ps.damageTaken = 0
	ps.revives = 0
end

function PlayerService.add(self, player: Player)
	if self.states[player] then
		return
	end
	local ps = {
		player = player,
		userId = player.UserId,
		x = 0,
		z = 8,
		vx = 0,
		vz = 0,
		hasBody = false,
		ready = false,
		lastHurtNotify = 0,
		connections = {},
	} :: any
	freshRunState(ps)
	self.states[player] = ps
	table.insert(
		ps.connections,
		player.CharacterAdded:Connect(function(character)
			self:setupCharacter(ps, character)
		end)
	)
	if player.Character then
		self:setupCharacter(ps, player.Character)
	end
	self:syncAll(ps)
	self.W.onPlayerJoined(ps)
end

function PlayerService.remove(self, player: Player)
	local ps = self.states[player]
	if not ps then
		return
	end
	for _, c in ps.connections do
		c:Disconnect()
	end
	self.states[player] = nil
	self.W.onPlayerLeft(ps)
end

function PlayerService.get(self, player: Player): PState?
	return self.states[player]
end

function PlayerService.list(self): { PState }
	local out = {}
	for _, ps in self.states do
		table.insert(out, ps)
	end
	return out
end

function PlayerService.count(self): number
	local n = 0
	for _ in self.states do
		n += 1
	end
	return n
end

-- Living (not downed) players with a character: zombie targets.
function PlayerService.targets(self): { PState }
	local out = {}
	for _, ps in self.states do
		if ps.hasBody and not ps.downed then
			table.insert(out, ps)
		end
	end
	return out
end

function PlayerService.allDown(self): boolean
	local any = false
	for _, ps in self.states do
		if ps.hasBody then
			any = true
			if not ps.downed then
				return false
			end
		end
	end
	return any
end

function PlayerService.setupCharacter(self, ps: PState, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	ps.humanoid = humanoid
	ps.root = root
	ps.hasBody = true
	-- Health is simulated by the server; the Humanoid never dies.
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.JumpPower = 0
	humanoid.WalkSpeed = ps.stats.speed * S
	humanoid.AutoRotate = false

	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Angle = 55
	light.Range = 60
	light.Brightness = 0
	light.Shadows = true
	light.Color = Color3.fromRGB(255, 244, 221)
	light.Face = Enum.NormalId.Front
	light.Parent = root
	ps.flashlight = light

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Revive"
	prompt.ActionText = "Revive"
	prompt.ObjectText = ps.player.DisplayName
	prompt.HoldDuration = Constants.REVIVE_SECONDS
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Enabled = ps.downed
	prompt.Parent = root
	prompt.Triggered:Connect(function(by: Player)
		local helper = self.states[by]
		if helper and helper ~= ps and ps.downed and not helper.downed then
			self:revive(ps, 0.5)
			helper.revives += 1
			self.W.notifyAll(`{by.DisplayName} revived {ps.player.DisplayName}`, "good")
		end
	end)
	ps.prompt = prompt

	self:updateGunModel(ps)
	self:applyMovement(ps)
	self:syncAll(ps)
end

-- Rebuilds the visible gun on the character's right hand for the current weapon.
function PlayerService.updateGunModel(_self, ps: PState)
	local character = ps.player.Character
	if not character then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	if ps.gun then
		ps.gun:Destroy()
	end
	local def = Weapons.defs[ps.arsenal.current]
	local length = if def.kind == "hitscan" and def.id == "pistol" then 1.0 elseif def.id == "sniper" then 3.4 else 2.4
	local model = Instance.new("Model")
	model.Name = "Gun"
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(0.35, 0.45, length)
	body.Color = if def.id == "flamer" then Color3.fromRGB(122, 42, 34) else Color3.fromRGB(44, 47, 51)
	body.Material = Enum.Material.Metal
	body.CanCollide = false
	body.CanQuery = false
	body.Massless = true
	body.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -length / 2 + 0.3)
	body.Parent = model
	local tip = Instance.new("Attachment")
	tip.Name = "Muzzle"
	tip.Position = Vector3.new(0, 0.1, -length / 2)
	tip.Parent = body
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = hand
	weld.Part1 = body
	weld.Parent = body
	model.PrimaryPart = body
	model.Parent = character
	ps.gun = model
	character:SetAttribute("Weapon", def.id)
end

-- Movement allowed only when standing; the client reads these for sprinting.
function PlayerService.applyMovement(_self, ps: PState)
	local h = ps.humanoid
	if h then
		h.WalkSpeed = if ps.downed then 0 else ps.stats.speed * S
	end
	if ps.prompt then
		ps.prompt.Enabled = ps.downed
	end
	ps.player:SetAttribute("Downed", ps.downed)
end

-- Updates simulation positions from characters (called every tick).
function PlayerService.tick(self, dt: number, night: number)
	for _, ps in self.states do
		local root = ps.root
		if root and root.Parent then
			local p = root.Position
			local nx, nz = p.X / S, p.Z / S
			ps.vx = (nx - ps.x) / math.max(dt, 1e-3)
			ps.vz = (nz - ps.z) / math.max(dt, 1e-3)
			ps.x, ps.z = nx, nz
			ps.hasBody = true
			if ps.flashlight then
				ps.flashlight.Brightness = if night > 0.35 and not ps.downed then 1.5 + night * 2.5 else 0
			end
		else
			ps.hasBody = false
		end
		ps.economy:update(dt)
	end
	self:syncAttributes()
end

function PlayerService.syncAttributes(self)
	for _, ps in self.states do
		local p = ps.player
		p:SetAttribute("HP", math.ceil(ps.hp))
		p:SetAttribute("MaxHP", ps.stats.maxHealth)
		p:SetAttribute("Armor", math.ceil(ps.armor))
		p:SetAttribute("MaxArmor", ps.stats.maxArmor)
		p:SetAttribute("Coins", ps.economy.coins)
		p:SetAttribute("Score", ps.economy.score)
		p:SetAttribute("Combo", ps.economy.comboCount)
		p:SetAttribute("ComboMult", ps.economy:multiplier())
		p:SetAttribute("ComboT", ps.economy:comboRemaining())
		p:SetAttribute("Ready", ps.ready)
	end
end

function PlayerService.syncArsenal(self, ps: PState)
	-- Reload times use the server's os.clock(); the client converts them to its own clock.
	self.W.remotes.ArsenalSync:FireClient(ps.player, ps.arsenal:serialize(), os.clock())
end

function PlayerService.syncStats(self, ps: PState)
	local perks = {}
	for _, id in ps.perks.order do
		table.insert(perks, { id = id, level = ps.perks:level(id) })
	end
	self.W.remotes.StatsSync:FireClient(ps.player, ps.stats, perks, ps.tiers)
end

function PlayerService.syncAll(self, ps: PState)
	self:syncArsenal(ps)
	self:syncStats(ps)
end

-- Recomputes stats after upgrades/perks; extra max health is granted immediately.
function PlayerService.refreshStats(self, ps: PState)
	local old = ps.stats
	ps.stats = PlayerStats.compute(ps.tiers, ps.perks)
	ps.hp = math.min(ps.stats.maxHealth, ps.hp + math.max(0, ps.stats.maxHealth - old.maxHealth))
	ps.armor = math.min(ps.stats.maxArmor, ps.armor)
	ps.economy.coinMultiplier = 1 + 0.25 * ps.perks:level("greed")
	self:applyMovement(ps)
	self:syncStats(ps)
end

function PlayerService.heal(_self, ps: PState, amount: number): number
	local before = ps.hp
	ps.hp = math.min(ps.stats.maxHealth, ps.hp + amount)
	return ps.hp - before
end

function PlayerService.addArmor(_self, ps: PState, amount: number): number
	local before = ps.armor
	ps.armor = math.min(ps.stats.maxArmor, ps.armor + amount)
	return ps.armor - before
end

--[[
	Applies damage with i-frames, armor, perks and knockback. Lethal damage
	downs the player (Second Wind can save them once per wave).
]]
function PlayerService.damage(self, ps: PState, amount: number, srcX: number, srcZ: number, knock: number, source: string)
	local W = self.W
	if ps.downed or not ps.hasBody or amount <= 0 then
		return
	end
	local now = os.clock()
	if now < ps.invulnUntil then
		return
	end
	amount *= ps.stats.damageTaken
	local continuous = amount < 1.5 and source == "acid"
	ps.hp, ps.armor = PlayerStats.applyArmor(ps.hp, ps.armor, amount)
	ps.damageTaken += amount
	if not continuous then
		ps.invulnUntil = now + 0.12
	end
	local dx, dz = ps.x - srcX, ps.z - srcZ
	local len = math.max(math.sqrt(dx * dx + dz * dz), 1e-3)
	if continuous then
		if now - ps.lastHurtNotify > 0.4 then
			ps.lastHurtNotify = now
			W.remotes.Hurt:FireClient(ps.player, amount, 0, 0, 0, true)
		end
	else
		W.remotes.Hurt:FireClient(ps.player, amount, dx / len, dz / len, knock, false)
	end

	if ps.hp <= 0 then
		if ps.perks:has("secondWind") and ps.secondWindWave ~= W.waves.wave then
			ps.secondWindWave = W.waves.wave
			ps.hp = 1
			ps.invulnUntil = now + 2
			W.notify(ps.player, "SECOND WIND!", "good")
			return
		end
		ps.hp = 0
		ps.downed = true
		self:applyMovement(ps)
		W.notifyAll(`{ps.player.DisplayName} is down! Hold E next to them to revive.`, "bad")
	end
end

function PlayerService.revive(self, ps: PState, fraction: number)
	if not ps.downed then
		return
	end
	ps.downed = false
	ps.hp = math.max(1, ps.stats.maxHealth * fraction)
	ps.invulnUntil = os.clock() + 1.5
	self:applyMovement(ps)
end

-- Starts a new run for everyone: fresh state, teleport to the plaza.
function PlayerService.resetAll(self)
	local i = 0
	for _, ps in self.states do
		freshRunState(ps)
		ps.ready = false
		self:applyMovement(ps)
		self:updateGunModel(ps)
		self:syncAll(ps)
		local root = ps.root
		if root and root.Parent then
			local a = i * (math.pi * 2 / 6)
			root.CFrame = CFrame.new(math.cos(a) * 2 * S, 3 * S, (8 + math.sin(a) * 2) * S)
			root.AssemblyLinearVelocity = Vector3.zero
		end
		i += 1
	end
end

return PlayerService
