--[[
	Gadget slots (Z / X / V, or LB + X / Y / B) with cooldown sweeps, plus the
	equipped melee weapon (right click / RB), above the weapon box.
]]
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Gear = require(Shared.Gear)

local Context = require(script.Parent.Parent.Context)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.theme

local KEYS = { "Z", "X", "V" }
local PAD_KEYS = { "LB+X", "LB+Y", "LB+B" }

local AbilityBar = {}

function AbilityBar.start(gui: ScreenGui)
	local bar = create("Frame", {
		Name = "Abilities",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -132),
		Size = UDim2.fromOffset(300, 62),
		Parent = gui,
	}, { Builder.list(6, true) })
	local layout = bar:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	end

	local function slot(order: number, width: number)
		local f = Builder.panel({ LayoutOrder = order, Size = UDim2.fromOffset(width, 62), Parent = bar })
		f.ClipsDescendants = true
		local fill = create("Frame", {
			Name = "Cooldown",
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			ZIndex = 2,
			Parent = f,
		})
		local name = Builder.label("", 13, {
			Font = T.bold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 0, 34),
			ZIndex = 3,
			Parent = f,
		})
		local key = Builder.label("", 12, {
			TextColor3 = T.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -2),
			Size = UDim2.new(1, 0, 0, 16),
			ZIndex = 3,
			Parent = f,
		})
		return f, fill, name, key
	end

	local meleeFrame, _, meleeName, meleeKey = slot(0, 96)
	local slots = {}
	for i = 1, Gear.GADGET_SLOTS do
		local f, fill, name, key = slot(i, 62)
		slots[i] = { frame = f, fill = fill, name = name, key = key }
	end

	RunService.RenderStepped:Connect(function()
		local phase = Context.phase()
		bar.Visible = phase ~= "lobby" and phase ~= "gameover"
		if not bar.Visible then
			return
		end
		local pad = Context.device == "gamepad"
		local touch = Context.device == "touch"
		local g = Context.gear
		local melee = g.melee
		meleeName.Text = if melee then Gear.defs[melee.id].name else "—"
		meleeName.TextColor3 = if melee then Color3.fromHex(Gear.rarities[melee.rarity].color) else T.muted
		meleeKey.Text = if pad then "RB" elseif touch then "SLASH" else "RIGHT CLICK"
		meleeFrame.Visible = melee ~= nil
		local now = Workspace:GetServerTimeNow()
		for i, s in slots do
			local item = g.gadgets and g.gadgets[i]
			if item then
				s.name.Text = Gear.defs[item.id].name
				s.name.TextColor3 = Color3.fromHex(Gear.rarities[item.rarity].color)
				local left = (Context.abilityReady[i] or 0) - now
				local frac = math.clamp(left / Gear.cooldownOf(item), 0, 1)
				s.fill.Size = UDim2.fromScale(1, frac)
				s.key.Text = if left > 0
					then `{math.ceil(left)}s`
					elseif pad then PAD_KEYS[i]
					elseif touch then `G{i}`
					else KEYS[i]
			else
				s.name.Text = "empty"
				s.name.TextColor3 = T.muted
				s.fill.Size = UDim2.fromScale(1, 0)
				s.key.Text = if pad then PAD_KEYS[i] elseif touch then `G{i}` else KEYS[i]
			end
		end
	end)
end

return AbilityBar
