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
	  swing    - melee: forehand, backhand and an overhead finisher (the melee
	             weapon shows only while swinging; the gun hides meanwhile)

	Every client animates every character from replicated state (character
	attributes set by the server, the Shot remote for others' recoil), so
	everyone sees the same thing. Poses change each joint's offset (Motor6D.C0,
	or Attachment0 for the AnimationConstraint joints of upgraded avatars)
	rather than its Transform, which the Animator rewrites every frame, so
	they always show and the default animations still play on top. Poses are
	expressed in each joint's parent-part frame so R15 and R6 rigs both work
	(R6 gets arms, roll and downed; crouching legs need R15). The Output
	window gets one "[CharacterAnimator]" line per character with the joints
	it found (or a warning if it found none).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local MeleeMath = require(Shared.MeleeMath)
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

-- A character joint we pose: a Motor6D (posed through C0) or an
-- AnimationConstraint (posed through its Attachment0), with its rest offset.
type Joint = {
	inst: Instance,
	attachment: Attachment?,
	original: CFrame,
	rc: CFrame,
	active: boolean,
	-- Transform strategy: the pose to apply in Stepped, and what we last wrote / the Animator wrote.
	pending: CFrame?,
	lastWritten: CFrame?,
	lastAnim: CFrame?,
}

type Rig = {
	character: Model,
	r15: boolean,
	joints: { [string]: Joint },
	gunGrip: Motor6D?,
	gunGripRest: CFrame?,
	meleeGrip: Motor6D?,
	meleeGripRest: CFrame?,
	swingShown: boolean?,
	-- How arm poses are applied: 1 = joint offsets (C0 / Attachment0), 2 = Transform in Stepped.
	strategy: number,
	badTime: number,
	strategyReported: boolean,
	failed: boolean,
	legLength: number,
	aim: number,
	sprint: number,
	crouch: number,
	downed: number,
	recoil: number,
	stride: number,
	rescanAt: number,
	firstSeen: number,
	reported: boolean,
	warned: boolean,
	jointSummary: string?,
}

local CharacterAnimator = {}

local rigs: { [Model]: Rig } = {}

local function wrap(inst: Instance): Joint?
	if inst:IsA("Motor6D") then
		return { inst = inst, attachment = nil, original = inst.C0, rc = inst.C0.Rotation, active = false }
	elseif inst:IsA("AnimationConstraint") then
		local a = inst.Attachment0
		if a then
			return { inst = inst, attachment = a, original = a.CFrame, rc = a.CFrame.Rotation, active = false }
		end
	end
	return nil
end

local function setOffset(j: Joint, cf: CFrame)
	if j.attachment then
		j.attachment.CFrame = cf
	else
		(j.inst :: Motor6D).C0 = cf
	end
end

local function findJoint(character: Model, partName: string, jointName: string): Instance?
	local part = character:FindFirstChild(partName)
	local direct = part and part:FindFirstChild(jointName)
	if direct and (direct:IsA("Motor6D") or direct:IsA("AnimationConstraint")) then
		return direct
	end
	for _, d in character:GetDescendants() do
		if d.Name == jointName and (d:IsA("Motor6D") or d:IsA("AnimationConstraint")) then
			return d
		end
	end
	return nil
end

