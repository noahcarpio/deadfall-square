--!strict
--[[
	Place IDs of the two places in the experience. Publish both places
	(home.project.json and default.project.json) to the same experience, then
	paste their IDs here. While an ID is 0, or when running in Studio, the
	teleports are skipped: the Home page says so, and the game restarts the
	run instead of sending players home.
]]
return {
	HOME_PLACE_ID = 0,
	GAME_PLACE_ID = 0,
}
