--!strict
--[[
	Parties on the Home page: pure bookkeeping, no Roblox APIs (unit-tested).
	A player is in at most one party; the first member is the leader, and the
	next member takes over when the leader leaves. An empty party is removed.
	The leader picks the difficulty tier, up to the highest they've unlocked.
]]
local PartyRules = {}

PartyRules.MAX = 6

export type Party = { id: number, leader: number, members: { number }, tier: number }
export type State = { parties: { [number]: Party }, of: { [number]: number }, nextId: number }

function PartyRules.new(): State
	return { parties = {}, of = {}, nextId = 0 }
end

function PartyRules.partyOf(state: State, userId: number): Party?
	local id = state.of[userId]
	return if id then state.parties[id] else nil
end

function PartyRules.leave(state: State, userId: number)
	local party = PartyRules.partyOf(state, userId)
	if not party then
		return
	end
	state.of[userId] = nil
	local i = table.find(party.members, userId)
	if i then
		table.remove(party.members, i)
	end
	if #party.members == 0 then
		state.parties[party.id] = nil
	elseif party.leader == userId then
		party.leader = party.members[1]
	end
end

-- Starts a new party led by `userId` (leaving any current one).
function PartyRules.create(state: State, userId: number): Party
	PartyRules.leave(state, userId)
	state.nextId += 1
	local party = { id = state.nextId, leader = userId, members = { userId }, tier = 1 }
	state.parties[party.id] = party
	state.of[userId] = party.id
	return party
end

-- Joins party `id`. Returns nil and a reason when it can't.
function PartyRules.join(state: State, userId: number, id: number): (Party?, string?)
	local party = state.parties[id]
	if not party then
		return nil, "That party no longer exists."
	end
	if state.of[userId] == id then
		return party, nil
	end
	if #party.members >= PartyRules.MAX then
		return nil, "That party is full."
	end
	PartyRules.leave(state, userId)
	table.insert(party.members, userId)
	state.of[userId] = id
	return party, nil
end

-- The leader sets the party's tier, up to `maxTier` (their unlocked tier). Returns a reason on failure.
function PartyRules.setTier(state: State, userId: number, tier: number, maxTier: number): (boolean, string?)
	local party = PartyRules.partyOf(state, userId)
	if not party then
		return false, "Create or join a party first."
	end
	if party.leader ~= userId then
		return false, "Only the party leader picks the tier."
	end
	if tier ~= tier or tier < 1 or tier > maxTier then
		return false, `Win tier {maxTier} to unlock the next one.`
	end
	party.tier = math.floor(tier)
	return true, nil
end

-- Only the leader can start; returns the party, or nil and a reason.
function PartyRules.canStart(state: State, userId: number): (Party?, string?)
	local party = PartyRules.partyOf(state, userId)
	if not party then
		return nil, "Create or join a party first."
	end
	if party.leader ~= userId then
		return nil, "Only the party leader can start."
	end
	return party, nil
end

return PartyRules
