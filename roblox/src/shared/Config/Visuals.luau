--!strict
--[[
	Art direction in one place. The target look is gritty realistic (see the
	README); the current art is placeholder.

	  * Colour grading, bloom and sun rays follow the day-night cycle: muted
	    and desaturated by day, cold and harsh at night.
	  * CLEAN_MATERIALS: Roblox's built-in textured materials (concrete,
	    slate, fabric...) turn into grainy noise from the high top-down camera,
	    so the placeholder look swaps them for smooth surfaces. Add a
	    MaterialVariant to MaterialService (e.g. a realistic brick) and every
	    part of that base material uses it instead (ArenaBuilder.variantFor).
]]
local CLEAN_MATERIALS = true

-- Textured material -> the material used in the clean look.
local CLEAN: { [string]: string } = {
	Concrete = "SmoothPlastic",
	Slate = "SmoothPlastic",
	Cobblestone = "SmoothPlastic",
	Asphalt = "SmoothPlastic",
	Brick = "SmoothPlastic",
	Ground = "SmoothPlastic",
	Fabric = "SmoothPlastic",
	Cardboard = "SmoothPlastic",
	CorrodedMetal = "Metal",
	WoodPlanks = "Wood",
	Marble = "SmoothPlastic",
	Grass = "SmoothPlastic",
}

-- Material name as used by the game (e.g. "Concrete") for the active look.
local function material(name: string): string
	if CLEAN_MATERIALS then
		return CLEAN[name] or name
	end
	return name
end

-- Same for an Enum.Material.
local function enum(m: Enum.Material): Enum.Material
	if not CLEAN_MATERIALS then
		return m
	end
	local mapped = CLEAN[m.Name]
	return if mapped then (Enum.Material :: any)[mapped] else m
end

return {
	CLEAN_MATERIALS = CLEAN_MATERIALS,
	material = material,
	enum = enum,
	-- Small per-part brightness variation (fraction) so large flat areas don't look plastic.
	COLOR_JITTER = 0.05,
	-- Colour grading by time of day (n = 0 day ... 1 night).
	GRADE = {
		dayTint = Color3.fromRGB(250, 236, 214),
		nightTint = Color3.fromRGB(182, 202, 240),
		contrast = { 0.22, 0.3 },
		saturation = { -0.3, -0.42 },
		brightness = { 0, -0.02 },
	},
	BLOOM = { intensity = { 0.35, 0.9 }, size = 22, threshold = { 1.6, 0.95 } },
	SUN_RAYS = { intensity = 0.03, spread = 0.7 },
	LIGHTING = { shadowSoftness = 0.25, environmentDiffuse = 0.6, environmentSpecular = 0.5 },
}
