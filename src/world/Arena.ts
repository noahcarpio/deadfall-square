import * as THREE from 'three';
import { Rng } from '../core/Rng';
import { CollisionWorld } from './Collision';
import { MeshBuilder } from './MeshBuilder';
import { drawGroundTexture } from './GroundTexture';

/** Half-size of the playable town square interior. */
export const ARENA_HALF = 36;
/** Half-size of the whole simulated world (includes alleys outside the square). */
export const WORLD_HALF = 48;

export interface SpawnPoint {
  x: number;
  z: number;
  /** Unit direction pointing into the arena. */
  dirX: number;
  dirZ: number;
}

export interface LampInfo {
  x: number;
  z: number;
  height: number;
}

interface Gap {
  from: number;
  to: number;
}

const BUILDING_PALETTE = ['#8a4b3c', '#a3714f', '#6f7a80', '#b59a72', '#5e6b5a', '#7d5a6b', '#9c8b6e', '#5a6578'];
const TRIM = '#3b3632';
const CONCRETE = '#8d8a84';
const DARK_CONCRETE = '#5f5c58';
const WOOD = '#7a5634';
const DARK_WOOD = '#4f3a26';

/**
 * Builds the abandoned town square: perimeter buildings with alleys (zombie
 * spawn routes), a low south fence (so it never hides the player from the
 * camera), and interior cover — cars, a bus, crates, fences, sandbags, a fountain.
 * All static geometry is merged into a handful of draw calls.
 */
export class Arena {
  readonly group = new THREE.Group();
  readonly collision: CollisionWorld;
  readonly spawnPoints: SpawnPoint[] = [];
  readonly lamps: LampInfo[] = [];
  /** Materials whose brightness follows the day/night cycle. */
  readonly litWindowMaterial: THREE.MeshBasicMaterial;
  readonly lampMaterial: THREE.MeshBasicMaterial;
  readonly lightPoolMaterial: THREE.MeshBasicMaterial;

  private readonly rng = new Rng(1337);
  private readonly solid: MeshBuilder;
  private readonly darkWindows = new MeshBuilder();
  private readonly litWindows = new MeshBuilder(0.15, () => this.rng.next());
  private readonly lampBulbs = new MeshBuilder();
  private readonly materials: THREE.Material[] = [];

  constructor(quality: { textureSize: number }) {
    this.solid = new MeshBuilder(0.06, () => this.rng.next());
    this.collision = new CollisionWorld({ minX: -WORLD_HALF, minZ: -WORLD_HALF, maxX: WORLD_HALF, maxZ: WORLD_HALF });

    this.litWindowMaterial = new THREE.MeshBasicMaterial({ vertexColors: true, color: '#ffffff' });
    this.lampMaterial = new THREE.MeshBasicMaterial({ color: '#fff3c4' });
    this.lightPoolMaterial = new THREE.MeshBasicMaterial({
      map: makeRadialTexture(),
      color: '#ffcf7a',
      transparent: true,
      opacity: 0,
      blending: THREE.AdditiveBlending,
      depthWrite: false,
    });

    this.buildGround(quality.textureSize);
    this.buildPerimeter();
    this.buildInterior();
    this.finalise();
  }

  // ---------------------------------------------------------------- ground

