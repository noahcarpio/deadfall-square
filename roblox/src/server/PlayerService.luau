--[[
	Server-side state for every player: vitals (health/armor, downed & revive),
	position in simulation metres, arsenal, coins/score, perks, upgrades and
	run statistics, the inventory bag and stealth state (crouching, footstep
	noise, whether a zombie can see them). Exposes values to clients through
	Player attributes and sync remotes; the server is authoritative for all
	of it.
]]
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Weapons = require(Shared.Config.Weapons)
local Zombies = require(Shared.Config.Zombies)
local Arsenal = require(Shared.Arsenal)
local Gear = require(Shared.Gear)
local Inventory = require(Shared.Inventory)
local Items = require(Shared.Config.Items)
local Stealth = require(Shared.Config.Stealth)
local MeshLibrary = require(Shared.MeshLibrary)
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
	tiers: { maxHealth: number, armor: number, speed: number, stamina: number, backpack: number },
	inventory: Inventory.Inventory,
	-- Equipped gear and the stash (Gear.Item tables; guns live in the arsenal too).
	gear: {
		stash: { Gear.Item },
		melee: Gear.Item?,
		armor: Gear.Item?,
		gadgets: { Gear.Item | false },
		guns: { [string]: Gear.Item },
	},
	nextUid: number,
	abilityReady: { [number]: number },
	meleeStep: number,
	crouching: boolean,
	noiseTimer: number,
	noiseX: number,
	noiseZ: number,
	spottedUntil: number,
	lastShotNoise: number,
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
	rewardOffer: { any }, -- RewardRules cards waiting for a choice
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
	ps.tiers = { maxHealth = 0, armor = 0, speed = 0, stamina = 0, backpack = 0 }
	-- Starting kit: a machete and a Charge Strike.
	ps.nextUid = 1
	local function uid()
		ps.nextUid += 1
		return ps.nextUid
	end
	ps.gear = {
		stash = {},
		melee = Gear.common("machete", uid()),
		armor = nil,
		gadgets = { Gear.common("chargeStrike", uid()), false, false },
		guns = {},
	}
	ps.abilityReady = {}
	ps.meleeStep = 0
	ps.stats = PlayerStats.compute(ps.tiers, ps.perks, Gear.bonus(ps.gear.armor))
	-- Everyone starts with a few rags and a bandage.
	ps.inventory = Inventory.new(ps.stats.carryCapacity)
	ps.inventory:add("cloth", 2)
	ps.inventory:add("bandage", 1)
	ps.spottedUntil = 0
	ps.hp = ps.stats.maxHealth
	ps.armor = 0
	ps.downed = false
	ps.invulnUntil = 0
	ps.lastRoll = 0
	ps.secondWindWave = -1
	ps.rewardOffer = {}
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
		crouching = false,
		noiseTimer = 0,
		noiseX = 0,
		noiseZ = 8,
		lastShotNoise = 0,
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
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
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

	ps.crouching = false
	character:SetAttribute("Crouching", false)
	self:updateGunModel(ps)
	self:updateMeleeModel(ps)
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
	local model = Instance.new("Model")
	model.Name = "Gun"
	-- Imported weapon mesh if available (barrel toward -Z), otherwise a simple block.
	local body: BasePart
	local mesh = MeshLibrary.clone("Gun_" .. def.id)
	if mesh then
		body = mesh
		body.Anchored = false
	else
		local length = if def.id == "pistol" then 1.0 elseif def.id == "sniper" then 3.4 else 2.4
		local block = Instance.new("Part")
		block.Size = Vector3.new(0.35, 0.45, length)
		block.Color = if def.id == "flamer" then Color3.fromRGB(122, 42, 34) else Color3.fromRGB(44, 47, 51)
		block.Material = Enum.Material.Metal
		body = block
	end
	local length = body.Size.Z
	body.Name = "Body"
	body.CanCollide = false
	body.CanQuery = false
	body.Massless = true
	body.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, -length / 2 + 0.3)
	body.Parent = model
	local tip = Instance.new("Attachment")
	tip.Name = "Muzzle"
	tip.Position = Vector3.new(0, 0.1, -length / 2)
	tip.Parent = body
	-- A Motor6D (not a weld) so clients can turn the gun to line up with the
	-- arm when CharacterAnimator raises it to aim.
	local grip = Instance.new("Motor6D")
	grip.Name = "GunGrip"
	grip.Part0 = hand
	grip.Part1 = body
	grip.C0 = CFrame.new(0, -hand.Size.Y / 2, 0)
	grip.C1 = CFrame.new(0, 0, length / 2 - 0.3)
	grip.Parent = body
	model.PrimaryPart = body
	model.Parent = character
	ps.gun = model
	character:SetAttribute("Weapon", def.id)
