import { expect, test } from '@playwright/test';
import { SHOTS, openGame, watchConsole } from './helpers';

/**
 * Stress test with 140+ zombies on screen. Headless Chromium renders with
 * SwiftShader (CPU), so GPU frame time is not meaningful here; instead this
 * checks the CPU budget (simulation step + render submission) and draw calls,
 * which are what instancing, pooling and spatial hashing optimise.
 */
test('holds the CPU frame budget with 140+ zombies', async ({ page }) => {
  const problems = watchConsole(page);
  await openGame(page);
  await page.evaluate(() => {
    const g = window.__game;
    g.startRun(5);
    g.setGodMode(true);
    g.spawn(80, 'walker');
    g.spawn(40, 'runner');
    g.spawn(25, 'spitter');
    g.spawn(15, 'brute');
  });
  await page.waitForTimeout(2500);

  const result = await page.evaluate(async () => {
    const g = window.__game;
    const steps: number[] = [];
    const submits: number[] = [];
    const draws: number[] = [];
    const alive: number[] = [];
    for (let i = 0; i < 120; i++) {
      await new Promise((r) => requestAnimationFrame(r));
      const s = g.snapshot();
      if (s.steps > 0) steps.push(s.updateMs / s.steps);
      submits.push(s.renderMs);
      draws.push(s.drawCalls);
      alive.push(s.alive);
    }
    const avg = (a: number[]): number => a.reduce((x, y) => x + y, 0) / a.length;
    const p95 = (a: number[]): number => [...a].sort((x, y) => x - y)[Math.floor(a.length * 0.95)] as number;
    return { stepAvg: avg(steps), stepP95: p95(steps), submitAvg: avg(submits), drawCalls: Math.max(...draws), minAlive: Math.min(...alive) };
  });
  await page.screenshot({ path: `${SHOTS}/09-horde-140.png` });
  test.info().annotations.push({ type: 'perf', description: JSON.stringify(result) });
  console.log('perf', JSON.stringify(result));

  expect(result.minAlive).toBeGreaterThanOrEqual(100);
  // A 60 fps frame is 16.7 ms. Simulation must stay a small fraction of it.
  expect(result.stepAvg).toBeLessThan(3);
  expect(result.stepP95).toBeLessThan(6);
  // Instanced rendering keeps draw calls flat regardless of zombie count.
  expect(result.drawCalls).toBeLessThan(80);
  expect(problems, problems.join('\n')).toEqual([]);
});
