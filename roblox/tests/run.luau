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
	expect(shots >= 4 and shots <= 5, `pistol fired {shots} shots in 1s`)
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

local function shopContext(coins: number)
	local economy = Economy.new()
	economy:addCoins(coins)
	local tiers = { maxHealth = 0, armor = 0, speed = 0, stamina = 0 }
	local ctx = {
		economy = economy,
		arsenal = Arsenal.new(),
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

test("Shop buys weapons, escalates upgrade prices, caps tiers", function()
	local ctx = shopContext(300)
	eq(ShopRules.purchase(ctx, { kind = "buyWeapon", weapon = "smg" }), false)
	eq(ShopRules.purchase(ctx, { kind = "buyWeapon", weapon = "shotgun" }), true)
	eq(ctx.economy.coins, 40)
	eq(ShopRules.getOffer(ctx, { kind = "buyWeapon", weapon = "shotgun" }).reason, "OWNED")
	local rich = shopContext(100000)
	local up = { kind = "weaponUpgrade", weapon = "pistol", upgrade = "magazine" }
	local first = ShopRules.getOffer(rich, up).cost
	eq(ShopRules.purchase(rich, up), true)
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
		records[i] = { id = i * 7, x = -33.21 + i, z = 41.5 - i, facing = (i * 0.37) % 6.28, state = 2, hp = 0.5, flags = 3 }
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
	local col = Collision.new(-48, -48, 48, 48)
	for _, c in layout.colliders do
		col:insert(table.clone(c) :: any)
	end
	local s = layout.playerSpawn
	eq(col:overlapsCircle(s[1], s[3], 0.6), false)
	-- Every spawn alley must reach the plaza.
	local grid = NavGrid.new(-48, -48, 48, 48)
	grid:rebuild(col.colliders, 0.45, function()
		return false
	end)
	local flow = FlowField.new(grid)
	flow:compute({ { s[1], s[3] } })
	for _, sp in layout.spawns do
		expect(flow:distanceAt(sp.x, sp.z) < math.huge, `spawn {sp.x},{sp.z} unreachable`)
	end
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	process.exit(1)
end
