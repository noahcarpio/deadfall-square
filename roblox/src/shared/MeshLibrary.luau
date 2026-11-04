--[[
	Optional art, looked up by name in ReplicatedStorage:

	  * ArtAssets - your realistic replacements (Creator Store models, AI-made
	    meshes, anything imported with Studio's Import 3D). A MeshPart here
	    replaces the generated mesh of the same name (zombie limbs, guns,
	    barricades, pickups...). A whole Model here replaces an arena prop
	    (cars, benches, crates, the bus...): it is scaled to the prop's
	    footprint and stood on the ground. See the README for every name.
	  * DeadfallMeshes - the generated meshes (roblox/assets/DeadfallMeshes.obj
	    imported with Import 3D).

	ArtAssets wins over DeadfallMeshes. Every caller keeps a Part-built
	fallback, so the game looks exactly as before when nothing is imported.

	Sizes come from Config/MeshSizes (generated alongside the meshes), so the
	importer's unit settings can't change how big anything is in game.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshSizes = require(script.Parent.Config.MeshSizes)

local FOLDERS = { "ArtAssets", "DeadfallMeshes" }

local MeshLibrary = {}

local found: { [string]: MeshPart } = {}

local function template(name: string): MeshPart?
	local cached = found[name]
	if cached and cached.Parent then
		return cached
	end
	for _, folderName in FOLDERS do
		local root = ReplicatedStorage:FindFirstChild(folderName)
		local part = root and root:FindFirstChild(name, true)
		if part and part:IsA("MeshPart") then
			found[name] = part
			return part
		end
	end
	return nil
end

function MeshLibrary.has(name: string): boolean
	return template(name) ~= nil
end

-- Generated bounding-box size in studs (nil for unknown names).
function MeshLibrary.size(name: string): Vector3?
	local s = (MeshSizes :: any)[name]
	if not s then
		return nil
	end
	return Vector3.new(s[1], s[2], s[3])
end

--[[
	Returns an anchored, non-colliding copy of the named mesh sized to `size`
	(or its generated size), or nil when the mesh hasn't been imported.
]]
function MeshLibrary.clone(name: string, size: Vector3?): MeshPart?
	local t = template(name)
	local targetSize = size or MeshLibrary.size(name)
	if not t or not targetSize then
		return nil
	end
	local part = t:Clone()
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = targetSize
	for _, child in part:GetChildren() do
		-- Imported meshes shouldn't carry scripts or welds into the game.
		if child:IsA("LuaSourceContainer") or child:IsA("JointInstance") then
			child:Destroy()
		end
	end
	return part
end

--[[
	A whole replacement Model from ArtAssets for an arena prop, scaled
	uniformly to fit `size` (studs) and anchored without collision (the
	simulation's own colliders still apply). Its pivot is moved to the centre
	of its bottom face, so callers place it on the ground. Nil when absent.
]]
function MeshLibrary.model(name: string, size: Vector3): Model?
	local root = ReplicatedStorage:FindFirstChild("ArtAssets")
	local template = root and root:FindFirstChild(name)
	if not template or not template:IsA("Model") then
		return nil
	end
	local model = template:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("LuaSourceContainer") or d:IsA("JointInstance") then
			d:Destroy()
		end
	end
	local cf, extents = model:GetBoundingBox()
	local fit = math.min(size.X / extents.X, size.Y / extents.Y, size.Z / extents.Z)
	if fit > 0 and fit < math.huge then
		model:ScaleTo(model:GetScale() * fit)
		cf, extents = model:GetBoundingBox()
	end
	model.WorldPivot = cf * CFrame.new(0, -extents.Y / 2, 0)
	return model
end

return MeshLibrary
