--[[
	Server entry point: builds the arena and every gameplay service, wires the
	remotes, and runs the co-op game loop:

	  lobby --(everyone ready)--> countdown --> wave --(cleared)--> intermission
	    ^                                        |                     |
	    +---- gameover <--(everyone downed)------+     <--(bell/timer)-+

	The intermission is a 30-second grace period: the merchant, workbench and
	alarm bell in the plaza open, containers restock, and players walk around
	to trade, craft, loot and build.

	Shared state for the HUD is published as attributes on
	ReplicatedStorage.GameState.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Waves = require(Shared.Config.Waves)
local Collision = require(Shared.Collision)
local FlowField = require(Shared.FlowField)
local MathUtil = require(Shared.Util.MathUtil)
local NavGrid = require(Shared.NavGrid)
local Net = require(Shared.Net)
local Rng = require(Shared.Util.Rng)
local ShopRules = require(Shared.ShopRules)
local Shop = require(Shared.Config.Shop)

local ArenaBuilder = require(script.Parent.ArenaBuilder)
local Combat = require(script.Parent.Combat)
local Hazards = require(script.Parent.Hazards)
local Leaderboard = require(script.Parent.Leaderboard)
local LootService = require(script.Parent.LootService)
local Pickups = require(script.Parent.Pickups)
local PlayerService = require(script.Parent.PlayerService)
local Stations = require(script.Parent.Stations)
local Structures = require(script.Parent.Structures)
local Throwables = require(script.Parent.Throwables)
local WaveDirector = require(script.Parent.WaveDirector)
local WeaponService = require(script.Parent.WeaponService)
local ZombieSim = require(script.Parent.ZombieSim)

local NAV_INFLATE = 0.45

local GameServer = {}

function GameServer.start()
	local remotesFolder = Net.setup(true)
	local remotes = {}
	for _, r in remotesFolder:GetChildren() do
		remotes[r.Name] = r
	end

	local stateFolder = Instance.new("Folder")
	stateFolder.Name = "GameState"
	stateFolder.Parent = ReplicatedStorage

	local arena = ArenaBuilder.build()
	local W = {
		remotes = remotes,
		rng = Rng.new(),
		arena = arena,
		spawns = arena.layout.spawns,
		aliveCap = 160,
		targets = {},
	} :: any

	local collision = Collision.new(
		-Constants.WORLD_HALF - 4,
		-Constants.WORLD_HALF - 4,
		Constants.WORLD_HALF + 4,
		Constants.WORLD_HALF + 4
	)
	for _, c in arena.layout.colliders do
		collision:insert(table.clone(c) :: any)
	end
	W.collision = collision
	W.nav = NavGrid.new(-Constants.WORLD_HALF, -Constants.WORLD_HALF, Constants.WORLD_HALF, Constants.WORLD_HALF)
	W.flow = FlowField.new(W.nav)
	-- Second field toward points of interest, for zombies investigating noises.
	W.noiseFlow = FlowField.new(W.nav)
	W.night = 0
	local noiseVersion = -1
	local noiseTimer = 0

	local flowDirty = true
	local flowTimer = 0
	local flowKey = ""

	function W.fx(kind: string, data)
		remotes.Fx:FireAllClients(kind, data)
	end
	function W.notify(player: Player, text: string, tone: string)
		remotes.Notify:FireClient(player, text, tone)
	end
	function W.notifyAll(text: string, tone: string)
		remotes.Notify:FireAllClients(text, tone)
	end
	-- A noise zombies within `radius` metres can hear.
	function W.noise(x: number, z: number, radius: number)
		if W.zombies and radius > 0 then
			W.zombies:hear(x, z, radius)
		end
	end
	function W.rebuildNav()
		W.nav:rebuild(collision.colliders, NAV_INFLATE, function(c)
			return W.structures:isStructureCollider(c)
		end)
		flowDirty = true
		noiseVersion = -1
	end

	local toLobby: () -> ()
	local phase = "lobby"
	local phaseEnd = 0
	local runStart = 0
	local night = 0.55
	local appliedNight = -1

	local function setPhase(p: string, duration: number?)
		phase = p
		phaseEnd = if duration then Workspace:GetServerTimeNow() + duration else 0
		stateFolder:SetAttribute("Phase", p)
		stateFolder:SetAttribute("PhaseEnd", phaseEnd)
		if W.stations then
			W.stations:setOpen(p == "intermission")
			W.loot:setActive(p ~= "lobby" and p ~= "gameover")
		end
	end

	W.onPlayerJoined = function(ps)
		if phase ~= "lobby" then
			W.notifyAll(`{ps.player.DisplayName} joined the fight`, "info")
		end
	end
	W.onPlayerLeft = function(_ps)
		if W.players and W.players:count() == 0 and phase ~= "lobby" then
			toLobby()
		end
	end

	W.combat = Combat.new(W)
	W.zombies = ZombieSim.new(W)
	W.hazards = Hazards.new(W)
	W.pickups = Pickups.new(W)
	W.structures = Structures.new(W)
	W.weapons = WeaponService.new(W)
	W.waves = WaveDirector.new(W)
	W.players = PlayerService.new(W)
	W.throwables = Throwables.new(W)
	W.loot = LootService.new(W, arena.layout)
	local leaderboard = Leaderboard.new()
	W.rebuildNav()

	------------------------------------------------------------ phases

	toLobby = function()
		W.zombies:clear()
		W.hazards:clear()
		W.pickups:clear()
		W.weapons:clear()
		W.combat:reset()
		W.structures:clear()
		W.waves:reset()
		W.players:resetAll()
		W.throwables:clear()
		W.loot:clear()
		setPhase("lobby")
	end

	local function startRun()
		W.zombies:clear()
		W.hazards:clear()
		W.pickups:clear()
		W.weapons:clear()
		W.combat:reset()
		W.structures:clear()
		W.waves:reset()
		W.players:resetAll()
		W.throwables:clear()
		W.loot:restock(1, true)
		runStart = os.clock()
		setPhase("countdown", Constants.COUNTDOWN_SECONDS)
	end

	local function onWaveCleared()
		local wave = W.waves.wave
		local bonus = Waves.clearBonus(wave)
		local perkWave = Waves.isPerkWave(wave)
		for _, ps in W.players:list() do
			ps.economy:addCoins(bonus)
			if ps.downed then
				W.players:revive(ps, 0.5)
			end
			ps.arsenal:reloadAll()
			ps.ready = false
			W.players:syncArsenal(ps)
			if perkWave then
				ps.perkOffer = ps.perks:rollChoices(W.rng, 3)
				if #ps.perkOffer > 0 then
					remotes.PerkOffer:FireClient(ps.player, ps.perkOffer)
				end
			end
		end
		W.pickups.vacuum = true
		W.loot:restock(wave + 1, false)
		W.fx("waveClear", { wave = wave, bonus = bonus })
		setPhase("intermission", Constants.INTERMISSION_SECONDS)
	end

	local function gameOver()
		local wave = W.waves.wave
		local team = {}
		for _, ps in W.players:list() do
			local kills = 0
			for _, n in ps.kills do
				kills += n
			end
			table.insert(
				team,
				{ name = ps.player.DisplayName, score = ps.economy.score, kills = kills, revives = ps.revives }
			)
		end
		table.sort(team, function(a, b)
			return a.score > b.score
		end)
		for _, ps in W.players:list() do
			leaderboard:submit(ps.userId, ps.economy.score)
			remotes.GameOver:FireClient(ps.player, {
				score = ps.economy.score,
				wavesSurvived = math.max(0, wave - 1),
				kills = ps.kills,
				accuracy = if ps.shotsFired > 0 then math.min(1, ps.shotsHit / ps.shotsFired) else 0,
				timePlayed = os.clock() - runStart,
				bestCombo = ps.economy.bestCombo,
				coinsEarned = ps.economy.totalCoinsEarned,
				damageDealt = math.floor(ps.damageDealt + 0.5),
				revives = ps.revives,
				team = team,
			})
		end
		W.waves.active = false
		setPhase("gameover", Constants.GAMEOVER_SECONDS)
	end

	local function everyoneReady(): boolean
		local list = W.players:list()
		if #list == 0 then
			return false
		end
		for _, ps in list do
			if not ps.ready then
				return false
			end
		end
		return true
	end

	------------------------------------------------------------ remotes

	local function stateOf(player: Player)
		return W.players:get(player)
	end

	remotes.Fire.OnServerEvent:Connect(function(player, weaponId, dirs, aimDistance)
		local ps = stateOf(player)
		if ps and phase ~= "lobby" then
			W.weapons:onFire(ps, weaponId, dirs, aimDistance)
		end
	end)
	remotes.Reload.OnServerEvent:Connect(function(player)
		local ps = stateOf(player)
		if ps then
			W.weapons:onReload(ps)
		end
	end)
	remotes.Switch.OnServerEvent:Connect(function(player, arg)
		local ps = stateOf(player)
		if ps then
			W.weapons:onSwitch(ps, arg)
		end
	end)
	remotes.Roll.OnServerEvent:Connect(function(player)
		local ps = stateOf(player)
		local now = os.clock()
		if ps and not ps.downed and now - ps.lastRoll >= 0.55 then
			ps.lastRoll = now
			ps.invulnUntil = math.max(ps.invulnUntil, now + 0.34)
			if player.Character then
				player.Character:SetAttribute("RollAt", Workspace:GetServerTimeNow())
			end
		end
	end)
	remotes.Crouch.OnServerEvent:Connect(function(player, on)
		local ps = stateOf(player)
		if ps and type(on) == "boolean" then
			W.players:setCrouch(ps, on)
		end
	end)
	remotes.UseItem.OnServerEvent:Connect(function(player, id, aimX, aimZ, aimDistance)
		local ps = stateOf(player)
		if not ps or phase == "lobby" or ps.downed or not ps.hasBody then
			return
		end
		if id == "bandage" then
			W.players:useBandage(ps)
		elseif id == "pipebomb" then
			if type(aimX) ~= "number" or type(aimZ) ~= "number" or type(aimDistance) ~= "number" then
				return
			end
			if aimDistance ~= aimDistance or not ps.inventory:has({ pipebomb = 1 }) then
				return
			end
			if W.throwables:throw(ps, aimX, aimZ, aimDistance) then
				ps.inventory:remove("pipebomb", 1)
				W.players:syncInventory(ps)
			end
		end
	end)
	remotes.DiscardItem.OnServerEvent:Connect(function(player, id, count)
		local ps = stateOf(player)
		if ps and type(id) == "string" and type(count) == "number" and count >= 1 and count == math.floor(count) then
			if ps.inventory:remove(id, math.min(count, ps.inventory:count(id))) then
				W.players:syncInventory(ps)
			end
		end
	end)
	remotes.Ready.OnServerEvent:Connect(function(player, value)
		local ps = stateOf(player)
		if ps and type(value) == "boolean" then
			ps.ready = value
		end
	end)
	remotes.ChoosePerk.OnServerEvent:Connect(function(player, id)
		local ps = stateOf(player)
		if ps and type(id) == "string" and table.find(ps.perkOffer, id) and ps.perks:canTake(id) then
			ps.perks:add(id)
			ps.perkOffer = {}
			W.players:refreshStats(ps)
		end
	end)

	local function shopContext(ps)
		return {
			economy = ps.economy,
			arsenal = ps.arsenal,
			inventory = ps.inventory,
			health = ps.hp,
			maxHealth = ps.stats.maxHealth,
			tiers = ps.tiers,
			structureCount = function(t: string)
				return W.structures:countFor(ps, t)
			end,
			structuresMissingHp = W.structures:missingHpFor(ps),
			applyPlayerUpgrade = function(id: string)
				ps.tiers[id] += 1
				W.players:refreshStats(ps)
				if id == "armor" then
					ps.armor = ps.stats.maxArmor
				end
			end,
			healFull = function()
				ps.hp = ps.stats.maxHealth
			end,
			repairStructures = function()
				W.structures:repairFor(ps)
			end,
		}
	end

	remotes.Purchase.OnServerInvoke = function(player, action)
		local ps = stateOf(player)
		if not ps or phase ~= "intermission" or type(action) ~= "table" or type(action.kind) ~= "string" then
			return false
		end
		local clean = {
			kind = action.kind,
			weapon = if type(action.weapon) == "string" then action.weapon else nil,
			upgrade = if type(action.upgrade) == "string" then action.upgrade else nil,
			id = if type(action.id) == "string" then action.id else nil,
			structure = if type(action.structure) == "string" then action.structure else nil,
		}
		local station = ShopRules.STATION[clean.kind]
		if not station or not W.stations:near(ps, station) then
			return false
		end
		local ok = ShopRules.purchase(shopContext(ps) :: any, clean)
		if ok then
			W.players:syncInventory(ps)
			if clean.kind == "buyWeapon" then
				W.players:updateGunModel(ps)
			end
			W.players:syncArsenal(ps)
			W.players:syncStats(ps)
			W.players:syncAttributes()
		end
		return ok
	end

	remotes.Place.OnServerInvoke = function(player, stype, x, z, rotated)
		local ps = stateOf(player)
		if not ps or phase ~= "intermission" then
			return false, "Build between waves"
		end
		if type(stype) ~= "string" or type(x) ~= "number" or type(z) ~= "number" or type(rotated) ~= "boolean" then
			return false, "Invalid"
		end
		if x ~= x or z ~= z then
			return false, "Invalid"
		end
		local def = Shop.structures[stype]
		if not def then
			return false, "Invalid"
		end
		local sx, sz = W.structures:snap(stype, rotated, x, z)
		local ok, reason = W.structures:canPlace(ps, stype, rotated, sx, sz)
		if not ok then
			return false, reason
		end
		if not ShopRules.payForStructure(shopContext(ps) :: any, stype) then
			return false, "Not enough materials"
		end
		W.structures:place(ps, stype, rotated, sx, sz)
		W.players:syncInventory(ps)
		W.players:syncAttributes()
		return true, nil
	end

	------------------------------------------------------------ stations

	local function onStation(name: string, player: Player)
		local ps = stateOf(player)
		if not ps or phase ~= "intermission" or not W.stations:near(ps, name) then
			return
		end
		if name == "bell" then
			ps.ready = not ps.ready
			local ready, total = 0, 0
			for _, other in W.players:list() do
				total += 1
				if other.ready then
					ready += 1
				end
			end
			W.notifyAll(
				if ps.ready
					then `{player.DisplayName} rang the bell ({ready}/{total} ready)`
					else `{player.DisplayName} isn't ready ({ready}/{total})`,
				"info"
			)
			W.players:syncAttributes()
		else
			local x, z = W.stations:position(name)
			remotes.OpenStation:FireClient(player, name, x, z)
		end
	end
	W.stations = Stations.new(W, arena.layout, onStation)

	remotes.GetLeaderboard.OnServerInvoke = function(_player)
		return leaderboard:top()
	end

	------------------------------------------------------------ world look

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
	local DAY_FOG = Color3.fromRGB(167, 178, 184)
	local DUSK_FOG = Color3.fromRGB(122, 92, 90)
	local NIGHT_FOG = Color3.fromRGB(13, 18, 32)

	local function applyNight(n: number)
		Lighting.ClockTime = (14 + n * 10) % 24
		Lighting.Brightness = 2.4 - n * 1.9
		Lighting.ExposureCompensation = -0.1 * n
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128):Lerp(Color3.fromRGB(40, 46, 70), n)
		Lighting.Ambient = Color3.fromRGB(70, 70, 70):Lerp(Color3.fromRGB(14, 16, 26), n)
		atmosphere.Density = 0.3 + n * 0.22
		atmosphere.Haze = 1 + n
		atmosphere.Color = if n < 0.45
			then DAY_FOG:Lerp(DUSK_FOG, n / 0.45)
			else DUSK_FOG:Lerp(NIGHT_FOG, (n - 0.45) / 0.55)
		ArenaBuilder.setNight(arena, n)
		stateFolder:SetAttribute("Night", n)
	end

	------------------------------------------------------------ main loop

	local function updateFlow(dt: number)
		flowTimer -= dt
		local targets = {}
		local keyParts = {}
		for _, ps in W.targets do
			table.insert(targets, { ps.x, ps.z })
			table.insert(keyParts, tostring(W.nav:indexAt(ps.x, ps.z)))
		end
		if #targets == 0 then
			return
		end
		local key = table.concat(keyParts, ",")
		if (key ~= flowKey or flowDirty) and flowTimer <= 0 then
			W.flow:compute(targets)
			flowKey = key
			flowDirty = false
			flowTimer = 0.15
		end
	end

	-- Investigation field: recomputed when the set of points of interest changes.
	local function updateNoiseFlow(dt: number)
		noiseTimer -= dt
		if noiseTimer > 0 then
			return
		end
		noiseTimer = 0.3
		local goals = W.zombies:liveGoals()
		if W.zombies.goalsVersion ~= noiseVersion then
			noiseVersion = W.zombies.goalsVersion
			if #goals > 0 then
				W.noiseFlow:compute(goals)
			else
				W.noiseFlow:compute({ { 0, 6 } })
			end
		end
	end

	setPhase("lobby")
	applyNight(night)

	RunService.Heartbeat:Connect(function(frameDt)
		local dt = math.min(frameDt, 0.1)
		local now = Workspace:GetServerTimeNow()
		local wave = W.waves.wave
		local targetNight = if phase == "lobby"
			then 0.55
			elseif phase == "wave" then Waves.night(math.max(1, wave))
			else Waves.night(math.max(1, wave + 1))
		night = MathUtil.damp(night, targetNight, 0.5, dt)
		W.night = night

		W.players:tick(dt, night)
		W.targets = W.players:targets()

		if phase == "lobby" then
			if everyoneReady() then
				startRun()
			end
		elseif phase == "countdown" then
			if now >= phaseEnd then
				W.pickups.vacuum = false
				W.waves:start(W.players:count())
				W.fx("waveStart", { wave = W.waves.wave, boss = Waves.isBossWave(W.waves.wave) })
				setPhase("wave")
			end
		elseif phase == "intermission" then
			if now >= phaseEnd or everyoneReady() then
				for _, ps in W.players:list() do
					ps.ready = false
					ps.perkOffer = {}
				end
				setPhase("countdown", Constants.COUNTDOWN_SECONDS)
			end
		elseif phase == "gameover" then
			if now >= phaseEnd then
				toLobby()
			end
		end

		if phase ~= "lobby" then
			updateFlow(dt)
			updateNoiseFlow(dt)
			W.zombies:update(dt)
			W.players:markSpotted(W.zombies.spotted)
			W.weapons:update(dt)
			W.throwables:update(dt)
			W.combat:processExplosions()
			W.structures:update(dt)
			W.hazards:update(dt)
			W.pickups:update(dt)
			if phase == "wave" then
				if W.waves:update(dt) then
					onWaveCleared()
				elseif W.players:allDown() then
					gameOver()
				end
			end
			W.combat:processExplosions()
			W.combat:flushHits()
		end

		-- HUD state.
		stateFolder:SetAttribute("Wave", W.waves.wave)
		stateFolder:SetAttribute("Remaining", if phase == "wave" then W.waves:remaining() else 0)
		local boss = W.waves.boss
		stateFolder:SetAttribute("BossId", if boss and not boss.dying then boss.id else 0)
		if boss and not boss.dying then
			stateFolder:SetAttribute("BossHp", boss.hp / boss.maxHp)
			stateFolder:SetAttribute("BossEnraged", boss.enraged)
		end
		stateFolder:SetAttribute("Players", #Players:GetPlayers())
		if math.abs(night - appliedNight) > 0.003 then
			appliedNight = night
			applyNight(night)
		end
	end)
end

return GameServer
