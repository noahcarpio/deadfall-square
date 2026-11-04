--[[
	The full-screen inventory (I / D-pad right / BAG). Usable anywhere:
	  GUNS  - every gun you own: hold it, drop it, sell it
	  GEAR  - what's equipped (melee, armor, gadgets, gun gear) and the stash:
	          equip, drop, sell
	  ITEMS - materials and consumables: use, drop, sell (one or all)
	Dropping leaves things on the ground for anyone to pick up. Selling only
	works while you stand at the merchant, who trades for the whole run; the
	server checks that again and decides the price.
]]
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Gear = require(Shared.Gear)
local Items = require(Shared.Config.Items)
local ShopRules = require(Shared.ShopRules)
local Weapons = require(Shared.Config.Weapons)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.paper
local S = Constants.STUDS

local InventoryScreen = {}

local TABS = { { "guns", "GUNS" }, { "gear", "GEAR" }, { "items", "ITEMS" } }

-- True when the player stands at the merchant while it's trading.
local function atMerchant(): boolean
	local phase = Context.phase()
	if phase == "waiting" or phase == "gameover" then
		return false
	end
	local stations = Workspace:FindFirstChild("Stations")
	local anchor = stations and stations:FindFirstChild("merchant") :: BasePart?
	local character = Context.character()
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not anchor or not root then
		return false
	end
	local d = (root.Position - anchor.Position) * Vector3.new(1, 0, 1)
	return d.Magnitude / S <= Constants.STATION_RANGE + 0.5
end

-- Read-only mirror of the server's shop context, enough to price sales.
local function context()
	local g = Context.gear
	local function inStash(uid: number): boolean
		for _, item in g.stash do
			if item.uid == uid then
				return true
			end
		end
		return false
	end
	return {
		economy = { coins = Context.player:GetAttribute("Coins") or 0 },
		arsenal = Context.arsenal,
		inventory = Context.inventory,
		health = 0,
		maxHealth = 0,
		tiers = Context.tiers,
		structureCount = function()
			return 0
		end,
		structuresMissingHp = 0,
		gear = {
			find = function(uid: number)
				for _, item in g.stash do
					if item.uid == uid then
						return item
					end
				end
				return nil
			end,
			inStash = inStash,
			stashFull = function()
				return #g.stash >= Gear.STASH_SIZE
			end,
		},
	} :: any
end