local function scan(rig: Rig)
	local names = if rig.r15 then JOINTS_R15 else JOINTS_R6
	for key, path in names do
		local existing = rig.joints[key]
		if not existing or not existing.inst.Parent then
			local inst = findJoint(rig.character, path[1], path[2])
			local j = inst and wrap(inst)
			if j then
				rig.joints[key] = j
			end
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

	-- Diagnostics in the Output window, once per character.
	local count, kinds = 0, {}
	for _, j in rig.joints do
		count += 1
		kinds[j.inst.ClassName] = true
	end
	if rig.joints.rShoulder and not rig.reported then
		rig.reported = true
		local classes = {}
		for k in kinds do
			table.insert(classes, k)
		end
		rig.jointSummary = `{if rig.r15 then "R15" else "R6"}, {count} joints ({table.concat(classes, ", ")})`
	elseif not rig.joints.rShoulder and not rig.warned and os.clock() - rig.firstSeen > 3 then
		rig.warned = true
		local found = {}
		for _, d in rig.character:GetDescendants() do
			if d:IsA("JointInstance") or d:IsA("Constraint") then
				found[d.ClassName .. " " .. d.Name] = true
			end
		end
		local list = {}
		for k in found do
			table.insert(list, k)
		end
		table.sort(list)
		warn(`[CharacterAnimator] {rig.character.Name}: no shoulder joint found; joints: {table.concat(list, ", ")}`)
	end
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
			joints = {},
			legLength = 2,
			strategy = 1,
			badTime = 0,
			strategyReported = false,
			failed = false,
			aim = 0,
			sprint = 0,
			crouch = 0,
			downed = 0,
			recoil = 0,
			stride = 0,
			rescanAt = 0,
			firstSeen = os.clock(),
			reported = false,
			warned = false,
		}
		rigs[character] = rig
		character.Destroying:Connect(function()
			rigs[character] = nil
		end)
	end
	local r = rig :: Rig
	if os.clock() > r.rescanAt and (r.joints.rShoulder == nil or r.joints.lShoulder == nil) then
		scan(r)
	end
	return r
end

--[[
	Poses a joint toward `d` (a CFrame in the joint's parent-part frame) by
	weight `w`, on top of whatever the Animator plays. The joint's offset
	(C0 / Attachment0) is changed rather than its Transform, which the
	Animator rewrites every frame; at weight 0 the rest offset is restored.
]]
local function poseJoint(j: Joint?, d: CFrame, w: number, strategy: number)
	if not j or not j.inst.Parent then
		return
	end
	if w <= 0.001 then
		if j.active then
			setOffset(j, j.original)
			j.active = false
		end
		j.pending = nil
		return
	end
	local target = j.rc:Inverse() * d * j.rc
	local rest = CFrame.new()
	local x = if w >= 0.999 then target else rest:Lerp(target, w)
	if strategy == 1 then
		setOffset(j, j.original * x)
		j.active = true
		j.pending = nil
	else
		if j.active then
			setOffset(j, j.original)
			j.active = false
		end
		j.pending = x
	end
end

local function pose(rig: Rig, key: string, d: CFrame, w: number)
	poseJoint(rig.joints[key], d, w, rig.strategy)
end

-- Transform strategy: applied after the Animator (Stepped), on top of its pose.
local function applyTransforms(rig: Rig)
	for _, j in rig.joints do
		local inst = j.inst :: any
		if j.pending and inst.Parent then
			local current: CFrame = inst.Transform
			-- If nothing animated this joint since our last write, reuse the Animator's last pose.
			local anim = if j.lastWritten and current == j.lastWritten then j.lastAnim or CFrame.new() else current
			j.lastAnim = anim
			local final = (j.pending :: CFrame) * anim
			inst.Transform = final
			j.lastWritten = final
		end
	end
end

-- Points a weapon grip so the weapon's world rotation is `desired`, blended from its rest offset by `w`.
local function aimGrip(grip: Motor6D, rest: CFrame, desired: CFrame, push: Vector3, w: number)
	local hand = grip.Part0
	if not hand then
		return
	end
	local target = CFrame.new(rest.Position) * (hand.CFrame.Rotation:Inverse() * desired) * CFrame.new(push)
	grip.C0 = if w >= 0.999 then target else rest:Lerp(target, math.max(0, w))
end

-- Checks the arm really rose; if not, tries the next posing strategy and reports what works.
local function checkArm(rig: Rig, dt: number)
	local hand = rig.character:FindFirstChild("RightHand") or rig.character:FindFirstChild("Right Arm")
	local torso = rig.character:FindFirstChild("UpperTorso") or rig.character:FindFirstChild("Torso")
	if not hand or not torso or not hand:IsA("BasePart") or not torso:IsA("BasePart") then
		return
	end
	local threshold = if rig.r15 then -0.7 else -0.4
	local raised = hand.Position.Y > torso.Position.Y + threshold * (torso.Size.Y / 2)
	if raised then
		rig.badTime = 0
		if not rig.strategyReported then
			rig.strategyReported = true
			print(
				`[CharacterAnimator] {rig.character.Name}: arm poses working via {if rig.strategy == 1
					then "joint offsets"
					else "Transform"} ({rig.jointSummary or "?"})`
			)
		end
		return
	end
	rig.badTime += dt
	if rig.badTime < 0.6 or rig.failed then
		return
	end
	rig.badTime = 0
	if rig.strategy == 1 then
		rig.strategy = 2
		for _, j in rig.joints do
			if j.active then
				setOffset(j, j.original)
				j.active = false
			end
		end
	else
		rig.failed = true
		warn(
			`[CharacterAnimator] {rig.character.Name}: couldn't raise the arms with joint offsets or Transform ({rig.jointSummary or "no joints found"}). Guns still aim correctly.`
		)
	end
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
	swing: number, -- 0..1 melee swing progress, or -1
	swingStep: number, -- combo step 1..3
	speed: number, -- studs/s
}

