# Deadfall Square — Roblox (co-op)

A co-op survival game for Roblox, grown from the browser game: 1–6 players hold the abandoned town square against waves of zombies. Between waves there's a 30-second grace period. Players walk to the merchant to spend coins and to the workbench to craft and upgrade with scavenged materials, and they build barricades and turrets. Zombies hunt by sight and sound, so sneaking, crouching and choosing when to shoot matter. Players can revive each other.

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

The game builds everything from plain Parts out of the box. `assets/` holds a set of matching placeholder meshes made for it: zombie body parts, the seven guns, pickups, the barricade and turret, and the arena props (cars, bus, crates, barrels, dumpsters, benches, barriers). `assets/preview.png` shows all of them. Importing them makes the game look more detailed. Nothing else changes, and if you skip this step nothing breaks.

1. Download the repository (**Code → Download ZIP** on GitHub) and unzip it. `DeadfallMeshes.obj`, `DeadfallMeshes.mtl` and `DeadfallPalette.png` must stay together in the same folder.
2. Open the place in Studio, then use **File → Import 3D** (also on the **Home** or **Avatar** tab) and choose `roblox/assets/DeadfallMeshes.obj`.
3. In the importer, leave **Merge meshes** (if you see it) turned **off**, so each object stays a separate MeshPart with its own name, then click **Import**. The palette texture is applied automatically.
4. In the Explorer, drag the imported model into **ReplicatedStorage** and rename it to exactly **`DeadfallMeshes`**. It doesn't matter where it lands in the world, how it's scaled, or whether its parts are nested in folders. The game looks each mesh up by name and sizes it itself.
5. Press **Play**. Any mesh that's present replaces its Part-built version; any that's missing (or renamed) falls back to Parts.
6. **Save/Publish** the place. The meshes are uploaded to your account along with it.

The meshes come from a script, `tools/make_meshes.py`. It uses only Python's standard library and needs no Blender. Change it, run `python3 tools/make_meshes.py` to regenerate the files and `Config/MeshSizes.luau`, then `python3 tools/preview_meshes.py` (needs NumPy and Pillow) to redraw the preview. After that, re-import the meshes. CI fails if the committed files don't match the script.

## Art style and using AI for models

**Status:** everything you see is a **draft / placeholder**: block-built parts and simple generated meshes, so the game is playable while the real art is made.

**Target look: gritty realistic.**
- Realistic proportions and real-world scale.
- Worn, dirty, rusted and blood-stained surfaces with proper PBR textures (colour, normal, roughness and metalness maps).
- A muted, desaturated palette. Overcast days, harsh contrast at night under street lamps and flashlights. Fog and grime rather than bright colours.
- Everything still has to read from the high top-down camera: clear silhouettes, and no detail that only shows up close.

**Where the look lives in code:** `src/shared/Config/Visuals.luau`.
- **Colour grading:** gritty and desaturated by day, cold blue at night, plus bloom and sun rays, all blended with the day-night cycle.
- **Placeholder materials:** `CLEAN_MATERIALS` swaps Roblox's built-in textured materials for smooth ones so the draft art isn't grainy from above. Turn it off, or replace the materials with `MaterialVariant`s, once real textures exist.