  private buildGround(textureSize: number): void {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = textureSize;
    drawGroundTexture(canvas, WORLD_HALF, ARENA_HALF, new Rng(99));
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.anisotropy = 4;
    const mat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.95, metalness: 0 });
    this.materials.push(mat);
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(WORLD_HALF * 2, WORLD_HALF * 2), mat);
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    ground.name = 'ground';
    this.group.add(ground);

    // Outer world boundary (invisible, beyond buildings).
    const H = WORLD_HALF;
    this.collision.addBox(-H - 2, -H - 2, H + 2, -H + 1, 20);
    this.collision.addBox(-H - 2, H - 1, H + 2, H + 2, 20);
    this.collision.addBox(-H - 2, -H - 2, -H + 1, H + 2, 20);
    this.collision.addBox(H - 1, -H - 2, H + 2, H + 2, 20);
  }

  // ------------------------------------------------------------- perimeter

  private buildPerimeter(): void {
    const A = ARENA_HALF;
    const H = WORLD_HALF - 1;
    const northGaps: Gap[] = [{ from: -16, to: -12 }, { from: 14, to: 18 }];
    const eastGaps: Gap[] = [{ from: -12, to: -8 }, { from: 18, to: 22 }];
    const westGaps: Gap[] = [{ from: -24, to: -20 }, { from: 6, to: 10 }];
    const southGaps: Gap[] = [{ from: -20, to: -16 }, { from: 10, to: 14 }];

    // North row: facades face +z (toward the camera, nicely visible).
    for (const [a, b] of segments(-H, H, northGaps)) this.buildingRow(a, b, 'north');
    for (const [a, b] of segments(-A, A, eastGaps)) this.buildingRow(a, b, 'east');
    for (const [a, b] of segments(-A, A, westGaps)) this.buildingRow(a, b, 'west');

    for (const g of northGaps) this.addSpawn((g.from + g.to) / 2, -H + 3, 0, 1);
    for (const g of eastGaps) this.addSpawn(H - 3, (g.from + g.to) / 2, -1, 0);
    for (const g of westGaps) this.addSpawn(-H + 3, (g.from + g.to) / 2, 1, 0);
    for (const g of southGaps) this.addSpawn((g.from + g.to) / 2, H - 3, 0, -1);

    // Alley end caps (tall wooden fences) for the building alleys.
    for (const g of northGaps) this.fenceCap(g.from, -H + 0.5, g.to, -H + 1, 'x');
    for (const g of eastGaps) this.fenceCap(H - 1, g.from, H - 0.5, g.to, 'z');
    for (const g of westGaps) this.fenceCap(-H + 0.5, g.from, -H + 1, g.to, 'z');

    // South side: low wall + chain-link fence with two gates; beyond it a vacant lot.
    for (const [a, b] of segments(-A, A, southGaps)) this.southWall(a, b, A);
    this.southLot();
  }

  private addSpawn(x: number, z: number, dirX: number, dirZ: number): void {
    this.spawnPoints.push({ x, z, dirX, dirZ });
  }

  private buildingRow(a: number, b: number, side: 'north' | 'east' | 'west'): void {
    let cursor = a;
    while (b - cursor > 0.5) {
      let w = this.rng.range(6, 11);
      if (b - cursor - w < 4) w = b - cursor;
      this.building(cursor, cursor + w, side);
      cursor += w;
    }
  }

  /**
   * One building occupying [a, b] along the row. `side` determines which way the
   * facade faces. Built in a local frame where the facade faces +z, then rotated.
   */
  private building(a: number, b: number, side: 'north' | 'east' | 'west'): void {
    const A = ARENA_HALF;
    const H = WORLD_HALF - 1;
    const depth = H - A;
    const width = b - a;
    const height = Math.round(this.rng.range(2, 4)) * 3 + this.rng.range(0, 0.8);
    const color = this.rng.pick(BUILDING_PALETTE);
    const mid = (a + b) / 2;

    let cx: number;
    let cz: number;
    let ry: number;
    if (side === 'north') {
      cx = mid; cz = -A - depth / 2; ry = 0;
      this.collision.addBox(a, -H, b, -A, height);
    } else if (side === 'east') {
      cx = A + depth / 2; cz = mid; ry = -Math.PI / 2;
      this.collision.addBox(A, a, H, b, height);
    } else {
      cx = -A - depth / 2; cz = mid; ry = Math.PI / 2;
      this.collision.addBox(-H, a, -A, b, height);
    }

    const s = this.solid;
    const rng = this.rng;
    this.inFrame(cx, cz, ry, () => {
      const front = depth / 2; // local +z is the facade
      s.box(width - 0.1, height, depth, color, 0, height / 2, 0);
      // Parapet + roof clutter.
      s.box(width - 0.1, 0.5, depth, TRIM, 0, height + 0.25, 0);
      s.box(width - 0.7, 0.2, depth - 0.6, '#4a4542', 0, height + 0.55, 0);
      if (rng.chance(0.6)) s.box(1.4, 0.9, 1.0, '#9a9ea3', rng.range(-width / 3, width / 3), height + 0.95, rng.range(-depth / 4, depth / 4));
      if (rng.chance(0.4)) s.cylinder(0.7, 0.7, 1.6, 8, '#6d4c3a', rng.range(-width / 3, width / 3), height + 1.3, -depth / 4);
      // Ground-floor band and floor cornices.
      s.box(width - 0.05, 0.25, 0.25, TRIM, 0, 3, front + 0.1);
      s.box(width - 0.05, 0.6, 0.2, '#2f2c2a', 0, 0.3, front + 0.05);
      // Door and optional awning.
      const doorX = rng.range(-width / 2 + 1.5, width / 2 - 1.5);
      s.box(1.3, 2.3, 0.15, '#2a211b', doorX, 1.15, front + 0.05);
      s.box(1.6, 0.2, 0.25, TRIM, doorX, 2.4, front + 0.1);
      if (rng.chance(0.55)) {
        const stripe = rng.pick(['#7e2b2b', '#2b5a7e', '#2f6b3d', '#8a6d2b']);
        const aw = Math.min(width - 1, rng.range(3, 6));
        s.box(aw, 0.12, 1.4, stripe, rng.range(-(width - aw) / 2, (width - aw) / 2), 2.85, front + 0.7, 0, 0.35);
      }
      // Shop window on the ground floor.
      const shopW = Math.min(width - 3.5, 3.2);
      if (shopW > 1.2) {
        const sx = doorX > 0 ? doorX - 2.6 : doorX + 2.6;
        if (Math.abs(sx) + shopW / 2 < width / 2 - 0.3) {
          s.box(shopW + 0.3, 1.6, 0.12, TRIM, sx, 1.45, front + 0.04);
          this.darkWindows.box(shopW, 1.3, 0.1, '#1c2733', sx, 1.45, front + 0.09);
        }
      }
      // Upper windows.
      const floors = Math.floor(height / 3);
      const cols = Math.max(1, Math.floor((width - 1) / 2.2));
      const spacing = (width - 1) / cols;
      for (let f = 1; f < floors; f++) {
        for (let c = 0; c < cols; c++) {
          const wx = -width / 2 + 0.5 + spacing * (c + 0.5);
          const wy = f * 3 + 1.4;
          if (rng.chance(0.12)) {
            s.box(1.1, 1.5, 0.08, '#4a3826', wx, wy, front + 0.05); // boarded up
            s.box(1.3, 0.18, 0.1, WOOD, wx, wy + 0.25, front + 0.1, 0, 0, rng.range(-0.4, 0.4));
            s.box(1.3, 0.18, 0.1, WOOD, wx, wy - 0.3, front + 0.1, 0, 0, rng.range(-0.4, 0.4));
            continue;
          }
          s.box(1.3, 1.7, 0.1, TRIM, wx, wy, front + 0.02);
          s.box(1.4, 0.12, 0.3, TRIM, wx, wy - 0.9, front + 0.12);
          if (rng.chance(0.3)) this.litWindows.box(1.05, 1.45, 0.06, rng.pick(['#ffd28a', '#ffc070', '#ffe3b0', '#9fd0ff']), wx, wy, front + 0.08);
          else this.darkWindows.box(1.05, 1.45, 0.06, rng.pick(['#1b2530', '#202b37', '#161d26']), wx, wy, front + 0.08);
        }
      }
    });
  }

  /** Applies one parent transform to every builder (solid, windows) while `fn` runs. */
  private inFrame(x: number, z: number, ry: number, fn: () => void): void {
    this.solid.group(x, 0, z, ry, () => {
      this.darkWindows.group(x, 0, z, ry, () => {
        this.litWindows.group(x, 0, z, ry, fn);
      });
    });
  }

  private fenceCap(minX: number, minZ: number, maxX: number, maxZ: number, axis: 'x' | 'z'): void {
    const len = axis === 'x' ? maxX - minX : maxZ - minZ;
    const cx = (minX + maxX) / 2;
    const cz = (minZ + maxZ) / 2;
    const ry = axis === 'x' ? 0 : Math.PI / 2;
    this.solid.group(cx, 0, cz, ry, () => {
      const planks = Math.round(len / 0.35);
      for (let i = 0; i < planks; i++) {
        const x = -len / 2 + (i + 0.5) * (len / planks);
        this.solid.box(len / planks - 0.04, 3 + this.rng.range(-0.3, 0.3), 0.15, i % 2 ? WOOD : DARK_WOOD, x, 1.5, 0);
      }
    });
  }

  private southWall(a: number, b: number, z: number): void {
    const len = b - a;
    const cx = (a + b) / 2;
    const s = this.solid;
    s.box(len, 1.1, 0.6, CONCRETE, cx, 0.55, z + 0.3);
    s.box(len, 0.12, 0.7, DARK_CONCRETE, cx, 1.16, z + 0.3);
    // Chain-link: posts and two rails, mesh suggested by thin wires.
    const posts = Math.max(2, Math.round(len / 3) + 1);
    for (let i = 0; i < posts; i++) {
      const x = a + (i * len) / (posts - 1);
      s.cylinder(0.06, 0.06, 1.8, 6, '#7c8288', x, 2.0, z + 0.3);
    }
    s.box(len, 0.06, 0.06, '#7c8288', cx, 2.85, z + 0.3);
    for (let y = 1.4; y < 2.8; y += 0.35) s.box(len, 0.025, 0.025, '#5d6369', cx, y, z + 0.3);
    this.collision.addBox(a, z, b, z + 0.6, 2.9);
  }

  private southLot(): void {
    const s = this.solid;
    const rng = this.rng;
    const A = ARENA_HALF;
    // Rubble piles and a burnt-out van, all low so the camera sees over them.
    for (let i = 0; i < 9; i++) {
      const x = rng.range(-42, 42);
      const z = rng.range(A + 3, WORLD_HALF - 3);
      if (Math.abs(x + 18) < 4 || Math.abs(x - 12) < 4) continue;
      const r = rng.range(0.8, 1.6);
      s.ico(r, 0, rng.pick(['#6d6862', '#5b5550', '#7a736b']), x, r * 0.25, z, 1, 0.45, 1);
      this.collision.addCircle(x, z, r * 0.9, 0.7);
    }
    this.car(-34, A + 6, 0, '#3a3530', true);
    this.car(30, A + 7, 0.15, '#3c3a38', true);
  }

  // -------------------------------------------------------------- interior

  private buildInterior(): void {
    this.fountain(0, 0);
    for (const [x, z] of [[-9, -9], [9, -9], [-9, 9], [9, 9], [-26, -30], [26, -30], [-30, 24], [30, 30], [0, -30]] as const) this.lamp(x, z);
    for (let i = 0; i < 4; i++) {
      const a = Math.PI / 4 + (i * Math.PI) / 2;
      this.bench(Math.cos(a) * 6.3, Math.sin(a) * 6.3, -a + Math.PI / 2);
    }
    for (const [x, z] of [[-24, 0], [24, 8], [-4, -16], [6, 28], [-30, -30]] as const) this.tree(x, z);

    const carColors = ['#7a2f2a', '#2f4f6e', '#5d6a3a', '#8a8378', '#3d3a46', '#9a6b2e', '#25544f'];
    const cars: Array<[number, number, number]> = [
      [-14, -8, 0], [11, -15, Math.PI / 2], [18, 11, 0], [-21, 16, Math.PI / 2],
      [5, 21, 0], [-8, -25, 0], [28, -24, Math.PI / 2], [-29, -7, Math.PI / 2],
    ];
    cars.forEach(([x, z, r], i) => this.car(x, z, r, carColors[i % carColors.length] as string, false));
    this.bus(25, -3);

    for (const [x, z] of [[-27, -20], [29, 23], [-11, 13], [14, -29], [-30, 29], [32, -8], [-4, 31]] as const) this.crateCluster(x, z);

    this.fence(-31, 10, -22, 10);
    this.fence(19, 27, 19, 33);
    this.fence(-6, -33, 3, -33);
    this.fence(31, 13, 35, 13);

    this.sandbags(-18, -29, 0);
    this.sandbags(13, 30, Math.PI);
    this.sandbags(31, 0, -Math.PI / 2);

    this.barrier(-2, 15, 0);
    this.barrier(15, -6, Math.PI / 2);
    this.barrier(-17, -1, Math.PI / 2);

    this.dumpster(33, -16, Math.PI / 2);
    this.dumpster(-33, 19, Math.PI / 2);

    for (const [x, z, c] of [[31, 4, '#a33a2a'], [-31, -14, '#c49a2a'], [7, -33, '#2a6aa3'], [-13, 32, '#a33a2a'], [22, -32, '#c49a2a'], [-24, 30, '#4a7a3a']] as const) this.barrel(x, z, c);
  }

  private fountain(x: number, z: number): void {
    const s = this.solid;
    s.cylinder(3.5, 3.7, 0.7, 14, '#8f8a83', x, 0.35, z);
    s.cylinder(3.0, 3.0, 0.2, 14, '#2f4f57', x, 0.62, z); // stagnant water
    s.cylinder(0.9, 1.1, 1.2, 8, '#7d7872', x, 1.2, z);
    s.cylinder(1.4, 1.2, 0.25, 10, '#8f8a83', x, 1.9, z);
    // Low-poly statue: a figure raising a torch.
    s.box(0.7, 1.0, 0.45, '#5c7a6a', x, 2.6, z);
    s.box(0.55, 0.5, 0.4, '#5c7a6a', x, 3.35, z);
    s.box(0.18, 1.0, 0.18, '#5c7a6a', x + 0.45, 3.4, z, 0, 0, -0.3);
    s.cone(0.2, 0.4, 6, '#4f6b5c', x + 0.62, 4.0, z);
    this.collision.addCircle(x, z, 3.6, 0.75);
    this.collision.addCircle(x, z, 1.1, 4);
  }

  private lamp(x: number, z: number): void {
    const s = this.solid;
    s.cylinder(0.22, 0.28, 0.4, 8, '#2b2e31', x, 0.2, z);
    s.cylinder(0.08, 0.1, 4.2, 6, '#2b2e31', x, 2.3, z);
    s.box(0.9, 0.08, 0.08, '#2b2e31', x + 0.35, 4.35, z);
    s.cone(0.32, 0.35, 6, '#2b2e31', x + 0.75, 4.25, z);
    this.lampBulbs.ico(0.17, 0, '#ffffff', x + 0.75, 4.08, z);
    this.lamps.push({ x: x + 0.75, z, height: 4.1 });
    this.collision.addCircle(x, z, 0.25, 4.4);
  }

  private bench(x: number, z: number, ry: number): void {
    const s = this.solid;
    s.group(x, 0, z, ry, () => {
      s.box(2.0, 0.1, 0.55, WOOD, 0, 0.5, 0);
      s.box(2.0, 0.45, 0.08, WOOD, 0, 0.85, -0.25, 0, -0.15);
      s.box(0.1, 0.5, 0.5, '#2b2e31', -0.85, 0.25, 0);
      s.box(0.1, 0.5, 0.5, '#2b2e31', 0.85, 0.25, 0);
    });
    this.collision.addCircle(x, z, 0.6, 0.9);
  }

  private tree(x: number, z: number): void {
    const s = this.solid;
    s.box(2.2, 0.6, 2.2, '#77716a', x, 0.3, z);
    s.box(1.9, 0.1, 1.9, '#3d2f22', x, 0.62, z);
    s.cylinder(0.15, 0.22, 2.2, 6, '#4b3727', x, 1.7, z);
    const dead = this.rng.chance(0.4);
    const leaf = dead ? '#6b5a3c' : '#3f5a35';
    s.ico(1.5, 0, leaf, x, 3.4, z, 1, 1.15, 1);
    s.ico(1.0, 0, dead ? '#5d4d33' : '#4a6a3e', x + 0.6, 4.3, z - 0.3);
    this.collision.addCircle(x, z, 1.2, 4.5);
  }

  private car(x: number, z: number, ry: number, color: string, burnt: boolean): void {
    const s = this.solid;
    const body = burnt ? '#2e2a27' : color;
    const glass = burnt ? '#1a1817' : '#24323d';
    s.group(x, 0, z, ry, () => {
      const tilt = this.rng.range(-0.04, 0.04);
      s.box(1.9, 0.75, 4.3, body, 0, 0.7, 0, 0, 0, tilt);
      s.box(1.7, 0.65, 2.2, body, 0, 1.38, -0.2, 0, 0, tilt);
      s.box(1.72, 0.5, 2.0, glass, 0, 1.38, -0.2, 0, 0, tilt);
      s.box(1.92, 0.12, 4.32, '#1f1f1f', 0, 0.38, 0);
      s.box(0.35, 0.15, 0.05, burnt ? '#2a2725' : '#f4e7b0', 0.6, 0.85, 2.16);
      s.box(0.35, 0.15, 0.05, burnt ? '#2a2725' : '#f4e7b0', -0.6, 0.85, 2.16);
      s.box(0.35, 0.15, 0.05, '#6b1d1d', 0.6, 0.85, -2.16);
      s.box(0.35, 0.15, 0.05, '#6b1d1d', -0.6, 0.85, -2.16);
      for (const [wx, wz] of [[-0.95, 1.4], [0.95, 1.4], [-0.95, -1.4], [0.95, -1.4]] as const) {
        s.cylinder(0.38, 0.38, 0.28, 8, '#161616', wx, 0.38, wz, 0, 0, Math.PI / 2);
      }
      if (!burnt && this.rng.chance(0.5)) s.box(0.9, 0.05, 0.9, '#3a3a3a', 0.3, 1.72, 0.2, 0, 0.6);
    });
    const hw = Math.abs(Math.sin(ry)) > 0.5 ? 2.2 : 1.0;
    const hd = Math.abs(Math.sin(ry)) > 0.5 ? 1.0 : 2.2;
    this.collision.addBox(x - hw, z - hd, x + hw, z + hd, burnt ? 1.2 : 1.7);
  }

  private bus(x: number, z: number): void {
    const s = this.solid;
    s.group(x, 0, z, 0, () => {
      s.box(2.6, 2.4, 10, '#c48a2a', 0, 1.55, 0, 0, 0, 0.05);
      s.box(2.62, 0.5, 10.02, '#3a3632', 0, 0.55, 0);
      s.box(2.64, 0.9, 8.6, '#22303a', 0, 2.0, -0.3, 0, 0, 0.05);
      s.box(2.4, 0.1, 9.6, '#a87420', 0, 2.8, 0, 0, 0, 0.05);
      for (const wz of [3.4, -3.4]) {
        s.cylinder(0.5, 0.5, 0.35, 8, '#161616', -1.25, 0.5, wz, 0, 0, Math.PI / 2);
        s.cylinder(0.5, 0.5, 0.35, 8, '#161616', 1.25, 0.5, wz, 0, 0, Math.PI / 2);
      }
    });
    this.collision.addBox(x - 1.35, z - 5.05, x + 1.35, z + 5.05, 2.8);
  }

  private crateCluster(x: number, z: number): void {
    const s = this.solid;
    const rng = this.rng;
    const n = rng.int(2, 4);
    for (let i = 0; i < n; i++) {
      const cx = x + (i % 2) * 1.25 - 0.6;
      const cz = z + Math.floor(i / 2) * 1.25 - 0.6;
      const size = 1.15;
      const stacked = rng.chance(0.4);
      const levels = stacked ? 2 : 1;
      for (let l = 0; l < levels; l++) {
        const rot = rng.range(-0.15, 0.15);
        const y = size / 2 + l * size;
        s.box(size, size, size, l === 0 ? '#8a6238' : '#9a7144', cx, y, cz, rot);
        s.box(size + 0.02, 0.14, size + 0.02, DARK_WOOD, cx, y + 0.35, cz, rot);
        s.box(size + 0.02, 0.14, size + 0.02, DARK_WOOD, cx, y - 0.35, cz, rot);
      }
      this.collision.addBox(cx - 0.6, cz - 0.6, cx + 0.6, cz + 0.6, levels * size);
    }
  }

  private fence(x0: number, z0: number, x1: number, z1: number): void {
    const s = this.solid;
    const len = Math.hypot(x1 - x0, z1 - z0);
    const ry = Math.atan2(-(z1 - z0), x1 - x0);
    s.group((x0 + x1) / 2, 0, (z0 + z1) / 2, ry, () => {
      const posts = Math.max(2, Math.round(len / 1.5) + 1);
      for (let i = 0; i < posts; i++) {
        const px = -len / 2 + (i * len) / (posts - 1);
        s.box(0.15, 1.25, 0.15, DARK_WOOD, px, 0.62, 0);
      }
      s.box(len, 0.14, 0.08, WOOD, 0, 0.95, 0, 0, 0, this.rng.range(-0.02, 0.02));
      s.box(len, 0.14, 0.08, WOOD, 0, 0.45, 0, 0, 0, this.rng.range(-0.02, 0.02));
    });
    const t = 0.15;
    this.collision.addBox(Math.min(x0, x1) - t, Math.min(z0, z1) - t, Math.max(x0, x1) + t, Math.max(z0, z1) + t, 1.2);
  }

  private sandbags(x: number, z: number, ry: number): void {
    const s = this.solid;
    const cos = Math.cos(ry);
    const sin = Math.sin(ry);
    // A shallow arc of bags, convex side facing local -z.
    const bag = (i: number): [number, number] => {
      const a = -0.9 + (i / 5) * 1.8;
      return [Math.sin(a) * 3, -Math.cos(a) * 3 + 2.4];
    };
    s.group(x, 0, z, ry, () => {
      for (let row = 0; row < 3; row++) {
        for (let i = 0; i < 6; i++) {
          const [bx, bz] = bag(i);
          s.ico(0.42, 0, row % 2 ? '#8c7c5c' : '#7d6e50', bx + (row % 2) * 0.12, 0.2 + row * 0.27, bz, 1.3, 0.55, 0.8);
        }
      }
    });
    for (let i = 0; i < 6; i++) {
      const [lx, lz] = bag(i);
      this.collision.addCircle(x + lx * cos + lz * sin, z - lx * sin + lz * cos, 0.55, 0.9);
    }
  }

  private barrier(x: number, z: number, ry: number): void {
    const s = this.solid;
    s.group(x, 0, z, ry, () => {
      s.box(3.0, 0.35, 0.8, CONCRETE, 0, 0.18, 0);
      s.box(3.0, 0.65, 0.35, CONCRETE, 0, 0.67, 0);
      s.box(3.0, 0.1, 0.36, '#c9a227', 0, 0.9, 0);
    });
    const along = Math.abs(Math.sin(ry)) > 0.5;
    const hw = along ? 0.4 : 1.5;
    const hd = along ? 1.5 : 0.4;
    this.collision.addBox(x - hw, z - hd, x + hw, z + hd, 1.0);
  }

  private dumpster(x: number, z: number, ry: number): void {
    const s = this.solid;
    s.group(x, 0, z, ry, () => {
      s.box(2.4, 1.3, 1.3, '#2f5a3a', 0, 0.75, 0);
      s.box(2.45, 0.1, 1.35, '#24452d', 0, 1.42, 0.05, 0.12);
      s.box(2.5, 0.12, 0.12, '#1d1d1d', 0, 0.12, 0.6);
      s.box(2.5, 0.12, 0.12, '#1d1d1d', 0, 0.12, -0.6);
    });
    const along = Math.abs(Math.sin(ry)) > 0.5;
    const hw = along ? 0.7 : 1.25;
    const hd = along ? 1.25 : 0.7;
    this.collision.addBox(x - hw, z - hd, x + hw, z + hd, 1.5);
  }

  private barrel(x: number, z: number, color: string): void {
    const s = this.solid;
    s.cylinder(0.42, 0.42, 1.1, 10, color, x, 0.55, z);
    s.cylinder(0.44, 0.44, 0.08, 10, '#2b2b2b', x, 0.3, z);
    s.cylinder(0.44, 0.44, 0.08, 10, '#2b2b2b', x, 0.8, z);
    this.collision.addCircle(x, z, 0.45, 1.1);
  }

  // ------------------------------------------------------------- finalise

  private finalise(): void {
    const solidMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.88, metalness: 0.02, flatShading: true });
    const darkMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.25, metalness: 0.4 });
    this.materials.push(solidMat, darkMat, this.litWindowMaterial, this.lampMaterial, this.lightPoolMaterial);

    const solid = new THREE.Mesh(this.solid.build(), solidMat);
    solid.castShadow = true;
    solid.receiveShadow = true;
    solid.name = 'arena-solid';
    this.group.add(solid);

    const dark = new THREE.Mesh(this.darkWindows.build(), darkMat);
    dark.name = 'arena-windows';
    this.group.add(dark);

    const lit = new THREE.Mesh(this.litWindows.build(), this.litWindowMaterial);
    lit.name = 'arena-lit-windows';
    this.group.add(lit);

    const bulbs = new THREE.Mesh(this.lampBulbs.build(), this.lampMaterial);
    bulbs.name = 'arena-lamps';
    this.group.add(bulbs);

    // Fake light pools under street lamps: cheap additive discs instead of real lights.
    const pools = new MeshBuilder();
    for (const l of this.lamps) pools.add(new THREE.PlaneGeometry(9, 9), '#ffffff', l.x, 0.03, l.z, -Math.PI / 2);
    const poolGeo = pools.build();
    // MeshBuilder strips UVs (not needed elsewhere); restore planar UVs for the radial texture.
    addPlanarUvs(poolGeo, this.lamps, 9);
    const poolMesh = new THREE.Mesh(poolGeo, this.lightPoolMaterial);
    poolMesh.renderOrder = 1;
    poolMesh.name = 'arena-light-pools';
    this.group.add(poolMesh);
  }

  /** Applies night factor (0 = day, 1 = deep night) to emissive arena elements. */
  setNight(night: number): void {
    const n = Math.max(0, Math.min(1, night));
    this.litWindowMaterial.color.setScalar(0.25 + 0.75 * n);
    this.lampMaterial.color.set('#fff3c4').multiplyScalar(0.35 + 0.65 * n);
    this.lightPoolMaterial.opacity = Math.max(0, (n - 0.25) / 0.75) * 0.55;
  }

  dispose(): void {
    this.group.traverse((o) => {
      if (o instanceof THREE.Mesh) o.geometry.dispose();
    });
    for (const m of this.materials) {
      const map = (m as THREE.MeshBasicMaterial).map;
      if (map) map.dispose();
      m.dispose();
    }
  }
}

