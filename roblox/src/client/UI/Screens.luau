--[[
	Full-screen overlays: the reward choice (1 of 3) and the end-of-run
	summary. The title page, parties and leaderboard live on the Home place.
]]
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Places = require(Shared.Config.Places)
local RewardRules = require(Shared.RewardRules)
local ZombiesConfig = require(Shared.Config.Zombies)
local MathUtil = require(Shared.Util.MathUtil)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.paper

local Screens = {}

-- After game over the server teleports everyone Home, except in Studio or before the IDs are set.
local goesHome = Places.HOME_PLACE_ID ~= 0 and not RunService:IsStudio()

local function backdrop(gui: ScreenGui, name: string): Frame
	return create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		-- Full-screen menus are pages of the field manual.
		BackgroundColor3 = T.bg,
		BackgroundTransparency = 0.03,
		Visible = false,
		Parent = gui,
	})
end

------------------------------------------------------------------ perks

function Screens.rewards(gui: ScreenGui)
	local root = backdrop(gui, "Rewards")
	local title = Builder.label("CHOOSE A REWARD", 40, {
		Font = T.head,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0, 0.14),
		Parent = root,
	})
	local sub = Builder.label("Pick one. Gear goes to your stash: equip it from the bag (I).", 16, {
		TextColor3 = T.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.14, 54),
		Parent = root,
	})
	local row = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(780, 330),
		Parent = root,
	})
	local layout = Builder.list(16, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row

	local self: any = { open = false, onChosen = nil }
	function self.show(cards: { any }, floor: number)
		for _, c in row:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		title.Text = `FLOOR {floor} CLEARED — CHOOSE A REWARD`
		sub.Text = "Pick one. Gear goes to your stash: equip it from the bag (I)."
		for i, card in cards do
			local text = RewardRules.describe(card)
			-- A file card: tab line naming the kind, the title, notes, and a rarity stamp.
			local cardButton = create("TextButton", {
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = true,
				BackgroundColor3 = T.panel,
				Size = UDim2.fromOffset(240, 320),
				Parent = row,
			}, { Builder.corner(2), Builder.stroke(T.border, 1, 0), Builder.padding(14), Builder.list(8) })
			local tabLine = Builder.label(text.footer, 14, {
				Font = T.type,
				TextColor3 = T.muted,
				LayoutOrder = 1,
				Parent = cardButton,
			})
			Builder.rule({ LayoutOrder = 2, Parent = cardButton })
			local name = Builder.label(string.upper(text.title), 22, {
				Font = T.head,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 54),
				LayoutOrder = 3,
				Parent = cardButton,
			})
			name.TextYAlignment = Enum.TextYAlignment.Top
			local item = card.item
			if card.kind == "gear" and item and item.rarity ~= "common" then
				Builder.stamp(item.rarity, Builder.rarityColor(item.rarity), {
					LayoutOrder = 4,
					Parent = cardButton,
				})
			end
			local desc = Builder.label(table.concat(text.lines, "\n"), 14, {
				TextColor3 = T.muted,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 120),
				LayoutOrder = 5,
				Parent = cardButton,
			})
			desc.TextYAlignment = Enum.TextYAlignment.Top
			-- Looks like a primary button; the whole card is the click target.
			Builder.label("TAKE", 18, {
				Font = T.head,
				BackgroundTransparency = 0,
				BackgroundColor3 = T.buttonFill,
				TextColor3 = T.buttonText,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 38),
				LayoutOrder = 6,
				Parent = cardButton,
			})
			tabLine.Text = string.upper(text.footer)
			cardButton.Activated:Connect(function()
				Context.remotes.ChooseReward:FireServer(i)
				Audio.play("uiBuy")
				self.hide()
				if self.onChosen then
					self.onChosen()
				end
			end)
		end
		root.Visible = true
		self.open = true
	end
	function self.hide()
		root.Visible = false
		self.open = false
	end
	return self
end

------------------------------------------------------------------ game over

function Screens.gameOver(gui: ScreenGui)
	local root = backdrop(gui, "GameOver")
	root.BackgroundTransparency = 0.25
	local panel = Builder.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.86, 0, 0.84, 0),
		Parent = root,
	})
	create("UISizeConstraint", { MaxSize = Vector2.new(920, 620), Parent = panel })
	Builder.padding(20).Parent = panel
	local heading = Builder.label("YOU DIED", 64, {
		Font = T.head,
		TextColor3 = T.danger,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = panel,
	})
	local stats = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(0.62, 0, 1, -130),
		Parent = panel,
	})
	create("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0, 58),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = stats,
	})
	local side = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.65, 0, 0, 80),
		Size = UDim2.new(0.35, 0, 1, -130),
		Parent = panel,
	})
	Builder.list(4).Parent = side
	local footer = Builder.label("", 15, {
		TextColor3 = T.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Parent = panel,
	})

	local self = { open = false, endsAt = 0 }
	local function stat(order: number, label: string, value: string, highlight: boolean?)
		local f = Builder.panel({ LayoutOrder = order, Parent = stats })
		Builder.padding(8).Parent = f
		Builder.label(value, 26, { Font = T.head, TextColor3 = if highlight then T.gold else T.text, Parent = f })
		Builder.label(
			label:upper(),
			11,
			{ Font = T.type, TextColor3 = T.muted, Position = UDim2.fromOffset(0, 30), Parent = f }
		)
	end

	function self.show(data)
		for _, c in stats:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for _, c in side:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local totalKills = 0
		for _, n in data.kills do
			totalKills += n
		end
		heading.Text = if data.victory then "THE CLIMB IS YOURS" else "YOU DIED"
		heading.TextColor3 = if data.victory then T.gold else T.danger
		stat(1, "Score", tostring(data.score), true)
		stat(2, "Floors cleared", tostring(data.wavesSurvived), true)
		stat(3, "Time played", MathUtil.formatTime(data.timePlayed))
		stat(4, "Total kills", tostring(totalKills))
		stat(5, "Accuracy", `{math.floor(data.accuracy * 100 + 0.5)}%`)
		stat(6, "Best combo", tostring(data.bestCombo))
		stat(7, "Coins earned", tostring(data.coinsEarned))
		stat(8, "Damage dealt", tostring(data.damageDealt))
		Builder.label("KILLS BY TYPE", 16, { Font = T.head, TextColor3 = T.accent, LayoutOrder = 0, Parent = side })
		for i, t in ZombiesConfig.types do
			local n = data.kills[t] or 0
			if n > 0 then
				Builder.label(`{ZombiesConfig.defs[t].name}: {n}`, 15, { LayoutOrder = i, Parent = side })
			end
		end
		if #data.team > 1 then
			Builder.label("TEAM", 16, { Font = T.head, TextColor3 = T.accent, LayoutOrder = 10, Parent = side })
			for i, m in data.team do
				Builder.label(
					`{m.name}: {m.score} pts · {m.kills} kills · {m.revives} revives`,
					14,
					{ LayoutOrder = 10 + i, Parent = side }
				)
			end
		end
		root.Visible = true
		self.open = true
	end
	function self.hide()
		root.Visible = false
		self.open = false
	end
	function self.update(secondsLeft: number)
		footer.Text = if goesHome
			then `Back to the Home page in {secondsLeft}s…`
			else `Next run in {secondsLeft}s… (Studio: no Home teleport)`
	end
	return self
end

return Screens
