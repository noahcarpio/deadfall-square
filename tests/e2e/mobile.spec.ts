import { expect, test, type Page } from '@playwright/test';
import { SHOTS, openGame, snapshot, watchConsole } from './helpers';

/** Dispatches a touch pointer gesture onto an element (drag from a to b and hold). */
async function touchDrag(page: Page, selector: string, id: number, from: [number, number], to: [number, number]): Promise<void> {
  await page.evaluate(({ selector, id, from, to }) => {
    const el = document.querySelector(selector) as HTMLElement;
    const ev = (type: string, x: number, y: number): PointerEvent =>
      new PointerEvent(type, { pointerId: id, pointerType: 'touch', clientX: x, clientY: y, bubbles: true, cancelable: true, isPrimary: id === 1 });
    el.dispatchEvent(ev('pointerdown', from[0], from[1]));
    el.dispatchEvent(ev('pointermove', to[0], to[1]));
  }, { selector, id, from, to });
}

async function touchEnd(page: Page, selector: string, id: number): Promise<void> {
  await page.evaluate(({ selector, id }) => {
    const el = document.querySelector(selector) as HTMLElement;
    el.dispatchEvent(new PointerEvent('pointerup', { pointerId: id, pointerType: 'touch', bubbles: true }));
  }, { selector, id });
}

test('touch twin-stick controls move, aim and shoot', async ({ page }) => {
  const problems = watchConsole(page);
  await openGame(page);
  await page.screenshot({ path: `${SHOTS}/10-mobile-menu.png` });
  await page.tap('.main-menu >> text=PLAY');
  await page.evaluate(() => window.__game.setGodMode(true));
  await expect(page.locator('.touch-controls')).toBeVisible();
  await expect(page.locator('.touch-btn.touch-roll')).toBeVisible();

  const vp = page.viewportSize() ?? { width: 412, height: 915 };
  const start = await snapshot(page);

  // Left stick: push right.
  const ly = vp.height * 0.75;
  await touchDrag(page, '.touch-zone.left', 1, [vp.width * 0.25, ly], [vp.width * 0.25 + 50, ly]);
  await page.waitForTimeout(1500);
  await touchEnd(page, '.touch-zone.left', 1);
  const moved = await snapshot(page);
  expect(moved.player.x).toBeGreaterThan(start.player.x + 1.5);

  // Right stick: aim up (north) and fire.
  const before = await snapshot(page);
  await touchDrag(page, '.touch-zone.right', 2, [vp.width * 0.75, ly], [vp.width * 0.75, ly - 50]);
  await page.waitForTimeout(1200);
  const firing = await snapshot(page);
  await page.screenshot({ path: `${SHOTS}/11-mobile-gameplay.png` });
  await touchEnd(page, '.touch-zone.right', 2);
  expect(firing.player.aimZ).toBeLessThan(-0.5);
  expect(firing.mag).toBeLessThan(before.mag);

  // Pause button opens the pause menu.
  await page.tap('.touch-pause');
  await expect(page.locator('.pause-menu')).toBeVisible();
  expect(problems, problems.join('\n')).toEqual([]);
});
