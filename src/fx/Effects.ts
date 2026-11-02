import * as THREE from 'three';
import type { QualityPreset } from '../config/quality';
import { DamageNumbers } from './DamageNumbers';
import { Decals } from './Decals';
import { ParticleSystem } from './Particles';
import { Tracers } from './Tracers';

const MAX_LIT = 2000;
const MAX_GLOW = 2000;
const MAX_DECALS = 200;

const C = {
  blood: new THREE.Color('#7a0d0d'),
  bloodDark: new THREE.Color('#4a0606'),
  spark: new THREE.Color('#ffd27a'),
  fire: new THREE.Color('#ff7a1a'),
  fireHot: new THREE.Color('#ffd25a'),
  smoke: new THREE.Color('#5c5753'),
  acid: new THREE.Color('#7dff3a'),
  acidDecal: new THREE.Color('#4fae1f'),
  scorch: new THREE.Color('#0d0b0a'),
  dust: new THREE.Color('#8a8070'),
  brass: new THREE.Color('#c9a23a'),
  wood: new THREE.Color('#7a5634'),
};

/**
 * Visual feedback facade: particles, decals, tracers, floating numbers and
 * screen-shake trauma. Gameplay code calls these semantic helpers.
 */
export class Effects {
  readonly lit = new ParticleSystem(MAX_LIT, false);
  readonly glow = new ParticleSystem(MAX_GLOW, true);
  readonly decals = new Decals(MAX_DECALS);
  readonly tracers = new Tracers(256);
  readonly numbers: DamageNumbers;
  /** Screen-shake trauma 0..1 (squared for the actual offset). */
  trauma = 0;
  shakeScale = 1;
  private readonly tmpC = new THREE.Color();

  constructor(scene: THREE.Scene, overlay: HTMLElement) {
    scene.add(this.lit.mesh, this.glow.mesh, this.decals.mesh, this.tracers.mesh);
    this.numbers = new DamageNumbers(overlay);
  }

  applyQuality(q: QualityPreset): void {
    this.lit.budget = Math.floor(q.particleBudget * 0.55);
    this.glow.budget = Math.floor(q.particleBudget * 0.45);
    this.decals.budget = Math.min(MAX_DECALS, q.decalBudget);
  }

  clear(): void {
    this.lit.clear();
    this.glow.clear();
    this.decals.clear();
    this.tracers.clear();
    this.numbers.clear();
    this.trauma = 0;
  }

  shake(amount: number): void {
    this.trauma = Math.min(1, this.trauma + amount * this.shakeScale);
  }

  update(dt: number): void {
    this.lit.update(dt);
    this.glow.update(dt);
    this.decals.update(dt);
    this.tracers.update(dt);
    this.trauma = Math.max(0, this.trauma - dt * 1.6);
  }

  sync(): void {
    this.lit.sync();
    this.glow.sync();
    this.tracers.sync();
  }

  private rand(a: number, b: number): number {
    return a + Math.random() * (b - a);
  }

  blood(x: number, y: number, z: number, dirX: number, dirZ: number, count: number, color: THREE.Color = C.blood): void {
    for (let i = 0; i < count; i++) {
      const s = this.rand(2, 6);
      this.lit.spawn({
        x, y, z,
        vx: dirX * s + this.rand(-2, 2), vy: this.rand(1, 5), vz: dirZ * s + this.rand(-2, 2),
        life: this.rand(0.5, 1.1), size: this.rand(0.06, 0.14), color: Math.random() < 0.3 ? C.bloodDark : color, drag: 1.5,
      });
    }
    if (count >= 4 && Math.random() < 0.6) this.decals.add(x + dirX * 0.8, z + dirZ * 0.8, this.rand(0.8, 1.6), C.blood, 0.75, 14);
  }

