--[[
	Plays sounds from Config/Sounds (every id is optional; empty ids are
	silent). Positional sounds use a pooled Attachment in the world.
]]
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Sounds = require(Shared.Config.Sounds)
local Constants = require(Shared.Config.Constants)

local S = Constants.STUDS

local Audio = {}

local lastPlayed: { [string]: number } = {}
local THROTTLE = { hit = 0.04, zombieDeath = 0.05, groan = 0.4, coin = 0.05, turret = 0.05, explosion = 0.04 }

local anchor = Instance.new("Part")
anchor.Name = "AudioAnchor"
anchor.Anchored = true
anchor.CanCollide = false
anchor.CanQuery = false
anchor.Transparency = 1
anchor.Size = Vector3.one
anchor.Parent = Workspace

local music: Sound? = nil
local musicKey = ""

function Audio.play(name: string, x: number?, z: number?, volumeScale: number?)
	local spec = (Sounds :: any)[name]
	if not spec or spec.id == "" then
		return
	end
	local now = os.clock()
	local throttle = (THROTTLE :: any)[name]
	if throttle and now - (lastPlayed[name] or 0) < throttle then
		return
	end
	lastPlayed[name] = now
	local sound = Instance.new("Sound")
	sound.SoundId = spec.id
	sound.Volume = spec.volume * (volumeScale or 1)
	sound.PlaybackSpeed = (spec.pitch or 1) * (0.94 + math.random() * 0.12)
	-- Positional sounds live on a temporary attachment; both are cleaned up
	-- when the sound ends (with a timeout in case Ended never fires).
	local holder: Instance = sound
	if x and z then
		local att = Instance.new("Attachment")
		att.WorldPosition = Vector3.new(x * S, 3, z * S)
		att.Parent = anchor
		sound.RollOffMaxDistance = 260
		sound.RollOffMinDistance = 30
		sound.Parent = att
		holder = att
	else
		sound.Parent = SoundService
	end
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
	task.delay(10, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

-- Background music for a mood ("musicCalm", "musicCombat", "musicBoss").
function Audio.music(key: string)
	if key == musicKey then
		return
	end
	musicKey = key
	if music then
		music:Destroy()
		music = nil
	end
	local spec = (Sounds :: any)[key]
	if not spec or spec.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = spec.id
	s.Volume = spec.volume
	s.Looped = true
	s.Parent = SoundService
	s:Play()
	music = s
end

return Audio
