--[[
	Instantiates the town square from the shared ArenaLayout: decorative parts
	(no collision), invisible collision parts that exactly match the gameplay
	colliders, street lamp lights and the player spawn.
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Constants = require(Shared.Config.Constants)
local MeshLibrary = require(Shared.MeshLibrary)
local Visuals = require(Shared.Config.Visuals)

local S = Constants.STUDS

local ArenaBuilder = {}

local MATERIALS = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Asphalt = Enum.Material.Asphalt,
	Concrete = Enum.Material.Concrete,
	Slate = Enum.Material.Slate,
	Cobblestone = Enum.Material.Cobblestone,
	Ground = Enum.Material.Ground,
	Brick = Enum.Material.Brick,
	Metal = Enum.Material.Metal,
	Wood = Enum.Material.Wood,
	WoodPlanks = Enum.Material.WoodPlanks,
	Fabric = Enum.Material.Fabric,
	Glass = Enum.Material.Glass,
	Neon = Enum.Material.Neon,
	Grass = Enum.Material.Grass,
	Rubber = Enum.Material.Rubber,
	Marble = Enum.Material.Marble,
	Cardboard = Enum.Material.Cardboard,
	CorrodedMetal = Enum.Material.CorrodedMetal,
}

export type Arena = {
	layout: ArenaLayout.Layout,
	folder: Folder,
	glowParts: { BasePart },
	lampLights: { PointLight },
}

local function pieceCFrame(piece: ArenaLayout.Piece): CFrame
	return CFrame.new(piece.pos[1] * S, piece.pos[2] * S, piece.pos[3] * S)
		* CFrame.Angles(0, piece.gry, 0)
		* CFrame.fromEulerAnglesYXZ(piece.rot[1], piece.rot[2], piece.rot[3])
end

--[[
	Places an imported mesh for a prop. The mesh pivot is its bounding-box
	centre, so it goes at the centre of the block fallback's bounds measured in
	the prop's own frame (the generator models each prop to the same bounds).
]]
local function placePropMesh(prop: ArenaLayout.Prop, parts: { ArenaLayout.Piece }, parent: Instance)
	local mesh = MeshLibrary.clone(prop.name)
	if not mesh then
		return false
	end
	local frame = CFrame.new(prop.x * S, prop.y * S, prop.z * S) * CFrame.Angles(0, prop.ry, 0)
	local lo = Vector3.one * math.huge
	local hi = -lo
	for _, piece in parts do
		local cf = pieceCFrame(piece)
		local h = Vector3.new(piece.size[1], piece.size[2], piece.size[3]) * (S / 2)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = frame:PointToObjectSpace(cf:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)))
					lo = lo:Min(p)
					hi = hi:Max(p)
				end
			end
		end
	end
	local centre = if #parts > 0 then (lo + hi) / 2 else Vector3.new(0, mesh.Size.Y / 2, 0)
	mesh.CFrame = frame * CFrame.new(centre)
	mesh.CastShadow = true
	mesh.Parent = parent
	return true
end

-- Deterministic small brightness variation per piece (clean look only).
local function jitter(color: Color3, index: number, material: string): Color3
	if not Visuals.CLEAN_MATERIALS or material == "Neon" or material == "Glass" then
		return color
	end
	local h = ((index * 2654435761) % 1000) / 1000
	local k = (h - 0.5) * 2 * Visuals.COLOR_JITTER
	return if k > 0 then color:Lerp(Color3.new(1, 1, 1), k) else color:Lerp(Color3.new(0, 0, 0), -k)
end

local function makePart(piece: ArenaLayout.Piece, index: number): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = jitter(Color3.fromHex(piece.color), index, piece.material)
	p.Material = MATERIALS[Visuals.material(piece.material)] or Enum.Material.SmoothPlastic
	local sx, sy, sz = piece.size[1] * S, piece.size[2] * S, piece.size[3] * S
	local base = pieceCFrame(piece)
	if piece.shape == "Cylinder" then
		-- Roblox cylinders run along X; rotate so the axis is vertical.
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(sy, sx, sz)
		p.CFrame = base * CFrame.Angles(0, 0, math.pi / 2)
	elseif piece.shape == "Ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(sx, sx, sx)
		p.CFrame = base
	else
		p.Size = Vector3.new(math.max(sx, 0.05), math.max(sy, 0.05), math.max(sz, 0.05))
		p.CFrame = base
	end
	p.CastShadow = sy > 0.5
	return p
