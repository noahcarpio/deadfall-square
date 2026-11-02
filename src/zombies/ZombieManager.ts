import { angleDamp, damp, rayCircle } from '../core/math';
import { SpatialHash } from '../core/SpatialHash';
import type { ZombieType } from '../config/zombies';
import { WORLD_HALF } from '../world/Arena';
import type { World } from '../game/World';
import { Zombie, type WaveScaling } from './Zombie';
import { updateZombieAI } from './ZombieAI';

export const MAX_ZOMBIES = 420;

/** Duration of the topple before the body dissolves. */
const TOPPLE_TIME = 0.45;
const DISSOLVE_TIME = 1.1;
const SPAWN_TIME = 0.7;
/** Seconds without progress before a zombie is relocated to a spawn alley. */
const STUCK_LIMIT = 8;

export interface ZombieHit {
  zombie: Zombie;
  t: number;
}

/**
 * Owns the zombie pool, the per-step spatial hash, and shared movement:
 * steering integration, crowd separation, knockback and obstacle collision.
 * Type-specific decisions are delegated to ZombieAI.
 */
export class ZombieManager {
  readonly pool: Zombie[] = [];
  /** Zombies currently in the world (alive or dying). */
  readonly list: Zombie[] = [];
  readonly hash = new SpatialHash(-WORLD_HALF, -WORLD_HALF, WORLD_HALF, WORLD_HALF, 2, MAX_ZOMBIES);
  private readonly free: Zombie[] = [];
  private readonly neighbourIds: number[] = [];
  private readonly hits: ZombieHit[] = [];
  private readonly removals: Zombie[] = [];
  /** Number of alive (not dying) zombies. */
  aliveCount = 0;

  constructor() {
    for (let i = 0; i < MAX_ZOMBIES; i++) {
      const z = new Zombie(i);
      this.pool.push(z);
    }
    for (let i = MAX_ZOMBIES - 1; i >= 0; i--) this.free.push(this.pool[i] as Zombie);
  }

  clear(): void {
    for (const z of this.list) {
      z.active = false;
      this.free.push(z);
    }
    this.list.length = 0;
    this.aliveCount = 0;
  }

  get capacityLeft(): number {
    return this.free.length;
  }

  spawn(type: ZombieType, x: number, z: number, scaling: WaveScaling, rand: () => number): Zombie | null {
    const zombie = this.free.pop();
    if (!zombie) return null;
    zombie.init(type, x, z, scaling, rand);
    zombie.listIndex = this.list.length;
    this.list.push(zombie);
    this.aliveCount++;
    return zombie;
  }

  /** Marks a zombie as dying (called by Combat). */
  markDying(z: Zombie, dirX: number, dirZ: number): void {
    if (z.state === 'dying') return;
    z.setState('dying');
    z.deathT = 0;
    const len = Math.hypot(dirX, dirZ) || 1;
    z.deathDirX = dirX / len;
    z.deathDirZ = dirZ / len;
    z.burnTime = 0;
    this.aliveCount--;
  }

  private remove(z: Zombie): void {
    const i = z.listIndex;
    const last = this.list.pop() as Zombie;
    if (last !== z) {
      this.list[i] = last;
      last.listIndex = i;
    }
    z.active = false;
    z.listIndex = -1;
    this.free.push(z);
  }

  /**
   * Safety net so a wave can always finish: a chasing zombie that makes no
   * progress for STUCK_LIMIT seconds (wedged by knockback, crowds or player
   * structures), or ends up with invalid coordinates, re-emerges from the
   * nearest spawn alley.
   */
  private watchdog(z: Zombie, dt: number, world: World): void {
    if (!Number.isFinite(z.x) || !Number.isFinite(z.z)) {
      this.relocate(z, world);
      return;
    }
    z.checkTimer -= dt;
    if (z.checkTimer > 0) return;
    z.checkTimer = 2;
    const moved = Math.hypot(z.x - z.checkX, z.z - z.checkZ);
    const farFromTarget = Math.hypot(world.targetX - z.x, world.targetZ - z.z) > z.radius + 3;
    const idleState = z.state === 'chase' || z.state === 'spawning';
    z.stuckTime = idleState && farFromTarget && moved < 0.4 && !z.blockedBy ? z.stuckTime + 2 : 0;
    z.checkX = z.x;
    z.checkZ = z.z;
    if (z.stuckTime >= STUCK_LIMIT) this.relocate(z, world);
  }

  private relocate(z: Zombie, world: World): void {
    let best = world.arena.spawnPoints[0];
    let bestD = Infinity;
    for (const sp of world.arena.spawnPoints) {
      const d = Number.isFinite(z.x) ? (sp.x - z.x) ** 2 + (sp.z - z.z) ** 2 : 0;
      if (d < bestD) {
        bestD = d;
        best = sp;
      }
    }
    if (!best) return;
    z.x = best.x;
    z.z = best.z;
    z.vx = z.vz = z.kx = z.kz = 0;
    z.checkX = z.x;
    z.checkZ = z.z;
    z.stuckTime = 0;
    z.setState('spawning');
  }

  /** Alive zombies within `radius` of a point (spatial hash; valid after update()). */
  queryRadius(x: number, z: number, radius: number, out: Zombie[]): number {
    // Hash stores centre points; widen the search by the largest body radius.
    const n = this.hash.query(x, z, radius + 1.4, this.neighbourIds);
    let count = 0;
    for (let i = 0; i < n; i++) {
      const zombie = this.list[this.neighbourIds[i] as number];
      if (!zombie || !zombie.alive) continue;
      const dx = zombie.x - x;
      const dz = zombie.z - z;
      const rr = radius + zombie.radius;
      if (dx * dx + dz * dz <= rr * rr) out[count++] = zombie;
    }
    return count;
  }

