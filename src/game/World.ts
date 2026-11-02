import * as THREE from 'three';
import type { AudioEngine } from '../audio/AudioEngine';
import { QUALITY_PRESETS, type QualityLevel } from '../config/quality';
import type { PlayerUpgradeId } from '../config/shop';
import { EventBus } from '../core/EventBus';
import { Rng } from '../core/Rng';
import { Effects } from '../fx/Effects';
import { Hazards } from '../fx/Hazards';
import { Player, type PlayerIntent } from '../player/Player';
import { PlayerModel } from '../player/PlayerModel';
import { computePlayerStats, type PlayerUpgradeTiers } from '../player/PlayerStats';
import { Economy } from '../progression/Economy';
import { PerkState } from '../progression/PerkState';
import { Pickups } from '../progression/Pickups';
import { Structures } from '../progression/Structures';
import { WaveDirector } from '../waves/WaveDirector';
import { Arsenal } from '../weapons/Arsenal';
import { WeaponSystem } from '../weapons/WeaponSystem';
import { Arena, WORLD_HALF } from '../world/Arena';
import type { CollisionWorld } from '../world/Collision';
import { FlowField } from '../world/FlowField';
import { Lighting } from '../world/Lighting';
import { NavGrid } from '../world/NavGrid';
import { ZombieManager, MAX_ZOMBIES } from '../zombies/ZombieManager';
import { ZombieRenderer } from '../zombies/ZombieRenderer';
import { Combat } from './Combat';
import type { GameEvents } from './events';
import { RunStats } from './RunStats';

/** Inflation radius for the nav grid (typical zombie body radius). */
const NAV_INFLATE = 0.45;

/**
 * The simulation: owns every gameplay system and advances them in a fixed
 * order each step. Rendering-only concerns (camera, HUD) live in Game.
 */
export class World {
  readonly scene = new THREE.Scene();
  readonly rng = new Rng();
  readonly events = new EventBus<GameEvents>();
  readonly arena: Arena;
  readonly collision: CollisionWorld;
  readonly nav: NavGrid;
  readonly flow: FlowField;
  readonly lighting: Lighting;
  readonly player: Player;
  readonly playerModel = new PlayerModel();
  readonly arsenal = new Arsenal();
  readonly perks = new PerkState();
  readonly economy = new Economy();
  readonly zombies = new ZombieManager();
  readonly zombieRenderer = new ZombieRenderer(MAX_ZOMBIES);
  readonly weapons: WeaponSystem;
  readonly hazards = new Hazards();
  readonly fx: Effects;
  readonly pickups = new Pickups();
  readonly structures = new Structures();
  readonly waves = new WaveDirector();
  readonly combat: Combat;
  readonly stats = new RunStats();
  upgrades: PlayerUpgradeTiers = { maxHealth: 0, speed: 0, armor: 0, stamina: 0 };

  /** Point zombies chase: the player in-game, a wandering decoy on the menu. */
  targetX = 0;
  targetZ = 0;
  targetIsPlayer = true;
  time = 0;
  private flowTimer = 0;
  private flowCell = -1;
  private flowDirty = true;
  private groanTimer = 2;
  private footstepTimer = 0;
  private readonly reachScratch: Uint8Array;
  private readonly queueScratch: Int32Array;

  constructor(readonly audio: AudioEngine, overlay: HTMLElement, quality: QualityLevel) {
    const q = QUALITY_PRESETS[quality];
    this.arena = new Arena({ textureSize: q.groundTextureSize });
    this.collision = this.arena.collision;
    this.nav = new NavGrid({ minX: -WORLD_HALF, minZ: -WORLD_HALF, maxX: WORLD_HALF, maxZ: WORLD_HALF }, 1);
    this.flow = new FlowField(this.nav);
    this.reachScratch = new Uint8Array(this.nav.size);
    this.queueScratch = new Int32Array(this.nav.size);
    this.lighting = new Lighting(this.scene);
    this.player = new Player(computePlayerStats(this.upgrades, this.perks));
    this.fx = new Effects(this.scene, overlay);
    this.weapons = new WeaponSystem(this.scene);
    this.combat = new Combat(this);

    this.scene.add(
      this.arena.group,
      this.playerModel.root,
      this.zombieRenderer.group,
      this.hazards.group,
      this.pickups.group,
      this.structures.group,
    );
    this.rebuildNav();
    this.applyQuality(quality);
  }

