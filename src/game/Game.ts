import * as THREE from 'three';
import { AudioEngine } from '../audio/AudioEngine';
import { PERKS, type PerkId } from '../config/perks';
import { isTouchDevice, QUALITY_PRESETS } from '../config/quality';
import { STRUCTURES, type PlayerUpgradeId, type StructureType } from '../config/shop';
import { isPerkWave } from '../config/waves';
import { Loop } from '../core/Loop';
import { clamp, damp } from '../core/math';
import { Settings, type SettingsData } from '../core/Settings';
import { Input } from '../input/Input';
import { TouchControls } from '../input/TouchControls';
import { emptyIntent, type PlayerIntent } from '../player/Player';
import { HighScores } from '../progression/HighScores';
import { purchase, type ShopAction, type ShopContext } from '../progression/Shop';
import { Hud } from '../ui/Hud';
import { GameOverScreen, HighScoresPanel, HowToPlay, MainMenu, PauseMenu, SettingsPanel, type MenuActions } from '../ui/Menus';
import { PerkUI } from '../ui/PerkUI';
import { PlacementUI } from '../ui/PlacementUI';
import { ShopUI } from '../ui/ShopUI';
import { ARENA_HALF } from '../world/Arena';
import type { Zombie } from '../zombies/Zombie';
import { CameraRig } from './CameraRig';
import { World } from './World';

export type GameState = 'menu' | 'playing' | 'paused' | 'perk' | 'shop' | 'placing' | 'gameover';

/** Night factor (0 day .. 1 deep night) for a wave: dusk by wave 5, full night from wave 11. */
export function nightForWave(wave: number): number {
  return clamp((wave - 1) / 10, 0, 1) * 0.95 + (wave >= 11 ? 0.05 : 0);
}

const GUN_HEIGHT = 1.2;

/**
 * Top-level orchestrator: renderer, game-state machine, input mapping,
 * camera, UI screens and the main loop.
 */
export class Game {
  readonly renderer: THREE.WebGLRenderer;
  readonly rig: CameraRig;
  readonly world: World;
  readonly audio = new AudioEngine();
  readonly settings = new Settings();
  readonly highScores = new HighScores();
  readonly input: Input;
  readonly touch: TouchControls;
  readonly loop: Loop;
  readonly hud: Hud;
  state: GameState = 'menu';
  /** Disables pointer lock and exposes hooks (set by ?test=1). */
  testMode = false;

  private readonly ui: HTMLElement;
  private readonly mainMenu: MainMenu;
  private readonly pauseMenu: PauseMenu;
  private readonly howTo: HowToPlay;
  private readonly settingsPanel: SettingsPanel;
  private readonly scoresPanel: HighScoresPanel;
  private readonly gameOverScreen: GameOverScreen;
  private readonly shopUI: ShopUI;
  private readonly perkUI: PerkUI;
  private readonly placementUI: PlacementUI;
  /** Which screen a sub-panel (settings/how-to) returns to. */
  private panelReturn: 'menu' | 'pause' = 'menu';

  private intent: PlayerIntent = emptyIntent();
  private readonly aimPoint = new THREE.Vector3();
  private readonly tmpV = new THREE.Vector3();
  private touchMode = isTouchDevice();
  private night = 0.55;
  private deathTimer = 0;
  private hadPointerLock = false;
  private placing: { type: StructureType; rotated: boolean; x: number; z: number; valid: boolean } | null = null;
  private panX = 0;
  private panZ = 0;
  private dragging: { id: number; x: number; y: number; moved: boolean } | null = null;
  private width = 1;
  private height = 1;

