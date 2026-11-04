--[[
	The merchant and workbench panels, docked to the right so the player can
	keep walking (walking away closes them). Opened by walking up to them in the
	plaza during the grace period. Offers are computed with the same shared
	ShopRules the server uses (so prices always match); every action is sent
	to the server, which checks the player's distance and applies it.

	  merchant  - WEAPONS (buy guns, refill ammo), GEAR (melee, armor and
	              gadgets), SURVIVOR (medkit and upgrades), SUPPLIES
	  workbench - CRAFT (bandages, pipe bombs, hand-loaded ammo), BUILD
	              (barricades, turrets, repairs), UPGRADES (weapon upgrades),
	              GEAR (salvage, reinforce, re-roll traits)
]]
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Items = require(Shared.Config.Items)
local Shop = require(Shared.Config.Shop)
local ShopRules = require(Shared.ShopRules)
local Weapons = require(Shared.Config.Weapons)
local Arsenal = require(Shared.Arsenal)
local Gear = require(Shared.Gear)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.paper
local S = Constants.STUDS

local StationUI = {}

local UPGRADE_LABELS = { damage = "Damage", fireRate = "Fire rate", magazine = "Magazine" }

local TABS = {
	merchant = {
		{ "weapons", "WEAPONS" },
		{ "gearShop", "GEAR" },
		{ "survivor", "SURVIVOR" },
		{ "supplies", "SUPPLIES" },
	},
	workbench = { { "craft", "CRAFT" }, { "build", "BUILD" }, { "upgrade", "UPGRADES" }, { "gearBench", "GEAR" } },
}

local TITLES = {
	merchant = "MERCHANT",
	workbench = "WORKBENCH",
}

-- "2 Rags · 1 Electronics" for a materials cost.
local function materialsText(items: { [string]: number }?): string
	if not items then
		return ""
	end
	local parts = {}
	for _, id in Items.order do
		local n = items[id]
		if n and n > 0 then
			table.insert(parts, `{n} {Items.defs[id].name}`)
		end
	end
	return table.concat(parts, " · ")
end

-- Every gear piece the player has: equipped first, then the stash.
local function allGear(): { any }
	local g = Context.gear
	local out = {}
	if g.melee then
		table.insert(out, g.melee)
	end
	if g.armor then
		table.insert(out, g.armor)
	end
	for _, item in g.gadgets do
		if item then
			table.insert(out, item)
		end
	end
	for _, id in Gear.order do
		if g.guns[id] then
			table.insert(out, g.guns[id])
		end
	end
	for _, item in g.stash do
		table.insert(out, item)
	end
	return out
end

-- Client mirror of the server's shop context (read-only; for display).
local function context()
	local p = Context.player
	local myName = p.DisplayName
	local structures = Workspace:FindFirstChild("Structures")
	local counts = { barricade = 0, turret = 0 }
	local missing = 0
	if structures then
		for _, m in structures:GetChildren() do
			if m:GetAttribute("Owner") == myName then
				local stype = if m.Name == Shop.structures.turret.name then "turret" else "barricade"
				counts[stype] += 1
				missing += (m:GetAttribute("MaxHP") or 0) - (m:GetAttribute("HP") or 0)
			end
		end
	end
	return {
		economy = {
			coins = p:GetAttribute("Coins") or 0,
			spend = function()
				return true
			end,
		},
		arsenal = Context.arsenal,
		inventory = Context.inventory,
		health = p:GetAttribute("HP") or 0,
		maxHealth = p:GetAttribute("MaxHP") or 100,
		tiers = Context.tiers,
		structureCount = function(t: string)
			return counts[t] or 0
		end,
		structuresMissingHp = missing,
		applyPlayerUpgrade = function() end,
		healFull = function() end,
		repairStructures = function() end,
		gear = {
			find = function(uid: number)
				for _, item in allGear() do
					if item.uid == uid then
						return item
					end
				end
				return nil
			end,
			stashFull = function()
				return #Context.gear.stash >= Gear.STASH_SIZE
			end,
			give = function()
				return true
			end,
			remove = function()
				return true
			end,
			newUid = function()
				return 0
			end,
			rng = nil,
		},
	}
end

