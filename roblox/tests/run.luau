--[[
	Unit tests for the pure shared modules, run with Lune (outside Roblox):
	    lune run tests/run
	Exits non-zero if any test fails.
]]
local process = require("@lune/process")

local Rng = require("../src/shared/Util/Rng")
local MathUtil = require("../src/shared/Util/MathUtil")
local SpatialHash = require("../src/shared/Util/SpatialHash")
local Collision = require("../src/shared/Collision")
local NavGrid = require("../src/shared/NavGrid")
local FlowField = require("../src/shared/FlowField")
local Economy = require("../src/shared/Economy")
local PerkState = require("../src/shared/PerkState")
local Arsenal = require("../src/shared/Arsenal")
local PlayerStats = require("../src/shared/PlayerStats")
local ShopRules = require("../src/shared/ShopRules")
local WaveComposition = require("../src/shared/WaveComposition")
local Waves = require("../src/shared/Config/Waves")
local Zombies = require("../src/shared/Config/Zombies")
local Weapons = require("../src/shared/Config/Weapons")
local Net = require("../src/shared/Net")
local ArenaLayout = require("../src/shared/ArenaLayout")
local W = require("../src/shared/Config/Constants").WORLD_HALF
local MeshSizes = require("../src/shared/Config/MeshSizes")
local Inventory = require("../src/shared/Inventory")
local Items = require("../src/shared/Config/Items")
local Loot = require("../src/shared/Loot")
local Shop = require("../src/shared/Config/Shop")
local Floors = require("../src/shared/Config/Floors")
local FloorPlan = require("../src/shared/FloorPlan")
local Gear = require("../src/shared/Gear")
local RewardRules = require("../src/shared/RewardRules")
local MeleeMath = require("../src/shared/MeleeMath")
local PartyRules = require("../src/shared/PartyRules")
local AnimationClips = require("../src/shared/Config/AnimationClips")
local Animations = require("../src/shared/Config/Animations")

local passed, failed = 0, 0
local current = ""

local function test(name: string, fn: () -> ())
	current = name
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local function expect(cond: boolean, msg: string?)
	if not cond then
		error(msg or "expectation failed", 2)
	end
