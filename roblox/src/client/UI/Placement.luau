--[[
	Structure placement mode: a ghost footprint follows the cursor (or a tap on
	touch), snapped to the grid and tinted by local validity. Click/PLACE asks
	the server to build it (the server re-validates and charges coins).
	R or right-click rotates; WASD (or a touch drag) pans the camera; Esc or
	CANCEL returns to the shop.
]]
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Collision = require(Shared.Collision)
local Constants = require(Shared.Config.Constants)
local Shop = require(Shared.Config.Shop)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local CameraController = require(script.Parent.Parent.CameraController)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.theme
local S = Constants.STUDS

local Placement = {}

local collision = Collision.new(-Constants.WORLD_HALF - 4, -Constants.WORLD_HALF - 4, Constants.WORLD_HALF + 4, Constants.WORLD_HALF + 4)
for _, c in ArenaLayout.generate().colliders do
	collision:insert(table.clone(c) :: any)
end

local function footprint(stype: string, rotated: boolean): (number, number)
	local fp = Shop.structures[stype].footprint
	if rotated then
		return fp[2] / 2, fp[1] / 2
	end
	return fp[1] / 2, fp[2] / 2
end

local function snap(stype: string, rotated: boolean, x: number, z: number): (number, number)
	local hw, hd = footprint(stype, rotated)
	local sx = if (hw * 2) % 2 == 0 then math.floor(x + 0.5) else math.floor(x) + 0.5
	local sz = if (hd * 2) % 2 == 0 then math.floor(z + 0.5) else math.floor(z) + 0.5
	return sx, sz
end

-- Overlap with other players' structures (live parts in Workspace.Structures).
local function overlapsStructures(minX: number, minZ: number, maxX: number, maxZ: number): boolean
	local folder = Workspace:FindFirstChild("Structures")
	if not folder then
		return false
	end
	for _, m in folder:GetChildren() do
		local blocker = m:FindFirstChild("Blocker") :: BasePart?
		if blocker then
			local p, size = blocker.Position / S, blocker.Size / S
			if p.X - size.X / 2 < maxX and p.X + size.X / 2 > minX and p.Z - size.Z / 2 < maxZ and p.Z + size.Z / 2 > minZ then
				return true
			end
		end
	end
	return false
end