function StationUI.new(gui: ScreenGui, onPlace: (string) -> (), onSell: () -> ())
	local self: any = { open = false, station = "merchant" }
	local stationX, stationZ = 0, 0
	local root = Builder.panel({
		Name = "Station",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.new(0.48, 0, 0.86, 0),
		BackgroundTransparency = 0.06,
		Visible = false,
		Parent = gui,
	})
	create("UISizeConstraint", { MinSize = Vector2.new(360, 0), MaxSize = Vector2.new(640, 720), Parent = root })
	Builder.padding(16).Parent = root
	local title = Builder.label("", 30, { Font = T.head, Parent = root })
	local coins = Builder.label("", 20, {
		Font = T.mono,
		TextColor3 = T.rust,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	Builder.rule({
		BackgroundColor3 = T.border,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 0, 2),
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
		Position = UDim2.fromOffset(0, 84),
		Size = UDim2.new(1, 0, 1, -140),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = root,
	})
	local grid = create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -8, 0, 168),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = body,
	})
	local footer = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 46),
		Parent = root,
	})
	local bag = Builder.label("", 14, {
		TextColor3 = T.muted,
		Size = UDim2.new(1, -330, 1, 0),
		TextWrapped = true,
		Parent = footer,
	})
	local leaveButton = Builder.button("LEAVE", "primary", nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(160, 46),
		Parent = footer,
	})
	-- Merchant only: sell guns, gear and items from the inventory.
	local sellButton = Builder.button("SELL", nil, nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -170, 0, 0),
		Size = UDim2.fromOffset(140, 46),
		TextColor3 = T.gold,
		Parent = footer,
	})
	sellButton.Activated:Connect(function()
		Audio.play("uiClick")
		onSell()
	end)

	local tab = "weapons"
	local render: () -> ()

	local function act(action)
		local ok = Context.remotes.Purchase:InvokeServer(action)
		Audio.play(if ok then "uiBuy" else "uiDeny")
		task.wait(0.05)
		if self.open then
			render()
		end
	end

	local function actionButton(c, offer, label: string, onUse: () -> ()): TextButton
		local canPay = ShopRules.affordable(c, offer)
		local text = if not offer.available
			then offer.reason
			elseif offer.cost > 0 then `{label} · {offer.cost}`
			else label
		local b = Builder.button(text, nil, nil, {
			TextSize = 18,
			Size = UDim2.new(1, 0, 0, 30),
			TextColor3 = if canPay then T.gold elseif offer.available then T.danger else T.muted,
		})
		b.Activated:Connect(function()
			if not offer.available then
				return
			end
			if not canPay then
				Audio.play("uiDeny")
				return
			end
			onUse()
		end)
		return b
	end

	local function card(order: number, titleText: string, desc: string?): Frame
		local f = Builder.panel({ LayoutOrder = order, Parent = body })
		local edge = f:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Thickness = 1
		end
		Builder.padding(10).Parent = f
		Builder.list(4).Parent = f
		Builder.label(titleText, 20, { Font = T.head, LayoutOrder = 0, Parent = f })
		if desc then
			local d = Builder.label(desc, 13, { TextColor3 = T.muted, LayoutOrder = 1, Parent = f })
			d.TextWrapped = true
			d.Size = UDim2.new(1, 0, 0, 34)
		end
		return f
	end

	-- A "needs: ..." line, red when the bag is short.
	local function needs(f: Frame, order: number, c, items: { [string]: number }?)
		if not items or next(items) == nil then
			return
		end
		local l = Builder.label(`Needs {materialsText(items)}`, 13, {
			TextColor3 = if c.inventory:has(items) then T.accent else T.danger,
			LayoutOrder = order,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 30),
			Parent = f,
		})
		l.TextYAlignment = Enum.TextYAlignment.Top
	end

	local function rowWith(f: Frame, order: number, labelText: string, button: TextButton)
		local r = create(
			"Frame",
			{ BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 30), Parent = f }
		)
		local l = Builder.label(labelText, 13, { Size = UDim2.new(0.5, 0, 1, 0), Parent = r })
		l.TextWrapped = true
		button.Position = UDim2.fromScale(0.5, 0)
		button.Size = UDim2.new(0.5, 0, 1, 0)
		button.Parent = r
	end

	local function simpleCard(c, order: number, titleText: string, desc: string, action, label: string, onUse)
		local f = card(order, titleText, desc)
		local o = ShopRules.getOffer(c, action)
		needs(f, 8, c, o.items)
		local b = actionButton(c, o, label, onUse or function()
			act(action)
		end)
		b.LayoutOrder = 9
		b.Parent = f
		return f
	end

	local renderers = {}

	-- Slot number (1-3) of an owned gun.
	local function slotOf(c, id: string): number
		for n, w in c.arsenal:list() do
			if w.id == id then
				return n
			end
		end
		return 0
	end

	function renderers.weapons(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 150)
		-- Buying with every gun slot full drops the gun in hand (else slot 2).
		local swap = c.arsenal:swapTarget()
		local full = c.arsenal:gunCount() >= Arsenal.MAX_GUNS
		for i, id in Weapons.order do
			local def = Weapons.defs[id]
			local w = c.arsenal:get(id)
			if not w then
				local note = if full and swap
					then `{def.description}\nSlots full: drops your {Weapons.defs[swap].name}.`
					else def.description
				simpleCard(c, i, def.name, note, { kind = "buyWeapon", weapon = id }, if full then "SWAP" else "BUY")
			elseif def.reserveMax ~= math.huge then
				local f = card(i, `{slotOf(c, id)}  {def.name}`, "Owned. Upgrade it at the workbench.")
				f.BackgroundColor3 = T.shade
				local action = { kind = "ammo", weapon = id }
				rowWith(
					f,
					5,
					`Ammo {w.reserve}/{def.reserveMax}`,
					actionButton(c, ShopRules.getOffer(c, action), "FILL", function()
						act(action)
					end)
				)
			else
				local f = card(i, `{slotOf(c, id)}  {def.name}`, "Owned. Infinite ammo.")
				f.BackgroundColor3 = T.shade
			end
		end
	end

	function renderers.gearShop(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 160)
		local order = 0
		for _, id in Gear.order do
			local d = Gear.defs[id]
			if d.price > 0 then
				order += 1
				simpleCard(c, order, d.name, d.description, { kind = "buyGear", id = id }, "BUY")
			end
		end
	end

	function renderers.gearBench(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 186)
		local stashed = {}
		for _, item in Context.gear.stash do
			stashed[item.uid] = true
		end
		for order, item in allGear() do
			local f = card(order, Gear.title(item), table.concat(Gear.describe(item), " · "))
			f.BackgroundColor3 = T.panel
			local reinforce = { kind = "reinforce", uid = item.uid }
			local ro = ShopRules.getOffer(c, reinforce)
			rowWith(
				f,
				5,
				`+0.1 power · {materialsText(ro.items)}`,
				actionButton(c, ro, "REINFORCE", function()
					act(reinforce)
				end)
			)
			local reroll = { kind = "reroll", uid = item.uid }
			local rr = ShopRules.getOffer(c, reroll)
			rowWith(
				f,
				6,
				`New trait · {materialsText(rr.items)}`,
				actionButton(c, rr, "RE-ROLL", function()
					act(reroll)
				end)
			)
			if stashed[item.uid] then
				local salvage = { kind = "salvage", uid = item.uid }
				rowWith(
					f,
					7,
					`→ {materialsText(Gear.salvageValue(item))}`,
					actionButton(c, ShopRules.getOffer(c, salvage), "SALVAGE", function()
						act(salvage)
					end)
				)
			end
		end
	end

	function renderers.survivor(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 140)
		simpleCard(
			c,
			0,
			"Field Medkit",
			`Restore health to full ({c.health} / {c.maxHealth}).`,
			{ kind = "heal" },
			"HEAL"
		)
		for i, id in Shop.upgradeOrder do
			local def = Shop.playerUpgrades[id]
			local action = { kind = "playerUpgrade", id = id }
			local o = ShopRules.getOffer(c, action)
			simpleCard(c, i, `{def.name}  {o.tier}/{o.maxTier}`, def.description, action, "BUY")
		end
	end

	function renderers.supplies(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 140)
		for i, id in Shop.itemShopOrder do
			local def = Items.defs[id]
			simpleCard(
				c,
				i,
				`{def.name}  ×{c.inventory:count(id)}`,
				`{def.description} ({def.weight} kg)`,
				{ kind = "buyItem", id = id },
				"BUY"
			)
		end
	end

	function renderers.craft(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 170)
		for i, id in Shop.recipeOrder do
			local recipe = Shop.recipes[id]
			local def = Items.defs[recipe.item]
			simpleCard(
				c,
				i,
				`{def.name}  ×{c.inventory:count(recipe.item)}`,
				`{def.description} Use with [{def.key}].`,
				{ kind = "craft", id = id },
				"CRAFT"
			)
		end
		local order = 10
		for _, id in Weapons.order do
			local def = Weapons.defs[id]
			local w = c.arsenal:get(id)
			if w and def.reserveMax ~= math.huge then
				order += 1
				simpleCard(
					c,
					order,
					`Hand-load: {def.name}`,
					`+{math.floor(Shop.handload.fraction * 100)}% ammo ({w.reserve}/{def.reserveMax}).`,
					{ kind = "handload", weapon = id },
					"LOAD"
				)
			end
		end
	end

	function renderers.build(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 170)
		for i, stype in Shop.structureOrder do
			local def = Shop.structures[stype]
			local action = { kind = "structure", structure = stype }
			local o = ShopRules.getOffer(c, action)
			simpleCard(
				c,
				i,
				`{def.name}  {o.tier}/{o.maxTier}`,
				`{def.description} {def.hp} HP.`,
				action,
				"PLACE",
				function()
					onPlace(stype)
				end
			)
		end
		simpleCard(
			c,
			9,
			"Repair",
			`Patch your barricades and turrets with planks (1 per {Shop.repairHpPerWood} HP).`,
			{ kind = "repair" },
			"REPAIR"
		)
	end

	function renderers.upgrade(c)
		grid.CellSize = UDim2.new(0.5, -8, 0, 176)
		local order = 0
		for _, id in Weapons.order do
			local def = Weapons.defs[id]
			if c.arsenal:get(id) then
				order += 1
				local f = card(order, `{slotOf(c, id)}  {def.name}`, nil)
				for k, kind in { "damage", "fireRate", "magazine" } do
					local action = { kind = "weaponUpgrade", weapon = id, upgrade = kind }
					local o = ShopRules.getOffer(c, action)
					local label = `{UPGRADE_LABELS[kind]} {o.tier}/{o.maxTier}`
					if o.available and o.items then
						label ..= `\n{materialsText(o.items)}`
					end
					rowWith(
						f,
						k,
						label,
						actionButton(c, o, "UP", function()
							act(action)
						end)
					)
				end
			end
		end
	end

	render = function()
		for _, c in body:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local c = context()
		coins.Text = `● {c.economy.coins}`
		for _, b in tabs:GetChildren() do
			if b:IsA("TextButton") then
				b.TextColor3 = if b.Name == tab then T.text else T.muted
				local underline = b:FindFirstChild("Underline")
				if underline and underline:IsA("Frame") then
					underline.Visible = b.Name == tab
				end
			end
		end
		renderers[tab](c)
	end

	local function buildTabs()
		for _, b in tabs:GetChildren() do
			if b:IsA("TextButton") then
				b:Destroy()
			end
		end
		for i, t in TABS[self.station] do
			local b = create("TextButton", {
				Name = t[1],
				LayoutOrder = i,
				Text = `<font face="SpecialElite" size="14">{string.format("%02d", i)}</font>  {t[2]}`,
				RichText = true,
				Font = T.head,
				TextSize = 20,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(140, 32),
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
	end

	leaveButton.Activated:Connect(function()
		Audio.play("uiClick")
		self.hide()
	end)

	function self.show(station: string, x: number, z: number)
		if not TABS[station] then
			return
		end
		if self.station ~= station or not self.open then
			tab = TABS[station][1][1]
		end
		self.station = station
		stationX, stationZ = x, z
		title.Text = TITLES[station]
		sellButton.Visible = station == "merchant"
		buildTabs()
		root.Visible = true
		self.open = true
		render()
		ContextActionService:BindActionAtPriority("DeadfallLeaveStation", function(_, state)
			if state == Enum.UserInputState.Begin then
				self.hide()
			end
			return Enum.ContextActionResult.Sink
		end, false, 4000, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	end

	function self.hide()
		if self.open then
			ContextActionService:UnbindAction("DeadfallLeaveStation")
		end
		root.Visible = false
		self.open = false
	end

	-- Called every frame: coins, bag, timer, and closing when the player walks off.
	function self.update()
		if not self.open then
			return
		end
		coins.Text = `● {Context.player:GetAttribute("Coins") or 0}`
		local left =
			math.max(0, math.ceil((Context.gameState:GetAttribute("PhaseEnd") or 0) - Workspace:GetServerTimeNow()))
		local inv = Context.inventory
		local timing = if Context.phase() == "intermission" then `next floor in {left}s` else "floor in progress"
		bag.Text =
			`Bag {string.format("%.1f", inv:weight())}/{inv.capacity} kg · {timing} · walk away or Esc to leave`
		local character = Context.character()
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local p = rootPart.Position / S
			local range = Constants.STATION_RANGE + 2
			if (p.X - stationX) ^ 2 + (p.Z - stationZ) ^ 2 > range * range then
				self.hide()
			end
		end
	end

	for _, sig in
		{
			Context.signals.arsenalChanged,
			Context.signals.statsChanged,
			Context.signals.inventoryChanged,
			Context.signals.gearChanged,
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

return StationUI
