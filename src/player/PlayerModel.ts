import * as THREE from 'three';
import type { WeaponId } from '../config/weapons';
import { buildWeaponGeometry } from '../weapons/WeaponModels';
import { MeshBuilder } from '../world/MeshBuilder';

const SKIN = '#d9a77c';
const JACKET = '#3f5a3a';
const SHIRT = '#b5a27a';
const PANTS = '#36404d';
const BOOTS = '#2a2420';
const CAP = '#8a2f2a';
const HIP_HEIGHT = 0.75;

function partMesh(build: (b: MeshBuilder) => void, material: THREE.Material): THREE.Mesh {
  const b = new MeshBuilder();
  build(b);
  const m = new THREE.Mesh(b.build(), material);
  m.castShadow = true;
  return m;
}

/**
 * Low-poly survivor model with simple procedural animation: walk cycle,
 * recoil, dodge-roll somersault and a red hurt flash.
 */
export class PlayerModel {
  readonly root = new THREE.Group();
  private readonly body = new THREE.Group();
  private readonly hips = new THREE.Group();
  private readonly torso: THREE.Mesh;
  private readonly head: THREE.Mesh;
  private readonly legL: THREE.Mesh;
  private readonly legR: THREE.Mesh;
  private readonly armL: THREE.Mesh;
  private readonly armR: THREE.Mesh;
  private readonly gunPivot = new THREE.Group();
  private readonly gun: THREE.Mesh;
  private readonly material: THREE.MeshLambertMaterial;
  private readonly weaponGeometries = new Map<WeaponId, { geometry: THREE.BufferGeometry; muzzle: number }>();
  private readonly ring: THREE.Mesh;
  muzzleOffset = 0.3;
  currentWeapon: WeaponId | null = null;
  private walkPhase = 0;

  constructor() {
    this.material = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
    const mat = this.material;

    this.legL = partMesh((b) => {
      b.box(0.2, 0.62, 0.24, PANTS, 0, -0.31, 0);
      b.box(0.22, 0.16, 0.32, BOOTS, 0, -0.66, 0.04);
    }, mat);
    this.legR = this.legL.clone();
    this.legL.position.set(-0.13, 0, 0);
    this.legR.position.set(0.13, 0, 0);

    this.torso = partMesh((b) => {
      b.box(0.56, 0.66, 0.34, JACKET, 0, 0.36, 0);
      b.box(0.2, 0.5, 0.36, SHIRT, 0, 0.4, 0.01);
      b.box(0.44, 0.52, 0.22, '#5a4a32', 0, 0.38, -0.27); // backpack
      b.box(0.46, 0.12, 0.24, '#4a3c2a', 0, 0.7, -0.27);
      b.box(0.58, 0.1, 0.36, '#2a2a2a', 0, 0.06, 0); // belt
    }, mat);
    this.torso.position.set(0, 0, 0);

    this.head = partMesh((b) => {
      b.box(0.3, 0.32, 0.3, SKIN, 0, 0.16, 0);
      b.box(0.33, 0.1, 0.33, CAP, 0, 0.33, 0);
      b.box(0.3, 0.04, 0.16, CAP, 0, 0.29, 0.2);
      b.box(0.31, 0.08, 0.05, '#222', 0, 0.2, 0.15);
    }, mat);
    this.head.position.set(0, 0.7, 0);
    this.torso.add(this.head);

    const arm = (b: MeshBuilder): void => {
      b.box(0.15, 0.48, 0.16, JACKET, 0, -0.22, 0);
      b.box(0.13, 0.12, 0.13, SKIN, 0, -0.5, 0);
    };
    this.armL = partMesh(arm, mat);
    this.armR = partMesh(arm, mat);
    this.armR.position.set(0.33, 0.6, 0.02);
    this.armL.position.set(-0.33, 0.6, 0.02);
    this.armR.rotation.set(-1.35, 0, 0.12);
    this.armL.rotation.set(-1.25, 0, 0.55);
    this.torso.add(this.armL, this.armR);

    this.gun = new THREE.Mesh(new THREE.BufferGeometry(), mat);
    this.gun.castShadow = true;
    this.gunPivot.position.set(0.12, 0.47, 0.42);
    this.gunPivot.add(this.gun);
    this.torso.add(this.gunPivot);

    // The hips group is the pivot for rolls and the death fall (about waist height).
    this.hips.position.y = HIP_HEIGHT;
    this.hips.add(this.legL, this.legR, this.torso);
    this.body.add(this.hips);
    this.root.add(this.body);

    // Subtle ring under the player for readability in crowds and darkness.
    const ringMat = new THREE.MeshBasicMaterial({ color: '#7dffb0', transparent: true, opacity: 0.35, depthWrite: false });
    this.ring = new THREE.Mesh(new THREE.RingGeometry(0.55, 0.68, 24), ringMat);
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.position.y = 0.04;
    this.root.add(this.ring);
  }

