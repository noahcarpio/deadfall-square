--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Deterministic description of the abandoned town square (in metres), ported
	from the browser version's arena generator. Produces:
	  * pieces    - visual parts for ArenaBuilder (server) to instantiate
	  * colliders - gameplay obstacles (also built as invisible collision parts)
	  * spawns    - alley entrances zombies emerge from
	  * lamps     - street lamp light positions
	The south edge is a low fence so geometry never hides players from the
	top-down camera.
]]
local Rng = if script then require(script.Parent.Util.Rng) else require("./Util/Rng")
local Constants = if script then require(script.Parent.Config.Constants) else require("./Config/Constants")

export type Piece = {
	shape: "Block" | "Cylinder" | "Ball" | "Wedge",
	size: { number }, -- x, y, z (for Cylinder: diameter, height, diameter; vertical)
	pos: { number },
	gry: number, -- parent frame yaw
	rot: { number }, -- local euler (YXZ) rx, ry, rz
	color: string,
	material: string,
	glow: boolean?, -- lit window / lamp: brightens at night
	prop: number?, -- index into props: replaced by that prop's mesh when it's imported
}

-- A whole object (car, crate...) that has an imported-mesh version. `y` is the
-- height of its base; the mesh's local +Z matches the layout's local +Z.
export type Prop = { name: string, x: number, y: number, z: number, ry: number }

export type ColliderSpec = {
	kind: "box" | "circle",
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number,
	x: number,
	z: number,
	r: number,
	height: number,
}

export type Spawn = { x: number, z: number, dirX: number, dirZ: number }

export type Layout = {
	pieces: { Piece },
	colliders: { ColliderSpec },
	spawns: { Spawn },
	lamps: { { number } },
	props: { Prop },
	playerSpawn: { number },
}

local A = Constants.ARENA_HALF
local H = Constants.WORLD_HALF - 1

local PALETTE = { "#8a4b3c", "#a3714f", "#6f7a80", "#b59a72", "#5e6b5a", "#7d5a6b", "#9c8b6e", "#5a6578" }
local TRIM = "#3b3632"
local CONCRETE = "#8d8a84"
local WOOD = "#7a5634"
local DARK_WOOD = "#4f3a26"

