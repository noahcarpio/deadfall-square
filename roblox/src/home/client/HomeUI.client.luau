--[[
	The Home page: a Field Manual cover page where players form a party.

	Left: the title, your party (leader marked), and the actions: create a
	party, start the run (leader), invite friends, leave. Right: numbered tabs
	for open parties to join, how to play, and the best climbs. Everything is
	redrawn from ReplicatedStorage.Parties, which the Home server keeps current.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartyRules = require(Shared.PartyRules)
local ZombiesConfig = require(Shared.Config.Zombies)

local Builder = require(script.Parent.UI.Builder)

local create = Builder.create
local T = Builder.paper

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("HomeRemotes")
local partiesFolder = ReplicatedStorage:WaitForChild("Parties")

local gui = Builder.screen("Home", 10)
gui.Parent = player:WaitForChild("PlayerGui")

local root = create("Frame", {
	Name = "Page",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = T.bg,
	BorderSizePixel = 0,
	Parent = gui,
})

------------------------------------------------------------------ left: cover + party

local left = create("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.06, 0.08),
	Size = UDim2.fromScale(0.4, 0.86),
	Parent = root,
})
create("UISizeConstraint", { MinSize = Vector2.new(300, 300), Parent = left })
Builder.list(8).Parent = left
Builder.label("CO-OP ZOMBIE SURVIVAL · 1 TO 6 PLAYERS", 14, {
	Font = T.type,
	TextColor3 = T.muted,
	LayoutOrder = 1,
	Parent = left,
})
Builder.label("DEADFALL", 80, { Font = T.head, LayoutOrder = 2, Parent = left })
Builder.label("SQUARE", 52, { Font = T.head, TextColor3 = T.rust, LayoutOrder = 3, Parent = left })
Builder.label("Climb 30 floors of the town square. Scavenge, trade, and get everyone to the top.", 16, {
	TextColor3 = T.muted,
	TextWrapped = true,
	Size = UDim2.new(1, 0, 0, 40),
	LayoutOrder = 4,
	Parent = left,
})
Builder.rule({ BackgroundColor3 = T.border, Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 5, Parent = left })
Builder.label("YOUR PARTY", 22, { Font = T.head, LayoutOrder = 6, Parent = left })
local members = create("Frame", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	Size = UDim2.new(1, 0, 0, 0),
	LayoutOrder = 7,
	Parent = left,
}, { Builder.list(2) })
local status = Builder.label("", 15, {
	Font = T.type,
	TextColor3 = T.muted,
	TextWrapped = true,
	Size = UDim2.new(1, 0, 0, 36),
	LayoutOrder = 8,
	Parent = left,
})
local mainButton = Builder.button("CREATE PARTY", "primary", nil, {
	Size = UDim2.new(0, 300, 0, 50),
	LayoutOrder = 9,
	Parent = left,
})
local inviteButton = Builder.button("INVITE FRIENDS", nil, nil, {
	Size = UDim2.new(0, 300, 0, 44),
	LayoutOrder = 10,
	Parent = left,
})
local leaveButton = Builder.button("LEAVE PARTY", "danger", nil, {
	Size = UDim2.new(0, 300, 0, 44),
	LayoutOrder = 11,
	Parent = left,
})

------------------------------------------------------------------ right: tabs

local right = Builder.panel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.94, 0.1),
	Size = UDim2.fromScale(0.4, 0.8),
	Parent = root,
})
create("UISizeConstraint", { MinSize = Vector2.new(320, 300), Parent = right })
Builder.padding(16).Parent = right

local pages: { [string]: Frame } = {}
local function page(name: string): Frame
	local f = create("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 1, -48),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = T.muted,
		Visible = false,
		Parent = right,
	}, { Builder.list(6) })
	pages[name] = f
	return f
end
local openPage = page("open")
local howPage = page("how")
local boardPage = page("board")

local refreshBoard: () -> ()
local showTab: (string) -> ()
local _, selectTab = Builder.tabs(right, {
	{ "open", "Open parties" },
	{ "how", "How to play" },
	{ "board", "Best climbs" },
}, function(name)
	showTab(name)
end)
showTab = function(name: string)
	selectTab(name)
	for key, f in pages do
		f.Visible = key == name
	end
	if name == "board" then
		task.spawn(refreshBoard)
	end