  setWeapon(id: WeaponId): void {
    let entry = this.weaponGeometries.get(id);
    if (!entry) {
      entry = buildWeaponGeometry(id);
      this.weaponGeometries.set(id, entry);
    }
    this.gun.geometry = entry.geometry;
    this.currentWeapon = id;
    this.muzzleOffset = entry.muzzle;
  }

  /** World-space muzzle position for the current facing. */
  muzzleWorld(x: number, z: number, facing: number, out: THREE.Vector3): THREE.Vector3 {
    const forward = 0.42 + this.muzzleOffset;
    const side = 0.12;
    const s = Math.sin(facing);
    const c = Math.cos(facing);
    out.set(x + s * forward + c * side, 1.22, z + c * forward - s * side);
    return out;
  }

  update(params: {
    x: number; z: number; facing: number; speed01: number; moveDot: number;
    rollT: number; rolling: boolean; recoil: number; hurt: number; reload: number; dt: number; alive: boolean; deathT: number;
  }): void {
    const p = params;
    this.root.position.set(p.x, 0, p.z);
    this.body.rotation.y = p.facing;

    if (!p.alive) {
      const t = Math.min(1, p.deathT / 0.6);
      this.body.rotation.x = 0;
      this.hips.rotation.x = -t * (Math.PI / 2) * 0.98;
      this.hips.position.y = HIP_HEIGHT - 0.55 * t;
      this.ring.visible = false;
      this.material.emissive.setRGB(0.25 * (1 - t), 0, 0);
      return;
    }
    this.ring.visible = true;

    this.walkPhase += p.dt * (4 + 7 * p.speed01) * (p.moveDot < -0.2 ? -1 : 1);
    const swing = Math.sin(this.walkPhase) * 0.75 * p.speed01;
    this.legL.rotation.x = swing;
    this.legR.rotation.x = -swing;
    const bob = Math.abs(Math.cos(this.walkPhase)) * 0.06 * p.speed01;

    if (p.rolling) {
      // Tuck and somersault forward around the body centre.
      const t = p.rollT;
      this.hips.rotation.x = t * Math.PI * 2;
      this.hips.position.y = HIP_HEIGHT - Math.sin(t * Math.PI) * 0.2;
      this.legL.rotation.x = -1.2;
      this.legR.rotation.x = -1.2;
    } else {
      this.hips.rotation.x = 0;
      this.hips.position.y = HIP_HEIGHT + bob;
    }
    this.torso.rotation.x = 0.08 * p.speed01 - p.recoil * 0.12;
    this.gunPivot.position.z = 0.42 - p.recoil * 0.08;
    // Reload: dip the gun and swing the left arm to the magazine.
    const r = p.reload > 0 ? Math.sin(p.reload * Math.PI) : 0;
    this.gunPivot.rotation.x = r * 0.7;
    this.armL.rotation.x = -1.25 + r * 0.8;

    this.material.emissive.setRGB(p.hurt * 0.9, p.hurt * 0.05, p.hurt * 0.05);
  }
}
