--[[
	Procedural upper-body and stance animation for every player character,
	layered over Roblox's default walk/run/idle animations (which the
	built-in Animate script still plays):

	  aim      - gun arm raised and pointing forward, the other hand supporting
	             it; lowered to a "low ready" while sprinting
	  recoil   - arm and gun kick back on each shot
	  reload   - gun twists, support hand drops to the belt for a new magazine
	  crouch   - knees bent and torso leaning in, with a slow sneaking stride
	  roll     - a forward tumble during the dodge roll
	  downed   - lying on the ground until revived

	Every client animates every character from replicated state (character
	attributes set by the server, the Shot remote for others' recoil), so
	everyone sees the same thing. Poses are written to Motor6D.Transform in
	RunService.Stepped, after the Animator has applied its tracks, and are
	expressed in each joint's parent-part frame so R15 and R6 rigs both work
	(R6 gets arms, roll and downed; crouching legs need R15).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local PlayerStats = require(Shared.PlayerStats)
local MathUtil = require(Shared.Util.MathUtil)

local Context = require(script.Parent.Context)

local damp = MathUtil.damp
local S = Constants.STUDS
local HALF_PI = math.pi / 2
local ROLL_TIME = PlayerStats.BASE.rollDuration
local CROUCH_DROP = 0.6
local SPRINT_SPEED = PlayerStats.BASE.speed * S * 1.25

local JOINTS_R15 = {
	rShoulder = { "RightUpperArm", "RightShoulder" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	rElbow = { "RightLowerArm", "RightElbow" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	rHip = { "RightUpperLeg", "RightHip" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	rAnkle = { "RightFoot", "RightAnkle" },
	lAnkle = { "LeftFoot", "LeftAnkle" },
}
local JOINTS_R6 = {
	rShoulder = { "Torso", "Right Shoulder" },
	lShoulder = { "Torso", "Left Shoulder" },
	root = { "HumanoidRootPart", "RootJoint" },
}

type Rig = {
	character: Model,
	r15: boolean,
	motors: { [string]: Motor6D },
	written: { [Motor6D]: CFrame },
	legLength: number,
	aim: number,
	sprint: number,
	crouch: number,
	downed: number,
	recoil: number,
	stride: number,
	rescanAt: number,
}

local CharacterAnimator = {}

local rigs: { [Model]: Rig } = {}

local function scan(rig: Rig)
	local joints = if rig.r15 then JOINTS_R15 else JOINTS_R6
	table.clear(rig.motors)
	for key, path in joints do
		local part = rig.character:FindFirstChild(path[1])
		local motor = part and part:FindFirstChild(path[2])
		if motor and motor:IsA("Motor6D") then
			rig.motors[key] = motor
		end
	end
	if rig.r15 then
		local upper = rig.character:FindFirstChild("RightUpperLeg") :: BasePart?
		local lower = rig.character:FindFirstChild("RightLowerLeg") :: BasePart?
		if upper and lower then
			rig.legLength = upper.Size.Y + lower.Size.Y
		end
	end
	rig.rescanAt = os.clock() + 1
end

local function rigFor(character: Model): Rig?
	local rig = rigs[character]
	if not rig then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return nil
		end
		rig = {
			character = character,
			r15 = humanoid.RigType == Enum.HumanoidRigType.R15,
			motors = {},
			written = {},
			legLength = 2,
			aim = 0,
			sprint = 0,
			crouch = 0,
			downed = 0,
			recoil = 0,
			stride = 0,
			rescanAt = 0,
		}
		rigs[character] = rig
		character.Destroying:Connect(function()
			rigs[character] = nil
		end)
	end
	local r = rig :: Rig
	if os.clock() > r.rescanAt and (next(r.motors) == nil or r.motors.rShoulder == nil) then
		scan(r)
	end
	return r
end

--[[
	Blends a joint toward pose `d` (a CFrame in the joint's parent-part frame)
	by weight `w`. The starting point is what the Animator wrote this frame, or
	the rest pose if no track drives this joint.
]]
local function pose(rig: Rig, key: string, d: CFrame, w: number)
	local m = rig.motors[key]
	if not m or not m.Parent then
		return
	end
	local current = m.Transform
	local base = if rig.written[m] == current then CFrame.identity else current
	if w <= 0.001 then
		if rig.written[m] then
			m.Transform = base
			rig.written[m] = nil
		end
		return
	end
	local rc = m.C0.Rotation
	local target = rc:Inverse() * d * rc
	local final = if w >= 0.999 then target else base:Lerp(target, w)
	m.Transform = final
	rig.written[m] = final
end

local function rx(a: number): CFrame
	return CFrame.Angles(a, 0, 0)
end

type State = {
	hasGun: boolean,
	downed: boolean,
	crouching: boolean,
	sprinting: boolean,
	reload: number, -- 0..1 progress, or -1
	roll: number, -- 0..1 progress, or -1
	speed: number, -- studs/s
}

local function animate(rig: Rig, st: State, dt: number)
	rig.aim = damp(rig.aim, if st.hasGun and not st.downed then 1 else 0, 14, dt)
	rig.sprint = damp(rig.sprint, if st.sprinting then 1 else 0, 10, dt)
	rig.crouch = damp(rig.crouch, if st.crouching and not st.downed then 1 else 0, 12, dt)
	rig.downed = damp(rig.downed, if st.downed then 1 else 0, 6, dt)
	rig.recoil = damp(rig.recoil, 0, 14, dt)

	-- Arms and gun.
	local bump = if st.reload >= 0 then math.sin(math.pi * math.clamp(st.reload, 0, 1)) else 0
	local raise = 1 - rig.sprint * 0.65
	local pitchR = 0.6 + (HALF_PI - 0.6) * raise + rig.recoil * 0.3 - bump * 0.55
	local pitchL = 0.6 + (1.42 - 0.6) * raise - bump * 1.05
	local armW = rig.aim * (1 - rig.downed)
	pose(rig, "rShoulder", CFrame.Angles(0, 0.22, 0) * rx(pitchR) * CFrame.Angles(0, bump * 0.9, 0), armW)
	pose(rig, "lShoulder", CFrame.Angles(0, -0.55, 0) * rx(pitchL), armW)
	pose(rig, "rElbow", rx(rig.recoil * 0.2), armW)
	pose(rig, "lElbow", rx(0.35 + bump * 0.7), armW)
	local gun = rig.character:FindFirstChild("Gun")
	local body = gun and gun:FindFirstChild("Body")
	local grip = body and body:FindFirstChild("GunGrip")
	if grip and grip:IsA("Motor6D") then
		-- Turn the gun to run along the raised arm, and kick it back on recoil.
		grip.Transform = CFrame.new(0, rig.recoil * 0.3, 0) * rx(-HALF_PI * armW)
	end

	-- Legs and torso.
	if rig.r15 then
		local c = rig.crouch
		local alpha = math.acos(math.clamp((rig.legLength - CROUCH_DROP) / rig.legLength, 0, 1))
		local move = math.clamp(st.speed / 8, 0, 1)
		rig.stride += dt * st.speed * 0.9
		local swing = math.sin(rig.stride) * 0.45 * move
		local lift = 0.3 * move
		local tuck = if st.roll >= 0 then math.sin(math.pi * st.roll) else 0
		local legW = math.max(c, tuck)
		local hipA = alpha * c + tuck * 1.3
		local kneeA = -2 * alpha * c - tuck * 2
		pose(rig, "rHip", rx(hipA + swing * c), legW)
		pose(rig, "lHip", rx(hipA - swing * c), legW)
		pose(rig, "rKnee", rx(kneeA - math.max(0, -math.sin(rig.stride)) * lift * c), legW)
		pose(rig, "lKnee", rx(kneeA - math.max(0, math.sin(rig.stride)) * lift * c), legW)
		pose(rig, "rAnkle", rx(alpha * c), c)
		pose(rig, "lAnkle", rx(alpha * c), c)
		pose(rig, "waist", rx(-0.35), c * (1 - rig.downed))
	end

	-- Whole body: roll tumble, or lying down while downed.
	if st.roll >= 0 then
		local t = math.clamp(st.roll, 0, 1)
		pose(rig, "root", CFrame.new(0, -1.1 * math.sin(math.pi * t), 0) * rx(-2 * math.pi * t), 1)
	else
		pose(rig, "root", CFrame.new(0, -2.0, -0.6) * rx(-1.45), rig.downed)
	end
end

local function stateFor(player: Player, character: Model): State
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local v = if root then root.AssemblyLinearVelocity else Vector3.zero
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local st: State = {
		hasGun = character:FindFirstChild("Gun") ~= nil,
		downed = player:GetAttribute("Downed") == true,
		crouching = false,
		sprinting = false,
		reload = -1,
		roll = -1,
		speed = speed,
	}
	if player == Context.player then
		st.crouching = Context.crouching
		st.sprinting = Context.sprinting and speed > 1
		local a = Context.arsenal
		if a.reloadEnd > 0 and a.reloadDuration > 0 then
			st.reload = 1 - (a.reloadEnd - os.clock()) / a.reloadDuration
		end
		if Context.rolling then
			st.roll = (os.clock() - Context.rollStart) / ROLL_TIME
		end
	else
		local now = Workspace:GetServerTimeNow()
		st.crouching = character:GetAttribute("Crouching") == true
		st.sprinting = speed > SPRINT_SPEED
		local reloadEnd = character:GetAttribute("ReloadEnd")
		local reloadTime = character:GetAttribute("ReloadTime")
		if type(reloadEnd) == "number" and type(reloadTime) == "number" and reloadTime > 0 and now < reloadEnd then
			st.reload = 1 - (reloadEnd - now) / reloadTime
		end
		local rollAt = character:GetAttribute("RollAt")
		if type(rollAt) == "number" and now - rollAt < ROLL_TIME then
			st.roll = (now - rollAt) / ROLL_TIME
		end
	end
	return st
end

function CharacterAnimator.start()
	-- Recoil kicks: our own shots (instant) and everyone else's (Shot remote).
	Context.signals.fired:connect(function()
		local character = Context.character()
		local rig = character and rigs[character]
		if rig then
			rig.recoil = 1
		end
	end)
	Context.remotes.Shot.OnClientEvent:Connect(function(userId: number)
		local p = Players:GetPlayerByUserId(userId)
		local rig = p and p.Character and rigs[p.Character]
		if rig then
			rig.recoil = 1
		end
	end)

	RunService.Stepped:Connect(function(_, dt)
		dt = math.min(dt, 0.1)
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character and character.Parent then
				local rig = rigFor(character)
				if rig then
					animate(rig, stateFor(player, character), dt)
				end
			end
		end
	end)
end

return CharacterAnimator