function InventoryScreen.new(gui: ScreenGui, onUseItem: (string) -> ())
	local self: any = { open = false }
	local root = Builder.panel({
		Name = "Inventory",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.48, 0, 0.86, 0),
		BackgroundTransparency = 0.04,
		Visible = false,
		Parent = gui,
	})
	create("UISizeConstraint", { MinSize = Vector2.new(360, 0), MaxSize = Vector2.new(640, 720), Parent = root })
	Builder.padding(16).Parent = root
	Builder.label("INVENTORY", 30, { Font = T.head, Parent = root })
	Builder.rule({
		BackgroundColor3 = T.border,
		Position = UDim2.fromOffset(0, 42),
		Size = UDim2.new(1, 0, 0, 2),
		Parent = root,
	})
	local header = Builder.label("", 16, {
		Font = T.mono,
		TextColor3 = T.text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, -120, 0, 24),
		Parent = root,
	})
	local status = Builder.label("", 14, {
		Font = T.type,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, -120, 0, 18),
		Parent = root,
	})
	local closeButton = Builder.button("CLOSE", "primary", nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(110, 40),
		Parent = root,
	})
	local tabs = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 34),
		Parent = root,
	}, { Builder.list(8, true) })
	local body = create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 1, -88),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = root,
	})
	create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 170),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})

	local tab = "guns"
	local selling = false
	local openedAtMerchant = false
	local render: () -> ()

	local function sell(action)
		if not selling then
			Audio.play("uiDeny")
			return
		end
		local ok = Context.remotes.Purchase:InvokeServer(action)
		Audio.play(if ok then "uiBuy" else "uiDeny")
		task.wait(0.05)
		if self.open then
			render()
		end
	end

	-- A card with a coloured title, detail lines and a row of buttons { label, colour, enabled, onClick }.
	local function card(order: number, title: string, color: Color3, lines: { string }, buttons: { { any } })
		local f = Builder.panel({ LayoutOrder = order, Parent = body })
		local edge = f:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Thickness = 1
		end
		Builder.padding(10).Parent = f
		Builder.label(string.upper(title), 19, {
			Font = T.head,
			TextColor3 = if color == T.muted then T.muted else T.text,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, -70, 0, 24),
			Parent = f,
		})
		-- Rarity is an ink stamp in the corner, never a coloured card.
		local rarity = if color == Builder.rarityColor("unique")
			then "Unique"
			elseif color == Builder.rarityColor("rare") then "Rare"
			else nil
		if rarity then
			Builder.stamp(rarity, color, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Parent = f,
			})
		end
		local text = Builder.label(table.concat(lines, "\n"), 12, {
			TextColor3 = T.muted,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, 26),
			Size = UDim2.new(1, 0, 1, -64),
			Parent = f,
		})
		text.TextYAlignment = Enum.TextYAlignment.Top
		local row = create("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 30),
			Parent = f,
		}, { Builder.list(6, true) })
		for i, b in buttons do
			local enabled = b[3] ~= false
			local button = Builder.button(b[1], nil, nil, {
				LayoutOrder = i,
				TextSize = 15,
				Size = UDim2.new(1 / #buttons, -6, 1, 0),
				TextColor3 = if enabled then (b[2] or T.text) else T.muted,
				Parent = row,
			})
			button.Activated:Connect(function()
				if not enabled then
					Audio.play("uiDeny")
					return
				end
				b[4]()
			end)
		end
		return f
	end

	local function sellButton(c, action): { any }
		local o = ShopRules.getOffer(c, action)
		local label = if o.available and o.gain then `SELL {o.gain}` else o.reason
		return {
			label,
			T.gold,
			selling and o.available,
			function()
				sell(action)
			end,
		}
	end

	local renderers = {}

	function renderers.guns(c)
		for i, id in Weapons.order do
			local w = c.arsenal:get(id)
			if w then
				local def = Weapons.defs[id]
				local gear = w.gear
				local color = if gear then Builder.rarityColor(gear.rarity) else T.text
				local title = if gear then `{Gear.rarities[gear.rarity].name} {def.name}` else def.name
				local lines = {
					`Damage {math.floor(Weapons.damageOf(def, w.upgrades) * c.arsenal:powerOf(id) + 0.5)} · {string.format(
						"%.1f",
						Weapons.fireRateOf(def, w.upgrades)
					)} shots/s`,
					if def.reserveMax == math.huge then "Ammo: infinite" else `Ammo {w.mag} + {w.reserve}`,
					`Upgrades: dmg {w.upgrades.damage} · rate {w.upgrades.fireRate} · mag {w.upgrades.magazine}`,
				}
				if gear then
					for _, t in gear.traits do
						table.insert(lines, `{Gear.traits[t].name}: {Gear.traits[t].description}`)
					end
				end
				local buttons = {
					{
						if c.arsenal.current == id then "HOLDING" else "HOLD",
						T.accent,
						c.arsenal.current ~= id,
						function()
							if Context.arsenal:switchTo(id, os.clock()) then
								Context.remotes.Switch:FireServer(id)
								Context.signals.arsenalChanged:fire()
							end
							Audio.play("uiClick")
						end,
					},
				}
				if id ~= "pistol" then
					table.insert(buttons, {
						"DROP",
						T.danger,
						true,
						function()
							Context.remotes.DropGun:FireServer(id)
							Audio.play("uiClick")
						end,
					})
					table.insert(buttons, sellButton(c, { kind = "sellGun", weapon = id }))
				end
				card(i, `{def.slot}  {title}`, color, lines, buttons)
			end
		end
	end

	function renderers.gear(c)
		local g = Context.gear
		local order = 0
		local function equipped(label: string, item: any)
			order += 1
			if item then
				card(
					order,
					`{label}: {Gear.title(item)}`,
					Builder.rarityColor(item.rarity),
					Gear.describe(item),
					{ { "EQUIPPED", T.muted, false, function() end } }
				)
			else
				card(order, `{label}: empty`, T.muted, { "Equip something from the stash below." }, {})
			end
		end
		equipped("MELEE", g.melee or nil)
		equipped("ARMOR", g.armor or nil)
		for i = 1, Gear.GADGET_SLOTS do
			equipped(`GADGET {({ "Z", "X", "V" })[i]}`, g.gadgets[i] or nil)
		end
		order = 100
		for _, item in g.stash do
			order += 1
			local buttons = {}
			if item.kind == "gadget" then
				for slot = 1, Gear.GADGET_SLOTS do
					table.insert(buttons, {
						`→{({ "Z", "X", "V" })[slot]}`,
						T.accent,
						true,
						function()
							Context.remotes.EquipGear:FireServer(item.uid, slot)
							Audio.play("uiBuy")
						end,
					})
				end
			else
				table.insert(buttons, {
					"EQUIP",
					T.accent,
					true,
					function()
						Context.remotes.EquipGear:FireServer(item.uid, nil)
						Audio.play("uiBuy")
					end,
				})
			end
			table.insert(buttons, {
				"DROP",
				T.danger,
				true,
				function()
					Context.remotes.DropGear:FireServer(item.uid)
					Audio.play("uiClick")
				end,
			})
			table.insert(buttons, sellButton(c, { kind = "sellGear", uid = item.uid }))
			card(order, `STASH: {Gear.title(item)}`, Builder.rarityColor(item.rarity), Gear.describe(item), buttons)
		end
	end

	function renderers.items(c)
		local any = false
		for i, id in Items.order do
			local n = c.inventory:count(id)
			if n > 0 then
				any = true
				local def = Items.defs[id]
				local buttons = {}
				if def.use then
					table.insert(buttons, {
						"USE",
						T.accent,
						true,
						function()
							onUseItem(id)
						end,
					})
				end
				table.insert(buttons, {
					"DROP 1",
					T.danger,
					true,
					function()
						Context.remotes.DiscardItem:FireServer(id, 1)
						Audio.play("uiClick")
					end,
				})
				if n > 1 then
					table.insert(buttons, {
						"DROP ALL",
						T.danger,
						true,
						function()
							Context.remotes.DiscardItem:FireServer(id, n)
							Audio.play("uiClick")
						end,
					})
				end
				table.insert(buttons, sellButton(c, { kind = "sellItem", id = id, count = 1 }))
				if n > 1 then
					table.insert(buttons, sellButton(c, { kind = "sellItem", id = id, count = n }))
				end
				card(i, `{def.name}  ×{n}`, T.text, {
					def.description,
					`{string.format("%.1f", def.weight * n)} kg`,
					`Sells for {ShopRules.itemSellValue(id)} each`,
				}, buttons)
			end
		end
		if not any then
			card(1, "Empty", T.muted, { "Search cars, crates, dumpsters and trash for materials." }, {})
		end
	end

	render = function()
		for _, child in body:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		for _, b in tabs:GetChildren() do
			if b:IsA("TextButton") then
				b.TextColor3 = if b.Name == tab then T.text else T.muted
				local underline = b:FindFirstChild("Underline")
				if underline and underline:IsA("Frame") then
					underline.Visible = b.Name == tab
				end
			end
		end
		renderers[tab](context())
	end

	for i, t in TABS do
		local b = create("TextButton", {
			Name = t[1],
			LayoutOrder = i,
			Text = `<font face="SpecialElite" size="14">{string.format("%02d", i)}</font>  {t[2]}`,
			RichText = true,
			Font = T.head,
			TextSize = 20,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(120, 32),
			TextColor3 = T.muted,
			Parent = tabs,
		})
		create("Frame", {
			Name = "Underline",
			BackgroundColor3 = T.rust,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 2),
			Size = UDim2.new(1, -16, 0, 3),
			Visible = false,
			Parent = b,
		})
		b.Activated:Connect(function()
			tab = t[1]
			Audio.play("uiClick")
			render()
		end)
	end

	-- `fromMerchant`: opened with the merchant's SELL button, so it closes when the player walks off.
	function self.show(startTab: string?, fromMerchant: boolean?)
		if startTab then
			tab = startTab
		end
		root.Visible = true
		self.open = true
		selling = atMerchant()
		openedAtMerchant = fromMerchant == true
		render()
		ContextActionService:BindActionAtPriority("DeadfallCloseInventory", function(_, state)
			if state == Enum.UserInputState.Begin then
				self.hide()
			end
			return Enum.ContextActionResult.Sink
		end, false, 4000, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	end

	function self.hide()
		if self.open then
			ContextActionService:UnbindAction("DeadfallCloseInventory")
		end
		root.Visible = false
		self.open = false
	end

	function self.toggle()
		Audio.play("uiClick")
		if self.open then
			self.hide()
		else
			self.show(nil)
		end
	end

	closeButton.Activated:Connect(function()
		Audio.play("uiClick")
		self.hide()
	end)

	-- Called every frame: header, and whether selling is possible right now.
	function self.update()
		if not self.open then
			return
		end
		local inv = Context.inventory
		header.Text =
			`● {Context.player:GetAttribute("Coins") or 0}    BAG {string.format("%.1f", inv:weight())}/{inv.capacity} kg    STASH {#Context.gear.stash}/{Gear.STASH_SIZE}`
		local now = atMerchant()
		status.Text = if now then "SELLING OPEN — you're at the merchant" else "Sell at the merchant (open all run)"
		status.TextColor3 = if now then T.accent else T.muted
		if openedAtMerchant and not now then
			self.hide()
			return
		end
		if now ~= selling then
			selling = now
			render()
		end
	end

	for _, sig in
		{
			Context.signals.arsenalChanged,
			Context.signals.inventoryChanged,
			Context.signals.gearChanged,
			Context.signals.statsChanged,
		}
	do
		sig:connect(function()
			if self.open then
				render()
			end
		end)
	end

	return self
end

return InventoryScreen