end

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error(`{msg or "values differ"}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

-------------------------------------------------------------------- core
test("Rng is deterministic and matches the browser PRNG", function()
	local a, b = Rng.new(42), Rng.new(42)
	for _ = 1, 100 do
		eq(a:next(), b:next())
	end
	-- First outputs of mulberry32(42), as produced by the TypeScript version.
	local r = Rng.new(42)
	local v = r:next()
	expect(v >= 0 and v < 1, "range")
	expect(near(v, 0.6011037519201636, 1e-12), `mulberry32(42) first value, got {v}`)
end)

test("Rng.int stays in range and weighted skips zero weights", function()
	local r = Rng.new(1)
	for _ = 1, 1000 do
		local v = r:int(3, 7)
		expect(v >= 3 and v <= 7)
		expect(r:weighted({ a = 1, b = 0, c = 3 }) ~= "b")
	end
end)

test("SpatialHash finds exactly the points within the radius", function()
	local h = SpatialHash.new(-50, -50, 50, 50, 2)
	local rng = Rng.new(3)
	local pts = {}
	h:clear()
	for i = 1, 300 do
		pts[i] = { rng:range(-45, 45), rng:range(-45, 45) }
		h:insert(i, pts[i][1], pts[i][2])
	end
	local out = {}
	local n = h:query(5, -3, 7.5, out)
	local found = {}
	for i = 1, n do
		found[out[i]] = true
	end
	for i, p in pts do
		local inside = math.sqrt((p[1] - 5) ^ 2 + (p[2] + 3) ^ 2) <= 7.5
		eq(found[i] == true, inside, `point {i}`)
	end
end)

test("MathUtil angles and rays", function()
	expect(near(MathUtil.wrapAngle(math.pi * 3), math.pi))
	expect(near(MathUtil.wrapAngle(-math.pi * 1.5), math.pi / 2))
	expect(near(MathUtil.rayCircle(0, 0, 1, 0, 5, 0, 1), 4))
	eq(MathUtil.rayCircle(0, 0, -1, 0, 5, 0, 1), -1)
	expect(near(MathUtil.rayAabb(0, 0, 0, 1, -1, 3, 1, 5), 3))
	eq(MathUtil.formatTime(125), "2:05")
end)

-------------------------------------------------------------- navigation
local function navSetup()
	local col = Collision.new(-20, -20, 20, 20)
	col:addBox(-20, -1, 10, 1, 3)
	col:addBox(14, -1, 20, 1, 3)
	local grid = NavGrid.new(-20, -20, 20, 20)
	grid:rebuild(col.colliders, 0.4, function(c)
		return c.owner == "structure"
	end)
	return col, grid, FlowField.new(grid)
end

test("NavGrid rasterises obstacles and blocks line of sight", function()
	local _, grid = navSetup()
	eq(grid:get(grid:col(0), grid:row(0)), NavGrid.SOLID)
	eq(grid:get(grid:col(12), grid:row(0)), NavGrid.FREE)
	eq(grid:lineOfSight(0, -5, 0, 5, true), false)
	eq(grid:lineOfSight(12, -5, 12, 5, true), true)
end)

test("FlowField routes around a wall through the gap", function()
	local _, _, flow = navSetup()
	flow:compute({ { 0, 10 } })
	local x, z = -15, -10
	for _ = 1, 400 do
		local dx, dz = flow:sample(x, z)
		if not dx then
			break
		end
		x += dx * 0.25
		z += (dz :: number) * 0.25
	end
	expect(math.sqrt(x * x + (z - 10) ^ 2) < 1.5, `ended at {x},{z}`)
	expect(flow:distanceAt(-15, -10) > math.sqrt(15 ^ 2 + 20 ^ 2))
end)

test("FlowField with several targets leads to the nearest one", function()
	local _, _, flow = navSetup()
	flow:compute({ { -15, 15 }, { 15, -15 } })
	local dx, dz = flow:sample(15, -12)
	expect(dx ~= nil)
	expect((dz :: number) < 0, "should head to the nearby target at z=-15")
end)

test("FlowField passes through structures only when it must", function()
	local col, grid, flow = navSetup()
	col:addBox(10, -1, 14, 1, 1.2, "structure")
	grid:rebuild(col.colliders, 0.4, function(c)
		return c.owner == "structure"
	end)
	eq(grid:get(grid:col(12), grid:row(0)), NavGrid.STRUCTURE)
	flow:compute({ { 0, 10 } })
	expect(flow:distanceAt(-15, -10) < math.huge)
end)

test("Collision push-out, height-aware raycast and removal", function()
	local col = Collision.new(-10, -10, 10, 10)
	local b = col:addBox(-1, -1, 1, 1, 2)
	col:addCircle(5, 5, 1, 2)
	local x, z = col:resolveCircle(1.2, 0, 0.5)
	expect(near(x, 1.5) and near(z, 0))
	local qx, qz = col:resolveCircle(5.5, 5, 0.5)
	expect(near(math.sqrt((qx - 5) ^ 2 + (qz - 5) ^ 2), 1.5))
	col:addBox(3, -1, 4, 1, 0.8)
	col:addBox(6, -1, 7, 1, 2.0)
	local t = col:raycast(1.5, 0, 1, 0, 9, 1.25)
	expect(near(t, 4.5), `ray hit at {t}`)
	col:remove(b)
	eq(col:overlapsCircle(0, 0, 0.2), false)
end)

-------------------------------------------------------------- progression
test("Economy combo multiplier, cap and reset", function()
	local e = Economy.new()
	for _ = 1, 10 do
		e:registerKill(10, 1)
	end
	eq(e:multiplier(), 2)
	e:update(3.01)
	eq(e.comboCount, 0)
	for _ = 1, 200 do
		e:registerKill(1, 1)
	end
	eq(e:multiplier(), 5)
	local f = Economy.new()
	f:addCoins(50)
	eq(f:spend(60), false)
	eq(f:spend(50), true)
	eq(f.coins, 0)
end)

test("Arsenal enforces fire rate and auto-reloads", function()
	local a = Arsenal.new()
	local shots = 0
	local t = 0
	while t < 1 do
		if a:tryFire(t, 0, 1) == "fired" then
			shots += 1
		end
		t += 1 / 60
	end
	expect(shots >= 3 and shots <= 4, `pistol fired {shots} shots in 1s`)
	for _ = 1, 20 do
		a:tryFire(t, 0, 1)
		t += 0.5
	end
	expect(a:currentState().mag > 0, "infinite pistol reserve keeps reloading")
end)

test("Arsenal reload moves ammo from reserve", function()
	local a = Arsenal.new()
	a:give("shotgun")
	a:switchTo("shotgun", 0)
	local w = a:currentState()
	w.mag = 1
	local reserve = w.reserve
	eq(a:startReload(1, 1), true)
	a:finishReload(1 + Weapons.defs.shotgun.reloadTime + 0.01)
	eq(w.mag, Weapons.defs.shotgun.magSize)
	eq(w.reserve, reserve - (Weapons.defs.shotgun.magSize - 1))
end)

test("Arsenal give, cycle and serialization round-trip", function()
	local a = Arsenal.new()
	eq(a:give("smg"), "new")
	eq(a:give("smg"), "ammo")
	a:give("sniper")
	a:cycle(1, 0)
	eq(a.current, "smg")
	a:cycle(1, 1)
	eq(a.current, "sniper")
	a:cycle(1, 2)
	eq(a.current, "pistol")
	local b = Arsenal.new()
	b:applySerialized(a:serialize())
	eq(b:currentState().reserve, math.huge)
	expect(b:owns("sniper") and b:owns("smg"))
end)

test("PerkState offers distinct perks and respects max stacks", function()
	local p = PerkState.new()
	local choices = p:rollChoices(Rng.new(5), 3)
	eq(#choices, 3)
	expect(choices[1] ~= choices[2] and choices[2] ~= choices[3] and choices[1] ~= choices[3])
	p:add("adrenaline")
	eq(p:canTake("adrenaline"), false)
	for seed = 1, 50 do
		for _, id in p:rollChoices(Rng.new(seed), 3) do
			expect(id ~= "adrenaline")
		end
	end
end)

test("Armor absorbs 70% and stats follow upgrades and perks", function()
	local h, a = PlayerStats.applyArmor(100, 50, 10)
	eq(h, 97)
	eq(a, 43)
	local p = PerkState.new()
	local base = PlayerStats.compute({ maxHealth = 0, armor = 0, speed = 0, stamina = 0 }, p)
	p:add("thickSkin")
	p:add("quickHands")
	local up = PlayerStats.compute({ maxHealth = 2, armor = 1, speed = 1, stamina = 0 }, p)
	eq(up.maxHealth, base.maxHealth + 40)
	eq(up.maxArmor, base.maxArmor + 25)
	expect(up.speed > base.speed and up.damageTaken < 1 and up.reloadSpeed > 1)
end)

local function shopContext(coins: number, capacity: number?)
	local economy = Economy.new()
	economy:addCoins(coins)
	local tiers = { maxHealth = 0, armor = 0, speed = 0, stamina = 0, backpack = 0 }
	local ctx = {
		economy = economy,
		arsenal = Arsenal.new(),
		inventory = Inventory.new(capacity or 1000),
		health = 40,
		maxHealth = 100,
		tiers = tiers,
		healed = false,
		structureCount = function(_t: string)
			return 0
		end,
		structuresMissingHp = 0,
		applyPlayerUpgrade = function(id: string)
			tiers[id] += 1
		end,
		healFull = function() end,
		repairStructures = function() end,
	}
	ctx.healFull = function()
		ctx.healed = true
	end
	return ctx
end

test("Arsenal carries the pistol plus two guns; buying a third swaps the one in hand", function()
	local a = Arsenal.new()
	eq(a:give("shotgun"), "new")
	eq(a:give("smg"), "new")
	eq(a:give("rifle"), "full")
	expect(not a:owns("rifle"))
	eq(a:inSlot(1), "pistol")
	eq(a:inSlot(2), "shotgun")
	eq(a:inSlot(3), "smg")
	-- Holding the pistol: slot 2 is the one swapped out; holding a gun: that gun.
	eq(a:swapTarget(), "shotgun")
	a:switchTo("smg", 0)
	eq(a:swapTarget(), "smg")
	expect(not a:attune("rifle", { uid = 1, rarity = "rare", power = 1.2, traits = {} }))
	-- The shop drops the gun in hand to make room and equips the new one.
	local ctx = shopContext(100000)
	ctx.arsenal:give("shotgun")
	ctx.arsenal:give("smg")
	ctx.arsenal:switchTo("shotgun", 0)
	local dropped = nil
	ctx.dropGun = function(id)
		dropped = id
		ctx.arsenal:remove(id)
	end
	eq(ShopRules.purchase(ctx, { kind = "buyWeapon", weapon = "rifle" }), true)
	eq(dropped, "shotgun")
	expect(ctx.arsenal:owns("rifle") and ctx.arsenal:owns("smg") and not ctx.arsenal:owns("shotgun"))
	eq(ctx.arsenal.current, "rifle")
	eq(ctx.arsenal:gunCount(), Arsenal.MAX_GUNS)
end)

test("Shop buys weapons, escalates upgrade prices, caps tiers", function()
	local ctx = shopContext(300)
	eq(ShopRules.purchase(ctx, { kind = "buyWeapon", weapon = "smg" }), false)
	eq(ShopRules.purchase(ctx, { kind = "buyWeapon", weapon = "shotgun" }), true)
	eq(ctx.economy.coins, 40)
	eq(ShopRules.getOffer(ctx, { kind = "buyWeapon", weapon = "shotgun" }).reason, "OWNED")
	local rich = shopContext(100000)
	local up = { kind = "weaponUpgrade", weapon = "pistol", upgrade = "magazine" }
	local first = ShopRules.getOffer(rich, up).cost
	-- Weapon upgrades also need materials.
	eq(ShopRules.purchase(rich, up), false)
	rich.inventory:add("scrap", 20)
	rich.inventory:add("parts", 20)
	eq(ShopRules.purchase(rich, up), true)
	eq(rich.inventory:count("scrap"), 19)
	expect(ShopRules.getOffer(rich, up).cost > first)
	eq(rich.arsenal:currentState().mag, 15)
	ShopRules.purchase(rich, up)
	ShopRules.purchase(rich, up)
	eq(ShopRules.getOffer(rich, up).reason, "MAX")
	eq(ShopRules.purchase(rich, { kind = "heal" }), true)
	eq(rich.healed, true)
	eq(ShopRules.purchase(rich, { kind = "playerUpgrade", id = "speed" }), true)
	eq(rich.tiers.speed, 1)
	eq(ShopRules.purchase(rich, { kind = "structure", structure = "barricade" }), false)
	eq(ShopRules.purchase(rich, { kind = "buyWeapon", weapon = "nonsense" }), false)
end)

------------------------------------------------------------------- waves
local function threat(wave: number): number
	local comp = WaveComposition.build(wave, Rng.new(wave), 1)
	local hp = 0
	for _, t in comp do
		hp += Zombies.defs[t].hp
	end
	return hp * Waves.hpMultiplier(wave) * Waves.damageMultiplier(wave)
end

test("Wave 1 is a small group of walkers; types unlock on schedule", function()
	local w1 = WaveComposition.build(1, Rng.new(1), 1)
	expect(#w1 >= 10 and #w1 <= 14, `wave 1 size {#w1}`)
	for _, t in w1 do
		eq(t, "walker")
	end
	local function contains(list, v)
		return table.find(list, v) ~= nil
	end
	expect(contains(WaveComposition.build(2, Rng.new(2), 1), "runner"))
	expect(contains(WaveComposition.build(3, Rng.new(3), 1), "spitter"))
	expect(contains(WaveComposition.build(4, Rng.new(4), 1), "exploder"))
	expect(contains(WaveComposition.build(6, Rng.new(6), 1), "brute"))
	for w = 1, 30 do
		expect(not contains(WaveComposition.build(w, Rng.new(w), 1), "boss"))
	end
end)

test("Difficulty rises: wave 10 >> wave 1, wave 21 >> wave 10", function()
	local last = 0
	for w = 1, 24 do
		if not Waves.isBossWave(w) then
			local t = threat(w)
			expect(t > last, `threat not increasing at wave {w}`)
			last = t
		end
	end
	expect(threat(10) / threat(1) > 10)
	expect(threat(21) / threat(10) > 3)
end)

test("Co-op scales the horde with player count", function()
	local solo = #WaveComposition.build(8, Rng.new(8), 1)
	local four = #WaveComposition.build(8, Rng.new(8), 4)
	expect(four > solo * 2, `solo {solo}, four players {four}`)
	expect(Waves.bossHpMultiplier(5, 4) > Waves.bossHpMultiplier(5, 1))
end)

---------------------------------------------------------------- network
test("Snapshot packing round-trips and fits an unreliable packet", function()
	local records = {}
	for i = 1, Net.MAX_PER_PACKET do
		records[i] =
			{ id = i * 7, x = -33.21 + i, z = 41.5 - i, facing = (i * 0.37) % 6.28, state = 2, hp = 0.5, flags = 3 }
	end
	local b = Net.pack(records, 1, #records, 1234.5)
	expect(buffer.len(b) <= 900, `packet is {buffer.len(b)} bytes`)
	local time, out = Net.unpack(b)
	eq(time, 1234.5)
	eq(#out, #records)
	for i, r in out do
		eq(r.id, records[i].id)
		expect(near(r.x, records[i].x, 0.011) and near(r.z, records[i].z, 0.011))
		expect(near(MathUtil.wrapAngle(r.facing - records[i].facing), 0, 0.03))
		eq(r.flags, 3)
	end
end)

test("Arena layout has spawns, lamps, colliders and a clear player spawn", function()
	local layout = ArenaLayout.generate()
	eq(#layout.spawns, 8)
	expect(#layout.lamps >= 9)
	expect(#layout.colliders > 60)
	expect(#layout.pieces > 300)
	local col = Collision.new(-W, -W, W, W)
	for _, c in layout.colliders do
		col:insert(table.clone(c) :: any)
	end
	local s = layout.playerSpawn
	eq(col:overlapsCircle(s[1], s[3], 0.6), false)
	-- Every spawn alley must reach the plaza.
	local grid = NavGrid.new(-W, -W, W, W)
	grid:rebuild(col.colliders, 0.45, function()
		return false
	end)
	local flow = FlowField.new(grid)
	flow:compute({ { s[1], s[3] } })
	for _, sp in layout.spawns do
		expect(flow:distanceAt(sp.x, sp.z) < math.huge, `spawn {sp.x},{sp.z} unreachable`)
	end
end)

test("Inventory respects its weight limit and takes costs atomically", function()
	local inv = Inventory.new(2)
	eq(inv:add("wood", 5), 2) -- 0.8 kg each
	eq(inv:count("wood"), 2)
	eq(inv:fits("cloth", 10), 2) -- 0.4 kg left at 0.2 kg each
	eq(inv:add("cloth", 10), 2)
	expect(near(inv:weight(), 2))
	eq(inv:add("cloth", 1), 0)
	eq(inv:take({ wood = 1, cloth = 3 }), false)
	eq(inv:count("cloth"), 2, "a failed take changes nothing")
	eq(inv:take({ wood = 1, cloth = 2 }), true)
	eq(inv:count("cloth"), 0)
	eq(inv.items.cloth, nil)
	eq(inv:remove("wood", 2), false)
	eq(inv:add("nonsense", 1), 0)
	local copy = Inventory.new(1)
	copy:load(inv:serialize())
	eq(copy:count("wood"), 1)
	eq(copy.capacity, 2)
end)

test("Loot rolls are deterministic and only produce known items", function()
	for kind, t in Loot.tables do
		for id in t.entries do
			expect(id == "coins" or id == "ammo" or Items.defs[id] ~= nil, `{kind} drops unknown {id}`)
		end
		local a = Loot.roll(Rng.new(7), kind, 1)
		local b = Loot.roll(Rng.new(7), kind, 1)
		local total = 0
		for id, n in a do
			eq(b[id], n, "same seed, same loot")
			expect(n >= 1)
			total += 1
		end
		expect(total >= 1, `{kind} rolled nothing`)
	end
	-- Later waves roll more often.
	local early, late = 0, 0
	for seed = 1, 40 do
		for _, n in Loot.roll(Rng.new(seed), "crate", 1) do
			early += n
		end
		for _, n in Loot.roll(Rng.new(seed), "crate", 16) do
			late += n
		end
	end
	expect(late > early)
end)

test("Workbench crafting, hand-loading, structures and repairs use materials", function()
	local ctx = shopContext(0)
	-- Every action kind belongs to a station.
	for _, kind in { "buyWeapon", "ammo", "playerUpgrade", "heal", "buyItem" } do
		eq(ShopRules.STATION[kind], "merchant")
	end
	for _, kind in { "weaponUpgrade", "craft", "handload", "repair", "structure" } do
		eq(ShopRules.STATION[kind], "workbench")
	end
	eq(ShopRules.purchase(ctx, { kind = "craft", id = "bandage" }), false)
	ctx.inventory:add("cloth", 3)
	eq(ShopRules.purchase(ctx, { kind = "craft", id = "bandage" }), true)
	eq(ctx.inventory:count("cloth"), 1)
	eq(ctx.inventory:count("bandage"), 1)
	eq(ShopRules.purchase(ctx, { kind = "craft", id = "nonsense" }), false)

	-- Hand-loaded ammo for a weapon that isn't full.
	ctx.arsenal:give("shotgun")
	local w = ctx.arsenal:get("shotgun")
	w.reserve = 0
	ctx.inventory:add("gunpowder", 2)
	ctx.inventory:add("scrap", 1)
	eq(ShopRules.purchase(ctx, { kind = "handload", weapon = "shotgun" }), true)
	eq(w.reserve, math.floor(48 * Shop.handload.fraction + 0.5))
	eq(ShopRules.getOffer(ctx, { kind = "handload", weapon = "pistol" }).available, false)

	-- Structures are paid in materials when placed.
	eq(ShopRules.purchase(ctx, { kind = "structure", structure = "barricade" }), false)
	eq(ShopRules.payForStructure(ctx, "barricade"), false)
	ctx.inventory:add("wood", 4)
	ctx.inventory:add("scrap", 1)
	eq(ShopRules.payForStructure(ctx, "barricade"), true)
	eq(ctx.inventory:count("wood"), 0)

	-- Repairs cost one plank per REPAIR_HP_PER_WOOD missing.
	ctx.structuresMissingHp = Shop.repairHpPerWood * 2 + 1
	local repair = ShopRules.getOffer(ctx, { kind = "repair" })
	eq((repair.items :: any).wood, 3)

	-- The merchant sells supplies only while they fit in the bag.
	local small = shopContext(1000, 0.5)
	eq(ShopRules.purchase(small, { kind = "buyItem", id = "scrap" }), true)
	eq(ShopRules.getOffer(small, { kind = "buyItem", id = "scrap" }).reason, "BAG FULL")
	eq(small.economy.coins, 1000 - Shop.itemPrices.scrap)
end)

test("Backpack upgrades raise carrying capacity", function()
	local p = PerkState.new()
	local base = PlayerStats.compute({ maxHealth = 0, armor = 0, speed = 0, stamina = 0 }, p)
	eq(base.carryCapacity, Items.BASE_CAPACITY)
	local packed = PlayerStats.compute({ maxHealth = 0, armor = 0, speed = 0, stamina = 0, backpack = 2 }, p)
	eq(packed.carryCapacity, Items.BASE_CAPACITY + 2 * Items.CAPACITY_PER_BACKPACK)
end)

test("Grace-period stations and loot spots are placed and reachable", function()
	local layout = ArenaLayout.generate()
	local names = {}
	for _, st in layout.stations do
		names[st.name] = st
	end
	expect(names.merchant ~= nil and names.workbench ~= nil and names.bell ~= nil)
	local col = Collision.new(-W, -W, W, W)
	for _, c in layout.colliders do
		col:insert(table.clone(c) :: any)
	end
	local grid = NavGrid.new(-W, -W, W, W)
	grid:rebuild(col.colliders, 0.45, function()
		return false
	end)
	local flow = FlowField.new(grid)
	local s = layout.playerSpawn
	flow:compute({ { s[1], s[3] } })
	for _, st in layout.stations do
		eq(col:overlapsCircle(st.px, st.pz, 0.3), false, `{st.name} prompt is inside an obstacle`)
		-- A little further out from the station must be walkable from the player spawn.
		local dx, dz = st.px - st.x, st.pz - st.z
		local len = math.sqrt(dx * dx + dz * dz)
		local ox, oz = st.px + dx / len, st.pz + dz / len
		expect(flow:distanceAt(ox, oz) < math.huge, `{st.name} is unreachable`)
	end
	expect(#layout.loot >= 20, "too few loot spots")
	for _, spot in layout.loot do
		expect(Loot.tables[spot.kind] ~= nil, `unknown loot kind {spot.kind}`)
	end
end)

test("The climb has 25 floors, bosses every fifth and a warm-up first floor", function()
	local a = FloorPlan.build(Rng.new(5))
	local b = FloorPlan.build(Rng.new(5))
	eq(#a, Floors.FLOORS)
	for i, f in a do
		eq(f.floor, i)
		eq(f.boss, i % 5 == 0 or i == Floors.FLOORS, `floor {i} boss flag`)
		eq(f.objective == "boss", f.boss)
		expect(Floors.objectives[f.objective] ~= nil and Floors.modifiers[f.modifier] ~= nil)
		eq(b[i].objective, f.objective, "same seed, same climb")
		eq(b[i].modifier, f.modifier)
		if f.boss then
			eq(f.modifier, "none")
		end
	end
	eq(a[1].objective, "clear")
	eq(a[1].modifier, "none")
	-- Over many climbs every objective shows up.
	local seen = {}
	for seed = 1, 20 do
		for _, f in FloorPlan.build(Rng.new(seed)) do
			seen[f.objective] = true
		end
	end
	for _, id in { "clear", "holdout", "defend", "elite", "boss" } do
		expect(seen[id], `objective {id} never rolled`)
	end
end)

test("Gear rolls are valid, deterministic and get rarer higher up", function()
	for seed = 1, 30 do
		local item = Gear.roll(Rng.new(seed), 10, seed)
		local again = Gear.roll(Rng.new(seed), 10, seed)
		eq(item.id, again.id)
		eq(item.rarity, again.rarity)
		local d = Gear.defs[item.id]
		expect(d ~= nil and d.kind == item.kind)
		eq(#item.traits, Gear.rarities[item.rarity].traits)
		for _, t in item.traits do
			expect(table.find(Gear.traits[t].kinds, item.kind) ~= nil, `trait {t} on {item.kind}`)
		end
		expect(#Gear.describe(item) >= 2)
	end
	local function uniques(floor: number): number
		local n = 0
		for seed = 1, 300 do
			if Gear.roll(Rng.new(seed), floor, 1).rarity == "unique" then
				n += 1
			end
		end
		return n
	end
	expect(uniques(24) > uniques(1), "uniques should be more common near the top")
	eq(Gear.roll(Rng.new(3), 1, 1, nil, "rare").rarity ~= "common", true)
	eq(Gear.roll(Rng.new(3), 1, 1, "melee").kind, "melee")
	-- Armor bonuses feed player stats.
	local vest = Gear.common("riotvest", 1)
	local b = Gear.bonus(vest)
	expect(b.defense > 0.2 and b.speed < 0)
	local p = PerkState.new()
	local tiers = { maxHealth = 0, armor = 0, speed = 0, stamina = 0 }
	local plain = PlayerStats.compute(tiers, p)
	local armored = PlayerStats.compute(tiers, p, b)
	expect(armored.damageTaken < plain.damageTaken and armored.speed < plain.speed)
end)

test("Reward cards: three per floor, rare+ gear on boss floors", function()
	local uid = 0
	local function nextUid()
		uid += 1
		return uid
	end
	for seed = 1, 40 do
		local cards = RewardRules.roll(Rng.new(seed), 7, false, { "vampire", "piercing" }, nextUid)
		eq(#cards, 3)
		local kinds = {}
		for _, c in cards do
			if c.kind ~= "gear" then
				expect(not kinds[c.kind], "duplicate non-gear card")
			end
			kinds[c.kind] = true
			local text = RewardRules.describe(c)
			expect(text.title ~= "" and #text.lines >= 1)
		end
		local boss = RewardRules.roll(Rng.new(seed), 10, true, {}, nextUid)
		eq(boss[1].kind, "gear")
		expect((boss[1].item :: any).rarity ~= "common")
	end
end)

test("Melee arcs, combos and timing", function()
	-- Straight ahead within range: hit. Behind: miss. Too far: miss.
	eq(MeleeMath.inArc(0, 0, 0, 1, 2, math.rad(110), 0, 1.8, 0.4), true)
	eq(MeleeMath.inArc(0, 0, 0, 1, 2, math.rad(110), 0, -1.8, 0.4), false)
	eq(MeleeMath.inArc(0, 0, 0, 1, 2, math.rad(110), 0, 3, 0.4), false)
	-- Just outside the cone, but a wide zombie still overlaps it.
	eq(MeleeMath.inArc(0, 0, 0, 1, 2, math.rad(90), 1.4, 1.2, 0.1), false)
	eq(MeleeMath.inArc(0, 0, 0, 1, 2, math.rad(90), 1.4, 1.2, 0.6), true)
	-- Touching is always a hit.
	eq(MeleeMath.inArc(0, 0, 0, 1, 2, math.rad(30), -0.3, -0.1, 0.4), true)
	eq(MeleeMath.comboStep(0, 0), 1)
	eq(MeleeMath.comboStep(1, 0.5), 2)
	eq(MeleeMath.comboStep(2, 0.5), 3)
	eq(MeleeMath.comboStep(3, 0.5), 1)
	eq(MeleeMath.comboStep(1, 2), 1)
	expect(MeleeMath.interval(2, true) < MeleeMath.interval(2, false))
end)

test("Gun gear survives a sync and powers the gun; gear workbench actions", function()
	local a = Arsenal.new()
	a:attune("shotgun", { uid = 9, rarity = "rare", power = 1.4, traits = { "rapid" } })
	expect(a:owns("shotgun"))
	local copy = Arsenal.new()
	copy:applySerialized(a:serialize())
	local w = copy:get("shotgun") :: any
	eq(w.gear.power, 1.4)
	eq(copy:powerOf("shotgun"), 1.4)
	expect(copy:rateBonus(w) > 1.1)

	local ctx: any = shopContext(10000)
	local stash = { Gear.common("fireaxe", 1) }
	stash[1].rarity = "rare"
	stash[1].traits = { "heavy" }
	ctx.gear = {
		find = function(id)
			for _, it in stash do
				if it.uid == id then
					return it
				end
			end
			return nil
		end,
		stashFull = function()
			return #stash >= Gear.STASH_SIZE
		end,
		give = function(item)
			table.insert(stash, item)
			return true
		end,
		remove = function(id)
			for i, it in stash do
				if it.uid == id then
					table.remove(stash, i)
					return true
				end
			end
			return false
		end,
		newUid = function()
			return 100 + #stash
		end,
		rng = Rng.new(1),
	}
	ctx.inventory:add("scrap", 20)
	ctx.inventory:add("parts", 20)
	ctx.inventory:add("gunpowder", 5)
	eq(ShopRules.purchase(ctx, { kind = "reinforce", uid = 1 }), true)
	eq(stash[1].power, 1.1)
	eq(ShopRules.purchase(ctx, { kind = "reroll", uid = 1 }), true)
	expect(stash[1].traits[1] ~= "heavy", "re-roll changes the trait")
	eq(ShopRules.purchase(ctx, { kind = "buyGear", id = "jacket" }), true)
	eq(#stash, 2)
	local scrapBefore = ctx.inventory:count("scrap")
	eq(ShopRules.purchase(ctx, { kind = "salvage", uid = 1 }), true)
	eq(#stash, 1)
	expect(ctx.inventory:count("scrap") > scrapBefore)
	eq(ShopRules.STATION.buyGear, "merchant")
	eq(ShopRules.STATION.salvage, "workbench")
end)

test("Selling: guns, stash gear and items at the merchant; the pistol stays", function()
	local ctx: any = shopContext(0)
	eq(ShopRules.STATION.sellGun, "merchant")
	eq(ShopRules.STATION.sellGear, "merchant")
	eq(ShopRules.STATION.sellItem, "merchant")
	-- The pistol can't be sold.
	eq(ShopRules.getOffer(ctx, { kind = "sellGun", weapon = "pistol" }).available, false)
	eq(ShopRules.purchase(ctx, { kind = "sellGun", weapon = "pistol" }), false)
	-- A plain shotgun sells for 40% of its price; holding it switches back to the pistol.
	ctx.arsenal:give("shotgun")
	ctx.arsenal:switchTo("shotgun", 0)
	local price = Weapons.defs.shotgun.price
	eq(ShopRules.getOffer(ctx, { kind = "sellGun", weapon = "shotgun" }).gain, math.floor(price * 0.4 + 0.5))
	eq(ShopRules.purchase(ctx, { kind = "sellGun", weapon = "shotgun" }), true)
	eq(ctx.arsenal:owns("shotgun"), false)
	eq(ctx.arsenal.current, "pistol")
	eq(ctx.economy.coins, math.floor(price * 0.4 + 0.5))
	-- Upgrades and rare gear make a gun worth more.
	local plain = ShopRules.gunSellValue("rifle", { upgrades = { damage = 0, fireRate = 0, magazine = 0 } })
	local upgraded = ShopRules.gunSellValue("rifle", { upgrades = { damage = 2, fireRate = 0, magazine = 0 } })
	local rare = ShopRules.gunSellValue(
		"rifle",
		{ upgrades = { damage = 0, fireRate = 0, magazine = 0 }, gear = { rarity = "rare", power = 1.2, traits = {} } }
	)
	expect(upgraded > plain and rare > plain)
	-- Items: one or a stack.
	ctx.inventory:add("parts", 3)
	local each = ShopRules.itemSellValue("parts")
	expect(each > 0)
	eq(ShopRules.getOffer(ctx, { kind = "sellItem", id = "parts", count = 4 }).available, false)
	local before = ctx.economy.coins
	eq(ShopRules.purchase(ctx, { kind = "sellItem", id = "parts", count = 3 }), true)
	eq(ctx.inventory:count("parts"), 0)
	eq(ctx.economy.coins, before + each * 3)
	-- Gear: stash pieces only; rarer is worth more.
	local stash = { Gear.common("fireaxe", 1) }
	local equippedPiece = Gear.common("jacket", 2)
	ctx.gear = {
		find = function(id)
			for _, it in stash do
				if it.uid == id then
					return it
				end
			end
			return if id == 2 then equippedPiece else nil
		end,
		inStash = function(id)
			return id == 1 and #stash > 0
		end,
		remove = function(id)
			if id == 1 and #stash > 0 then
				table.remove(stash, 1)
				return true
			end
			return false
		end,
		stashFull = function()
			return false
		end,
	}
	eq(ShopRules.getOffer(ctx, { kind = "sellGear", uid = 2 }).reason, "EQUIPPED")
	local commonValue = ShopRules.gearSellValue(stash[1])
	local uniqueAxe = Gear.common("fireaxe", 3)
	uniqueAxe.rarity = "unique"
	expect(ShopRules.gearSellValue(uniqueAxe) > commonValue)
	before = ctx.economy.coins
	eq(ShopRules.purchase(ctx, { kind = "sellGear", uid = 1 }), true)
	eq(#stash, 0)
	eq(ctx.economy.coins, before + commonValue)
end)

test("Every mesh the game asks for was generated, and props own their fallback pieces", function()
	local sizes = MeshSizes :: { [string]: { number } }
	local function has(name: string)
		local s = sizes[name]
		expect(s ~= nil, `mesh {name} missing from MeshSizes`)
		expect(s[1] > 0 and s[2] > 0 and s[3] > 0, `mesh {name} has a zero size`)
	end
	for _, name in { "ZombieTorso", "ZombieHead", "ZombieArm", "ZombieLeg", "Barricade", "TurretBase", "TurretHead" } do
		has(name)
	end
	for _, id in Weapons.order do
		has(`Gun_{id}`)
	end
	for _, kind in { "ammo", "health", "armor", "coins", "weapon" } do
		has(`Pickup_{kind}`)
	end
	local layout = ArenaLayout.generate()
	expect(#layout.props > 0, "layout has no props")
	local owned = {}
	for _, piece in layout.pieces do
		if piece.prop then
			expect(layout.props[piece.prop] ~= nil, `piece points at missing prop {piece.prop}`)
			owned[piece.prop] = true
		end
	end
	for i, prop in layout.props do
		has(prop.name)
		expect(owned[i] == true, `prop {prop.name} has no fallback pieces`)
	end
end)

test("Parties: create, join, leader hand-off, full parties and starting", function()
	local st = PartyRules.new()
	local a = PartyRules.create(st, 1)
	eq(a.leader, 1)
	local joined, err = PartyRules.join(st, 2, a.id)
	expect(joined == a and err == nil)
	eq(#a.members, 2)
	-- Only the leader can start.
	expect(PartyRules.canStart(st, 2) == nil)
	expect(PartyRules.canStart(st, 1) == a)
	-- The leader leaving hands the party to the next member.
	PartyRules.leave(st, 1)
	eq(a.leader, 2)
	eq(PartyRules.partyOf(st, 1), nil)
	-- Creating a new party leaves the old one; empty parties disappear.
	local b = PartyRules.create(st, 2)
	expect(st.parties[a.id] == nil, "empty party should be removed")
	eq(PartyRules.partyOf(st, 2), b)
	-- Full parties refuse new members.
	for id = 10, 9 + PartyRules.MAX - 1 do
		expect(PartyRules.join(st, id, b.id) ~= nil)
	end
	local full, why = PartyRules.join(st, 99, b.id)
	expect(full == nil and why ~= nil)
	expect(PartyRules.join(st, 99, 12345) == nil)
	expect(PartyRules.canStart(st, 99) == nil)
end)

test("Every keyframed clip has an id slot, and every reload clip exists", function()
	for name in AnimationClips do
		expect(Animations.IDS[name] ~= nil, `Config/Animations has no id slot for {name}`)
	end
	for name in Animations.IDS do
		expect(AnimationClips[name] ~= nil, `id slot {name} has no generated clip`)
	end
	for weapon, name in Animations.RELOAD do
		expect(Weapons.defs[weapon] ~= nil, `unknown weapon {weapon}`)
		expect(AnimationClips[name] ~= nil, `reload clip {name} missing`)
	end
	expect(AnimationClips.Reload_Rifle ~= nil, "fallback reload clip missing")
	for i = 1, 3 do
		eq(AnimationClips[`Swing_{i}`].length, MeleeMath.SWING_TIME)
	end
	eq(AnimationClips.Roll.length, PlayerStats.BASE.rollDuration)
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
