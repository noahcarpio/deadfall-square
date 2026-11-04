--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
local Perks = if script then require(script.Parent.Config.Perks) else require("./Config/Perks")
local RngModule = if script then require(script.Parent.Util.Rng) else require("./Util/Rng")

type Rng = typeof(RngModule.new(0))

local PerkState = {}
PerkState.__index = PerkState

export type PerkState = typeof(setmetatable({} :: { stacks: { [string]: number }, order: { string } }, PerkState))

function PerkState.new(): PerkState
	return setmetatable({ stacks = {}, order = {} }, PerkState)
end

function PerkState.level(self: PerkState, id: string): number
	return self.stacks[id] or 0
end

function PerkState.has(self: PerkState, id: string): boolean
	return self:level(id) > 0
end

function PerkState.canTake(self: PerkState, id: string): boolean
	local def = Perks.defs[id]
	return def ~= nil and self:level(id) < def.maxStacks
end

function PerkState.add(self: PerkState, id: string)
	assert(self:canTake(id), "perk cannot be taken: " .. id)
	if self:level(id) == 0 then
		table.insert(self.order, id)
	end
	self.stacks[id] = self:level(id) + 1
end

-- Up to `count` distinct perks that can still be taken.
function PerkState.rollChoices(self: PerkState, rng: Rng, count: number): { string }
	local pool = {}
	for _, id in Perks.ids do
		if self:canTake(id) then
			table.insert(pool, id)
		end
	end
	rng:shuffle(pool)
	local out = {}
	for i = 1, math.min(count, #pool) do
		out[i] = pool[i]
	end
	return out
end

return PerkState
