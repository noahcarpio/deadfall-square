--[[
	In-game heads-up display: health/armor/stamina, wave + zombies remaining,
	boss bar, score/coins/combo, weapon/ammo/reload and slots, perk badges,
	teammate list, minimap, crosshair with dynamic spread, toasts, the big
	centre banner and the hurt vignette.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ArenaLayout = require(Shared.ArenaLayout)
local Constants = require(Shared.Config.Constants)
local Perks = require(Shared.Config.Perks)
local Weapons = require(Shared.Config.Weapons)

local Context = require(script.Parent.Parent.Context)
local Audio = require(script.Parent.Parent.Audio)
local Builder = require(script.Parent.Builder)
local Fx = require(script.Parent.Parent.Fx)
local ZombieView = require(script.Parent.Parent.ZombieView)

local create = Builder.create
local T = Builder.theme
local S = Constants.STUDS
local MAP_HALF = Constants.ARENA_HALF + 6

local Hud = {}

local function minimap(parent: Instance): (Frame, (number) -> ())
	local size = 170
	local root = create("Frame", {
		Name = "Minimap",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Color3.fromRGB(20, 24, 22),
		BackgroundTransparency = 0.18,
		ClipsDescendants = true,
		Parent = parent,
	}, { Builder.corner(10), Builder.stroke() })
	local function toUnit(v: number): number
		return (v + MAP_HALF) / (MAP_HALF * 2)
	end
	-- Static obstacles.
	for _, c in ArenaLayout.generate().colliders do
		if math.abs(c.x) <= MAP_HALF + 2 and math.abs(c.z) <= MAP_HALF + 2 then
			local w = math.max(2 / size, (c.maxX - c.minX) / (MAP_HALF * 2))
			local h = math.max(2 / size, (c.maxZ - c.minZ) / (MAP_HALF * 2))
			local f = create("Frame", {
				BorderSizePixel = 0,
				BackgroundColor3 = if c.height > 3 then Color3.fromRGB(150, 145, 135) else Color3.fromRGB(110, 106, 98),
				BackgroundTransparency = 0.2,
				Position = UDim2.fromScale(toUnit(c.minX), toUnit(c.minZ)),
				Size = UDim2.fromScale(w, h),
				Parent = root,
			})
			if c.kind == "circle" then
				create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
			end
		end
	end
	local dots = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	local pool: { Frame } = {}
	local timer = 0
	local function dot(i: number, x: number, z: number, color: Color3, px: number)
		local f = pool[i]
		if not f then
			f = create("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Parent = dots })
			create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = f })
			pool[i] = f
		end
		f.Visible = true
		f.BackgroundColor3 = color
		f.Size = UDim2.fromOffset(px, px)
		f.Position = UDim2.fromScale(toUnit(x), toUnit(z))
	end
	local COLORS = {
		walker = Color3.fromRGB(224, 74, 58),
		runner = Color3.fromRGB(224, 74, 58),
		brute = Color3.fromRGB(255, 58, 42),
		spitter = Color3.fromRGB(154, 255, 74),
		exploder = Color3.fromRGB(255, 154, 42),
		boss = Color3.fromRGB(208, 80, 255),
	}
	local function update(dt: number)
		timer -= dt
		if timer > 0 then
			return
		end
		timer = 1 / 15
		local n = 0
		for _, z in ZombieView.list() do
			n += 1
			dot(n, z.x, z.z, COLORS[z.type] or COLORS.walker, if z.type == "boss" then 9 else 4)
		end
		for _, p in Players:GetPlayers() do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				n += 1
				local me = p == Context.player
				local color = if p:GetAttribute("Downed") then T.danger elseif me then T.accent else T.blue
				dot(n, root.Position.X / S, root.Position.Z / S, color, if me then 8 else 7)
			end
		end
		for i = n + 1, #pool do
			pool[i].Visible = false
		end
	end
	return root, update
end

function Hud.start(gui: ScreenGui)
	local playerGui = gui
	-------------------------------------------------- vitals
	local vitals = Builder.panel({
		Name = "Vitals",
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.fromOffset(250, 104),
		Parent = playerGui,
	})
	Builder.padding(10).Parent = vitals
	Builder.list(6).Parent = vitals
	local function row(name: string, color: Color3, height: number): (Frame, Frame, TextLabel)
		local r = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), Parent = vitals })
		Builder.label(name, 12, {
			Font = T.bold,
			TextColor3 = T.muted,
			Size = UDim2.new(0, 64, 1, 0),
			Parent = r,
		})
		local bar, fill, label = Builder.bar(color, height)
		bar.Position = UDim2.fromOffset(66, 0)
		bar.Size = UDim2.new(1, -66, 1, 0)
		bar.Parent = r
		return r, fill, label
	end
	local _, hpFill, hpLabel = row("HEALTH", Color3.fromRGB(230, 70, 60), 18)
	local _, armorFill, armorLabel = row("ARMOR", Color3.fromRGB(74, 160, 255), 14)
	local _, staminaFill = row("STAMINA", Color3.fromRGB(242, 220, 74), 10)
	local perkTray = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), Parent = vitals })
	Builder.list(5, true).Parent = perkTray

	-------------------------------------------------- wave / boss
	local waveBox = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(420, 110),
		Parent = playerGui,
	})
	local waveLabel = Builder.label("", 40, {
		Font = T.head,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		Parent = waveBox,
	})
	local waveSub = Builder.label("", 16, {
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 44),
		TextStrokeTransparency = 0.6,
		Parent = waveBox,
	})
	local bossFrame = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(40, 68),
		Size = UDim2.new(1, -80, 0, 34),
		Visible = false,
		Parent = waveBox,
	})
	Builder.label("THE ABOMINATION", 16, {
		Font = T.head,
		TextColor3 = T.boss,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bossFrame,
	})
	local bossBar, bossFill = Builder.bar(T.boss, 12)
	bossBar.Position = UDim2.fromOffset(0, 20)
	bossBar.Parent = bossFrame

	-------------------------------------------------- score / coins / combo
	local scoreBox = Builder.panel({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 14),
		Size = UDim2.fromOffset(190, 112),
		Parent = playerGui,
	})
	Builder.padding(10).Parent = scoreBox
	local scoreLabel =
		Builder.label("0", 28, { Font = T.head, TextXAlignment = Enum.TextXAlignment.Right, Parent = scoreBox })
	local coinsLabel = Builder.label("0", 22, {
		Font = T.head,
		TextColor3 = T.gold,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 32),
		Parent = scoreBox,
	})
	local comboLabel = Builder.label("", 26, {
		Font = T.head,
		TextColor3 = T.warn,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 58),
		Parent = scoreBox,
	})
	local comboBar, comboFill = Builder.bar(T.warn, 3)
	comboBar.Position = UDim2.new(0, 0, 1, -3)
	comboBar.Parent = scoreBox

	-------------------------------------------------- team list
	local team = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 136),
		Size = UDim2.fromOffset(190, 160),
		Parent = playerGui,
	})
	Builder.list(4).Parent = team

	-------------------------------------------------- weapon
	local weaponBox = Builder.panel({
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(240, 110),
		Parent = playerGui,
	})
	Builder.padding(10).Parent = weaponBox
	local weaponName = Builder.label("", 16, {
		Font = T.head,
		TextColor3 = T.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = weaponBox,
	})
	local ammoLabel = Builder.label("", 40, {
		Font = T.head,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromOffset(0, 18),
		Parent = weaponBox,
	})
	local reloadBar, reloadFill = Builder.bar(T.accent, 4)
	reloadBar.Position = UDim2.fromOffset(0, 66)
	reloadBar.Parent = weaponBox
	local slots = create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 22),
		Parent = weaponBox,
	})
	local slotLayout = Builder.list(4, true)
	slotLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	slotLayout.Parent = slots
	local slotLabels = {}
	for i, id in Weapons.order do
		local l = create("TextLabel", {
			LayoutOrder = i,
			Text = tostring(i),
			Font = T.bold,
			TextSize = 12,
			Size = UDim2.fromOffset(22, 22),
			BackgroundColor3 = Color3.fromRGB(30, 36, 42),
			TextColor3 = T.muted,
			Parent = slots,
		}, { Builder.corner(4) })
		slotLabels[id] = l
	end

	local mapRoot, mapUpdate = minimap(playerGui)

	-------------------------------------------------- crosshair
	local cross = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(30, 30),
		Parent = playerGui,
	}, {
		create("UICorner", { CornerRadius = UDim.new(1, 0) }),
		create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Transparency = 0.15 }),
	})
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = T.accent,
		Parent = cross,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	-------------------------------------------------- vignette, banner, toasts
	-- Vignette: four edge strips whose gradients fade toward the centre.
	local vignette = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = playerGui })
	local edges = {
		{ UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.22), 90 },
		{ UDim2.fromScale(0, 0.78), UDim2.fromScale(1, 0.22), -90 },
		{ UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0 },
		{ UDim2.fromScale(0.82, 0), UDim2.fromScale(0.18, 1), 180 },
	}
	local edgeGradients: { UIGradient } = {}
	for _, e in edges do
		local f = create("Frame", {
			Position = e[1],
			Size = e[2],
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromRGB(150, 0, 0),
			Parent = vignette,
		})
		local g = create("UIGradient", { Rotation = e[3], Parent = f })
		table.insert(edgeGradients, g)
	end
	local function setVignette(strength: number)
		vignette.Visible = strength > 0.01
		local seq = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - strength),
			NumberSequenceKeypoint.new(1, 1),
		})
		for _, g in edgeGradients do
			g.Transparency = seq
		end
	end
	setVignette(0)
	local banner = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(700, 110),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = playerGui,
	})
	local bannerTitle = Builder.label("", 72, {
		Font = T.head,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.4,
		Parent = banner,
	})
	local bannerSub = Builder.label("", 20, {
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 80),
		TextStrokeTransparency = 0.5,
		Parent = banner,
	})
	local bannerUntil = 0
	local function showBanner(title: string, sub: string, color: Color3, duration: number)
		bannerTitle.Text = title
		bannerTitle.TextColor3 = color
		bannerSub.Text = sub
		banner.Visible = true
		bannerUntil = os.clock() + duration
	end
	local toasts = create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 130),
		Size = UDim2.fromOffset(460, 160),
		Parent = playerGui,
	})
	local toastLayout = Builder.list(6)
	toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	toastLayout.Parent = toasts
	local toastOrder = 0
	local activeToasts: { Frame } = {}
	local TONES = { good = T.accent, bad = T.danger, info = T.blue, boss = T.boss }
	local function toast(text: string, tone: string)
		toastOrder -= 1
		local t = Builder.panel({
			LayoutOrder = toastOrder,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			Parent = toasts,
		})
		Builder.padding(6).Parent = t
		create("TextLabel", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			Text = text,
			Font = T.bold,
			TextSize = 15,
			TextColor3 = TONES[tone] or T.text,
			Parent = t,
		})
		table.insert(activeToasts, t)
		while #activeToasts > 4 do
			local oldest = table.remove(activeToasts, 1)
			if oldest then
				oldest:Destroy()
			end
		end
		task.delay(2.8, function()
			local i = table.find(activeToasts, t)
			if i then
				table.remove(activeToasts, i)
			end
			t:Destroy()
		end)
	end

	-------------------------------------------------- events
	local remotes = Context.remotes
	remotes.Notify.OnClientEvent:Connect(function(text: string, tone: string, x: number?, z: number?)
		if tone == "coin" or tone == "pickup" then
			if x and z then
				Fx.floatText(
					text,
					x,
					if tone == "coin" then 2.4 else 2.6,
					z,
					if tone == "coin" then T.gold else Color3.fromRGB(154, 216, 255),
					if tone == "coin" then 18 else 22
				)
			end
			Audio.play(if tone == "coin" then "coin" else "pickup")
			return
		end
		toast(text, tone)
	end)
	Context.signals.notify:connect(function(kind: string, fxKind: string?, data)
		if kind ~= "fx" then
			return
		end
		if fxKind == "waveStart" then
			if data.boss then
				showBanner(`WAVE {data.wave}`, "BOSS INCOMING — watch for red warnings!", T.boss, 3)
			else
				showBanner(
					`WAVE {data.wave}`,
					if data.wave == 1 then "Survive the horde" else "They keep coming…",
					Color3.fromRGB(255, 217, 207),
					2.4
				)
			end
			Audio.play("waveStart")
		elseif fxKind == "waveClear" then
			showBanner(`WAVE {data.wave} CLEARED`, `+{data.bonus} coins bonus`, T.accent, 3)
			Audio.play("waveClear")
		end
	end)
	local hurtFlash = 0
	Context.signals.hurt:connect(function(_amount: number, continuous: boolean)
		hurtFlash = math.max(hurtFlash, if continuous then 0.35 else 1)
		if not continuous then
			Audio.play("playerHurt")
		end
	end)

	-------------------------------------------------- per-frame update
	local perkSignature = ""
	local teamRows: { [Player]: Frame } = {}
	RunService.RenderStepped:Connect(function(dt)
		local p = Context.player
		local phase = Context.phase()
		local playing = phase ~= "lobby" and phase ~= "gameover"
		for _, f in { vitals, waveBox, scoreBox, weaponBox, mapRoot, team } do
			f.Visible = playing
		end

		local hp, maxHp = p:GetAttribute("HP") or 100, p:GetAttribute("MaxHP") or 100
		hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
		hpLabel.Text = `{hp} / {maxHp}`
		local armor, maxArmor = p:GetAttribute("Armor") or 0, p:GetAttribute("MaxArmor") or 50
		armorFill.Size = UDim2.fromScale(math.clamp(armor / math.max(1, maxArmor), 0, 1), 1)
		armorLabel.Text = `{armor} / {maxArmor}`
		staminaFill.Size = UDim2.fromScale(math.clamp(Context.stamina / Context.stats.maxStamina, 0, 1), 1)
		staminaFill.BackgroundColor3 = if Context.exhausted
			then Color3.fromRGB(106, 100, 64)
			else Color3.fromRGB(242, 220, 74)

		-- Wave status.
		local gs = Context.gameState
		local wave = gs:GetAttribute("Wave") or 0
		local remaining = gs:GetAttribute("Remaining") or 0
		local phaseEnd = gs:GetAttribute("PhaseEnd") or 0
		local secs = math.max(0, math.ceil(phaseEnd - Workspace:GetServerTimeNow()))
		if phase == "countdown" then
			waveLabel.Text = `WAVE {wave + 1}`
			waveSub.Text = `Starting in {secs}`
		elseif phase == "wave" then
			waveLabel.Text = `WAVE {wave}`
			waveSub.Text = `{remaining} zombie{if remaining == 1 then "" else "s"} remaining`
		elseif phase == "intermission" then
			waveLabel.Text = `WAVE {wave} CLEARED`
			waveSub.Text = `Next wave in {secs}s — shop open`
		end
		local bossId = gs:GetAttribute("BossId") or 0
		bossFrame.Visible = bossId ~= 0 and phase == "wave"
		if bossFrame.Visible then
			bossFill.Size = UDim2.fromScale(math.clamp(gs:GetAttribute("BossHp") or 0, 0, 1), 1)
			bossFill.BackgroundColor3 = if gs:GetAttribute("BossEnraged") then T.danger else T.boss
		end

		-- Score / combo.
		scoreLabel.Text = string.format("%d", p:GetAttribute("Score") or 0)
		coinsLabel.Text = `● {p:GetAttribute("Coins") or 0}`
		local combo = p:GetAttribute("Combo") or 0
		comboLabel.Text = if combo >= 2
			then `x{string.format("%.1f", p:GetAttribute("ComboMult") or 1)}  ({combo})`
			else ""
		comboFill.Size = UDim2.fromScale(math.clamp(p:GetAttribute("ComboT") or 0, 0, 1), 1)

		-- Weapon.
		local arsenal = Context.arsenal
		local w = arsenal:currentState()
		local def = Weapons.defs[w.id]
		weaponName.Text = def.name:upper()
		local reserve = if w.reserve == math.huge then "∞" else tostring(w.reserve)
		ammoLabel.Text = `{w.mag} / {reserve}`
		ammoLabel.TextColor3 = if w.mag <= math.ceil(arsenal:magSize(w.id) * 0.25) then T.danger else T.text
		local now = os.clock()
		reloadBar.Visible = arsenal:isReloading(now)
		if reloadBar.Visible then
			reloadFill.Size = UDim2.fromScale(
				math.clamp(1 - (arsenal.reloadEnd - now) / math.max(0.01, arsenal.reloadDuration), 0, 1),
				1
			)
		end
		for id, l in slotLabels do
			local owned = arsenal:owns(id)
			l.BackgroundColor3 = if id == arsenal.current
				then T.accent
				elseif owned then Color3.fromRGB(46, 54, 62)
				else Color3.fromRGB(24, 28, 32)
			l.TextColor3 = if id == arsenal.current
				then Color3.fromRGB(11, 26, 18)
				elseif owned then T.text
				else Color3.fromRGB(70, 74, 80)
		end

		-- Perks.
		local sig = ""
		for _, perk in Context.perks do
			sig ..= perk.id .. perk.level
		end
		if sig ~= perkSignature then
			perkSignature = sig
			for _, c in perkTray:GetChildren() do
				if c:IsA("TextLabel") then
					c:Destroy()
				end
			end
			for i, perk in Context.perks do
				local pdef = Perks.defs[perk.id]
				local color = Color3.fromHex(pdef.color)
				create("TextLabel", {
					LayoutOrder = i,
					Text = if perk.level > 1 then `{pdef.glyph}{perk.level}` else pdef.glyph,
					Font = T.head,
					TextSize = 16,
					TextColor3 = color,
					Size = UDim2.fromOffset(24, 24),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.5,
					Parent = perkTray,
				}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }), create("UIStroke", { Color = color }) })
			end
		end

		-- Teammates.
		for _, other in Players:GetPlayers() do
			if other ~= p then
				local rowFrame = teamRows[other]
				if not rowFrame then
					rowFrame = Builder.panel({ Size = UDim2.new(1, 0, 0, 30), Parent = team })
					Builder.padding(6).Parent = rowFrame
					Builder.label(
						other.DisplayName,
						13,
						{ Name = "Name", Font = T.bold, Size = UDim2.new(1, 0, 0, 14), Parent = rowFrame }
					)
					local bar, fill = Builder.bar(Color3.fromRGB(230, 70, 60), 4)
					bar.Name = "Bar"
					fill.Name = "Fill"
					bar.Position = UDim2.fromOffset(0, 15)
					bar.Parent = rowFrame
					teamRows[other] = rowFrame
				end
				local downed = other:GetAttribute("Downed") == true
				local nameLabel = rowFrame:FindFirstChild("Name") :: TextLabel
				nameLabel.Text = if downed then `{other.DisplayName} — DOWN` else other.DisplayName
				nameLabel.TextColor3 = if downed then T.danger else T.text
				local fill = (rowFrame:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill") :: Frame
				fill.Size = UDim2.fromScale(
					math.clamp((other:GetAttribute("HP") or 0) / (other:GetAttribute("MaxHP") or 100), 0, 1),
					1
				)
			end
		end
		for other, rowFrame in teamRows do
			if other.Parent == nil then
				rowFrame:Destroy()
				teamRows[other] = nil
			end
		end

		-- Crosshair follows the mouse; ring size reflects spread.
		local mouseMode = Context.device == "mouse" and playing and not Context.menuOpen
		cross.Visible = mouseMode
		UserInputService.MouseIconEnabled = not mouseMode and Context.device ~= "gamepad"
		if mouseMode then
			local m = UserInputService:GetMouseLocation()
			cross.Position = UDim2.fromOffset(m.X, m.Y)
			local px = math.clamp(Context.spread * Context.aimDistance * 26 + 14, 14, 140)
			cross.Size = UDim2.fromOffset(px, px)
		end

		-- Vignette: hit flash and low-health pulse.
		hurtFlash = math.max(0, hurtFlash - dt * 3)
		local low = if hp > 0 and hp < maxHp * 0.3 then 0.35 + math.sin(os.clock() * 6) * 0.15 else 0
		local downed = Context.downed()
		setVignette(math.max(hurtFlash * 0.7, low, if downed then 0.6 else 0))

		if banner.Visible and os.clock() > bannerUntil then
			banner.Visible = false
		end
		mapUpdate(dt)
	end)
end

return Hud
