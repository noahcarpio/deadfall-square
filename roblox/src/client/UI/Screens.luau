--[[
	Full-screen overlays: the lobby (title, ready-up, how to play, global
	leaderboard), the perk choice (1 of 3) and the end-of-run summary.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local RewardRules = require(Shared.RewardRules)
local ZombiesConfig = require(Shared.Config.Zombies)
local MathUtil = require(Shared.Util.MathUtil)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.paper

local Screens = {}

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

local function leaderboardList(parent: Instance): (Frame, () -> ())
	local box = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 260), Parent = parent })
	Builder.list(2).Parent = box
	local function refresh()
		for _, c in box:GetChildren() do
			if c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		local ok, result = pcall(function()
			return Context.remotes.GetLeaderboard:InvokeServer()
		end)
		if not ok or type(result) ~= "table" or not result.available then
			Builder.label("Global leaderboard unavailable (enable API Services in Game Settings).", 14, {
				TextColor3 = T.muted,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 40),
				Parent = box,
			})
			return
		end
		if #result.entries == 0 then
			Builder.label(
				"No scores yet. Be the first survivor on the board!",
				14,
				{ TextColor3 = T.muted, Parent = box }
			)
			return
		end
		for i, e in result.entries do
			Builder.label(string.format("%2d.  %-16s  %d", i, e.name, e.score), 16, {
				Font = T.mono,
				LayoutOrder = i,
				TextColor3 = if e.name == Context.player.Name then T.accent else T.text,
				Parent = box,
			})
		end
	end
	return box, refresh
end

------------------------------------------------------------------ lobby

function Screens.lobby(gui: ScreenGui)
	local root = backdrop(gui, "Lobby")
	local left = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.06, 0, 0.12, 0),
		Size = UDim2.new(0.4, 0, 0.8, 0),
		Parent = root,
	})
	create("UISizeConstraint", { MinSize = Vector2.new(300, 300), Parent = left })
	Builder.list(10).Parent = left
	Builder.label(
		"CO-OP ZOMBIE SURVIVAL · 1 TO 6 PLAYERS",
		14,
		{ Font = T.type, TextColor3 = T.muted, LayoutOrder = 1, Parent = left }
	)
	Builder.label("DEADFALL", 88, { Font = T.head, LayoutOrder = 2, Parent = left })
	Builder.label("SQUARE", 56, { Font = T.head, TextColor3 = T.rust, LayoutOrder = 3, Parent = left })
	Builder.label(
		"Climb 25 floors of the town square. Scavenge, trade, and get everyone to the top.",
		16,
		{ TextColor3 = T.muted, LayoutOrder = 4, Parent = left }
	)
	local status = Builder.label("", 16, { LayoutOrder = 5, TextColor3 = T.text, Parent = left })
	local readyButton =
		Builder.button("READY", "primary", nil, { LayoutOrder = 6, Size = UDim2.new(0, 300, 0, 50), Parent = left })
	local howButton =
		Builder.button("HOW TO PLAY", nil, nil, { LayoutOrder = 7, Size = UDim2.new(0, 300, 0, 44), Parent = left })

	local right = Builder.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(0.94, 0, 0.14, 0),
		Size = UDim2.new(0.38, 0, 0.72, 0),
		Parent = root,
	})
	Builder.padding(16).Parent = right
	Builder.list(8).Parent = right
	local rightTitle = Builder.label("BEST CLIMBS", 26, { Font = T.head, LayoutOrder = 0, Parent = right })
	local board, refreshBoard = leaderboardList(right)
	board.LayoutOrder = 1
	local how = create("TextLabel", {
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, -40),
		Visible = false,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Font = T.body,
		TextSize = 15,
		TextColor3 = T.text,
		RichText = true,
		Parent = right,
	})
	local zombieLines = {}
	for _, t in ZombiesConfig.types do
		local blurbs = {
			walker = "slow, dangerous in numbers",
			runner = "fast and fragile",
			brute = "huge health; its slam knocks you flying",
			spitter = "lobs acid that pools on the ground",
			exploder = "glowing belly, detonates when close",
			boss = "every 5 waves: charges, slams shockwaves, summons",
		}
		table.insert(zombieLines, `<b>{ZombiesConfig.defs[t].name}</b> — {blurbs[t]}`)
	end
	how.Text = table.concat({
		"<b>PC:</b> WASD move · mouse aim · hold click shoot · right click melee · Z / X / V gadgets · R reload · Shift sprint · Space roll · F use / search · B bandage · G pipe bomb · I inventory · 1–7 / wheel / Q / E switch",
		"<b>Controller:</b> left stick move · right stick aim (push fully to fire) · RT fire · RB melee · LB + X / Y / B gadgets · LB switch · A roll · X reload · B close menu · Y use / search · D-pad up bandage · down pipe bomb · right bag · L3/LT sprint",
		"<b>Mobile:</b> left thumbstick move · right side drag to aim & fire · RUN / ROLL / RELOAD / SWAP / HEAL / BOMB / BAG / SLASH / G1–G3 buttons, tap prompts to use",
		"",
		"<b>Climb.</b> 25 floors, each with a goal: clear it, hold out, defend the bell or hunt the elite. Every 5th floor has a boss. Modifiers like Thick Fog or Blood Moon change the rules.",
		"<b>Rewards and gear.</b> After each floor pick 1 of 3 rewards. Gear comes in Common, Rare and Unique with traits; equip, drop or sell it from the inventory (I), and salvage, reinforce or re-roll it at the workbench.",
		"<b>Merchant.</b> Open the whole climb: buy anything, and sell guns, gear and items from your inventory while you stand at the stall.",
		"<b>Scavenge.</b> Search cars, crates, dumpsters and trash for scrap, planks, rags, electronics and gunpowder. Your bag has a weight limit.",
		"<b>Grace period.</b> After each floor you get 30 seconds: trade coins at the <b>merchant</b>, craft and upgrade at the <b>workbench</b>, build barricades and turrets, or ring the <b>bell</b> to start early.",
		"If a teammate goes down, stand next to them and <b>hold F</b> to revive. The run ends when everyone is down.",
		"",
		table.concat(zombieLines, "\n"),
	}, "\n")

	local showingHow = false
	howButton.Activated:Connect(function()
		showingHow = not showingHow
		how.Visible = showingHow
		board.Visible = not showingHow
		rightTitle.Text = if showingHow then "HOW TO PLAY" else "BEST CLIMBS"
		howButton.Text = if showingHow then "LEADERBOARD" else "HOW TO PLAY"
		Audio.play("uiClick")
	end)
	readyButton.Activated:Connect(function()
		Context.remotes.Ready:FireServer(not (Context.player:GetAttribute("Ready") == true))
		Audio.play("uiClick")
	end)

	local self = {}
	function self.show()
		root.Visible = true
		task.spawn(refreshBoard)
	end
	function self.hide()
		root.Visible = false
	end
	function self.update()
		local players = game:GetService("Players"):GetPlayers()
		local ready = 0
		for _, p in players do
			if p:GetAttribute("Ready") then
				ready += 1
			end
		end
		local me = Context.player:GetAttribute("Ready") == true
		readyButton.Text = if me then "CANCEL READY" else "READY"
		status.Text = if #players == 1
			then "Press READY to start."
			else `{ready} / {#players} players ready — the run starts when everyone is ready.`
	end
	return self
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
		footer.Text = `Returning to the lobby in {secondsLeft}s…`
	end
	return self
end

return Screens
