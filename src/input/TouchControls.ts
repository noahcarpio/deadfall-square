import { clamp } from '../core/math';

interface Stick {
  pointerId: number;
  originX: number;
  originY: number;
  x: number;
  y: number;
  active: boolean;
  base: HTMLElement;
  knob: HTMLElement;
}

export type TouchButton = 'reload' | 'roll' | 'weapon' | 'pause' | 'interact';

const STICK_RADIUS = 56;

/**
 * Twin-stick touch controls: a floating movement joystick on the left half of
 * the screen and an aim/fire joystick on the right half, plus action buttons.
 */
export class TouchControls {
  readonly root: HTMLElement;
  /** Movement vector in screen space, length 0..1. */
  moveX = 0;
  moveY = 0;
  /** Aim vector in screen space, length 0..1. */
  aimX = 0;
  aimY = 0;
  private readonly move: Stick;
  private readonly aim: Stick;
  private readonly queued = new Set<TouchButton>();
  private visible = false;

  constructor(parent: HTMLElement, private readonly onActivity: () => void) {
    this.root = document.createElement('div');
    this.root.className = 'touch-controls hidden';
    parent.appendChild(this.root);

    const leftZone = this.zone('touch-zone left');
    const rightZone = this.zone('touch-zone right');
    this.move = this.makeStick('move');
    this.aim = this.makeStick('aim');
    this.bindZone(leftZone, this.move);
    this.bindZone(rightZone, this.aim);

    const bar = document.createElement('div');
    bar.className = 'touch-buttons';
    this.root.appendChild(bar);
    this.button(bar, 'roll', 'ROLL');
    this.button(bar, 'reload', 'RELOAD');
    this.button(bar, 'weapon', 'SWAP');
    const pause = this.button(this.root, 'pause', 'II');
    pause.classList.add('touch-pause');
  }

  /** True while the player is pushing the aim stick far enough to shoot. */
  get firing(): boolean {
    return this.aim.active && Math.hypot(this.aimX, this.aimY) > 0.3;
  }

  get aiming(): boolean {
    return this.aim.active && Math.hypot(this.aimX, this.aimY) > 0.15;
  }

  /** Pushing the movement stick to the rim sprints. */
  get sprinting(): boolean {
    return Math.hypot(this.moveX, this.moveY) > 0.95;
  }

  consume(button: TouchButton): boolean {
    if (!this.queued.has(button)) return false;
    this.queued.delete(button);
    return true;
  }

  setVisible(v: boolean): void {
    if (v === this.visible) return;
    this.visible = v;
    this.root.classList.toggle('hidden', !v);
    if (!v) this.reset();
  }

  reset(): void {
    for (const s of [this.move, this.aim]) this.release(s);
    this.queued.clear();
  }

  private zone(cls: string): HTMLElement {
    const z = document.createElement('div');
    z.className = cls;
    this.root.appendChild(z);
    return z;
  }

  private makeStick(name: string): Stick {
    const base = document.createElement('div');
    base.className = `stick stick-${name}`;
    const knob = document.createElement('div');
    knob.className = 'stick-knob';
    base.appendChild(knob);
    this.root.appendChild(base);
    return { pointerId: -1, originX: 0, originY: 0, x: 0, y: 0, active: false, base, knob };
  }

  private bindZone(zone: HTMLElement, stick: Stick): void {
    zone.addEventListener('pointerdown', (e) => {
      if (e.pointerType === 'mouse') return;
      e.preventDefault();
      this.onActivity();
      if (stick.active) return;
      try {
        zone.setPointerCapture(e.pointerId);
      } catch {
        // Capture can fail for synthetic/cancelled pointers; tracking still works via pointerId.
      }
      stick.active = true;
      stick.pointerId = e.pointerId;
      stick.originX = e.clientX;
      stick.originY = e.clientY;
      stick.base.style.transform = `translate(${e.clientX - STICK_RADIUS}px, ${e.clientY - STICK_RADIUS}px)`;
      stick.base.classList.add('active');
      this.updateStick(stick, e.clientX, e.clientY);
    });
    zone.addEventListener('pointermove', (e) => {
      if (!stick.active || e.pointerId !== stick.pointerId) return;
      e.preventDefault();
      this.updateStick(stick, e.clientX, e.clientY);
    });
    const end = (e: PointerEvent): void => {
      if (e.pointerId !== stick.pointerId) return;
      this.release(stick);
    };
    zone.addEventListener('pointerup', end);
    zone.addEventListener('pointercancel', end);
  }

  private updateStick(stick: Stick, px: number, py: number): void {
    let dx = px - stick.originX;
    let dy = py - stick.originY;
    const len = Math.hypot(dx, dy);
    if (len > STICK_RADIUS) {
      // Drag the origin along so the stick never feels "stuck" at the rim.
      const excess = len - STICK_RADIUS;
      stick.originX += (dx / len) * excess;
      stick.originY += (dy / len) * excess;
      dx = px - stick.originX;
      dy = py - stick.originY;
      stick.base.style.transform = `translate(${stick.originX - STICK_RADIUS}px, ${stick.originY - STICK_RADIUS}px)`;
    }
    stick.x = clamp(dx / STICK_RADIUS, -1, 1);
    stick.y = clamp(dy / STICK_RADIUS, -1, 1);
    stick.knob.style.transform = `translate(${dx}px, ${dy}px)`;
    this.sync();
  }

  private release(stick: Stick): void {
    stick.active = false;
    stick.pointerId = -1;
    stick.x = 0;
    stick.y = 0;
    stick.knob.style.transform = 'translate(0px, 0px)';
    stick.base.classList.remove('active');
    this.sync();
  }

  private sync(): void {
    this.moveX = this.move.x;
    this.moveY = this.move.y;
    this.aimX = this.aim.x;
    this.aimY = this.aim.y;
  }

  private button(parent: HTMLElement, id: TouchButton, label: string): HTMLElement {
    const b = document.createElement('button');
    b.className = `touch-btn touch-${id}`;
    b.textContent = label;
    b.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.onActivity();
      this.queued.add(id);
      b.classList.add('pressed');
    });
    const up = (): void => b.classList.remove('pressed');
    b.addEventListener('pointerup', up);
    b.addEventListener('pointercancel', up);
    parent.appendChild(b);
    return b;
  }

}
