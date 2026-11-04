--[[
	The emote menu (T, D-pad left, or EMOTE on touch): the player's equipped
	emotes (Player attribute "Emotes", from their profile) as a row of
	buttons above the ability bar. Picking one asks the server to play it;
	the menu closes on its own. Emotes are earned from crates on the Home page.
]]
local GuiService = game:GetService("GuiService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Cosmetics = require(Shared.Cosmetics)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.theme

local EmoteMenu = {}

function EmoteMenu.new(gui: ScreenGui)
	local self = { open = false }
	local root = Builder.night.panel({
		Name = "EmoteMenu",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 58),
		Visible = false,
		Parent = gui,
	})
	Builder.padding(8).Parent = root
	local row = create("Frame", {
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 42),
		Parent = root,
	}, { Builder.list(6, true) })

	function self.hide()
		root.Visible = false
		self.open = false
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
	end

	function self.show(viaGamepad: boolean)
		for _, c in row:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local first: GuiObject? = nil
		local list = string.split(Context.player:GetAttribute("Emotes") or "", ",")
		for i, id in list do
			local item = Cosmetics.ITEMS[id]
			if item and item.kind == "emote" then
				local b = Builder.night.button(item.name, nil, function()
					Context.remotes.Emote:FireServer(id)
					Audio.play("uiClick")
					self.hide()
				end, { LayoutOrder = i, Size = UDim2.fromOffset(110, 42), TextSize = 16, Parent = row })
				first = first or b
			end
		end
		if not first then
			Builder.night.label("No emotes yet: open crates on the Home page.", 14, {
				TextColor3 = T.muted,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 42),
				Parent = row,
			})
		end
		root.Visible = true
		self.open = true
		if viaGamepad and first then
			GuiService.SelectedObject = first
		end
	end

	function self.toggle(viaGamepad: boolean)
		if self.open then
			self.hide()
		else
			self.show(viaGamepad)
		end
	end

	return self
end

return EmoteMenu
