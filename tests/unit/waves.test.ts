import { describe, expect, it } from 'vitest';
import { ZOMBIES } from '../../src/config/zombies';
import {
  damageMultiplier, hpMultiplier, isBossWave, isPerkWave, maxAlive, spawnInterval, typeWeights, waveBudget,
} from '../../src/config/waves';
import { Rng } from '../../src/core/Rng';
import { buildComposition } from '../../src/waves/WaveDirector';

/** Rough "threat" score of a wave: total effective HP x damage pressure. */
function threat(wave: number): number {
  const comp = buildComposition(wave, new Rng(wave));
  const hp = comp.reduce((s, t) => s + ZOMBIES[t].hp, 0) * hpMultiplier(wave);
  return hp * damageMultiplier(wave);
}

describe('wave composition', () => {
  it('wave 1 is a small group of walkers only', () => {
    const comp = buildComposition(1, new Rng(1));
    expect(comp.length).toBeGreaterThanOrEqual(10);
    expect(comp.length).toBeLessThanOrEqual(14);
    expect(new Set(comp)).toEqual(new Set(['walker']));
  });

  it('introduces each type at its unlock wave', () => {
    expect(buildComposition(2, new Rng(2))).toContain('runner');
    expect(buildComposition(3, new Rng(3))).toContain('spitter');
    expect(buildComposition(4, new Rng(4))).toContain('exploder');
    expect(buildComposition(6, new Rng(6))).toContain('brute');
    expect(typeWeights(5).brute).toBe(0);
  });

  it('never contains bosses (they are spawned separately)', () => {
    for (let w = 1; w <= 30; w++) expect(buildComposition(w, new Rng(w))).not.toContain('boss');
  });

  it('spends roughly the whole budget', () => {
    for (const w of [1, 5, 10, 20]) {
      const comp = buildComposition(w, new Rng(w));
      const spent = comp.reduce((s, t) => s + ZOMBIES[t].cost, 0);
      const budget = waveBudget(w) * (isBossWave(w) ? 0.6 : 1);
      expect(spent).toBeGreaterThan(budget - 1.5);
      expect(spent).toBeLessThan(budget + 1.5);
    }
  });
});

describe('difficulty curve', () => {
  it('threat grows monotonically (excluding boss-wave dips)', () => {
    const nonBoss = Array.from({ length: 24 }, (_, i) => i + 1).filter((w) => !isBossWave(w));
    for (let i = 1; i < nonBoss.length; i++) {
      expect(threat(nonBoss[i] as number)).toBeGreaterThan(threat(nonBoss[i - 1] as number));
    }
  });

  it('wave 10 is several times harder than wave 1, wave 20 much harder still', () => {
    expect(threat(10) / threat(1)).toBeGreaterThan(10);
    expect(threat(21) / threat(10)).toBeGreaterThan(3);
  });

  it('spawn pacing tightens and the alive cap rises', () => {
    expect(spawnInterval(20)).toBeLessThan(spawnInterval(1));
    expect(maxAlive(20, 140)).toBeGreaterThan(maxAlive(1, 140));
    expect(maxAlive(50, 140)).toBe(140);
  });

  it('boss every 5 waves, perk every 3', () => {
    expect([5, 10, 15].every(isBossWave)).toBe(true);
    expect(isBossWave(4)).toBe(false);
    expect([3, 6, 9].every(isPerkWave)).toBe(true);
  });
});
