# Deadfall Square

A low-poly 3D zombie wave-survival game that runs in the browser. Hold an abandoned town square against escalating hordes, earn coins, upgrade your arsenal, build barricades and turrets, and survive into the night.

Built with **Three.js + Vite + TypeScript**. Every model is built from Three.js primitives, every texture is drawn procedurally on a canvas, and every sound (including the music) is synthesised at runtime with the Web Audio API — there are no asset files.

## Running locally

Requires Node.js 20+ (CI uses 22).

```bash
npm install
```

```bash
npm run dev
```

Then open the URL Vite prints (default http://localhost:5173). Other scripts:

| Command | What it does |
| --- | --- |
| `npm run build` | Type-check and build to `dist/` |
| `npm run preview` | Serve the production build on port 4173 |
| `npm run check` | Type-check, lint and run unit tests |
| `npm test` | Unit tests (Vitest) |
| `npm run test:e2e` | Playwright end-to-end tests (builds and serves automatically) |

Append `?test=1` to the URL to expose a `window.__game` automation hook (used by the Playwright suite; inactive otherwise).

## Deploying to GitHub Pages

`.github/workflows/deploy.yml` builds and deploys on every push to `main`. In the repository settings, set **Pages → Build and deployment → Source** to **GitHub Actions**. The Vite `base` is `./`, so the build works from any sub-path. A separate `ci.yml` runs type-checks, lint, unit and Playwright tests on pull requests.

## Controls

| Action | Keyboard & mouse | Touch |
| --- | --- | --- |
| Move | WASD / arrow keys | Left half: floating joystick |
| Aim | Mouse | Right half: aim joystick (light aim assist) |
| Shoot | Hold left click | Push the aim stick past 30% (auto-fire) |
| Sprint | Shift (uses stamina) | Push the move stick to its rim |
| Dodge roll | Space (brief invulnerability) | ROLL |
| Reload | R | RELOAD |
| Switch weapon | 1–7, mouse wheel, Q / E | SWAP |
| Pause | Esc / P | II button |
| Placement: rotate / cancel / pan | R or right-click / Esc / WASD | ROTATE / CANCEL / drag |

## Features

**Arena & movement**
- Walled town square: brick and stucco buildings with lit windows and alleys (zombie entrances), a low south fence, wrecked cars, a crashed bus, crates, fences, sandbags, concrete barriers, dumpsters, barrels, trees, benches and a fountain.
- Angled top-down follow camera with aim look-ahead and trauma-based screen shake.
- Sprint with stamina (exhaustion lockout), dodge roll with i-frames, knockback, collision against every obstacle.

**Zombies** — Walker, Runner, Brute (knock-back slam), Spitter (keeps range, lobs acid that leaves damaging puddles), Exploder (fuses near you, chain-explodes on death) and **The Abomination**, a boss every 5 waves that cycles through a telegraphed charge (stuns itself on walls), a ground slam that sends out shockwave rings you can roll through, and runner summons, enraging at half health.

**Waves** — budget-based composition with progressive type unlocks, scaling health/damage/speed, spawn pacing and concurrency caps, a short "wave cleared" break with loot vacuum, then perk and shop screens, then a 3-second countdown.

**Weapons** — M9 pistol (infinite ammo), pump shotgun (falloff), Vector SMG, AR-15, bolt sniper (pierces 5), flamethrower (burning DoT), grenade launcher (arcing AoE). Each has its own fire rate, spread (with movement penalty), damage, magazine, reload time, model, muzzle flash and synthesised sound. 8% critical hits.

**Progression**
- Drops: ammo, health, armor, coin bags and weapon crates, with a pity rule when you're low on ammo and a magnet radius.
- Shop: per-weapon damage / fire-rate / magazine tiers, weapon purchases, ammo refills, field medkit, Vitality, Kevlar, Running Shoes, Endurance, placeable spiked **barricades** and **auto-turrets**, and repairs.
- A choice of 3 random perks every 3 waves (12 perks: Vampire Bullets, Piercing Rounds, Explosive Kills, Quick Hands, Adrenaline, Thick Skin, Scavenger, Incendiary Rounds, Greed, Second Wind, Marathon, Big Game Hunter).
- Score with a kill-combo multiplier (+0.5x per 5 chained kills, up to 5x).

**Feedback** — hit flash, knockback, blood/gib/spark/fire particles, decals, topple-then-dissolve death shader with a glowing edge, floating damage numbers, crits, low-health heartbeat and red vignette.

**UI** — main menu over a live attract-mode scene, how-to-play, settings (master/music/effects volume, mouse sensitivity, graphics quality, show FPS, screen shake, damage numbers — persisted), pause menu, HUD (health, armor, stamina, ammo, weapon slots, wave, zombies remaining, coins, score, combo, perks, boss bar, minimap), game-over stats (waves survived, kills by type, accuracy, time, best combo, coins, damage) and a local top-10 leaderboard with name entry.

**Atmosphere** — the sky moves from afternoon through dusk into full night by wave 11; fog closes in, windows and street lamps light up, and the player's flashlight cone follows the aim. Dynamic shadows, muzzle-flash and explosion lighting. Procedural music (pads, bass, drums and bells in D minor) that shifts between menu, calm, combat and boss moods, plus positional zombie groans.

## Architecture

```
src/
  core/        loop (fixed 60 Hz step), RNG, event bus, spatial hash, math, settings, storage
  config/      all tuning data: weapons, zombies, waves, shop, perks, quality presets
  world/       arena generator, mesh builder, ground texture, collision, nav grid, flow field, lighting
  input/       keyboard/mouse (pointer lock + sensitivity) and twin-stick touch controls
  player/      player controller, stats derivation, procedural model
  zombies/     zombie data, AI behaviours, manager (pool, hash, steering), instanced renderer
  weapons/     arsenal (ammo/reload/fire-rate), firing system (hitscan, flames, grenades), models
  waves/       wave director
  progression/ economy, perks, shop rules, pickups, structures, high scores
  fx/          particles, decals, tracers, damage numbers, hazards (acid, shockwaves, telegraphs)
  audio/       audio engine, SFX recipes, procedural music
  game/        World (simulation), Combat (damage rules), Game (state machine), camera, events, stats
  ui/          HUD, minimap, menus, shop, perks, placement bar, styles
  debug/       test hook (only with ?test=1)
tests/
  unit/        Vitest: math, collision, navigation, economy, arsenal, shop, perks, scores, settings, wave curves
  e2e/         Playwright: screens + console errors, 3-wave playthrough, 140-zombie perf, touch controls
```

`World` owns the simulation and advances systems in a fixed order each step; `Game` owns rendering, the state machine (`menu → playing ⇄ paused → perk → shop ⇄ placing → playing … → gameover`), input mapping and UI. Systems communicate through a typed `EventBus` for cross-cutting concerns (HUD banners, stats, audio cues) and call each other directly where the dependency is real (e.g. `Combat`).

## Design decisions

- **TypeScript (strict)** for a codebase of this size; zero runtime dependencies besides Three.js and a bundled OFL font.
- **Camera:** angled top-down (~58°) rather than over-the-shoulder — it reads crowds better, makes mouse aim precise, and maps cleanly onto twin-stick touch controls. Buildings line only the north/east/west edges; the south edge is a low fence so geometry never hides the player from the camera.
- **Hold-to-fire for every weapon.** Semi-automatic click-per-shot was dropped so desktop and touch behave the same; fire rate is still enforced per weapon.
- **Pointer lock with a virtual cursor** while playing, so mouse sensitivity is meaningful and the cursor can't leave the window. Esc releases the lock and pauses. If pointer lock is unavailable the real cursor is used.
- **Pathfinding: a Dijkstra flow field** toward the player over a 1 m nav grid (inflated by body radius) instead of per-zombie A*. One search (~1 ms, recomputed only when the player changes cell, ≤ 6.7 Hz) serves every zombie in O(1); zombies with line of sight steer directly. Player structures are passable at a high cost, so zombies walk around barricades when they can and smash through them when they can't. Placement is rejected if it would seal the player off from every spawn.
- **Performance:** each zombie body part is one `InstancedMesh` (≈8 draw calls for the whole horde, shadows included); all static scenery is merged into a handful of meshes; particles, decals and tracers are instanced ring buffers in typed arrays; a per-step uniform-grid spatial hash handles crowd separation, flames and explosions; the light count never changes at runtime, so shaders never recompile mid-game; no per-frame allocations in hot loops. Measured headless: 140+ zombies cost ~0.4 ms per simulation step and ~3 ms of CPU render submission with ~25 draw calls.
- **Death animation:** a topple (ragdoll-style fall along the killing blow) followed by a noise-based dissolve with a glowing edge, implemented by patching the built-in materials (including the shadow depth material) via `onBeforeCompile`.
- **Fixed timestep (60 Hz) and a seeded RNG**, so gameplay is frame-rate independent and test runs are reproducible.
- **Robustness:** a watchdog relocates any zombie that makes no progress for 8 s back to the nearest alley, guaranteeing waves always finish.
- **Quality presets:** Low (no shadows, 1x pixel ratio, smaller particle budget, no MSAA on touch devices — default on touch), Medium (sun shadows, default on desktop), High (2k shadows, flashlight shadows). Changing quality applies immediately; the ground texture resolution is chosen at load.
- **Damage numbers are DOM elements** (pooled), which stay crisp at any resolution and cost no draw calls.
- **Accuracy** counts bullets and shotgun pellets individually; a grenade counts as a hit if its blast damages anything; flamethrower particles and turret shots are excluded.

## Balance

All knobs live in `src/config/`. Spawn budget per wave is `8 + 4w + 0.35w²` (cost: walker 1, runner 1.2, spitter/exploder 2, brute 5); zombie health scales by `1 + 0.1(w−1) + 0.006(w−1)²`, damage by `1 + 0.055(w−1)`, speed by up to +30%. New types appear at waves 2 (runners), 3 (spitters), 4 (exploders) and 6 (brutes); the boss arrives at wave 5 and every 5 waves after with +75% health each time.

| Wave | Zombies | Health × | Feel |
| --- | --- | --- | --- |
| 1 | 12 walkers | 1.0 | Gentle: learn to aim and kite |
| 4 | 23 (walkers, runners, spitters, exploders) | 1.35 | Every basic type in play |
| 5 | 17 + first boss | 1.5 | First real test; telegraphs teach dodging |
| 9 | 45 incl. first brutes | 2.2 | Upgrades and perks start to matter |
| 10 | 23 incl. 5 brutes + boss (+75% HP) | 2.4 | Challenging: needs a strong build and positioning |
| 11 | 61 mixed | 2.6 | Full night; sustained pressure |
| 20 | 67 incl. 11 brutes + boss (4th) | 5.1 | Very hard |
| 21 | 124, very short spawn gaps | 5.4 | Very hard: crowds, brutes and exploder chains |

Boss waves trade 40% of their regular horde for the boss.

This curve is covered by unit tests (monotonic threat, wave 10 ≥ 10× wave 1, wave 21 ≥ 3× wave 10). It was also playtested with an automated bot that has no build planning and only basic kiting (it buys a rifle, damage upgrades, health and armor): it took no damage through wave 5, beat the first boss, and died on wave 10 to the second boss. An earlier tuning in which the same bot died to the first boss on wave 5 led to the boss being toned down (1900 base HP, smaller summons, lighter charge).

## Testing

- `npm test` — 45 unit tests for the pure logic.
- `npm run test:e2e` — Playwright against the production build:
  - **screens**: menu, how-to-play, settings, gameplay, pause, game over (+ leaderboard save) with zero console errors/warnings; screenshots go to `tests/e2e/__screenshots__/`.
  - **waves**: a bot plays three waves using only simulated mouse/keyboard input and real UI clicks, asserting waves advance, zombies spawn and die, the perk and shop screens open and the score only rises.
  - **perf**: 140+ zombies on screen; asserts the simulation step and draw-call budgets.
  - **mobile**: Pixel 7 emulation; synthetic touch pointers drive both joysticks and the pause button.

Headless Chromium renders with SwiftShader (CPU), so the perf test measures CPU-side costs (simulation and render submission) rather than GPU frame time.