end

-- Melee weapon shapes in metres, built along -Z from the grip: { size, centre z, colour, material }.
local MELEE_SHAPES = {
	machete = {
		{ Vector3.new(0.07, 0.08, 0.26), -0.05, Color3.fromRGB(58, 40, 28), Enum.Material.Wood },
		{ Vector3.new(0.03, 0.12, 0.62), -0.48, Color3.fromRGB(170, 174, 178), Enum.Material.Metal },
	},
	fireaxe = {
		{ Vector3.new(0.06, 0.06, 0.95), -0.38, Color3.fromRGB(122, 86, 52), Enum.Material.Wood },
		{ Vector3.new(0.05, 0.3, 0.2), -0.78, Color3.fromRGB(178, 40, 34), Enum.Material.Metal },
	},
	sledge = {
		{ Vector3.new(0.07, 0.07, 1.0), -0.42, Color3.fromRGB(96, 72, 48), Enum.Material.Wood },
		{ Vector3.new(0.22, 0.22, 0.36), -0.92, Color3.fromRGB(74, 78, 84), Enum.Material.Metal },
	},
}

-- Rebuilds the melee weapon held in the right hand (hidden by clients except while swinging).
function PlayerService.updateMeleeModel(_self, ps: PState)
	local character = ps.player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("MeleeWeapon")
	if old then
		old:Destroy()
	end
	local item = ps.gear.melee
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not item or not hand or not hand:IsA("BasePart") then
		return
	end
	local shape = MELEE_SHAPES[item.id] or MELEE_SHAPES.machete
	local model = Instance.new("Model")
	model.Name = "MeleeWeapon"
	local root: BasePart? = nil
	for i, p in shape do
		local part = Instance.new("Part")
		part.Name = if i == 1 then "Handle" else "Head"
		part.Size = p[1] * S
		part.Color = p[3]
		part.Material = p[4]
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.CastShadow = false
		part.CFrame = hand.CFrame * CFrame.new(0, -hand.Size.Y / 2, p[2] * S)
		part.Parent = model
		if root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		else
			root = part
		end
	end
	local handle = root :: BasePart
	local grip = Instance.new("Motor6D")
	grip.Name = "MeleeGrip"
	grip.Part0 = hand
	grip.Part1 = handle
	grip.C0 = CFrame.new(0, -hand.Size.Y / 2, 0)
	grip.C1 = CFrame.new(0, 0, -shape[1][2] * S)
	grip.Parent = handle
	model.PrimaryPart = handle
	model.Parent = character
end

-- Movement allowed only when standing; the client reads these for sprinting.
function PlayerService.applyMovement(_self, ps: PState)
	local h = ps.humanoid
	if h then
		h.WalkSpeed = if ps.downed then 0 else ps.stats.speed * S * (if ps.crouching then Stealth.CROUCH_SPEED else 1)
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
			self:footsteps(ps, dt)
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
		p:SetAttribute("Spotted", os.clock() < ps.spottedUntil)
	end
end

