--!strict
--[[
	Remote definitions and the compact binary zombie snapshot format.

	Zombies are simulated only on the server; clients receive 15 Hz snapshots
	(10 bytes per zombie, packed into buffers small enough for unreliable
	remotes) and render/interpolate them locally. This keeps 100+ zombies cheap
	in bandwidth and server physics.
]]
local Net = {}

-- Client -> server and server -> client events (reliable).
Net.EVENTS = {
	"Fire", -- c->s: weaponId, originX, originZ, { dirs }, aimDistance
	"Reload", -- c->s
	"Switch", -- c->s: weaponId | cycle direction
	"Roll", -- c->s
	"Ready", -- c->s: lobby / intermission ready toggle
	"ChoosePerk", -- c->s: perkId
	"ZombieSpawn", -- s->c: { id, type, x, z }
	"ZombieDeath", -- s->c: { id, dirX, dirZ }
	"ZombieHits", -- s->c: { { id, damage, crit } }
	"Shot", -- s->c: tracer visuals from other shooters and turrets
	"Fx", -- s->c: explosions, acid, shockwaves, telegraphs, grenades, flames
	"ArsenalSync", -- s->c: authoritative weapon/ammo state
	"StatsSync", -- s->c: derived player stats (speed, stamina...)
	"Hurt", -- s->c: damage taken + knockback impulse
	"Notify", -- s->c: toast text
	"PerkOffer", -- s->c: three perk ids
	"GameOver", -- s->c: end-of-run stats
	"Adrenaline", -- s->c: stamina refund + speed boost after a kill
	"Crouch", -- c->s: boolean
	"UseItem", -- c->s: itemId, aimX, aimZ, aimDistance (bandage / pipe bomb)
	"DiscardItem", -- c->s: itemId, count
	"InventorySync", -- s->c: { items, capacity }
	"OpenStation", -- s->c: station name (merchant / workbench), prompt position x, z
}
Net.UNRELIABLE = { "Snapshot" }
Net.FUNCTIONS = { "Purchase", "Place", "GetLeaderboard" }

Net.STATES = {
	"spawning",
	"chase",
	"windup",
	"recover",
	"ranged",
	"fuse",
	"chargeTelegraph",
	"charging",
	"slamTelegraph",
	"summon",
	"stunned",
}
Net.STATE_CODE = {} :: { [string]: number }
for i, s in Net.STATES do
	Net.STATE_CODE[s] = i
end

Net.FLAG_BURNING = 1
Net.FLAG_ENRAGED = 2
-- Bits 4-6 of the flags byte carry the zombie type code (Config/Zombies.code),
-- so clients that missed a spawn event (late joiners) can still build the rig.
Net.TYPE_SHIFT = 16

Net.RECORD_BYTES = 10
Net.HEADER_BYTES = 10
-- Keeps each packet under the ~900 byte unreliable-remote limit.
Net.MAX_PER_PACKET = 85

export type ZombieRecord = {
	id: number,
	x: number,
	z: number,
	facing: number,
	state: number,
	hp: number, -- 0..1
	flags: number,
}

local POS_SCALE = 50 -- 2 cm precision, +-655 m range

-- Packs up to MAX_PER_PACKET records (from index `first`) with a server timestamp.
function Net.pack(records: { ZombieRecord }, first: number, count: number, time: number): buffer
	local b = buffer.create(Net.HEADER_BYTES + count * Net.RECORD_BYTES)
	buffer.writeu16(b, 0, count)
	buffer.writef64(b, 2, time)
	local o = Net.HEADER_BYTES
	for i = first, first + count - 1 do
		local r = records[i]
		buffer.writeu16(b, o, r.id)
		buffer.writei16(b, o + 2, math.clamp(math.floor(r.x * POS_SCALE + 0.5), -32768, 32767))
		buffer.writei16(b, o + 4, math.clamp(math.floor(r.z * POS_SCALE + 0.5), -32768, 32767))
		local f = (r.facing % (math.pi * 2)) / (math.pi * 2)
		buffer.writeu8(b, o + 6, math.floor(f * 255 + 0.5))
		buffer.writeu8(b, o + 7, r.state)
		buffer.writeu8(b, o + 8, math.clamp(math.floor(r.hp * 255 + 0.5), 0, 255))
		buffer.writeu8(b, o + 9, r.flags)
		o += Net.RECORD_BYTES
	end
	return b
end

function Net.unpack(b: buffer): (number, { ZombieRecord })
	local count = buffer.readu16(b, 0)
	local time = buffer.readf64(b, 2)
	local out = table.create(count)
	local o = Net.HEADER_BYTES
	for i = 1, count do
		out[i] = {
			id = buffer.readu16(b, o),
			x = buffer.readi16(b, o + 2) / POS_SCALE,
			z = buffer.readi16(b, o + 4) / POS_SCALE,
			facing = buffer.readu8(b, o + 6) / 255 * math.pi * 2,
			state = buffer.readu8(b, o + 7),
			hp = buffer.readu8(b, o + 8) / 255,
			flags = buffer.readu8(b, o + 9),
		}
		o += Net.RECORD_BYTES
	end
	return time, out
end

-- Server: creates the Remotes folder. Client: waits for it. (Roblox only.)
function Net.setup(isServer: boolean): Instance
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	if not isServer then
		return ReplicatedStorage:WaitForChild("Remotes")
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in Net.EVENTS do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in Net.UNRELIABLE do
		local r = Instance.new("UnreliableRemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in Net.FUNCTIONS do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

return Net