  /** Chunky body parts flying off on death. */
  gibs(x: number, z: number, skin: THREE.Color, cloth: THREE.Color, scale: number, dirX: number, dirZ: number): void {
    const n = Math.round(6 * scale);
    for (let i = 0; i < n; i++) {
      const s = this.rand(2, 6);
      this.lit.spawn({
        x: x + this.rand(-0.3, 0.3), y: this.rand(0.6, 1.5) * scale, z: z + this.rand(-0.3, 0.3),
        vx: dirX * s + this.rand(-2.5, 2.5), vy: this.rand(3, 7), vz: dirZ * s + this.rand(-2.5, 2.5),
        life: this.rand(0.9, 1.6), size: this.rand(0.12, 0.24) * scale, color: i % 2 ? skin : cloth, drag: 0.8,
      });
    }
    this.blood(x, 1, z, dirX, dirZ, Math.round(8 * scale));
    this.decals.add(x, z, this.rand(1.4, 2.4) * scale, C.blood, 0.85, 18);
  }

  sparks(x: number, y: number, z: number, dirX: number, dirZ: number, count: number, color: THREE.Color = C.spark): void {
    for (let i = 0; i < count; i++) {
      const s = this.rand(3, 8);
      this.glow.spawn({
        x, y, z,
        vx: dirX * s + this.rand(-3, 3), vy: this.rand(0.5, 4), vz: dirZ * s + this.rand(-3, 3),
        life: this.rand(0.12, 0.3), size: this.rand(0.04, 0.08), color, gravity: 0.6, drag: 2,
      });
    }
  }

  muzzle(x: number, y: number, z: number, dirX: number, dirZ: number, color: THREE.Color, big = false): void {
    const n = big ? 7 : 4;
    for (let i = 0; i < n; i++) {
      const s = this.rand(2, 7) * (big ? 1.4 : 1);
      this.glow.spawn({
        x, y, z,
        vx: dirX * s + this.rand(-1, 1), vy: this.rand(-0.3, 0.8), vz: dirZ * s + this.rand(-1, 1),
        life: this.rand(0.04, 0.09), size: this.rand(0.12, 0.24) * (big ? 1.5 : 1), color, gravity: 0, drag: 6,
      });
    }
  }

  casing(x: number, y: number, z: number, dirX: number, dirZ: number): void {
    // Eject to the right of the firing direction.
    const rx = dirZ;
    const rz = -dirX;
    this.lit.spawn({
      x, y, z,
      vx: rx * this.rand(1.5, 3) - dirX, vy: this.rand(2, 3.5), vz: rz * this.rand(1.5, 3) - dirZ,
      life: this.rand(0.8, 1.4), size: 0.05, color: C.brass, drag: 0.5,
    });
  }

  explosion(x: number, z: number, radius: number): void {
    const n = Math.round(18 + radius * 6);
    for (let i = 0; i < n; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = this.rand(2, 9) * (radius / 3.5);
      this.glow.spawn({
        x: x + Math.cos(a) * 0.3, y: this.rand(0.3, 1.2), z: z + Math.sin(a) * 0.3,
        vx: Math.cos(a) * s, vy: this.rand(2, 9), vz: Math.sin(a) * s,
        life: this.rand(0.25, 0.6), size: this.rand(0.25, 0.6), color: Math.random() < 0.5 ? C.fire : C.fireHot, gravity: -0.15, drag: 3.5,
      });
    }
    for (let i = 0; i < Math.round(n * 0.3); i++) {
      const a = Math.random() * Math.PI * 2;
      const s = this.rand(1, 3.5);
      this.lit.spawn({
        x, y: this.rand(0.5, 1.5), z,
        vx: Math.cos(a) * s, vy: this.rand(1, 3), vz: Math.sin(a) * s,
        life: this.rand(0.7, 1.2), size: this.rand(0.16, 0.3), color: C.smoke, gravity: -0.12, drag: 2, grow: 0.8,
      });
    }
    for (let i = 0; i < 8; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = this.rand(5, 11);
      this.lit.spawn({
        x, y: 0.5, z,
        vx: Math.cos(a) * s, vy: this.rand(4, 9), vz: Math.sin(a) * s,
        life: this.rand(0.8, 1.4), size: this.rand(0.08, 0.18), color: C.scorch, drag: 0.6,
      });
    }
    this.decals.add(x, z, radius * 1.3, C.scorch, 0.8, 25);
  }

