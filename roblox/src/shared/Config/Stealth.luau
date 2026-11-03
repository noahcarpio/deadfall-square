--!strict
--[[
	Zombie senses and player noise. Zombies wander until they see or hear
	something: a noise makes them investigate where it came from, and seeing a
	player makes them hunt. Every value is in metres or seconds.
]]
return {
	-- Sight range by day and at full night, scaled down while the player crouches.
	SIGHT_DAY = 13,
	SIGHT_NIGHT = 8,
	CROUCH_SIGHT = 0.55,
	-- Zombies see in a wide cone in front of them (cosine of the half-angle)...
	SIGHT_CONE = -0.1,
	-- ...and always notice a player this close, even behind them.
	TOUCH_RANGE = 2.4,
	-- A hunting zombie that hasn't seen anyone for this long goes to investigate.
	LOSE_TRACK = 6,
	-- A wandering zombie gets restless and heads roughly toward the nearest player.
	HUNCH_AFTER = 14,
	HUNCH_SPREAD = 5,
	-- Hearing range of each noise.
	NOISE = {
		walk = 4,
		sprint = 10,
		crouch = 1,
		search = 3,
		explosion = 34,
		turret = 18,
		barricade = 10,
	},
	-- How long a noise stays interesting to zombies heading toward it.
	NOISE_MEMORY = 6,
	-- Movement speed factors outside a hunt.
	WANDER_SPEED = 0.35,
	INVESTIGATE_SPEED = 0.75,
	CROUCH_SPEED = 0.5,
}
