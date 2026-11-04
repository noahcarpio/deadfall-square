--[[
	The Home page: a Field Manual cover page where players form a party.

	Left: the title, your Scrip and unlocked tier, your party (leader marked,
	with titles), the difficulty tier (the leader picks), and the actions:
	create a party, start the run (leader), invite friends, leave. Right:
	numbered tabs for open parties, the Locker (equip cosmetics), Crates (spend
	Scrip, odds shown), how to play and the best climbs. Parties redraw from
	ReplicatedStorage.Parties; the profile arrives through ProfileSync.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartyRules = require(Shared.PartyRules)
local ZombiesConfig = require(Shared.Config.Zombies)
local Tiers = require(Shared.Config.Tiers)
local Cosmetics = require(Shared.Cosmetics)

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
	Position = UDim2.fromScale(0.05, 0.06),
	Size = UDim2.fromScale(0.36, 0.9),
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
local walletLabel = Builder.label("", 16, {
	Font = T.mono,
	TextColor3 = T.rust,
	LayoutOrder = 5,
	Parent = left,
})
Builder.rule({ BackgroundColor3 = T.border, Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 6, Parent = left })
Builder.label("YOUR PARTY", 22, { Font = T.head, LayoutOrder = 7, Parent = left })
local members = create("Frame", {
	BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.Y,
	Size = UDim2.new(1, 0, 0, 0),
	LayoutOrder = 8,
	Parent = left,
}, { Builder.list(2) })
-- Difficulty tier: the leader steps through the tiers they've unlocked.
local tierRow = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 36),
	LayoutOrder = 9,
	Parent = left,
})
local tierDown = Builder.button("◂", nil, nil, {
	Size = UDim2.fromOffset(36, 36),
	Parent = tierRow,
})
local tierLabel = Builder.label("", 18, {
	Font = T.head,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.fromOffset(42, 0),
	Size = UDim2.new(0, 216, 1, 0),
	Parent = tierRow,
})
local tierUp = Builder.button("▸", nil, nil, {
	Position = UDim2.fromOffset(264, 0),
	Size = UDim2.fromOffset(36, 36),
	Parent = tierRow,
})
local status = Builder.label("", 15, {
	Font = T.type,
	TextColor3 = T.muted,
	TextWrapped = true,
	Size = UDim2.new(1, 0, 0, 36),
	LayoutOrder = 10,
	Parent = left,
})
local mainButton = Builder.button("CREATE PARTY", "primary", nil, {
	Size = UDim2.new(0, 300, 0, 50),
	LayoutOrder = 11,
	Parent = left,
})
local inviteButton = Builder.button("INVITE FRIENDS", nil, nil, {
	Size = UDim2.new(0, 300, 0, 44),
	LayoutOrder = 12,
	Parent = left,
})
local leaveButton = Builder.button("LEAVE PARTY", "danger", nil, {
	Size = UDim2.new(0, 300, 0, 44),
	LayoutOrder = 13,
	Parent = left,
})

------------------------------------------------------------------ right: tabs

