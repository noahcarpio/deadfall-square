import type * as THREE from 'three';
import type { WeaponId } from '../config/weapons';
import { MeshBuilder } from '../world/MeshBuilder';

const METAL = '#2c2f33';
const DARK = '#1c1d1f';
const WOOD = '#6b4528';

/**
 * Builds a low-poly weapon model with vertex colours. The barrel points along
 * +z with the grip at the origin; returns the geometry and muzzle offset (z).
 */
export function buildWeaponGeometry(id: WeaponId): { geometry: THREE.BufferGeometry; muzzle: number } {
  const b = new MeshBuilder();
  let muzzle = 0.5;
  switch (id) {
    case 'pistol':
      b.box(0.1, 0.12, 0.34, METAL, 0, 0.05, 0.1);
      b.box(0.08, 0.16, 0.09, DARK, 0, -0.06, -0.02, 0, -0.25);
      muzzle = 0.28;
      break;
    case 'shotgun':
      b.box(0.11, 0.12, 0.62, METAL, 0, 0.06, 0.28);
      b.box(0.07, 0.07, 0.5, DARK, 0, -0.02, 0.32);
      b.box(0.13, 0.1, 0.22, WOOD, 0, -0.02, 0.36);
      b.box(0.1, 0.15, 0.36, WOOD, 0, 0.0, -0.18, 0, 0.2);
      muzzle = 0.6;
      break;
    case 'smg':
      b.box(0.1, 0.14, 0.42, '#3a3d42', 0, 0.05, 0.14);
      b.box(0.06, 0.06, 0.14, DARK, 0, 0.07, 0.42);
      b.box(0.07, 0.22, 0.08, DARK, 0, -0.12, 0.14, 0.15);
      b.box(0.07, 0.14, 0.08, DARK, 0, -0.08, -0.02, -0.3);
      muzzle = 0.5;
      break;
    case 'rifle':
      b.box(0.1, 0.14, 0.62, '#3b3f36', 0, 0.06, 0.2);
      b.box(0.05, 0.05, 0.3, DARK, 0, 0.07, 0.62);
      b.box(0.07, 0.2, 0.09, DARK, 0, -0.11, 0.22, 0.2);
      b.box(0.09, 0.15, 0.3, '#3b3f36', 0, 0.02, -0.2);
      b.box(0.05, 0.06, 0.16, DARK, 0, 0.17, 0.18);
      muzzle = 0.78;
      break;
    case 'sniper':
      b.box(0.1, 0.13, 0.7, '#4a4632', 0, 0.05, 0.22);
      b.box(0.045, 0.045, 0.5, DARK, 0, 0.07, 0.8);
      b.cylinder(0.045, 0.045, 0.32, 8, DARK, 0, 0.18, 0.2, Math.PI / 2);
      b.box(0.09, 0.16, 0.34, '#4a4632', 0, 0.0, -0.24, 0, 0.15);
      muzzle = 1.05;
      break;
    case 'flamer':
      b.box(0.12, 0.14, 0.6, '#7a2a22', 0, 0.05, 0.22);
      b.cylinder(0.11, 0.11, 0.42, 8, '#c4a23a', 0, -0.1, 0.1, Math.PI / 2);
      b.cylinder(0.05, 0.07, 0.18, 8, DARK, 0, 0.06, 0.6, Math.PI / 2);
      muzzle = 0.7;
      break;
    case 'launcher':
      b.cylinder(0.1, 0.1, 0.55, 8, '#4d5a3a', 0, 0.07, 0.24, Math.PI / 2);
      b.cylinder(0.12, 0.12, 0.2, 8, DARK, 0, 0.07, 0.05, Math.PI / 2);
      b.box(0.07, 0.18, 0.08, DARK, 0, -0.1, 0.1, 0.2);
      b.box(0.09, 0.13, 0.3, '#4d5a3a', 0, 0.0, -0.22);
      muzzle = 0.55;
      break;
  }
  return { geometry: b.build(), muzzle };
}
