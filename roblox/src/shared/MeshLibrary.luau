--[[
	Optional imported meshes. If the place contains a model or folder named
	"DeadfallMeshes" in ReplicatedStorage (the result of importing
	roblox/assets/DeadfallMeshes.obj with Studio's Import 3D), MeshParts are
	looked up inside it by name and cloned. Every caller keeps a Part-built
	fallback, so the game looks exactly as before when a mesh is missing.

	Sizes come from Config/MeshSizes (generated alongside the meshes), so the
	importer's unit settings can't change how big anything is in game.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshSizes = require(script.Parent.Config.MeshSizes)

local FOLDER_NAME = "DeadfallMeshes"

local MeshLibrary = {}

local found: { [string]: MeshPart } = {}

local function template(name: string): MeshPart?
	local cached = found[name]
	if cached and cached.Parent then
		return cached
	end
	local root = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not root then
		return nil
	end
	local part = root:FindFirstChild(name, true)
	if part and part:IsA("MeshPart") then
		found[name] = part
		return part
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

return MeshLibrary
