--[[
	Player-built barricades and auto-turrets: placement validation (in bounds,
	no overlaps, never sealing anyone off from the spawns), nav-grid updates so
	zombies path around or break through, damage, and turret targeting.
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Visuals = require(Shared.Config.Visuals)
local Shop = require(Shared.Config.Shop)
local MathUtil = require(Shared.Util.MathUtil)
local MeshLibrary = require(Shared.MeshLibrary)
local NavGrid = require(Shared.NavGrid)

local S = Constants.STUDS
local TURRET = Shop.turret
local NAV_INFLATE = 0.45

local Structures = {}
Structures.__index = Structures

function Structures.new(W)
	local folder = Instance.new("Folder")
	folder.Name = "Structures"
	folder.Parent = Workspace
	return setmetatable({ W = W, list = {}, folder = folder, near = {} }, Structures)
end

function Structures.isStructureCollider(_self, c): boolean
	return type(c.owner) == "table" and c.owner.isStructure == true
end

function Structures.countFor(self, ps, stype: string): number
	local n = 0
	for _, s in self.list do
		if s.owner == ps and s.type == stype and not s.temporary then
			n += 1
		end
	end
	return n
end

function Structures.missingHpFor(self, ps): number
	local total = 0
	for _, s in self.list do
		if s.owner == ps then
			total += s.maxHp - s.hp
		end
	end
	return total
end

function Structures.repairFor(self, ps)
	for _, s in self.list do
		if s.owner == ps then
			s.hp = s.maxHp
			self:updateLook(s)
		end
	end
end

function Structures.clear(self)
	for _, s in table.clone(self.list) do
		self:remove(s, false)
	end
	self.W.rebuildNav()
end

-- Half extents of a footprint for a type and rotation.
function Structures.footprint(_self, stype: string, rotated: boolean): (number, number)
	local fp = Shop.structures[stype].footprint
	if rotated then
		return fp[2] / 2, fp[1] / 2
	end
	return fp[1] / 2, fp[2] / 2
end

function Structures.snap(self, stype: string, rotated: boolean, x: number, z: number): (number, number)
	local hw, hd = self:footprint(stype, rotated)
	local sx = if (hw * 2) % 2 == 0 then math.floor(x + 0.5) else math.floor(x) + 0.5
	local sz = if (hd * 2) % 2 == 0 then math.floor(z + 0.5) else math.floor(z) + 0.5
	return sx, sz
end

-- Flood fill: every standing player must still reach at least one spawn.
function Structures.keepsPathsOpen(self, minX: number, minZ: number, maxX: number, maxZ: number): boolean
	local W = self.W
	local g = W.nav
	local blocked = table.create(g.size, 0)
	for i = 1, g.size do
		if g.cells[i] ~= NavGrid.FREE then
			blocked[i] = 1
		end
	end
	for r = math.max(0, g:row(minZ - NAV_INFLATE)), math.min(g.rows - 1, g:row(maxZ + NAV_INFLATE)) do
		for c = math.max(0, g:col(minX - NAV_INFLATE)), math.min(g.cols - 1, g:col(maxX + NAV_INFLATE)) do
			blocked[r * g.cols + c + 1] = 1
		end
	end
	for _, ps in W.players:targets() do
		local seen = table.clone(blocked)
		local start = g:indexAt(ps.x, ps.z)
		seen[start] = 2
		local queue = { start }
		local head = 1
		while head <= #queue do
			local i = queue[head]
			head += 1
			local c = (i - 1) % g.cols
			local r = (i - 1 - c) // g.cols
			for k = 1, 4 do
				local n = if k == 1 and c > 0
					then i - 1
					elseif k == 2 and c < g.cols - 1 then i + 1
					elseif k == 3 and r > 0 then i - g.cols
					elseif k == 4 and r < g.rows - 1 then i + g.cols
					else -1
				if n > 0 and seen[n] == 0 then
					seen[n] = 2
					table.insert(queue, n)
				end
			end
		end
		local reaches = false
		for _, sp in W.spawns do
			if seen[g:indexAt(sp.x, sp.z)] == 2 then
				reaches = true
				break
			end
		end
		if not reaches then
			return false
		end
	end
	return true
end

function Structures.canPlace(
	self,
	ps,
	stype: string,
	rotated: boolean,
	x: number,
	z: number,
	ignoreLimit: boolean?
): (boolean, string?)
	local W = self.W
	local def = Shop.structures[stype]
	if not def then
		return false, "Unknown structure"
	end
	local hw, hd = self:footprint(stype, rotated)
	local limit = Constants.ARENA_HALF - 1.5
	if math.abs(x) + hw > limit or math.abs(z) + hd > limit then
		return false, "Out of bounds"
	end
	if W.collision:overlapsRect(x - hw - 0.1, z - hd - 0.1, x + hw + 0.1, z + hd + 0.1) then
		return false, "Blocked"
	end
	for _, other in W.players:list() do
		if other.x > x - hw - 0.5 and other.x < x + hw + 0.5 and other.z > z - hd - 0.5 and other.z < z + hd + 0.5 then
			return false, "A player is standing there"
		end
	end
	if not ignoreLimit and self:countFor(ps, stype) >= def.maxCount then
		return false, "Limit reached"
	end
	if not self:keepsPathsOpen(x - hw, z - hd, x + hw, z + hd) then
		return false, "That would seal someone in"
	end
	return true, nil
end

local function part(props): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function buildBarricade(model: Model, cf: CFrame)
	for _, x in { -1.3, 0, 1.3 } do
		part({
			Size = Vector3.new(0.18, 1.2, 0.18) * S,
			CFrame = cf * CFrame.new(x * S, 0.6 * S, 0),
			Color = Color3.fromHex("#4f3a26"),
			Material = Enum.Material.Wood,
		}).Parent =
			model
	end
	for i = 0, 2 do
		part({
			Size = Vector3.new(2.95, 0.28, 0.12) * S,
			CFrame = cf * CFrame.new(0, (0.3 + i * 0.36) * S, 0.08 * S) * CFrame.Angles(0, 0, (i - 1) * 0.03),
			Color = Color3.fromHex(if i % 2 == 1 then "#8a6238" else "#7a5634"),
			Material = Visuals.enum(Enum.Material.WoodPlanks),
		}).Parent =
			model
	end
	for i = 0, 4 do
		local spike = part({
			Size = Vector3.new(0.12, 0.6, 0.12) * S,
			CFrame = cf * CFrame.new((-1.2 + i * 0.6) * S, 0.75 * S, -0.3 * S) * CFrame.Angles(-1.1, 0, 0),
			Color = Color3.fromHex("#b8a888"),
			Material = Enum.Material.Wood,
		})
		spike.Parent = model
	end
end

local function buildTurret(model: Model, cf: CFrame): (BasePart, BasePart, BasePart)
	part({
		Size = Vector3.new(1.5, 0.12, 1.5) * S,
		CFrame = cf * CFrame.new(0, 0.06 * S, 0),
		Color = Color3.fromHex("#3a3d42"),
		Material = Enum.Material.Metal,
	}).Parent =
		model
	local column = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 0.75, 0.75) * S,
		CFrame = cf * CFrame.new(0, 0.45 * S, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = Color3.fromHex("#4a4f56"),
		Material = Enum.Material.Metal,
	})
	column.Parent = model
	local head = part({
		Name = "Head",
		Size = Vector3.new(0.62, 0.38, 0.7) * S,
		CFrame = cf * CFrame.new(0, 0.97 * S, 0),
		Color = Color3.fromHex("#56606a"),
		Material = Enum.Material.Metal,
	})
	head.Parent = model
	local barrel = part({
		Name = "Barrel",
		Size = Vector3.new(0.14, 0.14, 0.8) * S,
		CFrame = head.CFrame * CFrame.new(0, 0, -0.6 * S),
		Color = Color3.fromHex("#1f2124"),
		Material = Enum.Material.Metal,
	})
	barrel.Parent = model
	local eye = part({
		Size = Vector3.new(0.16, 0.12, 0.05) * S,
		CFrame = head.CFrame * CFrame.new(0, 0.1 * S, -0.36 * S),
		Color = Color3.fromHex("#ff3a2a"),
		Material = Enum.Material.Neon,
	})
	eye.Parent = model
	return head, barrel, eye
