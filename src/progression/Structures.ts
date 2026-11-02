import * as THREE from 'three';
import { STRUCTURES, TURRET, type StructureType } from '../config/shop';
import { angleDamp, wrapAngle } from '../core/math';
import type { World } from '../game/World';
import { ARENA_HALF } from '../world/Arena';
import { BULLET_HEIGHT, type BoxCollider, type Collider, type RayHit } from '../world/Collision';
import { MeshBuilder } from '../world/MeshBuilder';
import type { Zombie } from '../zombies/Zombie';

export class Structure {
  hp: number;
  readonly maxHp: number;
  collider: BoxCollider | null = null;
  readonly group = new THREE.Group();
  head: THREE.Object3D | null = null;
  headAngle = 0;
  cooldown = 0;
  target: Zombie | null = null;
  retarget = 0;
  flash = 0;
  wobble = 0;

  constructor(
    readonly type: StructureType,
    readonly x: number,
    readonly z: number,
    /** Footprint half-extents in world units. */
    readonly hw: number,
    readonly hd: number,
  ) {
    this.maxHp = STRUCTURES[type].hp;
    this.hp = this.maxHp;
  }
}

const GHOST_OK = new THREE.Color('#5aff8a');
const GHOST_BAD = new THREE.Color('#ff4a3a');

/**
 * Player-built barricades and turrets: placement validation, nav-grid
 * integration (zombies path around them or break through), damage and turret AI.
 */
export class Structures {
  readonly group = new THREE.Group();
  readonly list: Structure[] = [];
  private readonly material = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
  private readonly geos: Record<'barricade' | 'turretBase' | 'turretHead', THREE.BufferGeometry>;
  private readonly ghost: THREE.Group;
  private readonly ghostMat = new THREE.MeshBasicMaterial({ color: GHOST_OK, transparent: true, opacity: 0.45, depthWrite: false });
  private readonly ghostBarricade: THREE.Mesh;
  private readonly ghostTurret: THREE.Group;
  private readonly ghostRange: THREE.Mesh;
  private readonly rayHit: RayHit = { t: 0, collider: null };
  private readonly muzzleColor = new THREE.Color('#9ad8ff');

  constructor() {
    this.geos = {
      barricade: buildBarricade(),
      turretBase: buildTurretBase(),
      turretHead: buildTurretHead(),
    };
    this.ghost = new THREE.Group();
    this.ghostBarricade = new THREE.Mesh(this.geos.barricade, this.ghostMat);
    this.ghostTurret = new THREE.Group();
    this.ghostTurret.add(new THREE.Mesh(this.geos.turretBase, this.ghostMat), new THREE.Mesh(this.geos.turretHead, this.ghostMat));
    (this.ghostTurret.children[1] as THREE.Mesh).position.y = 0.85;
    const rangeGeo = new THREE.RingGeometry(TURRET.range - 0.12, TURRET.range, 64);
    rangeGeo.rotateX(-Math.PI / 2);
    this.ghostRange = new THREE.Mesh(rangeGeo, new THREE.MeshBasicMaterial({ color: '#9ad8ff', transparent: true, opacity: 0.35, depthWrite: false }));
    this.ghostRange.position.y = 0.05;
    this.ghostTurret.add(this.ghostRange);
    this.ghost.add(this.ghostBarricade, this.ghostTurret);
    this.ghost.visible = false;
    this.group.add(this.ghost);
  }

  get count(): Record<StructureType, number> {
    return {
      barricade: this.list.filter((s) => s.type === 'barricade').length,
      turret: this.list.filter((s) => s.type === 'turret').length,
    };
  }

  isStructureCollider(c: Collider): boolean {
    return c.owner instanceof Structure;
  }

  /** Total HP missing across structures (for the repair price). */
  get missingHp(): number {
    return this.list.reduce((sum, s) => sum + (s.maxHp - s.hp), 0);
  }

  repairAll(): void {
    for (const s of this.list) s.hp = s.maxHp;
  }

  clear(world: World | null): void {
    for (const s of [...this.list]) this.remove(s, world, false);
    if (world) world.rebuildNav();
  }

  /** Footprint (half extents) for a type and rotation. */
  footprint(type: StructureType, rotated: boolean): { hw: number; hd: number } {
    const [w, d] = STRUCTURES[type].footprint;
    return rotated ? { hw: d / 2, hd: w / 2 } : { hw: w / 2, hd: d / 2 };
  }

  /** Snaps a world position to the placement grid for a footprint. */
  snap(type: StructureType, rotated: boolean, x: number, z: number): { x: number; z: number } {
    const { hw, hd } = this.footprint(type, rotated);
    const sx = (hw * 2) % 2 === 0 ? Math.round(x) : Math.floor(x) + 0.5;
    const sz = (hd * 2) % 2 === 0 ? Math.round(z) : Math.floor(z) + 0.5;
    return { x: sx, z: sz };
  }

