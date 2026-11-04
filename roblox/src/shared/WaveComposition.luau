--!strict
-- String requires below are the Lune (unit test) branch; Roblox uses the Instance branch.
--# selene: allow(incorrect_standard_library_use)
local Waves = if script then require(script.Parent.Config.Waves) else require("./Config/Waves")
local Zombies = if script then require(script.Parent.Config.Zombies) else require("./Config/Zombies")

type RngLike = {
	weighted: (any, { [string]: number }) -> string,
	shuffle: (any, { string }) -> { string },
}

--[[
	Builds the shuffled list of zombie types for a wave from its spawn budget.
	Boss waves trade 40% of the horde for the boss (spawned separately). Each
	newly unlocked type appears at least once so players meet it.
]]
-- `countScale` grows the whole horde (difficulty tiers).
local function build(wave: number, rng: RngLike, players: number?, countScale: number?): { string }
	local budget = Waves.budget(wave) * Waves.playerScale(players or 1) * (countScale or 1)
	if Waves.isBossWave(wave) then
		budget *= 0.6
	end
	local weights = Waves.typeWeights(wave)
	local out = {}
	local keys = {}
	for t in weights do
		table.insert(keys, t)
	end
	table.sort(keys)
	for _, t in keys do
		local cost = Zombies.defs[t].cost
		if weights[t] > 0 and t ~= "walker" and budget >= cost then
			table.insert(out, t)
			budget -= cost
		end
	end
	local guard = 0
	while budget > 0.5 and guard < 5000 do
		guard += 1
		local t = rng:weighted(weights)
		local cost = Zombies.defs[t].cost
		if cost > budget + 0.5 then
			if budget >= 1 then
				table.insert(out, "walker")
				budget -= 1
			else
				break
			end
		else
			table.insert(out, t)
			budget -= cost
		end
	end
	return rng:shuffle(out)
end

return { build = build }