  applyQuality(level: QualityLevel): void {
    const q = QUALITY_PRESETS[level];
    this.lighting.applyQuality(q);
    this.fx.applyQuality(q);
    this.zombieRenderer.setShadows(q.shadows && q.zombieShadows);
    this.waves.aliveCap = level === 'low' ? 90 : 140;
  }

  /** Recomputes player stats after upgrades/perks change. */
  refreshStats(): void {
    this.player.applyStats(computePlayerStats(this.upgrades, this.perks));
    this.economy.coinMultiplier = 1 + 0.25 * this.perks.level('greed');
  }

  upgrade(id: PlayerUpgradeId): void {
    this.upgrades[id]++;
    this.refreshStats();
    if (id === 'armor') this.player.armor = this.player.stats.maxArmor;
  }

  /** Starts a fresh run. */
  reset(seed?: number): void {
    if (seed !== undefined) this.rng.reseed(seed);
    this.zombies.clear();
    this.fx.clear();
    this.hazards.clear();
    this.pickups.clear();
    this.weapons.clear(this);
    this.structures.clear(this);
    this.waves.reset();
    this.perks.reset();
    this.economy.reset(0);
    this.stats.reset();
    this.combat.reset();
    this.arsenal.reset();
    this.upgrades = { maxHealth: 0, speed: 0, armor: 0, stamina: 0 };
    this.player.reset(computePlayerStats(this.upgrades, this.perks));
    this.playerModel.setWeapon('pistol');
    this.lighting.reset();
    this.time = 0;
    this.targetIsPlayer = true;
    this.flowDirty = true;
    this.setNight(0);
  }

  setNight(n: number): void {
    this.lighting.setNight(n);
    this.arena.setNight(n);
  }

  /** Re-rasterises obstacles into the nav grid (after building/destroying structures). */
  rebuildNav(): void {
    this.nav.rebuild(this.collision.colliders, NAV_INFLATE, (c) => this.structures.isStructureCollider(c));
    this.flowDirty = true;
  }

