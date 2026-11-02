import { describe, expect, it } from 'vitest';
import { CollisionWorld } from '../../src/world/Collision';
import { FlowField } from '../../src/world/FlowField';
import { CELL_SOLID, CELL_STRUCTURE, NavGrid } from '../../src/world/NavGrid';

function setup(): { col: CollisionWorld; grid: NavGrid; flow: FlowField } {
  const bounds = { minX: -20, minZ: -20, maxX: 20, maxZ: 20 };
  const col = new CollisionWorld(bounds);
  // A wall across the middle with a gap on the right (x in [10, 14]).
  col.addBox(-20, -1, 10, 1, 3);
  col.addBox(14, -1, 20, 1, 3);
  const grid = new NavGrid(bounds, 1);
  grid.rebuild(col.colliders, 0.4, (c) => c.owner === 'structure');
  return { col, grid, flow: new FlowField(grid) };
}

/** Follows the flow field from a start point; returns the final position. */
function walk(flow: FlowField, x: number, z: number, steps = 400): { x: number; z: number } {
  const dir = { x: 0, z: 0 };
  for (let i = 0; i < steps; i++) {
    if (!flow.sample(x, z, dir)) break;
    x += dir.x * 0.25;
    z += dir.z * 0.25;
  }
  return { x, z };
}

describe('NavGrid', () => {
  it('rasterises obstacles with inflation', () => {
    const { grid } = setup();
    expect(grid.get(grid.col(0), grid.row(0))).toBe(CELL_SOLID);
    expect(grid.get(grid.col(12), grid.row(0))).toBe(0);
    expect(grid.get(grid.col(0), grid.row(5))).toBe(0);
  });

  it('line of sight is blocked by walls', () => {
    const { grid } = setup();
    expect(grid.lineOfSight(0, -5, 0, 5)).toBe(false);
    expect(grid.lineOfSight(12, -5, 12, 5)).toBe(true);
  });

  it('marks structures separately', () => {
    const { col, grid } = setup();
    col.addBox(11, -1, 13, 1, 1.2, 'structure');
    grid.rebuild(col.colliders, 0.4, (c) => c.owner === 'structure');
    expect(grid.get(grid.col(12), grid.row(0))).toBe(CELL_STRUCTURE);
  });
});

describe('FlowField', () => {
  it('routes around a wall through the gap', () => {
    const { flow } = setup();
    flow.compute(0, 10);
    const end = walk(flow, -15, -10);
    expect(Math.hypot(end.x - 0, end.z - 10)).toBeLessThan(1.5);
    // Path length must exceed the straight-line distance (it detours via the gap).
    expect(flow.distanceAt(-15, -10)).toBeGreaterThan(Math.hypot(15, 20));
  });

  it('prefers breaking through structures only when no other path exists', () => {
    const { col, grid, flow } = setup();
    // Seal the gap with a structure: path must now go through it.
    col.addBox(10, -1, 14, 1, 1.2, 'structure');
    grid.rebuild(col.colliders, 0.4, (c) => c.owner === 'structure');
    flow.compute(0, 10);
    expect(Number.isFinite(flow.distanceAt(-15, -10))).toBe(true);
    // The path crosses the wall line through the structure (where zombies stop and attack it).
    const dir = { x: 0, z: 0 };
    let x = -15;
    let z = -10;
    let crossX = Number.NaN;
    for (let i = 0; i < 800 && flow.sample(x, z, dir); i++) {
      const nz = z + dir.z * 0.25;
      if (z < 0 && nz >= 0) crossX = x;
      x += dir.x * 0.25;
      z = nz;
    }
    expect(crossX).toBeGreaterThan(9.5);
    expect(crossX).toBeLessThan(14.5);
  });

  it('steers out of blocked cells toward reachable space', () => {
    const { flow } = setup();
    flow.compute(0, 10);
    const dir = { x: 0, z: 0 };
    expect(flow.sample(0, 0, dir)).toBe(true);
    expect(Math.hypot(dir.x, dir.z)).toBeCloseTo(1);
  });
});

describe('CollisionWorld', () => {
  it('pushes circles out of boxes and circles', () => {
    const col = new CollisionWorld({ minX: -10, minZ: -10, maxX: 10, maxZ: 10 });
    col.addBox(-1, -1, 1, 1, 2);
    col.addCircle(5, 5, 1, 2);
    const p = { x: 1.2, z: 0 };
    col.resolveCircle(p, 0.5);
    expect(p.x).toBeCloseTo(1.5);
    const q = { x: 5.5, z: 5 };
    col.resolveCircle(q, 0.5);
    expect(Math.hypot(q.x - 5, q.z - 5)).toBeCloseTo(1.5);
  });

  it('raycasts respect obstacle height', () => {
    const col = new CollisionWorld({ minX: -10, minZ: -10, maxX: 10, maxZ: 10 });
    col.addBox(3, -1, 4, 1, 0.8); // low: bullets pass over
    col.addBox(6, -1, 7, 1, 2.0); // tall: blocks
    const hit = { t: 0, collider: null };
    col.raycast(0, 0, 1, 0, 9, 1.25, hit);
    expect(hit.t).toBeCloseTo(6);
  });

  it('removes colliders', () => {
    const col = new CollisionWorld({ minX: -10, minZ: -10, maxX: 10, maxZ: 10 });
    const c = col.addBox(-1, -1, 1, 1, 2);
    expect(col.overlapsCircle(0, 0, 0.2)).toBe(true);
    col.remove(c);
    expect(col.overlapsCircle(0, 0, 0.2)).toBe(false);
  });
});
