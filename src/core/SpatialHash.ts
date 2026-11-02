/**
 * Uniform-grid spatial hash for points on the XZ plane. It is rebuilt every
 * simulation step (clear + insert), which is O(n) and allocation-free thanks
 * to an intrusive linked list stored in typed arrays.
 */
export class SpatialHash {
  readonly cellSize: number;
  private readonly minX: number;
  private readonly minZ: number;
  private readonly cols: number;
  private readonly rows: number;
  private readonly heads: Int32Array;
  private next: Int32Array;
  private xs: Float32Array;
  private zs: Float32Array;

  constructor(minX: number, minZ: number, maxX: number, maxZ: number, cellSize: number, capacity = 512) {
    this.cellSize = cellSize;
    this.minX = minX;
    this.minZ = minZ;
    this.cols = Math.ceil((maxX - minX) / cellSize);
    this.rows = Math.ceil((maxZ - minZ) / cellSize);
    this.heads = new Int32Array(this.cols * this.rows).fill(-1);
    this.next = new Int32Array(capacity);
    this.xs = new Float32Array(capacity);
    this.zs = new Float32Array(capacity);
  }

  clear(): void {
    this.heads.fill(-1);
  }

  private cellIndex(x: number, z: number): number {
    let cx = Math.floor((x - this.minX) / this.cellSize);
    let cz = Math.floor((z - this.minZ) / this.cellSize);
    if (cx < 0) cx = 0; else if (cx >= this.cols) cx = this.cols - 1;
    if (cz < 0) cz = 0; else if (cz >= this.rows) cz = this.rows - 1;
    return cz * this.cols + cx;
  }

  /** Inserts item `id` (a dense index, 0..capacity) at the given position. */
  insert(id: number, x: number, z: number): void {
    if (id >= this.next.length) this.grow(Math.max(id + 1, this.next.length * 2));
    const c = this.cellIndex(x, z);
    this.xs[id] = x;
    this.zs[id] = z;
    this.next[id] = this.heads[c] as number;
    this.heads[c] = id;
  }

  /**
   * Writes ids of items within `radius` of (x, z) into `out` and returns the count.
   * `out` is reused by callers to avoid allocations.
   */
  query(x: number, z: number, radius: number, out: number[]): number {
    let count = 0;
    const r2 = radius * radius;
    const cs = this.cellSize;
    const x0 = Math.max(0, Math.floor((x - radius - this.minX) / cs));
    const x1 = Math.min(this.cols - 1, Math.floor((x + radius - this.minX) / cs));
    const z0 = Math.max(0, Math.floor((z - radius - this.minZ) / cs));
    const z1 = Math.min(this.rows - 1, Math.floor((z + radius - this.minZ) / cs));
    for (let cz = z0; cz <= z1; cz++) {
      for (let cx = x0; cx <= x1; cx++) {
        let id = this.heads[cz * this.cols + cx] as number;
        while (id !== -1) {
          const dx = (this.xs[id] as number) - x;
          const dz = (this.zs[id] as number) - z;
          if (dx * dx + dz * dz <= r2) out[count++] = id;
          id = this.next[id] as number;
        }
      }
    }
    return count;
  }

  private grow(capacity: number): void {
    const next = new Int32Array(capacity);
    next.set(this.next);
    const xs = new Float32Array(capacity);
    xs.set(this.xs);
    const zs = new Float32Array(capacity);
    zs.set(this.zs);
    this.next = next;
    this.xs = xs;
    this.zs = zs;
  }
}
