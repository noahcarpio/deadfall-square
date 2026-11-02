import { ARENA_HALF } from '../world/Arena';
import type { World } from '../game/World';

const VIEW_HALF = ARENA_HALF + 6;

/** Canvas minimap: pre-rendered obstacles plus live player/zombie/pickup markers. */
export class Minimap {
  readonly canvas: HTMLCanvasElement;
  private readonly ctx: CanvasRenderingContext2D;
  private readonly staticLayer: HTMLCanvasElement;
  private size = 0;
  private timer = 0;

  constructor(private readonly world: World) {
    this.canvas = document.createElement('canvas');
    this.canvas.className = 'minimap';
    const ctx = this.canvas.getContext('2d');
    if (!ctx) throw new Error('2D canvas unavailable');
    this.ctx = ctx;
    this.staticLayer = document.createElement('canvas');
  }

  private toPx(v: number): number {
    return ((v + VIEW_HALF) / (VIEW_HALF * 2)) * this.size;
  }

  /** (Re)draws static obstacles; call after structures change or on resize. */
  private renderStatic(): void {
    const s = this.size;
    this.staticLayer.width = this.staticLayer.height = s;
    const g = this.staticLayer.getContext('2d');
    if (!g) return;
    g.clearRect(0, 0, s, s);
    g.fillStyle = 'rgba(20,24,22,0.82)';
    g.fillRect(0, 0, s, s);
    g.fillStyle = 'rgba(70,70,64,0.5)';
    const a0 = this.toPx(-ARENA_HALF);
    const a1 = this.toPx(ARENA_HALF);
    g.fillRect(a0, a0, a1 - a0, a1 - a0);
    for (const c of this.world.collision.colliders) {
      if (this.world.structures.isStructureCollider(c)) continue;
      g.fillStyle = c.height > 3 ? 'rgba(150,145,135,0.85)' : 'rgba(115,110,100,0.8)';
      if (c.kind === 'box') {
        g.fillRect(this.toPx(c.minX), this.toPx(c.minZ), this.toPx(c.maxX) - this.toPx(c.minX), this.toPx(c.maxZ) - this.toPx(c.minZ));
      } else {
        g.beginPath();
        g.arc(this.toPx(c.x), this.toPx(c.z), (c.r / (VIEW_HALF * 2)) * s, 0, Math.PI * 2);
        g.fill();
      }
    }
    g.fillStyle = 'rgba(255,80,60,0.6)';
    for (const sp of this.world.arena.spawnPoints) {
      g.beginPath();
      g.arc(this.toPx(sp.x), this.toPx(sp.z), 2.5, 0, Math.PI * 2);
      g.fill();
    }
  }

  resize(cssSize: number): void {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const size = Math.round(cssSize * dpr);
    if (size === this.size) return;
    this.size = size;
    this.canvas.width = this.canvas.height = size;
    this.canvas.style.width = this.canvas.style.height = `${cssSize}px`;
    this.renderStatic();
  }

  update(dt: number): void {
    this.timer -= dt;
    if (this.timer > 0 || this.size === 0) return;
    this.timer = 1 / 20;
    const g = this.ctx;
    const s = this.size;
    const w = this.world;
    g.clearRect(0, 0, s, s);
    g.drawImage(this.staticLayer, 0, 0);
    const unit = s / (VIEW_HALF * 2);

    g.fillStyle = '#5aa8ff';
    for (const st of w.structures.list) {
      g.fillRect(this.toPx(st.x - st.hw), this.toPx(st.z - st.hd), st.hw * 2 * unit, st.hd * 2 * unit);
    }
    for (const p of w.pickups.list) {
      g.fillStyle = p.kind === 'health' ? '#ff5a6a' : p.kind === 'weapon' ? '#c070ff' : p.kind === 'armor' ? '#4aa8ff' : '#ffd23a';
      g.fillRect(this.toPx(p.x) - 2, this.toPx(p.z) - 2, 4, 4);
    }
    const r = Math.max(1.5, unit * 0.55);
    for (const z of w.zombies.list) {
      if (!z.alive) continue;
      if (z.type === 'boss') {
        g.fillStyle = '#d050ff';
        g.beginPath();
        g.arc(this.toPx(z.x), this.toPx(z.z), r * 3, 0, Math.PI * 2);
        g.fill();
        continue;
      }
      g.fillStyle = z.type === 'exploder' ? '#ff9a2a' : z.type === 'spitter' ? '#9aff4a' : z.type === 'brute' ? '#ff3a2a' : '#e04a3a';
      g.fillRect(this.toPx(z.x) - r, this.toPx(z.z) - r, r * 2, r * 2);
    }
    // Player arrow.
    const p = w.player;
    const px = this.toPx(p.x);
    const pz = this.toPx(p.z);
    const a = Math.atan2(p.aimX, p.aimZ);
    const len = unit * 2.4;
    g.save();
    g.translate(px, pz);
    g.rotate(-a + Math.PI);
    g.fillStyle = '#7dffb0';
    g.beginPath();
    g.moveTo(0, -len);
    g.lineTo(len * 0.65, len * 0.7);
    g.lineTo(0, len * 0.35);
    g.lineTo(-len * 0.65, len * 0.7);
    g.closePath();
    g.fill();
    g.restore();
  }
}
