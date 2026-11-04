--[[
	Loot dropped by zombies: ammo, health, armor, coin bags, weapon crates and
	gear (rarity-coloured, with a light beam; goes to the finder's stash).
	Pickups are anchored server parts (few at a time); clients animate them.
]]
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Visuals = require(Shared.Config.Visuals)
local MeshLibrary = require(Shared.MeshLibrary)
local Weapons = require(Shared.Config.Weapons)
local Gear = require(Shared.Gear)

local S = Constants.STUDS
local LIFETIME = 22
local BASE_DROP_CHANCE = 0.085

-- Plain gun drops by floor. The auto shotgun and railgun only come as gear (rewards and gear
-- drops), from floor 12 / 18 and at Rare / Unique (Weapons minFloor / minRarity).
local WEAPON_DROP_WAVE = {
	revolver = 2,
	shotgun = 2,
	doublebarrel = 3,
	smg = 3,
	rifle = 4,
	carbine = 4,
	dmr = 5,
	sniper = 6,
	lmg = 6,
	flamer = 7,
	launcher = 8,
}

local COLORS = {
	ammo = Color3.fromHex("#e0c050"),
	health = Color3.fromHex("#ff4a5a"),
	armor = Color3.fromHex("#4aa8ff"),
	weapon = Color3.fromHex("#c070ff"),
	coins = Color3.fromHex("#ffd23a"),
	bag = Color3.fromHex("#c8b28a"),
}

-- Seconds a dropped pickup ignores the player who dropped it (so the magnet doesn't grab it back).
local DROP_LOCK = 3

local Pickups = {}
Pickups.__index = Pickups

function Pickups.new(W)
	local folder = Instance.new("Folder")
	folder.Name = "Pickups"
	folder.Parent = Workspace
	return setmetatable({ W = W, list = {}, folder = folder, vacuum = false }, Pickups)
end

function Pickups.clear(self)
	for _, p in self.list do
		p.part:Destroy()
	end
	table.clear(self.list)
	self.vacuum = false
end

local function weaponCandidates(W, ps): { string }
	local out = {}
	for _, id in Weapons.order do
		local minWave = WEAPON_DROP_WAVE[id]
		if minWave and W.waves.wave >= minWave and not (ps and ps.arsenal:owns(id)) then
			table.insert(out, id)
		end
	end
	return out
end

function Pickups.rollDrop(self, z, ps)
	local W = self.W
	local chanceMult = if ps then ps.stats.dropChance else 1
	local chance = BASE_DROP_CHANCE * z.def.dropMult * chanceMult
	local lowAmmo = ps ~= nil and ps.arsenal:lowOnAmmo(0.2)
	if not W.rng:chance(if lowAmmo then chance * 1.6 else chance) then
		return
	end
	local missing = if ps then 1 - ps.hp / ps.stats.maxHealth else 0.3
	local kind = W.rng:weighted({
		ammo = if ps and #ps.arsenal:list() > 1 then (if lowAmmo then 60 else 32) else 10,
		health = 10 + missing * 45,
		armor = if ps and ps.armor < ps.stats.maxArmor then 14 else 4,
		coins = 18,
		weapon = if #weaponCandidates(W, ps) > 0 then 7 else 0,
	})
	self:spawn(kind, z.x, z.z, ps)
end

-- Block fallback used when the imported pickup mesh isn't in the place.
local function blockModel(kind: string): BasePart
	local part = Instance.new("Part")
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLORS[kind]
	if kind == "ammo" then
		part.Size = Vector3.new(1.9, 1.1, 1.3)
		part.Color = Color3.fromHex("#4a5a2a")
	elseif kind == "health" then
		part.Size = Vector3.new(1.8, 1.2, 1.35)
		part.Color = Color3.fromHex("#d42a3a")
	elseif kind == "armor" then
		part.Size = Vector3.new(1.5, 1.8, 0.4)
		part.Color = Color3.fromHex("#2e5f8f")
	elseif kind == "coins" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(0.5, 1.4, 1.4)
		part.Material = Enum.Material.Neon
	else
		part.Size = Vector3.new(2.7, 1.3, 1.65)
		part.Color = Color3.fromHex("#6a4a2a")
		part.Material = Visuals.enum(Enum.Material.WoodPlanks)
	end
	return part
end

local function makeModel(kind: string, weapon: string?, gearItem: Gear.Item?): BasePart
	local meshKind = if kind == "gear" then "weapon" elseif kind == "bag" then "ammo" else kind
	local part: BasePart = MeshLibrary.clone("Pickup_" .. meshKind) or blockModel(meshKind)
	local color = if gearItem then Color3.fromHex(Gear.rarities[gearItem.rarity].color) else COLORS[kind]
	part.Name = "Pickup"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 8
	light.Brightness = 1.2
	light.Parent = part
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 22)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 70
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.Text = if gearItem
		then Gear.title(gearItem):upper()
		elseif kind == "weapon" and weapon then Weapons.defs[weapon].name:upper()
		else kind:upper()
	if gearItem then
		-- A tall beam so gear is easy to spot from the top-down camera.
		local beam = Instance.new("Part")
		beam.Name = "Beam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.CanQuery = false
		beam.CanTouch = false
		beam.Material = Enum.Material.Neon
		beam.Color = color
		beam.Transparency = 0.55
		beam.Shape = Enum.PartType.Cylinder
		beam.Size = Vector3.new(6 * S, 0.25 * S, 0.25 * S)
		beam.Parent = part
		part:SetAttribute("Beam", true)
	end
	label.Parent = gui
	gui.Parent = part
	part:SetAttribute("Kind", kind)
	CollectionService:AddTag(part, "DeadfallPickup")
	return part
end

function Pickups.spawn(self, kind: string, x: number, z: number, ps)
	local W = self.W
	local weapon = nil
	if kind == "weapon" then
		local candidates = weaponCandidates(W, ps)
		if #candidates == 0 then
			kind = "ammo"
		else
			weapon = W.rng:pick(candidates)
		end
	end
	local part = makeModel(kind, weapon)
	part.Position = Vector3.new(x * S, 1.4 * S, z * S)
	part.Parent = self.folder
	table.insert(self.list, { kind = kind, weapon = weapon, x = x, z = z, life = LIFETIME, part = part })
end

-- Drops a gear piece (rolled for the current floor) at (x, z).
-- Drops a gear piece at (x, z): rolled for the current floor, or `item` when a player drops one.
function Pickups.spawnGear(
	self,
	x: number,
	z: number,
	kind: string?,
	minRarity: string?,
	item: Gear.Item?,
	dropper: any?
)
	local W = self.W
	item = item or Gear.roll(W.rng, math.max(1, W.waves.wave), 0, kind, minRarity)
	local part = makeModel("gear", nil, item)
	part.Position = Vector3.new(x * S, 1.4 * S, z * S)
	local beam = part:FindFirstChild("Beam") :: BasePart?
	if beam then
		beam.CFrame = CFrame.new(x * S, 3 * S, z * S) * CFrame.Angles(0, 0, math.pi / 2)
	end
	part.Parent = self.folder
	table.insert(self.list, {
		kind = "gear",
		item = item,
		x = x,
		z = z,
		life = if dropper then 120 else 60,
		part = part,
		lockedFor = dropper,
		lockUntil = os.clock() + DROP_LOCK,
	})
end

-- A dropped gun without gear (gives the gun, or ammo if you have it).
function Pickups.spawnGun(self, x: number, z: number, weapon: string, dropper: any?)
	local part = makeModel("weapon", weapon)
	part.Position = Vector3.new(x * S, 1.4 * S, z * S)
	part.Parent = self.folder
	table.insert(self.list, {
		kind = "weapon",
		weapon = weapon,
		x = x,
		z = z,
		life = 120,
		part = part,
		lockedFor = dropper,
		lockUntil = os.clock() + DROP_LOCK,
	})
end

-- A dropped bag of items ({ [id] = count }); whoever picks it up takes what fits.
function Pickups.spawnBag(self, x: number, z: number, contents: { [string]: number }, dropper: any?)
	local part = makeModel("bag")
	part.Position = Vector3.new(x * S, 1.4 * S, z * S)
	part.Parent = self.folder
	table.insert(self.list, {
		kind = "bag",
		contents = contents,
		x = x,
		z = z,
		life = 120,
		part = part,
		lockedFor = dropper,
		lockUntil = os.clock() + DROP_LOCK,
	})
end

-- Applies a pickup to a player. Returns false if it should stay on the ground.
function Pickups.collect(self, p, ps): boolean
	local W = self.W
	local label
	if p.kind == "health" then
		local healed = W.players:heal(ps, 30)
		if healed <= 0 and not self.vacuum then
			return false
		end
		label = `+{math.floor(healed + 0.5)} HP`
	elseif p.kind == "armor" then
		local added = W.players:addArmor(ps, 20)
		if added <= 0 and not self.vacuum then
			return false
		end
		label = `+{math.floor(added + 0.5)} ARMOR`
	elseif p.kind == "ammo" then
		for _, w in ps.arsenal:list() do
			ps.arsenal:addAmmoFraction(w.id, 0.3)
		end
		W.players:syncArsenal(ps)
		label = "AMMO"
	elseif p.kind == "gear" then
		local item = table.clone(p.item)
		item.traits = table.clone(p.item.traits)
		item.uid = W.players:newUid(ps)
		if item.kind == "gun" and not ps.arsenal:owns(item.id) and ps.arsenal:hasRoomFor(item.id) then
			-- A dropped gun with gear: take the gun and its gear straight into the hands.
			ps.gear.guns[item.id] = item
			ps.arsenal:attune(item.id, item :: any)
			ps.arsenal.owned[item.id].gear = item :: any
			W.players:syncArsenal(ps)
			W.players:syncGear(ps)
			label = `{Gear.title(item):upper()}`
		elseif not W.players:giveGear(ps, item) then
			return false -- stash full: leave it for someone else
		else
			label = `{Gear.title(item):upper()} → STASH`
		end
	elseif p.kind == "bag" then
		local took = {}
		local left = false
		for id, n in p.contents do
			local added = ps.inventory:add(id, n)
			if added > 0 then
				table.insert(took, `+{added} {id}`)
			end
			if added < n then
				p.contents[id] = n - added
				left = true
			else
				p.contents[id] = nil
			end
		end
		W.players:syncInventory(ps)
		if #took == 0 then
			return false
		end
		W.remotes.Notify:FireClient(ps.player, table.concat(took, ", "), "pickup", ps.x, ps.z)
		return not left
	elseif p.kind == "coins" then
		local amount = math.floor(W.rng:int(12, 22) * (1 + W.waves.wave * 0.08) * ps.economy.coinMultiplier + 0.5)
		ps.economy:addCoins(amount)
		label = `+{amount} COINS`
	else
		local name = Weapons.defs[p.weapon].name
		local res = ps.arsenal:give(p.weapon)
		if res == "full" then
			-- Gun slots full: leave it on the ground, and say how to take it (throttled).
			local now = os.clock()
			if now - (ps.slotNoticeAt or 0) > 4 then
				ps.slotNoticeAt = now
				W.notify(ps.player, `Gun slots full — drop a gun (I) to take the {name}`, "info")
			end
			return false
		end
		W.players:syncArsenal(ps)
		label = if res == "new" then `NEW: {name}` else `{name} AMMO`
	end
	W.remotes.Notify:FireClient(ps.player, label, "pickup", ps.x, ps.z)
	return true
end

function Pickups.update(self, dt: number)
	local W = self.W
	for i = #self.list, 1, -1 do
		local p = self.list[i]
		p.life -= dt
		if p.life <= 0 then
			p.part:Destroy()
			table.remove(self.list, i)
			continue
		end
		-- Nearest standing player within magnet range pulls it in.
		local best, bestD = nil, math.huge
		local now = os.clock()
		for _, ps in W.players:targets() do
			local d = math.sqrt((ps.x - p.x) ^ 2 + (ps.z - p.z) ^ 2)
			local locked = p.lockedFor == ps and now < (p.lockUntil or 0)
			if not locked and d < bestD and (self.vacuum or d < ps.stats.magnetRadius) then
				best, bestD = ps, d
			end
		end
		if best then
			local speed = if self.vacuum then 22 else 12
			local step = math.min(bestD, speed * dt)
			p.x += (best.x - p.x) / math.max(bestD, 1e-3) * step
			p.z += (best.z - p.z) / math.max(bestD, 1e-3) * step
			p.part.Position = Vector3.new(p.x * S, 1.4 * S, p.z * S)
			local beam = p.part:FindFirstChild("Beam") :: BasePart?
			if beam then
				beam.CFrame = CFrame.new(p.x * S, 3 * S, p.z * S) * CFrame.Angles(0, 0, math.pi / 2)
			end
			if bestD < 1.0 and self:collect(p, best) then
				p.part:Destroy()
				table.remove(self.list, i)
			end
		end
		if p.life < 5 and self.list[i] == p then
			p.part.Transparency = if math.floor(p.life * 8) % 2 == 0 then 0.7 else 0
		end
	end
end

return Pickups