end

------------------------------------------------------------------ how to play

local zombieLines = {}
for _, t in ZombiesConfig.types do
	local blurbs = {
		walker = "slow, dangerous in numbers",
		runner = "fast and fragile",
		brute = "huge health; its slam knocks you flying",
		spitter = "lobs acid that pools on the ground",
		exploder = "glowing belly, detonates when close",
		boss = "every 5th floor: charges, slams shockwaves, summons",
	}
	table.insert(zombieLines, `<b>{ZombiesConfig.defs[t].name}</b> — {blurbs[t] or ""}`)
end
create("TextLabel", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	Size = UDim2.new(1, -10, 0, 0),
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = T.body,
	TextSize = 15,
	TextColor3 = T.text,
	RichText = true,
	Text = table.concat({
		"<b>PC:</b> WASD move · mouse aim · hold click shoot · right click melee · Z / X / V gadgets · R reload · Shift sprint · Space roll · F use / search · B bandage · G pipe bomb · I inventory · 1–3 / wheel / Q / E switch",
		"<b>Controller:</b> left stick move · right stick aim (push fully to fire) · RT fire · RB melee · LB + X / Y / B gadgets · LB switch · A roll · X reload · B close menu · Y use / search · D-pad up bandage · down pipe bomb · right bag · L3/LT sprint",
		"<b>Mobile:</b> left thumbstick move · right side drag to aim & fire · on-screen buttons for the rest, tap prompts to use",
		"",
		"<b>Climb.</b> 30 floors, each with a goal: clear it, hold out, defend the bell or hunt the elite. Every 5th floor has a boss. Modifiers like Thick Fog or Blood Moon change the rules.",
		"<b>Two gun slots.</b> The pistol is always slot 1; carry up to two more guns. Buying a third swaps out the one in your hands; drop a gun (I) to pick up another.",
		"<b>Rewards and gear.</b> After each floor pick 1 of 3 rewards. Gear comes in Common, Rare and Unique with traits; equip, drop or sell it from the inventory (I), and salvage, reinforce or re-roll it at the workbench.",
		"<b>Merchant.</b> Open the whole climb: buy anything, and sell from your inventory while you stand at the stall. Walk away to close any menu.",
		"<b>Scavenge.</b> Search cars, crates, dumpsters and trash for scrap, planks, rags, electronics and gunpowder. Your bag has a weight limit.",
		"<b>Grace period.</b> Every third floor you get 30 seconds to trade, craft, build barricades and turrets, or ring the <b>bell</b> to start early. Other floors give a short breather; the merchant is open all climb.",
		"If a teammate goes down, stand next to them and <b>hold F</b> to revive. The run ends when everyone is down.",
		"",
		table.concat(zombieLines, "\n"),
	}, "\n"),
	Parent = howPage,
})

------------------------------------------------------------------ best climbs

refreshBoard = function()
	for _, c in boardPage:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local ok, result = pcall(function()
		return remotes.GetLeaderboard:InvokeServer()
	end)
	if not ok or type(result) ~= "table" or not result.available then
		Builder.label("Leaderboard unavailable (enable API Services in Game Settings).", 14, {
			TextColor3 = T.muted,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = boardPage,
		})
		return
	end
	if #result.entries == 0 then
		Builder.label("No climbs on record yet.", 14, { TextColor3 = T.muted, Parent = boardPage })
		return
	end
	for i, e in result.entries do
		Builder.label(string.format("%2d.  %-16s  %d", i, e.name, e.score), 16, {
			Font = T.mono,
			LayoutOrder = i,
			TextColor3 = if e.name == player.Name then T.rust else T.text,
			Parent = boardPage,
		})
	end
end

------------------------------------------------------------------ parties

