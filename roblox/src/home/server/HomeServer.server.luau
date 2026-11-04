--[[
	Home place server: parties and the start teleport.

	Players land here first. They create or join a party (PartyRules), invite
	friends through Roblox's invite prompt, and the leader starts the run:
	the whole party is teleported into a fresh reserved server of the game
	place, with the party size in the teleport data so the game knows whom to
	wait for. Party state is published as attributes on ReplicatedStorage.Parties
	(one folder per party) and the clients redraw from it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartyRules = require(Shared.PartyRules)
local Places = require(Shared.Config.Places)

local Leaderboard = require(script.Parent.Leaderboard)

local remotes = Instance.new("Folder")
remotes.Name = "HomeRemotes"
local partyEvent = Instance.new("RemoteEvent")
partyEvent.Name = "Party" -- c->s: action ("create" | "join" | "leave" | "start"), party id
partyEvent.Parent = remotes
local noticeEvent = Instance.new("RemoteEvent")
noticeEvent.Name = "Notice" -- s->c: text
noticeEvent.Parent = remotes
local boardFunction = Instance.new("RemoteFunction")
boardFunction.Name = "GetLeaderboard"
boardFunction.Parent = remotes
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
	end
	version += 1
	partiesFolder:SetAttribute("Version", version)
end

local function notice(player: Player, text: string)
	noticeEvent:FireClient(player, text)
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
	starting[party.id] = true
	publish()
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({ partySize = #players })
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
	publish()
end)

local leaderboard = Leaderboard.new()
boardFunction.OnServerInvoke = function(_player)
	return leaderboard:top()
end

publish()