end

function Structures.place(self, ps, stype: string, rotated: boolean, x: number, z: number)
	local W = self.W
	local def = Shop.structures[stype]
	local hw, hd = self:footprint(stype, rotated)
	local s = {
		isStructure = true,
		type = stype,
		owner = ps,
		x = x,
		z = z,
		hw = hw,
		hd = hd,
		hp = def.hp,
		maxHp = def.hp,
		headAngle = 0,
		cooldown = 0,
		retarget = 0,
		target = nil,
		collider = nil,
		model = nil :: Model?,
		head = nil :: BasePart?,
		headParts = {},
	}
	s.collider = W.collision:addBox(x - hw, z - hd, x + hw, z + hd, if stype == "turret" then 1.0 else 1.2, s)

	local model = Instance.new("Model")
	model.Name = def.name
	local cf = CFrame.new(x * S, 0, z * S) * CFrame.Angles(0, if rotated then math.pi / 2 else 0, 0)
	-- Imported meshes when available (bottom on the ground), else part-built models.
	if stype == "barricade" then
		local mesh = MeshLibrary.clone("Barricade")
		if mesh then
			mesh.CFrame = cf * CFrame.new(0, mesh.Size.Y / 2, 0)
			mesh.Parent = model
		else
			buildBarricade(model, cf)
		end
	else
		local base = MeshLibrary.clone("TurretBase")
		local headMesh = MeshLibrary.clone("TurretHead")
		if base and headMesh then
			base.CFrame = cf * CFrame.new(0, base.Size.Y / 2, 0)
			base.Parent = model
			headMesh.Name = "Head"
			headMesh.CFrame = CFrame.new(x * S, 0.97 * S, z * S) * CFrame.Angles(0, math.pi, 0)
			headMesh.Parent = model
			s.head = headMesh
			s.headParts = { headMesh }
		else
			local head, barrel, eye = buildTurret(model, cf)
			s.head = head
			s.headParts = { head, barrel, eye }
		end
	end
	-- Solid block so characters can't walk through.
	local blocker = part({
		Name = "Blocker",
		Size = Vector3.new(hw * 2, 1.2, hd * 2) * S,
		CFrame = CFrame.new(x * S, 0.6 * S, z * S),
		Transparency = 1,
		CanCollide = true,
	})
	blocker.Parent = model
	model:SetAttribute("HP", s.hp)
	model:SetAttribute("MaxHP", s.maxHp)
	model:SetAttribute("Owner", ps.player.DisplayName)
	model.Parent = self.folder
	s.model = model
	table.insert(self.list, s)
	W.rebuildNav()
	W.fx("build", { x = x, z = z })
	return s