/** Splits [from, to] into solid segments around the given gaps. */
function segments(from: number, to: number, gaps: Gap[]): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  let cursor = from;
  for (const g of [...gaps].sort((a, b) => a.from - b.from)) {
    if (g.from > cursor) out.push([cursor, g.from]);
    cursor = Math.max(cursor, g.to);
  }
  if (to > cursor) out.push([cursor, to]);
  return out;
}

function makeRadialTexture(): THREE.CanvasTexture {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  if (!g) throw new Error('2D canvas unavailable');
  const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.4, 'rgba(255,255,255,0.45)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Assigns UVs to merged square quads centred on each lamp (planar XZ projection). */
function addPlanarUvs(geo: THREE.BufferGeometry, centers: readonly LampInfo[], size: number): void {
  const pos = geo.getAttribute('position') as THREE.BufferAttribute;
  const uv = new Float32Array(pos.count * 2);
  const perQuad = pos.count / Math.max(1, centers.length);
  for (let i = 0; i < pos.count; i++) {
    const lamp = centers[Math.floor(i / perQuad)] as LampInfo;
    uv[i * 2] = (pos.getX(i) - lamp.x) / size + 0.5;
    uv[i * 2 + 1] = (pos.getZ(i) - lamp.z) / size + 0.5;
  }
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
}
