import * as THREE from 'three';
import { damp } from '../core/math';

const OFFSET = new THREE.Vector3(0, 20, 12.5);

/**
 * Angled top-down follow camera with aim look-ahead, trauma-based screen
 * shake, an attract-mode orbit for the menu, and screen <-> ground projection.
 */
export class CameraRig {
  readonly camera: THREE.PerspectiveCamera;
  private readonly focus = new THREE.Vector3();
  private readonly raycaster = new THREE.Raycaster();
  private readonly ndc = new THREE.Vector2();
  private readonly plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
  private readonly hit = new THREE.Vector3();
  private readonly projected = new THREE.Vector3();
  private readonly projectOut = { x: 0, y: 0, visible: false };
  private shakeTime = 0;
  private distanceScale = 1;

  constructor(aspect: number) {
    this.camera = new THREE.PerspectiveCamera(45, aspect, 1, 140);
    this.camera.position.copy(OFFSET);
    this.camera.lookAt(0, 0, 0);
  }

  resize(aspect: number): void {
    this.camera.aspect = aspect;
    // Portrait screens (phones) pull back so the play area stays readable.
    this.distanceScale = aspect < 1 ? Math.min(1.45, 1 + (1 - aspect) * 0.8) : 1;
    this.camera.updateProjectionMatrix();
  }

  /** Snaps the camera to a focus point (no smoothing), e.g. on new game. */
  snapTo(x: number, z: number): void {
    this.focus.set(x, 0, z);
    this.camera.position.set(x + OFFSET.x, OFFSET.y * this.distanceScale, z + OFFSET.z * this.distanceScale);
    this.camera.lookAt(this.focus);
  }

  follow(x: number, z: number, lookX: number, lookZ: number, trauma: number, dt: number): void {
    const tx = x + lookX;
    const tz = z + lookZ;
    this.focus.x = damp(this.focus.x, tx, 7, dt);
    this.focus.z = damp(this.focus.z, tz, 7, dt);
    this.focus.y = 0;
    this.camera.position.set(this.focus.x + OFFSET.x, OFFSET.y * this.distanceScale, this.focus.z + OFFSET.z * this.distanceScale);
    this.camera.lookAt(this.focus);
    this.applyShake(trauma, dt);
  }

  orbit(time: number): void {
    const a = time * 0.05;
    const r = 34;
    this.camera.position.set(Math.sin(a) * r, 20, Math.cos(a) * r);
    this.focus.set(0, 0, 0);
    this.camera.lookAt(0, 1, 0);
  }

  private applyShake(trauma: number, dt: number): void {
    if (trauma <= 0) return;
    this.shakeTime += dt;
    const s = trauma * trauma;
    const t = this.shakeTime * 28;
    const ox = (Math.sin(t * 1.1) + Math.sin(t * 2.3 + 1.7)) * 0.5 * s * 0.9;
    const oy = (Math.sin(t * 1.7 + 0.4) + Math.sin(t * 3.1)) * 0.5 * s * 0.6;
    const rz = Math.sin(t * 1.3 + 2.1) * s * 0.035;
    this.camera.position.x += ox;
    this.camera.position.y += oy;
    this.camera.rotateZ(rz);
  }

  /** Intersects a screen point (CSS pixels) with the horizontal plane at `height`. */
  screenToGround(sx: number, sy: number, width: number, height: number, planeHeight: number, out: THREE.Vector3): THREE.Vector3 | null {
    this.ndc.set((sx / width) * 2 - 1, -(sy / height) * 2 + 1);
    this.raycaster.setFromCamera(this.ndc, this.camera);
    this.plane.constant = -planeHeight;
    const p = this.raycaster.ray.intersectPlane(this.plane, this.hit);
    if (!p) return null;
    return out.copy(p);
  }

  /** Projects a world point to normalised screen coordinates (0..1). */
  project(x: number, y: number, z: number): { x: number; y: number; visible: boolean } {
    this.projected.set(x, y, z).project(this.camera);
    const o = this.projectOut;
    o.x = (this.projected.x + 1) / 2;
    o.y = (1 - this.projected.y) / 2;
    o.visible = this.projected.z < 1 && o.x > -0.1 && o.x < 1.1 && o.y > -0.1 && o.y < 1.1;
    return o;
  }
}
