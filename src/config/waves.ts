import type { ZombieType } from './zombies';

/**
 * Wave difficulty curves. All balance knobs for the wave director live here.
 * Wave 1 is a gentle trickle of walkers; by wave 10 every type is in play with
 * ~2.4x health; wave 20+ fields 150+ tough zombies with very short spawn gaps.
 */
export const WAVE = {
  /** Seconds the "wave cleared" banner shows before the perk/shop screens. */
  clearDelay: 2.5,
  /** Countdown before the next wave starts after leaving the shop. */
  countdown: 3,
  /** A perk choice is offered after clearing every Nth wave. */
  perkEvery: 3,
  /** A boss appears every Nth wave. */
  bossEvery: 5,
};

export function waveBudget(wave: number): number {
  return 8 + 4 * wave + 0.35 * wave * wave;
}

export function isBossWave(wave: number): boolean {
  return wave > 0 && wave % WAVE.bossEvery === 0;
}

export function isPerkWave(wave: number): boolean {
  return wave > 0 && wave % WAVE.perkEvery === 0;
}

/** Relative spawn weights per zombie type for a wave (types unlock progressively). */
export function typeWeights(wave: number): Partial<Record<ZombieType, number>> {
  return {
    walker: Math.max(2, 10 - wave * 0.35),
    runner: wave >= 2 ? Math.min(6, 1.2 + (wave - 2) * 0.55) : 0,
    spitter: wave >= 3 ? Math.min(3.5, 0.9 + (wave - 3) * 0.3) : 0,
    exploder: wave >= 4 ? Math.min(3.5, 0.9 + (wave - 4) * 0.3) : 0,
    brute: wave >= 6 ? Math.min(3, 0.5 + (wave - 6) * 0.28) : 0,
  };
}

export function hpMultiplier(wave: number): number {
  const w = wave - 1;
  return 1 + 0.1 * w + 0.006 * w * w;
}

export function damageMultiplier(wave: number): number {
  return 1 + 0.055 * (wave - 1);
}

export function speedMultiplier(wave: number): number {
  return Math.min(1.3, 1 + 0.015 * (wave - 1));
}

/** Seconds between spawn groups. */
export function spawnInterval(wave: number): number {
  return Math.max(0.22, 1.35 - 0.065 * (wave - 1));
}

export function spawnGroupSize(wave: number): number {
  return 1 + Math.floor(wave / 4);
}

/** Maximum simultaneously alive zombies. */
export function maxAlive(wave: number, cap: number): number {
  return Math.min(cap, 16 + 6 * wave);
}

/** Boss health multiplier for the k-th boss (k = wave / 5). */
export function bossHpMultiplier(wave: number): number {
  const k = Math.max(1, Math.floor(wave / WAVE.bossEvery));
  return 1 + 0.75 * (k - 1);
}

/** Coins awarded for clearing a wave. */
export function waveClearBonus(wave: number): number {
  return 25 + 6 * wave;
}