  canPlace(type: StructureType, rotated: boolean, x: number, z: number, world: World): boolean {
    const { hw, hd } = this.footprint(type, rotated);
    const limit = ARENA_HALF - 1.5;
    if (Math.abs(x) + hw > limit || Math.abs(z) + hd > limit) return false;
    if (world.collision.overlapsRect(x - hw - 0.1, z - hd - 0.1, x + hw + 0.1, z + hd + 0.1)) return false;
    const p = world.player;
    if (p.x > x - hw - p.radius && p.x < x + hw + p.radius && p.z > z - hd - p.radius && p.z < z + hd + p.radius) return false;
    if (this.count[type] >= STRUCTURES[type].maxCount) return false;
    // Never allow sealing the player in: the player's cell must still reach a spawn point.
    return world.wouldKeepPathOpen(x - hw, z - hd, x + hw, z + hd);
  }

  place(type: StructureType, rotated: boolean, x: number, z: number, world: World): Structure {
    const { hw, hd } = this.footprint(type, rotated);
    const s = new Structure(type, x, z, hw, hd);
    s.collider = world.collision.addBox(x - hw, z - hd, x + hw, z + hd, type === 'turret' ? 1.0 : 1.2, s);
    if (type === 'barricade') {
      const mesh = new THREE.Mesh(this.geos.barricade, this.material);
      mesh.rotation.y = rotated ? Math.PI / 2 : 0;
      mesh.castShadow = mesh.receiveShadow = true;
      s.group.add(mesh);
    } else {
      const base = new THREE.Mesh(this.geos.turretBase, this.material);
      base.castShadow = base.receiveShadow = true;
      const head = new THREE.Mesh(this.geos.turretHead, this.material);
      head.position.y = 0.85;
      head.castShadow = true;
      s.group.add(base, head);
      s.head = head;
    }
    s.group.position.set(x, 0, z);
    this.group.add(s.group);
    this.list.push(s);
    world.rebuildNav();
    world.fx.dust(x, z, 12, 0.8);
    world.audio.sfx('build', { x, z });
    world.stats.structuresBuilt++;
    return s;
  }

  private remove(s: Structure, world: World | null, rebuild = true): void {
    const i = this.list.indexOf(s);
    if (i === -1) return;
    this.list.splice(i, 1);
    this.group.remove(s.group);
    if (s.collider && world) world.collision.remove(s.collider);
    s.collider = null;
    if (world && rebuild) world.rebuildNav();
  }

  damage(s: Structure, amount: number, world: World): void {
    if (s.hp <= 0 || !this.list.includes(s)) return;
    s.hp -= amount;
    s.flash = 1;
    s.wobble = 1;
    world.audio.sfx('structureHit', { x: s.x, z: s.z, volume: 0.7 });
    world.fx.debris(s.x, 0.8, s.z, 2);
    if (s.hp <= 0) {
      world.fx.debris(s.x, 0.8, s.z, 16);
      world.fx.dust(s.x, s.z, 14, 1);
      world.audio.sfx('structureBreak', { x: s.x, z: s.z });
      world.events.emit('notify', { text: `${STRUCTURES[s.type].name} destroyed!`, tone: 'bad' });
      this.remove(s, world);
    }
  }

  damageInRadius(x: number, z: number, radius: number, amount: number, world: World): void {
    for (const s of [...this.list]) {
      const dx = Math.max(Math.abs(s.x - x) - s.hw, 0);
      const dz = Math.max(Math.abs(s.z - z) - s.hd, 0);
      if (dx * dx + dz * dz < radius * radius) this.damage(s, amount, world);
    }
  }

  update(dt: number, world: World): void {
    for (const s of this.list) {
      s.flash = Math.max(0, s.flash - dt * 5);
      s.wobble = Math.max(0, s.wobble - dt * 4);
      if (s.type !== 'turret' || !s.head) continue;
      s.cooldown -= dt;
      s.retarget -= dt;
      if (s.retarget <= 0 || !s.target || !s.target.alive) {
        s.retarget = 0.25;
        s.target = this.findTarget(s, world);
      }
      const t = s.target;
      if (!t) {
        s.headAngle += dt * 0.6; // idle scan
        continue;
      }
      const want = Math.atan2(t.x - s.x, t.z - s.z);
      s.headAngle = angleDamp(s.headAngle, want, TURRET.turnSpeed, dt);
      if (s.cooldown <= 0 && Math.abs(wrapAngle(want - s.headAngle)) < 0.15) {
        s.cooldown = 1 / TURRET.fireRate;
        const dx = Math.sin(s.headAngle);
        const dz = Math.cos(s.headAngle);
        // Start the ray outside the turret's own collider.
        const ox = s.x + dx * 1.15;
        const oz = s.z + dz * 1.15;
        world.weapons.hitscan(world, {
          ox, oz, dirX: dx, dirZ: dz, range: TURRET.range, damage: TURRET.damage * (1 + world.waves.wave * 0.04),
          pierce: 0, knockback: 1.2, source: 'turret', color: this.muzzleColor,
          fromX: ox, fromY: 1.1, fromZ: oz, critChance: 0, allowIncendiary: false,
        });
        world.fx.muzzle(ox, 1.1, oz, dx, dz, this.muzzleColor);
        world.audio.sfx('turret', { x: s.x, z: s.z, volume: 0.6 });
      }
    }
  }

