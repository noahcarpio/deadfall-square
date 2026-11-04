--[[
	The bag strip on the HUD, under the vitals: weight, materials, quick items
	and the hidden / spotted status. The full inventory (I) is InventoryScreen.
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
