--!strict
local MathUtil = {}

local TAU = math.pi * 2
MathUtil.TAU = TAU

function MathUtil.clamp(v: number, lo: number, hi: number): number
	if v < lo then
		return lo
	elseif v > hi then
		return hi
	end
	return v
end

function MathUtil.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Frame-rate independent exponential smoothing.
function MathUtil.damp(current: number, target: number, lambda: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-lambda * dt))
end

-- Wraps an angle into (-pi, pi].
function MathUtil.wrapAngle(a: number): number
	a = ((a + math.pi) % TAU + TAU) % TAU - math.pi
	if a <= -math.pi then
		a += TAU
	end
	return a
end

function MathUtil.angleDamp(current: number, target: number, lambda: number, dt: number): number
	return current + MathUtil.wrapAngle(target - current) * (1 - math.exp(-lambda * dt))
end

-- Ray (normalised direction) vs circle on the XZ plane. Returns entry distance or -1.
function MathUtil.rayCircle(ox: number, oz: number, dx: number, dz: number, cx: number, cz: number, r: number): number
	local fx = ox - cx
	local fz = oz - cz
	local b = fx * dx + fz * dz
	local c = fx * fx + fz * fz - r * r
	if c <= 0 then
		return 0
	end
	if b > 0 then
		return -1
	end
	local disc = b * b - c
	if disc < 0 then
		return -1
	end
	return -b - math.sqrt(disc)
end

-- Ray vs axis-aligned rectangle on the XZ plane. Returns entry distance or -1.
function MathUtil.rayAabb(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	minX: number,
	minZ: number,
	maxX: number,
	maxZ: number
): number
	local tmin = 0
	local tmax = math.huge
	if math.abs(dx) < 1e-9 then
		if ox < minX or ox > maxX then
			return -1
		end
	else
		local inv = 1 / dx
		local t1 = (minX - ox) * inv
		local t2 = (maxX - ox) * inv
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tmin = math.max(tmin, t1)
		tmax = math.min(tmax, t2)
		if tmin > tmax then
			return -1
		end
	end
	if math.abs(dz) < 1e-9 then
		if oz < minZ or oz > maxZ then
			return -1
		end
	else
		local inv = 1 / dz
		local t1 = (minZ - oz) * inv
		local t2 = (maxZ - oz) * inv
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tmin = math.max(tmin, t1)
		tmax = math.min(tmax, t2)
		if tmin > tmax then
			return -1
		end
	end
	return tmin
end

function MathUtil.formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return MathUtil
