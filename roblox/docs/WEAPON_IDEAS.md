# Weapon ideas, with balancing

**Added so far:** .357 Revolver, Double-Barrel, Marksman Rifle (DMR), Baseball Bat and Spear, with the stats below. Everything else here is still an idea.

This is a list of weapons that could be added to Deadfall Square, tuned against the guns already in `src/shared/Config/Weapons.luau`. The stats use the same fields as `WeaponDef`, so an approved row can be pasted in.

## How to read the numbers

- **Burst DPS** = damage × pellets × fire rate. This is the damage per second while the trigger is held and the magazine lasts.
- **Sustained DPS** = damage × pellets × mag ÷ (mag ÷ fire rate + reload time). This is the real output over a long fight, including reloads.
- **Coins per sustained DPS** is the price ÷ sustained DPS. It measures value for money. Current guns sit between about 3.6 (shotgun) and 6.6 (sniper). The launcher is about 10, but it hits several zombies at once. A new gun should sit near its peers. It should only go above that band if it hits many targets (AoE, pierce, chains).
- **Breakpoints** are how many hits a gun needs to kill a zombie, and they matter more than raw DPS.
  - On floor 1: Walker 34 HP, Runner 18, Spitter 30, Exploder 26, Brute 240, Abomination 1,900.
  - Health scales by `Waves.hpMultiplier`: ×1.5 on floor 5, ×2.4 on floor 10, ×5.1 on floor 20 and ×6.9 on floor 25.
  - Upgrades (+15% damage per tier, up to 5) and gear power push guns past breakpoints. A gun that one-shots Walkers early stops doing so around floor 4–5 unless it is upgraded. That is intended: it creates a reason to upgrade.

## Current guns (baseline)

| Gun | Burst DPS | Sustained DPS | Price | Coins / sDPS | Walker hits | Role |
|---|---|---|---|---|---|---|
| M9 Pistol (after the nerf: 12 dmg, 3.5/s, 10 mag) | 42 | 31 | free | — | 3 | Fallback, infinite ammo |
| Pump Shotgun | 101 | 72 | 260 | 3.6 | 1 | Close crowds |
| Vector SMG | 117 | 75 | 340 | 4.5 | 4 | Spray, ammo hungry |
| AR-15 Rifle | 162 | 106 | 520 | 4.9 | 2 | All-rounder |
| Bolt Sniper | 142 | 97 | 640 | 6.6 | 1 | Pierces 5, lines and elites |
| Flamethrower | 264 | 179 | 720 | 4.0 | 3 | 8 m range, burn |
| Grenade Launcher | 138 | 87 | 900 | 10.4 | 1 | AoE (r 4.2) |

Gaps this leaves:
- no cheap high-damage sidearm;
- nothing between the rifle and the sniper;
- no "hold the line" gun;
- nothing late-game that answers the boss and elites besides the sniper;
- no crafted gun, even though the game is about scavenging.

## Proposed guns

| # | Gun | Kind | Dmg × pellets | Rate | Mag / reload | Range | Burst / sustained DPS | Price | Coins / sDPS | Role | Weakness | New code? |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **.357 Revolver** | hitscan | 46 × 1 | 1.9 | 6 / 2.0 s | 42 | 87 / 54 | 300 | 5.6 | One-shots Walkers and Runners to about floor 4; pierce 1 | Slow, poor against crowds and Brutes | none |
| 2 | **Double-Barrel** | hitscan | 12 × 10 | 3.0 | 2 / 2.3 s | 12 | 360 / 81 | 380 | 4.7 | Huge two-shot burst; deletes a Brute charge | Long reload after every 2 shots | none |
| 3 | **Burst Carbine** | hitscan, 3-round burst | 22 × 1 | 7.5 | 24 / 1.7 s | 50 | 165 / 108 | 600 | 5.6 | Accurate rifle step-up (spread 0.02) | Bursts waste ammo on Runners | burst fire |
| 4 | **Marksman Rifle (DMR)** | hitscan | 58 × 1 | 2.6 | 12 / 2.0 s | 60 | 151 / 105 | 700 | 6.7 | Semi-auto sniper; pierce 1; one-shots Walkers to floor 5 | Weak up close; low knockback | none |
| 5 | **M249 LMG** | hitscan | 15 × 1 | 11 | 90 / 4.2 s | 40 | 165 / 109 | 760 | 7.0 | Holds a lane for a whole defend floor | 15% slower while held; big move spread (0.12); 4 s reload | move-speed modifier |
| 6 | **Auto Shotgun** | hitscan | 8 × 7 | 3.8 | 10 / 3.0 s | 12 | 213 / 99 | 980 | 9.9 | Late-game crowd shredder at close range | Range 12; expensive ammo | none |
| 7 | **Nail Gun** | hitscan | 13 × 1 | 6.5 | 40 / 2.0 s | 20 | 84 / 64 | crafted (8 scrap, 2 elec) | — | Workbench gun; ammo comes from scrap, not coins; pierce 2 | Short range, low damage late | ammo from materials |
| 8 | **Arc Projector** | chain | 22 × 1, chains to 4 at 70% each | 4.0 | 30 / 2.4 s | 14 | ≈223 / 170 against crowds (88 / 67 single target) | 1,150 | 6.8 (crowd) | Sci-fi-ish scavenger tech; clears packs and stuns Exploders | Bad single-target; can't chain through walls | chain hit |
| 9 | **Railgun** | hitscan, 0.6 s charge | 420 × 1 | 0.55 | 3 / 3.2 s | 90 | 231 / 146 | 1,500, Unique only | 10.3 | Boss and elite killer; pierces everything | Charge-up leaves you open; 3 shots | charge-up |