end

function ArenaBuilder.build(): Arena
	local layout = ArenaLayout.generate()
	local folder = Instance.new("Folder")
	folder.Name = "Arena"

	local visuals = Instance.new("Folder")
	visuals.Name = "Visuals"
	visuals.Parent = folder
	local glowParts = {}
	local ground: BasePart? = nil

	-- Props with an imported mesh replace their block pieces.
	local propPieces: { { ArenaLayout.Piece } } = {}
	for _, piece in layout.pieces do
		if piece.prop then
			local list = propPieces[piece.prop]
			if not list then
				list = {}
				propPieces[piece.prop] = list
			end
			table.insert(list, piece)
		end
	end
	local meshed: { [number]: boolean } = {}
	for index, prop in layout.props do
		meshed[index] = placePropMesh(prop, propPieces[index] or {}, visuals)
	end

	for i, piece in layout.pieces do
		if piece.prop and meshed[piece.prop] then
			continue
		end
		local p = makePart(piece, i)
		if piece.glow then
			table.insert(glowParts, p)
		end
		if i == 1 then
			ground = p
		end
		p.Parent = visuals
	end

	-- The ground (first piece) is the only visual part characters stand on.
	assert(ground, "arena layout has no ground")
	ground.CanCollide = true
	ground.CanQuery = true
	ground.Name = "Ground"

	-- Invisible collision that exactly matches the simulation's obstacles.
	local collision = Instance.new("Folder")
	collision.Name = "Collision"
	collision.Parent = folder
	for _, c in layout.colliders do
		local p = Instance.new("Part")
		p.Anchored = true
		p.Transparency = 1
		p.CanCollide = true
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		local height = math.max(c.height, 1.2) * S
		if c.kind == "box" then
			p.Size = Vector3.new((c.maxX - c.minX) * S, height, (c.maxZ - c.minZ) * S)
			p.CFrame = CFrame.new(c.x * S, height / 2, c.z * S)
		else
			p.Shape = Enum.PartType.Cylinder
			p.Size = Vector3.new(height, c.r * 2 * S, c.r * 2 * S)
			p.CFrame = CFrame.new(c.x * S, height / 2, c.z * S) * CFrame.Angles(0, 0, math.pi / 2)
		end
		p.Parent = collision
	end

	-- Street lamps: real lights that switch on as night falls.
	local lampLights = {}
	for _, l in layout.lamps do
		local holder = Instance.new("Part")
		holder.Anchored = true
		holder.Transparency = 1
		holder.CanCollide = false
		holder.CanQuery = false
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.Position = Vector3.new(l[1] * S, l[2] * S, l[3] * S)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 214, 150)
		light.Range = 36
		light.Brightness = 0
		light.Shadows = true
		light.Parent = holder
		holder.Parent = folder
		table.insert(lampLights, light)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.Duration = 0
	spawn.Size = Vector3.new(6, 1, 6)
	local ps = layout.playerSpawn
	spawn.Position = Vector3.new(ps[1] * S, 0.5, ps[3] * S)
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = folder

	folder.Parent = Workspace
	return { layout = layout, folder = folder, glowParts = glowParts, lampLights = lampLights }
end

-- Lamps and lit windows follow the day/night factor (0 day .. 1 night).
function ArenaBuilder.setNight(arena: Arena, night: number)
	local on = math.clamp((night - 0.25) / 0.75, 0, 1)
	for _, light in arena.lampLights do
		light.Brightness = on * 2.2
	end
	for _, p in arena.glowParts do
		p.Transparency = 0.6 * (1 - math.max(on, 0.25))
	end
end

return ArenaBuilder
