--!strict
--[[
	Published animation asset ids for the keyframed clips (see
	tools/make_animations.py and Config/AnimationClips). In Studio the clips
	play straight from ReplicatedStorage.DeadfallAnimations with no ids; a
	published game needs real ids:

	  1. In Studio, open ReplicatedStorage > DeadfallAnimations.
	  2. Right-click a clip (KeyframeSequence) > Save to Roblox, and publish it.
	  3. Paste its id here as "rbxassetid://<id>".

	A clip without an id falls back to the code-made pose, so nothing breaks.
]]
return {
	IDS = {
		Reload_Rifle = "",
		Reload_Pistol = "",
		Reload_Shotgun = "",
		Throw = "",
		Swing_1 = "",
		Swing_2 = "",
		Swing_3 = "",
		Roll = "",
		Downed = "",
		Kneel = "",
	} :: { [string]: string },
	-- Which reload clip each weapon uses (anything else: Reload_Rifle).
	RELOAD = {
		pistol = "Reload_Pistol",
		revolver = "Reload_Pistol",
		shotgun = "Reload_Shotgun",
		doublebarrel = "Reload_Shotgun",
		launcher = "Reload_Shotgun",
	} :: { [string]: string },
}