  fire(x: number, y: number, z: number, spread: number): void {
    this.glow.spawn({
      x: x + this.rand(-spread, spread), y: y + this.rand(0, 0.5), z: z + this.rand(-spread, spread),
      vx: this.rand(-0.4, 0.4), vy: this.rand(1.5, 3), vz: this.rand(-0.4, 0.4),
      life: this.rand(0.25, 0.5), size: this.rand(0.15, 0.3), color: Math.random() < 0.6 ? C.fire : C.fireHot, gravity: -0.1, drag: 1.5,
    });
  }

  /** A single flamethrower flame puff (visual only; gameplay is in WeaponSystem). */
  flame(x: number, y: number, z: number, vx: number, vz: number, life: number): void {
    this.tmpC.copy(Math.random() < 0.5 ? C.fire : C.fireHot);
    this.glow.spawn({ x, y, z, vx, vy: this.rand(0.2, 1.4), vz, life, size: this.rand(0.25, 0.45), color: this.tmpC, gravity: -0.15, drag: 1.2, grow: 1.4 });
  }

  smoke(x: number, y: number, z: number): void {
    this.lit.spawn({
      x, y, z, vx: this.rand(-0.3, 0.3), vy: this.rand(0.8, 1.6), vz: this.rand(-0.3, 0.3),
      life: this.rand(0.6, 1.0), size: this.rand(0.1, 0.2), color: C.smoke, gravity: -0.05, drag: 1, grow: 1.0,
    });
  }

  acid(x: number, y: number, z: number, count: number): void {
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = this.rand(1, 4);
      this.glow.spawn({
        x, y, z, vx: Math.cos(a) * s, vy: this.rand(2, 5), vz: Math.sin(a) * s,
        life: this.rand(0.3, 0.6), size: this.rand(0.08, 0.16), color: C.acid, drag: 1,
      });
    }
  }

  acidPuddle(x: number, z: number, radius: number, duration: number): void {
    this.decals.add(x, z, radius * 2.1, C.acidDecal, 0.8, duration);
  }

  bubble(x: number, z: number): void {
    this.glow.spawn({
      x, y: 0.08, z, vx: 0, vy: this.rand(0.6, 1.2), vz: 0,
      life: this.rand(0.3, 0.6), size: this.rand(0.06, 0.12), color: C.acid, gravity: 0, drag: 1,
    });
  }

  dust(x: number, z: number, count: number, spread = 0.3): void {
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = this.rand(0.5, 2.5);
      this.lit.spawn({
        x: x + Math.cos(a) * spread, y: 0.15, z: z + Math.sin(a) * spread,
        vx: Math.cos(a) * s, vy: this.rand(0.3, 1.5), vz: Math.sin(a) * s,
        life: this.rand(0.4, 0.8), size: this.rand(0.12, 0.25), color: C.dust, gravity: 0.05, drag: 3, grow: 1,
      });
    }
  }

  debris(x: number, y: number, z: number, count: number, color: THREE.Color = C.wood): void {
    for (let i = 0; i < count; i++) {
      const a = Math.random() * Math.PI * 2;
      const s = this.rand(2, 6);
      this.lit.spawn({
        x, y, z, vx: Math.cos(a) * s, vy: this.rand(2, 6), vz: Math.sin(a) * s,
        life: this.rand(0.8, 1.4), size: this.rand(0.1, 0.25), color, drag: 0.6,
      });
    }
  }

  sparkle(x: number, y: number, z: number, color: THREE.Color, count = 10): void {
    for (let i = 0; i < count; i++) {
      const a = (i / count) * Math.PI * 2;
      this.glow.spawn({
        x, y, z, vx: Math.cos(a) * 2.5, vy: this.rand(1, 3), vz: Math.sin(a) * 2.5,
        life: this.rand(0.3, 0.6), size: 0.1, color, gravity: 0.2, drag: 3,
      });
    }
  }

  ring(x: number, z: number, radius: number, color: THREE.Color, count = 24): void {
    for (let i = 0; i < count; i++) {
      const a = (i / count) * Math.PI * 2;
      this.glow.spawn({
        x: x + Math.cos(a) * radius, y: 0.2, z: z + Math.sin(a) * radius,
        vx: Math.cos(a) * 4, vy: this.rand(0.5, 2), vz: Math.sin(a) * 4,
        life: this.rand(0.3, 0.5), size: this.rand(0.15, 0.25), color, gravity: 0, drag: 3,
      });
    }
  }
}

export const FX_COLORS = C;
