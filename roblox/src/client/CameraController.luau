--[[
	Angled top-down follow camera with aim look-ahead and trauma screen shake.
	Portrait screens pull the camera back so the play area stays readable.
	With no character it slowly orbits the plaza (lobby attract mode).
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)

local Context = require(script.Parent.Context)

local S = Constants.STUDS
local OFFSET = Vector3.new(0, 20, 12.5) * S

local CameraController = {}

function CameraController.start()
	local camera = Workspace.CurrentCamera
	local focus = Vector3.new(0, 0, 8 * S)
	local shakeTime = 0
	local orbit = 0

	RunService:BindToRenderStep("DeadfallCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 45
		local viewport = camera.ViewportSize
		local aspect = viewport.X / math.max(1, viewport.Y)
		local scale = if aspect < 1 then math.min(1.45, 1 + (1 - aspect) * 0.8) else 1

		local character = Context.character()
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			orbit += dt * 0.05
			local r = 34 * S
			camera.CFrame = CFrame.lookAt(Vector3.new(math.sin(orbit) * r, 20 * S, math.cos(orbit) * r), Vector3.new(0, 3, 0))
			return
		end

		local look = Vector3.zero
		if Context.placing then
			look = Context.panOffset or Vector3.zero
		elseif not Context.downed() then
			local reach = if Context.device == "mouse" then math.min(4, Context.aimDistance * 0.3) else 2.5
			look = Vector3.new(Context.aimX, 0, Context.aimZ) * reach * S
		end
		local target = Vector3.new(root.Position.X, 0, root.Position.Z) + look
		local k = 1 - math.exp(-7 * dt)
		focus = focus:Lerp(target, k)
		local cf = CFrame.lookAt(focus + Vector3.new(OFFSET.X, OFFSET.Y * scale, OFFSET.Z * scale), focus)

		-- Trauma-based shake (squared for a nicer falloff).
		Context.trauma = math.max(0, Context.trauma - dt * 1.6)
		if Context.trauma > 0 then
			shakeTime += dt
			local s = Context.trauma * Context.trauma
			local t = shakeTime * 28
			local ox = (math.sin(t * 1.1) + math.sin(t * 2.3 + 1.7)) * 0.5 * s * 0.9 * S
			local oy = (math.sin(t * 1.7 + 0.4) + math.sin(t * 3.1)) * 0.5 * s * 0.6 * S
			cf = cf * CFrame.new(ox, oy, 0) * CFrame.Angles(0, 0, math.sin(t * 1.3 + 2.1) * s * 0.035)
		end
		camera.CFrame = cf
	end)
end

-- Intersects a screen point with the horizontal plane at `height` metres.
function CameraController.screenToGround(x: number, y: number, height: number): Vector3?
	local camera = Workspace.CurrentCamera
	local ray = camera:ViewportPointToRay(x, y)
	local planeY = height * S
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = (planeY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

return CameraController
