--[[
	Small declarative helper for building UI in code, plus the shared theme
	(colours and fonts matching the browser version).
]]
local Builder = {}

Builder.theme = {
	bg = Color3.fromRGB(11, 14, 20),
	panel = Color3.fromRGB(16, 21, 27),
	panelAlpha = 0.16,
	border = Color3.fromRGB(60, 66, 74),
	text = Color3.fromRGB(236, 231, 220),
	muted = Color3.fromRGB(155, 150, 139),
	accent = Color3.fromRGB(125, 255, 176),
	danger = Color3.fromRGB(255, 74, 58),
	warn = Color3.fromRGB(255, 178, 58),
	gold = Color3.fromRGB(255, 210, 58),
	blue = Color3.fromRGB(74, 168, 255),
	boss = Color3.fromRGB(208, 80, 255),
	head = Enum.Font.Bangers,
	body = Enum.Font.Gotham,
	bold = Enum.Font.GothamBold,
}

local T = Builder.theme

-- create("Frame", { Size = ..., [children] = {...} })
function Builder.create(className: string, props: { [any]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local create = Builder.create

function Builder.corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Builder.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return create("UIStroke", {
		Color = color or T.border,
		Thickness = thickness or 1,
		Transparency = transparency or 0.3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Builder.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return create("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Builder.panel(props: { [any]: any }?): Frame
	local p = props or {}
	local frame = create("Frame", {
		BackgroundColor3 = T.panel,
		BackgroundTransparency = T.panelAlpha,
		BorderSizePixel = 0,
	})
	for k, v in p do
		if k ~= "Parent" then
			(frame :: any)[k] = v
		end
	end
	Builder.corner(10).Parent = frame
	Builder.stroke().Parent = frame
	if p.Parent then
		frame.Parent = p.Parent
	end
	return frame
end

function Builder.label(text: string, size: number, props: { [any]: any }?): TextLabel
	local l = create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextSize = size,
		Font = T.body,
		TextColor3 = T.text,
		Size = UDim2.new(1, 0, 0, size + 6),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(l :: any)[k] = v
			end
		end
		if props.Parent then
			l.Parent = props.Parent
		end
	end
	return l
end

-- A themed button; `kind` = "primary" | "danger" | "normal".
function Builder.button(text: string, kind: string?, onClick: (() -> ())?, props: { [any]: any }?): TextButton
	local primary = kind == "primary"
	local b = create("TextButton", {
		Text = text,
		Font = T.head,
		TextSize = 24,
		AutoButtonColor = true,
		TextColor3 = if primary then Color3.fromRGB(11, 26, 18) else T.text,
		BackgroundColor3 = if primary then T.accent elseif kind == "danger" then Color3.fromRGB(70, 24, 20) else Color3.fromRGB(32, 38, 46),
		BackgroundTransparency = 0,
		Size = UDim2.new(1, 0, 0, 46),
		BorderSizePixel = 0,
	})
	Builder.corner(6).Parent = b
	if not primary then
		Builder.stroke().Parent = b
	end
	if onClick then
		b.Activated:Connect(onClick)
	end
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(b :: any)[k] = v
			end
		end
		if props.Parent then
			b.Parent = props.Parent
		end
	end
	return b
end

-- Horizontal bar: returns (root, fill, label).
function Builder.bar(color: Color3, height: number): (Frame, Frame, TextLabel)
	local root = create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
	})
	Builder.corner(4).Parent = root
	local fill = create("Frame", {
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	Builder.corner(4).Parent = fill
	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = T.bold,
		TextSize = math.max(10, height - 4),
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.5,
		Text = "",
		ZIndex = 2,
		Parent = root,
	})
	return root, fill, label
end

function Builder.list(padding: number, horizontal: boolean?): UIListLayout
	return create("UIListLayout", {
		Padding = UDim.new(0, padding),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Builder.screen(name: string, order: number): ScreenGui
	return create("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = order,
	})
end

return Builder
