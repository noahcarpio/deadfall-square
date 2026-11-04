--!strict
--[[
	Sound asset ids, all optional. Roblox can't synthesise audio at runtime and
	asset ids can't be verified outside Roblox, so every entry ships empty and
	the game simply plays silently for that event. To add audio: in Studio open
	Toolbox -> Audio (or Creator Store), pick a sound, copy its id and paste it
	here as "rbxassetid://<id>". Volume and pitch can be tuned per entry.
]]
export type SoundSpec = { id: string, volume: number, pitch: number? }

local function s(volume: number, pitch: number?): SoundSpec
	return { id = "", volume = volume, pitch = pitch }
end

return {
	pistol = s(0.6),
	shotgun = s(0.8),
	revolver = s(0.75),
	doublebarrel = s(0.9),
	dmr = s(0.75),
	carbine = s(0.6),
	lmg = s(0.55),
	autoshotgun = s(0.85),
	railgun = s(1.0),
	smg = s(0.45),
	rifle = s(0.6),
	sniper = s(0.9),
	flamer = s(0.5),
	launcher = s(0.7),
	turret = s(0.4),
	reload = s(0.5),
	dryFire = s(0.4),
	hit = s(0.35),
	zombieDeath = s(0.5),
	groan = s(0.4),
	explosion = s(0.9),
	playerHurt = s(0.6),
	pickup = s(0.5),
	coin = s(0.3),
	roll = s(0.4),
	melee = s(0.5),
	spit = s(0.5),
	bossRoar = s(0.9),
	waveStart = s(0.7),
	waveClear = s(0.6),
	uiClick = s(0.3),
	uiBuy = s(0.5),
	uiDeny = s(0.4),
	-- Background music loops by phase.
	musicCalm = s(0.25),
	musicCombat = s(0.3),
	musicBoss = s(0.35),
}
