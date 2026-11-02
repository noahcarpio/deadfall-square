import type { Game } from '../game/Game';
import type { PerkId } from '../config/perks';
import type { ShopAction } from '../progression/Shop';

export interface GameSnapshot {
  state: string;
  wave: number;
  wavePhase: string;
  remaining: number;
  alive: number;
  zombies: Array<{ x: number; z: number; type: string; hp: number }>;
  totalKills: number;
  score: number;
  coins: number;
  player: { x: number; z: number; health: number; alive: boolean; aimX: number; aimZ: number };
  weapon: string;
  mag: number;
  reserve: number;
  perkChoicesVisible: boolean;
  fps: number;
  drawCalls: number;
  triangles: number;
  updateMs: number;
  steps: number;
  renderMs: number;
}

/**
 * Test/automation hook, exposed as `window.__game` only when the page is
 * loaded with `?test=1`. Lets Playwright read state, project world positions
 * to screen pixels and speed up time; gameplay input still goes through the
 * real keyboard/mouse handlers.
 */
export function installTestHook(game: Game): void {
  game.testMode = true;
  (window as unknown as { __game: TestApi }).__game = createApi(game);
}

export type TestApi = ReturnType<typeof createApi>;

function createApi(game: Game) {
  return {
    /** Direct access for debugging in the browser console / tests. */
    get world() {
      return game.world;
    },
    snapshot(): GameSnapshot {
      const w = game.world;
      const info = game.renderer.info;
      return {
        state: game.state,
        wave: w.waves.wave,
        wavePhase: w.waves.phase,
        remaining: w.waves.remaining(w),
        alive: w.zombies.aliveCount,
        zombies: w.zombies.list.filter((z) => z.alive).map((z) => ({ x: z.x, z: z.z, type: z.type, hp: z.hp })),
        totalKills: w.stats.totalKills,
        score: w.economy.score,
        coins: w.economy.coins,
        player: { x: w.player.x, z: w.player.z, health: w.player.health, alive: w.player.alive, aimX: w.player.aimX, aimZ: w.player.aimZ },
        weapon: w.arsenal.currentId,
        mag: w.arsenal.current.mag,
        reserve: Number.isFinite(w.arsenal.current.reserve) ? w.arsenal.current.reserve : -1,
        perkChoicesVisible: game.state === 'perk',
        fps: game.loop.fps,
        drawCalls: info.render.calls,
        triangles: info.render.triangles,
        updateMs: game.loop.lastUpdateMs,
        steps: game.loop.lastSteps,
        renderMs: game.loop.lastRenderMs,
      };
    },
    /** World position -> CSS pixel position on screen. */
    toScreen(x: number, y: number, z: number): { x: number; y: number; visible: boolean } {
      const p = game.rig.project(x, y, z);
      return { x: p.x * window.innerWidth, y: p.y * window.innerHeight, visible: p.visible };
    },
    setTimeScale(s: number): void {
      game.loop.timeScale = s;
    },
    setGodMode(on: boolean): void {
      game.world.combat.godMode = on;
    },
    startRun(seed = 1234): void {
      game.startRun(seed);
    },
    choosePerk(index: number): void {
      const cards = document.querySelectorAll<HTMLButtonElement>('.perk-card');
      cards[index]?.click();
    },
    choosePerkId(id: PerkId): void {
      game.choosePerk(id);
    },
    startNextWave(): void {
      game.forceStartWave();
    },
    /** Purchases through the real shop rules (same path as the shop UI buttons). */
    buy(action: ShopAction): boolean {
      return game.buy(action);
    },
    giveCoins(n: number): void {
      game.world.economy.addCoins(n);
    },
    spawn(count: number, type?: 'walker' | 'runner' | 'brute' | 'spitter' | 'exploder'): number {
      return game.debugSpawn(count, type);
    },
    killPlayer(): void {
      const w = game.world;
      w.combat.godMode = false;
      w.player.invulnerable = 0;
      w.combat.damagePlayer(9999, w.player.x + 1, w.player.z, 0, 'test');
    },
  };
}
