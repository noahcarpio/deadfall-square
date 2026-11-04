--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
--[[
	Rolls the whole climb up front from a seed: each floor's objective and
	modifier. Boss floors (every BOSS_EVERY, and the top floor) have no
	modifier; floor 1 is always a plain clear so new players can warm up.
]]
local Floors = if script then require(script.Parent.Config.Floors) else require("./Config/Floors")

export type Floor = { floor: number, objective: string, modifier: string, boss: boolean }

type RngLike = { weighted: (any, { [string]: number }) -> string }

local function isBoss(floor: number): boolean
	return floor % Floors.BOSS_EVERY == 0 or floor == Floors.FLOORS
end

local function build(rng: RngLike, floors: number?): { Floor }
	local total = floors or Floors.FLOORS
	local out: { Floor } = {}
	local lastObjective = ""
	for f = 1, total do
		local boss = isBoss(f) or f == total
		local objective, modifier = "clear", "none"
		if boss then
			objective = "boss"
		elseif f > 1 then
			local ow: { [string]: number } = {}
			for _, id in Floors.objectiveOrder do
				local o = Floors.objectives[id]
				if f >= o.minFloor then
					-- Avoid the same special objective twice in a row.
					ow[id] = if id == lastObjective and id ~= "clear" then o.weight * 0.25 else o.weight
				end
			end
			objective = rng:weighted(ow)
			local mw: { [string]: number } = {}
			for _, id in Floors.modifierOrder do
				local m = Floors.modifiers[id]
				if f >= m.minFloor then
					mw[id] = m.weight
				end
			end
			modifier = rng:weighted(mw)
		end
		lastObjective = objective
		table.insert(out, { floor = f, objective = objective, modifier = modifier, boss = boss })
	end
	return out
end

return { build = build, isBoss = isBoss }