  /**
   * Checks that blocking the given rectangle would still leave the player
   * connected to at least one spawn point (so zombies can always reach them,
   * possibly by breaking structures — and the player can never be sealed in).
   */
  wouldKeepPathOpen(minX: number, minZ: number, maxX: number, maxZ: number): boolean {
    const g = this.nav;
    const blocked = this.reachScratch;
    blocked.fill(0);
    for (let i = 0; i < g.size; i++) if (g.cells[i] !== 0) blocked[i] = 1;
    const c0 = Math.max(0, g.col(minX - NAV_INFLATE));
    const c1 = Math.min(g.cols - 1, g.col(maxX + NAV_INFLATE));
    const r0 = Math.max(0, g.row(minZ - NAV_INFLATE));
    const r1 = Math.min(g.rows - 1, g.row(maxZ + NAV_INFLATE));
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) blocked[r * g.cols + c] = 1;
    const start = g.indexAt(this.player.x, this.player.z);
    if (blocked[start]) blocked[start] = 0;
    // Flood fill from the player through free cells.
    const queue = this.queueScratch;
    let head = 0;
    let tail = 0;
    queue[tail++] = start;
    blocked[start] = 2;
    while (head < tail) {
      const i = queue[head++] as number;
      const c = i % g.cols;
      const r = (i - c) / g.cols;
      for (let k = 0; k < 4; k++) {
        const n = k === 0 ? (c > 0 ? i - 1 : -1)
          : k === 1 ? (c < g.cols - 1 ? i + 1 : -1)
            : k === 2 ? (r > 0 ? i - g.cols : -1)
              : (r < g.rows - 1 ? i + g.cols : -1);
        if (n < 0 || blocked[n] !== 0) continue;
        blocked[n] = 2;
        queue[tail++] = n;
      }
    }
    return this.arena.spawnPoints.some((s) => blocked[g.indexAt(s.x, s.z)] === 2);
  }

  private updateFlow(dt: number): void {
    this.flowTimer -= dt;
    const cell = this.nav.indexAt(this.targetX, this.targetZ);
    if ((cell !== this.flowCell || this.flowDirty) && this.flowTimer <= 0) {
      // If the target stands in an inflated (blocked) cell, still seed the search there.
      this.flow.compute(this.targetX, this.targetZ);
      this.flowCell = cell;
      this.flowDirty = false;
      this.flowTimer = 0.15;
    }
  }

  /** One fixed simulation step of gameplay. */
  update(dt: number, intent: PlayerIntent): void {
    this.time += dt;
    this.stats.timePlayed += this.player.alive ? dt : 0;
    const p = this.player;
    this.targetIsPlayer = true;
    this.targetX = p.x;
    this.targetZ = p.z;
    this.updateFlow(dt);

    // Weapon switching / reload intents.
    if (p.alive) {
      if (intent.slot > 0) {
        const id = this.arsenal.list().find((w) => w.def.slot === intent.slot)?.def.id;
        if (id && this.arsenal.switchTo(id)) this.onWeaponSwitched();
      }
      if (intent.cycle !== 0 && this.arsenal.cycle(intent.cycle)) this.onWeaponSwitched();
      if (intent.reload && this.arsenal.startReload(p.stats.reloadSpeed)) this.audio.sfx('reload');
    }

    const res = p.update(dt, intent, this.collision);
    if (res.rolled) {
      this.audio.sfx('roll');
      this.fx.dust(p.x, p.z, 6, 0.2);
    }
    if (p.alive && p.speed01 > 0.2 && !p.rolling) {
      this.footstepTimer -= dt * (0.6 + p.speed01 * 1.4);
      if (this.footstepTimer <= 0) {
        this.footstepTimer = 0.32;
        this.audio.sfx('footstep', { volume: 0.5 });
      }
    }

    this.weapons.update(dt, this, intent.fire && p.alive);
    this.zombies.update(dt, this);
    this.combat.processExplosions();
    this.structures.update(dt, this);
    this.hazards.update(dt, this);
    this.pickups.vacuum = this.waves.phase === 'cleared';
    this.pickups.update(dt, this);
    this.waves.update(dt, this);
    this.combat.processExplosions();
    this.economy.update(dt);
    this.combat.update(dt);
    this.updateCommon(dt);
    this.ambientGroans(dt);
    this.audio.setListener(p.x, p.z);
  }

  /** Attract-mode simulation for the main menu: zombies shamble after a wandering decoy. */
  updateMenu(dt: number): void {
    this.time += dt;
    this.targetIsPlayer = false;
    const t = this.time * 0.12;
    this.targetX = Math.sin(t) * 10;
    this.targetZ = Math.cos(t * 1.3) * 8;
    this.updateFlow(dt);
    if (this.zombies.aliveCount < 18 && this.rng.chance(dt * 2)) {
      const sp = this.rng.pick(this.arena.spawnPoints);
      const type = this.rng.weighted({ walker: 6, runner: 1, brute: 0.5, spitter: 1, exploder: 0.8 });
      this.zombies.spawn(type, sp.x, sp.z, { hp: 1, damage: 1, speed: 0.6 }, () => this.rng.next());
    }
    this.zombies.update(dt, this);
    this.updateCommon(dt);
  }

  private updateCommon(dt: number): void {
    this.fx.update(dt);
    this.lighting.update(dt);
  }

  private ambientGroans(dt: number): void {
    this.groanTimer -= dt;
    if (this.groanTimer > 0) return;
    const alive = this.zombies.aliveCount;
    this.groanTimer = alive > 0 ? Math.max(0.6, 3.5 - alive * 0.05) * (0.6 + this.rng.next() * 0.8) : 2;
    if (alive === 0) return;
    const list = this.zombies.list;
    const z = list[this.rng.int(0, list.length - 1)];
    if (z && z.alive) this.audio.sfx('groan', { x: z.x, z: z.z, pitch: z.def.scale > 1.4 ? 0.7 : 1 });
  }

  private onWeaponSwitched(): void {
    this.playerModel.setWeapon(this.arsenal.currentId);
    this.audio.sfx('weaponSwap');
  }

  /** Syncs visual-only state before rendering. */
  syncVisuals(frameDt: number): void {
    const p = this.player;
    const reload = this.arsenal.reloading ? this.arsenal.reloadProgress : 0;
    this.playerModel.update({
      x: p.x, z: p.z, facing: p.facing, speed01: p.speed01, moveDot: p.moveDot,
      rollT: p.rollProgress, rolling: p.rolling, recoil: this.weapons.recoil, hurt: p.hurtFlash,
      reload, dt: frameDt, alive: p.alive, deathT: p.deathTime,
    });
    if (this.playerModel.currentWeapon !== this.arsenal.currentId) this.playerModel.setWeapon(this.arsenal.currentId);
    this.zombieRenderer.update(this.zombies.list, frameDt);
    this.fx.sync();
    this.hazards.sync();
    this.pickups.sync();
    this.structures.sync(this.time);
    this.lighting.follow(p.x, p.z);
    this.lighting.aimFlashlight(p.x + p.aimX * 0.4, 1.6, p.z + p.aimZ * 0.4, p.aimX, p.aimZ);
  }
}
