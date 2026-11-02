export type QualityLevel = 'low' | 'medium' | 'high';

export interface QualityPreset {
  /** Upper bound for devicePixelRatio. */
  pixelRatioCap: number;
  shadows: boolean;
  shadowMapSize: number;
  /** Whether the player's flashlight casts shadows (expensive). */
  flashlightShadow: boolean;
  /** Whether zombies render into the shadow map. */
  zombieShadows: boolean;
  particleBudget: number;
  decalBudget: number;
  groundTextureSize: number;
  /** Far plane for fog/camera — lower draws less. */
  fogScale: number;
}

export const QUALITY_PRESETS: Record<QualityLevel, QualityPreset> = {
  low: {
    pixelRatioCap: 1,
    shadows: false,
    shadowMapSize: 512,
    flashlightShadow: false,
    zombieShadows: false,
    particleBudget: 500,
    decalBudget: 60,
    groundTextureSize: 1024,
    fogScale: 0.85,
  },
  medium: {
    pixelRatioCap: 1.5,
    shadows: true,
    shadowMapSize: 1024,
    flashlightShadow: false,
    zombieShadows: true,
    particleBudget: 1200,
    decalBudget: 120,
    groundTextureSize: 2048,
    fogScale: 1,
  },
  high: {
    pixelRatioCap: 2,
    shadows: true,
    shadowMapSize: 2048,
    flashlightShadow: true,
    zombieShadows: true,
    particleBudget: 2000,
    decalBudget: 200,
    groundTextureSize: 2048,
    fogScale: 1,
  },
};

export function isTouchDevice(): boolean {
  if (typeof window === 'undefined') return false;
  return window.matchMedia?.('(pointer: coarse)').matches || 'ontouchstart' in window;
}

export function defaultQuality(): QualityLevel {
  return isTouchDevice() ? 'low' : 'medium';
}
