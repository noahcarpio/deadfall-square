import { expect, test } from '@playwright/test';
import { Bot, SHOTS, openGame, snapshot, watchConsole } from './helpers';

/**
 * Plays through the first three waves using only simulated mouse/keyboard
 * input (aiming, shooting, moving) and real UI clicks for the perk and shop
 * screens. God mode keeps the run deterministic enough for CI; time runs 3x.
 */
test('plays three waves: waves advance, zombies spawn and die, shop opens, score rises', async ({ page }) => {
  const problems = watchConsole(page);
  await openGame(page);
  await page.click('.main-menu >> text=PLAY');
  await page.evaluate(() => {
    window.__game.setGodMode(true);
    window.__game.setTimeScale(3);
  });

  const bot = new Bot(page);
  const scores: number[] = [];
  const shopsOpened = new Set<number>();
  let maxAlive = 0;
  let perkSeen = false;
  let lastProgress = Date.now();
  let lastKey = '';

  while (shopsOpened.size < 3) {
    const s = await snapshot(page);
    const key = `${s.wave}:${s.remaining}:${s.state}`;
    if (key !== lastKey) {
      lastKey = key;
      lastProgress = Date.now();
    }
    expect(Date.now() - lastProgress, `no progress for 45s at ${key}`).toBeLessThan(45_000);
    maxAlive = Math.max(maxAlive, s.alive);
    scores.push(s.score);

    if (s.state === 'playing') {
      await bot.step(s);
    } else if (s.state === 'perk') {
      await bot.release();
      perkSeen = true;
      await page.waitForTimeout(500);
      await page.screenshot({ path: `${SHOTS}/08-perk-choice.png` });
      await page.click('.perk-card >> nth=0');
    } else if (s.state === 'shop') {
      await bot.release();
      expect(s.remaining).toBe(0);
      if (!shopsOpened.has(s.wave)) {
        shopsOpened.add(s.wave);
        await page.waitForTimeout(500);
        if (s.wave === 1) await page.screenshot({ path: `${SHOTS}/07-shop.png` });
      }
      if (shopsOpened.size < 3) await page.click('.start-wave');
    } else {
      throw new Error(`unexpected state ${s.state}`);
    }
    await page.waitForTimeout(70);
  }

  const final = await snapshot(page);
  expect(final.state).toBe('shop');
  expect(final.wave).toBe(3);
  expect([...shopsOpened]).toEqual([1, 2, 3]);
  expect(perkSeen).toBe(true);
  expect(maxAlive).toBeGreaterThan(0);
  // Wave 1 alone has 10+ zombies; three waves comfortably exceed 40 kills.
  expect(final.totalKills).toBeGreaterThanOrEqual(40);
  expect(final.coins).toBeGreaterThan(0);
  // Score never decreases and ends well above zero.
  for (let i = 1; i < scores.length; i++) expect(scores[i]).toBeGreaterThanOrEqual(scores[i - 1] as number);
  expect(final.score).toBeGreaterThan(500);

  expect(problems, problems.join('\n')).toEqual([]);
});