local right = Builder.panel({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(0.96, 0.06),
	Size = UDim2.fromScale(0.52, 0.88),
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
local lockerPage = page("locker")
local cratePage = page("crates")
local howPage = page("how")
local boardPage = page("board")

local refreshBoard: () -> ()
local showTab: (string) -> ()
local _, selectTab = Builder.tabs(right, {
	{ "open", "Parties" },
	{ "locker", "Locker" },
	{ "crates", "Crates" },
	{ "how", "How to play" },
	{ "board", "Best" },
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
		"<b>Tiers and Scrip.</b> Win a climb to unlock the next difficulty tier (the party leader picks the tier). Beating bosses and winning pay Scrip; spend it on crates of skins, trails, emotes and titles, and equip them in the Locker.",
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

type PartyView = { id: number, leader: number, members: { number }, starting: boolean, tier: number }

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
				tier = f:GetAttribute("Tier") or 1,
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
			local p = Players:GetPlayerByUserId(userId)
			local title = p and p:GetAttribute("Title") or ""
			local line = `{string.format("%02d", i)}  {nameOf(userId)}{if lead then "  · LEADER" else ""}`
			Builder.label(if title ~= "" then `{line}  "{title}"` else line, 18, {
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
	-- Tier picker: the leader steps through their unlocked tiers; everyone else just sees it.
	tierRow.Visible = mine ~= nil
	if mine then
		local t = Tiers.get(mine.tier)
		local unlocked = player:GetAttribute("UnlockedTier") or 1
		tierLabel.Text = `TIER {t.tier} · {string.upper(t.name)}`
		tierDown.Visible = leader
		tierUp.Visible = leader
		tierDown.TextColor3 = if t.tier > 1 then T.text else T.rule
		tierUp.TextColor3 = if t.tier < unlocked then T.text else T.rule
	end
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
			Builder.label(
				`{#party.members} / {PartyRules.MAX} · tier {party.tier}{if party.starting then " · starting" else ""}`,
				14,
				{
					Font = T.mono,
					TextColor3 = T.muted,
					Position = UDim2.fromOffset(0, 24),
					Size = UDim2.new(1, -130, 0, 18),
					Parent = row,
				}
			)
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
tierDown.Activated:Connect(function()
	if mine and mine.tier > 1 then
		remotes.Party:FireServer("tier", mine.tier - 1)
	end
end)
tierUp.Activated:Connect(function()
	if mine and mine.tier < (player:GetAttribute("UnlockedTier") or 1) then
		remotes.Party:FireServer("tier", mine.tier + 1)
	end
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
local function showToast(text: string)
	toastId += 1
	local id = toastId
	toast.Text = text
	toast.Visible = true
	task.delay(6, function()
		if toastId == id then
			toast.Visible = false
		end
	end)
end
remotes.Notice.OnClientEvent:Connect(showToast)

------------------------------------------------------------------ profile: locker and crates

local profile: Cosmetics.Profile = Cosmetics.newProfile()
local offline = false
local KIND_TITLES = {
	skin = "WEAPON SKINS",
	trail = "TRAILS",
	emote = `EMOTES (up to {Cosmetics.EMOTE_SLOTS} in the emote menu: T in game)`,
	title = "TITLES",
}

local function rarityColor(rarity: string): Color3
	return Color3.fromHex(Cosmetics.RARITIES[rarity].color)
end

local function isEquipped(id: string): boolean
	local it = Cosmetics.ITEMS[id]
	if it.kind == "emote" then
		return table.find(profile.equipped.emotes, id) ~= nil
	end
	return (profile.equipped :: any)[it.kind] == id
end

local function equip(kind: string, id: string?)
	local ok = remotes.Locker:InvokeServer("equip", kind, id)
	if not ok and kind == "emote" then
		showToast(`The emote menu holds {Cosmetics.EMOTE_SLOTS}: remove one first.`)
	end
end

local function renderLocker()
	for _, c in lockerPage:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local order = 0
	for _, kind in Cosmetics.KINDS do
		order += 1
		Builder.label(KIND_TITLES[kind], 18, { Font = T.head, LayoutOrder = order, Parent = lockerPage })
		for _, id in Cosmetics.ORDER do
			local it = Cosmetics.ITEMS[id]
			if it.kind == kind then
				order += 1
				local owned = profile.owned[id] == true
				local row = create("Frame", {
					BackgroundTransparency = 1,
					Size = UDim2.new(1, -10, 0, 34),
					LayoutOrder = order,
					Parent = lockerPage,
				})
				Builder.stamp(Cosmetics.RARITIES[it.rarity].name, rarityColor(it.rarity), {
					Position = UDim2.fromOffset(0, 6),
					Parent = row,
				})
				Builder.label(if owned then it.name else `{it.name} · not owned`, 16, {
					Font = if owned then T.head else T.body,
					TextColor3 = if owned then T.text else T.muted,
					Position = UDim2.fromOffset(110, 4),
					Size = UDim2.new(1, -230, 0, 24),
					Parent = row,
				})
				if owned then
					local on = isEquipped(id)
					Builder.button(if on then "REMOVE" else "EQUIP", if on then nil else "primary", function()
						-- Emotes toggle; other kinds clear the slot when removed.
						equip(kind, if on and kind ~= "emote" then nil else id)
					end, {
						AnchorPoint = Vector2.new(1, 0),
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.fromOffset(110, 30),
						TextSize = 16,
						Parent = row,
					})
				end
			end
		end
	end
end

-- Crates: balance, the published odds, OPEN, and the reveal.
local crateBalance = Builder.label("", 20, { Font = T.mono, TextColor3 = T.rust, LayoutOrder = 1, Parent = cratePage })
Builder.label("SURVIVOR CRATE", 26, { Font = T.head, LayoutOrder = 2, Parent = cratePage })
Builder.label(
	`{Cosmetics.CRATE_PRICE} Scrip. One weapon skin, trail, emote or title you don't own yet. Scrip is earned by beating bosses and winning climbs; it can't be bought.`,
	14,
	{ TextWrapped = true, TextColor3 = T.muted, Size = UDim2.new(1, -10, 0, 40), LayoutOrder = 3, Parent = cratePage }
)
Builder.label("ODDS", 16, { Font = T.type, LayoutOrder = 4, Parent = cratePage })
for i, rarity in Cosmetics.RARITY_ORDER do
	local r = Cosmetics.RARITIES[rarity]
	Builder.label(string.format("%-10s %5.1f%%", r.name, r.odds * 100), 16, {
		Font = T.mono,
		TextColor3 = rarityColor(rarity),
		LayoutOrder = 4 + i,
		Parent = cratePage,
	})
end
Builder.label("If you already own every item of the rolled rarity, you get one from the next rarity up.", 13, {
	TextWrapped = true,
	TextColor3 = T.muted,
	Size = UDim2.new(1, -10, 0, 34),
	LayoutOrder = 9,
	Parent = cratePage,
})
local openButton = Builder.button("OPEN CRATE", "primary", nil, {
	Size = UDim2.fromOffset(240, 48),
	LayoutOrder = 10,
	Parent = cratePage,
})
local reveal = create("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -10, 0, 70),
	LayoutOrder = 11,
	Parent = cratePage,
})
local revealName = Builder.label("", 28, { Font = T.head, Position = UDim2.fromOffset(0, 30), Parent = reveal })
local revealStamp: Instance? = nil
if RunService:IsStudio() then
	Builder.button("+500 SCRIP (STUDIO TEST)", nil, function()
		remotes.Locker:InvokeServer("studioGrant")
	end, {
		Size = UDim2.fromOffset(240, 36),
		TextSize = 14,
		LayoutOrder = 12,
		Parent = cratePage,
	})
end
openButton.Activated:Connect(function()
	if profile.scrip < Cosmetics.CRATE_PRICE then
		showToast(`A crate costs {Cosmetics.CRATE_PRICE} Scrip: beat bosses and win climbs to earn it.`)
		return
	end
	openButton.Text = "OPENING…"
	local ok, result = remotes.Locker:InvokeServer("openCrate")
	openButton.Text = "OPEN CRATE"
	if revealStamp then
		revealStamp:Destroy()
		revealStamp = nil
	end
	if ok and type(result) == "string" and Cosmetics.ITEMS[result] then
		local it = Cosmetics.ITEMS[result]
		revealName.Text = `{string.upper(it.name)} · {it.kind}`
		revealStamp = Builder.stamp(Cosmetics.RARITIES[it.rarity].name, rarityColor(it.rarity), {
			TextSize = 16,
			Parent = reveal,
		})
	elseif type(result) == "string" then
		revealName.Text = result
	end
end)

local function renderProfile()
	walletLabel.Text = `SCRIP {profile.scrip} · TIER {Cosmetics.unlockedTier(profile)} UNLOCKED{if offline
		then " · not saved (offline)"
		else ""}`
	crateBalance.Text = `YOU HAVE {profile.scrip} SCRIP`
	openButton.TextColor3 = if profile.scrip >= Cosmetics.CRATE_PRICE then T.buttonText else T.rule
	renderLocker()
end

remotes.ProfileSync.OnClientEvent:Connect(function(p, isOffline: boolean)
	if type(p) == "table" then
		profile = Cosmetics.normalize(p)
		offline = isOffline == true
		renderProfile()
		render()
	end
end)
player:GetAttributeChangedSignal("UnlockedTier"):Connect(render)
renderProfile()

partiesFolder:GetAttributeChangedSignal("Version"):Connect(render)
Players.PlayerAdded:Connect(render)
Players.PlayerRemoving:Connect(function()
	task.defer(render)
end)
showTab("open")
render()
