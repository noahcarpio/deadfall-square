# Deadfall Square — Roblox (co-op)

A co-op port of the browser game for Roblox: 1–6 players hold the abandoned town square against waves of zombies, buy upgrades between waves, build barricades and turrets, and revive each other.

It is written in **Luau** and managed with **[Rojo](https://rojo.space)**, so the code lives in this repository and builds into a Roblox place file.

## Getting it into Roblox (no command line needed)

1. Install **Roblox Studio** (free, Windows or Mac) from https://create.roblox.com and sign in.
2. Download the place file: on GitHub open **Actions → Roblox → the latest successful run → Artifacts → `DeadfallSquare-place`**, and unzip it to get **`DeadfallSquare.rbxlx`**.
3. Double-click `DeadfallSquare.rbxlx` (or *File → Open from File* in Studio).
4. Press **Play** to try it alone. For co-op testing use **Test → Clients and Servers → 2 players → Start**.
5. **File → Publish to Roblox** → create a new experience and give it a name.
6. In **Game Settings → Security**, turn on **Enable Studio Access to API Services** (needed for the global leaderboard).
7. In the **Creator Dashboard** (https://create.roblox.com/dashboard/creations): fill in the **Maturity & Compliance questionnaire** (it has zombie violence; blood is drawn as green goo), add an icon and thumbnails, then make the experience **Public**.

### Developing with Rojo (optional)

If you want to edit the code and see changes live in Studio, install [Rokit](https://github.com/rojo-rbx/rokit), run `rokit install` in this folder (versions are pinned in `rokit.toml`), install the Rojo Studio plugin, then run `rojo serve` and click **Connect** in the plugin.

```bash
rojo build default.project.json -o DeadfallSquare.rbxlx   # build the place file
lune run tests/run                                      # unit tests
selene src                                              # lint
stylua src tests                                        # format
```

### Custom 3D models (optional, one-time import)

The game builds everything from plain Parts out of the box. `assets/` holds a set of matching low-poly meshes made for it: zombie body parts, the seven guns, pickups, the barricade and turret, and the arena props (cars, bus, crates, barrels, dumpsters, benches, barriers). `assets/preview.png` shows all of them. Importing them makes the game look more detailed. Nothing else changes, and if you skip this step nothing breaks.

1. Download the repository (**Code → Download ZIP** on GitHub) and unzip it. `DeadfallMeshes.obj`, `DeadfallMeshes.mtl` and `DeadfallPalette.png` must stay together in the same folder.
2. Open the place in Studio, then use **File → Import 3D** (also on the **Home** or **Avatar** tab) and choose `roblox/assets/DeadfallMeshes.obj`.
3. In the importer, leave **Merge meshes** (if you see it) turned **off**, so each object stays a separate MeshPart with its own name, then click **Import**. The palette texture is applied automatically.
4. In the Explorer, drag the imported model into **ReplicatedStorage** and rename it to exactly **`DeadfallMeshes`**. It doesn't matter where it lands in the world, how it's scaled, or whether its parts are nested in folders. The game looks each mesh up by name and sizes it itself.
5. Press **Play**. Any mesh that's present replaces its Part-built version; any that's missing (or renamed) falls back to Parts.
6. **Save/Publish** the place. The meshes are uploaded to your account along with it.

The meshes come from a script, `tools/make_meshes.py`. It uses only Python's standard library and needs no Blender. Change it, run `python3 tools/make_meshes.py` to regenerate the files and `Config/MeshSizes.luau`, then `python3 tools/preview_meshes.py` (needs NumPy and Pillow) to redraw the preview. After that, re-import the meshes. CI fails if the committed files don't match the script.

## Controls

| Action | PC | Controller | Mobile |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Left thumbstick |
| Aim | Mouse | Right stick | Drag on the right side |
| Shoot | Hold left click | RT (or push right stick fully) | Drag past 30% |
| Sprint | Shift | L3 / LT | RUN toggle |
| Dodge roll | Space | A | ROLL |
| Reload | R | X | RELOAD |
| Switch weapon | 1–7, wheel, Q / E | LB / RB | SWAP |
| Revive a teammate | Hold E next to them | Hold the prompt button | Tap and hold the prompt |
| Placement: rotate / cancel / pan | R or right-click / Esc / WASD | — / B / — | ROTATE / CANCEL / drag |

## What's in it

- **Arena:** the same town square as the browser version — buildings with lit windows and alleys, a low south fence, cars, a crashed bus, crates, fences, sandbags, barriers, dumpsters, barrels, trees, benches, a fountain and street lamps that switch on at night.
- **Zombies:** Walker, Runner, Brute (knock-back slam), Spitter (acid globs and puddles), Exploder (fuse and chain explosions), and the **Abomination** boss every 5 waves (telegraphed charge that stuns it on walls, shockwave slam you can roll through, runner summons, enrage at half health).
- **Weapons:** pistol (infinite ammo), shotgun, SMG, assault rifle, sniper (piercing), flamethrower (burning), grenade launcher, with per-weapon damage, fire-rate and magazine upgrades.
- **Co-op rules:** shared waves that scale with player count; personal coins, score, upgrades and perks; teammates can revive downed players; the run ends when everyone is down; the boss's coin reward is shared.
- **Between waves:** a 35-second intermission (or until everyone is ready) with the supply depot (weapons, ammo, medkit, Vitality/Kevlar/Running Shoes/Endurance, barricades, auto-turrets, repairs) and a choice of 3 perks every third wave.
- **Feel:** procedurally animated zombies with hit flash, knockback, topple-and-fade deaths, goo bursts and splats, explosions with light flashes, screen shake, floating damage numbers, combo multiplier, day-to-night cycle by wave with fog, lamps and per-player flashlights.
- **UI:** lobby with ready-up, how-to-play and the global top-10, HUD (health, armor, stamina, ammo, weapon slots, wave, zombies left, boss bar, score, coins, combo, perks, teammates, minimap, crosshair), shop, perk cards, game-over stats (waves survived, kills by type, accuracy, time, best combo, coins, damage, revives).

## Architecture

```
src/shared   (ReplicatedStorage.Shared)    config tables, RNG, economy, perks, arsenal, shop rules,
                                           wave composition, collision, nav grid, flow field,
                                           arena layout, network packing
src/server   (ServerScriptService.Server)  GameServer (state machine), ArenaBuilder, PlayerService,
                                           ZombieSim, Combat, WeaponService, Hazards, Pickups,
                                           Structures, WaveDirector, Leaderboard
src/client   (StarterPlayerScripts.Client) Camera, Input, Character, WeaponClient, ZombieView, Fx,
                                           Audio, UI (Hud, Shop, Screens, Placement)
tests/                                     Lune unit tests for the shared modules
tools/, assets/                            mesh generator + generated OBJ/MTL/palette and preview
```

- **Server-authoritative.** Health, ammo, coins, purchases, placement and every hit are decided on the server. Clients send trigger pulls with the pellet directions they predicted; the server checks ownership, fire rate and ammo, sanity-checks the spread and resolves hits itself.
- **Zombies have no Parts or physics on the server.** They are plain data moved by a multi-target **flow field** (one Dijkstra search toward every living player serves the whole horde), crowd separation through a spatial hash, and push-out against the same obstacle list the arena was built from. Clients get **15 Hz binary snapshots** (10 bytes per zombie, split into packets that fit Roblox's unreliable-remote limit), interpolate them and pose procedural rigs locally, moving every limb in a single `BulkMoveTo` call. This keeps 100+ zombies cheap in both bandwidth and server time.
- **One arena description.** `ArenaLayout` deterministically generates the visual parts, the gameplay colliders and invisible collision parts, so what players bump into, what bullets hit and what zombies path around always match.
- **Shared rules.** The shop prices, wave curves, arsenal logic and perk math are the same modules on server and client (and in the tests), so the UI never disagrees with what the server charges.

## Known limitations and choices

- **Sound is silent by default.** Roblox can't synthesise audio at runtime, and sound asset ids can't be verified outside Roblox, so every entry in `src/shared/Config/Sounds.luau` ships empty. To add audio, pick sounds in Studio's **Toolbox → Audio** (or the Creator Store), copy their ids and paste them in as `"rbxassetid://<id>"`.
- **Blood is green goo**, in line with Roblox's content rules for realistic gore.
- **No pause.** It's a multiplayer server; between waves the intermission gives breathing room instead.
- **Movement is client-side** (standard for Roblox characters). The server owns everything that affects scoring.
- **Not play-tested in Roblox by its author.** The code was written in an environment without Roblox Studio. CI verifies that it builds, lints, type-checks, is formatted and passes the unit tests, but in-engine behaviour (feel, UI layout on each device) needs a Studio play-test. Please report anything that looks off.