-- Footstep noise from how fast the player actually moved over the last interval.
function PlayerService.footsteps(self, ps: PState, dt: number)
	ps.noiseTimer -= dt
	if ps.noiseTimer > 0 then
		return
	end
	local interval = 0.4
	ps.noiseTimer = interval
	local moved = math.sqrt((ps.x - ps.noiseX) ^ 2 + (ps.z - ps.noiseZ) ^ 2) / interval
	ps.noiseX, ps.noiseZ = ps.x, ps.z
	if ps.downed or moved < 0.6 or moved > 40 then
		return -- standing still, or a teleport
	end
	local radius = if ps.crouching
		then Stealth.NOISE.crouch
		elseif moved > ps.stats.speed * 1.2 then Stealth.NOISE.sprint
		else Stealth.NOISE.walk
	self.W.noise(ps.x, ps.z, radius)
end

-- Marks players a zombie saw this tick (for the HUD's "spotted" eye).
function PlayerService.markSpotted(self, spotted: { [any]: boolean })
	local now = os.clock()
	for ps in spotted do
		if self.states[ps.player] == ps then
			ps.spottedUntil = now + 1
		end
	end
end

function PlayerService.setCrouch(self, ps: PState, on: boolean)
	if ps.downed then
		on = false
	end
	if ps.crouching == on then
		return
	end
	ps.crouching = on
	local character = ps.player.Character
	if character then
		character:SetAttribute("Crouching", on)
	end
	self:applyMovement(ps)
end

------------------------------------------------------------------ gear

function PlayerService.newUid(_self, ps: PState): number
	ps.nextUid += 1
	return ps.nextUid
end

function PlayerService.syncGear(self, ps: PState)
	local g = ps.gear
	local gadgets = {}
	for i = 1, Gear.GADGET_SLOTS do
		gadgets[i] = g.gadgets[i] or false
	end
	local character = ps.player.Character
	if character then
		character:SetAttribute("Melee", if g.melee then g.melee.id else nil)
	end
	self.W.remotes.GearSync:FireClient(ps.player, {
		stash = g.stash,
		melee = g.melee or false,
		armor = g.armor or false,
		gadgets = gadgets,
		guns = g.guns,
	})
end

-- Finds a piece anywhere (stash, equipped or attuned to a gun).
function PlayerService.findGear(_self, ps: PState, uid: number): Gear.Item?
	local g = ps.gear
	for _, item in g.stash do
		if item.uid == uid then
			return item
		end
	end
	if g.melee and g.melee.uid == uid then
		return g.melee
	end
	if g.armor and g.armor.uid == uid then
		return g.armor
	end
	for _, item in g.gadgets do
		if item and item.uid == uid then
			return item
		end
	end
	for _, item in g.guns do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

-- Puts a found piece in the stash. Returns false if the stash is full.
function PlayerService.giveGear(self, ps: PState, item: Gear.Item): boolean
	if #ps.gear.stash >= Gear.STASH_SIZE then
		return false
	end
	table.insert(ps.gear.stash, item)
	self:syncGear(ps)
	return true
end

-- Removes a stash piece (salvage / sold). Equipped pieces can't be removed.
function PlayerService.removeGear(self, ps: PState, uid: number): boolean
	for i, item in ps.gear.stash do
		if item.uid == uid then
			table.remove(ps.gear.stash, i)
			self:syncGear(ps)
			return true
		end
	end
	return false
end

-- Removes a gun (sold or dropped) and its attuned gear. Returns its gear, if any.
function PlayerService.removeGun(self, ps: PState, id: string): Gear.Item?
	if not ps.arsenal:remove(id) then
		return nil
	end
	local gear = ps.gear.guns[id]
	ps.gear.guns[id] = nil
	self:syncArsenal(ps)
	self:updateGunModel(ps)
	self:syncGear(ps)
	return gear
end

-- Drops a gun at the player's feet for anyone to pick up (the pistol stays).
function PlayerService.dropGun(self, ps: PState, id: string)
	if id == "pistol" or not ps.arsenal:owns(id) then
		return
	end
	local gear = self:removeGun(ps, id)
	if gear then
		self.W.pickups:spawnGear(ps.x, ps.z, nil, nil, gear, ps)
	else
		self.W.pickups:spawnGun(ps.x, ps.z, id, ps)
	end
end

-- Drops a stash gear piece at the player's feet.
function PlayerService.dropGear(self, ps: PState, uid: number)
	local item = nil
	for _, it in ps.gear.stash do
		if it.uid == uid then
			item = it
		end
	end
	if item and self:removeGear(ps, uid) then
		self.W.pickups:spawnGear(ps.x, ps.z, nil, nil, item, ps)
	end
end

-- Equips a stash piece, swapping whatever it replaces back into the stash.
function PlayerService.equipGear(self, ps: PState, uid: number, slot: number?): boolean
	local g = ps.gear
	local index = nil
	for i, item in g.stash do
		if item.uid == uid then
			index = i
		end
	end
	if not index then
		return false
	end
	local item = table.remove(g.stash, index) :: Gear.Item
	local old: Gear.Item? = nil
	if item.kind == "melee" then
		old = g.melee
		g.melee = item
		self:updateMeleeModel(ps)
	elseif item.kind == "armor" then
		old = g.armor
		g.armor = item
	elseif item.kind == "gadget" then
		local s = slot
		if not s or s < 1 or s > Gear.GADGET_SLOTS or s ~= math.floor(s) then
			s = table.find(g.gadgets, false) or 1
		end
		local current = g.gadgets[s :: number]
		old = if current then current else nil
		g.gadgets[s :: number] = item
	else
		old = g.guns[item.id]
		g.guns[item.id] = item
		ps.arsenal:attune(item.id, item :: any)
		ps.arsenal.owned[item.id].gear = item :: any -- share the table so reinforcing shows at once
		self:syncArsenal(ps)
		self:updateGunModel(ps)
	end
	if old then
		table.insert(g.stash, old)
	end
	self:refreshStats(ps)
	self:syncGear(ps)
	return true
end

function PlayerService.syncInventory(self, ps: PState)
	self.W.remotes.InventorySync:FireClient(ps.player, ps.inventory:serialize())
end

-- Uses a bandage. Returns true if one was used.
function PlayerService.useBandage(self, ps: PState): boolean
	if ps.downed or ps.hp >= ps.stats.maxHealth or not ps.inventory:remove("bandage", 1) then
		return false
	end
	self:heal(ps, Items.BANDAGE_HEAL)
	self:syncInventory(ps)
	self.W.notify(ps.player, `+{Items.BANDAGE_HEAL} health`, "good")
	return true
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
	self:syncInventory(ps)
	self:syncGear(ps)
end

-- Recomputes stats after upgrades/perks; extra max health is granted immediately.
function PlayerService.refreshStats(self, ps: PState)
	local old = ps.stats
	ps.stats = PlayerStats.compute(ps.tiers, ps.perks, Gear.bonus(ps.gear.armor))
	ps.hp = math.min(ps.stats.maxHealth, ps.hp + math.max(0, ps.stats.maxHealth - old.maxHealth))
	ps.armor = math.min(ps.stats.maxArmor, ps.armor)
	ps.inventory.capacity = ps.stats.carryCapacity
	self:syncInventory(ps)
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
function PlayerService.damage(
	self,
	ps: PState,
	amount: number,
	srcX: number,
	srcZ: number,
	knock: number,
	source: string
)
	local W = self.W
	if ps.downed or not ps.hasBody or amount <= 0 then
		return
	end
	local now = os.clock()
	if now < ps.invulnUntil then
		return
	end
	amount *= ps.stats.damageTaken
	if source == "acid" or source == "exploder" then
		amount *= ps.stats.hazardTaken
	end
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
		self:setCrouch(ps, false)
		self:applyMovement(ps)
		W.notifyAll(`{ps.player.DisplayName} is down! Hold F next to them to revive.`, "bad")
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
		self:setCrouch(ps, false)
		self:applyMovement(ps)
		self:updateGunModel(ps)
		self:updateMeleeModel(ps)
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