end

function Structures.updateLook(_self, s)
	if s.model then
		s.model:SetAttribute("HP", math.max(0, math.floor(s.hp + 0.5)))
	end
end

function Structures.remove(self, s, rebuild: boolean)
	local i = table.find(self.list, s)
	if not i then
		return
	end
	table.remove(self.list, i)
	if s.collider then
		self.W.collision:remove(s.collider)
	end
	if s.model then
		s.model:Destroy()
	end
	if rebuild then
		self.W.rebuildNav()
	end
end

function Structures.damage(self, s, amount: number)
	if s.hp <= 0 or not table.find(self.list, s) then
		return
	end
	s.hp -= amount
	self:updateLook(s)
	self.W.fx("structureHit", { x = s.x, z = s.z })
	if s.hp <= 0 then
		self.W.fx("structureBreak", { x = s.x, z = s.z })
		self.W.notifyAll(`{Shop.structures[s.type].name} destroyed!`, "bad")
		self:remove(s, true)
	end
end

function Structures.damageInRadius(self, x: number, z: number, radius: number, amount: number)
	for _, s in table.clone(self.list) do
		local dx = math.max(math.abs(s.x - x) - s.hw, 0)
		local dz = math.max(math.abs(s.z - z) - s.hd, 0)
		if dx * dx + dz * dz < radius * radius then
			self:damage(s, amount)
		end
	end