  private findTarget(s: Structure, world: World): Zombie | null {
    let best: Zombie | null = null;
    let bestD = TURRET.range * TURRET.range;
    for (const z of world.zombies.list) {
      if (!z.alive || z.state === 'spawning') continue;
      const dx = z.x - s.x;
      const dz = z.z - s.z;
      const d2 = dx * dx + dz * dz;
      if (d2 >= bestD) continue;
      const d = Math.sqrt(d2);
      const ox = s.x + (dx / d) * 1.15;
      const oz = s.z + (dz / d) * 1.15;
      const hit = world.collision.raycast(ox, oz, dx / d, dz / d, Math.max(0, d - 1.15), BULLET_HEIGHT, this.rayHit);
      if (hit.collider) continue;
      bestD = d2;
      best = z;
    }
    return best;
  }

  /** Visual sync (render step). */
  sync(time: number): void {
    for (const s of this.list) {
      if (s.head) s.head.rotation.y = s.headAngle;
      s.group.rotation.z = Math.sin(time * 40) * 0.02 * s.wobble;
      s.group.scale.setScalar(1 + s.flash * 0.04);
    }
  }

  // ------------------------------------------------------------ placement UI

  showGhost(type: StructureType, rotated: boolean, x: number, z: number, valid: boolean): void {
    this.ghost.visible = true;
    this.ghostBarricade.visible = type === 'barricade';
    this.ghostTurret.visible = type === 'turret';
    this.ghostBarricade.rotation.y = rotated ? Math.PI / 2 : 0;
    this.ghost.position.set(x, 0, z);
    this.ghostMat.color.copy(valid ? GHOST_OK : GHOST_BAD);
  }

  hideGhost(): void {
    this.ghost.visible = false;
  }
}

function buildBarricade(): THREE.BufferGeometry {
  const b = new MeshBuilder(0.08);
  // Three-metre spiked wooden wall, long axis along X.
  for (const x of [-1.3, 0, 1.3]) b.box(0.18, 1.2, 0.18, '#4f3a26', x, 0.6, 0);
  for (let i = 0; i < 3; i++) b.box(2.95, 0.28, 0.12, i % 2 ? '#8a6238' : '#7a5634', 0, 0.3 + i * 0.36, 0.08, 0, 0, (i - 1) * 0.03);
  for (let i = 0; i < 5; i++) {
    const x = -1.2 + i * 0.6;
    b.cone(0.07, 0.6, 5, '#b8a888', x, 0.75, -0.3, -1.1);
  }
  b.box(2.9, 0.08, 0.1, '#3a3a3a', 0, 0.95, 0.15);
  return b.build();
}

function buildTurretBase(): THREE.BufferGeometry {
  const b = new MeshBuilder();
  b.box(1.5, 0.12, 1.5, '#3a3d42', 0, 0.06, 0);
  for (const [x, z] of [[-0.55, -0.55], [0.55, -0.55], [-0.55, 0.55], [0.55, 0.55]] as const) b.box(0.12, 0.6, 0.12, '#2a2c30', x * 0.8, 0.35, z * 0.8, 0, x * z > 0 ? 0.2 : -0.2);
  b.cylinder(0.32, 0.4, 0.6, 8, '#4a4f56', 0, 0.45, 0);
  b.box(0.5, 0.08, 0.5, '#d8a020', 0, 0.78, 0);
  return b.build();
}

function buildTurretHead(): THREE.BufferGeometry {
  const b = new MeshBuilder();
  b.box(0.62, 0.38, 0.7, '#56606a', 0, 0.12, 0);
  b.box(0.5, 0.06, 0.6, '#d8a020', 0, 0.33, 0);
  b.cylinder(0.06, 0.06, 0.75, 6, '#1f2124', -0.12, 0.15, 0.6, Math.PI / 2);
  b.cylinder(0.06, 0.06, 0.75, 6, '#1f2124', 0.12, 0.15, 0.6, Math.PI / 2);
  b.box(0.16, 0.12, 0.08, '#ff3a2a', 0, 0.22, 0.36);
  return b.build();
}
