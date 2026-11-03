--[[
	Between-wave supply depot. Offers are computed with the same shared
	ShopRules the server uses (so prices always match); purchases are sent to
	the server, which validates and applies them.
]]
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Shop = require(Shared.Config.Shop)
local ShopRules = require(Shared.ShopRules)
local Weapons = require(Shared.Config.Weapons)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.theme

local ShopUI = {}

local UPGRADE_LABELS = { damage = "Damage", fireRate = "Fire rate", magazine = "Magazine" }

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
	}
end

function ShopUI.new(gui: ScreenGui, onPlace: (string) -> ())
	local self = { open = false }
	local root = Builder.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0.9, 0, 0.78, 0),
		BackgroundTransparency = 0.06,
		Visible = false,
		Parent = gui,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(1040, 640), Parent = root })
	Builder.padding(16).Parent = root
	local title = Builder.label("SUPPLY DEPOT", 30, { Font = T.head, Parent = root })
	local coins = Builder.label("", 26, {
		Font = T.head,
		TextColor3 = T.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})
	local tabs = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 42),
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
		CellSize = UDim2.new(0.25, -8, 0, 168),
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
	local hint = Builder.label("Barricades and turrets persist between waves. Ready up when you're done.", 14, {
		TextColor3 = T.muted,
		Size = UDim2.new(1, -260, 1, 0),
		Parent = footer,
	})
	hint.TextWrapped = true
	local readyButton = Builder.button("READY", "primary", nil, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(240, 46),
		Parent = footer,
	})

	local tab = "weapons"
	local render: () -> ()

	local function buy(action)
		local ok = Context.remotes.Purchase:InvokeServer(action)
		Audio.play(if ok then "uiBuy" else "uiDeny")
		task.wait(0.05)
		render()
	end

	local function buyButton(c, offer, label: string, onBuy: () -> ()): TextButton
		local affordable = c.economy.coins >= offer.cost
		local text = if offer.available then `{label} · {offer.cost}` else offer.reason
		local enabled = offer.available and affordable
		local b = Builder.button(text, nil, nil, {
			TextSize = 18,
			Size = UDim2.new(1, 0, 0, 30),
			TextColor3 = if enabled then T.gold elseif offer.available then T.danger else T.muted,
		})
		b.Activated:Connect(function()
			if not offer.available then
				return
			end
			if not affordable then
				Audio.play("uiDeny")
				return
			end
			onBuy()
		end)
		return b
	end

	local function card(order: number, titleText: string, desc: string?): Frame
		local f = Builder.panel({ LayoutOrder = order, Parent = body })
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

	local function rowWith(f: Frame, order: number, labelText: string, button: TextButton)
		local r = create("Frame", { BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 30), Parent = f })
		Builder.label(labelText, 13, { Size = UDim2.new(0.45, 0, 1, 0), Parent = r })
		button.Position = UDim2.fromScale(0.45, 0)
		button.Size = UDim2.new(0.55, 0, 1, 0)
		button.Parent = r
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
				b.TextColor3 = if b.Name == tab then T.accent else T.muted
			end
		end
		if tab == "weapons" then
			grid.CellSize = UDim2.new(0.25, -8, 0, 176)
			for i, id in Weapons.order do
				local def = Weapons.defs[id]
				local w = c.arsenal:get(id)
				if not w then
					local f = card(i, `{def.slot}  {def.name}`, def.description)
					local offer = ShopRules.getOffer(c, { kind = "buyWeapon", weapon = id })
					local b = buyButton(c, offer, "BUY", function()
						buy({ kind = "buyWeapon", weapon = id })
					end)
					b.LayoutOrder = 9
					b.Parent = f
				else
					local f = card(i, `{def.slot}  {def.name}`, nil)
					f.BackgroundColor3 = Color3.fromRGB(20, 32, 26)
					for k, kind in { "damage", "fireRate", "magazine" } do
						local action = { kind = "weaponUpgrade", weapon = id, upgrade = kind }
						local offer = ShopRules.getOffer(c, action)
						rowWith(f, k, `{UPGRADE_LABELS[kind]} {offer.tier}/{offer.maxTier}`, buyButton(c, offer, "UP", function()
							buy(action)
						end))
					end
					if def.reserveMax ~= math.huge then
						local action = { kind = "ammo", weapon = id }
						rowWith(f, 5, `Ammo {w.reserve}/{def.reserveMax}`, buyButton(c, ShopRules.getOffer(c, action), "FILL", function()
							buy(action)
						end))
					end
				end
			end
		elseif tab == "survivor" then
			grid.CellSize = UDim2.new(0.25, -8, 0, 140)
			local heal = { kind = "heal" }
			local f = card(0, "Field Medkit", `Restore health to full ({c.health} / {c.maxHealth}).`)
			local hb = buyButton(c, ShopRules.getOffer(c, heal), "HEAL", function()
				buy(heal)
			end)
			hb.LayoutOrder = 9
			hb.Parent = f
			for i, id in Shop.upgradeOrder do
				local def = Shop.playerUpgrades[id]
				local action = { kind = "playerUpgrade", id = id }
				local offer = ShopRules.getOffer(c, action)
				local uf = card(i, `{def.name}  {offer.tier}/{offer.maxTier}`, def.description)
				local b = buyButton(c, offer, "BUY", function()
					buy(action)
				end)
				b.LayoutOrder = 9
				b.Parent = uf
			end
		else
			grid.CellSize = UDim2.new(0.25, -8, 0, 140)
			for i, stype in Shop.structureOrder do
				local def = Shop.structures[stype]
				local offer = ShopRules.getOffer(c, { kind = "structure", structure = stype })
				local f = card(i, `{def.name}  {offer.tier}/{offer.maxTier}`, `{def.description} {def.hp} HP.`)
				local b = buyButton(c, offer, "PLACE", function()
					onPlace(stype)
				end)
				b.LayoutOrder = 9
				b.Parent = f
			end
			local repair = { kind = "repair" }
			local f = card(9, "Repair Kit", "Restore your barricades and turrets to full health.")
			local b = buyButton(c, ShopRules.getOffer(c, repair), "REPAIR", function()
				buy(repair)
			end)
			b.LayoutOrder = 9
			b.Parent = f
		end
	end

	for i, t in { { "weapons", "WEAPONS" }, { "survivor", "SURVIVOR" }, { "defenses", "DEFENSES" } } do
		local b = create("TextButton", {
			Name = t[1],
			LayoutOrder = i,
			Text = t[2],
			Font = T.head,
			TextSize = 22,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(130, 34),
			TextColor3 = T.muted,
			Parent = tabs,
		})
		b.Activated:Connect(function()
			tab = t[1]
			Audio.play("uiClick")
			render()
		end)
	end

	readyButton.Activated:Connect(function()
		local ready = not (Context.player:GetAttribute("Ready") == true)
		Context.remotes.Ready:FireServer(ready)
		Audio.play("uiClick")
	end)

	function self.show(wave: number)
		title.Text = `WAVE {wave} CLEARED — SUPPLY DEPOT`
		root.Visible = true
		self.open = true
		render()
	end

	function self.hide()
		root.Visible = false
		self.open = false
	end

	function self.update()
		if not self.open then
			return
		end
		local ready = Context.player:GetAttribute("Ready") == true
		readyButton.Text = if ready then "WAITING… (CANCEL)" else "READY"
		coins.Text = `● {Context.player:GetAttribute("Coins") or 0}`
	end

	Context.signals.arsenalChanged:connect(function()
		if self.open then
			render()
		end
	end)
	Context.signals.statsChanged:connect(function()
		if self.open then
			render()
		end
	end)

	return self
end

return ShopUI
