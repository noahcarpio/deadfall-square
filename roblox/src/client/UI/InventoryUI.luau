--[[
	The bag: a compact HUD strip under the vitals (weight, materials, quick
	items, stealth status) and a full panel (Tab / D-pad right / BAG) listing
	every item with Use and Drop buttons.
]]
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)

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
		Size = UDim2.fromOffset(320, 330),
		Visible = false,
		Parent = gui,
	})
	Builder.padding(10).Parent = panel
	Builder.label("BAG", 24, { Font = T.head, Parent = panel })
	local listFrame = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -32),
		Parent = panel,
	}, { Builder.list(4) })

	local function renderPanel()
		for _, c in listFrame:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
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
			local empty = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), Parent = listFrame })
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

	Context.signals.inventoryChanged:connect(function()
		if self.open then
			renderPanel()
		end
	end)

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
