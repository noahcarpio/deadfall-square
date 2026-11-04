--[[
	Home place server: parties, the start teleport, and the Locker and crates.

	Players land here first. They create or join a party (PartyRules), invite
	friends through Roblox's invite prompt, and the leader picks a difficulty
	tier (up to the one they've unlocked) and starts the run: the whole party
	is teleported into a fresh reserved server of the game place, with the
	party size and tier in the teleport data. Party state is published as
	attributes on ReplicatedStorage.Parties (one folder per party) and the
	clients redraw from it.

	Profiles (Scrip, unlocked tier, cosmetics) come from Profile; crate opens
	and equips are atomic profile updates using the rules in Cosmetics.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartyRules = require(Shared.PartyRules)
local Places = require(Shared.Config.Places)
local Cosmetics = require(Shared.Cosmetics)

local Leaderboard = require(script.Parent.Leaderboard)
local Profile = require(script.Parent.Profile)

local remotes = Instance.new("Folder")
remotes.Name = "HomeRemotes"
local partyEvent = Instance.new("RemoteEvent")
partyEvent.Name = "Party" -- c->s: action ("create" | "join" | "leave" | "start" | "tier"), party id / tier
partyEvent.Parent = remotes
local noticeEvent = Instance.new("RemoteEvent")
noticeEvent.Name = "Notice" -- s->c: text
noticeEvent.Parent = remotes
local boardFunction = Instance.new("RemoteFunction")
boardFunction.Name = "GetLeaderboard"
boardFunction.Parent = remotes
local profileEvent = Instance.new("RemoteEvent")
profileEvent.Name = "ProfileSync" -- s->c: profile, offline
profileEvent.Parent = remotes
local lockerFunction = Instance.new("RemoteFunction")
lockerFunction.Name = "Locker" -- c->s: "openCrate" | "equip" (kind, id) | "studioGrant"; returns ok, item / reason
lockerFunction.Parent = remotes
remotes.Parent = ReplicatedStorage

local partiesFolder = Instance.new("Folder")
partiesFolder.Name = "Parties"
partiesFolder.Parent = ReplicatedStorage

local state = PartyRules.new()
local starting: { [number]: boolean } = {}
local version = 0

-- Mirrors the party table into ReplicatedStorage.Parties.
local function publish()
	for id in starting do
		if not state.parties[id] then
			starting[id] = nil
		end
	end
	for _, child in partiesFolder:GetChildren() do
		local id = tonumber(child.Name)
		if not id or not state.parties[id] then
			child:Destroy()
		end
	end
	for id, party in state.parties do
		local folder = partiesFolder:FindFirstChild(tostring(id))
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = tostring(id)
			folder.Parent = partiesFolder
		end
		local members = {}
		for _, userId in party.members do
			table.insert(members, tostring(userId))
		end
		folder:SetAttribute("Leader", party.leader)
		folder:SetAttribute("Members", table.concat(members, ","))
		folder:SetAttribute("Starting", starting[id] == true)
		folder:SetAttribute("Tier", party.tier)
	end
	version += 1
	partiesFolder:SetAttribute("Version", version)
end

local function notice(player: Player, text: string)
	noticeEvent:FireClient(player, text)
end

------------------------------------------------------------------ profiles

local profiles: { [number]: Cosmetics.Profile } = {}

-- Keeps the client and the player's attributes (title, unlocked tier) in step with the profile.
local function syncProfile(player: Player, p: Cosmetics.Profile)
	profiles[player.UserId] = p
	local title = p.equipped.title
	player:SetAttribute("Title", if title then Cosmetics.ITEMS[title].name else "")
	player:SetAttribute("UnlockedTier", Cosmetics.unlockedTier(p))
	profileEvent:FireClient(player, p, Profile.isOffline())
end

local function unlockedTier(player: Player): number
	local p = profiles[player.UserId]
	return if p then Cosmetics.unlockedTier(p) else 1
end

local function start(player: Player)
	local party, why = PartyRules.canStart(state, player.UserId)
	if not party then
		notice(player, why or "Can't start.")
		return
	end
	if Places.GAME_PLACE_ID == 0 or RunService:IsStudio() then
		notice(
			player,
			"Teleports only work in the published game: set the place IDs in Config/Places, publish both places and play from Roblox."
		)
		return
	end
	if starting[party.id] then
		return
	end
	local players = {}
	for _, userId in party.members do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			table.insert(players, p)
		end
	end
	-- Leadership may have passed to someone who hasn't unlocked this tier.
	party.tier = math.min(party.tier, unlockedTier(player))
	starting[party.id] = true
	publish()
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({ partySize = #players, tier = party.tier })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Places.GAME_PLACE_ID, players, options)
	end)
	if not ok then
		starting[party.id] = nil
		publish()
		for _, p in players do
			notice(p, `Couldn't start: {err}`)
		end
	end
end

partyEvent.OnServerEvent:Connect(function(player, action, id)
	if action == "create" then
		PartyRules.create(state, player.UserId)
	elseif action == "join" and type(id) == "number" then
		local _, why = PartyRules.join(state, player.UserId, id)
		if why then
			notice(player, why)
		end
	elseif action == "leave" then
		PartyRules.leave(state, player.UserId)
	elseif action == "start" then
		start(player)
		return
	elseif action == "tier" and type(id) == "number" then
		local _, why = PartyRules.setTier(state, player.UserId, id, unlockedTier(player))
		if why then
			notice(player, why)
		end
	else
		return
	end
	publish()
end)

-- A failed teleport puts the party back to waiting so the leader can retry.
TeleportService.TeleportInitFailed:Connect(function(player, _result, message)
	local party = PartyRules.partyOf(state, player.UserId)
	if party and starting[party.id] then
		starting[party.id] = nil
		publish()
	end
	notice(player, `Teleport failed: {message}`)
end)

Players.PlayerRemoving:Connect(function(player)
	PartyRules.leave(state, player.UserId)
	profiles[player.UserId] = nil
	publish()
end)

local function onPlayerAdded(player: Player)
	local p = Profile.load(player.UserId)
	if player.Parent then
		syncProfile(player, p)
	end
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-- Crates and the Locker. One request at a time per player, so a crate can't be double-spent.
local busy: { [number]: boolean } = {}
local random = Random.new()
local rng = {
	next = function(_self)
		return random:NextNumber()
	end,
}
lockerFunction.OnServerInvoke = function(player: Player, action: any, kind: any, id: any)
	if busy[player.UserId] then
		return false, "One moment…"
	end
	busy[player.UserId] = true
	local ok, result, saved
	if action == "openCrate" then
		ok, result, saved = Profile.update(player.UserId, function(p)
			local bought, item = Cosmetics.buyCrate(p, rng)
			if not bought then
				return false, item
			end
			return item ~= nil, item or "You own every item already."
		end)
	elseif action == "equip" and type(kind) == "string" and (id == nil or type(id) == "string") then
		ok, result, saved = Profile.update(player.UserId, function(p)
			return Cosmetics.equip(p, kind, id), nil
		end)
	elseif action == "studioGrant" and RunService:IsStudio() then
		-- Studio only: Scrip to try crates without winning a climb first.
		ok, result, saved = Profile.update(player.UserId, function(p)
			p.scrip += 500
			return true, nil
		end)
	else
		busy[player.UserId] = nil
		return false, "Invalid"
	end
	busy[player.UserId] = nil
	if saved and player.Parent then
		syncProfile(player, saved)
	end
	return ok, result
end

local leaderboard = Leaderboard.new()
boardFunction.OnServerInvoke = function(_player)
	return leaderboard:top()
end

publish()
