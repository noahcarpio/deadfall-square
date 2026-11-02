/**
 * Small, fast, seedable PRNG (mulberry32). Gameplay randomness goes through
 * this so runs can be reproduced in tests by fixing the seed.
 */
export class Rng {
  private state: number;

  constructor(seed: number = (Math.random() * 0xffffffff) >>> 0) {
    this.state = seed >>> 0;
  }

  reseed(seed: number): void {
    this.state = seed >>> 0;
  }

  /** Uniform float in [0, 1). */
  next(): number {
    let t = (this.state = (this.state + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** Uniform float in [min, max). */
  range(min: number, max: number): number {
    return min + (max - min) * this.next();
  }

  /** Uniform integer in [min, max] (inclusive). */
  int(min: number, max: number): number {
    return min + Math.floor(this.next() * (max - min + 1));
  }

  chance(p: number): boolean {
    return this.next() < p;
  }

  sign(): number {
    return this.next() < 0.5 ? -1 : 1;
  }

  pick<T>(items: readonly T[]): T {
    if (items.length === 0) throw new Error('Rng.pick on empty array');
    return items[Math.floor(this.next() * items.length)] as T;
  }

  /** Picks a key according to non-negative weights. */
  weighted<K extends string>(weights: Partial<Record<K, number>>): K {
    let total = 0;
    for (const k in weights) total += weights[k] ?? 0;
    if (total <= 0) throw new Error('Rng.weighted with zero total weight');
    let r = this.next() * total;
    let last: K | undefined;
    for (const k in weights) {
      const w = weights[k] ?? 0;
      if (w <= 0) continue;
      last = k;
      if (r < w) return k;
      r -= w;
    }
    return last as K;
  }

  shuffle<T>(items: T[]): T[] {
    for (let i = items.length - 1; i > 0; i--) {
      const j = Math.floor(this.next() * (i + 1));
      const tmp = items[i] as T;
      items[i] = items[j] as T;
      items[j] = tmp;
    }
    return items;
  }
}
