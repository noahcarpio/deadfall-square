--[[
	Full-screen overlays: the lobby (title, ready-up, how to play, global
	leaderboard), the perk choice (1 of 3) and the end-of-run summary.
]]
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Perks = require(Shared.Config.Perks)
local ZombiesConfig = require(Shared.Config.Zombies)
local MathUtil = require(Shared.Util.MathUtil)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)

local create = Builder.create
local T = Builder.theme

local Screens = {}

local function backdrop(gui: ScreenGui, name: string): Frame
	return create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 8, 12),
		BackgroundTransparency = 0.35,
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
				Font = Enum.Font.Code,
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
	root.BackgroundTransparency = 0.45
	local left = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.06, 0, 0.12, 0),
		Size = UDim2.new(0.4, 0, 0.8, 0),
		Parent = root,
	})
	create("UISizeConstraint", { MinSize = Vector2.new(300, 300), Parent = left })
	Builder.list(10).Parent = left
	Builder.label(
		"A LOW-POLY CO-OP SURVIVAL HORROR",
		14,
		{ Font = T.bold, TextColor3 = T.accent, LayoutOrder = 1, Parent = left }
	)
	Builder.label("DEADFALL", 96, { Font = T.head, LayoutOrder = 2, Parent = left })
	Builder.label("SQUARE", 56, { Font = T.head, TextColor3 = T.danger, LayoutOrder = 3, Parent = left })
	Builder.label(
		"Hold the town square together. Survive the night.",
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
	local rightTitle = Builder.label("TOP SURVIVORS", 26, { Font = T.head, LayoutOrder = 0, Parent = right })
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
		"<b>PC:</b> WASD move · mouse aim · hold click shoot · R reload · Shift sprint · Space roll · C crouch · F use / search · B bandage · G pipe bomb · I bag · 1–7 / wheel / Q / E switch",
		"<b>Controller:</b> left stick move · right stick aim (push fully to fire) · RT fire · A roll · X reload · B crouch · Y use / search · D-pad up bandage · down pipe bomb · right bag · LB/RB switch · L3/LT sprint",
		"<b>Mobile:</b> left thumbstick move · right side drag to aim & fire · RUN / ROLL / RELOAD / SWAP / SNEAK / HEAL / BOMB / BAG buttons, tap prompts to use",
		"",
		"<b>Stay quiet.</b> Zombies wander until they see or hear you. Gunshots carry far, sprinting is loud, crouching is nearly silent and harder to spot. A pipe bomb's beeping lures them in before it blows.",
		"<b>Scavenge.</b> Search cars, crates, dumpsters and trash for scrap, planks, rags, electronics and gunpowder. Your bag has a weight limit.",
		"<b>Grace period.</b> After each wave you get 30 seconds: trade coins at the <b>merchant</b>, craft and upgrade at the <b>workbench</b>, build barricades and turrets, or ring the <b>bell</b> to start early. Every 3rd wave you pick a perk.",
		"If a teammate goes down, stand next to them and <b>hold F</b> to revive. The run ends when everyone is down.",
		"",
		table.concat(zombieLines, "\n"),
	}, "\n")

	local showingHow = false
	howButton.Activated:Connect(function()
		showingHow = not showingHow
		how.Visible = showingHow
		board.Visible = not showingHow
		rightTitle.Text = if showingHow then "HOW TO PLAY" else "TOP SURVIVORS"
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

function Screens.perks(gui: ScreenGui)
	local root = backdrop(gui, "Perks")
	Builder.label("CHOOSE A PERK", 48, {
		Font = T.head,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromScale(0, 0.18),
		Parent = root,
	})
	Builder.label("Pick one. Perks last for the whole run.", 16, {
		TextColor3 = T.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 0, 0.18, 54),
		Parent = root,
	})
	local row = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(720, 280),
		Parent = root,
	})
	local layout = Builder.list(16, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = row

	local self: any = { open = false, onChosen = nil }
	function self.show(choices: { string })
		for _, c in row:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		for i, id in choices do
			local def = Perks.defs[id]
			local color = Color3.fromHex(def.color)
			local level = 0
			for _, p in Context.perks do
				if p.id == id then
					level = p.level
				end
			end
			local cardButton = create("TextButton", {
				LayoutOrder = i,
				Text = "",
				AutoButtonColor = true,
				BackgroundColor3 = T.panel,
				Size = UDim2.fromOffset(220, 270),
				Parent = row,
			}, { Builder.corner(12), Builder.stroke(color, 2, 0.2), Builder.padding(14), Builder.list(8) })
			Builder.label(def.glyph, 56, {
				Font = T.head,
				TextColor3 = color,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 1,
				Parent = cardButton,
			})
			Builder.label(
				def.name,
				24,
				{ Font = T.head, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = cardButton }
			)
			local desc = Builder.label(def.description, 15, {
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = true,
				Size = UDim2.new(1, 0, 0, 80),
				LayoutOrder = 3,
				Parent = cardButton,
			})
			desc.TextYAlignment = Enum.TextYAlignment.Top
			Builder.label(if def.maxStacks > 1 then `LEVEL {level + 1} / {def.maxStacks}` else "UNIQUE", 13, {
				TextColor3 = T.muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				LayoutOrder = 4,
				Parent = cardButton,
			})
			cardButton.Activated:Connect(function()
				Context.remotes.ChoosePerk:FireServer(id)
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
	Builder.label("YOU DIED", 64, {
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
			{ Font = T.bold, TextColor3 = T.muted, Position = UDim2.fromOffset(0, 30), Parent = f }
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
		stat(1, "Score", tostring(data.score), true)
		stat(2, "Waves survived", tostring(data.wavesSurvived), true)
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
