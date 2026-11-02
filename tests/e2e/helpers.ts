import type { Page } from '@playwright/test';
import type { GameSnapshot, TestApi } from '../../src/debug/TestHook';

declare global {
  interface Window {
    __game: TestApi;
  }
}

export type Snapshot = GameSnapshot;

export const SHOTS = 'tests/e2e/__screenshots__';

/** Collects console errors, warnings and uncaught exceptions for a page. */
export function watchConsole(page: Page): string[] {
  const problems: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error' || m.type() === 'warning') problems.push(`${m.type()}: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  return problems;
}

export async function openGame(page: Page): Promise<void> {
  await page.goto('/?test=1');
  await page.waitForFunction(() => window.__game !== undefined);
  await page.locator('.main-menu').waitFor({ state: 'visible' });
}

export function snapshot(page: Page): Promise<Snapshot> {
  return page.evaluate(() => window.__game.snapshot());
}

/**
 * A simple player bot that drives the game through real mouse/keyboard input:
 * aims at the nearest zombie, holds the trigger, backs away from close threats
 * and drifts back to the plaza when idle.
 */
export class Bot {
  private readonly held = new Set<string>();

  constructor(private readonly page: Page) {}

  private async key(k: string, on: boolean): Promise<void> {
    if (on && !this.held.has(k)) {
      this.held.add(k);
      await this.page.keyboard.down(k);
    } else if (!on && this.held.has(k)) {
      this.held.delete(k);
      await this.page.keyboard.up(k);
    }
  }

  async release(): Promise<void> {
    await this.page.mouse.up();
    for (const k of [...this.held]) await this.key(k, false);
  }

  async step(s: Snapshot): Promise<void> {
    const p = s.player;
    let best: Snapshot['zombies'][number] | null = null;
    let bd = Infinity;
    for (const z of s.zombies) {
      const d = Math.hypot(z.x - p.x, z.z - p.z);
      if (d < bd) {
        bd = d;
        best = z;
      }
    }
    if (best) {
      // Aim at a point toward the target that is guaranteed to be on screen.
      const k = Math.min(bd, 8) / Math.max(bd, 0.001);
      const tx = p.x + (best.x - p.x) * k;
      const tz = p.z + (best.z - p.z) * k;
      const scr = await this.page.evaluate(([x, z]) => window.__game.toScreen(x, 1.2, z), [tx, tz] as const);
      await this.page.mouse.move(scr.x, scr.y);
      await this.page.mouse.down();
      const dx = best.x - p.x;
      const dz = best.z - p.z;
      const away = bd < 6;
      await this.key('a', away && dx > 0.5);
      await this.key('d', away && dx < -0.5);
      await this.key('w', away && dz > 0.5);
      await this.key('s', away && dz < -0.5);
    } else {
      await this.page.mouse.up();
      await this.key('a', p.x > 3);
      await this.key('d', p.x < -3);
      await this.key('w', p.z > 7);
      await this.key('s', p.z < 3);
    }
  }
}
