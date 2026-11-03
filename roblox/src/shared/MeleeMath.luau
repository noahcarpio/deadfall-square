--!strict
--[[
	Melee rules shared by the server (authoritative hits), the client (swing
	timing and animation) and the unit tests: which zombies a swing reaches,
	the three-hit combo and swing timing.
]]

local COMBO_WINDOW = 0.9 -- seconds after a swing in which the next one continues the combo
local FINISHER = { damage = 1.6, knock = 2, arc = 1.15 }
local SWING_TIME = 0.32 -- animation length of one swing

-- True if a circle (tx, tz, tr) is inside the swing cone from (ox, oz) toward (dx, dz).
local function inArc(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	range: number,
	arc: number,
	tx: number,
	tz: number,
	tr: number
): boolean
	local vx, vz = tx - ox, tz - oz
	local d = math.sqrt(vx * vx + vz * vz)
	if d - tr > range then
		return false
	end
	if d <= tr + 0.35 then
		return true -- touching: always hit
	end
	local cos = math.clamp((vx * dx + vz * dz) / d, -1, 1)
	local angle = math.acos(cos)
	-- A wide zombie counts as inside if any part of it is.
	return angle - math.atan2(tr, d) <= arc / 2
end

-- The combo step (1, 2 or 3) of a swing made `sinceLast` seconds after step `previous`.
local function comboStep(previous: number, sinceLast: number): number
	if previous <= 0 or previous >= 3 or sinceLast > COMBO_WINDOW then
		return 1
	end
	return previous + 1
end

-- Seconds between swings for a weapon with `rate` swings per second.
local function interval(rate: number, rapid: boolean): number
	return 1 / (rate * (if rapid then 1.15 else 1))
end

return {
	inArc = inArc,
	comboStep = comboStep,
	interval = interval,
	FINISHER = FINISHER,
	COMBO_WINDOW = COMBO_WINDOW,
	SWING_TIME = SWING_TIME,
	NOISE = 3,
}
