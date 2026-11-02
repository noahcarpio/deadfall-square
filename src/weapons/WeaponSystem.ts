import * as THREE from 'three';
import { WEAPONS, upgradedDamage, type WeaponDef, type WeaponId } from '../config/weapons';
import { BULLET_HEIGHT, type RayHit } from '../world/Collision';
import type { World } from '../game/World';
import type { Zombie } from '../zombies/Zombie';

interface Flame {
  x: number;
  z: number;
  vx: number;
  vz: number;
  life: number;
  maxLife: number;
  damage: number;
}

interface Grenade {
  x0: number;
  z0: number;
  x1: number;
  z1: number;
  t: number;
  duration: number;
  damage: number;
  radius: number;
  x: number;
  y: number;
  z: number;
}

export interface HitscanParams {
  ox: number;
  oz: number;
  dirX: number;
  dirZ: number;
  range: number;
  damage: number;
  pierce: number;
  knockback: number;
  source: string;
  color: THREE.Color;
  /** Visual tracer origin (muzzle), may differ from the logical ray origin. */
  fromX: number;
  fromY: number;
  fromZ: number;
  /** Damage falls off to this fraction at max range (shotgun). */
  falloff?: number;
  critChance?: number;
  allowIncendiary?: boolean;
}

const CRIT_CHANCE = 0.08;
const MAX_FLAMES = 300;

/**
 * Turns trigger pulls into bullets, flames and grenades: hitscan ray tests
 * against zombies and obstacles, flamethrower particles with burn, and arcing
 * grenades. Also used by turrets for their shots.
 */
export class WeaponSystem {
  private readonly flames: Flame[] = [];
  private readonly grenades: Grenade[] = [];
  private readonly grenadeMesh: THREE.InstancedMesh;
  private readonly rayHit: RayHit = { t: 0, collider: null };
  private readonly muzzle = new THREE.Vector3();
  private readonly colors = new Map<WeaponId, THREE.Color>();
  private readonly near: Zombie[] = [];
  private readonly m = new THREE.Matrix4();
  private readonly q = new THREE.Quaternion();
  private readonly s = new THREE.Vector3(1, 1, 1);
  private readonly p = new THREE.Vector3();
  private flameSoundOn = false;
  /** Current spread (radians), for the dynamic crosshair. */
  currentSpread = 0;
  /** 0..1 recoil kick for the player model. */
  recoil = 0;

