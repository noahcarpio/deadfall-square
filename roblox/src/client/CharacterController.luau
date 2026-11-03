--[[
	Local character feel: sprint with stamina (and exhaustion lockout), dodge
	roll with i-frames (the server grants the invulnerability), facing the aim
	direction, knockback from hits and the adrenaline perk boost. Movement is
	client-authoritative in Roblox, so these run locally.
]]
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local PlayerStats = require(Shared.PlayerStats)

local Context = require(script.Parent.Context)
local InputController = require(script.Parent.InputController)

local S = Constants.STUDS
local BASE = PlayerStats.BASE
local ROLL_SPEED_START = 14
local ROLL_SPEED_END = 5

local CharacterController = {}

function CharacterController.start()
	local exhausted = false
	local staminaDelay = 0
	local rollTime = 0
	local rollDir = Vector3.zero
	local rollCooldown = 0
	local boost = 0
	local align: AlignOrientation? = nil
	local velocity: LinearVelocity? = nil

	local function setup(character: Model)
		local root = character:WaitForChild("HumanoidRootPart") :: BasePart
		local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
		if not attachment then
			local created = Instance.new("Attachment")
			created.Parent = root
			attachment = created
		end
		local a = Instance.new("AlignOrientation")
		a.Mode = Enum.OrientationAlignmentMode.OneAttachment
		a.Attachment0 = attachment
		a.RigidityEnabled = false
		a.Responsiveness = 60
		a.MaxTorque = math.huge
		a.Parent = root
		align = a
		local v = Instance.new("LinearVelocity")
		v.Attachment0 = attachment
		v.MaxForce = 0
		v.RelativeTo = Enum.ActuatorRelativeTo.World
		v.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		v.PrimaryTangentAxis = Vector3.xAxis
		v.SecondaryTangentAxis = Vector3.zAxis
		v.Parent = root
		velocity = v
		Context.stamina = Context.stats.maxStamina
		Context.rolling = false
	end
	Context.player.CharacterAdded:Connect(setup)
	if Context.player.Character then
		task.spawn(setup, Context.player.Character)
	end

	InputController.onRoll:connect(function()
		if Context.rolling or rollCooldown > 0 or Context.downed() or Context.menuOpen then
			return
		end
		if Context.stamina < Context.stats.rollCost then
			return
		end
		local character = Context.character()
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local move = humanoid.MoveDirection
		rollDir = if move.Magnitude > 0.1
			then Vector3.new(move.X, 0, move.Z).Unit
			else Vector3.new(Context.aimX, 0, Context.aimZ)
		Context.rolling = true
		rollTime = 0
		Context.stamina -= Context.stats.rollCost
		staminaDelay = 0.8
		Context.remotes.Roll:FireServer()
		Context.signals.shot:fire("roll")
	end)

	Context.remotes.Hurt.OnClientEvent:Connect(
		function(amount: number, dirX: number, dirZ: number, knock: number, continuous: boolean)
			Context.signals.hurt:fire(amount, continuous)
			if continuous then
				return
			end
			Context.shake(math.min(0.6, 0.15 + amount / 60))
			local character = Context.character()
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and knock > 0 then
				root:ApplyImpulse(Vector3.new(dirX, 0.15, dirZ) * knock * S * root.AssemblyMass * 0.6)
			end
		end
	)

	Context.remotes.Adrenaline.OnClientEvent:Connect(function()
		Context.stamina = math.min(Context.stats.maxStamina, Context.stamina + 8)
		boost = 0.6
	end)

	RunService.Heartbeat:Connect(function(dt)
		local character = Context.character()
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			return
		end
		-- Your own revive prompt is only for teammates.
		local prompt = root:FindFirstChild("Revive")
		if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
			prompt.Enabled = false
		end
		local stats = Context.stats
		rollCooldown = math.max(0, rollCooldown - dt)
		boost = math.max(0, boost - dt)
		local downed = Context.downed()

		-- Facing: aim direction (or roll direction while rolling).
		if align then
			local dir = if Context.rolling then rollDir else Vector3.new(Context.aimX, 0, Context.aimZ)
			if dir.Magnitude > 0.01 and not downed then
				align.CFrame = CFrame.lookAt(Vector3.zero, dir)
			end
		end

		if Context.rolling then
			rollTime += dt
			local t = math.min(1, rollTime / BASE.rollDuration)
			local speed = (ROLL_SPEED_START + (ROLL_SPEED_END - ROLL_SPEED_START) * t) * S
			if velocity then
				velocity.MaxForce = math.huge
				velocity.PlaneVelocity = Vector2.new(rollDir.X, rollDir.Z) * speed
			end
			if rollTime >= BASE.rollDuration then
				Context.rolling = false
				rollCooldown = BASE.rollCooldown
				if velocity then
					velocity.MaxForce = 0
				end
			end
			return
		end

		local moving = humanoid.MoveDirection.Magnitude > 0.1
		local sprinting = Context.sprinting and moving and not exhausted and not downed and Context.stamina > 0
		if sprinting then
			Context.stamina = math.max(0, Context.stamina - BASE.staminaDrain * dt)
			staminaDelay = 0.8
			if Context.stamina <= 0 then
				exhausted = true
			end
		else
			staminaDelay = math.max(0, staminaDelay - dt)
			if staminaDelay <= 0 then
				Context.stamina = math.min(stats.maxStamina, Context.stamina + stats.staminaRegen * dt)
			end
		end
		if exhausted and Context.stamina >= stats.maxStamina * 0.3 then
			exhausted = false
		end
		Context.exhausted = exhausted
		if not downed then
			local speed = stats.speed
				* (if sprinting then BASE.sprintMultiplier else 1)
				* (if boost > 0 then 1.2 else 1)
			humanoid.WalkSpeed = speed * S
		end
	end)
end

return CharacterController
