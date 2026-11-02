import * as THREE from 'three';
import { clamp, lerp, smoothstep } from '../core/math';
import type { QualityPreset } from '../config/quality';

interface SkyKey {
  at: number;
  sun: THREE.Color;
  sunIntensity: number;
  sunElevation: number;
  hemiSky: THREE.Color;
  hemiGround: THREE.Color;
  hemiIntensity: number;
  fog: THREE.Color;
  fogNear: number;
  fogFar: number;
}

const KEYS: SkyKey[] = [
  { at: 0, sun: new THREE.Color('#fff1d6'), sunIntensity: 2.6, sunElevation: 1.0, hemiSky: new THREE.Color('#c4d6e6'), hemiGround: new THREE.Color('#5e554a'), hemiIntensity: 1.3, fog: new THREE.Color('#a7b2b8'), fogNear: 45, fogFar: 110 },
  { at: 0.45, sun: new THREE.Color('#ff9a5c'), sunIntensity: 2.0, sunElevation: 0.45, hemiSky: new THREE.Color('#d39a86'), hemiGround: new THREE.Color('#3d2f2c'), hemiIntensity: 0.85, fog: new THREE.Color('#7a5c5a'), fogNear: 38, fogFar: 95 },
  { at: 0.75, sun: new THREE.Color('#9c8cff'), sunIntensity: 0.7, sunElevation: 0.6, hemiSky: new THREE.Color('#4a4f7a'), hemiGround: new THREE.Color('#15141c'), hemiIntensity: 0.55, fog: new THREE.Color('#262a40'), fogNear: 32, fogFar: 82 },
  { at: 1, sun: new THREE.Color('#8fa8ff'), sunIntensity: 0.45, sunElevation: 0.9, hemiSky: new THREE.Color('#33405e'), hemiGround: new THREE.Color('#0c0e14'), hemiIntensity: 0.42, fog: new THREE.Color('#0d1220'), fogNear: 30, fogFar: 74 },
];

/**
 * Owns every light in the scene. The light count never changes at runtime
 * (only intensities do) so three.js never has to recompile shaders mid-game.
 */
export class Lighting {
  readonly hemi: THREE.HemisphereLight;
  readonly sun: THREE.DirectionalLight;
  readonly flashlight: THREE.SpotLight;
  readonly muzzle: THREE.PointLight;
  readonly blast: THREE.PointLight;
  readonly fog: THREE.Fog;
  /** 0 = day, 1 = deep night. */
  night = 0;
  flashlightOn = false;
  private muzzleIntensity = 0;
  private blastIntensity = 0;
  private fogScale = 1;
  private readonly sunDir = new THREE.Vector3();

  constructor(private readonly scene: THREE.Scene) {
    this.hemi = new THREE.HemisphereLight('#c4d6e6', '#5e554a', 1.2);
    scene.add(this.hemi);

    this.sun = new THREE.DirectionalLight('#fff1d6', 2.5);
    this.sun.shadow.camera.left = -26;
    this.sun.shadow.camera.right = 26;
    this.sun.shadow.camera.top = 26;
    this.sun.shadow.camera.bottom = -26;
    this.sun.shadow.camera.near = 1;
    this.sun.shadow.camera.far = 90;
    this.sun.shadow.bias = -0.0008;
    this.sun.shadow.normalBias = 0.03;
    scene.add(this.sun, this.sun.target);

    this.flashlight = new THREE.SpotLight('#fff4dd', 0, 30, 0.5, 0.55, 1.6);
    this.flashlight.shadow.mapSize.set(512, 512);
    this.flashlight.shadow.bias = -0.002;
    this.flashlight.shadow.camera.near = 0.5;
    this.flashlight.shadow.camera.far = 30;
    scene.add(this.flashlight, this.flashlight.target);

    this.muzzle = new THREE.PointLight('#ffc46b', 0, 9, 2);
    scene.add(this.muzzle);
    this.blast = new THREE.PointLight('#ff8a3a', 0, 18, 2);
    scene.add(this.blast);

    this.fog = new THREE.Fog('#a7b2b8', 45, 110);
    scene.fog = this.fog;
    scene.background = new THREE.Color('#a7b2b8');
  }

