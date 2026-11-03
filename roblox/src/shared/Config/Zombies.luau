--!strict
export type Vec3T = { number }

export type ZombieDef = {
	type: string,
	name: string,
	hp: number,
	speed: number,
	damage: number,
	reach: number,
	attackCooldown: number,
	windup: number,
	radius: number,
	scale: number,
	mass: number,
	score: number,
	coins: number,
	cost: number,
	dropMult: number,
	colors: { skin: string, shirt: string, pants: string, eyes: string },
	body: { torso: Vec3T, arms: Vec3T, legs: Vec3T, head: Vec3T, hunch: number },
}

local Z: { [string]: ZombieDef } = {
	walker = {
		type = "walker", name = "Walker", hp = 34, speed = 1.75, damage = 10, reach = 0.75, attackCooldown = 1.1, windup = 0.32,
		radius = 0.42, scale = 1, mass = 1, score = 10, coins = 3, cost = 1, dropMult = 1,
		colors = { skin = "#7f9a6a", shirt = "#5a5f73", pants = "#3e3b37", eyes = "#ffdf5a" },
		body = { torso = { 1, 1, 1 }, arms = { 1, 1, 1 }, legs = { 1, 1, 1 }, head = { 1, 1, 1 }, hunch = 0.25 },
	},
	runner = {
		type = "runner", name = "Runner", hp = 18, speed = 4.3, damage = 7, reach = 0.65, attackCooldown = 0.75, windup = 0.18,
		radius = 0.38, scale = 0.92, mass = 0.7, score = 14, coins = 3, cost = 1.2, dropMult = 0.8,
		colors = { skin = "#b7b08a", shirt = "#8a3a2e", pants = "#2f3a4a", eyes = "#ff5a3a" },
		body = { torso = { 0.82, 1, 0.85 }, arms = { 0.8, 1.05, 0.8 }, legs = { 0.85, 1.1, 0.85 }, head = { 0.9, 0.95, 0.9 }, hunch = 0.55 },
	},
	brute = {
		type = "brute", name = "Brute", hp = 240, speed = 1.45, damage = 24, reach = 1.1, attackCooldown = 1.7, windup = 0.6,
		radius = 0.85, scale = 1.55, mass = 4, score = 45, coins = 14, cost = 5, dropMult = 3,
		colors = { skin = "#6a7a5a", shirt = "#3b3b3b", pants = "#2a2622", eyes = "#ff3b2b" },
		body = { torso = { 1.45, 1.1, 1.35 }, arms = { 1.6, 1.15, 1.6 }, legs = { 1.35, 0.95, 1.35 }, head = { 0.85, 0.85, 0.85 }, hunch = 0.3 },
	},
	spitter = {
		type = "spitter", name = "Spitter", hp = 30, speed = 1.9, damage = 9, reach = 0.7, attackCooldown = 2.6, windup = 0.5,
		radius = 0.42, scale = 1.02, mass = 1, score = 20, coins = 6, cost = 2, dropMult = 1.4,
		colors = { skin = "#8fb85a", shirt = "#4a3a5a", pants = "#2f2f2f", eyes = "#c6ff4a" },
		body = { torso = { 0.95, 1, 0.95 }, arms = { 0.85, 1, 0.85 }, legs = { 0.95, 1, 0.95 }, head = { 1.15, 1.2, 1.15 }, hunch = 0.1 },
	},
	exploder = {
		type = "exploder", name = "Exploder", hp = 26, speed = 2.7, damage = 34, reach = 2.2, attackCooldown = 0, windup = 0.75,
		radius = 0.55, scale = 1.08, mass = 1.4, score = 22, coins = 6, cost = 2, dropMult = 1.2,
		colors = { skin = "#c27a4a", shirt = "#8a4a2a", pants = "#3a2a22", eyes = "#ffb23a" },
		body = { torso = { 1.25, 1, 1.35 }, arms = { 0.9, 0.9, 0.9 }, legs = { 1.05, 0.9, 1.05 }, head = { 0.9, 0.9, 0.9 }, hunch = 0.15 },
	},
	boss = {
		type = "boss", name = "The Abomination", hp = 1900, speed = 1.9, damage = 30, reach = 1.6, attackCooldown = 1.4, windup = 0.55,
		radius = 1.35, scale = 2.5, mass = 14, score = 600, coins = 160, cost = 0, dropMult = 0,
		colors = { skin = "#5a6a4a", shirt = "#4a2a2a", pants = "#2a2020", eyes = "#ff2a2a" },
		body = { torso = { 1.5, 1.15, 1.4 }, arms = { 1.7, 1.3, 1.7 }, legs = { 1.4, 1, 1.4 }, head = { 0.9, 0.9, 0.9 }, hunch = 0.35 },
	},
}

-- Stable numeric codes for network packing.
local TYPES = { "walker", "runner", "brute", "spitter", "exploder", "boss" }
local CODE: { [string]: number } = {}
for i, t in TYPES do
	CODE[t] = i
end

return {
	defs = Z,
	types = TYPES,
	code = CODE,
	spitter = {
		preferredMin = 7,
		preferredMax = 12,
		projectileSpeed = 12,
		splashRadius = 1.4,
		puddleRadius = 1.7,
		puddleDuration = 4.5,
		puddleDps = 11,
	},
	exploder = { blastRadius = 3.8, zombieDamage = 70, structureDamage = 90 },
	brute = { knockback = 15 },
	boss = {
		chargeSpeed = 15,
		chargeTelegraph = 0.9,
		chargeDuration = 1.1,
		slamTelegraph = 0.9,
		slamRingSpeed = 11,
		slamRingMaxRadius = 13,
		slamRingWidth = 0.9,
		slamDamage = 22,
		summonCount = 4,
		enrageThreshold = 0.5,
	},
}