  /**
   * All alive zombies hit by a ray, sorted by distance. The returned array is
   * reused between calls.
   */
  raycast(ox: number, oz: number, dx: number, dz: number, maxDist: number): ZombieHit[] {
    const hits = this.hits;
    let n = 0;
    for (let i = 0; i < this.list.length; i++) {
      const z = this.list[i] as Zombie;
      if (!z.alive || z.state === 'spawning' && z.stateTime < 0.25) continue;
      // Cheap reject: projection onto the ray.
      const px = z.x - ox;
      const pz = z.z - oz;
      const proj = px * dx + pz * dz;
      if (proj < -z.radius || proj > maxDist + z.radius) continue;
      const t = rayCircle(ox, oz, dx, dz, z.x, z.z, z.radius + 0.08);
      if (t < 0 || t > maxDist) continue;
      let h = hits[n];
      if (!h) {
        h = { zombie: z, t };
        hits[n] = h;
      } else {
        h.zombie = z;
        h.t = t;
      }
      n++;
    }
    hits.length = n;
    hits.sort((a, b) => a.t - b.t);
    return hits;
  }

  nearestAlive(x: number, z: number, maxDist: number): Zombie | null {
    let best: Zombie | null = null;
    let bestD = maxDist * maxDist;
    for (const zombie of this.list) {
      if (!zombie.alive) continue;
      const d = (zombie.x - x) ** 2 + (zombie.z - z) ** 2;
      if (d < bestD) {
        bestD = d;
        best = zombie;
      }
    }
    return best;
  }

  update(dt: number, world: World): void {
    // Rebuild the spatial hash from current positions.
    this.hash.clear();
    for (let i = 0; i < this.list.length; i++) {
      const z = this.list[i] as Zombie;
      if (z.alive) this.hash.insert(i, z.x, z.z);
    }

    const ids = this.neighbourIds;
    for (let i = this.list.length - 1; i >= 0; i--) {
      const z = this.list[i] as Zombie;
      z.stateTime += dt;
      z.flash = Math.max(0, z.flash - dt * 7);

      if (z.state === 'dying') {
        z.deathT += dt;
        z.kx = damp(z.kx, 0, 5, dt);
        z.kz = damp(z.kz, 0, 5, dt);
        z.x += z.kx * dt;
        z.z += z.kz * dt;
        z.dissolve = Math.min(1, Math.max(0, (z.deathT - TOPPLE_TIME) / DISSOLVE_TIME));
        if (z.deathT >= TOPPLE_TIME + DISSOLVE_TIME) this.removals.push(z);
        continue;
      }

      if (z.state === 'spawning') {
        z.dissolve = Math.max(0, 1 - z.stateTime / SPAWN_TIME);
        if (z.stateTime >= SPAWN_TIME) z.setState('chase');
      }

      // Burning damage over time (applied through combat for kills/feedback).
      if (z.burnTime > 0) {
        z.burnTime -= dt;
        world.combat.applyBurn(z, dt);
        if (!z.alive) continue;
      }
      z.flameCooldown = Math.max(0, z.flameCooldown - dt);
      z.attackCooldown -= dt;
      z.rangedCooldown -= dt;

      // Type-specific decisions produce a desired velocity.
      const desired = updateZombieAI(z, dt, world);
      if (!z.alive) continue;

      // Crowd separation.
      let sepX = 0;
      let sepZ = 0;
      const n = this.hash.query(z.x, z.z, z.radius + 1.4, ids);
      for (let k = 0; k < n; k++) {
        const other = this.list[ids[k] as number] as Zombie;
        if (other === z || !other.alive) continue;
        const dx = z.x - other.x;
        const dz = z.z - other.z;
        const minD = z.radius + other.radius;
        const d2 = dx * dx + dz * dz;
        if (d2 >= minD * minD || d2 < 1e-8) continue;
        const d = Math.sqrt(d2);
        const overlap = (minD - d) / minD;
        // Heavier zombies shove lighter ones aside.
        const massRatio = other.def.mass / (z.def.mass + other.def.mass);
        sepX += (dx / d) * overlap * 6 * massRatio * 2;
        sepZ += (dz / d) * overlap * 6 * massRatio * 2;
      }

      const accel = z.state === 'charging' ? 30 : 9;
      z.vx = damp(z.vx, desired.x, accel, dt);
      z.vz = damp(z.vz, desired.z, accel, dt);
      z.kx = damp(z.kx, 0, 7, dt);
      z.kz = damp(z.kz, 0, 7, dt);
      z.x += (z.vx + z.kx + sepX) * dt;
      z.z += (z.vz + z.kz + sepZ) * dt;

      const touched = world.collision.resolveCircle(z, z.radius);
      z.blockedBy = touched && world.structures.isStructureCollider(touched) ? touched.owner : null;
      if (touched && z.state === 'charging') world.combat.bossChargeImpact(z, touched);

      // Face movement (or the player while winding up attacks).
      const moveSpeed = Math.hypot(z.vx, z.vz);
      if (desired.face !== null) {
        z.facing = angleDamp(z.facing, desired.face, 10, dt);
      } else if (moveSpeed > 0.2) {
        z.facing = angleDamp(z.facing, Math.atan2(z.vx, z.vz), 8, dt);
      }
      z.animPhase += dt * (1.5 + moveSpeed * 2.4 / Math.max(0.7, z.def.scale));
      this.watchdog(z, dt, world);
    }

    // Deferred so spatial-hash indices stay valid for the whole step.
    for (const z of this.removals) this.remove(z);
    this.removals.length = 0;
  }
}