  constructor(scene: THREE.Scene) {
    const mat = new THREE.MeshLambertMaterial({ color: '#3d4a2c' });
    this.grenadeMesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(0.16, 1), mat, 32);
    this.grenadeMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.grenadeMesh.frustumCulled = false;
    this.grenadeMesh.count = 0;
    this.grenadeMesh.castShadow = true;
    scene.add(this.grenadeMesh);
    for (const id of Object.keys(WEAPONS) as WeaponId[]) this.colors.set(id, new THREE.Color(WEAPONS[id].color));
  }

  clear(world: World | null): void {
    this.flames.length = 0;
    this.grenades.length = 0;
    this.grenadeMesh.count = 0;
    this.recoil = 0;
    if (this.flameSoundOn && world) world.audio.setFlame(false);
    this.flameSoundOn = false;
  }

  /** Spread for the current weapon given the player's movement. */
  spreadFor(def: WeaponDef, world: World): number {
    const p = world.player;
    return def.spread + def.moveSpread * p.speed01 + (p.sprinting ? 0.05 : 0);
  }

  update(dt: number, world: World, triggerHeld: boolean): void {
    const arsenal = world.arsenal;
    const player = world.player;
    const canShoot = player.canAct;
    const result = arsenal.update(dt, triggerHeld, canShoot, player.stats.reloadSpeed);
    const w = arsenal.current;
    const def = w.def;
    this.currentSpread = this.spreadFor(def, world);
    this.recoil = Math.max(0, 1 - arsenal.sinceShot * 9);

    if (result.reloaded) world.audio.sfx('reloadDone');
    if (result.dryFire) world.audio.sfx('dryFire');
    if (result.shots > 0) {
      for (let i = 0; i < result.shots; i++) this.fire(def, world);
    }
    const flameActive = def.kind === 'flame' && triggerHeld && canShoot && !arsenal.reloading && w.mag > 0;
    if (flameActive !== this.flameSoundOn) {
      this.flameSoundOn = flameActive;
      world.audio.setFlame(flameActive);
    }

    this.updateFlames(dt, world);
    this.updateGrenades(dt, world);
  }

  private fire(def: WeaponDef, world: World): void {
    const player = world.player;
    const w = world.arsenal.current;
    const dirAngle = Math.atan2(player.aimX, player.aimZ);
    const muzzle = world.playerModel.muzzleWorld(player.x, player.z, dirAngle, this.muzzle);
    const color = this.colors.get(def.id) as THREE.Color;
    const damage = upgradedDamage(def, w.upgrades);
    const dx = Math.sin(dirAngle);
    const dz = Math.cos(dirAngle);
    const spread = this.currentSpread;

    world.fx.shake(def.shake);
    world.lighting.flashMuzzle(muzzle.x, muzzle.y, muzzle.z, def.kind === 'flame' ? 6 : def.id === 'shotgun' || def.id === 'sniper' ? 40 : 22);

    if (def.kind === 'hitscan') {
      world.fx.muzzle(muzzle.x, muzzle.y, muzzle.z, dx, dz, color, def.id === 'shotgun' || def.id === 'sniper');
      world.fx.casing(player.x + dx * 0.3, 1.2, player.z + dz * 0.3, dx, dz);
      world.audio.sfx(def.sound, { volume: def.id === 'smg' ? 0.7 : 1 });
      const pierce = def.pierce + world.perks.level('piercing');
      for (let i = 0; i < def.pellets; i++) {
        const a = dirAngle + gaussian() * spread * (def.pellets > 1 ? 0.6 : 0.5);
        const pdx = Math.sin(a);
        const pdz = Math.cos(a);
        world.stats.shotsFired++;
        const hit = this.hitscan(world, {
          ox: player.x, oz: player.z, dirX: pdx, dirZ: pdz, range: def.range,
          damage, pierce, knockback: def.knockback, source: def.id, color,
          fromX: muzzle.x, fromY: muzzle.y, fromZ: muzzle.z,
          falloff: def.id === 'shotgun' ? 0.35 : 1, critChance: CRIT_CHANCE, allowIncendiary: true,
        });
        if (hit) world.stats.shotsHit++;
      }
    } else if (def.kind === 'flame') {
      const speed = def.projectileSpeed ?? 12;
      for (let i = 0; i < def.pellets; i++) {
        if (this.flames.length >= MAX_FLAMES) break;
        const a = dirAngle + (Math.random() - 0.5) * 2 * spread;
        const s = speed * (0.85 + Math.random() * 0.3);
        const vx = Math.sin(a) * s + player.vx * 0.5;
        const vz = Math.cos(a) * s + player.vz * 0.5;
        const life = def.range / speed;
        this.flames.push({ x: muzzle.x, z: muzzle.z, vx, vz, life, maxLife: life, damage });
        world.fx.flame(muzzle.x, muzzle.y - 0.1, muzzle.z, vx, vz, life);
      }
    } else {
      world.fx.muzzle(muzzle.x, muzzle.y, muzzle.z, dx, dz, color, true);
      world.audio.sfx('launcher');
      const dist = Math.max(4, Math.min(def.range, player.aimDistance));
      const a = dirAngle + gaussian() * spread * 0.5;
      const x1 = player.x + Math.sin(a) * dist;
      const z1 = player.z + Math.cos(a) * dist;
      const duration = dist / (def.projectileSpeed ?? 20) + 0.15;
      world.stats.shotsFired++;
      this.grenades.push({
        x0: muzzle.x, z0: muzzle.z, x1, z1, t: 0, duration, damage, radius: def.blastRadius ?? 4,
        x: muzzle.x, y: muzzle.y, z: muzzle.z,
      });
    }
  }

  /**
   * Fires a single hitscan ray. Damages up to (pierce + 1) zombies in order and
   * stops at the first bullet-blocking obstacle. Returns true if anything was hit.
   */
  hitscan(world: World, p: HitscanParams): boolean {
    const wall = world.collision.raycast(p.ox, p.oz, p.dirX, p.dirZ, p.range, BULLET_HEIGHT, this.rayHit);
    const maxT = wall.t;
    const hits = world.zombies.raycast(p.ox, p.oz, p.dirX, p.dirZ, maxT);
    let endT = maxT;
    let remaining = p.pierce + 1;
    let damage = p.damage;
    let any = false;
    // Copy targets first: damage can trigger explosions that mutate zombie state.
    const targets = hits.slice(0, remaining).map((h) => ({ z: h.zombie, t: h.t }));
    for (const h of targets) {
      if (remaining <= 0) break;
      if (!h.z.alive) continue;
      const falloff = p.falloff !== undefined && p.falloff < 1 ? 1 - (1 - p.falloff) * Math.min(1, h.t / p.range) : 1;
      const crit = Math.random() < (p.critChance ?? 0);
      world.combat.damageZombie(h.z, damage * falloff * (crit ? 2 : 1), {
        dirX: p.dirX, dirZ: p.dirZ, knock: p.knockback, source: p.source, crit,
        hitX: p.ox + p.dirX * h.t, hitZ: p.oz + p.dirZ * h.t, allowIncendiary: p.allowIncendiary ?? false,
      });
      any = true;
      remaining--;
      damage *= 0.8; // each pierced body soaks some damage
      if (remaining <= 0) endT = h.t;
    }
    const ex = p.ox + p.dirX * endT;
    const ez = p.oz + p.dirZ * endT;
    world.fx.tracers.add(p.fromX, p.fromY, p.fromZ, ex, ez, p.color, p.source === 'sniper' ? 0.1 : 0.05, p.source === 'sniper' ? 0.16 : 0.07);
    if (remaining > 0 && wall.collider) {
      // Player bullets never damage the player's own structures; they just spark.
      world.fx.sparks(ex - p.dirX * 0.1, BULLET_HEIGHT, ez - p.dirZ * 0.1, -p.dirX, -p.dirZ, 4);
    }
    return any;
  }

  private updateFlames(dt: number, world: World): void {
    const near = this.near;
    for (let i = this.flames.length - 1; i >= 0; i--) {
      const f = this.flames[i] as Flame;
      f.life -= dt;
      f.x += f.vx * dt;
      f.z += f.vz * dt;
      const age = 1 - f.life / f.maxLife;
      if (f.life <= 0 || world.collision.overlapsCircle(f.x, f.z, 0.15)) {
        if (f.life > 0 && Math.random() < 0.3) world.fx.smoke(f.x, 1, f.z);
        this.flames.splice(i, 1);
        continue;
      }
      const radius = 0.35 + age * 0.9;
      const n = world.zombies.queryRadius(f.x, f.z, radius, near);
      for (let k = 0; k < n; k++) {
        const z = near[k] as Zombie;
        if (z.flameCooldown > 0) continue;
        z.flameCooldown = 0.1;
        world.combat.damageZombie(z, f.damage, { dirX: f.vx * 0.05, dirZ: f.vz * 0.05, knock: 0.4, source: 'flamer', crit: false, hitX: z.x, hitZ: z.z, allowIncendiary: false });
        world.combat.ignite(z, f.damage * 1.4, 2.5);
      }
    }
  }

  private updateGrenades(dt: number, world: World): void {
    let n = 0;
    for (let i = this.grenades.length - 1; i >= 0; i--) {
      const g = this.grenades[i] as Grenade;
      g.t += dt;
      const t = Math.min(1, g.t / g.duration);
      const nx = g.x0 + (g.x1 - g.x0) * t;
      const nz = g.z0 + (g.z1 - g.z0) * t;
      g.y = 1.2 * (1 - t) + 0.15 + Math.sin(t * Math.PI) * Math.min(3.5, g.duration * 3);
      // Blocked by tall obstacles mid-flight.
      let detonate = t >= 1;
      if (!detonate && g.y < 2.2 && world.collision.overlapsCircle(nx, nz, 0.15)) detonate = true;
      if (!detonate && g.y < 2.2 && world.zombies.queryRadius(nx, nz, 0.25, this.near) > 0) detonate = true;
      g.x = nx;
      g.z = nz;
      if (Math.random() < 0.6) world.fx.smoke(g.x, g.y, g.z);
      if (detonate) {
        this.grenades.splice(i, 1);
        const hits = world.combat.explosion(g.x, g.z, g.radius, g.damage, 0, 40, 'launcher');
        if (hits > 0) world.stats.shotsHit++;
      }
    }
    for (const g of this.grenades) {
      this.m.compose(this.p.set(g.x, g.y, g.z), this.q, this.s);
      this.grenadeMesh.setMatrixAt(n++, this.m);
    }
    this.grenadeMesh.count = n;
    if (n > 0) this.grenadeMesh.instanceMatrix.needsUpdate = true;
  }
}

/** Approximately normal random in roughly [-2, 2] (sum of uniforms). */
function gaussian(): number {
  return (Math.random() + Math.random() + Math.random() - 1.5) * 1.33;
}