local function nameOf(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	return if p then p.DisplayName else "Survivor"
end

type PartyView = { id: number, leader: number, members: { number }, starting: boolean }

local function readParties(): { PartyView }
	local list = {}
	for _, f in partiesFolder:GetChildren() do
		local id = tonumber(f.Name)
		if id then
			local ids = {}
			for part in string.gmatch(f:GetAttribute("Members") or "", "[^,]+") do
				table.insert(ids, tonumber(part) or 0)
			end
			table.insert(list, {
				id = id,
				leader = f:GetAttribute("Leader") or 0,
				members = ids,
				starting = f:GetAttribute("Starting") == true,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local mine: PartyView? = nil

local function render()
	local list = readParties()
	mine = nil
	for _, party in list do
		if table.find(party.members, player.UserId) then
			mine = party
		end
	end

	-- Your party.
	for _, c in members:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if mine then
		for i, userId in mine.members do
			local lead = userId == mine.leader
			Builder.label(`{string.format("%02d", i)}  {nameOf(userId)}{if lead then "  · LEADER" else ""}`, 18, {
				Font = T.mono,
				TextColor3 = if lead then T.rust else T.text,
				LayoutOrder = i,
				Parent = members,
			})
		end
	else
		Builder.label("Not in a party yet.", 16, { TextColor3 = T.muted, Parent = members })
	end
	local leader = mine ~= nil and mine.leader == player.UserId
	mainButton.Text = if not mine
		then "CREATE PARTY"
		elseif mine.starting then "STARTING…"
		elseif leader then "START RUN"
		else "WAITING FOR LEADER"
	mainButton.AutoButtonColor = mine == nil or (leader and not mine.starting)
	leaveButton.Visible = mine ~= nil
	status.Text = if not mine
		then "Create a party, or join one from the list."
		elseif leader then `{#mine.members} / {PartyRules.MAX} survivors. Start when everyone's in.`
		else `{#mine.members} / {PartyRules.MAX} survivors. The leader starts the run.`

	-- Open parties.
	for _, c in openPage:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local shown = 0
	for _, party in list do
		if party ~= mine then
			shown += 1
			local row = create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -10, 0, 44),
				LayoutOrder = shown,
				Parent = openPage,
			})
			Builder.label(`{nameOf(party.leader)}'s party`, 18, {
				Font = T.head,
				Size = UDim2.new(1, -130, 0, 24),
				Parent = row,
			})
			Builder.label(`{#party.members} / {PartyRules.MAX}{if party.starting then " · starting" else ""}`, 14, {
				Font = T.mono,
				TextColor3 = T.muted,
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.new(1, -130, 0, 18),
				Parent = row,
			})
			local full = #party.members >= PartyRules.MAX
			if not full and not party.starting then
				Builder.button("JOIN", nil, function()
					remotes.Party:FireServer("join", party.id)
				end, {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(1, 0.5),
					Size = UDim2.fromOffset(110, 36),
					Parent = row,
				})
			end
			Builder.rule({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Parent = row })
		end
	end
	if shown == 0 then
		Builder.label("No other parties in this server. Invite your friends.", 14, {
			TextColor3 = T.muted,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 40),
			Parent = openPage,
		})
	end
end

mainButton.Activated:Connect(function()
	if not mine then
		remotes.Party:FireServer("create")
	elseif mine.leader == player.UserId and not mine.starting then
		remotes.Party:FireServer("start")
	end
end)
leaveButton.Activated:Connect(function()
	remotes.Party:FireServer("leave")
end)
inviteButton.Activated:Connect(function()
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(player)
		end)
	end
end)

------------------------------------------------------------------ notices

local toast = Builder.label("", 16, {
	Font = T.type,
	TextColor3 = T.buttonText,
	BackgroundColor3 = T.buttonFill,
	BackgroundTransparency = 0,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextWrapped = true,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.new(0.6, 0, 0, 48),
	Visible = false,
	Parent = root,
})
local toastId = 0
remotes.Notice.OnClientEvent:Connect(function(text: string)
	toastId += 1
	local id = toastId
	toast.Text = text
	toast.Visible = true
	task.delay(6, function()
		if toastId == id then
			toast.Visible = false
		end
	end)
end)

partiesFolder:GetAttributeChangedSignal("Version"):Connect(render)
Players.PlayerAdded:Connect(render)
Players.PlayerRemoving:Connect(function()
	task.defer(render)
end)
showTab("open")
render()
