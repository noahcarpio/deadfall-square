import { isTouchDevice } from '../config/quality';

/**
 * Keyboard + mouse state. Edge-triggered presses are queued until consumed by
 * the fixed-step simulation, so short taps are never lost between frames.
 *
 * While the game is playing the pointer is locked and a virtual cursor is moved
 * by raw mouse deltas scaled by the sensitivity setting; if pointer lock is
 * unavailable (or denied) the real cursor position is used instead.
 */
export class Input {
  readonly keys = new Set<string>();
  private readonly pressed = new Set<string>();
  /** Virtual cursor in CSS pixels relative to the viewport. */
  cursorX = window.innerWidth / 2;
  cursorY = window.innerHeight / 2;
  mouseDown = false;
  rightDown = false;
  private wheel = 0;
  sensitivity = 1;
  /** Set when any mouse/keyboard input happens; used to switch away from touch UI. */
  lastDevice: 'mouse' | 'touch' = isTouchDevice() ? 'touch' : 'mouse';
  private enabled = true;

  constructor(private readonly element: HTMLElement) {
    window.addEventListener('keydown', this.onKeyDown);
    window.addEventListener('keyup', this.onKeyUp);
    window.addEventListener('blur', this.onBlur);
    // Pointer events (filtered to real mice) rather than mouse events: touch
    // screens emit compatibility mouse events after taps, which must not be
    // mistaken for a mouse.
    window.addEventListener('pointermove', this.onMouseMove);
    element.addEventListener('pointerdown', this.onMouseDown);
    window.addEventListener('pointerup', this.onMouseUp);
    element.addEventListener('wheel', this.onWheel, { passive: true });
    element.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  get pointerLocked(): boolean {
    return document.pointerLockElement === this.element;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (!enabled) this.onBlur();
  }

  requestPointerLock(): void {
    if (this.pointerLocked || this.lastDevice === 'touch') return;
    try {
      const result = this.element.requestPointerLock() as unknown;
      // Newer browsers return a promise that rejects if the request is denied.
      if (result instanceof Promise) result.catch(() => undefined);
    } catch {
      // Pointer lock unsupported: absolute cursor mode is used.
    }
  }

  exitPointerLock(): void {
    if (this.pointerLocked) document.exitPointerLock();
  }

  isDown(code: string): boolean {
    return this.keys.has(code);
  }

  /** Returns true once per physical press of `code`. */
  consume(code: string): boolean {
    if (!this.pressed.has(code)) return false;
    this.pressed.delete(code);
    return true;
  }

  consumeWheel(): number {
    const w = this.wheel;
    this.wheel = 0;
    return w;
  }

  /** Discards queued presses (e.g. when returning from a menu). */
  flush(): void {
    this.pressed.clear();
    this.wheel = 0;
  }

  /** Injects a synthetic key press (used by on-screen buttons and tests). */
  press(code: string): void {
    this.pressed.add(code);
  }

  private onKeyDown = (e: KeyboardEvent): void => {
    this.lastDevice = 'mouse';
    if (!this.enabled) return;
    if (['Space', 'ArrowUp', 'ArrowDown', 'Tab'].includes(e.code)) e.preventDefault();
    if (!e.repeat) this.pressed.add(e.code);
    this.keys.add(e.code);
  };

  private onKeyUp = (e: KeyboardEvent): void => {
    this.keys.delete(e.code);
  };

  private onBlur = (): void => {
    this.keys.clear();
    this.mouseDown = false;
    this.rightDown = false;
  };

  private onMouseMove = (e: PointerEvent): void => {
    if (e.pointerType !== 'mouse') return;
    if (e.movementX !== 0 || e.movementY !== 0) this.lastDevice = 'mouse';
    if (e.buttons !== (this.mouseDown ? 1 : 0) + (this.rightDown ? 2 : 0)) this.syncButtons(e.buttons);
    if (this.pointerLocked) {
      this.cursorX = Math.min(window.innerWidth, Math.max(0, this.cursorX + e.movementX * this.sensitivity));
      this.cursorY = Math.min(window.innerHeight, Math.max(0, this.cursorY + e.movementY * this.sensitivity));
    } else {
      this.cursorX = e.clientX;
      this.cursorY = e.clientY;
    }
  };

  private onMouseDown = (e: PointerEvent): void => {
    if (e.pointerType !== 'mouse') return;
    this.lastDevice = 'mouse';
    if (!this.enabled) return;
    if (!this.pointerLocked) {
      this.cursorX = e.clientX;
      this.cursorY = e.clientY;
    }
    this.syncButtons(e.buttons);
  };

  private onMouseUp = (e: PointerEvent): void => {
    if (e.pointerType !== 'mouse') return;
    this.syncButtons(e.buttons);
  };

  /**
   * Pointer events only report the first press/last release of a chord, so
   * button state is derived from the `buttons` bitmask on every event.
   */
  private syncButtons(buttons: number): void {
    const left = (buttons & 1) !== 0;
    const right = (buttons & 2) !== 0;
    if (right && !this.rightDown && this.enabled) this.pressed.add('MouseRight');
    this.mouseDown = left && this.enabled;
    this.rightDown = right;
  }

  private onWheel = (e: WheelEvent): void => {
    if (!this.enabled) return;
    this.wheel += Math.sign(e.deltaY);
  };
}
