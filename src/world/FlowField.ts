import { CELL_SOLID, CELL_STRUCTURE, type NavGrid } from './NavGrid';

const SQRT2 = Math.SQRT2;
/** Extra path cost for walking "through" a structure (i.e. breaking it). */
export const STRUCTURE_COST = 14;

const NEIGHBOURS: ReadonlyArray<readonly [number, number, number]> = [
  [1, 0, 1], [-1, 0, 1], [0, 1, 1], [0, -1, 1],
  [1, 1, SQRT2], [1, -1, SQRT2], [-1, 1, SQRT2], [-1, -1, SQRT2],
];

/** Binary min-heap keyed by float priority, storing integer cell indices. */
class IndexHeap {
  private keys: Float32Array;
  private vals: Int32Array;
  size = 0;

  constructor(capacity: number) {
    this.keys = new Float32Array(capacity);
    this.vals = new Int32Array(capacity);
  }

  push(key: number, val: number): void {
    if (this.size === this.keys.length) {
      const k = new Float32Array(this.keys.length * 2);
      k.set(this.keys);
      const v = new Int32Array(this.vals.length * 2);
      v.set(this.vals);
      this.keys = k;
      this.vals = v;
    }
    let i = this.size++;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if ((this.keys[p] as number) <= key) break;
      this.keys[i] = this.keys[p] as number;
      this.vals[i] = this.vals[p] as number;
      i = p;
    }
    this.keys[i] = key;
    this.vals[i] = val;
  }

  /** Pops the minimum; writes its key to `lastKey`. */
  lastKey = 0;
  pop(): number {
    const top = this.vals[0] as number;
    this.lastKey = this.keys[0] as number;
    const n = --this.size;
    if (n > 0) {
      const key = this.keys[n] as number;
      const val = this.vals[n] as number;
      let i = 0;
      for (;;) {
        let c = 2 * i + 1;
        if (c >= n) break;
        if (c + 1 < n && (this.keys[c + 1] as number) < (this.keys[c] as number)) c++;
        if ((this.keys[c] as number) >= key) break;
        this.keys[i] = this.keys[c] as number;
        this.vals[i] = this.vals[c] as number;
        i = c;
      }
      this.keys[i] = key;
      this.vals[i] = val;
    }
    return top;
  }
}

/**
 * Dijkstra flow field toward a single target. Every agent samples the field in
 * O(1), so hundreds of zombies path around obstacles for the cost of one search.
 */
export class FlowField {
  readonly dist: Float32Array;
  readonly dirX: Float32Array;
  readonly dirZ: Float32Array;
  private readonly heap: IndexHeap;
  targetIndex = -1;
  /** Incremented each time the field is recomputed. */
  version = 0;

  constructor(readonly grid: NavGrid) {
    this.dist = new Float32Array(grid.size);
    this.dirX = new Float32Array(grid.size);
    this.dirZ = new Float32Array(grid.size);
    this.heap = new IndexHeap(grid.size * 2);
  }

  compute(targetX: number, targetZ: number): void {
    const g = this.grid;
    const cols = g.cols;
    const rows = g.rows;
    const cells = g.cells;
    const dist = this.dist;
    dist.fill(Infinity);
    const start = g.indexAt(targetX, targetZ);
    this.targetIndex = start;
    dist[start] = 0;
    const heap = this.heap;
    heap.size = 0;
    heap.push(0, start);

    while (heap.size > 0) {
      const i = heap.pop();
      const d = heap.lastKey;
      if (d > (dist[i] as number)) continue;
      const c = i % cols;
      const r = (i - c) / cols;
      for (let n = 0; n < 8; n++) {
        const nb = NEIGHBOURS[n] as readonly [number, number, number];
        const nc = c + nb[0];
        const nr = r + nb[1];
        if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
        const ni = nr * cols + nc;
        const cell = cells[ni] as number;
        if (cell === CELL_SOLID) continue;
        if (nb[0] !== 0 && nb[1] !== 0) {
          // No diagonal corner cutting.
          if ((cells[r * cols + nc] as number) === CELL_SOLID || (cells[nr * cols + c] as number) === CELL_SOLID) continue;
        }
        const nd = d + nb[2] + (cell === CELL_STRUCTURE ? STRUCTURE_COST : 0);
        if (nd < (dist[ni] as number)) {
          dist[ni] = nd;
          heap.push(nd, ni);
        }
      }
    }
    this.buildDirections();
    this.version++;
  }

  private buildDirections(): void {
    const g = this.grid;
    const cols = g.cols;
    const rows = g.rows;
    const dist = this.dist;
    const cells = g.cells;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c;
        let best = dist[i] as number;
        let bx = 0;
        let bz = 0;
        for (let n = 0; n < 8; n++) {
          const nb = NEIGHBOURS[n] as readonly [number, number, number];
          const nc = c + nb[0];
          const nr = r + nb[1];
          if (nc < 0 || nr < 0 || nc >= cols || nr >= rows) continue;
          if (nb[0] !== 0 && nb[1] !== 0) {
            if ((cells[r * cols + nc] as number) === CELL_SOLID || (cells[nr * cols + c] as number) === CELL_SOLID) continue;
          }
          const nd = dist[nr * cols + nc] as number;
          if (nd < best) {
            best = nd;
            bx = nb[0];
            bz = nb[1];
          }
        }
        const len = Math.hypot(bx, bz) || 1;
        this.dirX[i] = bx / len;
        this.dirZ[i] = bz / len;
      }
    }
  }

  /** Path distance (in cells) from a world position to the target; Infinity if unreachable. */
  distanceAt(x: number, z: number): number {
    return this.dist[this.grid.indexAt(x, z)] as number;
  }

  /**
   * Writes the steering direction at a world position into `out`. If the
   * position sits in a blocked cell (agents can be shoved into the inflated
   * margin), steers toward the best reachable neighbouring cell instead.
   * Returns false if no direction is available (at target or unreachable).
   */
  sample(x: number, z: number, out: { x: number; z: number }): boolean {
    const g = this.grid;
    const i = g.indexAt(x, z);
    const d = this.dist[i] as number;
    if (d === 0) return false;
    if (d !== Infinity) {
      out.x = this.dirX[i] as number;
      out.z = this.dirZ[i] as number;
      return out.x !== 0 || out.z !== 0;
    }
    const c = Math.min(g.cols - 1, Math.max(0, g.col(x)));
    const r = Math.min(g.rows - 1, Math.max(0, g.row(z)));
    let best = Infinity;
    let tx = 0;
    let tz = 0;
    for (let dr = -2; dr <= 2; dr++) {
      for (let dc = -2; dc <= 2; dc++) {
        const nc = c + dc;
        const nr = r + dr;
        if (!g.inBounds(nc, nr)) continue;
        const nd = (this.dist[nr * g.cols + nc] as number) + Math.hypot(dc, dr);
        if (nd < best) {
          best = nd;
          tx = g.centerX(nc);
          tz = g.centerZ(nr);
        }
      }
    }
    if (best === Infinity) return false;
    const dx = tx - x;
    const dz = tz - z;
    const len = Math.hypot(dx, dz) || 1;
    out.x = dx / len;
    out.z = dz / len;
    return true;
  }
}
