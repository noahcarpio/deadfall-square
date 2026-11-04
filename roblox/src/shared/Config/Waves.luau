--!strict
--[[
	Wave difficulty curves (same as the browser version) plus co-op scaling.
	Wave 1 is a trickle of walkers; wave 10 is challenging; 20+ is very hard.
]]
local Waves = {}

Waves.clearDelay = 3
Waves.perkEvery = 3
Waves.bossEvery = 5

function Waves.budget(wave: number): number
	return 8 + 4 * wave + 0.35 * wave * wave
end

-- Extra horde per additional player (a full lobby of 6 faces ~3.75x the zombies).
function Waves.playerScale(players: number): number
	return 1 + 0.55 * (math.max(1, players) - 1)
end

function Waves.isBossWave(wave: number): boolean
	return wave > 0 and wave % Waves.bossEvery == 0
end

function Waves.isPerkWave(wave: number): boolean
	return wave > 0 and wave % Waves.perkEvery == 0
end

function Waves.typeWeights(wave: number): { [string]: number }
	return {
		walker = math.max(2, 10 - wave * 0.35),
		runner = if wave >= 2 then math.min(6, 1.2 + (wave - 2) * 0.55) else 0,
		spitter = if wave >= 3 then math.min(3.5, 0.9 + (wave - 3) * 0.3) else 0,
		exploder = if wave >= 4 then math.min(3.5, 0.9 + (wave - 4) * 0.3) else 0,
		brute = if wave >= 6 then math.min(3, 0.5 + (wave - 6) * 0.28) else 0,
	}
end

function Waves.hpMultiplier(wave: number): number
	local w = wave - 1
	return 1 + 0.1 * w + 0.006 * w * w
end

function Waves.damageMultiplier(wave: number): number
	return 1 + 0.055 * (wave - 1)
end

function Waves.speedMultiplier(wave: number): number
	return math.min(1.3, 1 + 0.015 * (wave - 1))
end

function Waves.spawnInterval(wave: number): number
	return math.max(0.22, 1.35 - 0.065 * (wave - 1))
end

function Waves.spawnGroupSize(wave: number): number
	return 1 + wave // 4
end

function Waves.maxAlive(wave: number, cap: number): number
	return math.min(cap, 16 + 6 * wave)
end

-- Boss health multiplier; also scales with the number of players.
function Waves.bossHpMultiplier(wave: number, players: number): number
	local k = math.max(1, wave // Waves.bossEvery)
	return (1 + 0.75 * (k - 1)) * (1 + 0.6 * (math.max(1, players) - 1))
end

function Waves.clearBonus(wave: number): number
	return 25 + 6 * wave
end

-- Night factor 0 (day) .. 1 (deep night): dusk by wave 5, full night from 11.
function Waves.night(wave: number): number
	return math.clamp((wave - 1) / 10, 0, 1)
end

return Waves
