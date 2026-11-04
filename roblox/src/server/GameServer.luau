--[[
	Server entry point: builds the arena and every gameplay service, wires the
	remotes, and runs the co-op game loop:

	  waiting --(party arrived)--> countdown --> wave (a floor of the climb)
	                                  ^             | floor done
	                                  |             v
	                             intermission <-- reward (pick 1 of 3 cards)
	                             (bell/timer)       |
	  Home place <-- gameover <-- everyone downed, or the top floor is cleared

	Parties form on the Home place (src/home) and are teleported here into a
	reserved server; the run starts once the whole party is in. After game
	over everyone is sent back Home. In Studio (or before the place IDs in
	Config/Places are set) one player is enough and game over starts a new run.

	Each "wave" is a floor of the tower climb (Config/Floors, FloorPlan) with
	an objective and a modifier. After a floor everyone picks a reward card
	(RewardRules), then the 30-second grace period opens the merchant,
	workbench and alarm bell, containers restock, and players trade, craft,
	loot, equip gear and build.

	Shared state for the HUD is published as attributes on
	ReplicatedStorage.GameState.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Config.Constants)
local Waves = require(Shared.Config.Waves)
local Floors = require(Shared.Config.Floors)
local Weapons = require(Shared.Config.Weapons)
local Places = require(Shared.Config.Places)
local Tiers = require(Shared.Config.Tiers)
local Cosmetics = require(Shared.Cosmetics)
local FloorPlan = require(Shared.FloorPlan)
local Gear = require(Shared.Gear)
local RewardRules = require(Shared.RewardRules)
local Collision = require(Shared.Collision)
local FlowField = require(Shared.FlowField)
local MathUtil = require(Shared.Util.MathUtil)
local NavGrid = require(Shared.NavGrid)
local Net = require(Shared.Net)
local Rng = require(Shared.Util.Rng)
local ShopRules = require(Shared.ShopRules)
local Shop = require(Shared.Config.Shop)
local Visuals = require(Shared.Config.Visuals)

local Abilities = require(script.Parent.Abilities)
local ArenaBuilder = require(script.Parent.ArenaBuilder)
local Combat = require(script.Parent.Combat)
local Hazards = require(script.Parent.Hazards)
local Leaderboard = require(script.Parent.Leaderboard)
local Profile = require(script.Parent.Profile)
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
		aliveCap = 220,
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
	W.night = 0

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
	function W.rebuildNav()
		W.nav:rebuild(collision.colliders, NAV_INFLATE, function(c)
			return W.structures:isStructureCollider(c)
		end)
		flowDirty = true
	end

	local reset: () -> ()
	local phase = "waiting"
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
			W.stations:setPhase(p)
			W.loot:setActive(p ~= "waiting" and p ~= "gameover")
		end
	end

	-- Waiting for the party: how many the Home page sent, and since when.
	local partySize = 1
	local firstJoin: number? = nil
	local homeBoundAt: number? = nil

	W.onPlayerJoined = function(ps)
		if phase ~= "waiting" then
			W.notifyAll(`{ps.player.DisplayName} joined the fight`, "info")
			return
		end
		firstJoin = firstJoin or os.clock()
		local ok, data = pcall(function()
			return ps.player:GetJoinData().TeleportData
		end)
		if ok and type(data) == "table" and type(data.partySize) == "number" then
			partySize = math.clamp(math.floor(data.partySize), 1, Players.MaxPlayers)
		end
		-- The difficulty tier the party leader picked on the Home page (Studio: STUDIO_TIER).
		local tier = if ok
				and type(data) == "table"
				and type(data.tier) == "number"
			then data.tier
			else Tiers.STUDIO_TIER
		W.waves.tier = Tiers.get(tier)
		stateFolder:SetAttribute("Tier", W.waves.tier.tier)
		stateFolder:SetAttribute("TierName", W.waves.tier.name)
	end

	-- Scrip: saved to each player's profile straight away; `amount` is shown at game over.
	local function awardScrip(ps, transform: (Cosmetics.Profile) -> number)
		task.spawn(function()
			local ok, amount = Profile.update(ps.userId, function(p)
				return true, transform(p)
			end)
			if ok and ps.player.Parent then
				W.notify(ps.player, `+{amount} Scrip`, "good")
			end
		end)
	end
	W.onBossKilled = function()
		local tier = W.waves.tier.tier
		for _, ps in W.players:list() do
			ps.scripEarned += Tiers.get(tier).scripBoss
			awardScrip(ps, function(p)
				return Cosmetics.applyBoss(p, tier)
			end)
		end
	end
	W.onPlayerLeft = function(_ps)
		if W.players and W.players:count() == 0 then
			reset()
			partySize = 1
			firstJoin = nil
			homeBoundAt = nil
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
	W.abilities = Abilities.new(W)
	W.loot = LootService.new(W, arena.layout)
	local leaderboard = Leaderboard.new()
	W.rebuildNav()

	------------------------------------------------------------ phases

	reset = function()
		W.zombies:clear()
		W.hazards:clear()
		W.pickups:clear()
		W.weapons:clear()
		W.combat:reset()
		W.structures:clear()
		W.waves:reset()
		W.abilities:clear()
		W.players:resetAll()
		W.throwables:clear()
		W.loot:clear()
		setPhase("waiting")
	end

	local function startRun()
		W.zombies:clear()
		W.hazards:clear()
		W.pickups:clear()
		W.weapons:clear()
		W.combat:reset()
		W.structures:clear()
		W.waves:reset()
		W.waves.plan = FloorPlan.build(W.rng)
		W.abilities:clear()
		W.players:resetAll()
		W.throwables:clear()
		W.loot:restock(1, true)
		runStart = os.clock()
		setPhase("countdown", Constants.COUNTDOWN_SECONDS)
	end

	local gameOver: (boolean) -> ()

	-- Applies a reward card to a player.
	local function applyReward(ps, card)
		if card.kind == "gear" and card.item then
			if not W.players:giveGear(ps, card.item) then
				-- Stash full: salvage it straight into materials.
				for id, n in Gear.salvageValue(card.item) do
					ps.inventory:add(id, n)
				end
				W.players:syncInventory(ps)
				W.notify(ps.player, "Stash full — the gear was salvaged into materials", "info")
			end
		elseif card.kind == "perk" and card.perk and ps.perks:canTake(card.perk) then
			ps.perks:add(card.perk)
			W.players:refreshStats(ps)
		elseif card.kind == "coins" then
			ps.economy:addCoins(card.amount or 0)
		elseif card.kind == "supplies" and card.supplies then
			for id, n in card.supplies do
				ps.inventory:add(id, n)
			end
			W.players:syncInventory(ps)
		elseif card.kind == "heal" then
			ps.hp = ps.stats.maxHealth
			ps.armor = ps.stats.maxArmor
		end
		ps.rewardOffer = {}
		W.players:syncAttributes()
	end

	-- After the reward pick: the full grace period every GRACE_EVERY floors, otherwise a
	-- short breather (the countdown to the next floor) so a 30-floor climb stays ~25 minutes.
	local function startGrace()
		for _, ps in W.players:list() do
			if #ps.rewardOffer > 0 then
				applyReward(ps, ps.rewardOffer[1]) -- didn't choose in time
			end
		end
		if W.waves.wave % Constants.GRACE_EVERY == 0 then
			setPhase("intermission", Constants.INTERMISSION_SECONDS)
		else
			setPhase("countdown", Constants.BREATHER_SECONDS)
		end
	end

	local function onWaveCleared()
		local floor = W.waves.wave
		if floor >= Floors.FLOORS then
			gameOver(true)
			return
		end
		local info = W.waves:floorInfo(floor)
		local bonus = math.floor(Waves.clearBonus(floor) * W.waves.modifier.coins * W.waves.tier.coins + 0.5)
		local rewarded = not W.waves.bellBroken
		for _, ps in W.players:list() do
			ps.economy:addCoins(bonus)
			if ps.downed then
				W.players:revive(ps, 0.5)
			end
			ps.arsenal:reloadAll()
			ps.ready = false
			W.players:syncArsenal(ps)
			ps.rewardOffer = {}
			if rewarded then
				ps.rewardOffer = RewardRules.roll(
					W.rng,
					floor,
					info ~= nil and info.boss,
					ps.perks:rollChoices(W.rng, 2),
					function()
						return W.players:newUid(ps)
					end
				)
				remotes.RewardOffer:FireClient(ps.player, ps.rewardOffer)
			end
		end
		W.pickups.vacuum = true
		W.loot:restock(floor + 1, false)
		W.fx("waveClear", { wave = floor, bonus = bonus })
		if rewarded then
			setPhase("reward", Floors.REWARD_SECONDS)
		else
			startGrace()
		end
	end

	gameOver = function(victory: boolean)
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
		local tier = W.waves.tier
		for _, ps in W.players:list() do
			leaderboard:submit(ps.userId, ps.economy.score)
			if victory then
				-- A win pays Scrip and unlocks the next tier for everyone who was there.
				ps.scripEarned += tier.scripWin
				awardScrip(ps, function(p)
					return Cosmetics.applyWin(p, tier.tier)
				end)
			end
			remotes.GameOver:FireClient(ps.player, {
				victory = victory,
				tier = tier.tier,
				tierName = tier.name,
				scrip = ps.scripEarned,
				unlocked = if victory and tier.tier < Tiers.MAX then tier.tier + 1 else nil,
				score = ps.economy.score,
				wavesSurvived = if victory then wave else math.max(0, wave - 1),
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

	-- Sends everyone back to the Home place. False in Studio or without a place ID.
	local function sendHome(): boolean
		if Places.HOME_PLACE_ID == 0 or RunService:IsStudio() then
			return false
		end
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(Places.HOME_PLACE_ID, Players:GetPlayers())
		end)
		if not ok then
			warn(`[GameServer] Teleport home failed: {err}`)
		end
		return ok
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
		if ps and phase ~= "waiting" then
			W.weapons:onFire(ps, weaponId, dirs, aimDistance)
		end
	end)
	remotes.Melee.OnServerEvent:Connect(function(player, aimX, aimZ)
		local ps = stateOf(player)
		if ps and phase ~= "waiting" then
			W.weapons:onMelee(ps, aimX, aimZ)
		end
	end)
	remotes.UseAbility.OnServerEvent:Connect(function(player, slot, aimX, aimZ, aimDistance)
		local ps = stateOf(player)
		if ps and phase ~= "waiting" and phase ~= "gameover" then
			W.abilities:use(ps, slot, aimX, aimZ, aimDistance)
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
	remotes.Emote.OnServerEvent:Connect(function(player, id)
		local ps = stateOf(player)
		if ps then
			W.players:playEmote(ps, id)
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
	remotes.UseItem.OnServerEvent:Connect(function(player, id, aimX, aimZ, aimDistance)
		local ps = stateOf(player)
		if not ps or phase == "waiting" or ps.downed or not ps.hasBody then
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
			local n = math.min(count, ps.inventory:count(id))
			if n > 0 and ps.inventory:remove(id, n) then
				W.players:syncInventory(ps)
				if phase ~= "waiting" and ps.hasBody then
					-- Dropped items land in a bag at your feet for anyone to pick up.
					W.pickups:spawnBag(ps.x, ps.z, { [id] = n }, ps)
				end
			end
		end
	end)
	remotes.ChooseReward.OnServerEvent:Connect(function(player, index)
		local ps = stateOf(player)
		if ps and phase == "reward" and type(index) == "number" and ps.rewardOffer[index] then
			applyReward(ps, ps.rewardOffer[index])
		end
	end)
	-- Dropping works anywhere: the thing lands at your feet for anyone to pick up.
	remotes.DropGun.OnServerEvent:Connect(function(player, id)
		local ps = stateOf(player)
		if ps and phase ~= "waiting" and type(id) == "string" then
			W.players:dropGun(ps, id)
		end
	end)
	remotes.DropGear.OnServerEvent:Connect(function(player, uid)
		local ps = stateOf(player)
		if ps and phase ~= "waiting" and type(uid) == "number" then
			W.players:dropGear(ps, uid)
		end
	end)
	remotes.EquipGear.OnServerEvent:Connect(function(player, uid, slot)
		local ps = stateOf(player)
		if ps and phase ~= "waiting" and type(uid) == "number" and (slot == nil or type(slot) == "number") then
			W.players:equipGear(ps, uid, slot)
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
			gear = {
				find = function(uid: number)
					return W.players:findGear(ps, uid)
				end,
				stashFull = function()
					return #ps.gear.stash >= Gear.STASH_SIZE
				end,
				give = function(item)
					return W.players:giveGear(ps, item)
				end,
				remove = function(uid: number)
					return W.players:removeGear(ps, uid)
				end,
				newUid = function()
					return W.players:newUid(ps)
				end,
				rng = W.rng,
				inStash = function(uid: number)
					for _, item in ps.gear.stash do
						if item.uid == uid then
							return true
						end
					end
					return false
				end,
			},
			removeGun = function(id: string)
				W.players:removeGun(ps, id)
			end,
			dropGun = function(id: string)
				W.players:dropGun(ps, id)
				W.notify(ps.player, `Dropped your {Weapons.defs[id].name} to make room`, "info")
			end,
		}
	end

	remotes.Purchase.OnServerInvoke = function(player, action)
		local ps = stateOf(player)
		if not ps or type(action) ~= "table" or type(action.kind) ~= "string" then
			return false
		end
		local clean = {
			kind = action.kind,
			weapon = if type(action.weapon) == "string" then action.weapon else nil,
			upgrade = if type(action.upgrade) == "string" then action.upgrade else nil,
			id = if type(action.id) == "string" then action.id else nil,
			structure = if type(action.structure) == "string" then action.structure else nil,
			uid = if type(action.uid) == "number" then action.uid else nil,
			count = if type(action.count) == "number" and action.count == action.count then action.count else nil,
		}
		-- The merchant trades all run; the workbench only between floors.
		local station = ShopRules.STATION[clean.kind]
		if not station or not W.stations:isOpen(station) or not W.stations:near(ps, station) then
			return false
		end
		local ok = ShopRules.purchase(shopContext(ps) :: any, clean)
		if ok then
			W.players:syncInventory(ps)
			if clean.uid then
				-- Reinforced / re-rolled gear may be equipped: refresh everything that reads it.
				W.players:refreshStats(ps)
				W.players:syncGear(ps)
			end
			if clean.kind == "sellGun" then
				W.players:updateGunModel(ps)
				W.players:syncGear(ps)
			end
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
		if not ps or not W.stations:isOpen(name) or not W.stations:near(ps, name) then
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

	------------------------------------------------------------ world look

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Parent = Lighting
	-- Colour grading, glow and sun rays (Config/Visuals), blended by time of day.
	local function effect(className: string): any
		local e = Lighting:FindFirstChildOfClass(className) or Instance.new(className)
		e.Parent = Lighting
		return e
	end
	local grade = effect("ColorCorrectionEffect")
	local bloom = effect("BloomEffect")
	local sunRays = effect("SunRaysEffect")
	bloom.Size = Visuals.BLOOM.size
	sunRays.Spread = Visuals.SUN_RAYS.spread
	Lighting.ShadowSoftness = Visuals.LIGHTING.shadowSoftness
	Lighting.EnvironmentDiffuseScale = Visuals.LIGHTING.environmentDiffuse
	Lighting.EnvironmentSpecularScale = Visuals.LIGHTING.environmentSpecular
	local function lerp(pair: { number }, n: number): number
		return pair[1] + (pair[2] - pair[1]) * n
	end

	local DAY_FOG = Color3.fromRGB(167, 178, 184)
	local DUSK_FOG = Color3.fromRGB(122, 92, 90)
	local NIGHT_FOG = Color3.fromRGB(13, 18, 32)

	local function applyNight(n: number)
		Lighting.ClockTime = (14 + n * 10) % 24
		Lighting.Brightness = 2.4 - n * 1.9
		Lighting.ExposureCompensation = -0.1 * n
		Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128):Lerp(Color3.fromRGB(40, 46, 70), n)
		Lighting.Ambient = Color3.fromRGB(70, 70, 70):Lerp(Color3.fromRGB(14, 16, 26), n)
		-- Floor modifiers: Thick Fog thickens the air, Blood Moon tints everything red.
		local m = if phase == "wave" then W.waves.modifier else Floors.modifiers.none
		atmosphere.Density = 0.3 + n * 0.22 + m.fog
		atmosphere.Haze = 1 + n
		atmosphere.Color = if n < 0.45
			then DAY_FOG:Lerp(DUSK_FOG, n / 0.45)
			else DUSK_FOG:Lerp(NIGHT_FOG, (n - 0.45) / 0.55)
		local g = Visuals.GRADE
		grade.TintColor = g.dayTint:Lerp(g.nightTint, n)
		if m.id == "bloodMoon" then
			grade.TintColor = grade.TintColor:Lerp(Color3.fromRGB(255, 120, 110), 0.45)
		end
		grade.Contrast = lerp(g.contrast, n)
		grade.Saturation = lerp(g.saturation, n)
		grade.Brightness = lerp(g.brightness, n)
		bloom.Intensity = lerp(Visuals.BLOOM.intensity, n)
		bloom.Threshold = lerp(Visuals.BLOOM.threshold, n)
		sunRays.Intensity = Visuals.SUN_RAYS.intensity * math.max(0, 1 - n * 2)
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

	setPhase("waiting")
	applyNight(night)

	RunService.Heartbeat:Connect(function(frameDt)
		local dt = math.min(frameDt, 0.1)
		local now = Workspace:GetServerTimeNow()
		local wave = W.waves.wave
		local targetNight = if phase == "waiting"
			then 0.55
			elseif phase == "wave" then Waves.night(math.max(1, wave))
			else Waves.night(math.max(1, wave + 1))
		night = MathUtil.damp(night, targetNight, 0.5, dt)
		W.night = night

		W.players:tick(dt, night)
		W.targets = W.players:targets()
		local bell = W.waves:extraTargets()
		if bell then
			table.insert(W.targets, bell)
		end

		if phase == "waiting" then
			local here = W.players:count()
			stateFolder:SetAttribute("PartyHere", here)
			stateFolder:SetAttribute("PartySize", partySize)
			-- After game over, players are on their way Home; if the teleport
			-- failed, they're still here after a while, so play again.
			if homeBoundAt and os.clock() - homeBoundAt > 30 then
				homeBoundAt = nil
			end
			local waited = if firstJoin then os.clock() - firstJoin else 0
			-- Start once everyone has a character in the world (a fresh join may still be loading).
			local spawned = true
			for _, ps in W.players:list() do
				if not ps.hasBody then
					spawned = false
				end
			end
			if
				not homeBoundAt
				and here > 0
				and spawned
				and (here >= partySize or waited >= Constants.PARTY_WAIT_SECONDS)
			then
				startRun()
			end
		elseif phase == "countdown" then
			if now >= phaseEnd then
				W.pickups.vacuum = false
				W.waves:start(W.players:count())
				local info = W.waves:floorInfo()
				W.fx("waveStart", {
					wave = W.waves.wave,
					boss = info ~= nil and info.boss,
					objective = W.waves.objective,
					modifier = W.waves.modifier.id,
				})
				setPhase("wave")
				applyNight(night)
			end
		elseif phase == "reward" then
			local waiting = false
			for _, ps in W.players:list() do
				if #ps.rewardOffer > 0 then
					waiting = true
				end
			end
			if now >= phaseEnd or not waiting then
				startGrace()
			end
		elseif phase == "intermission" then
			if now >= phaseEnd or everyoneReady() then
				for _, ps in W.players:list() do
					ps.ready = false
				end
				setPhase("countdown", Constants.COUNTDOWN_SECONDS)
			end
		elseif phase == "gameover" then
			if now >= phaseEnd then
				reset()
				if sendHome() then
					homeBoundAt = os.clock()
				end
			end
		end

		if phase ~= "waiting" then
			updateFlow(dt)
			W.zombies:update(dt)
			W.weapons:update(dt)
			W.throwables:update(dt)
			W.abilities:update(dt)
			W.combat:processExplosions()
			W.structures:update(dt)
			W.hazards:update(dt)
			W.pickups:update(dt)
			if phase == "wave" then
				if W.waves:update(dt) then
					onWaveCleared()
				elseif W.players:allDown() then
					gameOver(false)
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
		-- Floor objective state for the HUD.
		local upcoming = W.waves:floorInfo(if phase == "wave" then W.waves.wave else W.waves.wave + 1)
		stateFolder:SetAttribute("Floors", Floors.FLOORS)
		stateFolder:SetAttribute("Tier", W.waves.tier.tier)
		stateFolder:SetAttribute("TierName", W.waves.tier.name)
		stateFolder:SetAttribute("Objective", if upcoming then upcoming.objective else "clear")
		stateFolder:SetAttribute("Modifier", if upcoming then upcoming.modifier else "none")
		stateFolder:SetAttribute("TimeLeft", if phase == "wave" then W.waves:timeLeft() else 0)
		local bellState = W.waves.bell
		stateFolder:SetAttribute("BellHp", if phase == "wave" and bellState then bellState.hp / bellState.maxHp else -1)
		local elite = W.waves.elite
		stateFolder:SetAttribute(
			"EliteHp",
			if phase == "wave" and elite and not elite.dying then elite.hp / elite.maxHp else -1
		)
		if math.abs(night - appliedNight) > 0.003 then
			appliedNight = night
			applyNight(night)
		end
	end)
end

return GameServer