**Getting good models out of AI 3D tools** (Roblox Studio's built-in 3D generation, Meshy, Tripo, Rodin, ...):

1. **Use one style prompt for every model,** e.g. *"realistic game-ready 3D asset, post-apocalyptic, worn and dirty, chipped paint, rust and grime, realistic proportions, PBR textures, no baked lighting, neutral studio light, plain background"*, then add the object (e.g. *"abandoned 1990s sedan with a smashed windshield"*).
2. **Go image → 3D, not text → 3D.** Generate a reference image in that style first and feed it to the image-to-3D tool. It is far more consistent.
3. **Ask for game-ready output:**
   - about 10k triangles per prop (less for small items);
   - PBR maps at 1–2k (colour, normal, roughness, metalness);
   - FBX, real-world scale, centred.
4. **Clean up in Blender** (free):
   - Delete floating junk and fix the scale.
   - Check the normals, and bake if the tool gave you a messy mesh.
   - Export FBX.
5. **Import with Studio's Import 3D:**
   - Put the PBR maps on the mesh as a `SurfaceAppearance`.
   - For large surfaces (roads, walls), make `MaterialVariant`s instead.
   - Name each model like the placeholder it replaces (e.g. `Car_1`, `Gun_rifle`) and put it in `ReplicatedStorage.DeadfallMeshes`. `MeshLibrary` then uses it automatically, at the size in `Config/MeshSizes.luau`.
6. **Make one model first and check it in game** from the real camera, in daylight and at night, before doing a whole set.

## Controls

| Action | PC | Controller | Mobile |
| --- | --- | --- | --- |
| Move | WASD | Left stick | Left thumbstick |
| Aim | Mouse | Right stick | Drag on the right side |
| Shoot | Hold left click | RT (or push right stick fully) | Drag past 30% |
| Sprint | Shift | L3 / LT | RUN toggle |
| Dodge roll | Space | A | ROLL |
| Reload | R | X | RELOAD |
| Switch weapon | 1–7, wheel, Q / E | LB (tap) | SWAP |
| Melee swing (3-hit combo) | Right click | RB | SLASH |
| Gadgets 1 / 2 / 3 | Z / X / V | Hold LB + X / Y / B | G1 / G2 / G3 |
| Crouch (quiet, harder to see) | C / Ctrl | B | SNEAK toggle |
| Use: search, trade, craft, ring bell, revive | F (hold to search / revive) | Y | Tap (and hold) the prompt |
| Bandage / pipe bomb | B / G (thrown at the cursor) | D-pad up / down | HEAL / BOMB |
| Inventory (guns, gear, items: equip, use, drop, sell) | I | D-pad right | BAG |
| Leave the merchant / workbench | Esc or LEAVE | B | LEAVE |
| Placement: rotate / cancel / pan | R or right-click / Esc / WASD | — / B / — | ROTATE / CANCEL / drag |

## What's in it

- **Tower climb (25 floors):** each wave is a floor with an objective and maybe a modifier (`Config/Floors.luau`, rolled per run by `FloorPlan.luau`).
  - **Objectives:** *clear* every zombie; *hold out* until a timer runs out; *defend the bell* (it has health, zombies go for it, and if it breaks the floor gives no reward); *elite hunt* (a glowing elite leads an endless horde until it dies).
  - **Bosses:** every 5th floor is a boss floor, and floor 25 is the final boss. Clearing it wins the run.
  - **Modifiers:** *Thick Fog*, *Blood Moon* (faster zombies, more coins), *Swarm*, *Armored* and *Calm*.
- **Rewards:** after every floor each player picks 1 of 3 cards (`RewardRules.luau`): a piece of gear, a perk, coins, a supply crate or a full patch-up. Boss floors guarantee rare-or-better gear.
- **Gear with rarity** (`Gear.luau`):
  - **Rarities and power:** Common, Rare (1 trait) and Unique (2 traits). Power grows with the floor the gear was found on.
  - **Kinds:** guns (gear attunes to that gun), melee (Machete, Fire Axe, Sledgehammer), armor (Leather Jacket, Riot Vest, Hazmat Suit) and three gadget slots.
  - **Traits:** Serrated (bleed), Hollow-Point (crits), Rapid, Heavy, Leeching, Volatile, Chilling, Padded, Light, Lucky, Scavenger, Quick Recharge, Amplified.
  - **Where it comes from:** elites, bosses and the odd zombie drop gear with a coloured beam, and the merchant sells common pieces.
  - **Using it:** equip from the bag (I → GEAR). The stash holds 10. At the workbench, salvage gear into materials, reinforce it (+power) or re-roll a trait.
- **Melee and gadgets:**
  - **Melee:** right click / RB swings the equipped melee weapon in a 3-hit combo whose last hit is a heavy, staggering finisher. It is almost silent, so it pairs well with sneaking.
  - **Gadgets** on Z / X / V (cooldowns on the HUD): Charge Strike (dash and smash), Med Burst (heal the team nearby), Shock Beacon (stun), Scrap Drone (15 s turret), Flare (lure and burn) and Adrenal Shot (+30% speed and fire rate).
  - **Starting kit:** a Machete and Charge Strike.

- **Arena:** the same town square as the browser version — buildings with lit windows and alleys, a low south fence, cars, a crashed bus, crates, fences, sandbags, barriers, dumpsters, barrels, trees, benches, a fountain and street lamps that switch on at night.
- **Zombies:** Walker, Runner, Brute (knock-back slam), Spitter (acid globs and puddles), Exploder (fuse and chain explosions), and the **Abomination** boss every 5 floors (telegraphed charge that stuns it on walls, shockwave slam you can roll through, runner summons, enrage at half health).
- **Weapons:** pistol (infinite ammo), shotgun, SMG, assault rifle, sniper (piercing), flamethrower (burning), grenade launcher, with per-weapon damage, fire-rate and magazine upgrades.
- **Co-op rules:** shared waves that scale with player count; personal coins, score, upgrades and perks; teammates can revive downed players; the run ends when everyone is down; the boss's coin reward is shared.
- **Stealth and noise:** zombies wander, investigate what they hear and only hunt once they see you, get hurt or bump into you. Each gun has its own noise radius (a sniper shot carries 40 m, a flamethrower 10 m). Sprinting is loud, walking is quiet, and crouching is almost silent and roughly halves how far away zombies can see you. Sight is shorter at night. A HIDDEN / SPOTTED eye on the HUD tells you when you've been seen. New arrivals head into the plaza, and zombies that hear nothing for a while drift toward the survivors, so waves still end. Tuning lives in `Config/Stealth.luau`.
- **Scavenging:** cars, the bus, crate stacks, dumpsters and trash piles hold scrap, planks, rags, electronics, gunpowder, ammo, coins and bandages. Hold F to search. Loot is shared, and whatever doesn't fit stays for a teammate. Containers refill at the start of a run and some refill at every grace period. Searching makes a little noise. The bag has a weight limit (10 kg, +5 per Bigger Backpack).
- **Inventory (I):** a full-screen inventory you can open anywhere, with three tabs.
  - **Guns:** stats, ammo, upgrades and gear traits. Hold, drop or sell each gun.
  - **Gear:** what's equipped plus the stash. Equip, drop or sell pieces.
  - **Items:** use, drop or sell one or all.
  - **Dropping** leaves the thing on the ground for anyone to pick up. The dropper can't grab it back for 3 s.
  - **Selling** only works while you stand at the **merchant**, who trades for the whole climb, mid-floor too. It pays about 40% of the price, scaled by rarity, power and upgrades. The pistol can't be sold or dropped.
- **Grace period (30 s, after the reward pick):** no menus pop up. Walk to the **merchant** (open all climb; buys with coins: weapons, ammo refills, medkit, Vitality/Kevlar/Running Shoes/Endurance/Bigger Backpack, supplies) or the **workbench** (materials: bandages, pipe bombs, hand-loaded ammo, barricades, auto-turrets, repairs, and weapon upgrades for coins plus scrap and electronics). Ring the **alarm bell** to start the next floor early once everyone is ready.
- **Items:** bandages heal 35. Pipe bombs are thrown at the cursor, beep for 4 seconds to lure every zombie in earshot, then explode.
- **Character animation:** Roblox's default walk/run/idle animations, plus procedural poses everyone sees: gun raised to aim (lowered while sprinting), recoil on each shot, a reload motion, crouch-walking, melee swings (forehand, backhand, overhead finisher), a tumble on the dodge roll, and lying down while downed. R15 avatars get the full set; R6 gets the arm poses, roll and downed pose.
- **Feel:** procedurally animated zombies with hit flash, knockback, topple-and-fade deaths, goo bursts and splats, explosions with light flashes, screen shake, floating damage numbers, combo multiplier, day-to-night cycle by wave with fog, lamps and per-player flashlights.
- **UI:** lobby with ready-up, how-to-play and the global top-10, HUD (health, armor, stamina, bag and materials, hidden/spotted, ammo, weapon slots, wave, zombies left, boss bar, score, coins, combo, perks, teammates, minimap, crosshair), floor objective and progress, gadget cooldowns, merchant and workbench panels, bag and gear panel, reward cards, victory / game-over stats (floors cleared, kills by type, accuracy, time, best combo, coins, damage, revives).

## Architecture

```
src/shared   (ReplicatedStorage.Shared)    config tables, RNG, economy, perks, arsenal, shop rules,
                                           inventory, loot tables, wave composition, collision,
                                           nav grid, flow field, arena layout, network packing
src/server   (ServerScriptService.Server)  GameServer (state machine), ArenaBuilder, PlayerService,
                                           ZombieSim, Combat, WeaponService, Hazards, Pickups,
                                           Structures, Stations, LootService, Throwables,
                                           WaveDirector, Leaderboard
src/client   (StarterPlayerScripts.Client) Camera, Input, Character, CharacterAnimator,
                                           WeaponClient, ZombieView, Fx, Audio,
                                           UI (Hud, StationUI, InventoryUI, Screens, Placement)
tests/                                     Lune unit tests for the shared modules
tools/, assets/                            mesh generator + generated OBJ/MTL/palette and preview
```

- **Server-authoritative.** Health, ammo, coins, purchases, placement and every hit are decided on the server. Clients send trigger pulls with the pellet directions they predicted; the server checks ownership, fire rate and ammo, sanity-checks the spread and resolves hits itself.
- **Zombies have no Parts or physics on the server.** They are plain data moved by multi-target **flow fields**: one Dijkstra search toward every living player serves the whole hunting horde, and a second one toward recent noises serves the zombies investigating. Crowd separation runs through a spatial hash, with push-out against the same obstacle list the arena was built from. Clients get **15 Hz binary snapshots** (10 bytes per zombie, split into packets that fit Roblox's unreliable-remote limit), interpolate them and pose procedural rigs locally, moving every limb in a single `BulkMoveTo` call. This keeps 100+ zombies cheap in both bandwidth and server time.
- **One arena description.** `ArenaLayout` deterministically generates the visual parts, the gameplay colliders and invisible collision parts, so what players bump into, what bullets hit and what zombies path around always match.
- **Shared rules.** The shop prices, wave curves, arsenal logic and perk math are the same modules on server and client (and in the tests), so the UI never disagrees with what the server charges.

## Known limitations and choices

- **Sound is silent by default.** Roblox can't synthesise audio at runtime, and sound asset ids can't be verified outside Roblox, so every entry in `src/shared/Config/Sounds.luau` ships empty. To add audio, pick sounds in Studio's **Toolbox → Audio** (or the Creator Store), copy their ids and paste them in as `"rbxassetid://<id>"`.
- **Blood is green goo**, in line with Roblox's content rules for realistic gore.
- **No pause.** It's a multiplayer server; between waves the grace period gives breathing room instead.
- **Procedural, not keyframed, player animation.** Animation assets have to be uploaded to a Roblox account, so the aim, recoil, reload, crouch and roll poses are generated in code (`CharacterAnimator.luau`). You can swap in your own animations made in Studio's Animation Editor later. If the aim, recoil or reload poses don't appear, look for the `[CharacterAnimator]` line in Studio's Output window (it lists the joints it found) and report it.
- **Movement is client-side** (standard for Roblox characters). The server owns everything that affects scoring.
- **Not play-tested in Roblox by its author.** The code was written in an environment without Roblox Studio. CI verifies that it builds, lints, type-checks, is formatted and passes the unit tests, but in-engine behaviour (feel, UI layout on each device) needs a Studio play-test. Please report anything that looks off.
