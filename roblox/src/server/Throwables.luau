--[[
	Thrown lures, landing at the aim point (stopping short of obstacles):
	  pipebomb - beeps loudly to lure every zombie in earshot, then explodes
	  flare    - burns for a while, setting nearby zombies alight
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Items = require(Shared.Config.Items)

local S = Constants.STUDS
local BOMB = Items.PIPEBOMB
local THROW_SPEED = 14
local FLARE = { seconds = 7, burnRadius = 2.6, burnDps = 14 }

local Throwables = {}
Throwables.__index = Throwables

function Throwables.new(W)
	local folder = Instance.new("Folder")
	folder.Name = "Throwables"
	folder.Parent = Workspace
	return setmetatable({ W = W, list = {}, folder = folder }, Throwables)
end

function Throwables.clear(self)
	for _, b in self.list do
		if b.part then
			b.part:Destroy()
		end
	end
	table.clear(self.list)
end

-- Throws a pipe bomb (or a flare) from the player toward (dirX, dirZ). Returns true if thrown.
function Throwables.throw(self, ps, dirX: number, dirZ: number, distance: number, kind: string?): boolean
	local W = self.W
	local len = math.sqrt(dirX * dirX + dirZ * dirZ)
	if len < 1e-3 or len ~= len then
		return false
	end
	dirX, dirZ = dirX / len, dirZ / len
	local dist = math.clamp(distance, 2, BOMB.range)
	-- Walk the throw line and land just before the first obstacle.
	local reach = dist
	local step = 0.25
	local d = step
	while d <= dist do
		if W.collision:overlapsCircle(ps.x + dirX * d, ps.z + dirZ * d, 0.2) then
			reach = math.max(0.5, d - step)
			break
		end
		d += step
	end
	local x1, z1 = ps.x + dirX * reach, ps.z + dirZ * reach
	local flight = reach / THROW_SPEED + 0.2
	W.fx("grenade", { x0 = ps.x, z0 = ps.z, x1 = x1, z1 = z1, duration = flight, silent = true })
	table.insert(self.list, {
		kind = kind or "pipebomb",
		x = x1,
		z = z1,
		t = 0,
		flight = flight,
		beep = 0,
		part = nil,
		light = nil,
		owner = ps,
	})
	-- Clients play the throw animation from this.
	if ps.player.Character then
		ps.player.Character:SetAttribute("ThrowAt", Workspace:GetServerTimeNow())
	end
	return true
end

local function makeFlare(x: number, z: number): (BasePart, PointLight)
	local body = Instance.new("Part")
	body.Name = "Flare"
	body.Size = Vector3.new(0.1, 0.1, 0.35) * S
	body.Color = Color3.fromRGB(255, 80, 60)
	body.Material = Enum.Material.Neon
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(x * S, 0.05 * S, z * S) * CFrame.Angles(0, math.random() * math.pi, 0)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 90, 60)
	light.Range = 22
	light.Brightness = 5
	light.Parent = body
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 120, 60)
	fire.Parent = body
	return body, light
end

local function makeBomb(x: number, z: number): (BasePart, PointLight)
	local body = Instance.new("Part")
	body.Name = "PipeBomb"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(0.45 * S, 0.14 * S, 0.14 * S)
	body.Color = Color3.fromRGB(92, 96, 100)
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.CanTouch = false
	body.CFrame = CFrame.new(x * S, 0.07 * S, z * S) * CFrame.Angles(0, math.random() * math.pi, 0)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 10
	light.Brightness = 0
	light.Parent = body
	return body, light
end

function Throwables.update(self, dt: number)
	local W = self.W
	for i = #self.list, 1, -1 do
		local b = self.list[i]
		b.t += dt
		if b.kind == "flare" then
			if b.t >= b.flight then
				if not b.part then
					b.part, b.light = makeFlare(b.x, b.z)
					b.part.Parent = self.folder
				end
				b.beep -= dt
				if b.beep <= 0 then
					b.beep = 0.5
					local near = {}
					local n = W.zombies:queryRadius(b.x, b.z, FLARE.burnRadius, near)
					for k = 1, n do
						W.combat:ignite(near[k], FLARE.burnDps, 2.5)
						near[k].lastAttacker = b.owner
					end
				end
			end
			if b.t >= b.flight + FLARE.seconds then
				table.remove(self.list, i)
				if b.part then
					b.part:Destroy()
				end
			end
			continue
		end
		if b.t >= b.flight then
			if not b.part then
				b.part, b.light = makeBomb(b.x, b.z)
				b.part.Parent = self.folder
			end
			b.beep -= dt
			if b.beep <= 0 then
				-- Beeps speed up as the fuse runs out.
				local left = b.flight + BOMB.fuse - b.t
				b.beep = if left > 1.5 then 0.5 else 0.2
				W.fx("beep", { x = b.x, z = b.z })
			end
			if b.light then
				b.light.Brightness = if b.beep > 0.12 then 0 else 4
				b.part.Color = if b.beep > 0.12 then Color3.fromRGB(92, 96, 100) else Color3.fromRGB(255, 70, 50)
			end
		end
		if b.t >= b.flight + BOMB.fuse then
			table.remove(self.list, i)
			if b.part then
				b.part:Destroy()
			end
			local owner = if b.owner and b.owner.player.Parent then b.owner else nil
			W.combat:explosion(
				b.x,
				b.z,
				BOMB.radius,
				BOMB.damage * (1 + W.waves.wave * 0.04),
				30,
				40,
				"pipebomb",
				owner
			)
		end
	end
end

return Throwables
