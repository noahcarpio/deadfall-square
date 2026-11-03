--[[
	Maps keyboard/mouse, gamepad and touch onto the shared Context intent:
	aim direction + distance, trigger, sprint, and edge actions (roll, reload,
	weapon switch). Movement itself uses Roblox's default control scripts,
	which are camera-relative and already support WASD, thumbsticks and the
	touch thumbstick.
]]
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)

local Context = require(script.Parent.Context)
local CameraController = require(script.Parent.CameraController)
local Builder = require(script.Parent.UI.Builder)

local S = Constants.STUDS
local GUN_HEIGHT = 1.2
local STICK_RADIUS = 60

local InputController = {
	onRoll = Context.signal(),
	onReload = Context.signal(),
	onSwitch = Context.signal(), -- (slot | nil, direction | nil)
	onCrouch = Context.signal(), -- toggle
	onUseItem = Context.signal(), -- (itemId)
	onToggleBag = Context.signal(),
}

local mouseDown = false
local gamepadAim = Vector2.zero
local gamepadFire = false
local touchAim = Vector2.zero
local touchSprint = false
local mobileGui: ScreenGui? = nil

local function setDevice(device: "mouse" | "touch" | "gamepad")
	if Context.device ~= device then
		Context.device = device
		if mobileGui then
			mobileGui.Enabled = device == "touch" and not Context.menuOpen
		end
		UserInputService.MouseIconEnabled = device ~= "gamepad"
	end
end

------------------------------------------------------------------ touch UI

local function buildMobileControls(): ScreenGui
	local create = Builder.create
	local T = Builder.theme
	local gui = Builder.screen("DeadfallTouch", 5)
	gui.Enabled = false

	-- Right half: floating aim / fire stick.
	local zone = create("Frame", {
		Name = "AimZone",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromScale(0.5, 0.62),
		Parent = gui,
	})
	local base = create("Frame", {
		Name = "Stick",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(STICK_RADIUS * 2, STICK_RADIUS * 2),
		BackgroundColor3 = Color3.fromRGB(255, 120, 100),
		BackgroundTransparency = 0.85,
		Visible = false,
		Parent = gui,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = base })
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(54, 54),
		BackgroundColor3 = Color3.fromRGB(255, 120, 100),
		BackgroundTransparency = 0.35,
		Parent = base,
	})
	create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

	local activeInput: InputObject? = nil
	local origin = Vector2.zero
	zone.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or activeInput then
			return
		end
		setDevice("touch")
		activeInput = input
		origin = Vector2.new(input.Position.X, input.Position.Y)
		base.Position = UDim2.fromOffset(origin.X, origin.Y + GuiService:GetGuiInset().Y)
		base.Visible = true
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input ~= activeInput then
			return
		end
		local p = Vector2.new(input.Position.X, input.Position.Y)
		local d = p - origin
		if d.Magnitude > STICK_RADIUS then
			-- Drag the origin so the stick never feels stuck at the rim.
			origin += d.Unit * (d.Magnitude - STICK_RADIUS)
			d = p - origin
			base.Position = UDim2.fromOffset(origin.X, origin.Y + GuiService:GetGuiInset().Y)
		end
		touchAim = d / STICK_RADIUS
		knob.Position = UDim2.new(0.5, d.X, 0.5, d.Y)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == activeInput then
			activeInput = nil
			touchAim = Vector2.zero
			base.Visible = false
			knob.Position = UDim2.fromScale(0.5, 0.5)
		end
	end)

	local column = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.36, 0),
		Size = UDim2.fromOffset(64, 4 * 72),
		Parent = gui,
	}, { Builder.list(8) })
	local column2 = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -84, 0.36, 0),
		Size = UDim2.fromOffset(64, 4 * 72),
		Parent = gui,
	}, { Builder.list(8) })
	local function button(text: string, onPress: () -> (), parent: Frame?)
		local b = create("TextButton", {
			Text = text,
			Font = T.head,
			TextSize = 18,
			TextColor3 = Color3.new(1, 1, 1),
			BackgroundColor3 = T.panel,
			BackgroundTransparency = 0.35,
			Size = UDim2.fromOffset(64, 64),
			AutoButtonColor = true,
			Parent = parent or column,
		})
		create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = b })
		Builder.stroke(Color3.new(1, 1, 1), 2, 0.6).Parent = b
		b.Activated:Connect(onPress)
		return b
	end
	local sprintButton
	sprintButton = button("RUN", function()
		touchSprint = not touchSprint
		sprintButton.BackgroundColor3 = if touchSprint then T.accent else T.panel
	end)
	button("ROLL", function()
		InputController.onRoll:fire()
	end)
	button("RELOAD", function()
		InputController.onReload:fire()
	end)
	button("SWAP", function()
		InputController.onSwitch:fire(nil, 1)
	end)
	local crouchButton
	crouchButton = button("SNEAK", function()
		InputController.onCrouch:fire()
	end, column2)
	Context.signals.crouchChanged:connect(function()
		crouchButton.BackgroundColor3 = if Context.crouching then T.accent else T.panel
	end)
	button("HEAL", function()
		InputController.onUseItem:fire("bandage")
	end, column2)
	button("BOMB", function()
		InputController.onUseItem:fire("pipebomb")
	end, column2)
	button("BAG", function()
		InputController.onToggleBag:fire()
	end, column2)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