local function generate(): Layout
	local rng = Rng.new(1337)
	local pieces: { Piece } = {}
	local colliders: { ColliderSpec } = {}
	local spawns: { Spawn } = {}
	local lamps: { { number } } = {}
	local props: { Prop } = {}
	local currentProp: number? = nil

	-- Parent frame stack: { x, z, ry }.
	local frame = { 0, 0, 0 }

	local function withFrame(x: number, z: number, ry: number, fn: () -> ())
		local saved = frame
		frame = { x, z, ry }
		fn()
		frame = saved
	end

	local function add(
		shape: "Block" | "Cylinder" | "Ball" | "Wedge",
		sx: number,
		sy: number,
		sz: number,
		color: string,
		material: string,
		lx: number,
		ly: number,
		lz: number,
		rx: number?,
		ry: number?,
		rz: number?,
		glow: boolean?
	)
		local c, s = math.cos(frame[3]), math.sin(frame[3])
		table.insert(pieces, {
			shape = shape,
			size = { sx, sy, sz },
			pos = { frame[1] + lx * c + lz * s, ly, frame[2] - lx * s + lz * c },
			gry = frame[3],
			rot = { rx or 0, ry or 0, rz or 0 },
			color = color,
			material = material,
			glow = glow,
			prop = currentProp,
		})
	end

	-- Records a mesh-replaceable prop; pieces added inside `fn` are its block fallback.
	local function prop(name: string, x: number, y: number, z: number, ry: number, fn: () -> ())
		table.insert(props, { name = name, x = x, y = y, z = z, ry = ry })
		currentProp = #props
		fn()
		currentProp = nil
	end

	local function box(sx, sy, sz, color, material, x, y, z, rx: number?, ry: number?, rz: number?, glow: boolean?)
		add("Block", sx, sy, sz, color, material, x, y, z, rx, ry, rz, glow)
	end

	local function cyl(d, h, color, material, x, y, z)
		add("Cylinder", d, h, d, color, material, x, y, z)
	end

	local function colBox(minX: number, minZ: number, maxX: number, maxZ: number, height: number)
		table.insert(colliders, {
			kind = "box",
			minX = minX,
			minZ = minZ,
			maxX = maxX,
			maxZ = maxZ,
			x = (minX + maxX) / 2,
			z = (minZ + maxZ) / 2,
			r = 0,
			height = height,
		})
	end

	local function colCircle(x: number, z: number, r: number, height: number)
		table.insert(colliders, {
			kind = "circle",
			minX = x - r,
			minZ = z - r,
			maxX = x + r,
			maxZ = z + r,
			x = x,
			z = z,
			r = r,
			height = height,
		})
	end

	-- Splits [from, to] into solid segments around gaps.
	local function segments(from: number, to: number, gaps: { { number } }): { { number } }
		local out = {}
		local cursor = from
		for _, g in gaps do
			if g[1] > cursor then
				table.insert(out, { cursor, g[1] })
			end
			cursor = math.max(cursor, g[2])
		end
		if to > cursor then
			table.insert(out, { cursor, to })
		end
		return out
	end

	------------------------------------------------------------- ground
	box(H * 2 + 2, 0.4, H * 2 + 2, "#3b3d40", "Asphalt", 0, -0.2, 0)
	-- Sidewalks along the building rows.
	box(A * 2, 0.06, 3, "#6b6862", "Concrete", 0, 0.03, -A + 1.5)
	box(3, 0.06, A * 2, "#6b6862", "Concrete", A - 1.5, 0.03, 0)
	box(3, 0.06, A * 2, "#6b6862", "Concrete", -A + 1.5, 0.03, 0)
	-- Cobblestone plaza with a stone rim.
	cyl(28.9, 0.08, "#8f8a83", "Slate", 0, 0.04, 0)
	cyl(28, 0.1, "#77706a", "Cobblestone", 0, 0.05, 0)
	-- Faded lane markings: dashed loop around the plaza.
	for i = -10, 10 do
		local t = i * 2.2
		box(1.2, 0.02, 0.15, "#c8b45a", "SmoothPlastic", t, 0.012, -22)
		box(1.2, 0.02, 0.15, "#c8b45a", "SmoothPlastic", t, 0.012, 22)
		box(0.15, 0.02, 1.2, "#c8b45a", "SmoothPlastic", -22, 0.012, t)
		box(0.15, 0.02, 1.2, "#c8b45a", "SmoothPlastic", 22, 0.012, t)
	end
	-- Crosswalks near the north alleys.
	for i = 0, 5 do
		box(0.4, 0.02, 4, "#d8d8cc", "SmoothPlastic", -16 + i * 0.7, 0.012, -29)
		box(0.4, 0.02, 4, "#d8d8cc", "SmoothPlastic", 14 + i * 0.7, 0.012, -29)
	end
	-- South vacant lot.
	box(H * 2, 0.05, H - A, "#5a4a37", "Ground", 0, 0.025, (A + H) / 2 + 0.3)

	------------------------------------------------------------- boundary
	colBox(-H - 3, -H - 3, H + 3, -H, 20)
	colBox(-H - 3, H, H + 3, H + 3, 20)
	colBox(-H - 3, -H - 3, -H, H + 3, 20)
	colBox(H, -H - 3, H + 3, H + 3, 20)

	------------------------------------------------------------- buildings
	local function building(a: number, b: number, side: string)
		local depth = H - A
		local width = b - a
		local height = math.floor(rng:range(2, 4) + 0.5) * 3 + rng:range(0, 0.8)
		local color = rng:pick(PALETTE)
		local mid = (a + b) / 2
		local cx, cz, ry
		if side == "north" then
			cx, cz, ry = mid, -A - depth / 2, 0
			colBox(a, -H, b, -A, height)
		elseif side == "east" then
			cx, cz, ry = A + depth / 2, mid, -math.pi / 2
			colBox(A, a, H, b, height)
		else
			cx, cz, ry = -A - depth / 2, mid, math.pi / 2
			colBox(-H, a, -A, b, height)
		end
		withFrame(cx, cz, ry, function()
			local front = depth / 2
			box(width - 0.1, height, depth, color, "Brick", 0, height / 2, 0)
			box(width - 0.1, 0.5, depth, TRIM, "Concrete", 0, height + 0.25, 0)
			box(width - 0.7, 0.2, depth - 0.6, "#4a4542", "Slate", 0, height + 0.55, 0)
			if rng:chance(0.6) then
				box(
					1.4,
					0.9,
					1.0,
					"#9a9ea3",
					"Metal",
					rng:range(-width / 3, width / 3),
					height + 0.95,
					rng:range(-depth / 4, depth / 4)
				)
			end
			box(width - 0.05, 0.25, 0.25, TRIM, "Concrete", 0, 3, front + 0.1)
			box(width - 0.05, 0.6, 0.2, "#2f2c2a", "Concrete", 0, 0.3, front + 0.05)
			local doorX = rng:range(-width / 2 + 1.5, width / 2 - 1.5)
			box(1.3, 2.3, 0.15, "#2a211b", "Wood", doorX, 1.15, front + 0.05)
			box(1.6, 0.2, 0.25, TRIM, "Concrete", doorX, 2.4, front + 0.1)
			if rng:chance(0.55) then
				local stripe = rng:pick({ "#7e2b2b", "#2b5a7e", "#2f6b3d", "#8a6d2b" })
				local aw = math.min(width - 1, rng:range(3, 6))
				box(
					aw,
					0.12,
					1.4,
					stripe,
					"Fabric",
					rng:range(-(width - aw) / 2, (width - aw) / 2),
					2.85,
					front + 0.7,
					0.35
				)
			end
			local shopW = math.min(width - 3.5, 3.2)
			if shopW > 1.2 then
				local sx = if doorX > 0 then doorX - 2.6 else doorX + 2.6
				if math.abs(sx) + shopW / 2 < width / 2 - 0.3 then
					box(shopW + 0.3, 1.6, 0.12, TRIM, "Concrete", sx, 1.45, front + 0.04)
					box(shopW, 1.3, 0.1, "#1c2733", "Glass", sx, 1.45, front + 0.09)
				end
			end
			local floors = height // 3
			local cols = math.max(1, (width - 1) // 2.2)
			local spacing = (width - 1) / cols
			for f = 1, floors - 1 do
				for c = 0, cols - 1 do
					local wx = -width / 2 + 0.5 + spacing * (c + 0.5)
					local wy = f * 3 + 1.4
					if rng:chance(0.12) then
						box(1.1, 1.5, 0.08, "#4a3826", "Wood", wx, wy, front + 0.05)
						box(1.3, 0.18, 0.1, WOOD, "WoodPlanks", wx, wy + 0.25, front + 0.1, 0, 0, rng:range(-0.4, 0.4))
					else
						box(1.3, 1.7, 0.1, TRIM, "Concrete", wx, wy, front + 0.02)
						box(1.4, 0.12, 0.3, TRIM, "Concrete", wx, wy - 0.9, front + 0.12)
						if rng:chance(0.3) then
							box(
								1.05,
								1.45,
								0.06,
								rng:pick({ "#ffd28a", "#ffc070", "#ffe3b0" }),
								"Neon",
								wx,
								wy,
								front + 0.08,
								0,
								0,
								0,
								true
							)
						else
							box(1.05, 1.45, 0.06, "#1b2530", "Glass", wx, wy, front + 0.08)
						end
					end
				end
			end
		end)
	end

	local function buildingRow(a: number, b: number, side: string)
		local cursor = a
		while b - cursor > 0.5 do
			local w = rng:range(6, 11)
			if b - cursor - w < 4 then
				w = b - cursor
			end
			building(cursor, cursor + w, side)
			cursor += w
		end
	end

	local northGaps = { { -16, -12 }, { 14, 18 } }
	local eastGaps = { { -12, -8 }, { 18, 22 } }
	local westGaps = { { -24, -20 }, { 6, 10 } }
	local southGaps = { { -20, -16 }, { 10, 14 } }

	for _, s in segments(-H, H, northGaps) do
		buildingRow(s[1], s[2], "north")
	end
	for _, s in segments(-A, A, eastGaps) do
		buildingRow(s[1], s[2], "east")
	end
	for _, s in segments(-A, A, westGaps) do
		buildingRow(s[1], s[2], "west")
	end

	for _, g in northGaps do
		table.insert(spawns, { x = (g[1] + g[2]) / 2, z = -H + 3, dirX = 0, dirZ = 1 })
	end
	for _, g in eastGaps do
		table.insert(spawns, { x = H - 3, z = (g[1] + g[2]) / 2, dirX = -1, dirZ = 0 })
	end
	for _, g in westGaps do
		table.insert(spawns, { x = -H + 3, z = (g[1] + g[2]) / 2, dirX = 1, dirZ = 0 })
	end
	for _, g in southGaps do
		table.insert(spawns, { x = (g[1] + g[2]) / 2, z = H - 3, dirX = 0, dirZ = -1 })
	end

	-- Tall wooden fences capping the building alleys.
	local function fenceCap(cx: number, cz: number, len: number, ry: number)
		withFrame(cx, cz, ry, function()
			local planks = math.floor(len / 0.35 + 0.5)
			for i = 0, planks - 1 do
				local x = -len / 2 + (i + 0.5) * (len / planks)
				box(
					len / planks - 0.04,
					3 + rng:range(-0.3, 0.3),
					0.15,
					if i % 2 == 1 then WOOD else DARK_WOOD,
					"WoodPlanks",
					x,
					1.5,
					0
				)
			end
		end)
	end
	for _, g in northGaps do
		fenceCap((g[1] + g[2]) / 2, -H + 0.75, g[2] - g[1], 0)
	end
	for _, g in eastGaps do
		fenceCap(H - 0.75, (g[1] + g[2]) / 2, g[2] - g[1], math.pi / 2)
	end
	for _, g in westGaps do
		fenceCap(-H + 0.75, (g[1] + g[2]) / 2, g[2] - g[1], math.pi / 2)
	end

	-- South wall: low concrete with chain-link fence.
	for _, seg in segments(-A, A, southGaps) do
		local a, b = seg[1], seg[2]
		local len = b - a
		local cx = (a + b) / 2
		box(len, 1.1, 0.6, CONCRETE, "Concrete", cx, 0.55, A + 0.3)
		box(len, 0.12, 0.7, "#5f5c58", "Concrete", cx, 1.16, A + 0.3)
		local posts = math.max(2, math.floor(len / 3 + 0.5) + 1)
		for i = 0, posts - 1 do
			cyl(0.12, 1.8, "#7c8288", "Metal", a + i * len / (posts - 1), 2.0, A + 0.3)
		end
		box(len, 0.06, 0.06, "#7c8288", "Metal", cx, 2.85, A + 0.3)
		for y = 1.4, 2.6, 0.35 do
			box(len, 0.025, 0.025, "#5d6369", "Metal", cx, y, A + 0.3)
		end
		colBox(a, A, b, A + 0.6, 2.9)
	end

	------------------------------------------------------------- props
	local function car(name: string, x: number, z: number, ry: number, color: string, burnt: boolean)
		local body = if burnt then "#2e2a27" else color
		local glass = if burnt then "#1a1817" else "#24323d"
		prop(name, x, 0, z, ry, function()
			withFrame(x, z, ry, function()
			local tilt = rng:range(-0.04, 0.04)
			box(1.9, 0.75, 4.3, body, "Metal", 0, 0.7, 0, 0, 0, tilt)
			box(1.7, 0.65, 2.2, body, "Metal", 0, 1.38, -0.2, 0, 0, tilt)
			box(1.72, 0.5, 2.0, glass, "Glass", 0, 1.38, -0.2, 0, 0, tilt)
			box(1.92, 0.12, 4.32, "#1f1f1f", "SmoothPlastic", 0, 0.38, 0)
			box(0.35, 0.15, 0.05, if burnt then "#2a2725" else "#f4e7b0", "Neon", 0.6, 0.85, 2.16)
			box(0.35, 0.15, 0.05, if burnt then "#2a2725" else "#f4e7b0", "Neon", -0.6, 0.85, 2.16)
			box(0.35, 0.15, 0.05, "#6b1d1d", "SmoothPlastic", 0.6, 0.85, -2.16)
			box(0.35, 0.15, 0.05, "#6b1d1d", "SmoothPlastic", -0.6, 0.85, -2.16)
			for _, w in { { -0.95, 1.4 }, { 0.95, 1.4 }, { -0.95, -1.4 }, { 0.95, -1.4 } } do
				box(0.28, 0.76, 0.76, "#161616", "Rubber", w[1], 0.38, w[2])
			end
			end)
		end)
		local along = math.abs(math.sin(ry)) > 0.5
		local hw = if along then 2.2 else 1.0
		local hd = if along then 1.0 else 2.2
		colBox(x - hw, z - hd, x + hw, z + hd, if burnt then 1.2 else 1.7)
	end

	local function lamp(x: number, z: number)
		cyl(0.5, 0.4, "#2b2e31", "Metal", x, 0.2, z)
		cyl(0.18, 4.2, "#2b2e31", "Metal", x, 2.3, z)
		box(0.9, 0.08, 0.08, "#2b2e31", "Metal", x + 0.35, 4.35, z)
		box(0.5, 0.25, 0.5, "#2b2e31", "Metal", x + 0.75, 4.25, z)
		box(0.3, 0.12, 0.3, "#fff3c4", "Neon", x + 0.75, 4.08, z, 0, 0, 0, true)
		table.insert(lamps, { x + 0.75, 4.0, z })
		colCircle(x, z, 0.25, 4.4)
	end

	local function bench(x: number, z: number, ry: number)
		prop("Bench", x, 0, z, ry, function()
			withFrame(x, z, ry, function()
				box(2.0, 0.1, 0.55, WOOD, "Wood", 0, 0.5, 0)
				box(2.0, 0.45, 0.08, WOOD, "Wood", 0, 0.85, -0.25, -0.15)
				box(0.1, 0.5, 0.5, "#2b2e31", "Metal", -0.85, 0.25, 0)
				box(0.1, 0.5, 0.5, "#2b2e31", "Metal", 0.85, 0.25, 0)
			end)
		end)
		colCircle(x, z, 0.6, 0.9)
	end

	local function tree(x: number, z: number)
		box(2.2, 0.6, 2.2, "#77716a", "Concrete", x, 0.3, z)
		box(1.9, 0.1, 1.9, "#3d2f22", "Ground", x, 0.62, z)
		cyl(0.4, 2.2, "#4b3727", "Wood", x, 1.7, z)
		local dead = rng:chance(0.4)
		add("Ball", 3, 3, 3, if dead then "#6b5a3c" else "#3f5a35", "Grass", x, 3.4, z)
		add("Ball", 2, 2, 2, if dead then "#5d4d33" else "#4a6a3e", "Grass", x + 0.6, 4.3, z - 0.3)
		colCircle(x, z, 1.2, 4.5)
	end

	local function crates(x: number, z: number)
		local n = rng:int(2, 4)
		for i = 0, n - 1 do
			local cx = x + (i % 2) * 1.25 - 0.6
			local cz = z + (i // 2) * 1.25 - 0.6
			local levels = if rng:chance(0.4) then 2 else 1
			for l = 0, levels - 1 do
				local rot = rng:range(-0.15, 0.15)
				local y = 0.575 + l * 1.15
				prop("Crate", cx, l * 1.15, cz, rot, function()
					box(1.15, 1.15, 1.15, if l == 0 then "#8a6238" else "#9a7144", "WoodPlanks", cx, y, cz, 0, rot)
				end)
			end
			colBox(cx - 0.6, cz - 0.6, cx + 0.6, cz + 0.6, levels * 1.15)
		end
	end

	local function fence(x0: number, z0: number, x1: number, z1: number)
		local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local ry = math.atan2(-(z1 - z0), x1 - x0)
		withFrame((x0 + x1) / 2, (z0 + z1) / 2, ry, function()
			local posts = math.max(2, math.floor(len / 1.5 + 0.5) + 1)
			for i = 0, posts - 1 do
				box(0.15, 1.25, 0.15, DARK_WOOD, "Wood", -len / 2 + i * len / (posts - 1), 0.62, 0)
			end
			box(len, 0.14, 0.08, WOOD, "WoodPlanks", 0, 0.95, 0)
			box(len, 0.14, 0.08, WOOD, "WoodPlanks", 0, 0.45, 0)
		end)
		colBox(math.min(x0, x1) - 0.15, math.min(z0, z1) - 0.15, math.max(x0, x1) + 0.15, math.max(z0, z1) + 0.15, 1.2)
	end

	local function sandbags(x: number, z: number, ry: number)
		local c, s = math.cos(ry), math.sin(ry)
		withFrame(x, z, ry, function()
			for row = 0, 2 do
				for i = 0, 5 do
					local a = -0.9 + (i / 5) * 1.8
					local bx = math.sin(a) * 3 + (row % 2) * 0.12
					local bz = -math.cos(a) * 3 + 2.4
					box(
						1.0,
						0.36,
						0.6,
						if row % 2 == 1 then "#8c7c5c" else "#7d6e50",
						"Fabric",
						bx,
						0.18 + row * 0.27,
						bz,
						0,
						-a
					)
				end
			end
		end)
		for i = 0, 5 do
			local a = -0.9 + (i / 5) * 1.8
			local lx = math.sin(a) * 3
			local lz = -math.cos(a) * 3 + 2.4
			colCircle(x + lx * c + lz * s, z - lx * s + lz * c, 0.55, 0.9)
		end
	end

	local function barrier(x: number, z: number, ry: number)
		prop("Barrier", x, 0, z, ry, function()
			withFrame(x, z, ry, function()
				box(3.0, 0.35, 0.8, CONCRETE, "Concrete", 0, 0.18, 0)
				box(3.0, 0.65, 0.35, CONCRETE, "Concrete", 0, 0.67, 0)
				box(3.0, 0.1, 0.36, "#c9a227", "SmoothPlastic", 0, 0.9, 0)
			end)
		end)
		local along = math.abs(math.sin(ry)) > 0.5
		local hw = if along then 0.4 else 1.5
		local hd = if along then 1.5 else 0.4
		colBox(x - hw, z - hd, x + hw, z + hd, 1.0)
	end

	local function dumpster(x: number, z: number, ry: number)
		prop("Dumpster", x, 0, z, ry, function()
			withFrame(x, z, ry, function()
				box(2.4, 1.3, 1.3, "#2f5a3a", "Metal", 0, 0.75, 0)
				box(2.45, 0.1, 1.35, "#24452d", "Metal", 0, 1.42, 0.05, 0, 0.12)
			end)
		end)
		local along = math.abs(math.sin(ry)) > 0.5
		local hw = if along then 0.7 else 1.25
		local hd = if along then 1.25 else 0.7
		colBox(x - hw, z - hd, x + hw, z + hd, 1.5)
	end

	local BARREL_MESHES = { ["#a33a2a"] = "Barrel_red", ["#c49a2a"] = "Barrel_yellow", ["#2a6aa3"] = "Barrel_blue", ["#4a7a3a"] = "Barrel_green" }

	local function barrel(x: number, z: number, color: string)
		prop(BARREL_MESHES[color] or "Barrel_red", x, 0, z, 0, function()
			cyl(0.84, 1.1, color, "Metal", x, 0.55, z)
			cyl(0.88, 0.08, "#2b2b2b", "Metal", x, 0.3, z)
			cyl(0.88, 0.08, "#2b2b2b", "Metal", x, 0.8, z)
		end)
		colCircle(x, z, 0.45, 1.1)
	end

	-- Fountain with statue.
	cyl(7.2, 0.7, "#8f8a83", "Concrete", 0, 0.35, 0)
	cyl(6.0, 0.2, "#2f4f57", "Glass", 0, 0.62, 0)
	cyl(2.0, 1.2, "#7d7872", "Concrete", 0, 1.2, 0)
	cyl(2.8, 0.25, "#8f8a83", "Concrete", 0, 1.9, 0)
	box(0.7, 1.0, 0.45, "#5c7a6a", "Marble", 0, 2.6, 0)
	box(0.55, 0.5, 0.4, "#5c7a6a", "Marble", 0, 3.35, 0)
	box(0.18, 1.0, 0.18, "#5c7a6a", "Marble", 0.45, 3.4, 0, 0, 0, -0.3)
	colCircle(0, 0, 3.6, 0.75)
	colCircle(0, 0, 1.1, 4)

	for _, p in
		{ { -9, -9 }, { 9, -9 }, { -9, 9 }, { 9, 9 }, { -26, -30 }, { 26, -30 }, { -30, 24 }, { 30, 30 }, { 0, -30 } }
	do
		lamp(p[1], p[2])
	end
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		bench(math.cos(a) * 6.3, math.sin(a) * 6.3, -a + math.pi / 2)
	end
	for _, p in { { -24, 0 }, { 24, 8 }, { -4, -16 }, { 6, 28 }, { -30, -30 } } do
		tree(p[1], p[2])
	end
	local carColors = { "#7a2f2a", "#2f4f6e", "#5d6a3a", "#8a8378", "#3d3a46", "#9a6b2e", "#25544f" }
	local cars = {
		{ -14, -8, 0 },
		{ 11, -15, math.pi / 2 },
		{ 18, 11, 0 },
		{ -21, 16, math.pi / 2 },
		{ 5, 21, 0 },
		{ -8, -25, 0 },
		{ 28, -24, math.pi / 2 },
		{ -29, -7, math.pi / 2 },
	}
	for i, c in cars do
		local colorIndex = (i - 1) % #carColors + 1
		car(`Car_{colorIndex}`, c[1], c[2], c[3], carColors[colorIndex], false)
	end
	car("Car_burnt", -34, A + 6, 0, "#3a3530", true)
	car("Car_burnt", 30, A + 7, 0.15, "#3c3a38", true)

	-- Crashed bus.
	prop("Bus", 25, 0, -3, 0, function()
		withFrame(25, -3, 0, function()
			box(2.6, 2.4, 10, "#c48a2a", "Metal", 0, 1.55, 0, 0, 0, 0.05)
			box(2.62, 0.5, 10.02, "#3a3632", "Metal", 0, 0.55, 0)
			box(2.64, 0.9, 8.6, "#22303a", "Glass", 0, 2.0, -0.3, 0, 0, 0.05)
			for _, wz in { 3.4, -3.4 } do
				box(0.35, 1, 1, "#161616", "Rubber", -1.25, 0.5, wz)
				box(0.35, 1, 1, "#161616", "Rubber", 1.25, 0.5, wz)
			end
		end)
	end)
	colBox(25 - 1.35, -3 - 5.05, 25 + 1.35, -3 + 5.05, 2.8)

	for _, p in { { -27, -20 }, { 29, 23 }, { -11, 13 }, { 14, -29 }, { -30, 29 }, { 32, -8 }, { -4, 31 } } do
		crates(p[1], p[2])
	end
	fence(-31, 10, -22, 10)
	fence(19, 27, 19, 33)
	fence(-6, -33, 3, -33)
	fence(31, 13, 35, 13)
	sandbags(-18, -29, 0)
	sandbags(13, 30, math.pi)
	sandbags(31, 0, -math.pi / 2)
	barrier(-2, 15, 0)
	barrier(15, -6, math.pi / 2)
	barrier(-17, -1, math.pi / 2)
	dumpster(33, -16, math.pi / 2)
	dumpster(-33, 19, math.pi / 2)
	local barrels: { { x: number, z: number, color: string } } = {
		{ x = 31, z = 4, color = "#a33a2a" },
		{ x = -31, z = -14, color = "#c49a2a" },
		{ x = 7, z = -33, color = "#2a6aa3" },
		{ x = -13, z = 32, color = "#a33a2a" },
		{ x = 22, z = -32, color = "#c49a2a" },
		{ x = -24, z = 30, color = "#4a7a3a" },
	}
	for _, b in barrels do
		barrel(b.x, b.z, b.color)
	end

	-- Rubble in the south lot (low, so the camera sees over it).
	for _ = 1, 9 do
		local x = rng:range(-42, 42)
		local z = rng:range(A + 3, H - 2)
		if math.abs(x + 18) >= 4 and math.abs(x - 12) >= 4 then
			local r = rng:range(0.8, 1.6)
			box(
				r * 2,
				r * 0.6,
				r * 1.6,
				rng:pick({ "#6d6862", "#5b5550", "#7a736b" }),
				"Slate",
				x,
				r * 0.25,
				z,
				0,
				rng:range(0, 3)
			)
			colCircle(x, z, r * 0.9, 0.7)
		end
	end

	return {
		pieces = pieces,
		colliders = colliders,
		spawns = spawns,
		lamps = lamps,
		props = props,
		playerSpawn = { 0, 0, 8 },
	}
end

return { generate = generate }
