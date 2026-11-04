--[[
	The bag strip on the HUD, under the vitals: weight, materials and quick
	items. The full inventory (I) is InventoryScreen.
]]
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Items = require(Shared.Config.Items)

local Context = require(script.Parent.Parent.Context)
local Builder = require(script.Parent.Builder)

local T = Builder.theme

local SHORT = { scrap = "Scrap", wood = "Wood", cloth = "Rags", parts = "Elec", gunpowder = "Powder" }

local InventoryUI = {}

function InventoryUI.new(gui: ScreenGui)
	local self = {}

	-------------------------------------------------- HUD strip
	local strip = Builder.night.panel({
		Name = "Bag",
		Position = UDim2.fromOffset(14, 126),
		Size = UDim2.fromOffset(250, 82),
		Parent = gui,
	})
	Builder.padding(8).Parent = strip
	local weightLabel = Builder.night.label("", 13, { Font = T.bold, Size = UDim2.new(1, 0, 0, 16), Parent = strip })
	local weightBar, weightFill = Builder.night.bar(T.text, 4)
	weightBar.Position = UDim2.fromOffset(0, 19)
	weightBar.Parent = strip
	local matsLabel = Builder.night.label("", 12, {
		TextColor3 = T.muted,
		Position = UDim2.fromOffset(0, 27),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = strip,
	})
	local quickLabel = Builder.night.label("", 13, {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = strip,
	})

	RunService.RenderStepped:Connect(function()
		local phase = Context.phase()
		local playing = phase ~= "lobby" and phase ~= "gameover"
		strip.Visible = playing
		if not playing then
			return
		end
		local inv = Context.inventory
		local weight = inv:weight()
		weightLabel.Text = `BAG {string.format("%.1f", weight)}/{inv.capacity} kg`
		local full = weight / math.max(1, inv.capacity)
		weightFill.Size = UDim2.fromScale(math.clamp(full, 0, 1), 1)
		weightFill.BackgroundColor3 = if full > 0.9 then T.rust else T.text
		local mats = {}
		for _, id in Items.materials do
			table.insert(mats, `{SHORT[id]} {inv:count(id)}`)
		end
		matsLabel.Text = table.concat(mats, " · ")
		quickLabel.Text = `[B] Bandage ×{inv:count("bandage")}   [G] Pipe bomb ×{inv:count("pipebomb")}`
	end)

	return self
end

return InventoryUI