------------------------------------------------------------------ actions

local function bindActions()
	local function roll(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.onRoll:fire()
		end
		return Enum.ContextActionResult.Sink
	end
	ContextActionService:BindActionAtPriority(
		"DeadfallRoll",
		roll,
		false,
		3000,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)
	ContextActionService:BindAction("DeadfallReload", function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.onReload:fire()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:BindAction("DeadfallNext", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local dir = if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1
			InputController.onSwitch:fire(nil, dir)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Q, Enum.KeyCode.E, Enum.KeyCode.ButtonR1, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("DeadfallCrouch", function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.onCrouch:fire()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:BindAction("DeadfallItem", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local k = input.KeyCode
			local id = if k == Enum.KeyCode.B or k == Enum.KeyCode.DPadUp then "bandage" else "pipebomb"
			InputController.onUseItem:fire(id)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B, Enum.KeyCode.G, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown)
	ContextActionService:BindAction("DeadfallBag", function(_, state)
		if state == Enum.UserInputState.Begin then
			InputController.onToggleBag:fire()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.I, Enum.KeyCode.DPadRight)
	local digits = {
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.Four,
		Enum.KeyCode.Five,
		Enum.KeyCode.Six,
		Enum.KeyCode.Seven,
	}
	ContextActionService:BindAction("DeadfallSlot", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			local slot = table.find(digits, input.KeyCode)
			if slot then
				InputController.onSwitch:fire(slot, nil)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(digits))
end

------------------------------------------------------------------ start

function InputController.start()
	local gui = buildMobileControls()
	mobileGui = gui
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Context.device = "mouse" -- force setDevice to apply
		setDevice("touch")
	end
	bindActions()

	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 then
			setDevice("mouse")
			if not processed then
				mouseDown = true
			end
		elseif t == Enum.UserInputType.Touch then
			setDevice("touch")
		elseif t == Enum.UserInputType.Gamepad1 then
			setDevice("gamepad")
			if input.KeyCode == Enum.KeyCode.ButtonR2 then
				gamepadFire = true
			end
		elseif t == Enum.UserInputType.Keyboard then
			setDevice("mouse")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			mouseDown = false
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			gamepadFire = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			setDevice("mouse")
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not Context.menuOpen then
			InputController.onSwitch:fire(nil, if input.Position.Z > 0 then -1 else 1)
		elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local v = Vector2.new(input.Position.X, input.Position.Y)
			gamepadAim = if v.Magnitude > 0.2 then v else Vector2.zero
			if v.Magnitude > 0.2 then
				setDevice("gamepad")
			end
		end
	end)

	RunService:BindToRenderStep("DeadfallInput", Enum.RenderPriority.Input.Value + 1, function()
		local character = Context.character()
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		gui.Enabled = Context.device == "touch" and not Context.menuOpen
		if not root then
			Context.firing = false
			return
		end
		local px, pz = root.Position.X / S, root.Position.Z / S
		local blocked = Context.menuOpen or Context.placing
		if Context.device == "mouse" then
			local m = UserInputService:GetMouseLocation()
			local hit = CameraController.screenToGround(m.X, m.Y, GUN_HEIGHT)
			if hit then
				local dx, dz = hit.X / S - px, hit.Z / S - pz
				local d = math.sqrt(dx * dx + dz * dz)
				if d > 0.3 then
					Context.aimX, Context.aimZ = dx / d, dz / d
				end
				Context.aimDistance = d
			end
			Context.firing = mouseDown and not blocked
			Context.sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		elseif Context.device == "gamepad" then
			if gamepadAim.Magnitude > 0.2 then
				local u = gamepadAim.Unit
				Context.aimX, Context.aimZ = u.X, -u.Y
				Context.aimDistance = 8 + gamepadAim.Magnitude * 8
			end
			Context.firing = (gamepadFire or gamepadAim.Magnitude > 0.85) and not blocked
			Context.sprinting = UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
				or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL2)
		else
			if touchAim.Magnitude > 0.15 then
				local u = touchAim.Unit
				Context.aimX, Context.aimZ = u.X, u.Y
				Context.aimDistance = 12
			end
			Context.firing = touchAim.Magnitude > 0.3 and not blocked
			Context.sprinting = touchSprint
		end
	end)
end

return InputController
