import { expect, test } from '@playwright/test';
import { Bot, SHOTS, openGame, snapshot, watchConsole } from './helpers';

test('menus, gameplay, pause and game over render without console errors', async ({ page }) => {
  const problems = watchConsole(page);
  await openGame(page);
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${SHOTS}/01-menu.png` });

  await page.click('.main-menu >> text=HOW TO PLAY');
  await expect(page.locator('.howto')).toBeVisible();
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${SHOTS}/02-how-to-play.png` });
  await page.click('.howto >> text=BACK');

  await page.click('.main-menu >> text=SETTINGS');
  await expect(page.locator('.settings')).toBeVisible();
  await page.waitForTimeout(400);
  await page.screenshot({ path: `${SHOTS}/03-settings.png` });
  await page.click('.settings >> text=BACK');

  await page.click('.main-menu >> text=HIGH SCORES');
  await expect(page.locator('.highscores')).toBeVisible();
  await page.click('.highscores >> text=BACK');

  await page.click('.main-menu >> text=PLAY');
  await page.evaluate(() => window.__game.setGodMode(true));
  await expect.poll(async () => (await snapshot(page)).state).toBe('playing');
  await expect(page.locator('.hud')).toBeVisible();

  // Fight for a while so the screenshot shows real combat.
  const bot = new Bot(page);
  const end = Date.now() + 12_000;
  while (Date.now() < end) {
    await bot.step(await snapshot(page));
    await page.waitForTimeout(80);
  }
  await page.screenshot({ path: `${SHOTS}/04-gameplay.png` });
  await bot.release();

  await page.keyboard.press('Escape');
  await expect(page.locator('.pause-menu')).toBeVisible();
  expect((await snapshot(page)).state).toBe('paused');
  await page.waitForTimeout(300);
  await page.screenshot({ path: `${SHOTS}/05-pause.png` });
  await page.click('.pause-menu >> text=RESUME');
  expect((await snapshot(page)).state).toBe('playing');

  await page.evaluate(() => window.__game.killPlayer());
  await expect.poll(async () => (await snapshot(page)).state, { timeout: 30_000 }).toBe('gameover');
  await expect(page.locator('.gameover')).toBeVisible();
  await page.waitForTimeout(800);
  await page.screenshot({ path: `${SHOTS}/06-game-over.png` });

  // Name entry saves to the local leaderboard.
  const score = (await snapshot(page)).score;
  if (score > 0) {
    await page.fill('.name-input', 'Playwright');
    await page.click('.gameover >> text=SAVE');
    await expect(page.locator('.gameover table.scores')).toContainText('Playwright');
  }

  expect(problems, problems.join('\n')).toEqual([]);
});
