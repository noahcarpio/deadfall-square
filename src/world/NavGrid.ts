import type { Collider } from './Collision';

export const CELL_FREE = 0;
export const CELL_SOLID = 1;
/** Occupied by a player-built structure: walkable for path costs, but blocks movement until destroyed. */
export const CELL_STRUCTURE = 2;

export interface NavBounds {
  minX: number;
  minZ: number;
  maxX: number;
  maxZ: number;
}

/**
 * Walkability grid used by the flow field. Obstacles are rasterised with an
 * inflation radius so paths keep zombies' bodies clear of corners.
 */
export class NavGrid {
  readonly cols: number;
  readonly rows: number;
  readonly cells: Uint8Array;

  constructor(readonly bounds: NavBounds, readonly cellSize = 1) {
    this.cols = Math.round((bounds.maxX - bounds.minX) / cellSize);
    this.rows = Math.round((bounds.maxZ - bounds.minZ) / cellSize);
    this.cells = new Uint8Array(this.cols * this.rows);
  }

  get size(): number {
    return this.cols * this.rows;
  }

  col(x: number): number {
    return Math.floor((x - this.bounds.minX) / this.cellSize);
  }

  row(z: number): number {
    return Math.floor((z - this.bounds.minZ) / this.cellSize);
  }

  inBounds(col: number, row: number): boolean {
    return col >= 0 && row >= 0 && col < this.cols && row < this.rows;
  }

  index(col: number, row: number): number {
    return row * this.cols + col;
  }

  /** Cell index for a world position, clamped to the grid. */
  indexAt(x: number, z: number): number {
    const c = Math.min(this.cols - 1, Math.max(0, this.col(x)));
    const r = Math.min(this.rows - 1, Math.max(0, this.row(z)));
    return r * this.cols + c;
  }

  centerX(col: number): number {
    return this.bounds.minX + (col + 0.5) * this.cellSize;
  }

  centerZ(row: number): number {
    return this.bounds.minZ + (row + 0.5) * this.cellSize;
  }

  get(col: number, row: number): number {
    if (!this.inBounds(col, row)) return CELL_SOLID;
    return this.cells[row * this.cols + col] as number;
  }

  /** Rasterises all colliders (inflated by `inflate`). `isStructure` tags player-built obstacles. */
  rebuild(colliders: readonly Collider[], inflate: number, isStructure: (c: Collider) => boolean): void {
    this.cells.fill(CELL_FREE);
    for (const c of colliders) {
      const value = isStructure(c) ? CELL_STRUCTURE : CELL_SOLID;
      if (c.kind === 'box') {
        this.fillRect(c.minX - inflate, c.minZ - inflate, c.maxX + inflate, c.maxZ + inflate, value);
      } else {
        this.fillCircle(c.x, c.z, c.r + inflate, value);
      }
    }
  }

  private write(i: number, value: number): void {
    // Solid always wins over structure.
    if ((this.cells[i] as number) !== CELL_SOLID) this.cells[i] = value;
  }

  private fillRect(minX: number, minZ: number, maxX: number, maxZ: number, value: number): void {
    // A cell is blocked if its centre lies inside the inflated rectangle.
    const c0 = Math.max(0, Math.ceil((minX - this.bounds.minX) / this.cellSize - 0.5));
    const c1 = Math.min(this.cols - 1, Math.floor((maxX - this.bounds.minX) / this.cellSize - 0.5));
    const r0 = Math.max(0, Math.ceil((minZ - this.bounds.minZ) / this.cellSize - 0.5));
    const r1 = Math.min(this.rows - 1, Math.floor((maxZ - this.bounds.minZ) / this.cellSize - 0.5));
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) this.write(r * this.cols + c, value);
  }

  private fillCircle(x: number, z: number, radius: number, value: number): void {
    const c0 = Math.max(0, this.col(x - radius));
    const c1 = Math.min(this.cols - 1, this.col(x + radius));
    const r0 = Math.max(0, this.row(z - radius));
    const r1 = Math.min(this.rows - 1, this.row(z + radius));
    const r2 = radius * radius;
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const dx = this.centerX(c) - x;
        const dz = this.centerZ(r) - z;
        if (dx * dx + dz * dz <= r2) this.write(r * this.cols + c, value);
      }
    }
  }

  /** Grid line-of-sight test (sampled every quarter cell). Structures block sight when `structuresBlock`. */
  lineOfSight(ax: number, az: number, bx: number, bz: number, structuresBlock = true): boolean {
    const dx = bx - ax;
    const dz = bz - az;
    const len = Math.hypot(dx, dz);
    const steps = Math.ceil(len / (this.cellSize * 0.25));
    for (let i = 1; i < steps; i++) {
      const t = i / steps;
      const v = this.get(this.col(ax + dx * t), this.row(az + dz * t));
      if (v === CELL_SOLID || (structuresBlock && v === CELL_STRUCTURE)) return false;
    }
    return true;
  }
}