  constructor(private readonly container: HTMLElement) {
    const canvas = document.createElement('canvas');
    canvas.className = 'game-canvas';
    container.appendChild(canvas);
    const overlay = document.createElement('div');
    overlay.className = 'overlay';
    container.appendChild(overlay);
    this.ui = document.createElement('div');
    this.ui.className = 'ui';
    container.appendChild(this.ui);

    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: !this.touchMode, powerPreference: 'high-performance' });
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.05;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.world = new World(this.audio, overlay, this.settings.data.quality);
    this.rig = new CameraRig(window.innerWidth / Math.max(1, window.innerHeight));
    this.input = new Input(canvas);
    this.touch = new TouchControls(this.ui, () => this.setTouchMode(true));
    this.hud = new Hud(this.ui, this.world);

    const actions: MenuActions = {
      play: () => this.startRun(),
      resume: () => this.resume(),
      restart: () => this.startRun(),
      quitToMenu: () => this.goToMenu(),
      saveScore: (name) => this.saveScore(name),
      uiSound: (kind) => this.audio.sfx(kind === 'click' ? 'uiClick' : 'uiHover'),
    };
    this.mainMenu = new MainMenu(actions, (p) => this.openPanel(p, 'menu'));
    this.pauseMenu = new PauseMenu(actions, (p) => this.openPanel(p, 'pause'));
    this.howTo = new HowToPlay(actions, () => this.closePanel());
    this.settingsPanel = new SettingsPanel(this.settings, actions, () => this.closePanel());
    this.scoresPanel = new HighScoresPanel(() => this.highScores.list, actions, () => this.closePanel());
    this.gameOverScreen = new GameOverScreen(actions);
    this.shopUI = new ShopUI(() => this.shopContext(), {
      buy: (a) => this.buy(a),
      place: (t) => this.beginPlacement(t),
      startWave: () => this.startNextWave(),
      uiSound: (k) => this.audio.sfx(k === 'click' ? 'uiClick' : k === 'hover' ? 'uiHover' : 'uiDeny'),
    });
    this.perkUI = new PerkUI((id) => this.choosePerk(id), () => this.audio.sfx('uiHover'));
    this.placementUI = new PlacementUI({
      rotate: () => this.rotatePlacement(),
      confirm: () => this.confirmPlacement(),
      cancel: () => this.cancelPlacement(),
    });
    for (const s of [this.mainMenu, this.pauseMenu, this.howTo, this.settingsPanel, this.scoresPanel, this.gameOverScreen]) this.ui.appendChild(s.root);
    this.ui.append(this.shopUI.root, this.perkUI.root, this.placementUI.root);

    this.container.classList.toggle('touch', this.touchMode);
    this.bindEvents(canvas);
    this.wireGameEvents();
    this.applySettings(this.settings.data);
    this.settings.onChange((s) => this.applySettings(s));
    this.loop = new Loop({ update: (dt) => this.update(dt), render: (dt) => this.render(dt) });
    this.resize();
    this.goToMenu();
  }

  start(): void {
    this.loop.start();
  }

  // ------------------------------------------------------------------ setup

  private bindEvents(canvas: HTMLCanvasElement): void {
    window.addEventListener('resize', () => this.resize());
    const unlock = (): void => this.audio.unlock();
    window.addEventListener('pointerdown', unlock);
    window.addEventListener('keydown', unlock);
    window.addEventListener('keydown', (e) => this.onKey(e));
    document.addEventListener('pointerlockchange', () => {
      if (this.input.pointerLocked) {
        this.hadPointerLock = true;
      } else if (this.hadPointerLock && this.state === 'playing') {
        this.hadPointerLock = false;
        this.pause();
      }
    });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.state === 'playing') this.pause();
    });
    canvas.addEventListener('mousedown', (e) => {
      if (this.state === 'playing' && !this.testMode) this.input.requestPointerLock();
      if (this.state === 'placing' && !this.touchMode) {
        if (e.button === 0) this.confirmPlacement();
        else if (e.button === 2) this.rotatePlacement();
      }
    });
    // Touch panning / positioning during placement.
    canvas.addEventListener('pointerdown', (e) => {
      if (this.state !== 'placing' || e.pointerType === 'mouse') return;
      this.setTouchMode(true);
      this.dragging = { id: e.pointerId, x: e.clientX, y: e.clientY, moved: false };
    });
    canvas.addEventListener('pointermove', (e) => {
      const d = this.dragging;
      if (!d || d.id !== e.pointerId) return;
      const dx = e.clientX - d.x;
      const dy = e.clientY - d.y;
      if (Math.hypot(dx, dy) > 8) d.moved = true;
      if (d.moved) {
        const scale = 40 / this.height;
        this.panX = clamp(this.panX - dx * scale, -ARENA_HALF, ARENA_HALF);
        this.panZ = clamp(this.panZ - dy * scale, -ARENA_HALF, ARENA_HALF);
        d.x = e.clientX;
        d.y = e.clientY;
      }
    });
    canvas.addEventListener('pointerup', (e) => {
      const d = this.dragging;
      if (!d || d.id !== e.pointerId) return;
      this.dragging = null;
      if (!d.moved && this.placing) this.updateGhost(e.clientX, e.clientY);
    });
  }

  /** HUD banners, toasts and stingers driven by gameplay events. */
  private wireGameEvents(): void {
    const ev = this.world.events;
    ev.on('waveStarted', ({ wave, boss }) => {
      this.hud.announceWave(wave, boss);
      this.audio.sfx('waveStart');
    });
    ev.on('waveCleared', ({ wave, bonus }) => {
      this.hud.announceCleared(wave, bonus);
      this.audio.sfx('waveClear');
    });
    ev.on('bossSpawned', ({ zombie }) => {
      this.hud.toast('The Abomination has arrived!', 'boss');
      this.audio.sfx('bossRoar', { x: zombie.x, z: zombie.z, volume: 0.9 });
    });
    ev.on('notify', ({ text, tone }) => this.hud.toast(text, tone));
  }

  private setTouchMode(on: boolean): void {
    if (this.touchMode === on) return;
    this.touchMode = on;
    this.container.classList.toggle('touch', on);
    this.syncOverlayVisibility();
    this.resize();
  }

  private applySettings(s: SettingsData): void {
    this.audio.setVolumes(s.masterVolume, s.musicVolume, s.sfxVolume);
    this.input.sensitivity = s.sensitivity;
    this.hud.setFpsVisible(s.showFps);
    this.world.fx.shakeScale = s.screenShake ? 1 : 0;
    this.world.fx.numbers.enabled = s.damageNumbers;
    this.world.applyQuality(s.quality);
    this.resize();
  }

  private resize(): void {
    this.width = Math.max(1, window.innerWidth);
    this.height = Math.max(1, window.innerHeight);
    const q = QUALITY_PRESETS[this.settings.data.quality];
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, q.pixelRatioCap));
    this.renderer.setSize(this.width, this.height, false);
    this.rig.resize(this.width / this.height);
    const small = Math.min(this.width, this.height) < 600;
    this.hud.minimap.resize(this.touchMode || small ? 110 : 170);
  }

  // ------------------------------------------------------------ state flow

  private hideAllScreens(): void {
    for (const s of [this.mainMenu, this.pauseMenu, this.howTo, this.settingsPanel, this.scoresPanel, this.gameOverScreen]) s.hide();
    this.shopUI.hide();
    this.perkUI.hide();
    this.placementUI.hide();
  }

  private setState(state: GameState): void {
    this.state = state;
    this.input.setEnabled(state === 'playing' || state === 'placing');
    this.input.flush();
    this.syncOverlayVisibility();
    if (state !== 'playing') {
      this.input.exitPointerLock();
      this.audio.setFlame(false);
    }
    this.audio.setPaused(state === 'paused');
  }

  private syncOverlayVisibility(): void {
    const inGame = this.state !== 'menu';
    this.hud.setVisible(inGame && this.state !== 'gameover');
    this.touch.setVisible(this.touchMode && this.state === 'playing');
    this.hud.setCrosshairVisible(!this.touchMode && (this.state === 'playing' || this.state === 'placing'));
    this.container.classList.toggle('in-game', this.state === 'playing' || this.state === 'placing');
  }

  goToMenu(): void {
    this.hideAllScreens();
    this.world.reset();
    this.world.targetIsPlayer = false;
    this.world.playerModel.root.visible = false;
    this.hud.clearTransient();
    this.night = 0.55;
    this.mainMenu.show();
    this.setState('menu');
    this.audio.setMusicMood('menu');
  }

  startRun(seed?: number): void {
    this.hideAllScreens();
    this.world.reset(seed);
    this.world.playerModel.root.visible = true;
    this.rig.snapTo(this.world.player.x, this.world.player.z);
    this.hud.clearTransient();
    this.deathTimer = 0;
    this.night = nightForWave(1);
    this.panX = this.panZ = 0;
    this.setState('playing');
    this.world.waves.beginCountdown();
    this.audio.setMusicMood('calm');
    if (!this.testMode) this.input.requestPointerLock();
  }

  pause(): void {
    if (this.state !== 'playing') return;
    this.hideAllScreens();
    this.pauseMenu.show();
    this.setState('paused');
  }

  resume(): void {
    if (this.state !== 'paused') return;
    this.hideAllScreens();
    this.setState('playing');
    if (!this.testMode) this.input.requestPointerLock();
  }

  private openPanel(panel: 'howto' | 'settings' | 'scores', from: 'menu' | 'pause'): void {
    this.panelReturn = from;
    this.mainMenu.hide();
    this.pauseMenu.hide();
    if (panel === 'howto') this.howTo.show();
    else if (panel === 'settings') this.settingsPanel.show();
    else this.scoresPanel.show();
  }

  private closePanel(): void {
    this.howTo.hide();
    this.settingsPanel.hide();
    this.scoresPanel.hide();
    if (this.panelReturn === 'pause') this.pauseMenu.show();
    else this.mainMenu.show();
  }

  private openIntermission(): void {
    const wave = this.world.waves.wave;
    this.hud.clearTransient();
    this.world.arsenal.reloadAll();
    if (isPerkWave(wave)) {
      const choices = this.world.perks.rollChoices(this.world.rng, 3);
      if (choices.length > 0) {
        this.setState('perk');
        this.perkUI.open(choices, (id) => this.world.perks.level(id));
        this.audio.sfx('perk');
        return;
      }
    }
    this.openShop();
  }

  choosePerk(id: PerkId): void {
    if (this.state !== 'perk') return;
    this.world.perks.add(id);
    this.world.refreshStats();
    this.audio.sfx('uiBuy');
    this.hud.toast(`Perk acquired: ${PERKS[id].name}`, 'good');
    this.openShop();
  }

  private openShop(): void {
    this.hideAllScreens();
    this.setState('shop');
    this.shopUI.open(this.world.waves.wave);
    this.audio.setMusicMood('calm');
  }

  startNextWave(): void {
    if (this.state !== 'shop') return;
    this.hideAllScreens();
    this.setState('playing');
    this.world.waves.beginCountdown();
    if (!this.testMode) this.input.requestPointerLock();
  }

  private gameOver(): void {
    const w = this.world;
    this.hideAllScreens();
    this.setState('gameover');
    this.audio.sfx('gameOver');
    this.audio.setMusicMood('gameover');
    this.gameOverScreen.open({
      stats: w.stats,
      score: w.economy.score,
      bestCombo: w.economy.bestCombo,
      coinsEarned: w.economy.totalCoinsEarned,
      qualifies: this.highScores.qualifies(w.economy.score),
      lastName: this.highScores.lastName,
      getEntries: () => this.highScores.list,
    });
  }

  private saveScore(name: string): number {
    const w = this.world;
    this.highScores.lastName = name;
    return this.highScores.add(name, w.economy.score, w.stats.wavesCleared, w.stats.totalKills);
  }

  // ------------------------------------------------------------------ shop

  shopContext(): ShopContext {
    const w = this.world;
    return {
      economy: w.economy,
      arsenal: w.arsenal,
      health: w.player.health,
      maxHealth: w.player.stats.maxHealth,
      upgradeTiers: w.upgrades,
      structureCount: (t) => w.structures.count[t],
      structuresMissingHp: w.structures.missingHp,
      applyPlayerUpgrade: (id: PlayerUpgradeId) => w.upgrade(id),
      healFull: () => {
        w.player.health = w.player.stats.maxHealth;
      },
      repairStructures: () => w.structures.repairAll(),
    };
  }

  buy(action: ShopAction): boolean {
    const ok = purchase(this.shopContext(), action);
    if (ok) {
      this.audio.sfx('uiBuy');
      if (action.kind === 'buyWeapon') this.world.events.emit('weaponAcquired', { weapon: action.weapon });
    }
    return ok;
  }

  beginPlacement(type: StructureType): void {
    if (this.state !== 'shop') return;
    const def = STRUCTURES[type];
    if (!this.world.economy.canAfford(def.cost) || this.world.structures.count[type] >= def.maxCount) {
      this.audio.sfx('uiDeny');
      return;
    }
    this.shopUI.hide();
    this.setState('placing');
    const p = this.world.player;
    this.placing = { type, rotated: false, x: p.x + p.aimX * 3, z: p.z + p.aimZ * 3, valid: false };
    this.panX = this.panZ = 0;
    this.placementUI.show(type, def.cost, this.touchMode);
    if (this.touchMode) this.updateGhostAt(this.placing.x, this.placing.z);
  }

  private rotatePlacement(): void {
    if (!this.placing) return;
    this.placing.rotated = !this.placing.rotated;
    this.updateGhostAt(this.placing.x, this.placing.z);
    this.audio.sfx('uiClick');
  }

  private updateGhost(sx: number, sy: number): void {
    if (!this.placing) return;
    const hit = this.rig.screenToGround(sx, sy, this.width, this.height, 0, this.tmpV);
    if (hit) this.updateGhostAt(hit.x, hit.z);
  }

  private updateGhostAt(x: number, z: number): void {
    const pl = this.placing;
    if (!pl) return;
    const s = this.world.structures.snap(pl.type, pl.rotated, x, z);
    pl.x = s.x;
    pl.z = s.z;
    pl.valid = this.world.structures.canPlace(pl.type, pl.rotated, s.x, s.z, this.world);
    this.world.structures.showGhost(pl.type, pl.rotated, s.x, s.z, pl.valid);
    this.placementUI.setValid(pl.valid);
  }

  private confirmPlacement(): void {
    const pl = this.placing;
    if (!pl || this.state !== 'placing') return;
    if (!pl.valid || !this.world.economy.spend(STRUCTURES[pl.type].cost)) {
      this.audio.sfx('uiDeny');
      return;
    }
    this.world.structures.place(pl.type, pl.rotated, pl.x, pl.z, this.world);
    this.endPlacement();
  }

  private cancelPlacement(): void {
    if (this.state !== 'placing') return;
    this.audio.sfx('uiClick');
    this.endPlacement();
  }

  private endPlacement(): void {
    this.placing = null;
    this.world.structures.hideGhost();
    this.placementUI.hide();
    this.panX = this.panZ = 0;
    this.setState('shop');
    this.shopUI.open(this.world.waves.wave);
  }

  // ----------------------------------------------------------------- input

  private onKey(e: KeyboardEvent): void {
    if ((e.target as HTMLElement | null)?.tagName === 'INPUT') return;
    if (e.code === 'Escape' || e.code === 'KeyP') {
      if (this.state === 'playing') this.pause();
      else if (this.state === 'paused' && !this.settingsPanel.visible && !this.howTo.visible) this.resume();
      else if (this.state === 'placing' && e.code === 'Escape') this.cancelPlacement();
      else if (this.settingsPanel.visible || this.howTo.visible || this.scoresPanel.visible) this.closePanel();
    }
    if (this.state === 'placing' && e.code === 'KeyR') this.rotatePlacement();
  }

  private buildIntent(): PlayerIntent {
    const it = this.intent;
    const inp = this.input;
    const w = this.world;
    const p = w.player;
    if (this.touchMode && inp.lastDevice === 'mouse' && !this.testMode) this.setTouchMode(false);

    if (this.touchMode) {
      const t = this.touch;
      it.moveX = t.moveX;
      it.moveZ = t.moveY;
      it.sprint = t.sprinting;
      if (t.aiming) {
        const len = Math.hypot(t.aimX, t.aimY) || 1;
        let ax = t.aimX / len;
        let az = t.aimY / len;
        // Aim assist: snap to the nearest zombie inside a narrow cone.
        const target = this.aimAssistTarget(ax, az);
        if (target) {
          const dx = target.x - p.x;
          const dz = target.z - p.z;
          const d = Math.hypot(dx, dz) || 1;
          ax = dx / d;
          az = dz / d;
          it.aimDistance = d;
        } else {
          it.aimDistance = 12;
        }
        it.aimX = ax;
        it.aimZ = az;
      }
      it.fire = t.firing;
      it.reload = t.consume('reload');
      it.roll = t.consume('roll');
      it.cycle = t.consume('weapon') ? 1 : 0;
      it.slot = 0;
      if (t.consume('pause')) this.pause();
      return it;
    }

    let mx = 0;
    let mz = 0;
    if (inp.isDown('KeyW') || inp.isDown('ArrowUp')) mz -= 1;
    if (inp.isDown('KeyS') || inp.isDown('ArrowDown')) mz += 1;
    if (inp.isDown('KeyA') || inp.isDown('ArrowLeft')) mx -= 1;
    if (inp.isDown('KeyD') || inp.isDown('ArrowRight')) mx += 1;
    it.moveX = mx;
    it.moveZ = mz;
    it.sprint = inp.isDown('ShiftLeft') || inp.isDown('ShiftRight');
    it.fire = inp.mouseDown;
    it.reload = inp.consume('KeyR');
    it.roll = inp.consume('Space');
    it.slot = 0;
    for (let i = 1; i <= 7; i++) if (inp.consume(`Digit${i}`)) it.slot = i;
    const wheel = inp.consumeWheel();
    it.cycle = wheel !== 0 ? Math.sign(wheel) : inp.consume('KeyQ') ? -1 : inp.consume('KeyE') ? 1 : 0;

    const hit = this.rig.screenToGround(inp.cursorX, inp.cursorY, this.width, this.height, GUN_HEIGHT, this.aimPoint);
    if (hit) {
      const dx = hit.x - p.x;
      const dz = hit.z - p.z;
      const d = Math.hypot(dx, dz);
      if (d > 0.3) {
        it.aimX = dx / d;
        it.aimZ = dz / d;
      }
      it.aimDistance = d;
    }
    return it;
  }

  private aimAssistTarget(ax: number, az: number): Zombie | null {
    const p = this.world.player;
    let best: Zombie | null = null;
    let bestScore = Infinity;
    for (const z of this.world.zombies.list) {
      if (!z.alive) continue;
      const dx = z.x - p.x;
      const dz = z.z - p.z;
      const d = Math.hypot(dx, dz);
      if (d > 18 || d < 0.01) continue;
      const cos = (dx * ax + dz * az) / d;
      if (cos < 0.94) continue; // ~20° cone
      const score = d * (2 - cos);
      if (score < bestScore) {
        bestScore = score;
        best = z;
      }
    }
    return best;
  }

  // ------------------------------------------------------------------ loop

  private update(dt: number): void {
    const w = this.world;
    switch (this.state) {
      case 'menu':
        w.updateMenu(dt);
        break;
      case 'playing': {
        w.update(dt, this.buildIntent());
        if (w.waves.readyForIntermission && w.player.alive) this.openIntermission();
        if (!w.player.alive) {
          this.deathTimer += dt;
          if (this.deathTimer > 2.2) this.gameOver();
        }
        break;
      }
      case 'placing': {
        if (!this.touchMode) {
          const inp = this.input;
          const pan = 18 * dt;
          if (inp.isDown('KeyW') || inp.isDown('ArrowUp')) this.panZ -= pan;
          if (inp.isDown('KeyS') || inp.isDown('ArrowDown')) this.panZ += pan;
          if (inp.isDown('KeyA') || inp.isDown('ArrowLeft')) this.panX -= pan;
          if (inp.isDown('KeyD') || inp.isDown('ArrowRight')) this.panX += pan;
          this.panX = clamp(this.panX, -ARENA_HALF, ARENA_HALF);
          this.panZ = clamp(this.panZ, -ARENA_HALF, ARENA_HALF);
          this.updateGhost(inp.cursorX, inp.cursorY);
        }
        w.fx.update(dt);
        break;
      }
      default:
        break;
    }
  }

  private render(frameDt: number): void {
    const w = this.world;
    const p = w.player;
    const active = this.state === 'playing' || this.state === 'placing';

    // Day/night follows the wave number (the upcoming wave during breaks).
    const waveForSky = w.waves.phase === 'active' ? w.waves.wave : w.waves.nextWave;
    const targetNight = this.state === 'menu' ? 0.55 : nightForWave(Math.max(1, waveForSky));
    this.night = damp(this.night, targetNight, 0.6, frameDt);
    w.setNight(this.night);

    w.syncVisuals(frameDt);

    if (this.state === 'menu') {
      this.rig.orbit(w.time);
    } else {
      let lookX = 0;
      let lookZ = 0;
      if (this.state === 'placing') {
        lookX = this.panX;
        lookZ = this.panZ;
      } else if (p.alive) {
        const reach = this.touchMode ? 2.5 : Math.min(4, this.intent.aimDistance * 0.3);
        lookX = p.aimX * reach;
        lookZ = p.aimZ * reach;
      }
      this.rig.follow(p.x, p.z, lookX, lookZ, w.fx.trauma, frameDt);
    }

    // Music mood/intensity.
    if (this.state === 'playing') {
      const boss = w.waves.boss && w.waves.boss.alive;
      this.audio.setMusicMood(w.waves.phase === 'active' ? (boss ? 'boss' : 'combat') : 'calm');
      this.audio.setIntensity(w.zombies.aliveCount / 40);
    }

    if (this.state !== 'menu') this.hud.update(frameDt, this.loop.fps, this.state === 'playing');
    w.fx.numbers.update(frameDt, this.width, this.height, (x, y, z) => this.rig.project(x, y, z));
    if (active && !this.touchMode) {
      const spreadPx = this.spreadToPixels();
      this.hud.moveCrosshair(this.input.cursorX, this.input.cursorY, spreadPx);
    }
    this.renderer.render(w.scene, this.rig.camera);
  }

  /** Converts the current weapon spread at the cursor distance into screen pixels. */
  private spreadToPixels(): number {
    const p = this.world.player;
    const d = Math.max(2, this.intent.aimDistance);
    const spread = this.world.weapons.currentSpread;
    const side = d * Math.tan(spread);
    const a = this.rig.project(p.x + p.aimX * d, GUN_HEIGHT, p.z + p.aimZ * d);
    const ax = a.x;
    const ay = a.y;
    const b = this.rig.project(p.x + p.aimX * d - p.aimZ * side, GUN_HEIGHT, p.z + p.aimZ * d + p.aimX * side);
    return Math.hypot((b.x - ax) * this.width, (b.y - ay) * this.height) + 6;
  }

  // ------------------------------------------------------------ test hooks

  /** Starts a wave immediately (tests). */
  forceStartWave(): void {
    if (this.state === 'shop') this.startNextWave();
  }

  /** Spawns zombies near the player for profiling. */
  debugSpawn(count: number, type: 'walker' | 'runner' | 'brute' | 'spitter' | 'exploder' = 'walker'): number {
    const w = this.world;
    let n = 0;
    for (let i = 0; i < count; i++) {
      const a = (i / count) * Math.PI * 2;
      const r = 8 + (i % 5) * 2.5;
      const x = clamp(w.player.x + Math.cos(a) * r, -ARENA_HALF + 2, ARENA_HALF - 2);
      const z = clamp(w.player.z + Math.sin(a) * r, -ARENA_HALF + 2, ARENA_HALF - 2);
      if (w.collision.overlapsCircle(x, z, 0.5)) continue;
      if (w.zombies.spawn(type, x, z, { hp: 1, damage: 1, speed: 1 }, () => w.rng.next())) n++;
    }
    return n;
  }
}
