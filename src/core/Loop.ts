export const FIXED_DT = 1 / 60;

export interface LoopCallbacks {
  /** Fixed-timestep simulation update (seconds). */
  update(dt: number): void;
  /** Called once per animation frame after simulation; `frameDt` is real elapsed seconds. */
  render(frameDt: number): void;
}

/**
 * Fixed-timestep game loop driven by requestAnimationFrame. The simulation runs
 * at 60 Hz regardless of display refresh rate; `timeScale` lets tests run the
 * game faster than real time.
 */
export class Loop {
  timeScale = 1;
  private accumulator = 0;
  private last = 0;
  private running = false;
  private rafId = 0;
  /** Smoothed frames per second, for the FPS counter. */
  fps = 60;
  /** Milliseconds spent in update() during the last frame. */
  lastUpdateMs = 0;
  /** Simulation steps run during the last frame. */
  lastSteps = 0;
  /** Milliseconds spent in render() during the last frame. */
  lastRenderMs = 0;

  constructor(private readonly callbacks: LoopCallbacks) {}

  start(): void {
    if (this.running) return;
    this.running = true;
    this.last = performance.now();
    this.rafId = requestAnimationFrame(this.frame);
  }

  stop(): void {
    this.running = false;
    cancelAnimationFrame(this.rafId);
  }

  private frame = (now: number): void => {
    if (!this.running) return;
    this.rafId = requestAnimationFrame(this.frame);
    const frameDt = Math.min(0.1, Math.max(0, (now - this.last) / 1000));
    this.last = now;
    if (frameDt > 0) this.fps += (1 / frameDt - this.fps) * 0.05;

    this.accumulator += frameDt * this.timeScale;
    const maxSteps = Math.max(4, Math.ceil(6 * this.timeScale));
    let steps = 0;
    const t0 = performance.now();
    while (this.accumulator >= FIXED_DT && steps < maxSteps) {
      this.callbacks.update(FIXED_DT);
      this.accumulator -= FIXED_DT;
      steps++;
    }
    if (steps === maxSteps) this.accumulator = 0; // drop time instead of spiralling
    const t1 = performance.now();
    this.callbacks.render(frameDt);
    const t2 = performance.now();
    this.lastUpdateMs = t1 - t0;
    this.lastSteps = steps;
    this.lastRenderMs = t2 - t1;
  };
}
