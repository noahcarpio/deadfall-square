--[[
	The bag: a compact HUD strip under the vitals (weight, materials, quick
	items, stealth status) and a full panel (I / D-pad right / BAG) with two
	tabs: ITEMS (use / drop) and GEAR (what's equipped, and the stash with
	Equip buttons; gadgets can go in slot 1, 2 or 3).
]]
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)
local Gear = require(Shared.Gear)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.theme

local SHORT = { scrap = "Scrap", wood = "Wood", cloth = "Rags", parts = "Elec", gunpowder = "Powder" }

local InventoryUI = {}

function InventoryUI.new(gui: ScreenGui, onUse: (string) -> ())
	local self = { open = false }

	-------------------------------------------------- HUD strip
	local strip = Builder.panel({
		Name = "Bag",
		Position = UDim2.fromOffset(14, 126),
		Size = UDim2.fromOffset(250, 82),
		Parent = gui,
	})
	Builder.padding(8).Parent = strip
	local weightLabel = Builder.label("", 13, { Font = T.bold, Size = UDim2.new(0.6, 0, 0, 16), Parent = strip })
	local stealthLabel = Builder.label("", 13, {
		Font = T.bold,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, 0, 0, 16),
		Parent = strip,
	})
	local weightBar, weightFill = Builder.bar(Color3.fromRGB(154, 216, 255), 4)
	weightBar.Position = UDim2.fromOffset(0, 19)
	weightBar.Parent = strip
	local matsLabel = Builder.label("", 12, {
		TextColor3 = T.muted,
		Position = UDim2.fromOffset(0, 27),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = strip,
	})
	local quickLabel = Builder.label("", 13, {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = strip,
	})

	-------------------------------------------------- full panel
	local panel = Builder.panel({
		Name = "BagPanel",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(14, 216),
		Size = UDim2.fromOffset(380, 460),
		Visible = false,
		Parent = gui,
	})
	Builder.padding(10).Parent = panel
	local tabRow = create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		Parent = panel,
	}, { Builder.list(10, true) })
	local listFrame = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		Parent = panel,
	}, { Builder.list(4) })
	local tab = "items"
	local renderPanel: () -> ()

	for i, t in { { "items", "ITEMS" }, { "gear", "GEAR" } } do
		local b = create("TextButton", {
			Name = t[1],
			LayoutOrder = i,
			Text = t[2],
			Font = T.head,
			TextSize = 22,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(80, 28),
			TextColor3 = T.muted,
			Parent = tabRow,
		})
		b.Activated:Connect(function()
			tab = t[1]
			Audio.play("uiClick")
			renderPanel()
		end)
	end

	local function gearRow(order: number, label: string, item: any, buttons: { { string, () -> () } })
		local color = if item then Color3.fromHex(Gear.rarities[item.rarity].color) else T.muted
		local row = create("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = order,
			Size = UDim2.new(1, -8, 0, 44),
			Parent = listFrame,
		})
		local name = if item then Gear.title(item) else "— empty —"
		Builder.label(`{label}  {name}`, 14, {
			Font = T.bold,
			TextColor3 = color,
			Size = UDim2.new(1, -60 - 46 * #buttons, 0, 18),
			Parent = row,
		})
		if item then
			local detail = table.concat(Gear.describe(item), " · ")
			local d = Builder.label(detail, 11, {
				TextColor3 = T.muted,
				Position = UDim2.fromOffset(0, 19),
				Size = UDim2.new(1, -60 - 46 * #buttons, 0, 24),
				TextWrapped = true,
				Parent = row,
			})
			d.TextYAlignment = Enum.TextYAlignment.Top
		end
		for k, b in buttons do
			local button = Builder.button(b[1], nil, nil, {
				TextSize = 14,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -(k - 1) * 46, 0, 4),
				Size = UDim2.fromOffset(if #b[1] > 1 then 60 else 42, 26),
				Parent = row,
			})
			button.Activated:Connect(b[2])
		end
	end

	local function renderGear()
		local g = Context.gear
		local function equip(uid: number, slot: number?)
			return function()
				Context.remotes.EquipGear:FireServer(uid, slot)
				Audio.play("uiBuy")
			end
		end
		gearRow(1, "MELEE", g.melee or nil, {})
		gearRow(2, "ARMOR", g.armor or nil, {})
		for i = 1, Gear.GADGET_SLOTS do
			local key = ({ "Z", "X", "V" })[i]
			gearRow(2 + i, `GADGET [{key}]`, g.gadgets[i] or nil, {})
		end
		local order = 10
		for _, id in Gear.order do
			local item = g.guns[id]
			if item then
				order += 1
				gearRow(order, "GUN", item, {})
			end
		end
		local header = create("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 50,
			Size = UDim2.new(1, 0, 0, 26),
			Parent = listFrame,
		})
		Builder.label(`STASH {#g.stash}/{Gear.STASH_SIZE}  (salvage at the workbench)`, 14, {
			Font = T.head,
			TextColor3 = T.accent,
			Size = UDim2.fromScale(1, 1),
			Parent = header,
		})
		for i, item in g.stash do
			local buttons = if item.kind == "gadget"
				then {
					{ "3", equip(item.uid, 3) },
					{ "2", equip(item.uid, 2) },
					{ "1", equip(item.uid, 1) },
				}
				else { { "EQUIP", equip(item.uid, nil) } }
			-- Gadgets show three slot buttons (Z / X / V).
			gearRow(50 + i, string.upper(item.kind), item, buttons)
		end
	end

	renderPanel = function()
		for _, c in listFrame:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for _, b in tabRow:GetChildren() do
			if b:IsA("TextButton") then
				b.TextColor3 = if b.Name == tab then T.accent else T.muted
			end
		end
		if tab == "gear" then
			renderGear()
			return
		end
		local inv = Context.inventory
		local any = false
		for i, id in Items.order do
			local n = inv:count(id)
			if n > 0 then
				any = true
				local def = Items.defs[id]
				local row = create("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = i,
					Size = UDim2.new(1, 0, 0, 30),
					Parent = listFrame,
				})
				Builder.label(`{def.name} ×{n}  ({string.format("%.1f", def.weight * n)} kg)`, 14, {
					Size = UDim2.new(1, -130, 1, 0),
					Parent = row,
				})
				if def.use then
					local use = Builder.button("USE", nil, nil, {
						TextSize = 16,
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.new(1, -64, 0, 0),
						Size = UDim2.fromOffset(60, 28),
						Parent = row,
					})
					use.Activated:Connect(function()
						onUse(id)
					end)
				end
				local drop = Builder.button("DROP", nil, nil, {
					TextSize = 16,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromOffset(60, 28),
					TextColor3 = T.danger,
					Parent = row,
				})
				drop.Activated:Connect(function()
					Context.remotes.DiscardItem:FireServer(id, 1)
					Audio.play("uiClick")
				end)
			end
		end
		if not any then
			local empty =
				create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = listFrame })
			local l = Builder.label("Empty. Search cars, crates, dumpsters and trash for materials.", 13, {
				TextColor3 = T.muted,
				TextWrapped = true,
				Size = UDim2.fromScale(1, 1),
				Parent = empty,
			})
			l.TextYAlignment = Enum.TextYAlignment.Top
		end
	end

	function self.toggle()
		self.open = not self.open
		panel.Visible = self.open
		Audio.play("uiClick")
		if self.open then
			renderPanel()
		end
	end

	for _, sig in { Context.signals.inventoryChanged, Context.signals.gearChanged } do
		sig:connect(function()
			if self.open then
				renderPanel()
			end
		end)
	end

	RunService.RenderStepped:Connect(function()
		local phase = Context.phase()
		local playing = phase ~= "lobby" and phase ~= "gameover"
		strip.Visible = playing
		if not playing and self.open then
			self.open = false
		end
		panel.Visible = self.open and playing
		if not playing then
			return
		end
		local inv = Context.inventory
		local weight = inv:weight()
		weightLabel.Text = `BAG {string.format("%.1f", weight)}/{inv.capacity} kg`
		local full = weight / math.max(1, inv.capacity)
		weightFill.Size = UDim2.fromScale(math.clamp(full, 0, 1), 1)
		weightFill.BackgroundColor3 = if full > 0.9 then T.warn else Color3.fromRGB(154, 216, 255)
		local mats = {}
		for _, id in Items.materials do
			table.insert(mats, `{SHORT[id]} {inv:count(id)}`)
		end
		matsLabel.Text = table.concat(mats, " · ")
		quickLabel.Text = `[B] Bandage ×{inv:count("bandage")}   [G] Pipe bomb ×{inv:count("pipebomb")}`
		local spotted = Context.player:GetAttribute("Spotted") == true
		local crouch = if Context.crouching then "CROUCHED · " else ""
		stealthLabel.Text = if spotted then `{crouch}SPOTTED` else `{crouch}HIDDEN`
		stealthLabel.TextColor3 = if spotted then T.danger else T.accent
	end)

	return self
end

return InventoryUI
