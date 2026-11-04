--[[
	Small declarative helper for building UI in code, implementing the
	"Field Manual" design language (Theme.luau): square corners, ink rules,
	paper or night surfaces, condensed headings, mono figures.

	Two kits share one API:
	  Builder.label / panel / button / bar / tabs / stamp   -> paper (menus)
	  Builder.night.label / panel / button / bar / ...      -> night (HUD)
	Builder.paper and Builder.theme are the matching token tables
	(Builder.theme is the night palette, for the HUD modules).
]]
local Theme = require(script.Parent.Theme)

local Builder = {}

Builder.Theme = Theme
Builder.paper = Theme.paper
Builder.theme = Theme.night

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

local function apply(inst: Instance, props: { [any]: any }?)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
		if props.Parent then
			inst.Parent = props.Parent
		end
	end
end

-- Corners are square in this system (2 px at most).
function Builder.corner(radius: number): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, math.min(radius, Theme.CORNER)) })
end

function Builder.stroke(color: Color3?, thickness: number?, transparency: number?): UIStroke
	return create("UIStroke", {
		Color = color or Theme.paper.border,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Builder.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return create("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
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

-- A kit of components bound to one palette.
local function kit(P: Theme.Palette)
	local K = {}

	-- A page / panel: flat surface, 1-px rule (2-px ink border on paper pages).
	function K.panel(props: { [any]: any }?): Frame
		local frame = create("Frame", {
			BackgroundColor3 = P.panel,
			BackgroundTransparency = P.panelAlpha,
			BorderSizePixel = 0,
		})
		Builder.corner(Theme.CORNER).Parent = frame
		Builder.stroke(P.border, if P.name == "paper" then 2 else 1, 0).Parent = frame
		apply(frame, props)
		return frame
	end

	function K.label(text: string, size: number, props: { [any]: any }?): TextLabel
		local l = create("TextLabel", {
			BackgroundTransparency = 1,
			Text = text,
			TextSize = size,
			Font = P.body,
			TextColor3 = P.text,
			Size = UDim2.new(1, 0, 0, size + 6),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		apply(l, props)
		return l
	end

	--[[
		Buttons: `kind` = "primary" (ink fill), "danger" (rust outline) or nil
		(ink outline). Text is upper-case Oswald. Unavailable buttons are shown
		by the caller with the reason as text, in the muted colour.
	]]
	function K.button(text: string, kind: string?, onClick: (() -> ())?, props: { [any]: any }?): TextButton
		local primary = kind == "primary"
		local danger = kind == "danger"
		local b = create("TextButton", {
			Text = string.upper(text),
			Font = P.head,
			TextSize = 20,
			AutoButtonColor = true,
			TextColor3 = if primary then P.buttonText elseif danger then P.rust else P.text,
			BackgroundColor3 = if primary then P.buttonFill else P.panel,
			BackgroundTransparency = if primary then 0 else (if P.name == "paper" then 0 else 0.2),
			Size = UDim2.new(1, 0, 0, 44),
			BorderSizePixel = 0,
		})
		Builder.corner(Theme.CORNER).Parent = b
		if not primary then
			Builder.stroke(if danger then P.rust else P.border, 1, 0).Parent = b
		end
		if onClick then
			b.Activated:Connect(onClick)
		end
		apply(b, props)
		return b
	end

	-- Horizontal bar with an outline and a flat fill: returns (root, fill, label).
	function K.bar(color: Color3, height: number): (Frame, Frame, TextLabel)
		local root = create("Frame", {
			BackgroundColor3 = P.bg,
			BackgroundTransparency = if P.name == "paper" then 1 else 0.3,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, height),
		})
		Builder.stroke(P.text, 1, 0.35).Parent = root
		local fill = create("Frame", {
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		local label = create("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Font = P.mono,
			TextSize = math.max(10, height - 4),
			TextColor3 = P.text,
			TextStrokeTransparency = 0.6,
			Text = "",
			ZIndex = 2,
			Parent = root,
		})
		return root, fill, label
	end

	--[[
		A numbered tab index ("01 WEAPONS"): returns the row frame and a
		select(name) function that underlines the open tab in rust.
		`tabs` = { { name, title } }, `onPick(name)` runs on a click.
	]]
	function K.tabs(parent: Instance, tabs: { { string } }, onPick: (string) -> ()): (Frame, (string) -> ())
		local row = create("Frame", {
			Name = "Tabs",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 36),
			Parent = parent,
		}, { Builder.list(24, true) })
		create("Frame", {
			Name = "Rule",
			BackgroundColor3 = P.border,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = row,
		})
		local buttons = {}
		for i, t in tabs do
			local b = create("TextButton", {
				Name = t[1],
				LayoutOrder = i,
				Text = `<font face="SpecialElite" size="14">{string.format("%02d", i)}</font>  {string.upper(t[2])}`,
				RichText = true,
				Font = P.head,
				TextSize = 20,
				BackgroundTransparency = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				TextColor3 = P.muted,
				Parent = row,
			})
			local underline = create("Frame", {
				Name = "Underline",
				BackgroundColor3 = P.rust,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, 4),
				Size = UDim2.new(1, 0, 0, 3),
				Visible = false,
				Parent = b,
			})
			b.Activated:Connect(function()
				onPick(t[1])
			end)
			buttons[t[1]] = { button = b, underline = underline }
		end
		local function select(name: string)
			for key, e in buttons do
				local on = key == name
				e.button.TextColor3 = if on then P.text else P.muted
				e.underline.Visible = on
			end
		end
		return row, select
	end

	-- A rubber stamp ("RARE", "SOLD"): bordered, slightly rotated, ink only.
	function K.stamp(text: string, color: Color3, props: { [any]: any }?): TextLabel
		local l = create("TextLabel", {
			BackgroundTransparency = 1,
			Text = string.upper(text),
			Font = P.mono,
			TextSize = 12,
			TextColor3 = color,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			Rotation = -3,
		}, {
			create("UIStroke", {
				Color = color,
				Thickness = 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
		apply(l, props)
		return l
	end

	-- Stamp colour for a gear rarity.
	function K.rarityColor(rarity: string): Color3
		return if rarity == "unique" then P.stampUnique elseif rarity == "rare" then P.stampRare else P.stampCommon
	end

	-- A thin horizontal rule.
	function K.rule(props: { [any]: any }?): Frame
		local f = create("Frame", {
			BackgroundColor3 = P.rule,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1),
		})
		apply(f, props)
		return f
	end

	return K
end

local paperKit = kit(Theme.paper)
Builder.night = kit(Theme.night)

Builder.panel = paperKit.panel
Builder.label = paperKit.label
Builder.button = paperKit.button
Builder.bar = paperKit.bar
Builder.tabs = paperKit.tabs
Builder.stamp = paperKit.stamp
Builder.rarityColor = paperKit.rarityColor
Builder.rule = paperKit.rule

return Builder