  applyQuality(q: QualityPreset): void {
    this.sun.castShadow = q.shadows;
    if (this.sun.shadow.mapSize.x !== q.shadowMapSize) {
      this.sun.shadow.mapSize.set(q.shadowMapSize, q.shadowMapSize);
      this.sun.shadow.map?.dispose();
      this.sun.shadow.map = null;
    }
    this.flashlight.castShadow = q.shadows && q.flashlightShadow;
    this.fogScale = q.fogScale;
    this.setNight(this.night);
  }

  setNight(n: number): void {
    this.night = clamp(n, 0, 1);
    let a = KEYS[0] as SkyKey;
    let b = KEYS[KEYS.length - 1] as SkyKey;
    for (let i = 0; i < KEYS.length - 1; i++) {
      const k0 = KEYS[i] as SkyKey;
      const k1 = KEYS[i + 1] as SkyKey;
      if (this.night >= k0.at && this.night <= k1.at) {
        a = k0;
        b = k1;
        break;
      }
    }
    const t = b.at === a.at ? 0 : (this.night - a.at) / (b.at - a.at);
    this.sun.color.copy(a.sun).lerp(b.sun, t);
    this.sun.intensity = lerp(a.sunIntensity, b.sunIntensity, t);
    const elev = lerp(a.sunElevation, b.sunElevation, t);
    this.sunDir.set(-0.55, Math.sin(elev) * 1.4 + 0.25, 0.35).normalize();
    this.hemi.color.copy(a.hemiSky).lerp(b.hemiSky, t);
    this.hemi.groundColor.copy(a.hemiGround).lerp(b.hemiGround, t);
    this.hemi.intensity = lerp(a.hemiIntensity, b.hemiIntensity, t);
    this.fog.color.copy(a.fog).lerp(b.fog, t);
    this.fog.near = lerp(a.fogNear, b.fogNear, t) * this.fogScale;
    this.fog.far = lerp(a.fogFar, b.fogFar, t) * this.fogScale;
    (this.scene.background as THREE.Color).copy(this.fog.color);
    this.flashlightOn = this.night > 0.35;
  }

  /** Keeps the shadow frustum centred on the focus point, snapped to texels to avoid shimmer. */
  follow(x: number, z: number): void {
    const texel = 52 / this.sun.shadow.mapSize.x;
    const sx = Math.round(x / texel) * texel;
    const sz = Math.round(z / texel) * texel;
    this.sun.target.position.set(sx, 0, sz);
    this.sun.position.set(sx + this.sunDir.x * 50, this.sunDir.y * 50, sz + this.sunDir.z * 50);
  }

  /** Positions the flashlight at the player's gun, pointing along the aim direction. */
  aimFlashlight(x: number, y: number, z: number, dirX: number, dirZ: number): void {
    this.flashlight.position.set(x, y, z);
    this.flashlight.target.position.set(x + dirX * 10, 0, z + dirZ * 10);
    const target = this.flashlightOn ? smoothstep(0.35, 0.8, this.night) * 140 + 20 : 0;
    this.flashlight.intensity += (target - this.flashlight.intensity) * 0.15;
  }

  flashMuzzle(x: number, y: number, z: number, strength: number): void {
    this.muzzle.position.set(x, y, z);
    this.muzzleIntensity = Math.max(this.muzzleIntensity, strength);
  }

  flashBlast(x: number, z: number, strength: number): void {
    this.blast.position.set(x, 2.5, z);
    this.blastIntensity = Math.max(this.blastIntensity, strength);
  }

  update(dt: number): void {
    this.muzzleIntensity *= Math.exp(-dt * 30);
    this.blastIntensity *= Math.exp(-dt * 7);
    const nightBoost = 0.6 + this.night * 0.8;
    this.muzzle.intensity = this.muzzleIntensity < 0.05 ? 0 : this.muzzleIntensity * nightBoost;
    this.blast.intensity = this.blastIntensity < 0.05 ? 0 : this.blastIntensity * nightBoost;
  }

  reset(): void {
    this.muzzleIntensity = 0;
    this.blastIntensity = 0;
    this.flashlight.intensity = 0;
  }
}