end

function Structures.findTarget(self, s)
	local W = self.W
	local best, bestD = nil, TURRET.range * TURRET.range
	for _, z in W.zombies.list do
		if not z.dying and z.state ~= "spawning" then
			local dx, dz = z.x - s.x, z.z - s.z
			local d2 = dx * dx + dz * dz
			if d2 < bestD then
				local d = math.sqrt(d2)
				local ox, oz = s.x + dx / d * 1.15, s.z + dz / d * 1.15
				local _, hit =
					W.collision:raycast(ox, oz, dx / d, dz / d, math.max(0, d - 1.15), Constants.BULLET_HEIGHT)
				if not hit then
					best, bestD = z, d2
				end
			end
		end
	end
	return best
end

function Structures.update(self, dt: number)
	local W = self.W
	-- Temporary structures (the Scrap Drone gadget) expire.
	local now = os.clock()
	for _, s in table.clone(self.list) do
		if s.expires and now >= s.expires then
			W.fx("structureBreak", { x = s.x, z = s.z })
			self:remove(s, true)
		end
	end
	for _, s in self.list do
		if s.type == "turret" and s.head then
			s.cooldown -= dt
			s.retarget -= dt
			if s.retarget <= 0 or not s.target or s.target.dying then
				s.retarget = 0.25
				s.target = self:findTarget(s)
			end
			local t = s.target
			local prevAngle = s.headAngle
			if t then
				local want = math.atan2(t.x - s.x, t.z - s.z)
				s.headAngle = MathUtil.angleDamp(s.headAngle, want, TURRET.turnSpeed, dt)
				if s.cooldown <= 0 and math.abs(MathUtil.wrapAngle(want - s.headAngle)) < 0.15 then
					s.cooldown = 1 / TURRET.fireRate
					local dx, dz = math.sin(s.headAngle), math.cos(s.headAngle)
					local ox, oz = s.x + dx * 1.15, s.z + dz * 1.15
					local _, ex, ez = W.weapons:hitscan({
						ox = ox,
						oz = oz,
						dirX = dx,
						dirZ = dz,
						range = TURRET.range,
						damage = TURRET.damage * (1 + W.waves.wave * 0.04),
						pierce = 0,
						knock = 1.2,
						source = "turret",
						attacker = s.owner,
					})
					W.remotes.Shot:FireAllClients(0, "turret", ox, oz, { { ex, ez } })
				end
			else
				s.headAngle += dt * 0.6
			end
			if math.abs(s.headAngle - prevAngle) > 1e-3 then
				-- Rotate the head parts about the column (turret faces -Z at angle pi).
				local pivot = CFrame.new(s.x * S, 0.97 * S, s.z * S)
				local rot = CFrame.Angles(0, s.headAngle + math.pi, 0)
				local head = s.head :: BasePart
				head.CFrame = pivot * rot
				local barrel = s.headParts[2]
				if barrel then
					barrel.CFrame = head.CFrame * CFrame.new(0, 0, -0.6 * S)
				end
				local eye = s.headParts[3]
				if eye then
					eye.CFrame = head.CFrame * CFrame.new(0, 0.1 * S, -0.36 * S)
				end
			end
		end
	end
end

return Structures
