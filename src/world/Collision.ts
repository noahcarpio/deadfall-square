import { rayAabb, rayCircle } from '../core/math';

export interface BoxCollider {
  readonly kind: 'box';
  minX: number;
  minZ: number;
  maxX: number;
  maxZ: number;
  /** World height; bullets fly at BULLET_HEIGHT and pass over anything lower. */
  height: number;
  /** Optional gameplay owner (e.g. a placed structure). */
  owner: unknown;
  stamp: number;
}

export interface CircleCollider {
  readonly kind: 'circle';
  x: number;
  z: number;
  r: number;
  height: number;
  owner: unknown;
  stamp: number;
}

export type Collider = BoxCollider | CircleCollider;

/** Height at which bullets travel; obstacles lower than this do not block shots. */
export const BULLET_HEIGHT = 1.25;

export interface MutablePoint {
  x: number;
  z: number;
}

export interface RayHit {
  t: number;
  collider: Collider | null;
}

/**
 * Static + dynamic obstacle set on the XZ plane with a uniform broadphase grid.
 * Supports circle push-out (movement), ray casts (bullets) and overlap tests (placement).
 */
export class CollisionWorld {
  readonly colliders: Collider[] = [];
  private readonly cellSize = 4;
  private readonly minX: number;
  private readonly minZ: number;
  private readonly cols: number;
  private readonly rows: number;
  private cells: Collider[][];
  private stampCounter = 1;
  private readonly scratch: Collider[] = [];

  constructor(readonly bounds: { minX: number; minZ: number; maxX: number; maxZ: number }) {
    this.minX = bounds.minX;
    this.minZ = bounds.minZ;
    this.cols = Math.ceil((bounds.maxX - bounds.minX) / this.cellSize);
    this.rows = Math.ceil((bounds.maxZ - bounds.minZ) / this.cellSize);
    this.cells = Array.from({ length: this.cols * this.rows }, () => []);
  }

  addBox(minX: number, minZ: number, maxX: number, maxZ: number, height: number, owner: unknown = null): BoxCollider {
    const c: BoxCollider = { kind: 'box', minX, minZ, maxX, maxZ, height, owner, stamp: 0 };
    this.insert(c);
    return c;
  }

  addCircle(x: number, z: number, r: number, height: number, owner: unknown = null): CircleCollider {
    const c: CircleCollider = { kind: 'circle', x, z, r, height, owner, stamp: 0 };
    this.insert(c);
    return c;
  }

  remove(c: Collider): void {
    const i = this.colliders.indexOf(c);
    if (i === -1) return;
    this.colliders.splice(i, 1);
    this.forCells(c, (cell) => {
      const j = cell.indexOf(c);
      if (j !== -1) cell.splice(j, 1);
    });
  }

  private insert(c: Collider): void {
    this.colliders.push(c);
    this.forCells(c, (cell) => cell.push(c));
  }

  private forCells(c: Collider, fn: (cell: Collider[]) => void): void {
    const [x0, z0, x1, z1] = c.kind === 'box'
      ? [c.minX, c.minZ, c.maxX, c.maxZ]
      : [c.x - c.r, c.z - c.r, c.x + c.r, c.z + c.r];
    const cx0 = this.col(x0);
    const cx1 = this.col(x1);
    const cz0 = this.row(z0);
    const cz1 = this.row(z1);
    for (let z = cz0; z <= cz1; z++) {
      for (let x = cx0; x <= cx1; x++) fn(this.cells[z * this.cols + x] as Collider[]);
    }
  }

  private col(x: number): number {
    return Math.min(this.cols - 1, Math.max(0, Math.floor((x - this.minX) / this.cellSize)));
  }

  private row(z: number): number {
    return Math.min(this.rows - 1, Math.max(0, Math.floor((z - this.minZ) / this.cellSize)));
  }

  /** Collects unique colliders whose broadphase cells intersect the given rectangle. */
  private gather(x0: number, z0: number, x1: number, z1: number): Collider[] {
    const out = this.scratch;
    out.length = 0;
    const stamp = ++this.stampCounter;
    const cx0 = this.col(x0);
    const cx1 = this.col(x1);
    const cz0 = this.row(z0);
    const cz1 = this.row(z1);
    for (let z = cz0; z <= cz1; z++) {
      for (let x = cx0; x <= cx1; x++) {
        const cell = this.cells[z * this.cols + x] as Collider[];
        for (let i = 0; i < cell.length; i++) {
          const c = cell[i] as Collider;
          if (c.stamp === stamp) continue;
          c.stamp = stamp;
          out.push(c);
        }
      }
    }
    return out;
  }