function Placement.new(gui: ScreenGui, onDone: () -> ())
	local self: any = { active = false }
	local stype = "barricade"
	local rotated = false
	local gx, gz = 0, 0
	local valid = false
	local busy = false

	local ghost = create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Material = Enum.Material.ForceField,
		Transparency = 0.2,
		Parent = nil,
	})
	local range = create("Part", {
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(154, 216, 255),
		Transparency = 0.85,
		Parent = nil,
	})

	local bar = Builder.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.fromOffset(640, 76),
		Visible = false,
		Parent = gui,
	})
	Builder.padding(10).Parent = bar
	local label = Builder.label("", 22, { Font = T.head, Size = UDim2.new(1, -330, 0, 26), Parent = bar })
	local hint = Builder.label("", 13, {
		TextColor3 = T.muted,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, -330, 0, 26),
		TextWrapped = true,
		Parent = bar,
	})
	local buttons = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(320, 50),
		Parent = bar,
	}, { Builder.list(6, true) })
	local function finish()
		self.stop()
		onDone()
	end
	local function confirm()
		if busy or not self.active then
			return
		end
		if not valid then
			Audio.play("uiDeny")
			return
		end
		busy = true
		local ok, reason = Context.remotes.Place:InvokeServer(stype, gx, gz, rotated)
		busy = false
		if ok then
			Audio.play("uiBuy")
			finish()
		else
			Audio.play("uiDeny")
			hint.Text = reason or "Can't build there"
		end
	end
	local function rotate()
		rotated = not rotated
		Audio.play("uiClick")
	end
	Builder.button("ROTATE", nil, rotate, { Size = UDim2.fromOffset(100, 50), Parent = buttons })
	local placeButton = Builder.button("PLACE", "primary", confirm, { Size = UDim2.fromOffset(100, 50), Parent = buttons })
	Builder.button("CANCEL", "danger", finish, { Size = UDim2.fromOffset(100, 50), Parent = buttons })

	local function updateGhost(x: number, z: number)
		gx, gz = snap(stype, rotated, x, z)
		local hw, hd = footprint(stype, rotated)
		local limit = Constants.ARENA_HALF - 1.5
		valid = math.abs(gx) + hw <= limit
			and math.abs(gz) + hd <= limit
			and not collision:overlapsRect(gx - hw - 0.1, gz - hd - 0.1, gx + hw + 0.1, gz + hd + 0.1)
			and not overlapsStructures(gx - hw, gz - hd, gx + hw, gz + hd)
		ghost.Size = Vector3.new(hw * 2 * S, (if stype == "turret" then 1.0 else 1.2) * S, hd * 2 * S)
		ghost.CFrame = CFrame.new(gx * S, ghost.Size.Y / 2, gz * S)
		ghost.Color = if valid then T.accent else T.danger
		range.CFrame = CFrame.new(gx * S, 0.2, gz * S) * CFrame.Angles(0, 0, math.pi / 2)
		placeButton.AutoButtonColor = valid
	end

	local tapStart: Vector2? = nil
	UserInputService.InputBegan:Connect(function(input, processed)
		if not self.active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			confirm()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.R then
			rotate()
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			finish()
		elseif input.UserInputType == Enum.UserInputType.Touch then
			tapStart = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not self.active or input.UserInputType ~= Enum.UserInputType.Touch or not tapStart then
			return
		end
		local delta = input.Delta
		if delta.Magnitude > 0 then
			Context.panOffset -= Vector3.new(delta.X, 0, delta.Y) * 0.25
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		if not self.active or processed or input.UserInputType ~= Enum.UserInputType.Touch or not tapStart then
			return
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		if (p - tapStart).Magnitude < 10 then
			local hit = CameraController.screenToGround(p.X, p.Y, 0)
			if hit then
				updateGhost(hit.X / S, hit.Z / S)
			end
		end
		tapStart = nil
	end)

	RunService.RenderStepped:Connect(function(dt)
		if not self.active then
			return
		end
		local pan = 18 * S * dt
		local offset = Context.panOffset
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then
			offset -= Vector3.new(0, 0, pan)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			offset += Vector3.new(0, 0, pan)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then
			offset -= Vector3.new(pan, 0, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then
			offset += Vector3.new(pan, 0, 0)
		end
		local maxPan = Constants.ARENA_HALF * S
		Context.panOffset = Vector3.new(math.clamp(offset.X, -maxPan, maxPan), 0, math.clamp(offset.Z, -maxPan, maxPan))
		if Context.device ~= "touch" then
			local m = UserInputService:GetMouseLocation()
			local hit = CameraController.screenToGround(m.X, m.Y, 0)
			if hit then
				updateGhost(hit.X / S, hit.Z / S)
			end
		else
			updateGhost(gx, gz)
		end
	end)

	function self.start(structureType: string)
		stype = structureType
		rotated = false
		self.active = true
		Context.placing = true
		Context.panOffset = Vector3.zero
		local def = Shop.structures[stype]
		label.Text = `Placing {def.name} — {def.cost} coins`
		hint.Text = if Context.device == "touch"
			then "Drag to pan · tap the ground to position · PLACE to build"
			else "Click to place · R / right-click to rotate · WASD to pan · Esc to cancel"
		bar.Visible = true
		ghost.Parent = Workspace
		if stype == "turret" then
			local d = Shop.turret.range * 2 * S
			range.Size = Vector3.new(0.2, d, d)
			range.Parent = Workspace
		end
		local character = Context.character()
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			updateGhost(root.Position.X / S + Context.aimX * 3, root.Position.Z / S + Context.aimZ * 3)
		end
		ContextActionService:BindActionAtPriority("DeadfallPlacementSink", function()
			return Enum.ContextActionResult.Sink
		end, false, 4000, Enum.KeyCode.Space)
	end

	function self.stop()
		self.active = false
		Context.placing = false
		Context.panOffset = Vector3.zero
		bar.Visible = false
		ghost.Parent = nil
		range.Parent = nil
		ContextActionService:UnbindAction("DeadfallPlacementSink")
	end

	return self
end

return Placement
