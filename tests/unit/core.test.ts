import { describe, expect, it } from 'vitest';
import { Rng } from '../../src/core/Rng';
import { SpatialHash } from '../../src/core/SpatialHash';
import { angleDamp, clamp, rayAabb, rayCircle, wrapAngle, formatTime } from '../../src/core/math';
import { EventBus } from '../../src/core/EventBus';

describe('Rng', () => {
  it('is deterministic for a given seed', () => {
    const a = new Rng(42);
    const b = new Rng(42);
    for (let i = 0; i < 100; i++) expect(a.next()).toBe(b.next());
  });

  it('produces values in range', () => {
    const r = new Rng(1);
    for (let i = 0; i < 1000; i++) {
      const v = r.int(3, 7);
      expect(v).toBeGreaterThanOrEqual(3);
      expect(v).toBeLessThanOrEqual(7);
    }
  });

  it('weighted() never picks zero-weight keys', () => {
    const r = new Rng(7);
    for (let i = 0; i < 500; i++) expect(r.weighted({ a: 1, b: 0, c: 3 })).not.toBe('b');
  });
});

describe('SpatialHash', () => {
  it('finds exactly the points within the radius', () => {
    const h = new SpatialHash(-50, -50, 50, 50, 2, 8);
    const pts: Array<[number, number]> = [];
    const rng = new Rng(3);
    for (let i = 0; i < 300; i++) pts.push([rng.range(-45, 45), rng.range(-45, 45)]);
    h.clear();
    pts.forEach(([x, z], i) => h.insert(i, x, z));
    const out: number[] = [];
    const n = h.query(5, -3, 7.5, out);
    const found = new Set(out.slice(0, n));
    pts.forEach(([x, z], i) => {
      const inside = Math.hypot(x - 5, z + 3) <= 7.5;
      expect(found.has(i)).toBe(inside);
    });
  });

  it('grows beyond its initial capacity', () => {
    const h = new SpatialHash(0, 0, 10, 10, 1, 2);
    for (let i = 0; i < 20; i++) h.insert(i, 5, 5);
    const out: number[] = [];
    expect(h.query(5, 5, 0.1, out)).toBe(20);
  });
});

describe('math', () => {
  it('wraps angles into (-PI, PI]', () => {
    expect(wrapAngle(Math.PI * 3)).toBeCloseTo(Math.PI);
    expect(wrapAngle(-Math.PI * 1.5)).toBeCloseTo(Math.PI / 2);
  });

  it('angleDamp takes the short way round', () => {
    const a = angleDamp(Math.PI - 0.1, -Math.PI + 0.1, 10, 0.016);
    expect(a).toBeGreaterThan(Math.PI - 0.1);
  });

  it('ray vs circle / aabb', () => {
    expect(rayCircle(0, 0, 1, 0, 5, 0, 1)).toBeCloseTo(4);
    expect(rayCircle(0, 0, -1, 0, 5, 0, 1)).toBe(-1);
    expect(rayAabb(0, 0, 0, 1, -1, 3, 1, 5)).toBeCloseTo(3);
    expect(rayAabb(0, 0, 1, 0, -1, 3, 1, 5)).toBe(-1);
  });

  it('clamp and formatTime', () => {
    expect(clamp(5, 0, 3)).toBe(3);
    expect(formatTime(125)).toBe('2:05');
  });
});

describe('EventBus', () => {
  it('delivers and unsubscribes', () => {
    const bus = new EventBus<{ ping: { n: number } }>();
    const got: number[] = [];
    const off = bus.on('ping', ({ n }) => got.push(n));
    bus.emit('ping', { n: 1 });
    off();
    bus.emit('ping', { n: 2 });
    expect(got).toEqual([1]);
  });
});