-- Shows the melee weapon only while swinging, and hides the gun meanwhile (local view only).
local function setSwingVisibility(rig: Rig, swinging: boolean)
	if rig.swingShown == swinging then
		return
	end
	rig.swingShown = swinging
	local melee = rig.character:FindFirstChild("MeleeWeapon")
	if melee then
		for _, p in melee:GetDescendants() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = if swinging then 0 else 1
			end
		end
	end
	local gun = rig.character:FindFirstChild("Gun")
	if gun then
		for _, p in gun:GetDescendants() do
			if p:IsA("BasePart") then
				p.LocalTransparencyModifier = if swinging then 1 else 0
			end
		end
	end
end

local function animate(rig: Rig, st: State, dt: number)
	rig.aim = damp(rig.aim, if st.hasGun and not st.downed then 1 else 0, 14, dt)
	rig.sprint = damp(rig.sprint, if st.sprinting then 1 else 0, 10, dt)
	rig.crouch = damp(rig.crouch, if st.crouching and not st.downed then 1 else 0, 12, dt)
	rig.downed = damp(rig.downed, if st.downed then 1 else 0, 6, dt)
	rig.recoil = damp(rig.recoil, 0, 14, dt)

	-- Arms and gun.
	local bump = if st.reload >= 0 then math.sin(math.pi * math.clamp(st.reload, 0, 1)) else 0
	local raise = 1 - rig.sprint * 0.65
	local pitchR = 0.6 + (HALF_PI + 0.05 - 0.6) * raise + rig.recoil * 0.45 - bump * 0.8
	local pitchL = 0.6 + (1.45 - 0.6) * raise - bump * 1.1
	local armW = rig.aim * (1 - rig.downed)
	local swinging = st.swing >= 0 and st.swing < 1 and not st.downed
	-- Weapons can be rebuilt by the server (switching, equipping); re-apply visibility then.
	local melee = rig.character:FindFirstChild("MeleeWeapon")
	if melee and melee:GetAttribute("Seen") ~= true then
		melee:SetAttribute("Seen", true)
		rig.swingShown = nil
	end
	local gunModel = rig.character:FindFirstChild("Gun")
	if gunModel and gunModel:GetAttribute("Seen") ~= true then
		gunModel:SetAttribute("Seen", true)
		rig.swingShown = nil
	end
	setSwingVisibility(rig, swinging)
	if swinging then
		-- Ease out: fast start, settling at the end of the arc.
		local e = 1 - (1 - st.swing) ^ 3
		local yaw, pitch, waistYaw, waistPitch
		if st.swingStep == 3 then
			yaw, pitch = 0.1, 2.9 + (0.7 - 2.9) * e -- overhead smash
			waistYaw, waistPitch = 0, -0.3 * e
		elseif st.swingStep == 2 then
			yaw, pitch = -1.1 + 2.3 * e, 1.25 -- backhand
			waistYaw, waistPitch = yaw * 0.45, 0
		else
			yaw, pitch = 1.3 - 2.4 * e, 1.35 -- forehand
			waistYaw, waistPitch = yaw * 0.45, 0
		end
		pose(rig, "rShoulder", CFrame.Angles(0, yaw, 0) * rx(pitch), 1)
		pose(rig, "lShoulder", CFrame.Angles(0, -0.3, 0) * rx(0.45), 1)
		pose(rig, "rElbow", rx(0.15), 1)
		pose(rig, "lElbow", rx(0.6), 1)
		pose(rig, "waist", CFrame.Angles(0, waistYaw, 0) * rx(waistPitch), 1)
		-- The blade sweeps through the swing arc in the character's frame, whatever the arm does.
		local mgrip = melee and melee:FindFirstChild("MeleeGrip", true)
		if mgrip and mgrip:IsA("Motor6D") then
			if rig.meleeGrip ~= mgrip then
				rig.meleeGrip = mgrip
				rig.meleeGripRest = mgrip.C0
			end
			local root = rig.character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and rig.meleeGripRest then
				local tilt = if st.swingStep == 3 then 1.3 - 1.8 * e else -0.15
				aimGrip(mgrip, rig.meleeGripRest, root.CFrame.Rotation * CFrame.Angles(0, yaw, 0) * rx(tilt), Vector3.zero, 1)
			end
		end
	else
		pose(rig, "rShoulder", CFrame.Angles(0, 0.22, 0) * rx(pitchR) * CFrame.Angles(0, bump * 1.1, 0), armW)
		pose(rig, "lShoulder", CFrame.Angles(0, -0.55, 0) * rx(pitchL), armW)
		pose(rig, "rElbow", rx(rig.recoil * 0.25), armW)
		pose(rig, "lElbow", rx(0.35 + bump * 0.7), armW)
	end
	-- The gun's grip (our own Motor6D; rebuilt on every weapon switch). The gun is pointed where the
	-- character faces in world space, so it never follows a hanging arm toward the floor.
	local gun = rig.character:FindFirstChild("Gun")
	local body = gun and gun:FindFirstChild("Body")
	local grip = body and body:FindFirstChild("GunGrip")
	if grip and grip:IsA("Motor6D") then
		if rig.gunGrip ~= grip then
			rig.gunGrip = grip
			rig.gunGripRest = grip.C0
		end
		local root = rig.character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and rig.gunGripRest then
			local level = (1 - rig.sprint) * 1 + rig.sprint * 0.6 -- muzzle dips while sprinting
			local desired = root.CFrame.Rotation
				* rx(rig.recoil * 0.18 - bump * 0.5 - (1 - level) * 0.6)
				* CFrame.Angles(0, 0, bump * 0.7)
			aimGrip(grip, rig.gunGripRest, desired, Vector3.new(0, 0, rig.recoil * 0.35), armW)
		end
	end
	if not swinging and armW > 0.9 and rig.sprint < 0.2 and bump < 0.2 and rig.joints.rShoulder then
		checkArm(rig, dt)
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
		-- Lean in while crouched; the upper body kicks back a little on each shot.
		if not swinging then
			local waistW = if (c > 0.01 or rig.recoil > 0.02) and rig.downed < 0.5 then 1 else 0
			pose(rig, "waist", rx(-0.35 * c + 0.15 * rig.recoil), waistW)
		end
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
		swing = -1,
		swingStep = 1,
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
		local since = os.clock() - Context.swingAt
		if since < MeleeMath.SWING_TIME then
			st.swing = since / MeleeMath.SWING_TIME
			st.swingStep = Context.swingStep
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
		local swingAt = character:GetAttribute("SwingAt")
		if type(swingAt) == "number" and now - swingAt < MeleeMath.SWING_TIME then
			st.swing = (now - swingAt) / MeleeMath.SWING_TIME
			local step = character:GetAttribute("SwingStep")
			st.swingStep = if type(step) == "number" then step else 1
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

	-- Transform strategy rigs get their arm poses applied after the Animator, each physics step.
	RunService.Stepped:Connect(function()
		for _, rig in rigs do
			if rig.strategy == 2 then
				applyTransforms(rig)
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt)
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
