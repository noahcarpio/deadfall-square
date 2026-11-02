interface FloatingText {
  el: HTMLDivElement;
  x: number;
  y: number;
  z: number;
  vy: number;
  life: number;
  maxLife: number;
  active: boolean;
}

export type FloatStyle = 'damage' | 'crit' | 'heal' | 'coin' | 'info' | 'player';

/**
 * Pooled DOM floating text (damage numbers, pickups) projected from world space.
 * DOM text stays crisp at any resolution and costs no extra draw calls.
 */
export class DamageNumbers {
  private readonly pool: FloatingText[] = [];
  private cursor = 0;
  enabled = true;

  constructor(container: HTMLElement, size = 48) {
    for (let i = 0; i < size; i++) {
      const el = document.createElement('div');
      el.className = 'float-text';
      el.style.display = 'none';
      container.appendChild(el);
      this.pool.push({ el, x: 0, y: 0, z: 0, vy: 0, life: 0, maxLife: 1, active: false });
    }
  }

  clear(): void {
    for (const f of this.pool) {
      f.active = false;
      f.el.style.display = 'none';
    }
  }

  spawn(text: string, x: number, y: number, z: number, style: FloatStyle = 'damage'): void {
    if (!this.enabled && (style === 'damage' || style === 'crit')) return;
    const f = this.pool[this.cursor] as FloatingText;
    this.cursor = (this.cursor + 1) % this.pool.length;
    f.active = true;
    f.x = x + (Math.random() - 0.5) * 0.5;
    f.y = y;
    f.z = z + (Math.random() - 0.5) * 0.3;
    f.vy = style === 'damage' ? 2.2 : 1.5;
    f.life = f.maxLife = style === 'info' || style === 'coin' ? 1.1 : 0.75;
    f.el.textContent = text;
    f.el.className = `float-text ${style}`;
    f.el.style.display = 'block';
  }

  update(dt: number, width: number, height: number, project: (x: number, y: number, z: number) => { x: number; y: number; visible: boolean }): void {
    for (const f of this.pool) {
      if (!f.active) continue;
      f.life -= dt;
      if (f.life <= 0) {
        f.active = false;
        f.el.style.display = 'none';
        continue;
      }
      f.y += f.vy * dt;
      f.vy *= Math.exp(-3 * dt);
      const sp = project(f.x, f.y, f.z);
      if (!sp.visible) {
        f.el.style.display = 'none';
        continue;
      }
      f.el.style.display = 'block';
      const t = f.life / f.maxLife;
      const pop = t > 0.8 ? 1 + (t - 0.8) * 2.5 : 1;
      f.el.style.opacity = String(Math.min(1, t * 2.5));
      f.el.style.transform = `translate(${(sp.x * width).toFixed(1)}px, ${(sp.y * height).toFixed(1)}px) translate(-50%, -50%) scale(${pop.toFixed(2)})`;
    }
  }
}
