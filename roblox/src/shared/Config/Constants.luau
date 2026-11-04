--!strict
-- World-scale and networking constants. The simulation works in metres on the
-- XZ plane (same numbers as the browser version); the engine boundary converts
-- to studs with STUDS.
return {
	-- 1 m = 3 studs, so a 5-stud Roblox character is ~1.7 m tall.
	STUDS = 3,
	ARENA_HALF = 36,
	WORLD_HALF = 64,
	-- Bullets fly at this height (m); lower obstacles don't block shots.
	BULLET_HEIGHT = 1.25,
	MAX_ZOMBIES = 220,
	-- Zombie snapshot rate sent to clients.
	SNAPSHOT_HZ = 15,
	-- Clients render zombies this far in the past to interpolate smoothly.
	INTERP_DELAY = 0.12,
	PLAYER_RADIUS = 0.45,
	REVIVE_SECONDS = 3,
	-- Grace period between waves: visit the merchant and workbench, loot, build.
	INTERMISSION_SECONDS = 30,
	-- Stations only serve players standing this close (m).
	STATION_RANGE = 4.5,
	COUNTDOWN_SECONDS = 4,
	GAMEOVER_SECONDS = 14,
}