Notes:
- **Revolver vs pistol:** after the pistol nerf (31 sustained DPS) the revolver is a clear step up at 54. It is a cheap first buy that spends a gun slot, which is the point.
- **Double-barrel vs pump:** about the same sustained output, front-loaded. Its 0.7 s Brute kill is the reason to buy it. Watch knockback: two blasts at 5 knockback each can fling Brutes out of melee range. That is fine, but cap it.
- **DMR and LMG** both cost more per DPS than the rifle on purpose, because they get pierce or uptime. If playtests show the rifle is still always picked, cut the DMR's price to 620 before buffing its damage.
- **Auto shotgun and railgun** are late-game guns. Make them Rare or Unique rewards (floor 12+ and 18+), not merchant stock. That way the merchant's best buy stays the rifle or flamer, and rewards feel special.
- **Nail gun** is the only gun that turns materials into damage. Keep its coin price at 0 and its damage low, or scrap stops being a choice between barricades and bullets.

## Melee additions

Current: Machete 26 × 2.6/s = 68 DPS (110° arc), Fire Axe 44 × 1.6 = 70 (150° arc), Sledgehammer 82 × 0.95 = 78 (stagger).

| Weapon | Damage | Swings/s | DPS | Range / arc | Price | Role |
|---|---|---|---|---|---|---|
| **Baseball Bat** | 30 | 1.9 | 57 | 2.2 / 120° | 90 | Cheap; the finisher staggers (sledge-lite) |
| **Katana** | 31 | 2.4 | 74 | 2.3 / 100° | 420, Rare+ | Fastest high-DPS blade; best with Serrated (bleed) |
| **Spear** | 40 | 1.5 | 60 | 3.3 / 50° | 240 | Reach; hits everything in a straight line |
| **Chainsaw** | 9 per tick, 10 ticks/s while held | — | 90 | 2.0 / 70° | Unique only | Hold to cut; 20% slower while revving; uses fuel (shares flamer ammo) |

Keep melee DPS at or below about 80 so guns stay the main damage source. The chainsaw's 90 is paid for with the speed penalty and fuel.

## Throwables (next to the pipe bomb)

Pipe bomb: 220 damage, radius 4.5, 4 s fuse, crafted.

| Throwable | Effect | Craft | Notes |
|---|---|---|---|
| **Molotov** | 5 s fire pool, radius 3, 18 DPS plus burning | 1 rags, 1 gunpowder, 1 glass bottle (new loot) | Area denial for defend floors. Lower burst than the pipe bomb |
| **Flashbang** | Stuns everything in a radius of 6 for 2 s | 1 elec, 1 gunpowder | No damage. Rescues a downed teammate |
| **Sticky Bomb** | Sticks to the first zombie hit; 260 damage, radius 3 | 2 gunpowder, 1 scrap | For Brutes and elites |

## Before adding more guns

- **Slots: decided.** Players carry the pistol plus **two** guns (`Arsenal.MAX_GUNS`). Any number of guns can exist, and each pick is a real choice, so new guns can be a little stronger than when you could own all of them.
- **New mechanics, cheapest first:**
  1. a speed modifier while held (LMG, chainsaw);
  2. burst fire (carbine);
  3. charge-up (railgun);
  4. materials as ammo (nail gun);
  5. chain hits (arc projector).
- **Ammo prices** follow `price / 1200` in `Shop.luau`, so expensive guns automatically cost more to refill. Check the auto shotgun and railgun refills after adding them.
- **Test** each new gun by playing floors 1, 5, 10 and 20 with it alone. Record time-to-clear and how often it reloads. A gun that clears floor 10 more than 20% faster than the rifle at a similar price is overtuned.

## Recommended first batch

1. **Revolver**, **Double-Barrel** and **DMR**: they need no new code, fill real gaps and are easy to judge.
2. **Baseball Bat** and **Spear**: also no new code (melee definitions only).
3. Then the LMG, auto shotgun and railgun (the carry limit is now in place).