  /**
   * Pushes a circle out of all overlapping obstacles. Mutates `p` and returns the
   * last collider that was touched (or null), which callers use to detect what
   * blocked them (e.g. zombies attacking barricades).
   */
  resolveCircle(p: MutablePoint, r: number, iterations = 2): Collider | null {
    let touched: Collider | null = null;
    for (let it = 0; it < iterations; it++) {
      const list = this.gather(p.x - r, p.z - r, p.x + r, p.z + r);
      let moved = false;
      for (let i = 0; i < list.length; i++) {
        const c = list[i] as Collider;
        if (c.kind === 'box') {
          const qx = p.x < c.minX ? c.minX : p.x > c.maxX ? c.maxX : p.x;
          const qz = p.z < c.minZ ? c.minZ : p.z > c.maxZ ? c.maxZ : p.z;
          let dx = p.x - qx;
          let dz = p.z - qz;
          const d2 = dx * dx + dz * dz;
          if (d2 >= r * r) continue;
          if (d2 > 1e-10) {
            const d = Math.sqrt(d2);
            const push = r - d;
            p.x += (dx / d) * push;
            p.z += (dz / d) * push;
          } else {
            // Centre inside the box: exit along the axis of least penetration.
            const left = p.x - c.minX;
            const right = c.maxX - p.x;
            const down = p.z - c.minZ;
            const up = c.maxZ - p.z;
            const m = Math.min(left, right, down, up);
            dx = 0;
            dz = 0;
            if (m === left) p.x = c.minX - r;
            else if (m === right) p.x = c.maxX + r;
            else if (m === down) p.z = c.minZ - r;
            else p.z = c.maxZ + r;
          }
          touched = c;
          moved = true;
        } else {
          const dx = p.x - c.x;
          const dz = p.z - c.z;
          const rr = r + c.r;
          const d2 = dx * dx + dz * dz;
          if (d2 >= rr * rr) continue;
          const d = Math.sqrt(d2) || 1e-5;
          const push = rr - d;
          p.x += (dx / d) * push;
          p.z += (dz / d) * push;
          touched = c;
          moved = true;
        }
      }
      if (!moved) break;
    }
    return touched;
  }

  /** True if a circle at (x, z) overlaps any obstacle. */
  overlapsCircle(x: number, z: number, r: number): boolean {
    const list = this.gather(x - r, z - r, x + r, z + r);
    for (let i = 0; i < list.length; i++) {
      const c = list[i] as Collider;
      if (c.kind === 'box') {
        const qx = Math.max(c.minX, Math.min(x, c.maxX));
        const qz = Math.max(c.minZ, Math.min(z, c.maxZ));
        const dx = x - qx;
        const dz = z - qz;
        if (dx * dx + dz * dz < r * r) return true;
      } else {
        const dx = x - c.x;
        const dz = z - c.z;
        if (dx * dx + dz * dz < (r + c.r) * (r + c.r)) return true;
      }
    }
    return false;
  }

  /** True if an axis-aligned rectangle overlaps any obstacle. */
  overlapsRect(minX: number, minZ: number, maxX: number, maxZ: number): boolean {
    const list = this.gather(minX, minZ, maxX, maxZ);
    for (let i = 0; i < list.length; i++) {
      const c = list[i] as Collider;
      if (c.kind === 'box') {
        if (c.minX < maxX && c.maxX > minX && c.minZ < maxZ && c.maxZ > minZ) return true;
      } else {
        const qx = Math.max(minX, Math.min(c.x, maxX));
        const qz = Math.max(minZ, Math.min(c.z, maxZ));
        const dx = c.x - qx;
        const dz = c.z - qz;
        if (dx * dx + dz * dz < c.r * c.r) return true;
      }
    }
    return false;
  }

  /**
   * Casts a ray (normalised direction) against obstacles taller than `minHeight`.
   * Writes the nearest hit into `out`; `out.t` is `maxDist` when nothing is hit.
   */
  raycast(ox: number, oz: number, dx: number, dz: number, maxDist: number, minHeight: number, out: RayHit): RayHit {
    out.t = maxDist;
    out.collider = null;
    const ex = ox + dx * maxDist;
    const ez = oz + dz * maxDist;
    const list = this.gather(Math.min(ox, ex), Math.min(oz, ez), Math.max(ox, ex), Math.max(oz, ez));
    for (let i = 0; i < list.length; i++) {
      const c = list[i] as Collider;
      if (c.height < minHeight) continue;
      const t = c.kind === 'box'
        ? rayAabb(ox, oz, dx, dz, c.minX, c.minZ, c.maxX, c.maxZ)
        : rayCircle(ox, oz, dx, dz, c.x, c.z, c.r);
      if (t >= 0 && t < out.t) {
        out.t = t;
        out.collider = c;
      }
    }
    return out;
  }
}
